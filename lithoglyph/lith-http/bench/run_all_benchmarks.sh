#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Run all M13 performance benchmarks

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Lithoglyph HTTP API - M13 Performance Suite           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if server is running (for HTTP tests)
SERVER_RUNNING=0
if curl -s http://localhost:4000/api/v1/health > /dev/null 2>&1; then
  SERVER_RUNNING=1
  echo "✓ Server is running on http://localhost:4000"
else
  echo "⚠ Server not running (HTTP load tests will be skipped)"
  echo "  Start server: mix phx.server"
fi
echo ""

# Create results directory
RESULTS_DIR="bench/results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"
echo "Results will be saved to: $RESULTS_DIR"
echo ""

# 1. Spatial Index Benchmark
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1/5: R-tree Spatial Index Benchmark"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mix run bench/spatial_index_bench.exs | tee "$RESULTS_DIR/spatial_index.txt"
echo ""

# 2. Temporal Index Benchmark
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2/5: B-tree Temporal Index Benchmark"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mix run bench/temporal_index_bench.exs | tee "$RESULTS_DIR/temporal_index.txt"
echo ""

# 3. Query Cache Benchmark
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3/5: Query Cache Benchmark"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mix run bench/query_cache_bench.exs | tee "$RESULTS_DIR/query_cache.txt"
echo ""

# 4. WebSocket Stress Test (Simulation)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4/5: WebSocket Stress Test (Simulation)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mix run bench/websocket_stress_test.exs | tee "$RESULTS_DIR/websocket.txt"
echo ""

# 5. HTTP Load Test (if server running)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5/5: HTTP Load Test (k6)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $SERVER_RUNNING -eq 1 ]; then
  if command -v k6 &> /dev/null; then
    k6 run bench/http_load_test.js --out json="$RESULTS_DIR/http_load_test.json" \
      | tee "$RESULTS_DIR/http_load_test.txt"
  else
    echo "⚠ k6 not installed - skipping HTTP load test"
    echo "  Install: https://k6.io/docs/get-started/installation/"
  fi
else
  echo "⚠ Skipped (server not running)"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Benchmark Complete                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Summary files:"
ls -lh "$RESULTS_DIR"
echo ""

# Generate summary report
cat > "$RESULTS_DIR/SUMMARY.md" << EOF
# M13 Performance Benchmark Results

**Date:** $(date)
**Server:** ${SERVER_RUNNING}

## Tests Run

1. ✓ R-tree Spatial Index Benchmark
2. ✓ B-tree Temporal Index Benchmark
3. ✓ Query Cache Benchmark
4. ✓ WebSocket Stress Test (Simulation)
5. $(if [ $SERVER_RUNNING -eq 1 ]; then echo "✓"; else echo "⚠"; fi) HTTP Load Test

## Result Files

$(ls -1 "$RESULTS_DIR" | grep -v SUMMARY.md | while read f; do echo "- \`$f\`"; done)

## Quick Stats

### Spatial Index
\`\`\`
$(grep "Throughput:" "$RESULTS_DIR/spatial_index.txt" | head -4)
\`\`\`

### Temporal Index
\`\`\`
$(grep "Throughput:" "$RESULTS_DIR/temporal_index.txt" | head -4)
\`\`\`

### Query Cache
\`\`\`
$(grep "Throughput:" "$RESULTS_DIR/query_cache.txt" | head -3)
\`\`\`

## Next Steps

1. Review detailed results in individual files
2. Compare against baseline metrics
3. Identify bottlenecks for optimization
4. Run production load tests with real Rust NIF (M14)
EOF

echo "Summary report: $RESULTS_DIR/SUMMARY.md"
echo ""
echo "View results:"
echo "  cat $RESULTS_DIR/SUMMARY.md"
echo "  less $RESULTS_DIR/spatial_index.txt"
echo ""
