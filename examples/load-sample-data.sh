#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# load-sample-data.sh — Load VeriSimDB sample data and run example VQL queries.
#
# This script loads 50 sample hexad entities from seed.json into a running
# VeriSimDB instance, then executes all VQL example queries from the
# vql-queries/ directory. It is intended for demonstration and testing.
#
# The sample data tells the story of a research institution ecosystem:
# 10 academic papers, 10 researchers, 10 organisations, 10 datasets,
# and 10 events — all cross-linked via graph edges and with 10 entities
# containing intentional cross-modal drift for drift detection testing.
#
# Usage:
#   ./load-sample-data.sh [--api-url URL]
#
# Prerequisites:
#   - VeriSimDB rust-core running on port 8080 (or specify --api-url)
#   - jq installed (for pretty-printing responses)
#   - curl installed
#
# Examples:
#   ./load-sample-data.sh
#   ./load-sample-data.sh --api-url http://192.168.1.10:8080/api/v1

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
      # Positional fallback for bare URL argument
      API_URL="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/sample-data/seed.json"

echo "=== VeriSimDB Sample Data Loader ==="
echo "API URL: ${API_URL}"
echo ""

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required but not installed."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed."; exit 1; }

if [[ ! -f "$DATA_FILE" ]]; then
  echo "ERROR: Sample data file not found at ${DATA_FILE}"
  echo "Expected: examples/sample-data/seed.json"
  exit 1
fi

# ---------------------------------------------------------------------------
# Server health check
# ---------------------------------------------------------------------------

echo "Checking server health..."
HEALTH=$(curl -sf "${API_URL}/health" 2>/dev/null || echo '{"status":"unreachable"}')
STATUS=$(echo "$HEALTH" | jq -r '.status // "unknown"')

if [ "$STATUS" != "ok" ] && [ "$STATUS" != "healthy" ]; then
  echo "ERROR: Server not healthy at ${API_URL}. Status: ${STATUS}"
  echo ""
  echo "Start VeriSimDB first:"
  echo "  cd rust-core && cargo run"
  echo ""
  echo "Or specify a different URL:"
  echo "  ./load-sample-data.sh --api-url http://HOST:PORT/api/v1"
  exit 1
fi

echo "Server healthy."
echo ""

# ---------------------------------------------------------------------------
# Load entities
# ---------------------------------------------------------------------------

echo "Loading 50 sample entities from ${DATA_FILE}..."
echo ""

LOADED=0
FAILED=0

# Process each entity from the JSON array
jq -c '.[]' "$DATA_FILE" | while read -r entity; do
  ID=$(echo "$entity" | jq -r '.id')
  CATEGORY=$(echo "$entity" | jq -r '.category')
  TITLE=$(echo "$entity" | jq -r '.document.title // "(untitled)"')

  RESPONSE=$(curl -sf -X POST "${API_URL}/hexads" \
    -H "Content-Type: application/json" \
    -d "$entity" 2>/dev/null || echo "FAILED")

  if [ "$RESPONSE" = "FAILED" ]; then
    echo "  FAIL: ${ID} [${CATEGORY}] ${TITLE}"
    FAILED=$((FAILED + 1))
  else
    echo "  OK:   ${ID} [${CATEGORY}] ${TITLE}"
    LOADED=$((LOADED + 1))
  fi
done

echo ""
echo "Loading complete. Check output above for individual results."
echo ""

# ---------------------------------------------------------------------------
# Run VQL example queries
# ---------------------------------------------------------------------------

echo "=== Running VQL Example Queries ==="
echo ""

VQL_DIR="${SCRIPT_DIR}/vql-queries"

if [[ ! -d "$VQL_DIR" ]]; then
  echo "WARNING: VQL queries directory not found at ${VQL_DIR}"
  echo "Skipping query execution."
  exit 0
fi

for vql_file in "${VQL_DIR}"/*.vql; do
  [[ -f "$vql_file" ]] || continue

  BASENAME=$(basename "$vql_file")

  # Extract the query: strip comment lines (--) and collapse whitespace
  QUERY=$(grep -v '^--' "$vql_file" | tr '\n' ' ' | sed 's/  */ /g' | xargs)

  if [[ -z "$QUERY" ]]; then
    echo "--- ${BASENAME} --- (empty query, skipping)"
    echo ""
    continue
  fi

  echo "--- ${BASENAME} ---"
  echo "Query: ${QUERY}"
  echo ""

  # Escape double quotes in the query for JSON payload
  ESCAPED_QUERY=$(echo "$QUERY" | sed 's/"/\\"/g')

  RESULT=$(curl -sf -X POST "${API_URL}/vql/execute" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"${ESCAPED_QUERY}\"}" 2>/dev/null || echo '{"error": "query execution failed or server unreachable"}')

  echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
  echo ""
done

echo "=== Done ==="
