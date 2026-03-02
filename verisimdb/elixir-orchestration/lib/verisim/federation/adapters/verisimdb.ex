# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.VeriSimDB do
  @moduledoc """
  Federation adapter for VeriSimDB-to-VeriSimDB communication.

  This is the default adapter used when federating across VeriSimDB instances.
  It communicates via the verisim-api HTTP endpoints, routing queries based
  on requested modalities:

  - `:vector` → `POST /search/vector` (embedding similarity)
  - `:graph` → `GET /search/related/:id` (graph traversal)
  - `:document` / `:text` → `GET /search/text` (Tantivy full-text)
  - `:spatial` → `POST /spatial/search/radius` (PostGIS-backed)
  - default → `GET /hexads` (paginated listing)

  ## Capabilities

  A VeriSimDB peer supports all 8 octad modalities natively:
  Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, Spatial.

  ## Configuration

  No special `adapter_config` is required — the peer's `endpoint` URL
  is sufficient. Optionally, a PSK can be provided for authenticated
  federation:

      %{
        endpoint: "http://verisim-peer:8080/api/v1",
        adapter_config: %{
          psk: "shared-secret-key"
        }
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
    limit = Map.get(query_params, :limit, 100)
    modalities = Map.get(query_params, :modalities, [])

    start = System.monotonic_time(:millisecond)

    result = dispatch_query(peer_info.endpoint, modalities, query_params, limit, timeout)

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
        "VeriSimDB adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    url = "#{peer_info.endpoint}/health"
    start = System.monotonic_time(:millisecond)

    headers = auth_headers(peer_info)

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
    # VeriSimDB peers support all 8 octad modalities natively.
    [:graph, :vector, :tensor, :semantic, :document, :temporal, :provenance, :spatial]
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn item ->
      %{
        source_store: peer_info.store_id,
        hexad_id: item["id"] || item["entity_id"] || "unknown",
        score: item["score"] || 0.0,
        drifted: item["drifted"] || false,
        data: item,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — Query Dispatch
  # ---------------------------------------------------------------------------

  defp dispatch_query(endpoint, modalities, query_params, limit, timeout) do
    headers = []

    cond do
      :vector in modalities && Map.has_key?(query_params, :vector_query) ->
        url = "#{endpoint}/search/vector"
        body = %{vector: query_params.vector_query, k: limit}

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, extract_results(body)}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      :graph in modalities && Map.has_key?(query_params, :graph_pattern) ->
        url = "#{endpoint}/search/related/#{query_params.graph_pattern}"

        case Req.get(url, params: [limit: limit], headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, extract_results(body)}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        url = "#{endpoint}/search/text"

        case Req.get(url,
               params: [q: query_params.text_query, limit: limit],
               headers: headers,
               receive_timeout: timeout
             ) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, extract_results(body)}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      :spatial in modalities && Map.has_key?(query_params, :spatial_bounds) ->
        url = "#{endpoint}/spatial/search/bounds"
        body = Map.put(query_params.spatial_bounds, :limit, limit)

        case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, extract_results(body)}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        # Default: paginated listing
        url = "#{endpoint}/hexads"

        case Req.get(url, params: [limit: limit], headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, extract_results(body)}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp extract_results(body) when is_list(body), do: body

  defp extract_results(%{"results" => results}) when is_list(results), do: results
  defp extract_results(%{"hexads" => hexads}) when is_list(hexads), do: hexads
  defp extract_results(body) when is_map(body), do: [body]
  defp extract_results(_), do: []

  defp auth_headers(peer_info) do
    case get_in(peer_info, [:adapter_config, :psk]) do
      nil -> []
      psk -> [{"X-Federation-PSK", psk}]
    end
  end
end
