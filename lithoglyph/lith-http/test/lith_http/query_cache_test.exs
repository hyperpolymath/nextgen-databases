# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttp.QueryCacheTest do
  @moduledoc """
  Tests for the QueryCache GenServer.
  Covers cache get/put, TTL expiration, invalidation,
  query key generation, and statistics.
  """

  use ExUnit.Case, async: false

  alias LithHttp.QueryCache

  @moduletag :capture_log

  setup do
    QueryCache.clear_all()
    # Brief pause for async cast to complete
    Process.sleep(50)
    :ok
  end

  # ============================================================
  # Basic get / put
  # ============================================================

  describe "get/1 and put/2" do
    test "returns :miss for non-existent key" do
      assert :miss = QueryCache.get("does_not_exist")
    end

    test "stores and retrieves a value" do
      QueryCache.put("basic_key", %{data: "hello"})
      Process.sleep(50)
      assert {:ok, %{data: "hello"}} = QueryCache.get("basic_key")
    end

    test "stores complex values" do
      value = %{
        features: [%{id: "feat_1", type: "Point"}],
        bbox: [0.0, 0.0, 10.0, 10.0],
        count: 42
      }
      QueryCache.put("complex_key", value)
      Process.sleep(50)
      assert {:ok, ^value} = QueryCache.get("complex_key")
    end
  end

  # ============================================================
  # TTL expiration
  # ============================================================

  describe "TTL expiration" do
    test "entry expires after TTL" do
      # Set a very short TTL (1 second)
      QueryCache.put("ttl_key", %{data: "ephemeral"}, 1)
      Process.sleep(50)
      assert {:ok, _} = QueryCache.get("ttl_key")

      # Wait for expiry
      Process.sleep(1100)
      assert :miss = QueryCache.get("ttl_key")
    end
  end

  # ============================================================
  # Invalidation
  # ============================================================

  describe "invalidate/1" do
    test "removes a specific key" do
      QueryCache.put("inv_key", %{data: "remove_me"})
      Process.sleep(50)
      assert {:ok, _} = QueryCache.get("inv_key")

      assert :ok = QueryCache.invalidate("inv_key")
      assert :miss = QueryCache.get("inv_key")
    end
  end

  describe "clear_all/0" do
    test "removes all entries" do
      for i <- 1..5 do
        QueryCache.put("clear_#{i}", %{i: i})
      end
      Process.sleep(50)

      QueryCache.clear_all()
      Process.sleep(50)

      for i <- 1..5 do
        assert :miss = QueryCache.get("clear_#{i}")
      end
    end
  end

  # ============================================================
  # Query key generation
  # ============================================================

  describe "query_key/3" do
    test "generates deterministic keys for same params" do
      params = %{series_id: "temp", start: 1000, end: 2000}
      key1 = QueryCache.query_key("db1", :timeseries, params)
      key2 = QueryCache.query_key("db1", :timeseries, params)
      assert key1 == key2
    end

    test "generates different keys for different db_ids" do
      params = %{series_id: "temp", start: 1000, end: 2000}
      key1 = QueryCache.query_key("db1", :timeseries, params)
      key2 = QueryCache.query_key("db2", :timeseries, params)
      assert key1 != key2
    end

    test "generates different keys for different query types" do
      params = %{bbox: {0, 0, 10, 10}}
      key1 = QueryCache.query_key("db1", :geo_bbox, params)
      key2 = QueryCache.query_key("db1", :timeseries, params)
      assert key1 != key2
    end

    test "generates different keys for different params" do
      key1 = QueryCache.query_key("db1", :timeseries, %{start: 0, end: 100})
      key2 = QueryCache.query_key("db1", :timeseries, %{start: 0, end: 200})
      assert key1 != key2
    end

    test "returns a hex-encoded string" do
      key = QueryCache.query_key("db1", :test, %{})
      assert is_binary(key)
      assert Regex.match?(~r/^[0-9a-f]+$/, key)
    end
  end

  # ============================================================
  # Stats
  # ============================================================

  describe "stats/0" do
    test "returns cache statistics" do
      stats = QueryCache.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :max_size)
      assert Map.has_key?(stats, :hits)
      assert Map.has_key?(stats, :misses)
      assert Map.has_key?(stats, :evictions)
      assert Map.has_key?(stats, :hit_rate)
      assert Map.has_key?(stats, :memory_bytes)
      assert Map.has_key?(stats, :memory_mb)
    end

    test "reports correct size after insertions" do
      for i <- 1..10 do
        QueryCache.put("stats_#{i}", %{i: i})
      end
      Process.sleep(100)
      stats = QueryCache.stats()
      assert stats.size >= 10
    end
  end
end
