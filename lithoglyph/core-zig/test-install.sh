#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Lithoglyph Installation Test
#
# Verifies that the Zig bridge can be built and installed correctly.
# Tests both static and shared library builds.

set -euo pipefail

echo "=== Lithoglyph Installation Test ==="
echo ""

# Check Zig installation
if ! command -v zig &> /dev/null; then
    echo "❌ Zig not found. Please install Zig 0.13+ first."
    exit 1
fi

ZIG_VERSION=$(zig version)
echo "✅ Zig version: $ZIG_VERSION"
echo ""

# Build static library
echo "=== Building static library ==="
zig build-lib src/bridge.zig -O ReleaseSafe
if [ -f "libbridge.a" ]; then
    SIZE=$(du -h libbridge.a | cut -f1)
    echo "✅ Static library built: libbridge.a ($SIZE)"
else
    echo "❌ Static library build failed"
    exit 1
fi
echo ""

# Build shared library
echo "=== Building shared library ==="
zig build-lib -dynamic src/bridge.zig -O ReleaseSafe
if [ -f "libbridge.so" ] || [ -f "libbridge.dylib" ] || [ -f "bridge.dll" ]; then
    if [ -f "libbridge.so" ]; then
        SIZE=$(du -h libbridge.so | cut -f1)
        echo "✅ Shared library built: libbridge.so ($SIZE)"
    elif [ -f "libbridge.dylib" ]; then
        SIZE=$(du -h libbridge.dylib | cut -f1)
        echo "✅ Shared library built: libbridge.dylib ($SIZE)"
    else
        SIZE=$(du -h bridge.dll | cut -f1)
        echo "✅ Shared library built: bridge.dll ($SIZE)"
    fi
else
    echo "❌ Shared library build failed"
    exit 1
fi
echo ""

# Verify ABI exports
echo "=== Verifying ABI exports ==="
if [ -f "libbridge.so" ]; then
    EXPORTS=$(nm -D libbridge.so | grep "fdb_" | wc -l)
    echo "Found $EXPORTS exported fdb_* functions"

    if nm -D libbridge.so | grep -q "fdb_db_open"; then
        echo "✅ fdb_db_open found"
    else
        echo "❌ fdb_db_open missing"
        exit 1
    fi

    if nm -D libbridge.so | grep -q "fdb_apply"; then
        echo "✅ fdb_apply found"
    else
        echo "❌ fdb_apply missing"
        exit 1
    fi

    if nm -D libbridge.so | grep -q "fdb_txn_begin"; then
        echo "✅ fdb_txn_begin found"
    else
        echo "❌ fdb_txn_begin missing"
        exit 1
    fi
else
    echo "ℹ️  Skipping ABI verification (not on Linux)"
fi
echo ""

# Test block storage module
echo "=== Testing block storage ==="
zig test src/blocks.zig
echo "✅ Block storage tests passed"
echo ""

# Test bridge module
echo "=== Testing bridge ==="
zig test src/bridge.zig
echo "✅ Bridge tests passed"
echo ""

# Cleanup
echo "=== Cleanup ==="
rm -f libbridge.a libbridge.so libbridge.dylib bridge.dll
rm -f *.o *.obj
rm -f test*.lgh
echo "✅ Cleanup complete"
echo ""

echo "========================================="
echo "✅ All installation tests passed!"
echo "========================================="
