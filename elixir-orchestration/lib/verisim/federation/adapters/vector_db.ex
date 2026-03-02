# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.VectorDB do
  @moduledoc """
  Unified federation adapter for dedicated vector databases: Qdrant, Milvus,
  and Weaviate.

  Rather than maintaining three separate adapters for purpose-built vector
  databases, this unified adapter dispatches to backend-specific API formats
  based on the `:backend` configuration. All three backends share the same
  core capability — high-performance vector similarity search — but differ
  in their API shapes, filtering syntax, and secondary features.

  ## Modality Mapping

  | VeriSimDB Modality | Capability                    | Backend Support              |
  |--------------------|-------------------------------|------------------------------|
  | `:vector`          | Native ANN similarity search  | All (Qdrant, Milvus, Weaviate) |
  | `:temporal`        | Timestamp-based filtering     | All (payload/property filter) |
  | `:spatial`         | Geo-distance filtering        | Qdrant (geo payload), Weaviate |
  | `:semantic`        | Metadata/payload filtering    | All (payload/property filter) |

  Dedicated vector databases do not support graph traversal, full-text
  document search, tensor operations, or provenance chains, so `:graph`,
  `:document`, `:tensor`, and `:provenance` modalities are not supported.

  ## Configuration

      # Qdrant
      %{
        host: "qdrant.internal",
        port: 6333,
        collection: "hexads",
        backend: :qdrant,
        auth: {:api_key, "your-api-key"}
      }

      # Milvus
      %{
        host: "milvus.internal",
        port: 19530,
        collection: "hexads",
        backend: :milvus,
        auth: {:bearer, "token"}
      }

      # Weaviate
      %{
        host: "weaviate.internal",
        port: 8080,
        collection: "Hexad",
        backend: :weaviate,
        auth: {:api_key, "your-api-key"}
      }

  ## Backend Dispatch

  Each backend uses a different API format:
  - **Qdrant**: REST API — `POST /collections/{name}/points/search`
  - **Milvus**: REST API (v2) — `POST /v2/vectordb/entities/search`
  - **Weaviate**: GraphQL API — `POST /v1/graphql`
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

    backend = get_backend(peer_info)
    result = dispatch_query(backend, peer_info, modalities, query_params, limit, timeout)

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
        "VectorDB adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    backend = get_backend(peer_info)
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(peer_info.adapter_config)

    url = health_url(backend, peer_info)

    case Req.get(url, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, elapsed}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unhealthy, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  @impl true
  def supported_modalities(adapter_config) do
    backend = Map.get(adapter_config, :backend, :qdrant)

    base = [:vector, :temporal, :semantic]

    # Qdrant and Weaviate support geo filtering
    base
    |> maybe_add(:spatial, backend in [:qdrant, :weaviate])
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    backend = get_backend(peer_info)

    raw_results
    |> List.wrap()
    |> Enum.map(fn row ->
      {id, score, data} = extract_result(backend, row)

      %{
        source_store: peer_info.store_id,
        hexad_id: id,
        score: score,
        drifted: false,
        data: data,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — Backend Dispatch
  # ---------------------------------------------------------------------------

  defp dispatch_query(:qdrant, peer_info, modalities, query_params, limit, timeout) do
    query_qdrant(peer_info, modalities, query_params, limit, timeout)
  end

  defp dispatch_query(:milvus, peer_info, modalities, query_params, limit, timeout) do
    query_milvus(peer_info, modalities, query_params, limit, timeout)
  end

  defp dispatch_query(:weaviate, peer_info, modalities, query_params, limit, timeout) do
    query_weaviate(peer_info, modalities, query_params, limit, timeout)
  end

  defp dispatch_query(backend, _peer_info, _modalities, _query_params, _limit, _timeout) do
    {:error, {:unsupported_backend, backend}}
  end

  # ---------------------------------------------------------------------------
  # Private — Qdrant
  # ---------------------------------------------------------------------------

  defp query_qdrant(peer_info, modalities, query_params, limit, timeout) do
    config = peer_info.adapter_config
    collection = Map.get(config, :collection, "hexads")
    headers = auth_headers(config)

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # Qdrant: POST /collections/{name}/points/search
        url = "#{peer_info.endpoint}/collections/#{collection}/points/search"
        embedding = query_params.vector_query

        body = %{
          "vector" => embedding,
          "limit" => limit,
          "with_payload" => true
        }

        # Add filters for temporal/spatial/semantic modalities
        body = maybe_add_qdrant_filter(body, modalities, query_params)

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: 200, body: resp}} ->
            results = resp["result"] || []
            {:ok, results}

          {:ok, %Req.Response{status: status, body: resp}} ->
            {:error, {:qdrant_error, status, resp["status"] || "unknown"}}

          {:error, reason} ->
            {:error, reason}
        end

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # Qdrant: scroll with filter (no vector)
        url = "#{peer_info.endpoint}/collections/#{collection}/points/scroll"

        body = %{
          "filter" => build_qdrant_filter(query_params),
          "limit" => limit,
          "with_payload" => true
        }

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: 200, body: resp}} ->
            results = resp["result"]["points"] || []
            {:ok, results}

          {:ok, %Req.Response{status: status, body: resp}} ->
            {:error, {:qdrant_error, status, resp}}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        # Default: scroll all points
        url = "#{peer_info.endpoint}/collections/#{collection}/points/scroll"

        body = %{"limit" => limit, "with_payload" => true}

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: 200, body: resp}} ->
            {:ok, resp["result"]["points"] || []}

          {:ok, %Req.Response{status: status, body: resp}} ->
            {:error, {:qdrant_error, status, resp}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp maybe_add_qdrant_filter(body, modalities, query_params) do
    filter = build_qdrant_filter_conditions(modalities, query_params)

    if filter == %{} do
      body
    else
      Map.put(body, "filter", filter)
    end
  end

  defp build_qdrant_filter(query_params) do
    filters = Map.get(query_params, :filters, %{})

    must_conditions =
      Enum.map(filters, fn {field, value} ->
        %{"key" => to_string(field), "match" => %{"value" => value}}
      end)

    %{"must" => must_conditions}
  end

  defp build_qdrant_filter_conditions(modalities, query_params) do
    conditions = []

    conditions =
      if :temporal in modalities && Map.has_key?(query_params, :temporal_range) do
        range = query_params.temporal_range

        conditions ++
          [
            %{
              "key" => "created_at",
              "range" => %{
                "gte" => range[:start] || range["start"],
                "lte" => range[:end] || range["end"]
              }
            }
          ]
      else
        conditions
      end

    conditions =
      if :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) do
        bounds = query_params.spatial_bounds

        conditions ++
          [
            %{
              "key" => "location",
              "geo_bounding_box" => %{
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
          ]
      else
        conditions
      end

    conditions =
      if :semantic in modalities && Map.has_key?(query_params, :filters) do
        filter_conditions =
          Enum.map(query_params.filters, fn {field, value} ->
            %{"key" => to_string(field), "match" => %{"value" => value}}
          end)

        conditions ++ filter_conditions
      else
        conditions
      end

    if conditions == [], do: %{}, else: %{"must" => conditions}
  end

  # ---------------------------------------------------------------------------
  # Private — Milvus
  # ---------------------------------------------------------------------------

  defp query_milvus(peer_info, modalities, query_params, limit, timeout) do
    config = peer_info.adapter_config
    collection = Map.get(config, :collection, "hexads")
    headers = auth_headers(config) ++ [{"Content-Type", "application/json"}]

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # Milvus REST v2: POST /v2/vectordb/entities/search
        url = "#{peer_info.endpoint}/v2/vectordb/entities/search"
        embedding = query_params.vector_query

        body = %{
          "collectionName" => collection,
          "data" => [embedding],
          "limit" => limit,
          "outputFields" => ["*"]
        }

        # Add filter expression for temporal/semantic
        body = maybe_add_milvus_filter(body, modalities, query_params)

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: 200, body: resp}} ->
            results = resp["data"] || []
            {:ok, results}

          {:ok, %Req.Response{status: status, body: resp}} ->
            {:error, {:milvus_error, status, resp["message"] || "unknown"}}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        # Milvus: query without vector (filter only)
        url = "#{peer_info.endpoint}/v2/vectordb/entities/query"

        filter_expr = build_milvus_filter(modalities, query_params)

        body = %{
          "collectionName" => collection,
          "filter" => filter_expr,
          "limit" => limit,
          "outputFields" => ["*"]
        }

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: 200, body: resp}} ->
            {:ok, resp["data"] || []}

          {:ok, %Req.Response{status: status, body: resp}} ->
            {:error, {:milvus_error, status, resp["message"] || "unknown"}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp maybe_add_milvus_filter(body, modalities, query_params) do
    filter_expr = build_milvus_filter(modalities, query_params)

    if filter_expr == "" do
      body
    else
      Map.put(body, "filter", filter_expr)
    end
  end

  defp build_milvus_filter(modalities, query_params) do
    conditions = []

    conditions =
      if :temporal in modalities && Map.has_key?(query_params, :temporal_range) do
        range = query_params.temporal_range
        start_time = range[:start] || range["start"] || ""
        end_time = range[:end] || range["end"] || ""
        conditions ++ ["created_at >= '#{start_time}' AND created_at <= '#{end_time}'"]
      else
        conditions
      end

    conditions =
      if :semantic in modalities && Map.has_key?(query_params, :filters) do
        filter_exprs =
          Enum.map(query_params.filters, fn {field, value} ->
            "#{field} == '#{value}'"
          end)

        conditions ++ filter_exprs
      else
        conditions
      end

    Enum.join(conditions, " AND ")
  end

  # ---------------------------------------------------------------------------
  # Private — Weaviate
  # ---------------------------------------------------------------------------

  defp query_weaviate(peer_info, modalities, query_params, limit, timeout) do
    config = peer_info.adapter_config
    collection = Map.get(config, :collection, "Hexad")
    headers = auth_headers(config) ++ [{"Content-Type", "application/json"}]

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # Weaviate GraphQL: nearVector search
        url = "#{peer_info.endpoint}/v1/graphql"
        embedding = query_params.vector_query

        where_filter = build_weaviate_where(modalities, query_params)

        graphql = build_weaviate_near_vector_query(collection, embedding, limit, where_filter)

        body = %{"query" => graphql}

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: 200, body: resp}} ->
            results =
              get_in(resp, ["data", "Get", collection]) || []

            {:ok, results}

          {:ok, %Req.Response{status: status, body: resp}} ->
            errors = resp["errors"] || []
            error_msg = Enum.map_join(errors, "; ", & &1["message"])
            {:error, {:weaviate_error, status, error_msg}}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        # Weaviate: filtered query without vector
        url = "#{peer_info.endpoint}/v1/graphql"

        where_filter = build_weaviate_where(modalities, query_params)
        graphql = build_weaviate_get_query(collection, limit, where_filter)

        body = %{"query" => graphql}

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: 200, body: resp}} ->
            {:ok, get_in(resp, ["data", "Get", collection]) || []}

          {:ok, %Req.Response{status: status, body: resp}} ->
            errors = resp["errors"] || []
            error_msg = Enum.map_join(errors, "; ", & &1["message"])
            {:error, {:weaviate_error, status, error_msg}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp build_weaviate_near_vector_query(collection, embedding, limit, where_filter) do
    embedding_str = Jason.encode!(embedding)
    where_clause = if where_filter != "", do: ", where: #{where_filter}", else: ""

    """
    { Get { #{collection}(
        nearVector: { vector: #{embedding_str} }
        limit: #{limit}
        #{where_clause}
      ) {
        _additional { id distance }
        ... on #{collection} { _additional { id } }
      }
    } }
    """
  end

  defp build_weaviate_get_query(collection, limit, where_filter) do
    where_clause = if where_filter != "", do: ", where: #{where_filter}", else: ""

    """
    { Get { #{collection}(
        limit: #{limit}
        #{where_clause}
      ) {
        _additional { id }
      }
    } }
    """
  end

  defp build_weaviate_where(modalities, query_params) do
    conditions = []

    conditions =
      if :temporal in modalities && Map.has_key?(query_params, :temporal_range) do
        range = query_params.temporal_range
        start_time = range[:start] || range["start"] || ""

        conditions ++
          [
            ~s|{ path: ["created_at"], operator: GreaterThanEqual, valueDate: "#{start_time}" }|
          ]
      else
        conditions
      end

    conditions =
      if :semantic in modalities && Map.has_key?(query_params, :filters) do
        filter_conditions =
          Enum.map(query_params.filters, fn {field, value} ->
            ~s|{ path: ["#{field}"], operator: Equal, valueText: "#{value}" }|
          end)

        conditions ++ filter_conditions
      else
        conditions
      end

    case conditions do
      [] -> ""
      [single] -> single
      multiple -> "{ operator: And, operands: [#{Enum.join(multiple, ", ")}] }"
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp get_backend(peer_info) do
    Map.get(peer_info.adapter_config, :backend, :qdrant)
  end

  defp health_url(:qdrant, peer_info) do
    "#{peer_info.endpoint}/readyz"
  end

  defp health_url(:milvus, peer_info) do
    "#{peer_info.endpoint}/v2/vectordb/collections/list"
  end

  defp health_url(:weaviate, peer_info) do
    "#{peer_info.endpoint}/v1/.well-known/ready"
  end

  defp health_url(_backend, peer_info) do
    "#{peer_info.endpoint}/health"
  end

  defp extract_result(:qdrant, row) do
    id = to_string(row["id"] || "unknown")
    score = row["score"] || 0.0
    data = row["payload"] || row
    {id, score, data}
  end

  defp extract_result(:milvus, row) do
    id = to_string(row["id"] || row["pk"] || "unknown")
    score = row["distance"] || row["score"] || 0.0
    {id, score, row}
  end

  defp extract_result(:weaviate, row) do
    additional = row["_additional"] || %{}
    id = additional["id"] || "unknown"
    score = 1.0 - (additional["distance"] || 1.0)
    data = Map.drop(row, ["_additional"])
    {id, score, data}
  end

  defp extract_result(_backend, row) do
    id = row["id"] || row["_id"] || "unknown"
    score = parse_score(row)
    {to_string(id), score, row}
  end

  defp parse_score(row) do
    case row["score"] || row["distance"] do
      score when is_number(score) -> score / 1
      _ -> 0.0
    end
  end

  defp maybe_add(list, item, true), do: list ++ [item]
  defp maybe_add(list, _item, false), do: list

  defp auth_headers(config) do
    case Map.get(config, :auth, :none) do
      {:basic, user, pass} ->
        encoded = Base.encode64("#{user}:#{pass}")
        [{"Authorization", "Basic #{encoded}"}]

      {:bearer, token} ->
        [{"Authorization", "Bearer #{token}"}]

      {:api_key, key} ->
        [{"Authorization", "Bearer #{key}"}]

      _ ->
        []
    end
  end
end
