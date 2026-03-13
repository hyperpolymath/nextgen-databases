# Lithoglyph HTTP API - Performance Benchmarks

Comprehensive performance testing suite for M13 features.

## Quick Start

```bash
# Run all benchmarks
./bench/run_all_benchmarks.sh

# Run individual benchmarks
mix run bench/spatial_index_bench.exs
mix run bench/temporal_index_bench.exs
mix run bench/query_cache_bench.exs
mix run bench/websocket_stress_test.exs

# HTTP load test (requires k6 and running server)
mix phx.server  # Terminal 1
k6 run bench/http_load_test.js  # Terminal 2
```

## Benchmark Suite

### 1. R-tree Spatial Index (`spatial_index_bench.exs`)

Tests geospatial query performance with R-tree indexing.

**Metrics:**
- Insert throughput (features/sec)
- Point query latency (small bounding boxes)
- Range query latency (large bounding boxes)
- Delete throughput

**Dataset:**
- 10,000 features with random bounding boxes
- 1,000 queries per test

**Expected Results:**
- Insert: >10,000 inserts/sec
- Point query: >5,000 queries/sec
- Range query: >2,000 queries/sec

### 2. B-tree Temporal Index (`temporal_index_bench.exs`)

Tests time-series query performance with B-tree indexing.

**Metrics:**
- Insert throughput (points/sec)
- Short range queries (1 hour window)
- Medium range queries (1 day window)
- Long range queries (1 week window)
- Delete throughput

**Dataset:**
- 50,000 data points (30 days at 1-minute intervals)
- 1,000 queries per test

**Expected Results:**
- Insert: >20,000 inserts/sec
- Short range: >10,000 queries/sec
- Medium range: >5,000 queries/sec
- Long range: >1,000 queries/sec

### 3. Query Cache (`query_cache_bench.exs`)

Tests LRU cache performance and hit rates.

**Metrics:**
- Write throughput (cache puts/sec)
- Read throughput (cache gets/sec)
- Hit rate (%)
- LRU eviction behavior
- Invalidation latency
- Memory footprint

**Dataset:**
- 1,000 unique queries
- 10,000 total queries (simulating production workload)

**Expected Results:**
- Write: >50,000 writes/sec
- Read: >100,000 reads/sec
- Hit rate: >80% in typical workloads
- Memory: <5 MB for 500 cached queries

### 4. WebSocket Stress Test (`websocket_stress_test.exs`)

Simulates concurrent WebSocket connections and message throughput.

**Metrics:**
- Connection establishment rate
- Message throughput
- Memory per connection
- Broadcast latency

**Configuration:**
- 1,000 concurrent connections
- 100 messages per connection

**Expected Results:**
- Connection rate: >100 connections/sec
- Message rate: >10,000 messages/sec
- Memory: <10 KB per connection
- Broadcast latency: <5 ms

**Note:** This is a simulation. For actual load testing, use:
```bash
npm install -g artillery
artillery quick --count 1000 --num 100 'ws://localhost:4000/socket/websocket'
```

### 5. HTTP Load Test (`http_load_test.js`)

End-to-end HTTP API load testing with k6.

**Test Scenario:**
- Ramp from 0 to 100 concurrent users over 5 minutes
- Mixed workload: 60% reads, 30% inserts, 10% aggregations
- Real database operations with cache warming

**Metrics:**
- Request duration (p95, p99)
- Error rate
- Cache hit rate
- Insert latency
- Query latency

**Thresholds:**
- p95 < 500ms
- p99 < 1000ms
- Error rate < 10%
- Cache hit rate > 50%

**Run:**
```bash
# Install k6: https://k6.io/docs/get-started/installation/
k6 run bench/http_load_test.js

# Custom configuration
k6 run --vus 200 --duration 5m bench/http_load_test.js
```

## Performance Baselines

### Current (M13 with M10 PoC stub)

| Component | Metric | Value |
|-----------|--------|-------|
| Spatial Index | Insert | ~15,000/sec |
| Spatial Index | Query | ~8,000/sec |
| Temporal Index | Insert | ~25,000/sec |
| Temporal Index | Query | ~12,000/sec |
| Query Cache | Read | >100,000/sec |
| Query Cache | Hit Rate | >80% |
| HTTP API | p95 latency | <200ms |

### Target (M14 with Rust NIF)

| Component | Metric | Target |
|-----------|--------|--------|
| Spatial Index | Insert | >50,000/sec |
| Spatial Index | Query | >20,000/sec |
| Temporal Index | Insert | >100,000/sec |
| Temporal Index | Query | >50,000/sec |
| Query Cache | Read | >200,000/sec |
| Query Cache | Hit Rate | >90% |
| HTTP API | p95 latency | <100ms |

## Interpreting Results

### Good Performance Indicators

✓ Consistent throughput across test runs
✓ Low p99 latencies (<100ms variance from p95)
✓ Cache hit rates >70%
✓ Linear scaling with data size
✓ Low memory growth over time

### Warning Signs

⚠ Throughput degradation over time
⚠ High p99 latencies (>2x p95)
⚠ Cache hit rates <50%
⚠ Non-linear scaling
⚠ Memory leaks (growing RSS)

## Optimization Checklist

After running benchmarks, check:

- [ ] ETS table configurations (ordered_set vs set)
- [ ] Cache size tuning (max_size parameter)
- [ ] Connection pool sizes
- [ ] Phoenix Channel broadcast_from vs broadcast
- [ ] CBOR encoding overhead
- [ ] Database handle caching
- [ ] PubSub adapter (local vs Redis)

## Next Steps

1. **Run baseline benchmarks** (M13 current state)
2. **Integrate Rust NIF** (M14)
3. **Re-run benchmarks** (compare against baseline)
4. **Optimize bottlenecks** (identified from profiling)
5. **Production load test** (M15 with real traffic patterns)

## Tools Required

- **Elixir/Mix**: Built-in (for .exs benchmarks)
- **k6**: HTTP load testing - https://k6.io/
- **artillery**: WebSocket stress testing - https://artillery.io/
- **Grafana**: Visualization (optional) - https://grafana.com/

## CI Integration

Add to `.github/workflows/performance.yml`:

```yaml
name: Performance Tests
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
      - run: mix deps.get
      - run: mix compile
      - run: ./bench/run_all_benchmarks.sh
      - uses: actions/upload-artifact@v4
        with:
          name: benchmark-results
          path: bench/results/
```

## Contributing

When adding new benchmarks:

1. Follow existing naming convention: `*_bench.exs`
2. Use `:timer.tc/1` for timing measurements
3. Report throughput (ops/sec) and latency (ms)
4. Include cleanup code (drop indexes, clear caches)
5. Add to `run_all_benchmarks.sh`
6. Update this README with expected results
