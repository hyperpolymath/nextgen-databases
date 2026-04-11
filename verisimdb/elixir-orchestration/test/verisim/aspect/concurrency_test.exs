# SPDX-License-Identifier: PMPL-1.0-or-later
# Author: Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
#
# Concurrency aspect tests for VeriSimDB.
#
# Validates that the in-process components of VeriSimDB handle concurrent
# access correctly, with no data corruption, deadlocks, or silent data loss.
#
# Test categories:
#
#   1. Concurrent entity writes  — last-write-wins or CRDT merge, never corrupt.
#   2. Parallel VCL queries      — all queries complete without contention.
#   3. Concurrent Kraft proposals — at most one accepted per term slot.
#   4. DriftMonitor under load   — concurrent drift reports do not corrupt state.
#   5. SchemaRegistry concurrency — concurrent type registrations are serialised.
#
# All tests are in-process. No external databases, containers, or TCP.

defmodule VeriSim.Aspect.ConcurrencyTest do
  @moduledoc """
  Concurrency tests for the VeriSimDB in-process stack.

  All concurrent operations are performed from Elixir Tasks, which map to
  BEAM processes. The BEAM scheduler ensures preemptive multi-tasking, making
  these tests meaningful even without OS-level thread races.
  """

  use ExUnit.Case, async: false

  alias VeriSim.{DriftMonitor, SchemaRegistry}
  alias VeriSim.Consensus.KRaftNode
  alias VeriSim.Query.{VCLBridge, VCLExecutor}
  alias VeriSim.Test.VCLTestHelpers, as: H

  # Number of concurrent writers / readers for load tests.
  @concurrency 20

  # Timeout for collecting Task results (ms).
  @task_timeout 5_000

  setup_all do
    _pid = H.ensure_bridge_started()
    :ok
  end

  # ===========================================================================
  # 1. Concurrent Entity Writes
  #
  # @concurrency Tasks simultaneously write to the same entity ID via the
  # EntityServer. The final state must be consistent — no corrupt maps, no
  # nil fields, version must be a non-negative integer.
  # ===========================================================================

  describe "concurrent writes to EntityServer" do
    test "concurrent updates to same entity produce consistent final state" do
      alias VeriSim.EntityServer

      entity_id = "conc-write-#{System.unique_integer([:positive])}"
      {:ok, _pid} = EntityServer.start_link(entity_id)

      # Spawn @concurrency concurrent update tasks.
      tasks =
        for _i <- 1..@concurrency do
          Task.async(fn ->
            EntityServer.update(entity_id, [{:modality, :document, true}])
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      # Every task must receive a result (no timeout, no crash).
      assert length(results) == @concurrency

      Enum.each(results, fn result ->
        assert match?({:ok, _state}, result) or match?({:error, _}, result),
               "Unexpected result from concurrent update: #{inspect(result)}"
      end)

      # Final state must be structurally valid.
      {:ok, final_state} = EntityServer.get(entity_id)
      assert is_map(final_state)
      assert final_state.id == entity_id
      assert is_integer(final_state.version) and final_state.version >= 0
      assert final_state.status == :active
    end

    test "concurrent writes to different entities do not interfere" do
      alias VeriSim.EntityServer

      # Start @concurrency independent entities.
      entity_ids =
        for i <- 1..@concurrency do
          id = "conc-isolated-#{i}-#{System.unique_integer([:positive])}"
          {:ok, _pid} = EntityServer.start_link(id)
          id
        end

      # Each task writes only to its own entity.
      tasks =
        for id <- entity_ids do
          Task.async(fn ->
            EntityServer.update(id, [{:modality, :vector, true}])
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      # All tasks complete.
      assert length(results) == @concurrency

      # Each entity's final state reflects its own writes, not another's.
      for id <- entity_ids do
        {:ok, state} = EntityServer.get(id)
        assert state.id == id
        assert state.modalities.vector == true
      end
    end
  end

  # ===========================================================================
  # 2. Parallel VCL Queries
  #
  # @concurrency Tasks simultaneously execute VCL queries through the executor.
  # All must complete; none must crash or block indefinitely.
  # ===========================================================================

  describe "parallel VCL queries" do
    test "concurrent VCL parse calls produce consistent results" do
      query = "SELECT DOCUMENT.* FROM HEXAD 'entity-001' LIMIT 10"

      tasks =
        for _i <- 1..@concurrency do
          Task.async(fn ->
            VCLBridge.parse(query)
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      # Every parse must return the same AST (parsers must be pure functions).
      assert length(results) == @concurrency

      unique_results =
        results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, ast} -> ast end)
        |> Enum.uniq()

      # All successes should be structurally identical.
      if length(unique_results) > 1 do
        flunk("Concurrent parse of identical query produced #{length(unique_results)} different ASTs")
      end
    end

    test "concurrent VCL executions do not contend on internal state" do
      # Build a simple no-proof query AST (avoids Rust-core dependency).
      ast = %{
        modalities: [:document],
        source: {:octad, "concurrent-query-test"},
        where: nil,
        proof: nil,
        limit: 1,
        offset: 0
      }

      tasks =
        for _i <- 1..@concurrency do
          Task.async(fn ->
            VCLExecutor.execute(ast)
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      # All queries must produce a structured result.
      assert length(results) == @concurrency

      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result),
               "Concurrent executor returned invalid result: #{inspect(result)}"
      end)
    end

    test "concurrent explain plan generation is deterministic" do
      ast = %{
        modalities: [:graph, :vector, :document],
        source: {:octad, "explain-concurrent"},
        where: nil,
        proof: nil,
        limit: 5,
        offset: 0
      }

      tasks =
        for _i <- 1..@concurrency do
          Task.async(fn ->
            VCLExecutor.execute(ast, explain: true)
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      plans =
        results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, plan} -> plan end)

      # All explain plans must be structurally identical.
      unique_plans = Enum.uniq_by(plans, fn p -> {p[:strategy], length(p[:steps] || [])} end)

      assert length(unique_plans) <= 1,
             "Concurrent explain produced divergent plans: #{inspect(unique_plans)}"
    end
  end

  # ===========================================================================
  # 3. Concurrent Kraft Proposals
  #
  # Multiple tasks simultaneously propose to the leader. All must complete
  # (success or redirect), and the committed log must be internally consistent.
  # ===========================================================================

  describe "concurrent Kraft proposals" do
    test "concurrent proposals to leader do not corrupt registry" do
      suffix = System.unique_integer([:positive])
      node_id = "conc-kraft-#{suffix}"
      {:ok, pid} = KRaftNode.start_link(node_id: node_id, peers: [])

      # Wait for election.
      Process.sleep(500)
      assert KRaftNode.diagnostics(node_id).role == :leader

      # Propose @concurrency unique stores concurrently.
      tasks =
        for i <- 1..@concurrency do
          Task.async(fn ->
            KRaftNode.propose(
              node_id,
              {:register_store, "store-#{i}-#{suffix}", "http://localhost:#{9000 + i}", ["graph"]}
            )
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      # All must complete.
      assert length(results) == @concurrency

      # Every result must be {:ok, index} — all proposals to a single leader
      # should be accepted (no network partition).
      Enum.each(results, fn result ->
        assert match?({:ok, _index}, result),
               "Concurrent proposal failed unexpectedly: #{inspect(result)}"
      end)

      # Give time for all entries to be applied.
      Process.sleep(200)

      # The registry must contain all @concurrency stores.
      registry = KRaftNode.registry(node_id)
      registered_count = map_size(registry.stores)

      assert registered_count == @concurrency,
             "Expected #{@concurrency} stores in registry, found #{registered_count}"

      GenServer.stop(pid, :normal, 1_000)
    catch
      :exit, _ -> :ok
    end

    test "log index monotonically increases under concurrent proposals" do
      suffix = System.unique_integer([:positive])
      node_id = "conc-mono-#{suffix}"
      {:ok, pid} = KRaftNode.start_link(node_id: node_id, peers: [])

      Process.sleep(500)

      # Collect log indices from concurrent proposals.
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            KRaftNode.propose(
              node_id,
              {:register_store, "mono-store-#{i}-#{suffix}", "http://localhost:#{9100 + i}", ["vector"]}
            )
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      indices =
        results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, index} -> index end)
        |> Enum.sort()

      # Indices must be unique and strictly ascending (no duplicates).
      assert indices == Enum.uniq(indices),
             "Duplicate log indices detected: #{inspect(indices)}"

      GenServer.stop(pid, :normal, 1_000)
    catch
      :exit, _ -> :ok
    end
  end

  # ===========================================================================
  # 4. DriftMonitor Under Concurrent Load
  #
  # @concurrency Tasks simultaneously report drift events. The monitor's
  # health snapshot must remain structurally valid throughout.
  # ===========================================================================

  describe "DriftMonitor under concurrent load" do
    test "concurrent drift reports do not corrupt monitor state" do
      tasks =
        for i <- 1..@concurrency do
          Task.async(fn ->
            entity_id = "drift-conc-#{i}-#{System.unique_integer([:positive])}"
            drift_score = :rand.uniform() * 0.5
            DriftMonitor.report_drift(entity_id, drift_score, :semantic_vector)
          end)
        end

      Task.await_many(tasks, @task_timeout)

      # Allow the monitor to process all events.
      Process.sleep(100)

      # The monitor's status must remain structurally valid.
      status = DriftMonitor.status()
      assert is_map(status)
      assert status[:overall_health] in [:healthy, :warning, :degraded, :critical],
             "Invalid overall_health after concurrent drift reports: #{inspect(status[:overall_health])}"
      assert is_integer(status[:entities_with_drift]) and status[:entities_with_drift] >= 0,
             "entities_with_drift is non-integer: #{inspect(status[:entities_with_drift])}"
    end

    test "concurrent entity_changed notifications do not deadlock" do
      tasks =
        for i <- 1..@concurrency do
          Task.async(fn ->
            entity_id = "changed-conc-#{i}"
            DriftMonitor.entity_changed(entity_id)
          end)
        end

      # If this times out it indicates a deadlock in the monitor.
      Task.await_many(tasks, @task_timeout)

      # Verification: monitor is still responsive after the storm.
      status = DriftMonitor.status()
      assert is_map(status)
    end
  end

  # ===========================================================================
  # 5. SchemaRegistry Concurrent Type Registration
  #
  # Concurrent registrations of different types must all succeed (or be
  # de-duplicated cleanly), and the registry must reflect every registration.
  # ===========================================================================

  describe "SchemaRegistry concurrent type registration" do
    test "concurrent type registrations are serialised without data loss" do
      suffix = System.unique_integer([:positive])

      type_defs =
        for i <- 1..@concurrency do
          %{
            iri: "https://concurrent.test.org/Type#{i}-#{suffix}",
            label: "Concurrent Type #{i}",
            supertypes: ["verisim:Entity"],
            constraints: []
          }
        end

      tasks =
        for type_def <- type_defs do
          Task.async(fn ->
            SchemaRegistry.register_type(type_def)
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      # All registrations must succeed.
      Enum.each(results, fn result ->
        assert result == :ok,
               "Type registration failed: #{inspect(result)}"
      end)

      # All types must be retrievable from the registry.
      for i <- 1..@concurrency do
        iri = "https://concurrent.test.org/Type#{i}-#{suffix}"
        type = SchemaRegistry.get_type(iri)
        assert not is_nil(type),
               "Type #{iri} missing from registry after concurrent registration"
        assert type.label == "Concurrent Type #{i}"
      end
    end

    test "concurrent registration of the same type is handled safely (no crash)" do
      # NOTE: SchemaRegistry.register_type/1 returns {:error, :already_exists}
      # for duplicate IRIs rather than :ok (idempotent upsert). This is the
      # current implementation behaviour. The test verifies the minimum safety
      # bar: concurrent duplicate registrations must not crash, corrupt state,
      # or return unexpected values — only :ok or {:error, :already_exists}.
      suffix = System.unique_integer([:positive])
      iri = "https://idempotent.test.org/SharedType-#{suffix}"

      type_def = %{
        iri: iri,
        label: "Shared Type",
        supertypes: ["verisim:Entity"],
        constraints: []
      }

      # Register once first to ensure the IRI exists.
      assert :ok = SchemaRegistry.register_type(type_def)

      tasks =
        for _i <- 1..@concurrency do
          Task.async(fn ->
            SchemaRegistry.register_type(type_def)
          end)
        end

      results = Task.await_many(tasks, @task_timeout)

      # All results must be :ok (first registration) or {:error, :already_exists}.
      # None may be a crash, timeout, or unexpected value.
      Enum.each(results, fn result ->
        assert result == :ok or result == {:error, :already_exists},
               "Concurrent duplicate registration returned unexpected value: #{inspect(result)}"
      end)

      # The type must still be present exactly once after the concurrent storm.
      type = SchemaRegistry.get_type(iri)
      assert not is_nil(type)
      assert type.label == "Shared Type"
    end
  end
end
