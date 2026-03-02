# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.ClickHouse do
  @moduledoc """
  Federation adapter for ClickHouse.

  Translates VeriSimDB modality queries into ClickHouse SQL and executes
  them via the ClickHouse HTTP interface (port 8123). ClickHouse is an
  OLAP columnar database optimised for analytical queries over large
  datasets, with built-in support for vector operations, full-text search,
  and geospatial functions.

  ## Modality Mapping

  | VeriSimDB Modality | ClickHouse Capability       | Extension/Feature Required   |
  |--------------------|-----------------------------|------------------------------|
  | `:vector`          | Array distance functions    | Built-in (cosineDistance)     |
  | `:document`        | Full-text index / ngramBF   | Built-in (experimental)      |
  | `:temporal`        | DateTime64 / toInterval     | Built-in                     |
  | `:spatial`         | Geo functions (pointInPolygon) | Built-in                  |
  | `:semantic`        | JSON extraction              | Built-in (JSONExtract*)      |

  ClickHouse does not natively support graph traversal, tensor operations,
  or provenance tracking, so `:graph`, `:tensor`, and `:provenance`
  modalities are not supported.

  ## Configuration

      %{
        host: "clickhouse.internal",
        port: 8123,
        database: "verisimdb",
        table: "hexads",
        auth: {:basic, "default", "password"}
      }

  ## ClickHouse HTTP Interface

  ClickHouse exposes a native HTTP interface on port 8123. Queries are
  sent as POST body to `/?database={db}&default_format=JSONEachRow`.
  The root endpoint `GET /` returns `"Ok.\\n"` for health checks.
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

    sql = build_sql(modalities, query_params, limit, peer_info)

    result = execute_sql(peer_info, sql, timeout)

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
        "ClickHouse adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(peer_info.adapter_config)

    # ClickHouse HTTP interface: GET / returns "Ok.\n"
    url = peer_info.endpoint

    case Req.get(url, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        if String.starts_with?(String.trim(to_string(body)), "Ok") do
          elapsed = System.monotonic_time(:millisecond) - start
          {:ok, elapsed}
        else
          {:error, {:unexpected_health_response, body}}
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
    # ClickHouse supports these modalities natively — no extensions needed
    [:vector, :document, :temporal, :spatial, :semantic]
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
  # Private — ClickHouse SQL Builder
  # ---------------------------------------------------------------------------

  defp build_sql(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    db = Map.get(config, :database, "verisimdb")
    table = Map.get(config, :table, "hexads")
    qualified_table = "#{db}.#{table}"

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # ClickHouse cosineDistance on Array(Float32) columns
        embedding = query_params.vector_query
        embedding_str = "[" <> Enum.join(Enum.map(embedding, &to_string/1), ", ") <> "]"
        distance_fn = Map.get(config, :distance_function, "cosineDistance")

        """
        SELECT *,
               1.0 - #{distance_fn}(embedding, #{embedding_str}) AS score
        FROM #{qualified_table}
        ORDER BY #{distance_fn}(embedding, #{embedding_str}) ASC
        LIMIT #{limit}
        FORMAT JSONEachRow
        """

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # ClickHouse full-text search via hasToken / multiSearchAny / ngramSearch
        text = escape_clickhouse_string(query_params.text_query)
        tokens = String.split(text, ~r/\s+/, trim: true)

        token_conditions =
          tokens
          |> Enum.map(fn token -> "hasToken(lower(content), '#{String.downcase(token)}')" end)
          |> Enum.join(" AND ")

        condition = if token_conditions == "", do: "1=1", else: token_conditions

        """
        SELECT *,
               ngramSearch(lower(content), '#{String.downcase(text)}') AS score
        FROM #{qualified_table}
        WHERE #{condition}
        ORDER BY score DESC
        LIMIT #{limit}
        FORMAT JSONEachRow
        """

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        range = query_params.temporal_range
        start_time = escape_clickhouse_string(range[:start] || range["start"] || "")
        end_time = escape_clickhouse_string(range[:end] || range["end"] || "")

        """
        SELECT *, 0.0 AS score
        FROM #{qualified_table}
        WHERE created_at >= toDateTime64('#{start_time}', 3)
          AND created_at <= toDateTime64('#{end_time}', 3)
        ORDER BY created_at DESC
        LIMIT #{limit}
        FORMAT JSONEachRow
        """

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        bounds = query_params.spatial_bounds
        min_lon = bounds[:min_lon] || bounds["min_lon"] || 0.0
        min_lat = bounds[:min_lat] || bounds["min_lat"] || 0.0
        max_lon = bounds[:max_lon] || bounds["max_lon"] || 0.0
        max_lat = bounds[:max_lat] || bounds["max_lat"] || 0.0

        """
        SELECT *, 0.0 AS score
        FROM #{qualified_table}
        WHERE pointInPolygon(
          (longitude, latitude),
          [(#{min_lon}, #{min_lat}), (#{max_lon}, #{min_lat}),
           (#{max_lon}, #{max_lat}), (#{min_lon}, #{max_lat})]
        )
        LIMIT #{limit}
        FORMAT JSONEachRow
        """

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # JSONExtract functions for structured metadata queries
        filters = query_params.filters

        where_clauses =
          filters
          |> Enum.map(fn {field, value} ->
            "JSONExtractString(metadata, '#{escape_clickhouse_string(to_string(field))}') = '#{escape_clickhouse_string(to_string(value))}'"
          end)
          |> Enum.join(" AND ")

        where_clause = if where_clauses == "", do: "1=1", else: where_clauses

        """
        SELECT *, 0.0 AS score
        FROM #{qualified_table}
        WHERE #{where_clause}
        LIMIT #{limit}
        FORMAT JSONEachRow
        """

      true ->
        # Default: paginated listing
        """
        SELECT *, 0.0 AS score
        FROM #{qualified_table}
        ORDER BY id ASC
        LIMIT #{limit}
        FORMAT JSONEachRow
        """
    end
  end

  defp execute_sql(peer_info, sql, timeout) do
    config = peer_info.adapter_config
    db = Map.get(config, :database, "verisimdb")
    headers = auth_headers(config)

    # ClickHouse HTTP interface: POST with SQL as body
    url = "#{peer_info.endpoint}/?database=#{db}&default_format=JSONEachRow"

    case Req.post(url, body: sql, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        # JSONEachRow format: one JSON object per line
        rows = parse_json_each_row(body)
        {:ok, rows}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        rows = body["data"] || [body]
        {:ok, rows}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_msg = if is_binary(body), do: String.trim(body), else: inspect(body)
        Logger.warning("ClickHouse adapter: query failed (#{status}): #{error_msg}")
        {:error, {:sql_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp parse_json_each_row(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case Jason.decode(line) do
        {:ok, row} -> row
        {:error, _} -> %{"raw" => line}
      end
    end)
  end

  defp parse_score(row) do
    case row["score"] do
      score when is_number(score) -> score / 1
      _ -> 0.0
    end
  end

  defp escape_clickhouse_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end

  defp escape_clickhouse_string(str), do: to_string(str)

  defp auth_headers(config) do
    case Map.get(config, :auth, :none) do
      {:basic, user, pass} ->
        encoded = Base.encode64("#{user}:#{pass}")
        [{"Authorization", "Basic #{encoded}"}]

      {:bearer, token} ->
        [{"Authorization", "Bearer #{token}"}]

      {:api_key, key} ->
        [{"X-ClickHouse-Key", key}]

      _ ->
        []
    end
  end
end
