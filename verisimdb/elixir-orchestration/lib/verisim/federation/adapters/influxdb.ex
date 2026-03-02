# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.InfluxDB do
  @moduledoc """
  Federation adapter for InfluxDB 2.x.

  Translates VeriSimDB modality queries into Flux (InfluxDB's functional
  query language) and executes them via the InfluxDB v2 HTTP API. InfluxDB
  is purpose-built for time-series data and excels at temporal queries with
  high write throughput and configurable retention policies.

  ## Modality Mapping

  | VeriSimDB Modality | InfluxDB Capability        | Extension/Feature Required |
  |--------------------|----------------------------|----------------------------|
  | `:temporal`        | Native time-series storage | Built-in                   |
  | `:semantic`        | Tag-based filtering        | Built-in                   |

  InfluxDB is specialised for time-series workloads. It does not support
  graph traversal, vector similarity, full-text search, tensor operations,
  provenance tracking, or geospatial queries, so `:graph`, `:vector`,
  `:document`, `:tensor`, `:provenance`, and `:spatial` modalities are not
  supported.

  ## Configuration

      %{
        host: "influxdb.internal",
        port: 8086,
        org: "verisim-org",
        bucket: "hexads",
        token: "your-influxdb-token",
        measurement: "hexad_events"
      }

  ## InfluxDB v2 HTTP API

  Queries are sent to `POST /api/v2/query` with Flux as the request body.
  Health checks hit `GET /health` which returns `{"status": "pass"}` when
  the server is ready. Authentication uses Bearer tokens.

  ## Flux Query Language

  Flux is a functional data scripting language designed for InfluxDB:

      from(bucket: "hexads")
        |> range(start: -1h)
        |> filter(fn: (r) => r._measurement == "hexad_events")
        |> sort(columns: ["_time"], desc: true)
        |> limit(n: 100)
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

    flux = build_flux(modalities, query_params, limit, peer_info)

    result = execute_flux(peer_info, flux, timeout)

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
        "InfluxDB adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(peer_info.adapter_config)

    # InfluxDB v2 health endpoint: GET /health returns {"status": "pass"}
    url = "#{peer_info.endpoint}/health"

    case Req.get(url, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        status = if is_map(body), do: body["status"], else: body

        if status in ["pass", "ready"] do
          elapsed = System.monotonic_time(:millisecond) - start
          {:ok, elapsed}
        else
          {:error, {:unhealthy_status, status}}
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
    # InfluxDB is a time-series database — only temporal and semantic (tags)
    [:temporal, :semantic]
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn row ->
      %{
        source_store: peer_info.store_id,
        hexad_id: extract_id(row),
        score: parse_score(row),
        drifted: false,
        data: row,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — Flux Query Builder
  # ---------------------------------------------------------------------------

  defp build_flux(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    bucket = Map.get(config, :bucket, "hexads")
    measurement = Map.get(config, :measurement, "hexad_events")

    cond do
      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        # Time-range query — the core InfluxDB use case
        range = query_params.temporal_range
        start_time = range[:start] || range["start"] || "-24h"
        end_time = range[:end] || range["end"] || "now()"

        # Determine if start/end are relative durations or absolute timestamps
        start_expr = format_flux_time(start_time)
        end_expr = format_flux_time(end_time)

        base_flux = """
        from(bucket: "#{bucket}")
          |> range(start: #{start_expr}, stop: #{end_expr})
          |> filter(fn: (r) => r._measurement == "#{measurement}")
        """

        # Add tag filters if semantic modality is also requested
        base_flux =
          if :semantic in modalities && Map.has_key?(query_params, :filters) do
            tag_filters = build_flux_tag_filters(query_params.filters)
            base_flux <> tag_filters
          else
            base_flux
          end

        base_flux <>
          """
            |> sort(columns: ["_time"], desc: true)
            |> limit(n: #{limit})
          """

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # Tag-based filtering with default time range
        tag_filters = build_flux_tag_filters(query_params.filters)

        """
        from(bucket: "#{bucket}")
          |> range(start: -30d)
          |> filter(fn: (r) => r._measurement == "#{measurement}")
        #{tag_filters}
          |> sort(columns: ["_time"], desc: true)
          |> limit(n: #{limit})
        """

      true ->
        # Default: recent data from the bucket
        """
        from(bucket: "#{bucket}")
          |> range(start: -24h)
          |> filter(fn: (r) => r._measurement == "#{measurement}")
          |> sort(columns: ["_time"], desc: true)
          |> limit(n: #{limit})
        """
    end
  end

  defp build_flux_tag_filters(filters) do
    filters
    |> Enum.map(fn {tag, value} ->
      tag_str = escape_flux(to_string(tag))
      val_str = escape_flux(to_string(value))
      "  |> filter(fn: (r) => r.#{tag_str} == \"#{val_str}\")"
    end)
    |> Enum.join("\n")
  end

  defp format_flux_time(time) when is_binary(time) do
    cond do
      # Relative duration: -1h, -24h, -7d, etc.
      String.match?(time, ~r/^-\d+[smhdw]$/) -> time
      # "now()" function call
      time == "now()" -> "now()"
      # Absolute ISO8601 timestamp
      true -> ~s|#{time}|
    end
  end

  defp format_flux_time(time), do: to_string(time)

  defp execute_flux(peer_info, flux, timeout) do
    config = peer_info.adapter_config
    org = Map.get(config, :org, "verisim-org")
    headers = auth_headers(config)

    # InfluxDB v2 query endpoint: POST /api/v2/query
    url = "#{peer_info.endpoint}/api/v2/query?org=#{URI.encode(org)}"

    query_headers =
      headers ++
        [
          {"Content-Type", "application/vnd.flux"},
          {"Accept", "application/json"}
        ]

    case Req.post(url, body: flux, headers: query_headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        # InfluxDB may return CSV or annotated CSV; parse to maps
        rows = parse_flux_csv(body)
        {:ok, rows}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        results = body["results"] || [body]
        {:ok, results}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_msg =
          cond do
            is_map(body) -> body["message"] || body["error"] || "HTTP #{status}"
            is_binary(body) -> String.trim(body)
            true -> "HTTP #{status}"
          end

        Logger.warning("InfluxDB adapter: query failed (#{status}): #{error_msg}")
        {:error, {:flux_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp parse_flux_csv(csv_body) when is_binary(csv_body) do
    lines = String.split(csv_body, "\n", trim: true)

    case lines do
      [] ->
        []

      [header_line | data_lines] ->
        # Skip annotation lines (start with #) and empty lines
        {headers, data} = extract_csv_headers_and_data(header_line, data_lines)

        Enum.map(data, fn line ->
          values = String.split(line, ",")

          headers
          |> Enum.zip(values)
          |> Enum.reject(fn {h, _v} -> String.starts_with?(h, "#") end)
          |> Map.new()
        end)
    end
  end

  defp extract_csv_headers_and_data(first_line, rest) do
    # InfluxDB annotated CSV has annotation rows starting with #
    all_lines = [first_line | rest]

    non_annotation = Enum.reject(all_lines, &String.starts_with?(&1, "#"))

    case non_annotation do
      [] -> {[], []}
      [header | data] -> {String.split(header, ","), data}
    end
  end

  defp extract_id(row) do
    # InfluxDB records are identified by measurement + tag set + timestamp
    id_parts =
      [
        row["_measurement"],
        row["entity_id"] || row["id"],
        row["_time"]
      ]
      |> Enum.reject(&is_nil/1)

    case id_parts do
      [] -> "unknown"
      parts -> Enum.join(parts, ":")
    end
  end

  defp parse_score(row) do
    case row["_value"] || row["score"] do
      score when is_number(score) -> score / 1
      _ -> 0.0
    end
  end

  defp escape_flux(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp auth_headers(config) do
    token = Map.get(config, :token)

    case Map.get(config, :auth, :none) do
      {:bearer, tok} ->
        [{"Authorization", "Token #{tok}"}]

      {:api_key, key} ->
        [{"Authorization", "Token #{key}"}]

      :none when is_binary(token) ->
        # InfluxDB convention: token in config map directly
        [{"Authorization", "Token #{token}"}]

      {:basic, user, pass} ->
        encoded = Base.encode64("#{user}:#{pass}")
        [{"Authorization", "Basic #{encoded}"}]

      _ ->
        []
    end
  end
end
