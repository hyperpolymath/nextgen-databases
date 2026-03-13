# SPDX-License-Identifier: PMPL-1.0-or-later
# Benchmark: B-tree Temporal Index Performance

alias LithHttp.TemporalIndex

# Configuration
db_id = "bench_temporal"
series_id = "sensor_01"
num_points = 50_000
query_count = 1_000

IO.puts("=== B-tree Temporal Index Benchmark ===")
IO.puts("Data points: #{num_points}")
IO.puts("Queries: #{query_count}")
IO.puts("")

# Setup: Create index
IO.puts("Setting up temporal index...")
TemporalIndex.create_index(db_id, series_id)

# Generate time range (30 days of data, 1 point per minute)
base_time = System.system_time(:second) - (30 * 24 * 60 * 60)

# Benchmark 1: Insertion Performance
IO.puts("\n1. Insertion Performance")
{insert_time_us, _} = :timer.tc(fn ->
  for i <- 1..num_points do
    point_id = "point_#{i}"
    # Time increments by ~1 minute
    timestamp_unix = base_time + (i * 60)

    TemporalIndex.insert(db_id, series_id, point_id, timestamp_unix)
  end
end)

insert_time_ms = insert_time_us / 1_000
inserts_per_sec = num_points / (insert_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(insert_time_ms, 2)} ms")
IO.puts("  Per insert: #{Float.round(insert_time_ms / num_points, 4)} ms")
IO.puts("  Throughput: #{Float.round(inserts_per_sec, 0)} inserts/sec")

# Get index stats
{:ok, stats} = TemporalIndex.stats(db_id, series_id)
IO.puts("\nIndex Stats:")
IO.puts("  Count: #{stats.count}")
IO.puts("  Time range: #{stats.time_range_seconds} seconds (#{Float.round(stats.time_range_seconds / 86400, 1)} days)")
IO.puts("  Min timestamp: #{stats.min_timestamp}")
IO.puts("  Max timestamp: #{stats.max_timestamp}")

# Benchmark 2: Short Range Query (1 hour)
IO.puts("\n2. Short Range Query Performance (1 hour windows)")
hour_in_seconds = 3600

{query_time_us, results} = :timer.tc(fn ->
  for _i <- 1..query_count do
    # Random 1-hour window
    start_time = base_time + :rand.uniform(num_points * 60 - hour_in_seconds)
    end_time = start_time + hour_in_seconds

    case TemporalIndex.range_query(db_id, series_id, start_time, end_time, 1000) do
      {:ok, point_ids} -> length(point_ids)
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
IO.puts("  Avg results: #{Float.round(avg_results, 1)} points")

# Benchmark 3: Medium Range Query (1 day)
IO.puts("\n3. Medium Range Query Performance (1 day windows)")
day_in_seconds = 86400

{day_time_us, day_results} = :timer.tc(fn ->
  for _i <- 1..query_count do
    # Random 1-day window
    start_time = base_time + :rand.uniform(num_points * 60 - day_in_seconds)
    end_time = start_time + day_in_seconds

    case TemporalIndex.range_query(db_id, series_id, start_time, end_time, 10000) do
      {:ok, point_ids} -> length(point_ids)
      _ -> 0
    end
  end
end)

day_time_ms = day_time_us / 1_000
avg_day_results = Enum.sum(day_results) / query_count
day_queries_per_sec = query_count / (day_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(day_time_ms, 2)} ms")
IO.puts("  Per query: #{Float.round(day_time_ms / query_count, 4)} ms")
IO.puts("  Throughput: #{Float.round(day_queries_per_sec, 0)} queries/sec")
IO.puts("  Avg results: #{Float.round(avg_day_results, 1)} points")

# Benchmark 4: Long Range Query (1 week)
IO.puts("\n4. Long Range Query Performance (1 week windows)")
week_in_seconds = 7 * 86400

{week_time_us, week_results} = :timer.tc(fn ->
  for _i <- 1..100 do  # Fewer queries for long ranges
    # Random 1-week window
    start_time = base_time + :rand.uniform(num_points * 60 - week_in_seconds)
    end_time = start_time + week_in_seconds

    case TemporalIndex.range_query(db_id, series_id, start_time, end_time, 10000) do
      {:ok, point_ids} -> length(point_ids)
      _ -> 0
    end
  end
end)

week_time_ms = week_time_us / 1_000
avg_week_results = Enum.sum(week_results) / 100
week_queries_per_sec = 100 / (week_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(week_time_ms, 2)} ms")
IO.puts("  Per query: #{Float.round(week_time_ms / 100, 4)} ms")
IO.puts("  Throughput: #{Float.round(week_queries_per_sec, 0)} queries/sec")
IO.puts("  Avg results: #{Float.round(avg_week_results, 1)} points")

# Benchmark 5: Delete Performance
IO.puts("\n5. Delete Performance")
points_to_delete = Enum.take_random(1..num_points, 5_000)

{delete_time_us, _} = :timer.tc(fn ->
  for i <- points_to_delete do
    point_id = "point_#{i}"
    timestamp_unix = base_time + (i * 60)
    TemporalIndex.delete(db_id, series_id, point_id, timestamp_unix)
  end
end)

delete_time_ms = delete_time_us / 1_000
deletes_per_sec = length(points_to_delete) / (delete_time_ms / 1_000)

IO.puts("  Total time: #{Float.round(delete_time_ms, 2)} ms")
IO.puts("  Per delete: #{Float.round(delete_time_ms / length(points_to_delete), 4)} ms")
IO.puts("  Throughput: #{Float.round(deletes_per_sec, 0)} deletes/sec")

# Cleanup
IO.puts("\n6. Cleanup")
TemporalIndex.drop_index(db_id, series_id)
IO.puts("  Index dropped")

IO.puts("\n=== Benchmark Complete ===")
