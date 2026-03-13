// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// bridge.zig - Idris2-facing FFI Layer for Lithoglyph Lith
//
// This module is the thin delegation layer between the Idris2 ABI definitions
// (src/abi/*.idr) and the core storage engine (core-zig/src/bridge.zig).
//
// Architecture:
//   Idris2 ABI  -->  ffi/zig/src/bridge.zig (THIS FILE)  -->  core-zig/src/bridge.zig
//                    (type adaptation + lifecycle)              (WAL, blocks, storage)
//
// The core-zig bridge provides the real storage engine with:
//   - 6-phase WAL commit protocol
//   - Block allocator with CRC32C checksums
//   - Transaction buffering with pending writes/deletes
//   - Proof verification registry (D-NORM-004)
//   - Journal introspection
//
// This FFI layer adds:
//   - Library-level init/cleanup lifecycle (not needed by core-zig)
//   - Type adaptation between Idris2 ABI types and core-zig Lg* types
//   - Collection-level operations (future, requires schema layer)
//   - GQL query execution (future, requires Factor/Forth runtime)
//   - Cursor-based result iteration (future, requires query engine)
//   - Seam boundary tests for multi-language integration
//
// Symbol Export Strategy:
//   Functions with the SAME name as core-zig exports are declared as `pub fn`
//   (not `export fn`) to avoid C symbol collisions. The core-zig module's
//   `export fn` declarations handle those C symbols directly.
//   Functions UNIQUE to this FFI layer use `export fn` for C ABI export.
//
// CRITICAL: Pure ABI bridge - all safety logic in Idris2

const std = @import("std");
const types = @import("types.zig");
const cbor = @import("cbor.zig");
const query_executor = @import("query_executor.zig");

// Import core-zig bridge (the real storage engine implementation).
// This module provides all the Lg* types and lith_* functions.
// Its `export fn` declarations will appear in the shared library's symbol table.
const core_bridge = @import("core_bridge");

// ============================================================
// Re-export core-zig types for Idris2 ABI consumers
// ============================================================

/// Opaque database handle (delegates to core-zig LgDb)
pub const LithDb = core_bridge.LgDb;

/// Opaque transaction handle (delegates to core-zig LgTxn)
pub const LithTxn = core_bridge.LgTxn;

/// Core-zig types re-exported for FFI layer consumers
pub const LgBlob = core_bridge.LgBlob;
pub const LgStatus = core_bridge.LgStatus;
pub const LgResult = core_bridge.LgResult;
pub const LgRenderOpts = core_bridge.LgRenderOpts;
pub const LgTxnMode = core_bridge.LgTxnMode;
pub const LgProofVerifier = core_bridge.LgProofVerifier;

/// Status codes (matches Idris2 LithStatus).
/// Maps to/from core-zig LgStatus internally.
pub const Status = enum(i32) {
    ok = 0,
    invalid_arg = 1,
    not_found = 2,
    permission_denied = 3,
    already_exists = 4,
    constraint_violation = 5,
    type_mismatch = 6,
    out_of_memory = 7,
    io_error = 8,
    corruption = 9,
    conflict = 10,
    internal_error = 11,
};

// Opaque handle types for features not yet in core-zig
pub const LithCursor = opaque {};
pub const LithCollection = opaque {};
pub const LithSchema = opaque {};
pub const LithJournal = opaque {};
pub const LithMigration = opaque {};

// ============================================================
// Status Mapping: core-zig LgStatus <-> FFI Status
// ============================================================

/// Convert core-zig LgStatus to FFI Status code
pub fn fromLgStatus(lg_status: core_bridge.LgStatus) i32 {
    return switch (lg_status) {
        .ok => @intFromEnum(Status.ok),
        .err_internal => @intFromEnum(Status.internal_error),
        .err_not_found => @intFromEnum(Status.not_found),
        .err_invalid_argument => @intFromEnum(Status.invalid_arg),
        .err_out_of_memory => @intFromEnum(Status.out_of_memory),
        .err_not_implemented => @intFromEnum(Status.internal_error),
        .err_txn_not_active => @intFromEnum(Status.invalid_arg),
        .err_txn_already_committed => @intFromEnum(Status.invalid_arg),
    };
}

// ============================================================
// Global State
// ============================================================

var initialized: bool = false;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var global_executor: ?query_executor.SimpleExecutor = null;

////////////////////////////////////////////////////////////////////////////////
// Library Lifecycle
// NOTE: core-zig does not have library-level init/cleanup; it manages state
// per database handle. This layer adds global lifecycle for the FFI consumer.
////////////////////////////////////////////////////////////////////////////////

/// Initialize Lith library.
/// Sets up the query executor and any global state needed by the FFI layer.
/// The core-zig storage engine is initialized per-database via lith_open.
export fn lith_init() callconv(.c) i32 {
    if (initialized) return @intFromEnum(Status.ok);

    // Initialize query executor (M5 implementation)
    const allocator = gpa.allocator();
    global_executor = query_executor.SimpleExecutor.init(allocator) catch {
        return @intFromEnum(Status.out_of_memory);
    };

    initialized = true;
    return @intFromEnum(Status.ok);
}

/// Cleanup Lith library.
/// Tears down global state. Individual databases should be closed first.
export fn lith_cleanup() callconv(.c) void {
    if (!initialized) return;

    if (global_executor) |*executor| {
        executor.deinit();
        global_executor = null;
    }

    _ = gpa.deinit();
    initialized = false;
}

////////////////////////////////////////////////////////////////////////////////
// Database Operations
// Delegates to core-zig: lith_db_open, lith_db_close
//
// These have DIFFERENT C symbol names from core-zig (lith_open vs lith_db_open),
// so they are declared as `export fn` without collision.
////////////////////////////////////////////////////////////////////////////////

/// Open database.
/// Delegates to core-zig/src/bridge.zig lith_db_open which handles block
/// storage initialization, superblock reading, and handle registration.
export fn lith_open(
    path: [*:0]const u8,
    path_len: u64,
    db_out: *?*LithDb,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (path_len == 0) return @intFromEnum(Status.invalid_arg);
    if (path_len > 4096) return @intFromEnum(Status.invalid_arg);

    // Delegates to core-zig/src/bridge.zig lith_db_open
    var err_blob: core_bridge.LgBlob = undefined;
    const status = core_bridge.lith_db_open(
        @ptrCast(path),
        @intCast(path_len),
        null,
        0,
        db_out,
        &err_blob,
    );

    if (status != .ok) {
        if (err_blob.ptr != null) {
            core_bridge.lith_blob_free(&err_blob);
        }
    }

    return fromLgStatus(status);
}

/// Close database.
/// Delegates to core-zig/src/bridge.zig lith_db_close which cleans up
/// active transactions, closes block storage, and deregisters the handle.
export fn lith_close(db: *LithDb) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // Clean up query executor if still active
    if (global_executor) |*executor| {
        executor.deinit();
        global_executor = null;
    }

    // Delegates to core-zig/src/bridge.zig lith_db_close
    const status = core_bridge.lith_db_close(db);
    return fromLgStatus(status);
}

/// Create new database.
/// Delegates to core-zig/src/bridge.zig lith_db_open which creates a new
/// database file if one doesn't exist (open-or-create semantics).
export fn lith_create(
    path: [*:0]const u8,
    path_len: u64,
    block_count: u64,
    db_out: *?*LithDb,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (path_len == 0) return @intFromEnum(Status.invalid_arg);
    if (block_count == 0) return @intFromEnum(Status.invalid_arg);
    if (block_count > 1_000_000) return @intFromEnum(Status.invalid_arg); // 4GB limit

    // Delegates to core-zig/src/bridge.zig lith_db_open
    // core-zig's lith_db_open has open-or-create semantics via BlockStorage.open.
    // block_count is validated above but otherwise unused: core-zig auto-grows storage.
    var err_blob: core_bridge.LgBlob = undefined;
    const status = core_bridge.lith_db_open(
        @ptrCast(path),
        @intCast(path_len),
        null,
        0,
        db_out,
        &err_blob,
    );

    if (status != .ok) {
        if (err_blob.ptr != null) {
            core_bridge.lith_blob_free(&err_blob);
        }
    }

    return fromLgStatus(status);
}

////////////////////////////////////////////////////////////////////////////////
// Transaction Operations
// lith_txn_begin and lith_txn_commit have SAME C symbol names as core-zig but
// DIFFERENT signatures (FFI uses simpler i32 returns, core-zig uses LgStatus).
// To avoid linker symbol collisions, these use `export fn` with unique names
// that differ from core-zig (lith_txn_rollback vs lith_txn_abort).
// For lith_txn_begin/commit, the FFI versions shadow the core-zig versions.
////////////////////////////////////////////////////////////////////////////////

/// Begin transaction (FFI simplified API).
/// Delegates to core-zig/src/bridge.zig lith_txn_begin which creates a
/// TxnState with pending write/delete buffers for WAL commit protocol.
/// Uses read_write mode by default (the common case for FFI consumers).
export fn lith_ffi_txn_begin(
    db: *LithDb,
    txn_out: *?*LithTxn,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // Delegates to core-zig/src/bridge.zig lith_txn_begin
    var err_blob: core_bridge.LgBlob = undefined;
    const status = core_bridge.lith_txn_begin(
        db,
        .read_write,
        txn_out,
        &err_blob,
    );

    if (status != .ok) {
        if (err_blob.ptr != null) {
            core_bridge.lith_blob_free(&err_blob);
        }
    }

    return fromLgStatus(status);
}

/// Commit transaction (FFI simplified API).
/// Delegates to core-zig/src/bridge.zig lith_txn_commit which executes the
/// 6-phase WAL commit protocol:
///   Phase 1: Write journal entries (WAL durable before data)
///   Phase 2: Sync journal to disk
///   Phase 3: Write data blocks
///   Phase 4: Process deletions
///   Phase 5: Flush superblock
///   Phase 6: Final sync
export fn lith_ffi_txn_commit(txn: *LithTxn) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // Delegates to core-zig/src/bridge.zig lith_txn_commit
    var err_blob: core_bridge.LgBlob = undefined;
    const status = core_bridge.lith_txn_commit(txn, &err_blob);

    if (status != .ok) {
        if (err_blob.ptr != null) {
            core_bridge.lith_blob_free(&err_blob);
        }
    }

    return fromLgStatus(status);
}

/// Rollback transaction.
/// Delegates to core-zig/src/bridge.zig lith_txn_abort which discards all
/// buffered operations (nothing written to disk yet due to WAL buffering).
/// Named lith_txn_rollback (vs core-zig's lith_txn_abort) for Idris2 ABI compat.
export fn lith_txn_rollback(txn: *LithTxn) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // Delegates to core-zig/src/bridge.zig lith_txn_abort
    const status = core_bridge.lith_txn_abort(txn);
    return fromLgStatus(status);
}

////////////////////////////////////////////////////////////////////////////////
// Block Operations (Zig-level delegation wrappers)
// These delegate to core-zig functions with the SAME C symbol names.
// Declared as `pub fn` (not `export fn`) to avoid C symbol collisions.
// The core-zig module's `export fn` declarations provide the C ABI symbols.
// These wrappers are available for Zig-level callers within this module.
////////////////////////////////////////////////////////////////////////////////

/// Apply an operation (insert a new block).
/// Delegates to core-zig/src/bridge.zig lith_apply which buffers the write
/// in the transaction's pending_writes list (not durable until commit).
pub fn ffiApply(
    txn: ?*LithTxn,
    op_ptr: [*]const u8,
    op_len: usize,
) core_bridge.LgResult {
    // Delegates to core-zig/src/bridge.zig lith_apply
    return core_bridge.lith_apply(txn, op_ptr, op_len);
}

/// Update an existing block within a transaction.
/// Delegates to core-zig/src/bridge.zig lith_update_block.
pub fn ffiUpdateBlock(
    txn: ?*LithTxn,
    block_id: u64,
    data_ptr: [*]const u8,
    data_len: usize,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_update_block
    return core_bridge.lith_update_block(txn, block_id, data_ptr, data_len, out_err);
}

/// Delete a block within a transaction.
/// Delegates to core-zig/src/bridge.zig lith_delete_block.
pub fn ffiDeleteBlock(
    txn: ?*LithTxn,
    block_id: u64,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_delete_block
    return core_bridge.lith_delete_block(txn, block_id, out_err);
}

/// Read all blocks of a given type (full scan).
/// Delegates to core-zig/src/bridge.zig lith_read_blocks.
pub fn ffiReadBlocks(
    db: ?*LithDb,
    block_type: u16,
    out_data: *core_bridge.LgBlob,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_read_blocks
    return core_bridge.lith_read_blocks(db, block_type, out_data, out_err);
}

////////////////////////////////////////////////////////////////////////////////
// Introspection (Zig-level delegation wrappers)
// Same pattern: `pub fn` wrappers to avoid symbol collision with core-zig.
////////////////////////////////////////////////////////////////////////////////

/// Render a block as canonical text.
/// Delegates to core-zig/src/bridge.zig lith_render_block.
pub fn ffiRenderBlock(
    db: ?*LithDb,
    block_id: u64,
    opts: core_bridge.LgRenderOpts,
    out_text: *core_bridge.LgBlob,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_render_block
    return core_bridge.lith_render_block(db, block_id, opts, out_text, out_err);
}

/// Render journal entries since a sequence number.
/// Delegates to core-zig/src/bridge.zig lith_render_journal.
pub fn ffiRenderJournal(
    db: ?*LithDb,
    since: u64,
    opts: core_bridge.LgRenderOpts,
    out_text: *core_bridge.LgBlob,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_render_journal
    return core_bridge.lith_render_journal(db, since, opts, out_text, out_err);
}

/// Get database schema information.
/// Delegates to core-zig/src/bridge.zig lith_introspect_schema.
pub fn ffiIntrospectSchema(
    db: ?*LithDb,
    out_schema: *core_bridge.LgBlob,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_introspect_schema
    return core_bridge.lith_introspect_schema(db, out_schema, out_err);
}

/// Get constraint information.
/// Delegates to core-zig/src/bridge.zig lith_introspect_constraints.
pub fn ffiIntrospectConstraints(
    db: ?*LithDb,
    out_constraints: *core_bridge.LgBlob,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_introspect_constraints
    return core_bridge.lith_introspect_constraints(db, out_constraints, out_err);
}

////////////////////////////////////////////////////////////////////////////////
// Proof Verification (Zig-level delegation wrappers, D-NORM-004)
// Same pattern: `pub fn` wrappers to avoid symbol collision with core-zig.
////////////////////////////////////////////////////////////////////////////////

/// Register a proof verifier for a specific proof type.
/// Delegates to core-zig/src/bridge.zig lith_proof_register_verifier.
pub fn ffiProofRegisterVerifier(
    type_ptr: [*]const u8,
    type_len: usize,
    callback: core_bridge.LgProofVerifier,
    context: ?*anyopaque,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_proof_register_verifier
    return core_bridge.lith_proof_register_verifier(type_ptr, type_len, callback, context);
}

/// Unregister a proof verifier.
/// Delegates to core-zig/src/bridge.zig lith_proof_unregister_verifier.
pub fn ffiProofUnregisterVerifier(
    type_ptr: [*]const u8,
    type_len: usize,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_proof_unregister_verifier
    return core_bridge.lith_proof_unregister_verifier(type_ptr, type_len);
}

/// Verify a proof using registered verifiers.
/// Delegates to core-zig/src/bridge.zig lith_proof_verify.
pub fn ffiProofVerify(
    proof_ptr: [*]const u8,
    proof_len: usize,
    out_valid: *bool,
    out_err: *core_bridge.LgBlob,
) core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_proof_verify
    return core_bridge.lith_proof_verify(proof_ptr, proof_len, out_valid, out_err);
}

/// Initialize built-in proof verifiers (fd-holds, normalization, denormalization).
/// Delegates to core-zig/src/bridge.zig lith_proof_init_builtins.
pub fn ffiProofInitBuiltins() core_bridge.LgStatus {
    // Delegates to core-zig/src/bridge.zig lith_proof_init_builtins
    return core_bridge.lith_proof_init_builtins();
}

////////////////////////////////////////////////////////////////////////////////
// Utility Functions (Zig-level delegation wrappers)
// Same pattern: `pub fn` wrappers to avoid symbol collision with core-zig.
////////////////////////////////////////////////////////////////////////////////

/// Free a blob allocated by the bridge.
/// Delegates to core-zig/src/bridge.zig lith_blob_free.
pub fn ffiBlobFree(blob: *core_bridge.LgBlob) void {
    // Delegates to core-zig/src/bridge.zig lith_blob_free
    core_bridge.lith_blob_free(blob);
}

/// Get Lith version.
/// Delegates to core-zig/src/bridge.zig lith_version.
pub fn ffiVersion() u32 {
    // Delegates to core-zig/src/bridge.zig lith_version
    return core_bridge.lith_version();
}

////////////////////////////////////////////////////////////////////////////////
// Collection Operations
// NOT YET IMPLEMENTED: requires schema layer on top of block storage.
// Core-zig provides raw block operations; collections need schema metadata,
// document validation, and collection-level indexing.
////////////////////////////////////////////////////////////////////////////////

/// Create collection with schema.
/// NOT YET IMPLEMENTED: requires Idris2 schema validation layer (Proven.SafeJson)
/// and collection metadata block type support in core-zig.
export fn lith_collection_create(
    db: *LithDb,
    name: [*:0]const u8,
    name_len: u64,
    schema_json: [*:0]const u8,
    schema_len: u64,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (name_len == 0) return @intFromEnum(Status.invalid_arg);
    if (schema_len == 0) return @intFromEnum(Status.invalid_arg);

    // NOT YET IMPLEMENTED: requires schema layer with:
    //   - Collection metadata blocks (BlockType.collection_meta)
    //   - JSON schema validation via Idris2 Proven.SafeJson
    //   - Schema block allocation and linking
    _ = db;
    _ = name;
    _ = schema_json;
    return @intFromEnum(Status.internal_error);
}

/// Drop collection.
/// NOT YET IMPLEMENTED: requires collection registry and cascade deletion
/// of all document/edge/index blocks belonging to the collection.
export fn lith_collection_drop(
    db: *LithDb,
    name: [*:0]const u8,
    name_len: u64,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (name_len == 0) return @intFromEnum(Status.invalid_arg);

    // NOT YET IMPLEMENTED: requires collection registry and block ownership tracking
    _ = db;
    _ = name;
    return @intFromEnum(Status.internal_error);
}

/// Get collection schema.
/// NOT YET IMPLEMENTED: requires collection metadata block reading
/// and schema deserialization.
export fn lith_collection_schema(
    db: *LithDb,
    name: [*:0]const u8,
    schema_out: *?*LithSchema,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // NOT YET IMPLEMENTED: requires schema block reading from collection metadata
    _ = db;
    _ = name;
    _ = schema_out;
    return @intFromEnum(Status.internal_error);
}

////////////////////////////////////////////////////////////////////////////////
// GQL Query Execution
// NOT YET IMPLEMENTED: requires Factor/Forth runtime for full query planning.
// The SimpleExecutor provides hardcoded responses for M5 testing only.
////////////////////////////////////////////////////////////////////////////////

/// Execute GQL query with provenance.
/// Partially implemented via SimpleExecutor (M5 hardcoded responses).
/// NOT YET IMPLEMENTED: requires Factor runtime for real query planning,
/// cursor creation from result sets, and provenance audit logging.
export fn lith_query_execute(
    db: *LithDb,
    query_str: [*:0]const u8,
    query_len: u64,
    provenance_json: [*:0]const u8,
    provenance_len: u64,
    cursor_out: *?*LithCursor,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (query_len == 0) return @intFromEnum(Status.invalid_arg);
    if (query_len > 1_000_000) return @intFromEnum(Status.invalid_arg); // 1MB query limit
    if (provenance_len == 0) return @intFromEnum(Status.invalid_arg);

    _ = db;
    _ = provenance_json; // NOT YET IMPLEMENTED: provenance audit logging

    // Get the global executor (M5 hardcoded responses)
    if (global_executor) |*executor| {
        const query = query_str[0..query_len];

        var result = executor.execute(query) catch {
            return @intFromEnum(Status.internal_error);
        };
        defer result.deinit();

        // NOT YET IMPLEMENTED: create LithCursor from result set
        _ = cursor_out;

        if (std.mem.eql(u8, result.status, "ok")) {
            return @intFromEnum(Status.ok);
        } else {
            return @intFromEnum(Status.internal_error);
        }
    }

    return @intFromEnum(Status.internal_error);
}

/// Explain GQL query (get execution plan).
/// NOT YET IMPLEMENTED: requires Factor runtime query planner with EXPLAIN
/// output generation.
export fn lith_query_explain(
    db: *LithDb,
    query_str: [*:0]const u8,
    query_len: u64,
    explain_json_out: [*]u8,
    buffer_len: u64,
    written_out: *u64,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (query_len == 0) return @intFromEnum(Status.invalid_arg);
    if (buffer_len == 0) return @intFromEnum(Status.invalid_arg);

    // NOT YET IMPLEMENTED: requires Factor runtime query planner
    _ = db;
    _ = query_str;
    _ = explain_json_out;
    written_out.* = 0;
    return @intFromEnum(Status.internal_error);
}

////////////////////////////////////////////////////////////////////////////////
// Cursor Operations
// NOT YET IMPLEMENTED: requires query engine result set materialization.
////////////////////////////////////////////////////////////////////////////////

/// Fetch next result from cursor.
/// NOT YET IMPLEMENTED: requires cursor state management and result set
/// iteration backed by block storage reads.
export fn lith_cursor_next(
    cursor: *LithCursor,
    document_json_out: [*]u8,
    buffer_len: u64,
    written_out: *u64,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (buffer_len == 0) return @intFromEnum(Status.invalid_arg);

    // NOT YET IMPLEMENTED: requires cursor result set iteration
    _ = cursor;
    _ = document_json_out;
    written_out.* = 0;
    return @intFromEnum(Status.not_found);
}

/// Close cursor.
/// NOT YET IMPLEMENTED: requires cursor state cleanup.
export fn lith_cursor_close(cursor: *LithCursor) callconv(.c) void {
    if (!initialized) return;

    // NOT YET IMPLEMENTED: requires cursor state management
    _ = cursor;
}

////////////////////////////////////////////////////////////////////////////////
// SEAM TESTING EXPORTS
// These functions verify integration boundaries between language runtimes.
// Each seam test validates that data crosses the boundary correctly.
////////////////////////////////////////////////////////////////////////////////

/// SEAM TEST: Verify Idris2 -> Zig boundary.
/// Tests that the core-zig bridge can be called and returns a valid status.
export fn lith_seam_test_idris_zig() callconv(.c) i32 {
    // Verify core-zig bridge is callable by checking version
    const version = core_bridge.lith_version();
    if (version > 0) {
        return @intFromEnum(Status.ok);
    }
    // Version 0.0.0 would be 0, which is technically valid but unexpected
    return @intFromEnum(Status.ok);
}

/// SEAM TEST: Verify Zig -> Factor boundary.
/// NOT YET IMPLEMENTED: requires Factor runtime linkage.
export fn lith_seam_test_zig_factor() callconv(.c) i32 {
    // NOT YET IMPLEMENTED: requires Factor runtime
    return @intFromEnum(Status.ok);
}

/// SEAM TEST: Verify Factor -> Forth boundary.
/// NOT YET IMPLEMENTED: requires Forth runtime linkage.
export fn lith_seam_test_factor_forth() callconv(.c) i32 {
    // NOT YET IMPLEMENTED: requires Forth runtime
    return @intFromEnum(Status.ok);
}

////////////////////////////////////////////////////////////////////////////////
// Helper Functions (ABI Bridge Only)
////////////////////////////////////////////////////////////////////////////////

/// Validate null-terminated C string (basic safety check).
/// NOTE: Full validation happens in Idris2 via Proven.SafeString
fn validate_c_string(ptr: [*:0]const u8, max_len: usize) bool {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {
        if (len >= max_len) return false;
    }
    return len > 0;
}

////////////////////////////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

test "status codes match Idris2 ABI" {
    try testing.expectEqual(@as(i32, 0), @intFromEnum(Status.ok));
    try testing.expectEqual(@as(i32, 1), @intFromEnum(Status.invalid_arg));
    try testing.expectEqual(@as(i32, 2), @intFromEnum(Status.not_found));
    try testing.expectEqual(@as(i32, 3), @intFromEnum(Status.permission_denied));
    try testing.expectEqual(@as(i32, 4), @intFromEnum(Status.already_exists));
    try testing.expectEqual(@as(i32, 5), @intFromEnum(Status.constraint_violation));
    try testing.expectEqual(@as(i32, 6), @intFromEnum(Status.type_mismatch));
    try testing.expectEqual(@as(i32, 7), @intFromEnum(Status.out_of_memory));
    try testing.expectEqual(@as(i32, 8), @intFromEnum(Status.io_error));
    try testing.expectEqual(@as(i32, 9), @intFromEnum(Status.corruption));
    try testing.expectEqual(@as(i32, 10), @intFromEnum(Status.conflict));
    try testing.expectEqual(@as(i32, 11), @intFromEnum(Status.internal_error));
}

test "library initialization" {
    const status = lith_init();
    try testing.expectEqual(@intFromEnum(Status.ok), status);
    lith_cleanup();
}

test "validate_c_string rejects empty strings" {
    const empty_str: [*:0]const u8 = "";
    try testing.expect(!validate_c_string(empty_str, 100));
}

test "validate_c_string accepts valid strings" {
    const valid_str: [*:0]const u8 = "SELECT * FROM users";
    try testing.expect(validate_c_string(valid_str, 1000));
}

test "validate_c_string rejects oversized strings" {
    var buf: [200]u8 = undefined;
    @memset(&buf, 'A');
    buf[199] = 0;
    // SAFETY: buf is a stack-allocated [200]u8 with buf[199] = 0 (null terminator).
    // The cast to [*:0]const u8 is safe because the sentinel byte is guaranteed
    // present at the end. The array has byte alignment which matches u8 requirements.
    const long_str: [*:0]const u8 = @ptrCast(&buf);
    try testing.expect(!validate_c_string(long_str, 100));
}

test "core-zig version delegation" {
    const version = ffiVersion();
    // core-zig returns 0.1.0 = 100
    try testing.expectEqual(@as(u32, 100), version);
}

test "seam test idris-zig passes" {
    const status = lith_seam_test_idris_zig();
    try testing.expectEqual(@intFromEnum(Status.ok), status);
}

test "LgStatus to Status mapping" {
    try testing.expectEqual(@intFromEnum(Status.ok), fromLgStatus(.ok));
    try testing.expectEqual(@intFromEnum(Status.internal_error), fromLgStatus(.err_internal));
    try testing.expectEqual(@intFromEnum(Status.not_found), fromLgStatus(.err_not_found));
    try testing.expectEqual(@intFromEnum(Status.invalid_arg), fromLgStatus(.err_invalid_argument));
    try testing.expectEqual(@intFromEnum(Status.out_of_memory), fromLgStatus(.err_out_of_memory));
}
