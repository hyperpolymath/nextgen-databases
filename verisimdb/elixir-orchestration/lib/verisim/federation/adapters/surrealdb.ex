# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.SurrealDB do
  @moduledoc """
  Federation adapter for SurrealDB.

  Translates VeriSimDB modality queries into SurrealQL and executes them
  via the SurrealDB HTTP REST API. SurrealDB is a multi-model database
  with native graph traversal, schemaless documents, and built-in
  full-text search — making it a natural fit for several VeriSimDB modalities.

  ## Modality Mapping

  | VeriSimDB Modality | SurrealDB Capability         | Extension/Feature Required |
  |--------------------|------------------------------|----------------------------|
  | `:graph`           | RELATE / graph traversal     | Built-in                   |
  | `:document`        | Full-text search (analyzers) | Built-in                   |
  | `:temporal`        | datetime type / duration     | Built-in                   |
  | `:semantic`        | Schemaless nested records    | Built-in                   |

  SurrealDB does not natively support vector similarity search, tensor
  operations, provenance chains, or geospatial queries (though spatial
  support is on the roadmap), so `:vector`, `:tensor`, `:provenance`,
  and `:spatial` modalities are not supported.

  ## Configuration

      %{
        host: "surrealdb.internal",
        port: 8000,
        namespace: "verisim",
        database: "production",
        auth: {:basic, "root", "root"}
      }

  ## SurrealDB HTTP API

  Queries are sent to `POST /sql` with SurrealQL as the request body.
  The `NS` and `DB` headers select the namespace and database context.
  Health checks hit `GET /health` which returns 200 when the server is
  ready.
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

    surreal_ql = build_surreal_ql(modalities, query_params, limit, peer_info)

    result = execute_surreal_ql(peer_info, surreal_ql, timeout)

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
        "SurrealDB adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(peer_info.adapter_config)

    # SurrealDB health endpoint: GET /health returns 200 when ready
    url = "#{peer_info.endpoint}/health"

    case Req.get(url, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200}} ->
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
  def supported_modalities(_adapter_config) do
    # SurrealDB supports graph, document, temporal, and semantic natively
    [:graph, :document, :temporal, :semantic]
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn record ->
      %{
        source_store: peer_info.store_id,
        hexad_id: extract_id(record),
        score: parse_score(record),
        drifted: false,
        data: record,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — SurrealQL Query Builder
  # ---------------------------------------------------------------------------

  defp build_surreal_ql(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    table = Map.get(config, :table, "hexads")

    cond do
      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        # SurrealDB graph traversal: record links and RELATE edges
        start_vertex = query_params.graph_pattern
        edge_table = Map.get(config, :edge_table, "connects")
        max_depth = Map.get(config, :max_depth, 3)

        """
        SELECT *
        FROM #{table}:#{escape_surreal(start_vertex)}
        ->#{edge_table}->#{table}
        LIMIT #{limit};
        """

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # SurrealDB full-text search via search analyzer
        text = escape_surreal(query_params.text_query)
        search_fields = Map.get(config, :search_fields, ["title", "body", "content"])

        # Build OR conditions across searchable fields
        conditions =
          search_fields
          |> Enum.map(fn field -> "string::contains(string::lowercase(#{field}), string::lowercase('#{text}'))" end)
          |> Enum.join(" OR ")

        """
        SELECT *, search::score(0) AS score
        FROM #{table}
        WHERE #{conditions}
        ORDER BY score DESC
        LIMIT #{limit};
        """

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        range = query_params.temporal_range
        start_time = escape_surreal(range[:start] || range["start"] || "")
        end_time = escape_surreal(range[:end] || range["end"] || "")

        """
        SELECT *
        FROM #{table}
        WHERE created_at >= d'#{start_time}'
          AND created_at <= d'#{end_time}'
        ORDER BY created_at DESC
        LIMIT #{limit};
        """

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # Schemaless nested record query
        filters = query_params.filters

        where_clauses =
          filters
          |> Enum.map(fn {field, value} ->
            "metadata.#{escape_surreal(to_string(field))} = '#{escape_surreal(to_string(value))}'"
          end)
          |> Enum.join(" AND ")

        where_clause = if where_clauses == "", do: "true", else: where_clauses

        """
        SELECT *
        FROM #{table}
        WHERE #{where_clause}
        LIMIT #{limit};
        """

      true ->
        # Default: select all records from the table
        """
        SELECT *
        FROM #{table}
        ORDER BY id ASC
        LIMIT #{limit};
        """
    end
  end

  defp execute_surreal_ql(peer_info, surreal_ql, timeout) do
    config = peer_info.adapter_config
    namespace = Map.get(config, :namespace, "verisim")
    database = Map.get(config, :database, "production")

    url = "#{peer_info.endpoint}/sql"

    headers =
      auth_headers(config) ++
        [
          {"NS", namespace},
          {"DB", database},
          {"Accept", "application/json"},
          {"Content-Type", "text/plain"}
        ]

    case Req.post(url, body: surreal_ql, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        # SurrealDB returns an array of statement results: [{"result": [...], "status": "OK"}]
        results = extract_surreal_results(body)
        {:ok, results}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_msg = extract_surreal_error(body) || "HTTP #{status}"
        Logger.warning("SurrealDB adapter: query failed: #{error_msg}")
        {:error, {:surreal_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp extract_surreal_results(body) when is_list(body) do
    # SurrealDB returns [{%{"result" => [...], "status" => "OK"}}]
    body
    |> Enum.flat_map(fn statement ->
      case statement do
        %{"result" => results, "status" => "OK"} -> List.wrap(results)
        %{"result" => results} -> List.wrap(results)
        _ -> []
      end
    end)
  end

  defp extract_surreal_results(body) when is_map(body) do
    body["result"] || [body]
  end

  defp extract_surreal_results(_body), do: []

  defp extract_surreal_error(body) when is_list(body) do
    body
    |> Enum.find_value(fn
      %{"status" => status, "detail" => detail} when status != "OK" -> detail
      %{"status" => status, "result" => result} when status != "OK" -> inspect(result)
      _ -> nil
    end)
  end

  defp extract_surreal_error(body) when is_map(body) do
    body["information"] || body["description"] || body["error"]
  end

  defp extract_surreal_error(_), do: nil

  defp extract_id(record) do
    case record["id"] do
      # SurrealDB IDs are "table:id" format — extract the id part
      id when is_binary(id) ->
        case String.split(id, ":", parts: 2) do
          [_table, record_id] -> record_id
          _ -> id
        end

      _ ->
        record["_id"] || record["_key"] || "unknown"
    end
  end

  defp parse_score(record) do
    case record["score"] do
      score when is_number(score) -> score / 1
      _ -> 0.0
    end
  end

  defp escape_surreal(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end

  defp escape_surreal(str), do: to_string(str)

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
