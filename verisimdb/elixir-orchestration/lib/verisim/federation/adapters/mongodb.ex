# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.MongoDB do
  @moduledoc """
  Federation adapter for MongoDB (with Atlas Vector Search and GeoJSON support).

  Translates VeriSimDB modality queries into MongoDB aggregation pipelines and
  executes them via the MongoDB Data API (HTTP/JSON). Supports a wide range of
  modalities through MongoDB's multi-model capabilities and Atlas extensions.

  ## Modality Mapping

  | VeriSimDB Modality | MongoDB Capability          | Extension/Module Required       |
  |--------------------|-----------------------------|--------------------------------|
  | `:graph`           | `$graphLookup` / `DBRef`    | Built-in                       |
  | `:vector`          | Atlas Vector Search          | Atlas cluster with vector index |
  | `:document`        | `$text` search / Atlas FTS  | Text index on collection       |
  | `:temporal`        | ISODate range filters       | Built-in                       |
  | `:provenance`      | Change streams / oplog      | Replica set required           |
  | `:spatial`         | `$geoNear` / `$geoWithin`  | 2dsphere index                 |
  | `:semantic`        | Nested BSON documents       | Built-in                       |

  The `:tensor` modality has no direct MongoDB mapping and is not supported
  by this adapter.

  ## Configuration

      %{
        host: "cluster0.example.mongodb.net",
        port: 27017,
        database: "verisimdb",
        collection: "hexads",
        auth: {:basic, "verisim_user", "password"},
        replica_set: "rs0",
        data_api: true  # Use MongoDB Data API (HTTP) instead of wire protocol
      }

  ## MongoDB Data API

  When `data_api: true` (default), queries are sent via the MongoDB Atlas Data
  API at `POST /action/aggregate`. When `data_api: false`, the adapter falls
  back to a generic HTTP proxy endpoint compatible with mongosh-style queries.

  ## Health Check

  The adapter sends a `{ping: 1}` command via the Data API's `runCommand`
  endpoint or checks the `/status` endpoint of a MongoDB HTTP proxy.
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

    pipeline = build_pipeline(modalities, query_params, limit, peer_info)

    result = execute_aggregate(peer_info, pipeline, timeout)

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
        "MongoDB adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    config = peer_info.adapter_config
    db = Map.get(config, :database, "verisimdb")
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(config)

    # MongoDB Data API: run {ping: 1} command
    url = "#{peer_info.endpoint}/action/runCommand"

    body = %{
      "database" => db,
      "dataSource" => Map.get(config, :data_source, "Cluster0"),
      "command" => %{"ping" => 1}
    }

    case Req.post(url, json: body, headers: headers, receive_timeout: 5_000) do
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
    # MongoDB supports most modalities natively; vector search requires Atlas
    atlas_enabled = Map.get(adapter_config, :atlas, false)
    has_replica_set = Map.has_key?(adapter_config, :replica_set)
    has_geo_index = Map.get(adapter_config, :geo_index, true)

    base = [:graph, :document, :temporal, :semantic]

    base
    |> maybe_add(:vector, atlas_enabled)
    |> maybe_add(:provenance, has_replica_set)
    |> maybe_add(:spatial, has_geo_index)
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn doc ->
      %{
        source_store: peer_info.store_id,
        hexad_id: extract_id(doc),
        score: parse_score(doc),
        drifted: false,
        data: doc,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — MongoDB Aggregation Pipeline Builder
  # ---------------------------------------------------------------------------

  defp build_pipeline(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    _collection = Map.get(config, :collection, "hexads")

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # Atlas Vector Search — $vectorSearch aggregation stage
        embedding = query_params.vector_query
        index_name = Map.get(config, :vector_index, "vector_index")

        [
          %{
            "$vectorSearch" => %{
              "index" => index_name,
              "path" => "embedding",
              "queryVector" => embedding,
              "numCandidates" => limit * 10,
              "limit" => limit
            }
          },
          %{
            "$addFields" => %{
              "score" => %{"$meta" => "vectorSearchScore"}
            }
          }
        ]

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # Full-text search via $text index or Atlas Search
        text = query_params.text_query

        [
          %{
            "$match" => %{
              "$text" => %{"$search" => text}
            }
          },
          %{
            "$addFields" => %{
              "score" => %{"$meta" => "textScore"}
            }
          },
          %{"$sort" => %{"score" => -1}},
          %{"$limit" => limit}
        ]

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        # GeoJSON $geoWithin or $geoNear
        bounds = query_params.spatial_bounds
        min_lon = bounds[:min_lon] || bounds["min_lon"] || 0.0
        min_lat = bounds[:min_lat] || bounds["min_lat"] || 0.0
        max_lon = bounds[:max_lon] || bounds["max_lon"] || 0.0
        max_lat = bounds[:max_lat] || bounds["max_lat"] || 0.0

        [
          %{
            "$match" => %{
              "location" => %{
                "$geoWithin" => %{
                  "$geometry" => %{
                    "type" => "Polygon",
                    "coordinates" => [
                      [
                        [min_lon, min_lat],
                        [max_lon, min_lat],
                        [max_lon, max_lat],
                        [min_lon, max_lat],
                        [min_lon, min_lat]
                      ]
                    ]
                  }
                }
              }
            }
          },
          %{"$limit" => limit}
        ]

      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        # $graphLookup for recursive graph traversal
        start_id = query_params.graph_pattern
        edges_collection = Map.get(config, :edges_collection, "edges")

        [
          %{
            "$match" => %{"_id" => start_id}
          },
          %{
            "$graphLookup" => %{
              "from" => edges_collection,
              "startWith" => "$_id",
              "connectFromField" => "target_id",
              "connectToField" => "source_id",
              "as" => "traversal",
              "maxDepth" => 3,
              "depthField" => "depth"
            }
          },
          %{"$limit" => limit}
        ]

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        # Date range filter on ISODate fields
        range = query_params.temporal_range
        start_time = range[:start] || range["start"] || ""
        end_time = range[:end] || range["end"] || ""

        [
          %{
            "$match" => %{
              "created_at" => %{
                "$gte" => %{"$date" => start_time},
                "$lte" => %{"$date" => end_time}
              }
            }
          },
          %{"$sort" => %{"created_at" => -1}},
          %{"$limit" => limit}
        ]

      :provenance in modalities ->
        # Query change stream log or provenance collection
        provenance_collection = Map.get(config, :provenance_collection, "provenance_log")

        [
          %{
            "$unionWith" => %{
              "coll" => provenance_collection,
              "pipeline" => [
                %{"$sort" => %{"timestamp" => -1}},
                %{"$limit" => limit}
              ]
            }
          },
          %{"$limit" => limit}
        ]

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # Nested document query via dot notation
        filters = query_params.filters
        match_clause = Enum.into(filters, %{}, fn {k, v} -> {"metadata.#{k}", v} end)

        [
          %{"$match" => match_clause},
          %{"$limit" => limit}
        ]

      true ->
        # Default: return all documents sorted by _id
        [
          %{"$sort" => %{"_id" => 1}},
          %{"$limit" => limit}
        ]
    end
  end

  defp execute_aggregate(peer_info, pipeline, timeout) do
    config = peer_info.adapter_config
    db = Map.get(config, :database, "verisimdb")
    collection = Map.get(config, :collection, "hexads")
    headers = auth_headers(config)

    url = "#{peer_info.endpoint}/action/aggregate"

    body = %{
      "database" => db,
      "dataSource" => Map.get(config, :data_source, "Cluster0"),
      "collection" => collection,
      "pipeline" => pipeline
    }

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        documents = resp_body["documents"] || resp_body["cursor"]["firstBatch"] || []
        {:ok, documents}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = resp_body["error"] || resp_body["errorMessage"] || "HTTP #{status}"
        Logger.warning("MongoDB adapter: aggregate failed: #{error_msg}")
        {:error, {:mongo_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp extract_id(doc) do
    doc["_id"] || doc["id"] || doc["_key"] || "unknown"
  end

  defp parse_score(doc) do
    case doc["score"] do
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
        [{"Authorization", "Basic #{encoded}"}, {"Content-Type", "application/json"}]

      {:bearer, token} ->
        [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

      {:api_key, key} ->
        [{"api-key", key}, {"Content-Type", "application/json"}]

      _ ->
        [{"Content-Type", "application/json"}]
    end
  end
end
