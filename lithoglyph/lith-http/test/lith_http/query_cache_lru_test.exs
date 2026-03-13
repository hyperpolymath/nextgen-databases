# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule LithHttp.QueryCacheLRUTest do
  use ExUnit.Case, async: false

  alias LithHttp.QueryCache

  @moduletag :capture_log

  describe "LRU eviction" do
    setup do
      # Clear cache before each test
      QueryCache.clear_all()
      :ok
    end

    test "evicts least recently used entry when cache is full" do
      # Cache max is 1000 entries (hardcoded in QueryCache)
      max_entries = 1000

      # Fill cache to capacity
      for i <- 1..max_entries do
        key = "key_#{i}"
        QueryCache.put(key, %{data: "value_#{i}"})
      end

      # Wait for async puts to complete
      Process.sleep(100)

      # Verify cache is full
      stats = QueryCache.stats()
      assert stats.size == max_entries

      # Access the first 100 keys to make them "recently used"
      for i <- 1..100 do
        key = "key_#{i}"
        assert {:ok, _} = QueryCache.get(key)
      end

      # Wait a bit to ensure last_access times are updated
      Process.sleep(100)

      # Now insert a new key - should evict one of the old keys (101-1000)
      QueryCache.put("key_new", %{data: "new_value"})
      Process.sleep(100)

      # The first 100 keys (recently accessed) should still be there
      for i <- 1..100 do
        key = "key_#{i}"
        result = QueryCache.get(key)
        assert {:ok, _} = result, "Key #{key} should still be cached (recently used)"
      end

      # At least one of the old keys (101-1000) should be evicted
      old_keys_cached = Enum.count(101..1000, fn i ->
        key = "key_#{i}"
        case QueryCache.get(key) do
          {:ok, _} -> true
          :miss -> false
        end
      end)

      # Should have evicted at least one old key
      assert old_keys_cached < 900,
        "Expected some old keys to be evicted, but #{old_keys_cached}/900 still cached"
    end

    test "evicts correct number of entries when inserting multiple" do
      max_entries = 1000

      # Fill cache
      for i <- 1..max_entries do
        QueryCache.put("key_#{i}", %{data: i})
      end

      Process.sleep(100)
      assert QueryCache.stats().size == max_entries

      # Insert 50 more keys
      for i <- 1001..1050 do
        QueryCache.put("key_#{i}", %{data: i})
      end

      Process.sleep(100)

      # Cache should still be at max
      stats = QueryCache.stats()
      assert stats.size == max_entries
      assert stats.evictions == 50
    end
  end
end
