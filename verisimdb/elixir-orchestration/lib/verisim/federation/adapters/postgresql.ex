# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.PostgreSQL do
  @moduledoc """
  Federation adapter for PostgreSQL (with pgvector and PostGIS extensions).

  Translates VeriSimDB modality queries into SQL and executes them via
  the PostgreSQL wire protocol (Postgrex). Supports rich modality mapping
  when optional extensions are installed.

  ## Modality Mapping

  | VeriSimDB Modality | PostgreSQL Capability     | Extension Required |
  |--------------------|---------------------------|--------------------|
  | `:document`        | `tsvector` + GIN index    | Built-in           |
  | `:vector`          | `pgvector` cosine/L2      | pgvector           |
  | `:semantic`        | JSONB columns             | Built-in           |
  | `:temporal`        | `tstzrange`, timestamps   | Built-in           |
  | `:spatial`         | PostGIS `geometry`/`geography` | PostGIS       |
  | `:graph`           | Recursive CTEs            | Built-in           |
  | `:provenance`      | Audit table / triggers    | Built-in           |

  The `:tensor` modality has no direct PostgreSQL mapping and is not
  supported by this adapter.

  ## Configuration

      %{
        host: "postgres.internal",
        port: 5432,
        database: "verisimdb",
        schema: "public",
        table: "hexads",
        auth: {:basic, "verisim", "password"},
        extensions: [:pgvector, :postgis]  # Optional: declares installed extensions
      }

  ## Connection Management

  This adapter uses Req for HTTP-based PostgreSQL proxies (e.g., PostgREST,
  Supabase) or can be extended to use Postgrex for direct wire protocol.
  The HTTP approach is used for consistency with other federation adapters
  and to avoid adding Postgrex as a required dependency.

  For direct Postgrex connections (higher performance), configure:

      %{
        protocol: :wire,
        host: "localhost",
        port: 5432,
        ...
      }
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
        "PostgreSQL adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    _config = peer_info.adapter_config
    start = System.monotonic_time(:millisecond)

    # Health check: execute a trivial query to verify the connection
    result = execute_sql(peer_info, "SELECT 1 AS ok", %{}, 5_000)

    case result do
      {:ok, _} ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, elapsed}

      {:error, reason} ->
        Logger.warning(
          "PostgreSQL adapter: health check failed for #{peer_info.store_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  @impl true
  def supported_modalities(adapter_config) do
    extensions = Map.get(adapter_config, :extensions, [])

    base = [:document, :semantic, :temporal, :graph, :provenance]

    base
    |> maybe_add(:vector, :pgvector in extensions)
    |> maybe_add(:spatial, :postgis in extensions)
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
  # Private — SQL Query Builder
  # ---------------------------------------------------------------------------

  defp build_sql(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    schema = Map.get(config, :schema, "public")
    table = Map.get(config, :table, "hexads")
    qualified_table = "#{schema}.#{table}"

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # pgvector cosine similarity search
        embedding = query_params.vector_query
        embedding_str = "[" <> Enum.join(embedding, ",") <> "]"

        sql = """
        SELECT *,
               1 - (embedding <=> $1::vector) AS score
        FROM #{qualified_table}
        ORDER BY embedding <=> $1::vector
        LIMIT $2
        """

        {sql, %{"$1" => embedding_str, "$2" => limit}}

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # Full-text search via tsvector
        sql = """
        SELECT *,
               ts_rank_cd(search_vector, plainto_tsquery('english', $1)) AS score
        FROM #{qualified_table}
        WHERE search_vector @@ plainto_tsquery('english', $1)
        ORDER BY score DESC
        LIMIT $2
        """

        {sql, %{"$1" => query_params.text_query, "$2" => limit}}

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        # PostGIS bounding box query
        bounds = query_params.spatial_bounds

        sql = """
        SELECT *,
               0.0 AS score
        FROM #{qualified_table}
        WHERE ST_Within(
          geom,
          ST_MakeEnvelope($1, $2, $3, $4, 4326)
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
        edges_table = Map.get(config, :edges_table, "#{schema}.edges")

        sql = """
        WITH RECURSIVE traversal AS (
          SELECT id, 1 AS depth
          FROM #{qualified_table}
          WHERE id = $1

          UNION ALL

          SELECT e.target_id, t.depth + 1
          FROM #{edges_table} e
          INNER JOIN traversal t ON e.source_id = t.id
          WHERE t.depth < 3
        )
        SELECT h.*, 0.0 AS score
        FROM #{qualified_table} h
        INNER JOIN traversal t ON h.id = t.id
        LIMIT $2
        """

        {sql, %{"$1" => query_params.graph_pattern, "$2" => limit}}

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        range = query_params.temporal_range

        sql = """
        SELECT *, 0.0 AS score
        FROM #{qualified_table}
        WHERE created_at >= $1::timestamptz
          AND created_at <= $2::timestamptz
        ORDER BY created_at DESC
        LIMIT $3
        """

        {sql, %{
          "$1" => range[:start] || range["start"] || "",
          "$2" => range[:end] || range["end"] || "",
          "$3" => limit
        }}

      :provenance in modalities ->
        audit_table = Map.get(config, :audit_table, "#{schema}.audit_log")

        sql = """
        SELECT *, 0.0 AS score
        FROM #{audit_table}
        ORDER BY event_time DESC
        LIMIT $1
        """

        {sql, %{"$1" => limit}}

      true ->
        # Default: paginated listing
        sql = """
        SELECT *, 0.0 AS score
        FROM #{qualified_table}
        ORDER BY id ASC
        LIMIT $1
        """

        {sql, %{"$1" => limit}}
    end
  end

  defp execute_sql(peer_info, sql, params, timeout) do
    config = peer_info.adapter_config
    protocol = Map.get(config, :protocol, :http)

    case protocol do
      :http ->
        execute_via_http(peer_info, sql, params, timeout)

      :wire ->
        # Direct Postgrex connection — requires Postgrex in mix.exs
        execute_via_postgrex(peer_info, sql, params, timeout)
    end
  end

  # HTTP-based execution (PostgREST / pg-gateway / custom endpoint)
  defp execute_via_http(peer_info, sql, params, timeout) do
    url = "#{peer_info.endpoint}/query"
    headers = auth_headers(peer_info.adapter_config)

    body = %{
      "query" => sql,
      "params" => params
    }

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        rows = resp_body["rows"] || resp_body["result"] || resp_body
        {:ok, List.wrap(rows)}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = resp_body["error"] || resp_body["message"] || "HTTP #{status}"
        Logger.warning("PostgreSQL adapter: query failed: #{error_msg}")
        {:error, {:sql_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Direct Postgrex wire protocol — only used when :protocol is :wire.
  # Requires Postgrex as an optional dependency in mix.exs.
  # Falls back to HTTP if Postgrex is not available.
  defp execute_via_postgrex(peer_info, sql, params, _timeout) do
    config = peer_info.adapter_config

    postgrex_opts = [
      hostname: Map.get(config, :host, "localhost"),
      port: Map.get(config, :port, 5432),
      database: Map.get(config, :database, "verisimdb"),
      username: extract_username(config),
      password: extract_password(config)
    ]

    # Use dynamic dispatch to avoid compile-time dependency on Postgrex.
    # If Postgrex is not in mix.exs, the UndefinedFunctionError rescue
    # below catches it and falls back to HTTP.
    postgrex_mod = Module.concat([Postgrex])

    case apply(postgrex_mod, :start_link, [postgrex_opts]) do
      {:ok, conn} ->
        param_values = params |> Map.values()

        case apply(postgrex_mod, :query, [conn, sql, param_values]) do
          {:ok, result} ->
            # Postgrex.Result has :columns and :rows fields
            columns = Map.get(result, :columns, [])
            rows = Map.get(result, :rows, [])

            results =
              Enum.map(rows, fn row ->
                columns |> Enum.zip(row) |> Map.new()
              end)

            GenServer.stop(conn)
            {:ok, results}

          {:error, reason} ->
            GenServer.stop(conn)
            {:error, {:postgrex_error, reason}}
        end

      {:error, reason} ->
        Logger.warning(
          "PostgreSQL adapter: Postgrex connection failed for #{peer_info.store_id}, " <>
            "falling back to HTTP: #{inspect(reason)}"
        )

        execute_via_http(peer_info, sql, params, @default_timeout)
    end
  rescue
    UndefinedFunctionError ->
      Logger.debug(
        "PostgreSQL adapter: Postgrex not available, using HTTP for #{peer_info.store_id}"
      )

      execute_via_http(peer_info, sql, params, @default_timeout)
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

  defp extract_username(config) do
    case Map.get(config, :auth, :none) do
      {:basic, user, _pass} -> user
      _ -> "postgres"
    end
  end

  defp extract_password(config) do
    case Map.get(config, :auth, :none) do
      {:basic, _user, pass} -> pass
      _ -> ""
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
        [{"X-API-Key", key}]

      _ ->
        []
    end
  end
end
