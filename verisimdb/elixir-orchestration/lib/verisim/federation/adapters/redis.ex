# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.Redis do
  @moduledoc """
  Federation adapter for Redis (with RedisSearch, RedisGraph, RedisJSON, and
  RedisTimeSeries modules).

  Translates VeriSimDB modality queries into Redis command sequences and
  executes them via the Redis HTTP API (RedisInsight REST, Redis Cloud API,
  or a custom HTTP-to-Redis bridge). Modality support depends on which Redis
  modules are installed on the target instance.

  ## Modality Mapping

  | VeriSimDB Modality | Redis Capability         | Module Required     |
  |--------------------|--------------------------|---------------------|
  | `:graph`           | RedisGraph (Cypher)      | RedisGraph          |
  | `:vector`          | Vector Similarity Search | RediSearch 2.4+     |
  | `:document`        | Full-text index (FT)     | RediSearch           |
  | `:temporal`        | Time-series data         | RedisTimeSeries      |
  | `:provenance`      | Redis Streams            | Built-in (5.0+)     |
  | `:semantic`        | JSON documents           | RedisJSON            |

  The `:tensor` and `:spatial` modalities have no direct Redis mapping and
  are not supported by this adapter. Spatial queries could be partially
  served via RediSearch GEO filters if needed in future.

  ## Configuration

      %{
        host: "redis.internal",
        port: 6379,
        database: 0,
        auth: {:basic, "default", "password"},
        modules: [:redisearch, :redisgraph, :redisjson, :redistimeseries]
      }

  ## Module Detection

  The `supported_modalities/1` callback checks the `modules` list in the
  adapter configuration to determine which modalities are available. This
  mirrors the PostgreSQL adapter's extension-based modality detection.

  ## Redis HTTP Bridge

  Redis does not natively expose an HTTP API. This adapter assumes one of:
  - Redis Cloud REST API
  - RedisInsight API
  - A custom HTTP-to-Redis proxy (e.g., webdis, redis-rest)

  Commands are sent as JSON arrays to `POST /command` or equivalent.
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

    commands = build_commands(modalities, query_params, limit, peer_info)

    result = execute_commands(peer_info, commands, timeout)

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
        "Redis adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(peer_info.adapter_config)

    # Send PING command via HTTP bridge
    url = "#{peer_info.endpoint}/command"

    body = %{"command" => ["PING"]}

    case Req.post(url, json: body, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        # Redis PING returns "PONG" or {"result": "PONG"}
        response = if is_map(resp_body), do: resp_body["result"], else: resp_body

        if response in ["PONG", "pong"] do
          elapsed = System.monotonic_time(:millisecond) - start
          {:ok, elapsed}
        else
          {:error, {:unexpected_ping_response, response}}
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
  def supported_modalities(adapter_config) do
    modules = Map.get(adapter_config, :modules, [])

    # Provenance via Redis Streams is built-in (Redis 5.0+), always available
    base = [:provenance]

    base
    |> maybe_add(:vector, :redisearch in modules)
    |> maybe_add(:document, :redisearch in modules)
    |> maybe_add(:graph, :redisgraph in modules)
    |> maybe_add(:temporal, :redistimeseries in modules)
    |> maybe_add(:semantic, :redisjson in modules)
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn row ->
      # Redis results come in varied formats depending on the command.
      # Normalise to a consistent map structure.
      {id, data} = extract_id_and_data(row)

      %{
        source_store: peer_info.store_id,
        hexad_id: id,
        score: parse_score(row),
        drifted: false,
        data: data,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — Redis Command Builder
  # ---------------------------------------------------------------------------

  defp build_commands(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    index_name = Map.get(config, :index_name, "hexad_idx")

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # RediSearch Vector Similarity Search (VSS)
        # FT.SEARCH index_name "*=>[KNN limit @vec_field $BLOB]" PARAMS 2 BLOB <vector_bytes>
        embedding = query_params.vector_query
        vector_field = Map.get(config, :vector_field, "embedding")
        blob = encode_vector_blob(embedding)

        %{
          "command" => [
            "FT.SEARCH",
            index_name,
            "*=>[KNN #{limit} @#{vector_field} $BLOB]",
            "PARAMS",
            "2",
            "BLOB",
            blob,
            "SORTBY",
            "__#{vector_field}_score",
            "LIMIT",
            "0",
            to_string(limit),
            "DIALECT",
            "2"
          ]
        }

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # RediSearch full-text query
        text = query_params.text_query

        %{
          "command" => [
            "FT.SEARCH",
            index_name,
            text,
            "LIMIT",
            "0",
            to_string(limit),
            "WITHSCORES"
          ]
        }

      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        # RedisGraph Cypher query
        graph_key = Map.get(config, :graph_key, "hexad_graph")
        start_vertex = query_params.graph_pattern

        cypher = """
        MATCH (n)-[r*1..3]-(m)
        WHERE n.id = '#{start_vertex}'
        RETURN m
        LIMIT #{limit}
        """

        %{
          "command" => ["GRAPH.QUERY", graph_key, String.trim(cypher)]
        }

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        # RedisTimeSeries range query
        range = query_params.temporal_range
        ts_key = Map.get(config, :timeseries_key, "hexad_ts")
        start_ts = range[:start] || range["start"] || "-"
        end_ts = range[:end] || range["end"] || "+"

        %{
          "command" => ["TS.RANGE", ts_key, to_string(start_ts), to_string(end_ts), "COUNT", to_string(limit)]
        }

      :provenance in modalities ->
        # Redis Streams — XREVRANGE for latest events
        stream_key = Map.get(config, :stream_key, "hexad_provenance")

        %{
          "command" => ["XREVRANGE", stream_key, "+", "-", "COUNT", to_string(limit)]
        }

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # RedisJSON — JSON.GET with path filters
        filters = query_params.filters
        json_key_pattern = Map.get(config, :json_key_pattern, "hexad:*")

        # Use FT.SEARCH with JSON filter if RediSearch is available
        filter_clauses =
          filters
          |> Enum.map(fn {field, value} -> "@#{field}:{#{value}}" end)
          |> Enum.join(" ")

        %{
          "command" => [
            "FT.SEARCH",
            index_name,
            filter_clauses,
            "LIMIT",
            "0",
            to_string(limit)
          ],
          "_json_key_pattern" => json_key_pattern
        }

      true ->
        # Default: scan keys matching the collection pattern
        key_pattern = Map.get(config, :key_pattern, "hexad:*")

        %{
          "command" => ["SCAN", "0", "MATCH", key_pattern, "COUNT", to_string(limit)]
        }
    end
  end

  defp execute_commands(peer_info, commands, timeout) do
    url = "#{peer_info.endpoint}/command"
    headers = auth_headers(peer_info.adapter_config)

    # Send the command(s) to the Redis HTTP bridge
    body = Map.take(commands, ["command"])

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        results = parse_redis_response(resp_body)
        {:ok, results}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = resp_body["error"] || "HTTP #{status}"
        Logger.warning("Redis adapter: command failed: #{error_msg}")
        {:error, {:redis_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp parse_redis_response(resp_body) when is_map(resp_body) do
    # Redis HTTP bridges typically return {"result": [...]} or {"data": [...]}
    result = resp_body["result"] || resp_body["data"] || resp_body
    List.wrap(result)
  end

  defp parse_redis_response(resp_body) when is_list(resp_body), do: resp_body
  defp parse_redis_response(resp_body), do: [resp_body]

  defp extract_id_and_data(row) when is_map(row) do
    id = row["id"] || row["_id"] || row["key"] || "unknown"
    {id, row}
  end

  defp extract_id_and_data(row) when is_binary(row) do
    {row, %{"raw" => row}}
  end

  defp extract_id_and_data(row) do
    {"unknown", %{"raw" => inspect(row)}}
  end

  defp parse_score(row) when is_map(row) do
    case row["score"] || row["__score"] do
      score when is_number(score) -> score / 1
      score when is_binary(score) -> String.to_float(score)
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end

  defp parse_score(_row), do: 0.0

  defp encode_vector_blob(embedding) when is_list(embedding) do
    # Encode float vector as Base64-encoded binary blob for RediSearch VSS
    embedding
    |> Enum.map(fn f -> <<f::float-little-32>> end)
    |> IO.iodata_to_binary()
    |> Base.encode64()
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
        [{"X-API-Key", key}, {"Content-Type", "application/json"}]

      _ ->
        [{"Content-Type", "application/json"}]
    end
  end
end
