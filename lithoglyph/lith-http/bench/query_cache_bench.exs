# SPDX-License-Identifier: PMPL-1.0-or-later
# Benchmark: Query Cache Performance & Hit Rate Analysis

alias LithHttp.QueryCache

# Configuration
num_unique_queries = 1_000
num_total_queries = 10_000
cache_size = 500

IO.puts("=== Query Cache Benchmark ===")
IO.puts("Unique queries: #{num_unique_queries}")
IO.puts("Total queries: #{num_total_queries}")
IO.puts("Cache size: #{cache_size}")
IO.puts("")

# Generate test data (simulating query results)
test_data = %{
  type: "FeatureCollection",
  features: Enum.map(1..100, fn i ->
    %{
      id: "feat_#{i}",
      type: "Feature",
      geometry: %{type: "Point", coordinates: [:rand.uniform(1000), :rand.uniform(1000)]},
      properties: %{value: :rand.uniform(100)}
    }
  end)
}

# Benchmark 1: Write Performance
IO.puts("1. Cache Write Performance")
cache_keys = Enum.map(1..num_unique_queries, fn i ->
  QueryCache.query_key("db_#{rem(i, 10)}", :geo_bbox, %{
    bbox: {:rand.uniform(1000), :rand.uniform(1000), :rand.uniform(1000), :rand.uniform(1000)},
    limit: 100
  })
end)

{write_time_us, _} = :timer.tc(fn ->
  for key <- cache_keys do
    QueryCache.put(key, test_data)
  end
end)

write_time_ms = write_time_us / 1_000
writes_per_sec = num_unique_queries / (write_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(write_time_ms, 2)} ms")
IO.puts("  Per write: #{Float.round(write_time_ms / num_unique_queries, 4)} ms")
IO.puts("  Throughput: #{Float.round(writes_per_sec, 0)} writes/sec")

# Benchmark 2: Read Performance (Cache Hits)
IO.puts("\n2. Cache Read Performance (all hits)")

{read_time_us, hits} = :timer.tc(fn ->
  for _i <- 1..num_total_queries do
    # Read random cached key (should always hit)
    key = Enum.random(cache_keys)
    case QueryCache.get(key) do
      {:ok, _data} -> 1
      :miss -> 0
    end
  end
end)

read_time_ms = read_time_us / 1_000
hit_count = Enum.sum(hits)
hit_rate = hit_count / num_total_queries * 100
reads_per_sec = num_total_queries / (read_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(read_time_ms, 2)} ms")
IO.puts("  Per read: #{Float.round(read_time_ms / num_total_queries, 4)} ms")
IO.puts("  Throughput: #{Float.round(reads_per_sec, 0)} reads/sec")
IO.puts("  Hit rate: #{Float.round(hit_rate, 1)}%")

# Benchmark 3: Mixed Workload (80% hits, 20% misses)
IO.puts("\n3. Mixed Workload (80% hits, 20% misses)")

# Create some keys that don't exist
missing_keys = Enum.map(1..200, fn i ->
  QueryCache.query_key("db_missing_#{i}", :geo_bbox, %{
    bbox: {:rand.uniform(1000), :rand.uniform(1000), :rand.uniform(1000), :rand.uniform(1000)},
    limit: 100
  })
end)

{mixed_time_us, mixed_results} = :timer.tc(fn ->
  for _i <- 1..num_total_queries do
    key = if :rand.uniform(100) <= 80 do
      Enum.random(cache_keys)  # 80% hits
    else
      Enum.random(missing_keys)  # 20% misses
    end

    case QueryCache.get(key) do
      {:ok, _data} -> :hit
      :miss -> :miss
    end
  end
end)

mixed_time_ms = mixed_time_us / 1_000
mixed_hits = Enum.count(mixed_results, &(&1 == :hit))
mixed_misses = Enum.count(mixed_results, &(&1 == :miss))
mixed_hit_rate = mixed_hits / num_total_queries * 100
mixed_reads_per_sec = num_total_queries / (mixed_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(mixed_time_ms, 2)} ms")
IO.puts("  Per read: #{Float.round(mixed_time_ms / num_total_queries, 4)} ms")
IO.puts("  Throughput: #{Float.round(mixed_reads_per_sec, 0)} reads/sec")
IO.puts("  Hits: #{mixed_hits} (#{Float.round(mixed_hit_rate, 1)}%)")
IO.puts("  Misses: #{mixed_misses} (#{Float.round(100 - mixed_hit_rate, 1)}%)")

# Benchmark 4: Cache Eviction (LRU behavior)
IO.puts("\n4. Cache Eviction Test (LRU behavior)")

# Fill cache beyond capacity
extra_keys = num_unique_queries - cache_size
IO.puts("  Cache capacity: #{cache_size}")
IO.puts("  Total keys: #{num_unique_queries}")
IO.puts("  Expected evictions: #{extra_keys}")

# Test if oldest keys were evicted
{eviction_time_us, eviction_results} = :timer.tc(fn ->
  # Check first 100 keys (should be evicted)
  oldest_keys = Enum.take(cache_keys, 100)
  oldest_hits = Enum.count(oldest_keys, fn key ->
    case QueryCache.get(key) do
      {:ok, _} -> true
      :miss -> false
    end
  end)

  # Check last 100 keys (should still be cached)
  newest_keys = Enum.take(cache_keys, -100)
  newest_hits = Enum.count(newest_keys, fn key ->
    case QueryCache.get(key) do
      {:ok, _} -> true
      :miss -> false
    end
  end)

  {oldest_hits, newest_hits}
end)

{oldest_hits, newest_hits} = eviction_results
eviction_time_ms = eviction_time_us / 1_000

IO.puts("  Eviction test time: #{Float.round(eviction_time_ms, 2)} ms")
IO.puts("  Oldest keys still cached: #{oldest_hits}/100")
IO.puts("  Newest keys still cached: #{newest_hits}/100")
IO.puts("  LRU working: #{if newest_hits > oldest_hits, do: "✓", else: "✗"}")

# Benchmark 5: Invalidation Performance
IO.puts("\n5. Cache Invalidation Performance")

# Invalidate by database
db_to_invalidate = "db_5"
{invalidate_time_us, _} = :timer.tc(fn ->
  QueryCache.invalidate_db(db_to_invalidate)
end)

invalidate_time_ms = invalidate_time_us / 1_000

IO.puts("  Invalidation time: #{Float.round(invalidate_time_ms, 4)} ms")
IO.puts("  Database invalidated: #{db_to_invalidate}")

# Verify invalidation worked
invalidated_count = Enum.count(cache_keys, fn key ->
  # Keys for db_5 should be invalidated
  if String.contains?(key, "db_5") do
    case QueryCache.get(key) do
      :miss -> true
      {:ok, _} -> false
    end
  else
    false
  end
end)

IO.puts("  Keys invalidated: #{invalidated_count}")

# Benchmark 6: Memory Footprint
IO.puts("\n6. Memory Footprint Analysis")

cache_info = :ets.info(:query_cache)
memory_words = cache_info[:memory]
memory_bytes = memory_words * :erlang.system_info(:wordsize)
memory_mb = memory_bytes / (1024 * 1024)

IO.puts("  ETS table size: #{cache_info[:size]} entries")
IO.puts("  Memory usage: #{Float.round(memory_mb, 2)} MB")
IO.puts("  Avg per entry: #{Float.round(memory_bytes / cache_info[:size] / 1024, 2)} KB")

IO.puts("\n=== Benchmark Complete ===")
