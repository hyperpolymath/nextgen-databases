# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Federation do
  @moduledoc """
  Federation operations for cross-instance VeriSimDB queries.

  VeriSimDB supports a federated architecture where multiple instances can be
  registered as peers. Federated queries fan out to all (or selected) peers
  and merge results transparently. This module provides peer management and
  federated query execution.

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      {:ok, peer} = VeriSimClient.Federation.register_peer(client,
        "us-west-replica",
        "https://peer.example.com:8080",
        "verisimdb",
        %{api_key: "peer-key-123"}
      )

      {:ok, peers} = VeriSimClient.Federation.list_peers(client)

      {:ok, results} = VeriSimClient.Federation.query(client,
        [:vector, :graph],
        %{vector: [0.1, 0.2, 0.3], k: 5}
      )
  """

  alias VeriSimClient.Types

  @doc """
  Register a remote VeriSimDB instance (or compatible adapter) as a
  federation peer.

  ## Parameters

    * `client`       — A `VeriSimClient.t()` connection.
    * `store_id`     — Unique logical name for the peer (e.g. "us-west-replica").
    * `endpoint`     — Base URL of the peer's API.
    * `adapter_type` — Adapter kind: "verisimdb", "quandledb", "lithoglyph", or custom.
    * `config`       — Adapter-specific configuration (auth tokens, timeouts, etc.).

  ## Returns

  `{:ok, peer_record}` on success, where `peer_record` is a map.
  """
  @spec register_peer(VeriSimClient.t(), String.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def register_peer(%VeriSimClient{} = client, store_id, endpoint, adapter_type, config)
      when is_binary(store_id) and is_binary(endpoint) and
             is_binary(adapter_type) and is_map(config) do
    body = %{
      store_id: store_id,
      endpoint: endpoint,
      adapter_type: adapter_type,
      config: config
    }

    VeriSimClient.do_post(client, "/api/v1/federation/peers", body)
  end

  @doc """
  List all registered federation peers.

  Returns a list of peer records, each containing the store ID, endpoint,
  adapter type, health status, and last-seen timestamp.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
  """
  @spec list_peers(VeriSimClient.t()) :: {:ok, [map()]} | {:error, term()}
  def list_peers(%VeriSimClient{} = client) do
    VeriSimClient.do_get(client, "/api/v1/federation/peers")
  end

  @doc """
  Execute a federated query that fans out to all registered peers.

  The query targets the specified modalities and passes `params` to each
  peer's local query engine. Results are merged and returned with per-peer
  attribution.

  ## Parameters

    * `client`     — A `VeriSimClient.t()` connection.
    * `modalities` — List of modality atoms to query across peers.
    * `params`     — Query parameters map (modality-specific filters, limits, etc.).

  ## Returns

  `{:ok, results}` where `results` is a list of `federation_result()` maps.
  """
  @spec query(VeriSimClient.t(), [Types.modality()], map()) ::
          {:ok, [Types.federation_result()]} | {:error, term()}
  def query(%VeriSimClient{} = client, modalities, params)
      when is_list(modalities) and is_map(params) do
    body = %{
      modalities: modalities,
      params: params
    }

    VeriSimClient.do_post(client, "/api/v1/federation/query", body)
  end
end
