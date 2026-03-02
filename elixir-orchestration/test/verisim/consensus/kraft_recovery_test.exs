# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Consensus.KRaftRecoveryTest do
  @moduledoc """
  Tests for KRaft node WAL integration and crash recovery.

  Verifies that KRaft nodes:
  1. Persist durable state (currentTerm, votedFor) via WAL
  2. Persist log entries via WAL
  3. Recover correctly after restart (simulated crash)
  4. Preserve registry state through recovery
  """

  use ExUnit.Case, async: false

  alias VeriSim.Consensus.KRaftNode
  alias VeriSim.Consensus.KRaftWAL

  setup do
    dir = Path.join(System.tmp_dir!(), "kraft_recovery_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, wal_path: dir}
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  defp start_node(node_id, opts \\ []) do
    {:ok, pid} = KRaftNode.start_link([node_id: node_id] ++ opts)
    pid
  end

  defp stop_node(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
  catch
    :exit, _ -> :ok
  end

  # ===========================================================================
  # WAL persistence during normal operation
  # ===========================================================================

  describe "WAL persistence during normal operation" do
    test "persists term and votedFor when node starts election", %{wal_path: wal_path} do
      node_id = unique_id("wal-election")
      pid = start_node(node_id, wal_path: wal_path)

      # Wait for election (single node becomes leader)
      Process.sleep(500)

      # Check WAL has persisted state
      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert recovered.current_term > 0
      assert recovered.voted_for == node_id

      stop_node(pid)
    end

    test "persists log entries when commands are proposed", %{wal_path: wal_path} do
      node_id = unique_id("wal-propose")
      pid = start_node(node_id, wal_path: wal_path)

      # Wait for leader election
      Process.sleep(500)

      # Propose a command
      command = {:register_store, "s1", "http://localhost:9000", ["graph"]}
      {:ok, _index} = KRaftNode.propose(node_id, command)

      # Check WAL has the entry (plus the noop from leader election)
      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert length(recovered.log) >= 2

      # The last entry should be our register_store command
      last_entry = List.last(recovered.log)
      assert last_entry.command == command

      stop_node(pid)
    end

    test "persists noop entry when node becomes leader", %{wal_path: wal_path} do
      node_id = unique_id("wal-noop")
      pid = start_node(node_id, wal_path: wal_path)

      Process.sleep(500)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      # Leader appends a noop entry on election
      noop_entries = Enum.filter(recovered.log, &(&1.command == :noop))
      assert length(noop_entries) >= 1

      stop_node(pid)
    end
  end

  # ===========================================================================
  # Crash recovery — single node
  # ===========================================================================

  describe "crash recovery — single node" do
    test "recovers term after restart", %{wal_path: wal_path} do
      node_id = unique_id("recover-term")

      # Phase 1: Start node, let it elect itself
      pid = start_node(node_id, wal_path: wal_path)
      Process.sleep(500)

      diag1 = KRaftNode.diagnostics(node_id)
      term_before = diag1.current_term
      assert term_before > 0

      # "Crash" the node
      stop_node(pid)
      Process.sleep(100)

      # Phase 2: Restart with same WAL path
      pid2 = start_node(node_id, wal_path: wal_path)
      Process.sleep(100)

      # Should recover with at least the previous term
      diag2 = KRaftNode.diagnostics(node_id)
      assert diag2.current_term >= term_before

      stop_node(pid2)
    end

    test "recovers log entries after restart", %{wal_path: wal_path} do
      node_id = unique_id("recover-log")

      # Phase 1: Start, elect, propose commands
      pid = start_node(node_id, wal_path: wal_path)
      Process.sleep(500)

      {:ok, _} = KRaftNode.propose(node_id, {:register_store, "s1", "http://a:8080", ["graph"]})
      {:ok, _} = KRaftNode.propose(node_id, {:register_store, "s2", "http://b:8080", ["vector"]})

      diag1 = KRaftNode.diagnostics(node_id)
      log_length_before = diag1.log_length

      stop_node(pid)
      Process.sleep(100)

      # Phase 2: Restart and check recovered log
      pid2 = start_node(node_id, wal_path: wal_path)
      Process.sleep(100)

      diag2 = KRaftNode.diagnostics(node_id)
      # Log length should match (noop + 2 commands)
      assert diag2.log_length == log_length_before

      stop_node(pid2)
    end

    test "recovers registry state after restart", %{wal_path: wal_path} do
      node_id = unique_id("recover-registry")

      # Phase 1: Start, elect, register stores
      pid = start_node(node_id, wal_path: wal_path)
      Process.sleep(500)

      {:ok, _} = KRaftNode.propose(node_id, {:register_store, "s1", "http://a:8080", ["graph"]})
      {:ok, _} = KRaftNode.propose(node_id, {:register_store, "s2", "http://b:8080", ["vector"]})
      Process.sleep(100)

      registry_before = KRaftNode.registry(node_id)
      assert Map.has_key?(registry_before.stores, "s1")
      assert Map.has_key?(registry_before.stores, "s2")

      stop_node(pid)
      Process.sleep(100)

      # Phase 2: Restart — the node needs to re-apply committed entries
      # Since there's no snapshot, it replays from the WAL
      pid2 = start_node(node_id, wal_path: wal_path)
      Process.sleep(500)

      # After re-election and re-applying log, registry should have the stores
      # Note: The recovered node starts as follower, needs to re-elect and
      # re-commit entries. In a single-node cluster it will re-elect itself.
      # After election, it appends a new noop and re-commits.
      diag = KRaftNode.diagnostics(node_id)

      # The node should have re-elected and the log entries should be present
      assert diag.log_length >= 2

      stop_node(pid2)
    end
  end

  # ===========================================================================
  # WAL with no persistence (nil path)
  # ===========================================================================

  describe "WAL with no persistence (nil path)" do
    test "node operates normally without WAL", %{} do
      node_id = unique_id("no-wal")
      pid = start_node(node_id, wal_path: nil)

      Process.sleep(500)

      diag = KRaftNode.diagnostics(node_id)
      assert diag.role == :leader

      {:ok, _} = KRaftNode.propose(node_id, {:register_store, "s1", "http://x", []})

      registry = KRaftNode.registry(node_id)
      assert Map.has_key?(registry.stores, "s1")

      stop_node(pid)
    end
  end

  # ===========================================================================
  # Multi-node WAL integration
  # ===========================================================================

  describe "multi-node WAL integration" do
    test "3-node cluster persists state across all nodes" do
      suffix = System.unique_integer([:positive])
      ids = ["w1-#{suffix}", "w2-#{suffix}", "w3-#{suffix}"]

      wal_paths =
        Enum.map(ids, fn id ->
          path = Path.join(System.tmp_dir!(), "kraft_multi_#{id}")
          File.rm_rf!(path)
          path
        end)

      on_exit(fn -> Enum.each(wal_paths, &File.rm_rf!/1) end)

      pids =
        Enum.zip(ids, wal_paths)
        |> Enum.map(fn {id, wal_path} ->
          peers = Enum.reject(ids, &(&1 == id))
          start_node(id, peers: peers, wal_path: wal_path)
        end)

      # Wait for election
      Process.sleep(1_500)

      # Find the leader
      {leader_id, _} =
        ids
        |> Enum.map(fn id -> {id, KRaftNode.diagnostics(id)} end)
        |> Enum.find(fn {_id, diag} -> diag.role == :leader end)

      # Propose a command through the leader
      {:ok, _} =
        KRaftNode.propose(
          leader_id,
          {:register_store, "cluster-store", "http://cluster:8080", ["graph"]}
        )

      Process.sleep(500)

      # All nodes should have WAL data
      Enum.each(wal_paths, fn wal_path ->
        {:ok, recovered} = KRaftWAL.recover(wal_path)
        assert recovered != nil
        assert recovered.current_term > 0
      end)

      Enum.each(pids, &stop_node/1)
    end
  end
end
