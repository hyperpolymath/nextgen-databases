# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Consensus.KRaftNodeTest do
  use ExUnit.Case, async: false

  alias VeriSim.Consensus.KRaftNode

  # The Consensus.Registry is started by the Application supervisor.
  # KRaft nodes use unique via-tuple names, so each test can start
  # its own nodes without conflict.

  setup do
    # Track started nodes for cleanup
    nodes = []
    on_exit(fn ->
      # Nodes are cleaned up by ExUnit since we use start_supervised for each
      :ok
    end)
    {:ok, nodes: nodes}
  end

  defp start_kraft(node_id, peers \\ []) do
    # Use start_link directly since Registry is already running via the app.
    # We can't use start_supervised! because it expects a child spec compatible
    # with the test supervisor, and the via-tuple registration goes through the
    # app's Consensus.Registry.
    {:ok, pid} = KRaftNode.start_link(node_id: node_id, peers: peers)
    pid
  end

  defp stop_kraft(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
  catch
    :exit, _ -> :ok
  end

  describe "single-node leader election" do
    test "node with 0 peers becomes leader within 500ms" do
      node_id = "solo-#{System.unique_integer([:positive])}"
      pid = start_kraft(node_id)

      # Wait for election timeout (max 300ms) + margin
      Process.sleep(500)

      diag = KRaftNode.diagnostics(node_id)
      assert diag.role == :leader
      assert diag.leader_id == node_id

      stop_kraft(pid)
    end
  end

  describe "3-node cluster election" do
    test "exactly 1 leader emerges" do
      suffix = System.unique_integer([:positive])
      ids = ["n1-#{suffix}", "n2-#{suffix}", "n3-#{suffix}"]

      pids =
        for id <- ids do
          peers = Enum.reject(ids, &(&1 == id))
          start_kraft(id, peers)
        end

      # Allow enough time for election (timeouts are 150-300ms, but under CI
      # load or when the system is busy, elections can take several rounds).
      # Retry up to 5 times with increasing delays to handle slow convergence.
      {leaders, roles} =
        Enum.reduce_while(1..5, {0, []}, fn attempt, _acc ->
          wait = 500 * attempt
          Process.sleep(wait)

          roles =
            Enum.map(ids, fn id ->
              KRaftNode.diagnostics(id).role
            end)

          leaders = Enum.count(roles, &(&1 == :leader))

          if leaders == 1 do
            {:halt, {leaders, roles}}
          else
            {:cont, {leaders, roles}}
          end
        end)

      assert leaders == 1, "Expected 1 leader, got #{leaders}. Roles: #{inspect(roles)}"

      Enum.each(pids, &stop_kraft/1)
    end
  end

  describe "command proposal" do
    test "leader accepts register_store command" do
      node_id = "cmd-#{System.unique_integer([:positive])}"
      pid = start_kraft(node_id)

      Process.sleep(500)

      command = {:register_store, "store-1", "http://localhost:9000", ["graph", "vector"]}
      assert {:ok, _index} = KRaftNode.propose(node_id, command)

      stop_kraft(pid)
    end
  end

  describe "registry state after commit" do
    test "register_store appears in registry" do
      node_id = "reg-#{System.unique_integer([:positive])}"
      pid = start_kraft(node_id)

      Process.sleep(500)

      command = {:register_store, "my-store", "http://localhost:9001", ["document"]}
      {:ok, _} = KRaftNode.propose(node_id, command)

      # Give time for commit + apply
      Process.sleep(100)

      registry = KRaftNode.registry(node_id)
      assert Map.has_key?(registry.stores, "my-store")
      assert registry.stores["my-store"].endpoint == "http://localhost:9001"
      assert registry.stores["my-store"].modalities == ["document"]

      stop_kraft(pid)
    end
  end

  describe "non-leader redirect" do
    test "proposal to follower returns {:error, {:not_leader, leader_id}}" do
      suffix = System.unique_integer([:positive])
      ids = ["f1-#{suffix}", "f2-#{suffix}", "f3-#{suffix}"]

      pids =
        for id <- ids do
          peers = Enum.reject(ids, &(&1 == id))
          start_kraft(id, peers)
        end

      Process.sleep(1_000)

      # Find a follower
      {follower_id, _} =
        ids
        |> Enum.map(fn id -> {id, KRaftNode.diagnostics(id)} end)
        |> Enum.find(fn {_id, diag} -> diag.role == :follower end)

      result = KRaftNode.propose(follower_id, {:register_store, "s", "http://x", []})
      assert {:error, {:not_leader, _leader}} = result

      Enum.each(pids, &stop_kraft/1)
    end
  end

  describe "dynamic membership — add_server" do
    test "leader accepts add_server and new peer appears in registry members" do
      node_id = "add-#{System.unique_integer([:positive])}"
      pid = start_kraft(node_id)

      Process.sleep(500)

      assert {:ok, _index} = KRaftNode.add_server(node_id, "new-peer-1", [])

      Process.sleep(100)

      registry = KRaftNode.registry(node_id)
      members = get_in(registry, [:config, :members]) || []
      assert "new-peer-1" in members

      stop_kraft(pid)
    end
  end

  describe "dynamic membership — remove_server" do
    test "leader accepts remove_server and peer is removed from registry members" do
      node_id = "rm-#{System.unique_integer([:positive])}"
      pid = start_kraft(node_id)

      Process.sleep(500)

      # Add then remove
      {:ok, _} = KRaftNode.add_server(node_id, "ephemeral-peer", [])
      Process.sleep(100)
      {:ok, _} = KRaftNode.remove_server(node_id, "ephemeral-peer")
      Process.sleep(100)

      registry = KRaftNode.registry(node_id)
      members = get_in(registry, [:config, :members]) || []
      refute "ephemeral-peer" in members

      stop_kraft(pid)
    end
  end

  describe "dynamic membership — removed node stops participating" do
    test "removed peer no longer in diagnostics peer_count after commit" do
      suffix = System.unique_integer([:positive])
      leader_id = "dyn-l-#{suffix}"
      follower_id = "dyn-f-#{suffix}"

      leader_pid = start_kraft(leader_id, [follower_id])
      follower_pid = start_kraft(follower_id, [leader_id])

      Process.sleep(1_000)

      # Find which one is leader
      leader_diag = KRaftNode.diagnostics(leader_id)
      {actual_leader, actual_follower, actual_follower_pid} =
        if leader_diag.role == :leader do
          {leader_id, follower_id, follower_pid}
        else
          {follower_id, leader_id, leader_pid}
        end

      # Remove the follower via the leader
      {:ok, _} = KRaftNode.remove_server(actual_leader, actual_follower)
      Process.sleep(200)

      # Leader's peer count should now be 0 (follower removed from peers)
      diag = KRaftNode.diagnostics(actual_leader)
      assert diag.peer_count == 0

      stop_kraft(leader_pid)
      stop_kraft(follower_pid)
    end
  end

  describe "diagnostics" do
    test "returns expected fields" do
      node_id = "diag-#{System.unique_integer([:positive])}"
      pid = start_kraft(node_id)

      Process.sleep(500)

      diag = KRaftNode.diagnostics(node_id)

      assert is_binary(diag.node_id)
      assert diag.node_id == node_id
      assert diag.role in [:leader, :follower, :candidate]
      assert is_integer(diag.current_term)
      assert is_integer(diag.commit_index)
      assert is_integer(diag.last_applied)
      assert is_integer(diag.log_length)
      assert is_integer(diag.peer_count)
      assert is_integer(diag.election_count)
      assert is_integer(diag.pending_requests)

      stop_kraft(pid)
    end
  end
end
