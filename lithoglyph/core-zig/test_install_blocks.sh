#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Lithoglyph Block Storage Installation Test

set -euo pipefail

echo "=== Lithoglyph Block Storage Installation Test ==="
echo ""

# Check Zig
if ! command -v zig &> /dev/null; then
    echo "❌ Zig not found"
    exit 1
fi

echo "✅ Zig version: $(zig version)"
echo ""

# Test block storage
echo "=== Testing block storage module ==="
zig test src/blocks.zig
echo "✅ All 9 tests passed"
echo ""

echo "========================================="
echo "✅ Installation test passed!"
echo "========================================="
