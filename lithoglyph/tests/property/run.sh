#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Property test runner — compiles ReScript and runs with Deno
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Lith Property Tests ==="
echo ""

# Build ReScript sources
echo "Building ReScript..."
deno task build 2>&1

# Run the GQL property tests
echo ""
echo "Running GQL property tests (12 predicates)..."
deno run --allow-read --allow-env src/Lith_Property_GQL.res.js

echo ""
echo "=== Property tests complete ==="
