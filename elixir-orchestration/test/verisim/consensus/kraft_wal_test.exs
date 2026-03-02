# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Consensus.KRaftWALTest do
  @moduledoc """
  Tests for the KRaft Write-Ahead Log.

  Verifies that the WAL correctly:
  1. Persists and recovers durable Raft state (currentTerm, votedFor)
  2. Appends and recovers log entries
  3. Handles snapshots with WAL truncation
  4. Recovers correctly after simulated crashes
  5. Handles edge cases (empty WAL, corrupt data, missing files)
  """

  use ExUnit.Case, async: true

  alias VeriSim.Consensus.KRaftWAL

  setup do
    # Create a unique temp directory for each test
    dir = Path.join(System.tmp_dir!(), "kraft_wal_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, wal_path: dir}
  end

  # ===========================================================================
  # init/1
  # ===========================================================================

  describe "init/1" do
    test "creates WAL directory", %{wal_path: wal_path} do
      assert :ok = KRaftWAL.init(wal_path)
      assert File.dir?(wal_path)
    end

    test "succeeds if directory already exists", %{wal_path: wal_path} do
      File.mkdir_p!(wal_path)
      assert :ok = KRaftWAL.init(wal_path)
    end

    test "nil path returns :ok" do
      assert :ok = KRaftWAL.init(nil)
    end
  end

  # ===========================================================================
  # persist_state/3 and recover/1 — durable state
  # ===========================================================================

  describe "persist_state/3 + recover/1 — durable state" do
    test "persists and recovers currentTerm and votedFor", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      KRaftWAL.persist_state(wal_path, 5, "node-2")

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert recovered.current_term == 5
      assert recovered.voted_for == "node-2"
    end

    test "persists nil votedFor", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      KRaftWAL.persist_state(wal_path, 3, nil)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert recovered.current_term == 3
      assert recovered.voted_for == nil
    end

    test "overwrites previous state", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      KRaftWAL.persist_state(wal_path, 1, "node-1")
      KRaftWAL.persist_state(wal_path, 2, "node-3")

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert recovered.current_term == 2
      assert recovered.voted_for == "node-3"
    end

    test "nil path is a no-op" do
      assert :ok = KRaftWAL.persist_state(nil, 5, "node-2")
    end
  end

  # ===========================================================================
  # append_entry/2 and recover/1 — log entries
  # ===========================================================================

  describe "append_entry/2 + recover/1 — log entries" do
    test "appends and recovers a single entry", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      entry = %{
        term: 1,
        index: 1,
        command: {:register_store, "s1", "http://localhost:9000", ["graph"]},
        timestamp: 1_000_000
      }

      assert :ok = KRaftWAL.append_entry(wal_path, entry)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert length(recovered.log) == 1

      [recovered_entry] = recovered.log
      assert recovered_entry.term == 1
      assert recovered_entry.index == 1
      assert recovered_entry.command == {:register_store, "s1", "http://localhost:9000", ["graph"]}
    end

    test "appends multiple entries sequentially", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      for i <- 1..5 do
        entry = %{
          term: 1,
          index: i,
          command: :noop,
          timestamp: 1_000_000 + i
        }

        KRaftWAL.append_entry(wal_path, entry)
      end

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert length(recovered.log) == 5
      assert Enum.map(recovered.log, & &1.index) == [1, 2, 3, 4, 5]
    end

    test "nil path is a no-op" do
      entry = %{term: 1, index: 1, command: :noop}
      assert :ok = KRaftWAL.append_entry(nil, entry)
    end
  end

  # ===========================================================================
  # append_entries/2 — batch append
  # ===========================================================================

  describe "append_entries/2 — batch append" do
    test "appends multiple entries in one write", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      entries =
        for i <- 1..3 do
          %{term: 1, index: i, command: :noop, timestamp: 1_000_000 + i}
        end

      assert :ok = KRaftWAL.append_entries(wal_path, entries)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert length(recovered.log) == 3
    end

    test "empty list is a no-op", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      assert :ok = KRaftWAL.append_entries(wal_path, [])
    end
  end

  # ===========================================================================
  # Command serialization round-trip
  # ===========================================================================

  describe "command serialization round-trip" do
    test "noop", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      entry = %{term: 1, index: 1, command: :noop}
      KRaftWAL.append_entry(wal_path, entry)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert hd(recovered.log).command == :noop
    end

    test "register_store", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      entry = %{
        term: 1,
        index: 1,
        command: {:register_store, "store-1", "http://host:8080", ["graph", "vector"]}
      }

      KRaftWAL.append_entry(wal_path, entry)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert hd(recovered.log).command ==
               {:register_store, "store-1", "http://host:8080", ["graph", "vector"]}
    end

    test "unregister_store", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      entry = %{term: 1, index: 1, command: {:unregister_store, "store-1"}}
      KRaftWAL.append_entry(wal_path, entry)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert hd(recovered.log).command == {:unregister_store, "store-1"}
    end

    test "map_hexad", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      locations = ["store-1", "store-2", "store-3"]
      entry = %{term: 1, index: 1, command: {:map_hexad, "hex-1", locations}}
      KRaftWAL.append_entry(wal_path, entry)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert hd(recovered.log).command == {:map_hexad, "hex-1", locations}
    end

    test "unmap_hexad", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      entry = %{term: 1, index: 1, command: {:unmap_hexad, "hex-1"}}
      KRaftWAL.append_entry(wal_path, entry)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert hd(recovered.log).command == {:unmap_hexad, "hex-1"}
    end

    test "update_trust", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      entry = %{term: 1, index: 1, command: {:update_trust, "store-1", 0.85}}
      KRaftWAL.append_entry(wal_path, entry)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert hd(recovered.log).command == {:update_trust, "store-1", 0.85}
    end
  end

  # ===========================================================================
  # save_snapshot/4 + recover/1
  # ===========================================================================

  describe "save_snapshot/4 + recover/1" do
    test "saves and recovers snapshot with registry state", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      # Write 5 entries
      for i <- 1..5 do
        entry = %{term: 1, index: i, command: :noop}
        KRaftWAL.append_entry(wal_path, entry)
      end

      # Create a snapshot at index 3
      registry = %{
        stores: %{
          "s1" => %{
            store_id: "s1",
            endpoint: "http://localhost:9000",
            modalities: ["graph"],
            trust_level: 0.95
          }
        },
        mappings: %{}
      }

      KRaftWAL.save_snapshot(wal_path, registry, 3, 1)

      {:ok, recovered} = KRaftWAL.recover(wal_path)

      # Snapshot state
      assert recovered.snapshot_index == 3
      assert recovered.snapshot_term == 1
      assert recovered.registry.stores["s1"].endpoint == "http://localhost:9000"
      assert recovered.registry.stores["s1"].trust_level == 0.95

      # Only entries after snapshot should remain in log
      assert length(recovered.log) == 2
      assert Enum.map(recovered.log, & &1.index) == [4, 5]
    end

    test "snapshot truncates WAL entries at or before snapshot index", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      for i <- 1..10 do
        entry = %{term: 1, index: i, command: :noop}
        KRaftWAL.append_entry(wal_path, entry)
      end

      KRaftWAL.save_snapshot(wal_path, %{stores: %{}, mappings: %{}}, 7, 1)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert length(recovered.log) == 3
      assert Enum.map(recovered.log, & &1.index) == [8, 9, 10]
    end
  end

  # ===========================================================================
  # truncate_after/2
  # ===========================================================================

  describe "truncate_after/2" do
    test "keeps entries up to given index", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      for i <- 1..5 do
        entry = %{term: 1, index: i, command: :noop}
        KRaftWAL.append_entry(wal_path, entry)
      end

      KRaftWAL.truncate_after(wal_path, 3)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert length(recovered.log) == 3
      assert Enum.map(recovered.log, & &1.index) == [1, 2, 3]
    end

    test "truncate to 0 removes all entries", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      for i <- 1..3 do
        entry = %{term: 1, index: i, command: :noop}
        KRaftWAL.append_entry(wal_path, entry)
      end

      KRaftWAL.truncate_after(wal_path, 0)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert recovered.log == []
    end

    test "truncate + append simulates follower log conflict resolution", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      # Follower has entries from term 1
      for i <- 1..5 do
        entry = %{term: 1, index: i, command: :noop}
        KRaftWAL.append_entry(wal_path, entry)
      end

      # New leader sends entries starting at index 3 with term 2
      KRaftWAL.truncate_after(wal_path, 2)

      new_entries =
        for i <- 3..6 do
          %{term: 2, index: i, command: :noop}
        end

      KRaftWAL.append_entries(wal_path, new_entries)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert length(recovered.log) == 6
      assert Enum.map(recovered.log, & &1.index) == [1, 2, 3, 4, 5, 6]
      # First 2 entries from term 1, remaining from term 2
      assert Enum.map(recovered.log, & &1.term) == [1, 1, 2, 2, 2, 2]
    end

    test "nil path is a no-op" do
      assert :ok = KRaftWAL.truncate_after(nil, 5)
    end
  end

  # ===========================================================================
  # Recovery edge cases
  # ===========================================================================

  describe "recovery edge cases" do
    test "recover from non-existent directory returns nil", %{wal_path: wal_path} do
      {:ok, result} = KRaftWAL.recover(wal_path)
      assert result == nil
    end

    test "recover from empty directory returns defaults", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      assert recovered.current_term == 0
      assert recovered.voted_for == nil
      assert recovered.log == []
      assert recovered.registry == nil
      assert recovered.snapshot_index == 0
      assert recovered.snapshot_term == 0
    end

    test "recover skips corrupt WAL lines", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)

      # Write a valid entry
      entry = %{term: 1, index: 1, command: :noop}
      KRaftWAL.append_entry(wal_path, entry)

      # Append a corrupt line directly
      wal_file = Path.join(wal_path, "wal.jsonl")
      File.write!(wal_file, "this is not valid json\n", [:append])

      # Write another valid entry
      entry2 = %{term: 1, index: 2, command: :noop}
      KRaftWAL.append_entry(wal_path, entry2)

      {:ok, recovered} = KRaftWAL.recover(wal_path)
      # Should recover 2 valid entries, skipping the corrupt line
      assert length(recovered.log) == 2
    end

    test "recover with nil path returns nil" do
      {:ok, result} = KRaftWAL.recover(nil)
      assert result == nil
    end
  end

  # ===========================================================================
  # Full crash recovery simulation
  # ===========================================================================

  describe "full crash recovery simulation" do
    test "recovers complete state after simulated crash", %{wal_path: wal_path} do
      # Phase 1: Normal operation
      KRaftWAL.init(wal_path)
      KRaftWAL.persist_state(wal_path, 3, "node-2")

      entries = [
        %{term: 1, index: 1, command: {:register_store, "s1", "http://a:8080", ["graph"]}},
        %{term: 1, index: 2, command: {:register_store, "s2", "http://b:8080", ["vector"]}},
        %{term: 2, index: 3, command: {:map_hexad, "h1", ["s1", "s2"]}},
        %{term: 3, index: 4, command: :noop},
        %{term: 3, index: 5, command: {:update_trust, "s1", 0.9}}
      ]

      for entry <- entries, do: KRaftWAL.append_entry(wal_path, entry)

      # Phase 2: "Crash" — just forget everything in memory

      # Phase 3: Recovery
      {:ok, recovered} = KRaftWAL.recover(wal_path)

      assert recovered.current_term == 3
      assert recovered.voted_for == "node-2"
      assert length(recovered.log) == 5

      # Verify all commands survived
      commands = Enum.map(recovered.log, & &1.command)

      assert Enum.at(commands, 0) ==
               {:register_store, "s1", "http://a:8080", ["graph"]}

      assert Enum.at(commands, 1) ==
               {:register_store, "s2", "http://b:8080", ["vector"]}

      assert Enum.at(commands, 2) == {:map_hexad, "h1", ["s1", "s2"]}
      assert Enum.at(commands, 3) == :noop
      assert Enum.at(commands, 4) == {:update_trust, "s1", 0.9}
    end

    test "recovers after snapshot + additional entries", %{wal_path: wal_path} do
      KRaftWAL.init(wal_path)
      KRaftWAL.persist_state(wal_path, 5, nil)

      # Write entries 1-10
      for i <- 1..10 do
        entry = %{term: div(i - 1, 3) + 1, index: i, command: :noop}
        KRaftWAL.append_entry(wal_path, entry)
      end

      # Snapshot at index 7
      registry = %{
        stores: %{
          "s1" => %{
            store_id: "s1",
            endpoint: "http://host:8080",
            modalities: ["graph", "vector"],
            trust_level: 0.85
          }
        },
        mappings: %{
          "h1" => %{
            hexad_id: "h1",
            locations: ["s1"],
            primary_store: "s1"
          }
        }
      }

      KRaftWAL.save_snapshot(wal_path, registry, 7, 3)

      # Add entries 11-13 after snapshot
      for i <- 11..13 do
        entry = %{term: 5, index: i, command: :noop}
        KRaftWAL.append_entry(wal_path, entry)
      end

      # "Crash" and recover
      {:ok, recovered} = KRaftWAL.recover(wal_path)

      assert recovered.current_term == 5
      assert recovered.snapshot_index == 7
      assert recovered.snapshot_term == 3

      # Log should contain entries 8-13 (after snapshot)
      assert length(recovered.log) == 6
      assert Enum.map(recovered.log, & &1.index) == [8, 9, 10, 11, 12, 13]

      # Registry from snapshot
      assert recovered.registry.stores["s1"].trust_level == 0.85
      assert recovered.registry.mappings["h1"].primary_store == "s1"
    end
  end
end
