# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.Neo4j do
  @moduledoc """
  Federation adapter for Neo4j.

  Translates VeriSimDB modality queries into Cypher and executes them via
  the Neo4j HTTP Transactional API. Neo4j is the premier graph database,
  offering native graph storage and processing with a rich query language
  (Cypher), vector search indices, full-text indices, temporal types, and
  spatial point types.

  ## Modality Mapping

  | VeriSimDB Modality | Neo4j Capability              | Extension/Feature Required |
  |--------------------|-------------------------------|----------------------------|
  | `:graph`           | Native Cypher traversal       | Built-in                   |
  | `:vector`          | Vector index (5.11+)          | Built-in (5.11+)           |
  | `:document`        | Full-text index (Lucene)      | Built-in                   |
  | `:temporal`        | Temporal types (date, datetime) | Built-in                 |
  | `:spatial`         | Point type, distance()        | Built-in                   |
  | `:semantic`        | Node/relationship properties  | Built-in                   |

  Neo4j does not support tensor operations or provenance chains natively,
  so `:tensor` and `:provenance` modalities are not supported. Provenance
  could be modelled as relationship chains if needed in future.

  ## Configuration

      %{
        host: "neo4j.internal",
        port: 7474,
        bolt_port: 7687,
        database: "neo4j",
        auth: {:basic, "neo4j", "password"},
        version: 5  # Major version (4 or 5)
      }

  ## Neo4j HTTP API

  Queries are sent to `POST /db/{database}/tx/commit` as Cypher statements.
  Health checks hit `GET /` which returns the server discovery document.
  For vector search, Neo4j 5.11+ is required.
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

    {cypher, cypher_params} = build_cypher(modalities, query_params, limit, peer_info)

    result = execute_cypher(peer_info, cypher, cypher_params, timeout)

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
        "Neo4j adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    start = System.monotonic_time(:millisecond)
    headers = auth_headers(peer_info.adapter_config)

    # Neo4j discovery endpoint: GET / returns server info JSON
    url = peer_info.endpoint

    case Req.get(url, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        # Neo4j returns {"bolt_routing": "...", "transaction": "...", ...}
        if Map.has_key?(body, "bolt_routing") or Map.has_key?(body, "neo4j_version") do
          elapsed = System.monotonic_time(:millisecond) - start
          {:ok, elapsed}
        else
          # Could still be a valid Neo4j response; accept any 200
          elapsed = System.monotonic_time(:millisecond) - start
          {:ok, elapsed}
        end

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
  def supported_modalities(adapter_config) do
    version = Map.get(adapter_config, :version, 5)

    base = [:graph, :document, :temporal, :spatial, :semantic]

    # Vector search requires Neo4j 5.11+
    base
    |> maybe_add(:vector, version >= 5)
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn row ->
      # Neo4j transaction API returns {"row": [...], "meta": [...]} per result
      node_data = extract_node_data(row)

      %{
        source_store: peer_info.store_id,
        hexad_id: node_data["id"] || node_data["elementId"] || node_data["_id"] || "unknown",
        score: parse_score(node_data),
        drifted: false,
        data: node_data,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — Cypher Query Builder
  # ---------------------------------------------------------------------------

  defp build_cypher(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    label = Map.get(config, :label, "Hexad")

    cond do
      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        # Cypher graph traversal: variable-length path patterns
        start_id = query_params.graph_pattern
        max_depth = Map.get(config, :max_depth, 3)
        rel_type = Map.get(config, :relationship_type, "CONNECTED_TO")

        cypher = """
        MATCH (start:#{label} {id: $start_id})
        MATCH path = (start)-[:#{rel_type}*1..#{max_depth}]-(connected)
        RETURN connected, length(path) AS depth, 0.0 AS score
        ORDER BY depth ASC
        LIMIT $limit
        """

        params = %{"start_id" => start_id, "limit" => limit}
        {cypher, params}

      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        # Neo4j 5.11+ vector index query
        embedding = query_params.vector_query
        index_name = Map.get(config, :vector_index, "hexad_embedding_index")

        cypher = """
        CALL db.index.vector.queryNodes($index_name, $limit, $embedding)
        YIELD node, score
        RETURN node, score
        ORDER BY score DESC
        """

        params = %{
          "index_name" => index_name,
          "limit" => limit,
          "embedding" => embedding
        }

        {cypher, params}

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # Neo4j full-text index (Lucene-backed)
        text = query_params.text_query
        index_name = Map.get(config, :fulltext_index, "hexad_fulltext")

        cypher = """
        CALL db.index.fulltext.queryNodes($index_name, $query)
        YIELD node, score
        RETURN node, score
        ORDER BY score DESC
        LIMIT $limit
        """

        params = %{
          "index_name" => index_name,
          "query" => text,
          "limit" => limit
        }

        {cypher, params}

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        # Neo4j point-based spatial queries
        bounds = query_params.spatial_bounds
        center_lat = ((bounds[:min_lat] || 0.0) + (bounds[:max_lat] || 0.0)) / 2
        center_lon = ((bounds[:min_lon] || 0.0) + (bounds[:max_lon] || 0.0)) / 2
        # Approximate radius from bounds (rough calculation)
        radius_km = Map.get(query_params, :radius_km, 50.0)

        cypher = """
        MATCH (n:#{label})
        WHERE point.distance(n.location, point({latitude: $lat, longitude: $lon})) < $radius
        RETURN n, point.distance(n.location, point({latitude: $lat, longitude: $lon})) AS distance,
               0.0 AS score
        ORDER BY distance ASC
        LIMIT $limit
        """

        params = %{
          "lat" => center_lat,
          "lon" => center_lon,
          "radius" => radius_km * 1000,
          "limit" => limit
        }

        {cypher, params}

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        range = query_params.temporal_range

        cypher = """
        MATCH (n:#{label})
        WHERE n.created_at >= datetime($start_time)
          AND n.created_at <= datetime($end_time)
        RETURN n, 0.0 AS score
        ORDER BY n.created_at DESC
        LIMIT $limit
        """

        params = %{
          "start_time" => range[:start] || range["start"] || "",
          "end_time" => range[:end] || range["end"] || "",
          "limit" => limit
        }

        {cypher, params}

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # Node property filters
        filters = query_params.filters

        where_clauses =
          filters
          |> Enum.with_index()
          |> Enum.map(fn {{field, _value}, idx} ->
            "n.#{field} = $filter_#{idx}"
          end)
          |> Enum.join(" AND ")

        where_clause = if where_clauses == "", do: "true", else: where_clauses

        filter_params =
          filters
          |> Enum.with_index()
          |> Enum.into(%{}, fn {{_field, value}, idx} ->
            {"filter_#{idx}", value}
          end)

        cypher = """
        MATCH (n:#{label})
        WHERE #{where_clause}
        RETURN n, 0.0 AS score
        LIMIT $limit
        """

        params = Map.merge(filter_params, %{"limit" => limit})
        {cypher, params}

      true ->
        # Default: return all nodes of the label
        cypher = """
        MATCH (n:#{label})
        RETURN n, 0.0 AS score
        ORDER BY n.id ASC
        LIMIT $limit
        """

        params = %{"limit" => limit}
        {cypher, params}
    end
  end

  defp execute_cypher(peer_info, cypher, cypher_params, timeout) do
    config = peer_info.adapter_config
    database = Map.get(config, :database, "neo4j")
    headers = auth_headers(config) ++ [{"Content-Type", "application/json"}]

    # Neo4j Transaction API: POST /db/{database}/tx/commit
    url = "#{peer_info.endpoint}/db/#{database}/tx/commit"

    body = %{
      "statements" => [
        %{
          "statement" => cypher,
          "parameters" => cypher_params,
          "resultDataContents" => ["row"]
        }
      ]
    }

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        errors = resp_body["errors"] || []

        if errors == [] do
          results = extract_neo4j_results(resp_body)
          {:ok, results}
        else
          error = List.first(errors)
          error_msg = "#{error["code"]}: #{error["message"]}"
          Logger.warning("Neo4j adapter: Cypher error: #{error_msg}")
          {:error, {:cypher_error, error_msg}}
        end

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = resp_body["message"] || "HTTP #{status}"
        Logger.warning("Neo4j adapter: request failed: #{error_msg}")
        {:error, {:neo4j_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp extract_neo4j_results(resp_body) do
    results = resp_body["results"] || []

    results
    |> Enum.flat_map(fn result ->
      columns = result["columns"] || []
      data = result["data"] || []

      Enum.map(data, fn datum ->
        row_values = datum["row"] || []
        Enum.zip(columns, row_values) |> Map.new()
      end)
    end)
  end

  defp extract_node_data(row) when is_map(row) do
    # Neo4j rows may contain node objects under column names like "n", "node", "connected"
    # Extract the first map value that looks like node properties
    node =
      row
      |> Map.values()
      |> Enum.find(fn
        v when is_map(v) -> true
        _ -> false
      end)

    case node do
      nil -> row
      node_map -> Map.merge(row, node_map)
    end
  end

  defp extract_node_data(row), do: %{"raw" => row}

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
