#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Fuzz test runner — compiles ReScript and runs all 4 targets with Deno
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ITERATIONS="${1:-10000}"

echo "=== Lith Fuzz Tests ==="
echo "Iterations per target: $ITERATIONS"
echo ""

# Build ReScript sources
echo "Building ReScript..."
deno task build 2>&1

# Run all fuzz targets
echo ""
echo "Running 4 fuzz targets..."
deno run --allow-read --allow-env --allow-write \
  src/Lith_Fuzz_Main.res.js --iterations "$ITERATIONS"

echo ""
echo "=== Fuzz tests complete ==="
