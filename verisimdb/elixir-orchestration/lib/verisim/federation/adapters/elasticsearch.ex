# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.Elasticsearch do
  @moduledoc """
  Federation adapter for Elasticsearch (and OpenSearch).

  Translates VeriSimDB modality queries into Elasticsearch Query DSL
  and normalises results into the federation result format. Communicates
  via the Elasticsearch REST API.

  ## Modality Mapping

  | VeriSimDB Modality | Elasticsearch Capability  | Mapping Type          |
  |--------------------|---------------------------|-----------------------|
  | `:document`        | Full-text search          | `text` + `match`      |
  | `:vector`          | kNN / dense_vector        | `dense_vector` + kNN  |
  | `:semantic`        | Nested objects            | `nested` / `object`   |
  | `:temporal`        | Date range queries        | `date` + `range`      |
  | `:spatial`         | Geo queries               | `geo_shape` / `geo_point` |

  Elasticsearch does not natively support graph traversal, tensors, or
  provenance chains, so `:graph`, `:tensor`, and `:provenance` modalities
  are not supported.

  ## Configuration

      %{
        index: "hexads",              # Default index name
        auth: {:basic, "elastic", "password"},
        version: 8                     # ES major version (7 or 8)
      }

  ## OpenSearch Compatibility

  This adapter is compatible with OpenSearch (the AWS-managed fork).
  Set `version: 7` for OpenSearch 1.x/2.x compatibility (uses
  `_doc` type specifier where needed).
  """

  @behaviour VeriSim.Federation.Adapter

  require Logger

  @default_timeout 10_000

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def connect(peer_info) do
    case health_check(peer_info) do
      {:ok, _latency} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def query(peer_info, query_params, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    modalities = Map.get(query_params, :modalities, [])
    limit = Map.get(query_params, :limit, 100)

    start = System.monotonic_time(:millisecond)

    dsl = build_query_dsl(modalities, query_params, limit, peer_info)

    result = execute_search(peer_info, dsl, timeout)

    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, raw_results} ->
        normalised =
          raw_results
          |> translate_results(peer_info)
          |> Enum.map(fn r -> Map.put(r, :response_time_ms, elapsed) end)

        {:ok, normalised}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning(
        "Elasticsearch adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    url = "#{peer_info.endpoint}/_cluster/health"
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(peer_info.adapter_config)

    case Req.get(url, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        status = body["status"]

        if status in ["green", "yellow"] do
          elapsed = System.monotonic_time(:millisecond) - start
          {:ok, elapsed}
        else
          {:error, {:cluster_red, status}}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unhealthy, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  @impl true
  def supported_modalities(_adapter_config) do
    [:document, :vector, :semantic, :temporal, :spatial]
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn hit ->
      # Elasticsearch hits have _source, _id, _score structure
      source = hit["_source"] || hit
      id = hit["_id"] || source["id"] || "unknown"
      score = hit["_score"] || 0.0

      %{
        source_store: peer_info.store_id,
        hexad_id: id,
        score: if(is_number(score), do: score, else: 0.0),
        drifted: false,
        data: source,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — Elasticsearch Query DSL Builder
  # ---------------------------------------------------------------------------

  defp build_query_dsl(modalities, query_params, limit, peer_info) do
    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # kNN search (Elasticsearch 8+) or script_score (ES 7)
        version = get_in(peer_info, [:adapter_config, :version]) || 8

        if version >= 8 do
          build_knn_query(query_params.vector_query, limit)
        else
          build_script_score_vector_query(query_params.vector_query, limit)
        end

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        build_text_query(query_params.text_query, limit)

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        build_spatial_query(query_params.spatial_bounds, limit)

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        build_temporal_query(query_params.temporal_range, limit)

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        build_filter_query(query_params.filters, limit)

      true ->
        # Default: match_all
        %{
          "query" => %{"match_all" => %{}},
          "size" => limit
        }
    end
  end

  # Elasticsearch 8+ native kNN search
  defp build_knn_query(vector, limit) do
    %{
      "knn" => %{
        "field" => "embedding",
        "query_vector" => vector,
        "k" => limit,
        "num_candidates" => limit * 10
      },
      "size" => limit
    }
  end

  # Elasticsearch 7 / OpenSearch script_score fallback for vector search
  defp build_script_score_vector_query(vector, limit) do
    %{
      "query" => %{
        "script_score" => %{
          "query" => %{"match_all" => %{}},
          "script" => %{
            "source" => "cosineSimilarity(params.query_vector, 'embedding') + 1.0",
            "params" => %{"query_vector" => vector}
          }
        }
      },
      "size" => limit
    }
  end

  # Full-text search with multi_match across common text fields
  defp build_text_query(text_query, limit) do
    %{
      "query" => %{
        "multi_match" => %{
          "query" => text_query,
          "fields" => ["title^3", "body^2", "content", "description"],
          "type" => "best_fields",
          "fuzziness" => "AUTO"
        }
      },
      "size" => limit
    }
  end

  # Geo bounding box query (PostGIS equivalent)
  defp build_spatial_query(bounds, limit) do
    %{
      "query" => %{
        "geo_bounding_box" => %{
          "location" => %{
            "top_left" => %{
              "lat" => bounds[:max_lat] || bounds["max_lat"] || 0.0,
              "lon" => bounds[:min_lon] || bounds["min_lon"] || 0.0
            },
            "bottom_right" => %{
              "lat" => bounds[:min_lat] || bounds["min_lat"] || 0.0,
              "lon" => bounds[:max_lon] || bounds["max_lon"] || 0.0
            }
          }
        }
      },
      "size" => limit
    }
  end

  # Date range query
  defp build_temporal_query(range, limit) do
    %{
      "query" => %{
        "range" => %{
          "created_at" => %{
            "gte" => range[:start] || range["start"],
            "lte" => range[:end] || range["end"],
            "format" => "strict_date_optional_time"
          }
        }
      },
      "sort" => [%{"created_at" => %{"order" => "desc"}}],
      "size" => limit
    }
  end

  # Generic filter query for semantic/structured data
  defp build_filter_query(filters, limit) do
    must_clauses =
      Enum.map(filters, fn {field, value} ->
        %{"term" => %{field => value}}
      end)

    %{
      "query" => %{
        "bool" => %{"must" => must_clauses}
      },
      "size" => limit
    }
  end

  defp execute_search(peer_info, dsl, timeout) do
    config = peer_info.adapter_config
    index = Map.get(config, :index, "hexads")
    url = "#{peer_info.endpoint}/#{index}/_search"
    headers = auth_headers(config) ++ [{"Content-Type", "application/json"}]

    case Req.post(url, json: dsl, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        hits = get_in(body, ["hits", "hits"]) || []
        {:ok, hits}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_type = get_in(body, ["error", "type"]) || "unknown"
        error_reason = get_in(body, ["error", "reason"]) || "HTTP #{status}"

        Logger.warning(
          "Elasticsearch adapter: search failed: #{error_type} — #{error_reason}"
        )

        {:error, {:es_error, status, error_type, error_reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp auth_headers(config) do
    case Map.get(config, :auth, :none) do
      {:basic, user, pass} ->
        encoded = Base.encode64("#{user}:#{pass}")
        [{"Authorization", "Basic #{encoded}"}]

      {:bearer, token} ->
        [{"Authorization", "Bearer #{token}"}]

      {:api_key, key} ->
        [{"Authorization", "ApiKey #{key}"}]

      _ ->
        []
    end
  end
end
