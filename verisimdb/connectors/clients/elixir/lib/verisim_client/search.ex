# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Search do
  @moduledoc """
  Search operations across VeriSimDB's multi-modal hexad entities.

  Supports full-text search, vector similarity (k-NN), graph-relational
  traversal, and geospatial queries (radius, bounding box, nearest-neighbour).

  All functions take a `VeriSimClient.t()` as their first argument and return
  `{:ok, results}` or `{:error, reason}` tuples.

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      # Full-text search
      {:ok, results} = VeriSimClient.Search.text(client, "machine learning", limit: 10)

      # Vector similarity
      {:ok, results} = VeriSimClient.Search.vector(client, [0.1, 0.2, 0.3], k: 5)

      # Spatial radius search
      {:ok, results} = VeriSimClient.Search.spatial_radius(client, 51.5074, -0.1278, 10.0, limit: 20)
  """

  alias VeriSimClient.Types

  @doc """
  Full-text search across hexad names, descriptions, and document content.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `query`  — The search query string.
    * `opts`   — Keyword list with optional `:limit` (default 20).
  """
  @spec text(VeriSimClient.t(), String.t(), keyword()) ::
          {:ok, [Types.hexad()]} | {:error, term()}
  def text(%VeriSimClient{} = client, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    encoded_query = URI.encode_www_form(query)
    VeriSimClient.do_get(client, "/api/v1/search/text?q=#{encoded_query}&limit=#{limit}")
  end

  @doc """
  Vector similarity search (k-nearest neighbours).

  Finds the `k` hexads whose stored vector embeddings are closest to the
  provided vector (cosine similarity by default).

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `vector` — The query embedding (list of floats).
    * `opts`   — Keyword list with optional `:k` (default 10).
  """
  @spec vector(VeriSimClient.t(), [float()], keyword()) ::
          {:ok, [Types.hexad()]} | {:error, term()}
  def vector(%VeriSimClient{} = client, vector, opts \\ []) when is_list(vector) do
    k = Keyword.get(opts, :k, 10)
    body = %{vector: vector, k: k}
    VeriSimClient.do_post(client, "/api/v1/search/vector", body)
  end

  @doc """
  Find hexads related to the given entity via graph edges.

  Traverses one hop of the graph modality and returns all directly connected
  hexads.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The hexad identifier to find relations for.
  """
  @spec related(VeriSimClient.t(), String.t()) ::
          {:ok, [Types.hexad()]} | {:error, term()}
  def related(%VeriSimClient{} = client, id) when is_binary(id) do
    VeriSimClient.do_get(client, "/api/v1/search/related/#{id}")
  end

  @doc """
  Spatial search: find hexads within a given radius of a point.

  ## Parameters

    * `client`    — A `VeriSimClient.t()` connection.
    * `lat`       — Centre latitude (WGS 84 decimal degrees).
    * `lon`       — Centre longitude (WGS 84 decimal degrees).
    * `radius_km` — Search radius in kilometres.
    * `opts`      — Keyword list with optional `:limit` (default 20).
  """
  @spec spatial_radius(VeriSimClient.t(), float(), float(), float(), keyword()) ::
          {:ok, [Types.hexad()]} | {:error, term()}
  def spatial_radius(%VeriSimClient{} = client, lat, lon, radius_km, opts \\ [])
      when is_number(lat) and is_number(lon) and is_number(radius_km) do
    limit = Keyword.get(opts, :limit, 20)

    body = %{
      latitude: lat,
      longitude: lon,
      radius_km: radius_km,
      limit: limit
    }

    VeriSimClient.do_post(client, "/api/v1/search/spatial/radius", body)
  end

  @doc """
  Spatial search: find hexads within a rectangular bounding box.

  ## Parameters

    * `client`  — A `VeriSimClient.t()` connection.
    * `min_lat` — Southern boundary latitude.
    * `min_lon` — Western boundary longitude.
    * `max_lat` — Northern boundary latitude.
    * `max_lon` — Eastern boundary longitude.
    * `opts`    — Keyword list with optional `:limit` (default 20).
  """
  @spec spatial_bounds(VeriSimClient.t(), float(), float(), float(), float(), keyword()) ::
          {:ok, [Types.hexad()]} | {:error, term()}
  def spatial_bounds(%VeriSimClient{} = client, min_lat, min_lon, max_lat, max_lon, opts \\ [])
      when is_number(min_lat) and is_number(min_lon) and
             is_number(max_lat) and is_number(max_lon) do
    limit = Keyword.get(opts, :limit, 20)

    body = %{
      min_lat: min_lat,
      min_lon: min_lon,
      max_lat: max_lat,
      max_lon: max_lon,
      limit: limit
    }

    VeriSimClient.do_post(client, "/api/v1/search/spatial/bounds", body)
  end

  @doc """
  Spatial search: find the `k` nearest hexads to a given point.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `lat`    — Query point latitude (WGS 84 decimal degrees).
    * `lon`    — Query point longitude (WGS 84 decimal degrees).
    * `opts`   — Keyword list with optional `:k` (default 10).
  """
  @spec nearest(VeriSimClient.t(), float(), float(), keyword()) ::
          {:ok, [Types.hexad()]} | {:error, term()}
  def nearest(%VeriSimClient{} = client, lat, lon, opts \\ [])
      when is_number(lat) and is_number(lon) do
    k = Keyword.get(opts, :k, 10)

    body = %{
      latitude: lat,
      longitude: lon,
      k: k
    }

    VeriSimClient.do_post(client, "/api/v1/search/spatial/nearest", body)
  end
end
