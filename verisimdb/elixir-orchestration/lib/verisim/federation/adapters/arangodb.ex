# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.ArangoDB do
  @moduledoc """
  Federation adapter for ArangoDB.

  ArangoDB is a multi-model database supporting documents, graphs, and
  key-value access. This adapter translates VeriSimDB modality queries
  into AQL (ArangoDB Query Language) and normalises results into the
  federation result format.

  ## Modality Mapping

  | VeriSimDB Modality | ArangoDB Capability       | Implementation              |
  |--------------------|---------------------------|-----------------------------|
  | `:graph`           | Native graph traversal    | `FOR v, e IN ... GRAPH`     |
  | `:document`        | Fulltext index (Analyzer) | `ANALYZER(... "text_en")`   |
  | `:semantic`        | Document attributes       | JSON document fields        |
  | `:temporal`        | Document with date fields | AQL date functions          |
  | `:provenance`      | Edge collections          | `FOR e IN edges FILTER ...` |
  | `:spatial`         | GeoJSON index             | `GEO_DISTANCE(...)` filter  |

  ArangoDB does not natively support vector similarity or tensor storage,
  so `:vector` and `:tensor` modalities are not supported.

  ## Configuration

      %{
        database: "_system",         # ArangoDB database name
        collection: "hexads",        # Default document collection
        graph_name: "hexad_graph",   # Named graph for traversals
        auth: {:basic, "root", "password"}
      }

  ## ArangoDB HTTP API

  Queries are sent to `POST /_db/{database}/_api/cursor` with AQL.
  Health checks hit `GET /_api/version`.
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

    {aql, bind_vars} = build_aql(modalities, query_params, limit, peer_info)

    result = execute_aql(peer_info, aql, bind_vars, timeout)

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
        "ArangoDB adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    config = peer_info.adapter_config
    db = Map.get(config, :database, "_system")
    url = "#{peer_info.endpoint}/_db/#{db}/_api/version"

    start = System.monotonic_time(:millisecond)
    headers = auth_headers(config)

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
    [:graph, :document, :semantic, :temporal, :provenance, :spatial]
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn doc ->
      %{
        source_store: peer_info.store_id,
        hexad_id: extract_id(doc),
        score: doc["_score"] || doc["score"] || 0.0,
        drifted: false,
        data: doc,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — AQL Query Builder
  # ---------------------------------------------------------------------------

  defp build_aql(modalities, query_params, limit, peer_info) do
    config = peer_info.adapter_config
    collection = Map.get(config, :collection, "hexads")

    cond do
      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        graph_name = Map.get(config, :graph_name, "hexad_graph")
        start_vertex = query_params.graph_pattern

        aql = """
        FOR v, e, p IN 1..3 ANY @start_vertex GRAPH @graph_name
          LIMIT @limit
          RETURN MERGE(v, {_edge: e, _path_length: LENGTH(p.edges)})
        """

        bind_vars = %{
          "start_vertex" => "#{collection}/#{start_vertex}",
          "graph_name" => graph_name,
          "limit" => limit
        }

        {aql, bind_vars}

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        aql = """
        FOR doc IN #{collection}
          FILTER ANALYZER(LIKE(doc.title, @query) OR LIKE(doc.body, @query), "text_en")
          SORT BM25(doc) DESC
          LIMIT @limit
          RETURN MERGE(doc, {_score: BM25(doc)})
        """

        bind_vars = %{
          "query" => "%#{query_params.text_query}%",
          "limit" => limit
        }

        {aql, bind_vars}

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        bounds = query_params.spatial_bounds

        aql = """
        FOR doc IN #{collection}
          FILTER GEO_CONTAINS(
            GEO_POLYGON([
              [@min_lon, @min_lat],
              [@max_lon, @min_lat],
              [@max_lon, @max_lat],
              [@min_lon, @max_lat],
              [@min_lon, @min_lat]
            ]),
            doc.location
          )
          LIMIT @limit
          RETURN doc
        """

        bind_vars = %{
          "min_lat" => bounds[:min_lat] || bounds["min_lat"] || 0.0,
          "min_lon" => bounds[:min_lon] || bounds["min_lon"] || 0.0,
          "max_lat" => bounds[:max_lat] || bounds["max_lat"] || 0.0,
          "max_lon" => bounds[:max_lon] || bounds["max_lon"] || 0.0,
          "limit" => limit
        }

        {aql, bind_vars}

      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        range = query_params.temporal_range

        aql = """
        FOR doc IN #{collection}
          FILTER doc.created_at >= @start_time AND doc.created_at <= @end_time
          SORT doc.created_at DESC
          LIMIT @limit
          RETURN doc
        """

        bind_vars = %{
          "start_time" => range[:start] || range["start"] || "",
          "end_time" => range[:end] || range["end"] || "",
          "limit" => limit
        }

        {aql, bind_vars}

      :provenance in modalities ->
        edge_collection = Map.get(config, :edge_collection, "provenance_edges")

        aql = """
        FOR e IN #{edge_collection}
          SORT e.timestamp DESC
          LIMIT @limit
          RETURN MERGE(e, {
            _from_doc: DOCUMENT(e._from),
            _to_doc: DOCUMENT(e._to)
          })
        """

        bind_vars = %{"limit" => limit}
        {aql, bind_vars}

      true ->
        # Default: return documents from the collection
        aql = """
        FOR doc IN #{collection}
          SORT doc._key ASC
          LIMIT @limit
          RETURN doc
        """

        bind_vars = %{"limit" => limit}
        {aql, bind_vars}
    end
  end

  defp execute_aql(peer_info, aql, bind_vars, timeout) do
    config = peer_info.adapter_config
    db = Map.get(config, :database, "_system")
    url = "#{peer_info.endpoint}/_db/#{db}/_api/cursor"
    headers = auth_headers(config)

    body = %{
      "query" => aql,
      "bindVars" => bind_vars,
      "batchSize" => 1000
    }

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..201 ->
        results = resp_body["result"] || []
        {:ok, results}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = resp_body["errorMessage"] || "HTTP #{status}"
        Logger.warning("ArangoDB adapter: query failed: #{error_msg}")
        {:error, {:aql_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_id(doc) do
    # ArangoDB uses _key or _id; normalise to a plain ID
    doc["_key"] || doc["_id"] || doc["id"] || "unknown"
  end

  defp auth_headers(config) do
    case Map.get(config, :auth, :none) do
      {:basic, user, pass} ->
        encoded = Base.encode64("#{user}:#{pass}")
        [{"Authorization", "Basic #{encoded}"}]

      {:bearer, token} ->
        [{"Authorization", "Bearer #{token}"}]

      _ ->
        []
    end
  end
end
