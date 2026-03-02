# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.SQLite do
  @moduledoc """
  Federation adapter for SQLite (with sqlite-vss and FTS5 extensions).

  Translates VeriSimDB modality queries into SQLite SQL and executes them
  via an HTTP endpoint (a lightweight sidecar wrapping the SQLite C library).
  SQLite is the world's most deployed database and excels at embedded,
  edge, and single-node workloads with zero configuration.

  ## Modality Mapping

  | VeriSimDB Modality | SQLite Capability          | Extension Required      |
  |--------------------|----------------------------|-------------------------|
  | `:graph`           | Recursive CTEs             | Built-in                |
  | `:vector`          | sqlite-vss (HNSW)         | sqlite-vss              |
  | `:document`        | FTS5 full-text search      | fts5 (built-in compile) |
  | `:temporal`        | datetime() / julianday()   | Built-in                |
  | `:semantic`        | JSON1 functions            | json1 (built-in)        |

  SQLite does not support tensor operations, provenance chains, or
  geospatial queries natively, so `:tensor`, `:provenance`, and `:spatial`
  modalities are not supported. SpatiaLite could add spatial support in
  future if needed.

  ## Configuration

      %{
        path: "/data/verisimdb.sqlite3",
        extensions: [:vss, :fts5],
        table: "hexads"
      }

  ## HTTP Endpoint

  SQLite has no network protocol. This adapter assumes a lightweight HTTP
  wrapper (e.g., sqlite-web, sqld from Turso, or a custom Rust sidecar)
  that accepts SQL via `POST /query` and returns JSON results.

  ## Edge Federation

  SQLite adapters are ideal for edge federation — running VeriSimDB
  modality queries on devices, embedded systems, or serverless functions
  where a full database server would be too heavy.
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
        "SQLite adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    start = System.monotonic_time(:millisecond)

    # SQLite health check: execute a trivial query
    result = execute_sql(peer_info, "SELECT 1 AS ok", %{}, 5_000)

    case result do
      {:ok, _} ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, elapsed}

      {:error, reason} ->
        Logger.warning(
          "SQLite adapter: health check failed for #{peer_info.store_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  @impl true
  def supported_modalities(adapter_config) do
    extensions = Map.get(adapter_config, :extensions, [])

    # SQLite always supports: recursive CTEs (graph), datetime (temporal),
    # and JSON1 (semantic — compiled in by default since SQLite 3.38)
    base = [:graph, :temporal, :semantic]

    base
    |> maybe_add(:vector, :vss in extensions)
    |> maybe_add(:document, :fts5 in extensions)
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn row ->
      %{
        source_store: peer_info.store_id,
        hexad_id: row["id"] || row["rowid"] || row["entity_id"] || "unknown",
        score: parse_score(row),
        drifted: false,
        data: row,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — SQLite SQL Query Builder
  # ---------------------------------------------------------------------------

  defp build_sql(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    table = Map.get(config, :table, "hexads")

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # sqlite-vss: virtual table for vector similarity search
        embedding = query_params.vector_query
        embedding_json = Jason.encode!(embedding)
        vss_table = Map.get(config, :vss_table, "vss_#{table}")

        sql = """
        SELECT h.*, v.distance AS score
        FROM #{vss_table} v
        INNER JOIN #{table} h ON h.rowid = v.rowid
        WHERE vss_search(v.embedding, vss_search_params($1, $2))
        ORDER BY v.distance ASC
        LIMIT $2
        """

        {sql, %{"$1" => embedding_json, "$2" => limit}}

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # FTS5: full-text search with MATCH syntax
        text = query_params.text_query
        fts_table = Map.get(config, :fts_table, "#{table}_fts")

        sql = """
        SELECT h.*, fts.rank AS score
        FROM #{fts_table} fts
        INNER JOIN #{table} h ON h.rowid = fts.rowid
        WHERE #{fts_table} MATCH $1
        ORDER BY fts.rank
        LIMIT $2
        """

        {sql, %{"$1" => text, "$2" => limit}}

      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        # Recursive CTE for graph traversal
        edges_table = Map.get(config, :edges_table, "edges")

        sql = """
        WITH RECURSIVE traversal(id, depth) AS (
          SELECT id, 0
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
        WHERE datetime(created_at) >= datetime($1)
          AND datetime(created_at) <= datetime($2)
        ORDER BY datetime(created_at) DESC
        LIMIT $3
        """

        {sql, %{
          "$1" => range[:start] || range["start"] || "",
          "$2" => range[:end] || range["end"] || "",
          "$3" => limit
        }}

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # JSON1 extraction for structured metadata queries
        filters = query_params.filters

        where_clauses =
          filters
          |> Enum.map(fn {field, value} ->
            "json_extract(metadata, '$.#{field}') = '#{escape_sqlite(to_string(value))}'"
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
        ORDER BY rowid ASC
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
        rows = resp_body["rows"] || resp_body["result"] || resp_body["results"] || resp_body
        {:ok, List.wrap(rows)}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = resp_body["error"] || resp_body["message"] || "HTTP #{status}"
        Logger.warning("SQLite adapter: query failed: #{error_msg}")
        {:error, {:sql_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp parse_score(row) do
    case row["score"] || row["rank"] || row["distance"] do
      score when is_number(score) -> score / 1
      _ -> 0.0
    end
  end

  defp maybe_add(list, item, true), do: list ++ [item]
  defp maybe_add(list, _item, false), do: list

  defp escape_sqlite(str) when is_binary(str) do
    String.replace(str, "'", "''")
  end

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
