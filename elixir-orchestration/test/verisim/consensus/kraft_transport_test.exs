# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Consensus.KRaftTransportTest do
  @moduledoc """
  Tests for the KRaft network transport abstraction.

  Verifies that the transport:
  1. Resolves local peers via Elixir Registry
  2. Handles remote peer tuple format
  3. Serializes/deserializes requests correctly for JSON transport
  4. Sends async RPC messages
  """

  use ExUnit.Case, async: false

  alias VeriSim.Consensus.KRaftTransport
  alias VeriSim.Consensus.KRaftNode

  # ===========================================================================
  # peer_id/1
  # ===========================================================================

  describe "peer_id/1" do
    test "extracts ID from string" do
      assert KRaftTransport.peer_id("node-1") == "node-1"
    end

    test "extracts ID from tuple" do
      assert KRaftTransport.peer_id({"node-1", "http://host:4000"}) == "node-1"
    end
  end

  # ===========================================================================
  # JSON serialization
  # ===========================================================================

  describe "serialize_for_json/1" do
    test "converts atom keys to strings" do
      result = KRaftTransport.serialize_for_json(%{term: 5, leader_id: "node-1"})
      assert result == %{"term" => 5, "leader_id" => "node-1"}
    end

    test "converts atom values to strings" do
      result = KRaftTransport.serialize_for_json(%{role: :leader})
      assert result == %{"role" => "leader"}
    end

    test "preserves nil and boolean values" do
      result = KRaftTransport.serialize_for_json(%{active: true, voted_for: nil})
      assert result == %{"active" => true, "voted_for" => nil}
    end

    test "serializes nested maps" do
      result =
        KRaftTransport.serialize_for_json(%{
          term: 1,
          entries: [%{term: 1, index: 1, command: :noop}]
        })

      assert result["entries"] == [%{"term" => 1, "index" => 1, "command" => "noop"}]
    end
  end

  # ===========================================================================
  # Local transport — send_vote_request/2
  # ===========================================================================

  describe "send_vote_request/2 — local" do
    test "sends vote request to a local KRaft node" do
      node_id = "transport-vote-#{System.unique_integer([:positive])}"
      {:ok, pid} = KRaftNode.start_link(node_id: node_id, peers: [])

      Process.sleep(500)

      request = %{
        term: 100,
        candidate_id: "other-node",
        last_log_index: 0,
        last_log_term: 0
      }

      result = KRaftTransport.send_vote_request(node_id, request)
      assert {:ok, response} = result
      assert is_map(response)
      assert Map.has_key?(response, :term) or Map.has_key?(response, "term")

      GenServer.stop(pid, :normal, 1_000)
    end

    test "returns error for non-existent local peer" do
      result = KRaftTransport.send_vote_request("nonexistent-node-xyz", %{})
      assert {:error, _reason} = result
    end
  end

  # ===========================================================================
  # Local transport — send_append_entries/2
  # ===========================================================================

  describe "send_append_entries/2 — local" do
    test "sends append_entries to a local KRaft node" do
      node_id = "transport-ae-#{System.unique_integer([:positive])}"
      {:ok, pid} = KRaftNode.start_link(node_id: node_id, peers: [])

      Process.sleep(500)

      request = %{
        term: 100,
        leader_id: "other-leader",
        prev_log_index: 0,
        prev_log_term: 0,
        entries: [],
        leader_commit: 0
      }

      result = KRaftTransport.send_append_entries(node_id, request)
      assert {:ok, response} = result
      assert is_map(response)

      GenServer.stop(pid, :normal, 1_000)
    end
  end

  # ===========================================================================
  # Remote peer detection
  # ===========================================================================

  describe "remote peer detection" do
    test "tuple peer is treated as remote" do
      # This will fail with connection refused, but it should attempt HTTP
      result =
        KRaftTransport.send_vote_request(
          {"remote-node", "http://127.0.0.1:59999"},
          %{term: 1, candidate_id: "me", last_log_index: 0, last_log_term: 0}
        )

      assert {:error, _reason} = result
    end
  end

  # ===========================================================================
  # Async RPC
  # ===========================================================================

  describe "async_vote_request/3" do
    test "sends response back to caller process" do
      node_id = "transport-async-#{System.unique_integer([:positive])}"
      {:ok, pid} = KRaftNode.start_link(node_id: node_id, peers: [])

      Process.sleep(500)

      request = %{
        term: 100,
        candidate_id: "other-node",
        last_log_index: 0,
        last_log_term: 0
      }

      KRaftTransport.async_vote_request(node_id, request, self())

      assert_receive {:vote_response, ^node_id, response}, 2_000
      assert is_map(response)

      GenServer.stop(pid, :normal, 1_000)
    end
  end

  describe "async_append_entries/3" do
    test "sends response back to caller process" do
      node_id = "transport-async-ae-#{System.unique_integer([:positive])}"
      {:ok, pid} = KRaftNode.start_link(node_id: node_id, peers: [])

      Process.sleep(500)

      request = %{
        term: 100,
        leader_id: "other-leader",
        prev_log_index: 0,
        prev_log_term: 0,
        entries: [],
        leader_commit: 0
      }

      KRaftTransport.async_append_entries(node_id, request, self())

      assert_receive {:append_entries_response, ^node_id, response}, 2_000
      assert is_map(response)

      GenServer.stop(pid, :normal, 1_000)
    end
  end
end
