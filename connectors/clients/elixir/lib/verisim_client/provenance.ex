# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Provenance do
  @moduledoc """
  Provenance chain operations for VeriSimDB.

  Every hexad entity in VeriSimDB maintains an append-only provenance chain
  recording creation, transformation, derivation, and access events. This
  module provides methods to read, append to, and cryptographically verify
  provenance chains.

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      {:ok, chain} = VeriSimClient.Provenance.chain(client, "entity-uuid")

      {:ok, event} = VeriSimClient.Provenance.record(client, "entity-uuid", %{
        entity_id: "entity-uuid",
        event_type: "transformation",
        agent: "etl-pipeline-v2",
        description: "Re-embedded with ada-003 model"
      })

      {:ok, verification} = VeriSimClient.Provenance.verify(client, "entity-uuid")
  """

  alias VeriSimClient.Types

  @doc """
  Retrieve the full provenance chain for a hexad entity.

  Events are returned in chronological order (oldest first).

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The hexad entity identifier.
  """
  @spec chain(VeriSimClient.t(), String.t()) ::
          {:ok, [Types.provenance_event()]} | {:error, term()}
  def chain(%VeriSimClient{} = client, id) when is_binary(id) do
    VeriSimClient.do_get(client, "/api/v1/provenance/#{id}")
  end

  @doc """
  Append a new event to a hexad's provenance chain.

  The event is immutably recorded; its timestamp and identifier are assigned
  by the server. The returned map contains the server-assigned fields.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The hexad entity identifier.
    * `event`  — A `provenance_event()` map describing what happened.
  """
  @spec record(VeriSimClient.t(), String.t(), Types.provenance_event()) ::
          {:ok, Types.provenance_event()} | {:error, term()}
  def record(%VeriSimClient{} = client, id, event)
      when is_binary(id) and is_map(event) do
    VeriSimClient.do_post(client, "/api/v1/provenance/#{id}", event)
  end

  @doc """
  Verify the integrity of a hexad's provenance chain.

  The server checks that the chain is contiguous, that no events have been
  tampered with, and that cryptographic hashes (if enabled) are consistent.

  Returns a map with `"valid"` (boolean), `"chain_length"` (integer), and
  optional `"errors"` list describing any integrity violations.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The hexad entity identifier.
  """
  @spec verify(VeriSimClient.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def verify(%VeriSimClient{} = client, id) when is_binary(id) do
    VeriSimClient.do_get(client, "/api/v1/provenance/#{id}/verify")
  end
end
