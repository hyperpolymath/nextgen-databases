# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttp.SpatialIndexTest do
  @moduledoc """
  Tests for the R-tree spatial index GenServer.
  Covers index creation, insertion, querying, deletion, and edge cases.
  """

  use ExUnit.Case, async: false

  alias LithHttp.SpatialIndex

  @moduletag :capture_log

  setup do
    # Use a unique db_id per test to avoid cross-test state pollution
    db_id = "test_spatial_#{System.unique_integer([:positive])}"
    SpatialIndex.create_index(db_id)
    on_exit(fn -> SpatialIndex.drop_index(db_id) end)
    {:ok, db_id: db_id}
  end

  # ============================================================
  # Index lifecycle
  # ============================================================

  describe "create_index/1 and drop_index/1" do
    test "creates and drops an index" do
      db = "lifecycle_test_#{System.unique_integer([:positive])}"
      assert :ok = SpatialIndex.create_index(db)
      assert {:ok, []} = SpatialIndex.query(db, {0, 0, 100, 100})
      assert :ok = SpatialIndex.drop_index(db)
    end

    test "query returns error for non-existent index" do
      assert {:error, :index_not_found} =
               SpatialIndex.query("totally_nonexistent_db", {0, 0, 1, 1})
    end

    test "insert returns error for non-existent index" do
      assert {:error, :index_not_found} =
               SpatialIndex.insert("nonexistent_insert", "feat_1", {0, 0, 1, 1})
    end
  end

  # ============================================================
  # Insert and query
  # ============================================================

  describe "insert/3 and query/2" do
    test "inserts and queries a single point feature", %{db_id: db_id} do
      assert :ok = SpatialIndex.insert(db_id, "feat_point", {5.0, 5.0, 5.0, 5.0})
      assert {:ok, results} = SpatialIndex.query(db_id, {0.0, 0.0, 10.0, 10.0})
      assert "feat_point" in results
    end

    test "returns empty list for non-intersecting query", %{db_id: db_id} do
      SpatialIndex.insert(db_id, "feat_far", {100.0, 100.0, 110.0, 110.0})
      assert {:ok, []} = SpatialIndex.query(db_id, {0.0, 0.0, 10.0, 10.0})
    end

    test "inserts multiple features and queries subset", %{db_id: db_id} do
      SpatialIndex.insert(db_id, "a", {1.0, 1.0, 3.0, 3.0})
      SpatialIndex.insert(db_id, "b", {5.0, 5.0, 7.0, 7.0})
      SpatialIndex.insert(db_id, "c", {50.0, 50.0, 60.0, 60.0})

      assert {:ok, results} = SpatialIndex.query(db_id, {0.0, 0.0, 10.0, 10.0})
      assert "a" in results
      assert "b" in results
      refute "c" in results
    end

    test "handles overlapping bounding boxes", %{db_id: db_id} do
      SpatialIndex.insert(db_id, "overlap1", {0.0, 0.0, 10.0, 10.0})
      SpatialIndex.insert(db_id, "overlap2", {5.0, 5.0, 15.0, 15.0})

      # Query should find both
      assert {:ok, results} = SpatialIndex.query(db_id, {4.0, 4.0, 6.0, 6.0})
      assert "overlap1" in results
      assert "overlap2" in results
    end

    test "handles edge-touching bounding boxes", %{db_id: db_id} do
      SpatialIndex.insert(db_id, "edge", {10.0, 10.0, 20.0, 20.0})
      # Query bbox touches at corner (10,10)
      assert {:ok, results} = SpatialIndex.query(db_id, {0.0, 0.0, 10.0, 10.0})
      assert "edge" in results
    end
  end

  # ============================================================
  # Delete
  # ============================================================

  describe "delete/2" do
    test "removes a feature from the index", %{db_id: db_id} do
      SpatialIndex.insert(db_id, "to_delete", {5.0, 5.0, 5.0, 5.0})
      assert {:ok, results} = SpatialIndex.query(db_id, {0.0, 0.0, 10.0, 10.0})
      assert "to_delete" in results

      assert :ok = SpatialIndex.delete(db_id, "to_delete")
      assert {:ok, results} = SpatialIndex.query(db_id, {0.0, 0.0, 10.0, 10.0})
      refute "to_delete" in results
    end

    test "delete of non-existent feature is a no-op", %{db_id: db_id} do
      assert :ok = SpatialIndex.delete(db_id, "never_existed")
    end

    test "delete returns error for non-existent index" do
      assert {:error, :index_not_found} =
               SpatialIndex.delete("no_such_idx", "feat_1")
    end
  end

  # ============================================================
  # Node splitting (stress test)
  # ============================================================

  describe "node splitting" do
    test "handles more than max_entries_per_node (8) insertions", %{db_id: db_id} do
      # Insert 20 features to trigger at least one node split
      for i <- 1..20 do
        x = i * 1.0
        SpatialIndex.insert(db_id, "split_#{i}", {x, x, x + 1.0, x + 1.0})
      end

      # All features in range should be found
      assert {:ok, results} = SpatialIndex.query(db_id, {0.0, 0.0, 25.0, 25.0})
      assert length(results) == 20
    end
  end
end
