#!/bin/sh
# SPDX-License-Identifier: PMPL-1.0-or-later
# VeriSimDB entrypoint — starts Rust API then Elixir orchestration
set -e

# Start Rust API server in background
echo "Starting VeriSimDB Rust API..."
/app/verisim-api &
RUST_PID=$!

# Wait for Rust API to become ready
echo "Waiting for Rust API to be ready..."
RETRIES=0
MAX_RETRIES=30
until curl -sf http://127.0.0.1:${VERISIM_PORT:-8080}/health > /dev/null 2>&1; do
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
        echo "ERROR: Rust API failed to start after ${MAX_RETRIES}s"
        kill "$RUST_PID" 2>/dev/null || true
        exit 1
    fi
    sleep 1
done
echo "Rust API ready on port ${VERISIM_PORT:-8080}"

# Clean shutdown: kill Rust API when Elixir exits
cleanup() {
    echo "Shutting down..."
    kill "$RUST_PID" 2>/dev/null || true
    wait "$RUST_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Start Elixir release in foreground
echo "Starting VeriSimDB Elixir orchestration..."
exec /app/elixir/bin/verisim start
