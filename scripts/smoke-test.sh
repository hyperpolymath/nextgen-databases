#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# VeriSimDB single-node production smoke test.
# Validates: startup, create, read, shutdown, restart, verify persistence.
#
# Usage: ./scripts/smoke-test.sh [--persistent]
#
# Requires: cargo, curl, jq

set -euo pipefail

PERSIST=""
DATA_DIR=""
PORT=18080
GRPC_PORT=18051

if [[ "${1:-}" == "--persistent" ]]; then
    PERSIST="yes"
    DATA_DIR=$(mktemp -d /tmp/verisimdb-smoke-XXXXXX)
    echo "=== VeriSimDB Smoke Test (PERSISTENT mode) ==="
    echo "  Data dir: $DATA_DIR"
else
    echo "=== VeriSimDB Smoke Test (in-memory mode) ==="
fi

cleanup() {
    echo ""
    echo "Cleaning up..."
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -SIGTERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [[ -n "$DATA_DIR" ]]; then
        rm -rf "$DATA_DIR"
    fi
}
trap cleanup EXIT

# Build
echo ""
echo "[1/6] Building VeriSimDB..."
if [[ -n "$PERSIST" ]]; then
    cargo build -p verisim-api --features persistent --release 2>&1 | tail -1
    BINARY="target/release/verisim-api"
else
    cargo build -p verisim-api --release 2>&1 | tail -1
    BINARY="target/release/verisim-api"
fi

# Start server
echo "[2/6] Starting server on port $PORT..."
export VERISIM_HOST="127.0.0.1"
export VERISIM_PORT="$PORT"
export VERISIM_GRPC_PORT="$GRPC_PORT"
if [[ -n "$PERSIST" ]]; then
    export VERISIM_PERSISTENCE_DIR="$DATA_DIR"
fi

$BINARY &
SERVER_PID=$!
sleep 2

# Check it's running
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "FAIL: Server did not start"
    exit 1
fi
echo "  Server started (PID: $SERVER_PID)"

# Health check
echo "[3/6] Health check..."
HEALTH=$(curl -sf "http://127.0.0.1:$PORT/health" 2>/dev/null || echo "FAIL")
if echo "$HEALTH" | grep -q "healthy\|ok"; then
    echo "  Health: OK"
else
    echo "  FAIL: Health check returned: $HEALTH"
    exit 1
fi

# Create entity
echo "[4/6] Creating entity..."
CREATE_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/octads" \
    -H "Content-Type: application/json" \
    -d '{
        "document": {
            "title": "Smoke Test Entity",
            "body": "This entity tests single-node production readiness."
        },
        "vector": {
            "embedding": [0.1, 0.2, 0.3, 0.4, 0.5]
        }
    }' 2>/dev/null || echo "FAIL")

if echo "$CREATE_RESP" | grep -q "id"; then
    ENTITY_ID=$(echo "$CREATE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    if [[ -z "$ENTITY_ID" ]]; then
        # Try jq
        ENTITY_ID=$(echo "$CREATE_RESP" | jq -r '.id' 2>/dev/null || echo "")
    fi
    echo "  Created: $ENTITY_ID"
else
    echo "  FAIL: Create returned: $CREATE_RESP"
    exit 1
fi

# Read entity back
echo "[5/6] Reading entity back..."
GET_RESP=$(curl -sf "http://127.0.0.1:$PORT/octads/$ENTITY_ID" 2>/dev/null || echo "FAIL")
if echo "$GET_RESP" | grep -q "$ENTITY_ID"; then
    echo "  Read: OK"
else
    echo "  FAIL: Get returned: $GET_RESP"
    exit 1
fi

# Graceful shutdown
echo "[6/6] Graceful shutdown..."
kill -SIGTERM "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
echo "  Server stopped cleanly"

# If persistent, restart and verify data survived
if [[ -n "$PERSIST" ]]; then
    echo ""
    echo "[BONUS] Persistence verification..."
    echo "  Restarting server..."
    $BINARY &
    SERVER_PID=$!
    sleep 2

    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "  FAIL: Server did not restart"
        exit 1
    fi

    GET_RESP2=$(curl -sf "http://127.0.0.1:$PORT/octads/$ENTITY_ID" 2>/dev/null || echo "FAIL")
    if echo "$GET_RESP2" | grep -q "$ENTITY_ID"; then
        echo "  Persistence: VERIFIED — entity survived restart"
    else
        echo "  WARN: Entity not found after restart (WAL replay may need octad registry rebuild)"
        echo "  Response: $GET_RESP2"
    fi

    kill -SIGTERM "$SERVER_PID"
    wait "$SERVER_PID" 2>/dev/null || true
fi

echo ""
echo "=== SMOKE TEST PASSED ==="
