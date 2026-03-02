# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Consensus.KRaftTransport do
  @moduledoc """
  Network transport abstraction for KRaft Raft consensus.

  Provides RPC delivery to peers via either local GenServer.call (same VM)
  or HTTP (remote nodes). Automatically detects whether a peer is local
  (registered in the Elixir Registry) or remote (requires HTTP).

  ## Peer Format

  Peers can be specified as:
  - `"node-1"` — resolved via local Elixir Registry (same VM)
  - `{"node-1", "http://host:4000"}` — resolved via HTTP (remote VM)

  ## HTTP Endpoints

  When using HTTP transport, the remote node must expose:
  - `POST /raft/vote` — RequestVote RPC
  - `POST /raft/append` — AppendEntries RPC
  - `POST /raft/propose` — Client proposal (forwarded to leader)

  ## Architecture

      ┌──────────────────────────────────────────────────┐
      │  KRaftTransport                                  │
      │    ├── Local: GenServer.call via Registry        │
      │    └── Remote: HTTP POST via :httpc              │
      └──────────────────────────────────────────────────┘
                    ↕                        ↕
      ┌──────────────────┐      ┌──────────────────────┐
      │  Same-VM Peers   │      │  Remote Peers (HTTP)  │
      └──────────────────┘      └──────────────────────┘
  """

  require Logger

  @rpc_timeout 1_000
  @connect_timeout 500

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Send a RequestVote RPC to a peer.

  Returns `{:ok, response}` or `{:error, reason}`.
  The response is a map with `:term` and `:vote_granted` keys.
  """
  def send_vote_request(peer, request) do
    case resolve_peer(peer) do
      {:local, node_id} ->
        local_call(node_id, {:request_vote, request})

      {:remote, _node_id, endpoint} ->
        http_post(endpoint, "/raft/vote", request)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Send an AppendEntries RPC to a peer.

  Returns `{:ok, response}` or `{:error, reason}`.
  The response is a map with `:term`, `:success`, and `:match_index` keys.
  """
  def send_append_entries(peer, request) do
    case resolve_peer(peer) do
      {:local, node_id} ->
        local_call(node_id, {:append_entries, request})

      {:remote, _node_id, endpoint} ->
        http_post(endpoint, "/raft/append", request)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Send a vote request to a peer asynchronously.

  Spawns a Task that sends the result back to the caller process
  as `{:vote_response, peer_id, response}`.
  """
  def async_vote_request(peer, request, reply_to) do
    peer_id = peer_id(peer)

    Task.start(fn ->
      case send_vote_request(peer, request) do
        {:ok, response} ->
          send(reply_to, {:vote_response, peer_id, response})

        {:error, reason} ->
          Logger.debug("KRaft transport: vote request to #{peer_id} failed: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Send an AppendEntries RPC to a peer asynchronously.

  Spawns a Task that sends the result back to the caller process
  as `{:append_entries_response, peer_id, response}`.
  """
  def async_append_entries(peer, request, reply_to) do
    peer_id = peer_id(peer)

    Task.start(fn ->
      case send_append_entries(peer, request) do
        {:ok, response} ->
          send(reply_to, {:append_entries_response, peer_id, response})

        {:error, reason} ->
          Logger.debug(
            "KRaft transport: append_entries to #{peer_id} failed: #{inspect(reason)}"
          )
      end
    end)
  end

  @doc """
  Extract the node ID string from a peer specification.
  """
  def peer_id({node_id, _endpoint}), do: node_id
  def peer_id(node_id) when is_binary(node_id), do: node_id

  # ---------------------------------------------------------------------------
  # Private: Peer Resolution
  # ---------------------------------------------------------------------------

  defp resolve_peer({node_id, endpoint}) when is_binary(endpoint) do
    # Explicit remote endpoint — always use HTTP
    {:remote, node_id, endpoint}
  end

  defp resolve_peer(node_id) when is_binary(node_id) do
    # Check if peer is registered locally first
    case Registry.lookup(VeriSim.Consensus.Registry, node_id) do
      [{_pid, _}] -> {:local, node_id}
      _ -> {:error, {:peer_not_found, node_id}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Local RPC (same VM)
  # ---------------------------------------------------------------------------

  defp local_call(node_id, message) do
    via = {:via, Registry, {VeriSim.Consensus.Registry, node_id}}

    try do
      response = GenServer.call(via, message, @rpc_timeout)
      {:ok, response}
    catch
      :exit, _ -> {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: HTTP RPC (remote VM)
  # ---------------------------------------------------------------------------

  defp http_post(endpoint, path, request) do
    url = String.to_charlist("#{endpoint}#{path}")
    body = Jason.encode!(serialize_for_json(request))
    content_type = ~c"application/json"
    http_opts = [timeout: @rpc_timeout, connect_timeout: @connect_timeout]

    case :httpc.request(
           :post,
           {url, [], content_type, body},
           http_opts,
           []
         ) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        parsed = Jason.decode!(to_string(response_body))
        {:ok, atomize_keys(parsed)}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  rescue
    e -> {:error, {:http_exception, Exception.message(e)}}
  end

  # ---------------------------------------------------------------------------
  # Private: JSON Serialization Helpers
  # ---------------------------------------------------------------------------

  @doc false
  def serialize_for_json(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), serialize_for_json(v)}
      {k, v} -> {k, serialize_for_json(v)}
    end)
  end

  def serialize_for_json(list) when is_list(list) do
    Enum.map(list, &serialize_for_json/1)
  end

  def serialize_for_json(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) do
    Atom.to_string(atom)
  end

  def serialize_for_json(other), do: other

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, atomize_keys(v)}
    end)
  rescue
    ArgumentError -> map
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(other), do: other
end
