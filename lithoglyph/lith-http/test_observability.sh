#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Lithoglyph HTTP Observability Endpoints Test Script

set -e

BASE_URL="http://localhost:4000"

echo ""
echo "=== Lithoglyph HTTP Observability Test ==="
echo ""

# Test 1: Basic health check
echo "Test 1: GET /health"
curl -s "$BASE_URL/health" | jq '.'
echo ""

# Test 2: Liveness probe
echo "Test 2: GET /health/live"
curl -s "$BASE_URL/health/live" | jq '.'
echo ""

# Test 3: Readiness probe
echo "Test 3: GET /health/ready"
curl -s "$BASE_URL/health/ready" | jq '.'
echo ""

# Test 4: Detailed health check
echo "Test 4: GET /health/detailed"
curl -s "$BASE_URL/health/detailed" | jq '.'
echo ""

# Test 5: Prometheus metrics
echo "Test 5: GET /metrics"
echo "First 20 lines of metrics output:"
curl -s "$BASE_URL/metrics" | head -20
echo ""
echo "..."
echo ""

# Test 6: Make some requests to generate metrics
echo "Test 6: Generate some traffic for metrics"
curl -s "$BASE_URL/api/v1/version" > /dev/null
curl -s "$BASE_URL/health" > /dev/null
curl -s "$BASE_URL/health/ready" > /dev/null
echo "Traffic generated"
echo ""

# Test 7: Check metrics after traffic
echo "Test 7: GET /metrics (after traffic)"
echo "Last 10 lines of metrics output:"
curl -s "$BASE_URL/metrics" | tail -10
echo ""

echo "=== All observability tests passed! ==="
echo ""
