# SPDX-License-Identifier: PMPL-1.0-or-later
# Benchmark: R-tree Spatial Index Performance

alias LithHttp.SpatialIndex

# Configuration
db_id = "bench_spatial"
num_features = 10_000
query_count = 1_000

IO.puts("=== R-tree Spatial Index Benchmark ===")
IO.puts("Features: #{num_features}")
IO.puts("Queries: #{query_count}")
IO.puts("")

# Setup: Create index
IO.puts("Setting up spatial index...")
SpatialIndex.create_index(db_id)

# Benchmark 1: Insertion Performance
IO.puts("\n1. Insertion Performance")
{insert_time_us, _} = :timer.tc(fn ->
  for i <- 1..num_features do
    feature_id = "feat_#{i}"
    # Random bounding box in range [0, 1000]
    minx = :rand.uniform(900)
    miny = :rand.uniform(900)
    maxx = minx + :rand.uniform(100)
    maxy = miny + :rand.uniform(100)
    bbox = {minx, miny, maxx, maxy}

    SpatialIndex.insert(db_id, feature_id, bbox)
  end
end)

insert_time_ms = insert_time_us / 1_000
inserts_per_sec = num_features / (insert_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(insert_time_ms, 2)} ms")
IO.puts("  Per insert: #{Float.round(insert_time_ms / num_features, 4)} ms")
IO.puts("  Throughput: #{Float.round(inserts_per_sec, 0)} inserts/sec")

# Benchmark 2: Point Query Performance (small bbox)
IO.puts("\n2. Point Query Performance (small bboxes)")
{query_time_us, results} = :timer.tc(fn ->
  for _i <- 1..query_count do
    # Random 10x10 query box
    minx = :rand.uniform(990)
    miny = :rand.uniform(990)
    bbox = {minx, miny, minx + 10, miny + 10}

    case SpatialIndex.query(db_id, bbox) do
      {:ok, feature_ids} -> length(feature_ids)
      _ -> 0
    end
  end
end)

query_time_ms = query_time_us / 1_000
avg_results = Enum.sum(results) / query_count
queries_per_sec = query_count / (query_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(query_time_ms, 2)} ms")
IO.puts("  Per query: #{Float.round(query_time_ms / query_count, 4)} ms")
IO.puts("  Throughput: #{Float.round(queries_per_sec, 0)} queries/sec")
IO.puts("  Avg results: #{Float.round(avg_results, 1)} features")

# Benchmark 3: Range Query Performance (large bbox)
IO.puts("\n3. Range Query Performance (large bboxes)")
{range_time_us, range_results} = :timer.tc(fn ->
  for _i <- 1..query_count do
    # Random 100x100 query box
    minx = :rand.uniform(900)
    miny = :rand.uniform(900)
    bbox = {minx, miny, minx + 100, miny + 100}

    case SpatialIndex.query(db_id, bbox) do
      {:ok, feature_ids} -> length(feature_ids)
      _ -> 0
    end
  end
end)

range_time_ms = range_time_us / 1_000
avg_range_results = Enum.sum(range_results) / query_count
range_queries_per_sec = query_count / (range_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(range_time_ms, 2)} ms")
IO.puts("  Per query: #{Float.round(range_time_ms / query_count, 4)} ms")
IO.puts("  Throughput: #{Float.round(range_queries_per_sec, 0)} queries/sec")
IO.puts("  Avg results: #{Float.round(avg_range_results, 1)} features")

# Benchmark 4: Delete Performance
IO.puts("\n4. Delete Performance")
features_to_delete = Enum.take_random(1..num_features, 1_000)

{delete_time_us, _} = :timer.tc(fn ->
  for i <- features_to_delete do
    feature_id = "feat_#{i}"
    SpatialIndex.delete(db_id, feature_id)
  end
end)

delete_time_ms = delete_time_us / 1_000
deletes_per_sec = length(features_to_delete) / (delete_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(delete_time_ms, 2)} ms")
IO.puts("  Per delete: #{Float.round(delete_time_ms / length(features_to_delete), 4)} ms")
IO.puts("  Throughput: #{Float.round(deletes_per_sec, 0)} deletes/sec")

# Cleanup
IO.puts("\n5. Cleanup")
SpatialIndex.drop_index(db_id)
IO.puts("  Index dropped")

IO.puts("\n=== Benchmark Complete ===")
