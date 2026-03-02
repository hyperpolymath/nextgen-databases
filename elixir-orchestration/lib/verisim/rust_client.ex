# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.RustClient do
  @moduledoc """
  HTTP client for communicating with the Rust core (verisim-api).

  This module provides a typed interface to the Rust HTTP API,
  handling serialization, error handling, and retries.
  """

  require Logger

  @default_base_url "http://localhost:8080/api/v1"
  @default_timeout 30_000
  @cache_table :verisim_rust_client_cache
  @cache_ttl_ms 30_000  # 30 seconds default TTL

  # ---------------------------------------------------------------------------
  # ETS Cache — transparent read-through caching for hexad lookups and searches
  # ---------------------------------------------------------------------------

  @doc """
  Initialize the ETS cache table. Call from application supervisor or init.
  """
  def init_cache do
    if :ets.info(@cache_table) == :undefined do
      :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  @doc """
  Clear all cached entries.
  """
  def clear_cache do
    if :ets.info(@cache_table) != :undefined do
      :ets.delete_all_objects(@cache_table)
    end
    :ok
  end

  @doc """
  Invalidate a specific cache key (e.g., after a write operation).
  """
  def invalidate_cache(key) do
    if :ets.info(@cache_table) != :undefined do
      :ets.delete(@cache_table, key)
    end
    :ok
  end

  defp cache_get(key) do
    if :ets.info(@cache_table) != :undefined do
      case :ets.lookup(@cache_table, key) do
        [{^key, value, expiry}] ->
          if System.monotonic_time(:millisecond) < expiry do
            {:hit, value}
          else
            :ets.delete(@cache_table, key)
            :miss
          end
        _ -> :miss
      end
    else
      :miss
    end
  end

  defp cache_put(key, value, ttl_ms \\ @cache_ttl_ms) do
    if :ets.info(@cache_table) != :undefined do
      expiry = System.monotonic_time(:millisecond) + ttl_ms
      :ets.insert(@cache_table, {key, value, expiry})
    end
    value
  end

  # Configuration

  def base_url do
    Application.get_env(:verisim, :rust_core_url, @default_base_url)
  end

  def timeout do
    Application.get_env(:verisim, :rust_core_timeout, @default_timeout)
  end

  # Health Check

  @doc """
  Check the health of the Rust core.
  """
  def health do
    case get("/health") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status}} ->
        {:error, {:unhealthy, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Hexad Operations

  @doc """
  Create a new hexad entity.
  """
  def create_hexad(input) do
    case post("/hexads", input) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 201, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get a hexad by ID.
  """
  def get_hexad(entity_id) do
    cache_key = {:hexad, entity_id}

    case cache_get(cache_key) do
      {:hit, cached} -> {:ok, cached}
      :miss ->
        case get("/hexads/#{entity_id}") do
          {:ok, %{status: 200, body: body}} ->
            cache_put(cache_key, body)
            {:ok, body}
          {:ok, %{status: 404}} -> {:error, :not_found}
          {:ok, %{status: status, body: body}} -> {:error, {status, body}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Update a hexad.
  """
  def update_hexad(entity_id, changes) do
    case put("/hexads/#{entity_id}", changes) do
      {:ok, %{status: 200, body: body}} ->
        invalidate_cache({:hexad, entity_id})
        invalidate_cache({:drift, entity_id})
        {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete a hexad.
  """
  def delete_hexad(entity_id) do
    case delete("/hexads/#{entity_id}") do
      {:ok, %{status: 204}} ->
        invalidate_cache({:hexad, entity_id})
        invalidate_cache({:drift, entity_id})
        :ok
      {:ok, %{status: 200}} ->
        invalidate_cache({:hexad, entity_id})
        invalidate_cache({:drift, entity_id})
        :ok
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Search Operations

  @doc """
  Search for hexads by text.
  """
  def search_text(query, limit \\ 10) do
    case get("/search/text", q: query, limit: limit) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search for hexads by vector similarity.
  """
  def search_vector(vector, k \\ 10) do
    case post("/search/vector", %{vector: vector, k: k}) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get related hexads (graph query).
  """
  def get_related(entity_id) do
    case get("/search/related/#{entity_id}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Drift and Normalization

  @doc """
  Get the drift score for an entity.
  """
  def get_drift_score(entity_id) do
    cache_key = {:drift, entity_id}

    case cache_get(cache_key) do
      {:hit, cached} -> {:ok, cached}
      :miss ->
        case get("/drift/entity/#{entity_id}") do
          {:ok, %{status: 200, body: %{"score" => score}}} ->
            cache_put(cache_key, score, 10_000)  # Short TTL — drift changes frequently
            {:ok, score}
          {:ok, %{status: 404}} -> {:ok, 0.0}
          {:ok, %{status: status, body: body}} -> {:error, {status, body}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Get overall drift status.
  """
  def drift_status do
    case get("/drift/status") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Trigger normalization for an entity.
  """
  def normalize(entity_id) do
    case post("/normalizer/trigger/#{entity_id}", %{}) do
      {:ok, %{status: 202}} -> :ok
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get normalizer status.
  """
  def normalizer_status do
    case get("/normalizer/status") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Provenance Operations

  @doc """
  Retrieve the full provenance chain for an entity.
  """
  def get_provenance_chain(entity_id) do
    cache_key = {:provenance_chain, entity_id}

    case cache_get(cache_key) do
      {:hit, cached} ->
        {:ok, cached}

      :miss ->
        case get("/provenance/#{entity_id}") do
          {:ok, %{status: 200, body: body}} ->
            cache_put(cache_key, body, 15_000)
            {:ok, body}

          {:ok, %{status: 404}} ->
            {:error, :not_found}

          {:ok, %{status: status, body: body}} ->
            {:error, {status, body}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Record a new provenance event for an entity.
  """
  def record_provenance(entity_id, event) do
    case post("/provenance/#{entity_id}/record", event) do
      {:ok, %{status: 200, body: body}} ->
        invalidate_cache({:provenance_chain, entity_id})
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verify the hash-chain integrity for an entity's provenance.
  """
  def verify_provenance(entity_id) do
    case get("/provenance/#{entity_id}/verify") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Spatial Operations

  @doc """
  Search for entities within a given radius of a point.
  """
  def search_spatial_radius(latitude, longitude, radius_km, opts \\ []) do
    body = %{
      latitude: latitude,
      longitude: longitude,
      radius_km: radius_km,
      limit: Keyword.get(opts, :limit, 50)
    }

    case post("/spatial/search/radius", body) do
      {:ok, %{status: 200, body: results}} -> {:ok, results}
      {:ok, %{status: status, body: body_resp}} -> {:error, {status, body_resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search for entities within a bounding box.
  """
  def search_spatial_bounds(min_lat, min_lon, max_lat, max_lon, opts \\ []) do
    body = %{
      min_lat: min_lat,
      min_lon: min_lon,
      max_lat: max_lat,
      max_lon: max_lon,
      limit: Keyword.get(opts, :limit, 50)
    }

    case post("/spatial/search/bounds", body) do
      {:ok, %{status: 200, body: results}} -> {:ok, results}
      {:ok, %{status: status, body: body_resp}} -> {:error, {status, body_resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Find the k nearest entities to a given point.
  """
  def search_spatial_nearest(latitude, longitude, k \\ 10) do
    body = %{
      latitude: latitude,
      longitude: longitude,
      k: k
    }

    case post("/spatial/search/nearest", body) do
      {:ok, %{status: 200, body: results}} -> {:ok, results}
      {:ok, %{status: status, body: body_resp}} -> {:error, {status, body_resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  # HTTP Helpers (public: get/2 and post/2 used by Federation.Resolver)

  def get(path, params \\ []) do
    url = base_url() <> path

    case Req.get(url,
      params: params,
      receive_timeout: timeout(),
      decode_body: true
    ) do
      {:ok, resp} -> validate_json_response(resp)
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:request_failed, e}}
  end

  def post(path, body) do
    url = base_url() <> path

    case Req.post(url,
      json: body,
      receive_timeout: timeout(),
      decode_body: true
    ) do
      {:ok, resp} -> validate_json_response(resp)
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:request_failed, e}}
  end

  defp put(path, body) do
    url = base_url() <> path

    case Req.put(url,
      json: body,
      receive_timeout: timeout(),
      decode_body: true
    ) do
      {:ok, resp} -> validate_json_response(resp)
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:request_failed, e}}
  end

  defp delete(path) do
    url = base_url() <> path

    case Req.delete(url,
      receive_timeout: timeout(),
      decode_body: true
    ) do
      {:ok, resp} -> validate_json_response(resp)
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:request_failed, e}}
  end

  # Validates that the response body is decoded JSON (map or list), not a raw
  # string. When a non-VeriSimDB server (e.g. nginx) sits on the configured
  # port, Req returns status 200 with an HTML string body. Without this check,
  # upstream code crashes trying to enumerate/map over a binary.
  defp validate_json_response(%{status: status, body: body} = resp)
       when is_map(body) or is_list(body) do
    {:ok, resp}
  end

  defp validate_json_response(%{status: status, body: body})
       when is_binary(body) and status >= 200 and status < 300 do
    Logger.warning("Rust core returned non-JSON response (status #{status}): #{String.slice(body, 0, 120)}...")
    {:error, {:non_json_response, status, String.slice(body, 0, 500)}}
  end

  defp validate_json_response(%{status: status, body: body}) when is_binary(body) do
    {:error, {status, body}}
  end

  defp validate_json_response(resp), do: {:ok, resp}
end
