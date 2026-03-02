#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# smoke-test.sh — VeriSimDB smoke test.
#
# Validates that the VeriSimDB server is running and can handle basic
# operations: health check, hexad CRUD, VQL query execution, drift
# endpoint, and orchestration layer health. Returns exit 0 on success,
# non-zero on failure.
#
# Suitable for CI integration — the exit code reflects the test outcome.
# Individual test results are printed to stdout.
#
# Usage:
#   ./smoke-test.sh [--api-url URL]
#
# Examples:
#   ./smoke-test.sh
#   ./smoke-test.sh --api-url http://192.168.1.10:8080/api/v1

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

API_URL="http://localhost:8080/api/v1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-url)
      API_URL="$2"
      shift 2
      ;;
    *)
      API_URL="$1"
      shift
      ;;
  esac
done

FAILURES=0

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "=== VeriSimDB Smoke Test ==="
echo "API URL: ${API_URL}"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# 1. Health check — verify the Rust core is responding
echo "1. Health check"
if curl -sf "${API_URL}/health" | jq -e '.status' >/dev/null 2>&1; then
  pass "Server is healthy"
else
  fail "Server health check failed — is VeriSimDB running?"
fi

# 2. Create a hexad — test the write path
echo "2. Create hexad"
CREATE_PAYLOAD='{
  "id": "smoke-test-001",
  "category": "test",
  "document": {
    "title": "Smoke Test Entity",
    "content": "This entity is created by the VeriSimDB smoke test and should be deleted after the test completes.",
    "tags": ["smoke-test", "ephemeral"]
  },
  "graph": {
    "edges": []
  },
  "vector": {
    "embedding": [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
  },
  "semantic": {
    "types": ["http://schema.org/Thing"],
    "properties": {"test": true}
  },
  "temporal": {
    "created": "2026-02-28T00:00:00Z",
    "modified": "2026-02-28T00:00:00Z",
    "version": 1
  },
  "provenance": {
    "origin": "smoke-test.sh",
    "actor": "ci-runner",
    "chain": ["created-by-smoke-test"]
  },
  "spatial": {
    "lat": 51.5074,
    "lon": -0.1278,
    "label": "Central London (test)"
  }
}'

CREATE_RESP=$(curl -sf -X POST "${API_URL}/hexads" \
  -H "Content-Type: application/json" \
  -d "$CREATE_PAYLOAD" 2>/dev/null || echo "FAILED")

if [ "$CREATE_RESP" != "FAILED" ]; then
  pass "Hexad created"
else
  fail "Hexad creation failed"
fi

# 3. Read the hexad back — test the read path
echo "3. Read hexad"
if curl -sf "${API_URL}/hexads/smoke-test-001" | jq -e '.id' >/dev/null 2>&1; then
  pass "Hexad readable"
else
  fail "Hexad read failed"
fi

# 4. Execute a VQL query — test the query engine
echo "4. VQL query"
VQL_RESP=$(curl -sf -X POST "${API_URL}/vql/execute" \
  -H "Content-Type: application/json" \
  -d '{"query":"SELECT * FROM hexads LIMIT 5"}' 2>/dev/null || echo "FAILED")

if [ "$VQL_RESP" != "FAILED" ]; then
  pass "VQL query executed"
else
  fail "VQL query failed"
fi

# 5. Check drift endpoint — test drift scoring
echo "5. Drift check"
if curl -sf "${API_URL}/drift/entity/smoke-test-001" >/dev/null 2>&1; then
  pass "Drift endpoint responds"
else
  fail "Drift endpoint failed"
fi

# 6. Telemetry / orchestration layer — test the Elixir layer (may not be
#    running in all environments, so a failure here is noted but expected)
ORCH_URL="${API_URL/8080/4080}"
ORCH_URL="${ORCH_URL/\/api\/v1/}"
echo "6. Telemetry (orchestration layer)"
if curl -sf "${ORCH_URL}/health" | jq -e '.status' >/dev/null 2>&1; then
  pass "Orchestration layer healthy"
else
  fail "Orchestration layer unreachable (expected if Elixir not running)"
fi

# 7. Delete test entity — clean up after ourselves
echo "7. Cleanup"
curl -sf -X DELETE "${API_URL}/hexads/smoke-test-001" >/dev/null 2>&1 || true
pass "Cleanup attempted"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
if [ $FAILURES -eq 0 ]; then
  echo "=== ALL PASSED ==="
  exit 0
else
  echo "=== ${FAILURES} FAILURE(S) ==="
  exit 1
fi
