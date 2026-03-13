# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttp.DatabaseRegistryTest do
  @moduledoc """
  Tests for the DatabaseRegistry GenServer.
  Covers CRUD operations on database handle storage.
  """

  use ExUnit.Case, async: false

  alias LithHttp.DatabaseRegistry

  @moduletag :capture_log

  # ============================================================
  # Put / Get
  # ============================================================

  describe "put/3 and get/1" do
    test "stores and retrieves a database handle" do
      handle = make_ref()
      assert :ok = DatabaseRegistry.put("test_db_1", handle)
      assert DatabaseRegistry.get("test_db_1") == handle
    end

    test "stores handle with metadata" do
      handle = make_ref()
      metadata = %{name: "my_db", description: "A test database"}
      assert :ok = DatabaseRegistry.put("test_db_2", handle, metadata)
      assert DatabaseRegistry.get("test_db_2") == handle
    end

    test "returns nil for non-existent db_id" do
      assert DatabaseRegistry.get("nonexistent_db_id") == nil
    end

    test "overwrites existing entry" do
      handle1 = make_ref()
      handle2 = make_ref()
      DatabaseRegistry.put("test_db_overwrite", handle1)
      DatabaseRegistry.put("test_db_overwrite", handle2)
      assert DatabaseRegistry.get("test_db_overwrite") == handle2
    end
  end

  # ============================================================
  # Metadata
  # ============================================================

  describe "get_metadata/1" do
    test "returns metadata for existing entry" do
      handle = make_ref()
      metadata = %{name: "meta_db", description: "Has metadata"}
      DatabaseRegistry.put("meta_db_1", handle, metadata)

      assert {:ok, ^metadata} = DatabaseRegistry.get_metadata("meta_db_1")
    end

    test "returns empty map when no metadata provided" do
      handle = make_ref()
      DatabaseRegistry.put("meta_db_2", handle)
      assert {:ok, %{}} = DatabaseRegistry.get_metadata("meta_db_2")
    end

    test "returns error for non-existent entry" do
      assert {:error, :not_found} = DatabaseRegistry.get_metadata("nonexistent_meta_db")
    end
  end

  # ============================================================
  # Delete
  # ============================================================

  describe "delete/1" do
    test "removes an existing entry" do
      handle = make_ref()
      DatabaseRegistry.put("del_db_1", handle)
      assert DatabaseRegistry.get("del_db_1") == handle

      assert :ok = DatabaseRegistry.delete("del_db_1")
      assert DatabaseRegistry.get("del_db_1") == nil
    end

    test "succeeds even if entry does not exist" do
      assert :ok = DatabaseRegistry.delete("never_existed")
    end
  end

  # ============================================================
  # List
  # ============================================================

  describe "list/0" do
    test "returns list of database entries" do
      # Store a couple known entries
      handle_a = make_ref()
      handle_b = make_ref()
      DatabaseRegistry.put("list_db_a", handle_a, %{name: "DB A", description: "First"})
      DatabaseRegistry.put("list_db_b", handle_b, %{name: "DB B", description: "Second"})

      list = DatabaseRegistry.list()
      assert is_list(list)

      # Verify our entries are in the list
      db_ids = Enum.map(list, & &1.db_id)
      assert "list_db_a" in db_ids
      assert "list_db_b" in db_ids

      entry_a = Enum.find(list, &(&1.db_id == "list_db_a"))
      assert entry_a.name == "DB A"
      assert entry_a.description == "First"
      assert %DateTime{} = entry_a.created_at
    end
  end
end
