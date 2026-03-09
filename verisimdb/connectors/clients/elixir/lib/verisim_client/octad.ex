# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Octad do
  @moduledoc """
  Octad CRUD operations for VeriSimDB.

  Octads are the fundamental multi-modal entities in VeriSimDB. Each octad can
  carry data across all eight modalities (graph, vector, tensor, semantic,
  document, temporal, provenance, spatial). This module provides create, read,
  update, delete, and list operations.

  All functions take a `VeriSimClient.t()` as their first argument and return
  `{:ok, result}` or `{:error, reason}` tuples.

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      {:ok, octad} = VeriSimClient.Octad.create(client, %{
        name: "My Entity",
        description: "A test octad",
        vector: %{embedding: [0.1, 0.2, 0.3], model: "ada-002"}
      })

      {:ok, fetched} = VeriSimClient.Octad.get(client, octad["id"])
  """

  alias VeriSimClient.Types

  @doc """
  Create a new octad entity.

  The server assigns a UUID and timestamps; the returned map contains the
  fully-populated record.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `input`  — A `octad_input()` map. At minimum, `:name` should be set.
  """
  @spec create(VeriSimClient.t(), Types.octad_input()) ::
          {:ok, Types.octad()} | {:error, term()}
  def create(%VeriSimClient{} = client, input) when is_map(input) do
    VeriSimClient.do_post(client, "/api/v1/octads", input)
  end

  @doc """
  Retrieve a single octad by its unique identifier.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The octad UUID string.
  """
  @spec get(VeriSimClient.t(), String.t()) ::
          {:ok, Types.octad()} | {:error, term()}
  def get(%VeriSimClient{} = client, id) when is_binary(id) do
    VeriSimClient.do_get(client, "/api/v1/octads/#{id}")
  end

  @doc """
  Update an existing octad entity (partial update / merge semantics).

  Only the fields present in `input` are modified; omitted fields retain their
  current values.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The octad UUID string.
    * `input`  — A `octad_input()` map with the fields to update.
  """
  @spec update(VeriSimClient.t(), String.t(), Types.octad_input()) ::
          {:ok, Types.octad()} | {:error, term()}
  def update(%VeriSimClient{} = client, id, input)
      when is_binary(id) and is_map(input) do
    VeriSimClient.do_put(client, "/api/v1/octads/#{id}", input)
  end

  @doc """
  Delete a octad entity by its unique identifier.

  This is a hard delete — the entity and all associated modality data are
  removed. Provenance records are retained for auditability.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The octad UUID string.
  """
  @spec delete(VeriSimClient.t(), String.t()) :: :ok | {:error, term()}
  def delete(%VeriSimClient{} = client, id) when is_binary(id) do
    VeriSimClient.do_delete(client, "/api/v1/octads/#{id}")
  end

  @doc """
  List octad entities with pagination.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `opts`   — Keyword list with optional `:limit` (default 20) and `:offset` (default 0).

  ## Examples

      {:ok, page} = VeriSimClient.Octad.list(client, limit: 50, offset: 100)
  """
  @spec list(VeriSimClient.t(), keyword()) ::
          {:ok, Types.paginated_response()} | {:error, term()}
  def list(%VeriSimClient{} = client, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    VeriSimClient.do_get(client, "/api/v1/octads?limit=#{limit}&offset=#{offset}")
  end
end
