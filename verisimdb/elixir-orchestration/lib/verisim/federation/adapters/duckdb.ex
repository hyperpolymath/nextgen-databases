# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.DuckDB do
  @moduledoc """
  Federation adapter for DuckDB (with HNSW, FTS, and Spatial extensions).

  Translates VeriSimDB modality queries into DuckDB SQL and executes them
  via an HTTP endpoint (DuckDB Web Shell, duckdb-wasm REST proxy, or a
  custom HTTP wrapper around the DuckDB C/C++ library). DuckDB excels at
  analytical workloads and can query Parquet, CSV, and JSON files directly.

  ## Modality Mapping

  | VeriSimDB Modality | DuckDB Capability            | Extension Required |
  |--------------------|------------------------------|--------------------|
  | `:graph`           | Recursive CTEs               | Built-in           |
  | `:vector`          | HNSW index, array distance   | hnsw               |
  | `:document`        | Full-text search (FTS)       | fts                |
  | `:temporal`        | TIMESTAMP / INTERVAL types   | Built-in           |
  | `:spatial`         | ST_* functions               | spatial            |
  | `:semantic`        | JSON extraction              | Built-in (json)    |
  | `:tensor`          | FLOAT[] array operations     | Built-in           |

  The `:provenance` modality has no direct DuckDB mapping and is not
  supported by this adapter (DuckDB is an analytical engine without
  change tracking).

  ## Configuration

      %{
        path: "/data/verisimdb.duckdb",   # Database file or :memory
        extensions: [:hnsw, :fts, :spatial],
        table: "hexads"
      }

  ## HTTP Endpoint

  DuckDB does not natively expose an HTTP API. This adapter assumes a
  lightweight HTTP wrapper (e.g., a Rust/Elixir sidecar) that accepts
  SQL via `POST /query` and returns JSON results.
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

    {sql, params} = build_sql(modalities, query_params, limit, peer_info)

    result = execute_sql(peer_info, sql, params, timeout)

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
        "DuckDB adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    start = System.monotonic_time(:millisecond)

    # DuckDB health check: execute a trivial query
    result = execute_sql(peer_info, "SELECT 1 AS ok", %{}, 5_000)

    case result do
      {:ok, _} ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, elapsed}

      {:error, reason} ->
        Logger.warning(
          "DuckDB adapter: health check failed for #{peer_info.store_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  @impl true
  def supported_modalities(adapter_config) do
    extensions = Map.get(adapter_config, :extensions, [])

    # DuckDB always supports: recursive CTEs (graph), timestamps (temporal),
    # JSON (semantic), and FLOAT[] arrays (tensor)
    base = [:graph, :temporal, :semantic, :tensor]

    base
    |> maybe_add(:vector, :hnsw in extensions)
    |> maybe_add(:document, :fts in extensions)
    |> maybe_add(:spatial, :spatial in extensions)
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn row ->
      %{
        source_store: peer_info.store_id,
        hexad_id: row["id"] || row["entity_id"] || row["_key"] || "unknown",
        score: parse_score(row),
        drifted: false,
        data: row,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — DuckDB SQL Query Builder
  # ---------------------------------------------------------------------------

  defp build_sql(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    table = Map.get(config, :table, "hexads")

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # HNSW extension: array_distance for cosine similarity
        embedding = query_params.vector_query
        embedding_str = "[" <> Enum.join(Enum.map(embedding, &to_string/1), ", ") <> "]"
        distance_metric = Map.get(config, :distance_metric, "cosine")

        sql = """
        SELECT *,
               1.0 - array_distance(embedding, $1::FLOAT[#{length(embedding)}], '#{distance_metric}') AS score
        FROM #{table}
        ORDER BY array_distance(embedding, $1::FLOAT[#{length(embedding)}], '#{distance_metric}') ASC
        LIMIT $2
        """

        {sql, %{"$1" => embedding_str, "$2" => limit}}

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # FTS extension: fts_main_{table}.match_bm25
        text = query_params.text_query
        fts_index = "fts_main_#{table}"

        sql = """
        SELECT *,
               fts_main_#{table}.match_bm25(id, $1, fields := 'title, body, content') AS score
        FROM #{table}
        WHERE score IS NOT NULL
        ORDER BY score DESC
        LIMIT $2
        """

        {sql, %{"$1" => text, "$2" => limit}}

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        # Spatial extension: ST_Within / ST_MakeEnvelope
        bounds = query_params.spatial_bounds

        sql = """
        SELECT *,
               0.0 AS score
        FROM #{table}
        WHERE ST_Within(
          geom,
          ST_MakeEnvelope($1, $2, $3, $4)
        )
        LIMIT $5
        """

        {sql, %{
          "$1" => bounds[:min_lon] || bounds["min_lon"] || 0.0,
          "$2" => bounds[:min_lat] || bounds["min_lat"] || 0.0,
          "$3" => bounds[:max_lon] || bounds["max_lon"] || 0.0,
          "$4" => bounds[:max_lat] || bounds["max_lat"] || 0.0,
          "$5" => limit
        }}

      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        # Recursive CTE for graph traversal
        edges_table = Map.get(config, :edges_table, "edges")

        sql = """
        WITH RECURSIVE traversal AS (
          SELECT id, 1 AS depth
          FROM #{table}
          WHERE id = $1

          UNION ALL

          SELECT e.target_id, t.depth + 1
          FROM #{edges_table} e
          INNER JOIN traversal t ON e.source_id = t.id
          WHERE t.depth < 3
        )
        SELECT h.*, 0.0 AS score
        FROM #{table} h
        INNER JOIN traversal t ON h.id = t.id
        LIMIT $2
        """

        {sql, %{"$1" => query_params.graph_pattern, "$2" => limit}}

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        range = query_params.temporal_range

        sql = """
        SELECT *, 0.0 AS score
        FROM #{table}
        WHERE created_at >= CAST($1 AS TIMESTAMP)
          AND created_at <= CAST($2 AS TIMESTAMP)
        ORDER BY created_at DESC
        LIMIT $3
        """

        {sql, %{
          "$1" => range[:start] || range["start"] || "",
          "$2" => range[:end] || range["end"] || "",
          "$3" => limit
        }}

      :tensor in modalities && Map.has_key?(query_params, :vector_query) ->
        # DuckDB array operations for tensor similarity
        embedding = query_params.vector_query
        embedding_str = "[" <> Enum.join(Enum.map(embedding, &to_string/1), ", ") <> "]"

        sql = """
        SELECT *,
               list_cosine_similarity(tensor_data, $1::FLOAT[]) AS score
        FROM #{table}
        WHERE tensor_data IS NOT NULL
        ORDER BY score DESC
        LIMIT $2
        """

        {sql, %{"$1" => embedding_str, "$2" => limit}}

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # JSON extraction via DuckDB's built-in JSON support
        filters = query_params.filters

        where_clauses =
          filters
          |> Enum.map(fn {field, value} ->
            "json_extract_string(metadata, '$.#{field}') = '#{value}'"
          end)
          |> Enum.join(" AND ")

        where_clause = if where_clauses == "", do: "1=1", else: where_clauses

        sql = """
        SELECT *, 0.0 AS score
        FROM #{table}
        WHERE #{where_clause}
        LIMIT $1
        """

        {sql, %{"$1" => limit}}

      true ->
        # Default: paginated listing
        sql = """
        SELECT *, 0.0 AS score
        FROM #{table}
        ORDER BY id ASC
        LIMIT $1
        """

        {sql, %{"$1" => limit}}
    end
  end

  defp execute_sql(peer_info, sql, params, timeout) do
    url = "#{peer_info.endpoint}/query"
    headers = auth_headers(peer_info.adapter_config)

    body = %{
      "query" => sql,
      "params" => params
    }

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        rows = resp_body["rows"] || resp_body["result"] || resp_body["data"] || resp_body
        {:ok, List.wrap(rows)}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = resp_body["error"] || resp_body["message"] || "HTTP #{status}"
        Logger.warning("DuckDB adapter: query failed: #{error_msg}")
        {:error, {:sql_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp parse_score(row) do
    case row["score"] do
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
        [{"X-API-Key", key}, {"Content-Type", "application/json"}]

      _ ->
        [{"Content-Type", "application/json"}]
    end
  end
end
