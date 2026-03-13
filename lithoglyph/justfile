# SPDX-License-Identifier: PMPL-1.0-or-later
# justfile - Just recipes for Lithoglyph
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

# Default recipe
default:
    @just --list

# ============================================================
# BUILD
# ============================================================

# Build Zig libraries (static + shared)
build-zig:
    cd core-zig && zig build

# Build shared library for FFI consumers
build-ffi:
    cd core-zig && zig build-lib src/bridge.zig -dynamic -lc -O ReleaseFast

# Build C FFI integration test binary
build-ffi-tests:
    cd core-zig && gcc -o test-ffi-integration test-ffi-integration.c -L zig-out/lib -llith_bridge
    cd core-zig && gcc -o test-version-only test-version-only.c -L zig-out/lib -llith_bridge
    cd core-zig && gcc -o test-db-open test-db-open.c -L zig-out/lib -llith_bridge

# Build everything
build: build-zig

# ============================================================
# TESTS
# ============================================================

# Run Zig unit tests (bridge + blocks)
test-zig:
    @echo "=== Zig Unit Tests ==="
    cd core-zig && zig build test
    @echo "Zig tests passed"

# Run Zig tests directly (faster, no build system)
test-zig-fast:
    @echo "=== Zig Direct Tests ==="
    cd core-zig && zig test src/bridge.zig
    cd core-zig && zig test src/blocks.zig

# Run Forth block layer tests
test-forth:
    @echo "=== Forth Block Tests ==="
    cd core-forth/test && gforth test-blocks.fs -e bye

# Run C FFI integration tests (requires build-zig first)
test-ffi: build-zig
    @echo "=== C FFI Integration Tests ==="
    cd core-zig && LD_LIBRARY_PATH=zig-out/lib ./test-ffi-integration

# Run C FFI quick smoke tests
test-ffi-smoke: build-zig
    @echo "=== C FFI Smoke Tests ==="
    cd core-zig && LD_LIBRARY_PATH=zig-out/lib ./test-version-only
    cd core-zig && LD_LIBRARY_PATH=zig-out/lib ./test-db-open

# Run Factor seam tests
test-factor:
    @echo "=== Factor Seam Tests ==="
    cd core-factor/gql && factor seam-tests.factor

# Run ReScript property tests
test-property:
    @echo "=== ReScript Property Tests ==="
    cd tests/property && deno task test

# Run ReScript fuzz tests (quick: 1K iterations)
test-fuzz-quick:
    @echo "=== ReScript Fuzz Tests (Quick) ==="
    cd tests/fuzz && deno task fuzz:quick

# Run ReScript fuzz tests (standard: 10K iterations)
test-fuzz:
    @echo "=== ReScript Fuzz Tests ==="
    cd tests/fuzz && deno task fuzz

# Run ReScript integration tests (requires Deno + ReScript)
test-integration:
    @echo "=== ReScript Integration Tests ==="
    cd tests/integration && deno task test

# Run E2E tests (requires running Lith server on :8080)
test-e2e:
    @echo "=== E2E Tests (requires server on :8080) ==="
    cd tests/e2e && deno task test

# Run all core tests (no server required)
test: test-zig test-forth test-ffi

# Run all tests including ReScript suites
test-all: test-zig test-forth test-ffi test-property test-fuzz-quick

# ============================================================
# BENCHMARKS
# ============================================================

# Run Factor GQL benchmarks
bench-factor:
    @echo "=== Factor GQL Benchmarks ==="
    cd core-factor/gql && factor benchmarks.factor

# Run all benchmarks
bench: bench-factor

# ============================================================
# CHECKS & VALIDATION
# ============================================================

# Check that Forth code loads without errors
check-forth:
    @echo "Checking Forth code loads..."
    cd core-forth/src && gforth lithoglyph-blocks.fs -e 'bye'
    cd core-forth/src && gforth lithoglyph-journal.fs -e 'bye'
    cd core-forth/src && gforth lithoglyph-model.fs -e 'bye'
    @echo "All Forth files load successfully"

# Check that Lean code compiles
check-lean:
    @echo "Checking Lean code compiles..."
    cd normalizer/lean && lake build
    @echo "Lean code compiles"

# Verify Zig ABI exports match expectations
check-abi: build-zig
    @echo "=== ABI Export Verification ==="
    nm -D core-zig/zig-out/lib/liblith_bridge.so | grep ' T fdb_' | sort
    @echo "Expected: fdb_version, fdb_db_open, fdb_db_close, fdb_txn_begin, fdb_txn_commit, fdb_txn_abort, fdb_apply, fdb_introspect_schema, fdb_render_block, fdb_render_journal, fdb_blob_free"

# Run all checks
check: check-forth check-lean check-abi

# Format Zig code
fmt:
    cd core-zig && zig fmt src/

# ============================================================
# CLEAN
# ============================================================

# Clean build artifacts
clean:
    @echo "Cleaning build artifacts..."
    rm -rf core-zig/zig-out core-zig/.zig-cache
    rm -f core-zig/test-*.lgh
    @echo "Clean complete"

# ============================================================
# DEV TOOLS
# ============================================================

# Show development environment status
env-status:
    @echo "Development Environment Status:"
    @echo "================================"
    @which zig 2>/dev/null && echo "Zig: $(zig version)" || echo "Zig: NOT INSTALLED"
    @which gforth 2>/dev/null && echo "Forth: $(gforth --version 2>&1 | head -1)" || echo "gforth: NOT INSTALLED"
    @which factor 2>/dev/null && echo "Factor: installed" || echo "Factor: NOT INSTALLED"
    @which lean 2>/dev/null && echo "Lean: $(lean --version 2>&1 | head -1)" || echo "Lean: NOT INSTALLED"
    @which deno 2>/dev/null && echo "Deno: $(deno --version 2>&1 | head -1)" || echo "Deno: NOT INSTALLED"

# Start demo server for E2E testing
serve:
    @echo "Starting Lithoglyph demo server on :8080..."
    cd core-zig && zig run ../demo-server.zig -- -lc
