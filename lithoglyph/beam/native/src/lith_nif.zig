// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Lith BEAM NIF - Zig implementation
//
// This NIF connects BEAM (Erlang/Gleam/Elixir) to Lith via the Lith C ABI.
// Uses CBOR-encoded binaries for efficient data transfer.
//
// The NIF delegates all storage operations to the core bridge (generated/abi/bridge.h)
// via C ABI extern declarations. Error codes from the bridge are translated to
// BEAM-style {:ok, result} / {:error, reason} tuples.

const std = @import("std");
const beam = @import("beam.zig");

// ============================================================
// Lith C ABI declarations (from generated/abi/bridge.h)
//
// These extern functions are provided by liblith.so (the Zig FFI
// bridge implementation at ffi/zig/src/bridge.zig). The NIF shared
// library links against liblith at load time.
// ============================================================

/// Opaque database handle from the core bridge
const FdbDb = opaque {};

/// Opaque transaction handle from the core bridge
const FdbTxn = opaque {};

/// Owned byte buffer passed across the FFI boundary
const LgBlob = extern struct {
    ptr: ?[*]const u8,
    len: usize,
};

/// Result type for operations returning data + provenance
const LgResult = extern struct {
    data: LgBlob,
    provenance: LgBlob,
    status: c_int, // FdbStatus
    error_blob: LgBlob,
};

/// Transaction mode
const LgTxnMode = enum(c_int) {
    read_only = 0,
    read_write = 1,
};

/// Render options for introspection functions
const LgRenderOpts = extern struct {
    format: c_int, // 0 = JSON
    include_metadata: bool,
};

/// FdbStatus codes (must match bridge.h FdbStatus enum)
const FdbStatus = enum(c_int) {
    ok = 0,
    err_internal = 1,
    err_not_found = 2,
    err_invalid_argument = 3,
    err_out_of_memory = 4,
    err_not_implemented = 5,
    err_txn_not_active = 6,
    err_txn_already_committed = 7,
    err_io_error = 8,
    err_corruption = 9,
    err_conflict = 10,
    err_already_exists = 11,
};

// --- Extern C ABI bridge functions ---

extern fn fdb_db_open(
    path_ptr: [*]const u8,
    path_len: usize,
    opts_ptr: ?[*]const u8,
    opts_len: usize,
    out_db: *?*FdbDb,
    out_err: *LgBlob,
) callconv(.c) c_int;

extern fn fdb_db_close(db: *FdbDb) callconv(.c) c_int;

extern fn fdb_txn_begin(
    db: *FdbDb,
    mode: LgTxnMode,
    out_txn: *?*FdbTxn,
    out_err: *LgBlob,
) callconv(.c) c_int;

extern fn fdb_txn_commit(txn: *FdbTxn, out_err: *LgBlob) callconv(.c) c_int;

extern fn fdb_txn_abort(txn: *FdbTxn) callconv(.c) c_int;

extern fn fdb_apply(
    txn: *FdbTxn,
    op_ptr: [*]const u8,
    op_len: usize,
) callconv(.c) LgResult;

extern fn fdb_introspect_schema(
    db: *FdbDb,
    out_schema: *LgBlob,
    out_err: *LgBlob,
) callconv(.c) c_int;

extern fn fdb_render_journal(
    db: *FdbDb,
    since: u64,
    opts: LgRenderOpts,
    out_text: *LgBlob,
    out_err: *LgBlob,
) callconv(.c) c_int;

extern fn fdb_blob_free(blob: *LgBlob) callconv(.c) void;

extern fn fdb_version() callconv(.c) u32;

/// Convert an FdbStatus integer to an atom name for BEAM error tuples.
/// Returns a descriptive atom string for each known status code.
fn status_to_atom(status: c_int) [*:0]const u8 {
    return switch (status) {
        0 => "ok",
        1 => "internal_error",
        2 => "not_found",
        3 => "invalid_argument",
        4 => "out_of_memory",
        5 => "not_implemented",
        6 => "txn_not_active",
        7 => "txn_already_committed",
        8 => "io_error",
        9 => "corruption",
        10 => "conflict",
        11 => "already_exists",
        else => "unknown_error",
    };
}

// Global allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Resource types (initialized in nif_init)
var db_handle_type: ?*beam.resource_type = undefined;
var txn_handle_type: ?*beam.resource_type = undefined;

// Database handle wrapper — holds an opaque FdbDb pointer from the core bridge.
const DbHandle = struct {
    fdb: *FdbDb,
    path: []const u8,

    /// Open a database via the core bridge C ABI (fdb_db_open).
    fn create(path: []const u8) !*DbHandle {
        var out_db: ?*FdbDb = null;
        var out_err: LgBlob = .{ .ptr = null, .len = 0 };

        const status = fdb_db_open(
            path.ptr,
            path.len,
            null, // no options
            0,
            &out_db,
            &out_err,
        );

        // Free error blob regardless of outcome
        if (out_err.ptr != null) fdb_blob_free(&out_err);

        if (status != @intFromEnum(FdbStatus.ok) or out_db == null) {
            return error.InitFailed;
        }

        const db = try allocator.create(DbHandle);
        db.* = .{
            .fdb = out_db.?,
            .path = try allocator.dupe(u8, path),
        };

        return db;
    }

    /// Close the database via the core bridge C ABI (fdb_db_close) and free memory.
    fn destroy(self: *DbHandle) void {
        _ = fdb_db_close(self.fdb);
        allocator.free(self.path);
        allocator.destroy(self);
    }
};

// Transaction handle wrapper — holds an opaque FdbTxn pointer from the core bridge.
const TxnHandle = struct {
    fdb_txn: *FdbTxn,
    db: *DbHandle,
    mode: TransactionMode,

    const TransactionMode = enum {
        read_only,
        read_write,

        /// Convert to the C ABI LgTxnMode enum for bridge calls.
        fn to_lg_mode(self: TransactionMode) LgTxnMode {
            return switch (self) {
                .read_only => .read_only,
                .read_write => .read_write,
            };
        }
    };
};

//==============================================================================
// NIF Functions
//==============================================================================

/// Get Lith version from the core bridge.
/// The bridge encodes version as: major * 10000 + minor * 100 + patch.
/// Returns {Major, Minor, Patch} tuple.
export fn version(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    _ = argc;
    _ = argv;

    const ver = fdb_version();
    const major: c_int = @intCast(ver / 10000);
    const minor: c_int = @intCast((ver % 10000) / 100);
    const patch: c_int = @intCast(ver % 100);

    return beam.make_tuple3(env,
        beam.make_int(env, major),
        beam.make_int(env, minor),
        beam.make_int(env, patch),
    );
}

/// Open a Lith database
/// Parameters: Path (binary)
/// Returns: {ok, DbRef} | {error, Reason}
export fn db_open(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 1) {
        return beam.make_badarg(env);
    }

    // Get path as binary
    var path_bin: beam.binary = undefined;
    if (beam.get_binary(env, argv[0], &path_bin) == 0) {
        return beam.make_badarg(env);
    }

    const path = path_bin.data[0..path_bin.size];

    // Create database handle
    const db = DbHandle.create(path) catch {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "init_failed")
        );
    };

    // Create resource (opaque reference for Erlang)
    const db_res = beam.alloc_resource(env, db, db_handle_type) catch {
        db.destroy();
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "resource_alloc_failed")
        );
    };

    return beam.make_tuple2(env,
        beam.make_atom(env, "ok"),
        db_res
    );
}

/// Close a Lith database
/// Parameters: DbRef (resource)
/// Returns: ok | {error, Reason}
export fn db_close(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 1) {
        return beam.make_badarg(env);
    }

    // Get database handle
    const db_ptr = beam.get_resource(env, argv[0], DbHandle, db_handle_type) catch {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "invalid_handle")
        );
    };

    // SAFETY: db_ptr comes from beam.get_resource() which retrieves the pointer
    // originally stored by beam.alloc_resource() in db_open. The NIF resource system
    // guarantees the pointer is valid while the resource reference is live. Alignment
    // is met because DbHandle was heap-allocated by allocator.create(DbHandle).
    const db: *DbHandle = @ptrCast(@alignCast(db_ptr));
    db.destroy();

    return beam.make_atom(env, "ok");
}

/// Begin a transaction
/// Parameters: DbRef, Mode (read_only | read_write)
/// Returns: {ok, TxnRef} | {error, Reason}
export fn txn_begin(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 2) {
        return beam.make_badarg(env);
    }

    // Get database handle
    const db_ptr = beam.get_resource(env, argv[0], DbHandle, db_handle_type) catch {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "invalid_handle")
        );
    };

    // SAFETY: db_ptr comes from beam.get_resource() which retrieves the pointer
    // originally stored by beam.alloc_resource() in db_open. The NIF resource system
    // guarantees the pointer is valid while the resource reference is live. Alignment
    // is met because DbHandle was heap-allocated by allocator.create(DbHandle).
    const db: *DbHandle = @ptrCast(@alignCast(db_ptr));

    // Get transaction mode
    var mode_atom: [32]u8 = undefined;
    const mode_len = beam.get_atom(env, argv[1], &mode_atom);
    if (mode_len == 0) {
        return beam.make_badarg(env);
    }

    const mode_str = mode_atom[0..mode_len];
    const mode: TxnHandle.TransactionMode = if (std.mem.eql(u8, mode_str, "read_only"))
        .read_only
    else if (std.mem.eql(u8, mode_str, "read_write"))
        .read_write
    else
        return beam.make_badarg(env);

    // Begin transaction via the core bridge C ABI (fdb_txn_begin)
    var out_txn: ?*FdbTxn = null;
    var out_err: LgBlob = .{ .ptr = null, .len = 0 };

    const status = fdb_txn_begin(
        db.fdb,
        mode.to_lg_mode(),
        &out_txn,
        &out_err,
    );

    // Free error blob regardless of outcome
    if (out_err.ptr != null) fdb_blob_free(&out_err);

    if (status != @intFromEnum(FdbStatus.ok) or out_txn == null) {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, status_to_atom(status)),
        );
    }

    // Create transaction handle wrapping the bridge FdbTxn
    const txn = allocator.create(TxnHandle) catch {
        // Abort the bridge transaction to avoid leaking it
        _ = fdb_txn_abort(out_txn.?);
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "alloc_failed"),
        );
    };

    txn.* = .{
        .fdb_txn = out_txn.?,
        .db = db,
        .mode = mode,
    };

    // Create resource
    const txn_res = beam.alloc_resource(env, txn, txn_handle_type) catch {
        _ = fdb_txn_abort(out_txn.?);
        allocator.destroy(txn);
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "resource_alloc_failed"),
        );
    };

    return beam.make_tuple2(env,
        beam.make_atom(env, "ok"),
        txn_res,
    );
}

/// Commit a transaction
/// Parameters: TxnRef
/// Returns: ok | {error, Reason}
export fn txn_commit(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 1) {
        return beam.make_badarg(env);
    }

    // Get transaction handle
    const txn_ptr = beam.get_resource(env, argv[0], TxnHandle, txn_handle_type) catch {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "invalid_handle")
        );
    };

    // SAFETY: txn_ptr comes from beam.get_resource() which retrieves the pointer
    // originally stored by beam.alloc_resource() in txn_begin. The NIF resource
    // system guarantees the pointer is valid while the resource reference is live.
    // Alignment is met because TxnHandle was heap-allocated by allocator.create().
    const txn: *TxnHandle = @ptrCast(@alignCast(txn_ptr));

    // Commit the transaction via the core bridge C ABI (fdb_txn_commit).
    // This executes the 6-phase WAL: journal -> sync -> blocks -> deletes -> superblock -> sync.
    var out_err: LgBlob = .{ .ptr = null, .len = 0 };
    const status = fdb_txn_commit(txn.fdb_txn, &out_err);

    // Free error blob regardless of outcome
    if (out_err.ptr != null) fdb_blob_free(&out_err);

    // Clean up the Zig-side wrapper regardless of commit outcome
    allocator.destroy(txn);

    if (status != @intFromEnum(FdbStatus.ok)) {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, status_to_atom(status)),
        );
    }

    return beam.make_atom(env, "ok");
}

/// Abort a transaction, discarding all buffered operations.
/// Parameters: TxnRef
/// Returns: ok | {error, Reason}
export fn txn_abort(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 1) {
        return beam.make_badarg(env);
    }

    // Get transaction handle
    const txn_ptr = beam.get_resource(env, argv[0], TxnHandle, txn_handle_type) catch {
        return beam.make_atom(env, "ok"); // Already aborted/invalid
    };

    // SAFETY: txn_ptr comes from beam.get_resource() which retrieves the pointer
    // originally stored by beam.alloc_resource() in txn_begin. The NIF resource
    // system guarantees the pointer is valid while the resource reference is live.
    // Alignment is met because TxnHandle was heap-allocated by allocator.create().
    const txn: *TxnHandle = @ptrCast(@alignCast(txn_ptr));

    // Abort the transaction via the core bridge C ABI (fdb_txn_abort).
    const status = fdb_txn_abort(txn.fdb_txn);

    // Clean up the Zig-side wrapper regardless of abort outcome
    allocator.destroy(txn);

    if (status != @intFromEnum(FdbStatus.ok)) {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, status_to_atom(status)),
        );
    }

    return beam.make_atom(env, "ok");
}

/// Apply an operation within a transaction via the core bridge.
/// The bridge buffers writes until commit (6-phase WAL).
/// Parameters: TxnRef, OpCbor (binary)
/// Returns: {ok, ResultCbor} | {ok, ResultCbor, ProvenanceCbor} | {error, Reason}
export fn apply(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 2) {
        return beam.make_badarg(env);
    }

    // Get transaction handle
    const txn_ptr = beam.get_resource(env, argv[0], TxnHandle, txn_handle_type) catch {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "invalid_handle"),
        );
    };

    // SAFETY: txn_ptr comes from beam.get_resource() which retrieves the pointer
    // originally stored by beam.alloc_resource() in txn_begin. The NIF resource
    // system guarantees the pointer is valid while the resource reference is live.
    // Alignment is met because TxnHandle was heap-allocated by allocator.create().
    const txn: *TxnHandle = @ptrCast(@alignCast(txn_ptr));

    // Get CBOR operation binary
    var cbor_bin: beam.binary = undefined;
    if (beam.get_binary(env, argv[1], &cbor_bin) == 0) {
        return beam.make_badarg(env);
    }

    if (cbor_bin.size == 0 or cbor_bin.size > 1_048_576) {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "invalid_argument"),
        );
    }

    const cbor_data = cbor_bin.data[0..cbor_bin.size];

    // Apply the operation via the core bridge C ABI (fdb_apply).
    // The bridge parses the CBOR/JSON payload, validates it, and buffers the write.
    const result: LgResult = fdb_apply(txn.fdb_txn, cbor_data.ptr, cbor_data.len);

    if (result.status != @intFromEnum(FdbStatus.ok)) {
        // Free any blobs the bridge may have allocated
        var err_blob = result.error_blob;
        if (err_blob.ptr != null) fdb_blob_free(&err_blob);
        var data_blob = result.data;
        if (data_blob.ptr != null) fdb_blob_free(&data_blob);

        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, status_to_atom(result.status)),
        );
    }

    // Build the result binary from the bridge data blob
    const result_bin = blk: {
        if (result.data.ptr != null and result.data.len > 0) {
            // SAFETY: result.data.ptr is non-null and result.data.len > 0 (checked above).
            // The bridge guarantees the pointer is valid until fdb_blob_free() is called.
            // We copy the data into a BEAM binary before freeing, so no use-after-free.
            const data_slice = result.data.ptr.?[0..result.data.len];
            break :blk beam.make_binary(env, data_slice) catch {
                var data_blob = result.data;
                fdb_blob_free(&data_blob);
                var prov_blob = result.provenance;
                if (prov_blob.ptr != null) fdb_blob_free(&prov_blob);
                return beam.make_tuple2(env,
                    beam.make_atom(env, "error"),
                    beam.make_atom(env, "result_alloc_failed"),
                );
            };
        } else {
            // No data returned — return empty binary
            const empty = [_]u8{};
            break :blk beam.make_binary(env, &empty) catch {
                return beam.make_tuple2(env,
                    beam.make_atom(env, "error"),
                    beam.make_atom(env, "result_alloc_failed"),
                );
            };
        }
    };

    // Include provenance token in response if the bridge provided one
    const has_provenance = result.provenance.ptr != null and result.provenance.len > 0;

    if (has_provenance) {
        // SAFETY: result.provenance.ptr is non-null and result.provenance.len > 0 (checked above).
        // The bridge guarantees the pointer is valid until fdb_blob_free() is called.
        // We copy the data into a BEAM binary before freeing.
        const prov_slice = result.provenance.ptr.?[0..result.provenance.len];
        const prov_bin = beam.make_binary(env, prov_slice) catch {
            var data_blob = result.data;
            if (data_blob.ptr != null) fdb_blob_free(&data_blob);
            var prov_blob = result.provenance;
            fdb_blob_free(&prov_blob);
            return beam.make_tuple2(env,
                beam.make_atom(env, "error"),
                beam.make_atom(env, "result_alloc_failed"),
            );
        };

        // Free bridge blobs now that data is copied into BEAM binaries
        var data_blob = result.data;
        if (data_blob.ptr != null) fdb_blob_free(&data_blob);
        var prov_blob = result.provenance;
        fdb_blob_free(&prov_blob);

        return beam.make_tuple3(env,
            beam.make_atom(env, "ok"),
            result_bin,
            prov_bin,
        );
    }

    // Free bridge data blob (no provenance to free)
    var data_blob = result.data;
    if (data_blob.ptr != null) fdb_blob_free(&data_blob);

    return beam.make_tuple2(env,
        beam.make_atom(env, "ok"),
        result_bin,
    );
}

/// Get database schema via the core bridge (fdb_introspect_schema).
/// Parameters: DbRef
/// Returns: {ok, SchemaJson} | {error, Reason}
export fn schema(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 1) {
        return beam.make_badarg(env);
    }

    // Get database handle from resource
    const db_ptr = beam.get_resource(env, argv[0], DbHandle, db_handle_type) catch {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "invalid_handle"),
        );
    };

    // SAFETY: db_ptr comes from beam.get_resource() which retrieves the pointer
    // originally stored by beam.alloc_resource() in db_open. The NIF resource system
    // guarantees the pointer is valid while the resource reference is live. Alignment
    // is met because DbHandle was heap-allocated by allocator.create(DbHandle).
    const db: *DbHandle = @ptrCast(@alignCast(db_ptr));

    // Call the core bridge to introspect the schema
    var out_schema: LgBlob = .{ .ptr = null, .len = 0 };
    var out_err: LgBlob = .{ .ptr = null, .len = 0 };

    const status = fdb_introspect_schema(db.fdb, &out_schema, &out_err);

    // Free error blob regardless of outcome
    if (out_err.ptr != null) fdb_blob_free(&out_err);

    if (status != @intFromEnum(FdbStatus.ok)) {
        if (out_schema.ptr != null) fdb_blob_free(&out_schema);
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, status_to_atom(status)),
        );
    }

    // Copy schema data into a BEAM binary
    const schema_bin = blk: {
        if (out_schema.ptr != null and out_schema.len > 0) {
            // SAFETY: out_schema.ptr is non-null and out_schema.len > 0 (checked above).
            // The bridge guarantees the pointer is valid until fdb_blob_free() is called.
            const schema_slice = out_schema.ptr.?[0..out_schema.len];
            break :blk beam.make_binary(env, schema_slice) catch {
                fdb_blob_free(&out_schema);
                return beam.make_tuple2(env,
                    beam.make_atom(env, "error"),
                    beam.make_atom(env, "alloc_failed"),
                );
            };
        } else {
            // No schema data — return empty JSON object
            const empty_map = [_]u8{ '{', '}' };
            break :blk beam.make_binary(env, &empty_map) catch {
                return beam.make_tuple2(env,
                    beam.make_atom(env, "error"),
                    beam.make_atom(env, "alloc_failed"),
                );
            };
        }
    };

    // Free the bridge blob now that data is copied
    if (out_schema.ptr != null) fdb_blob_free(&out_schema);

    return beam.make_tuple2(env,
        beam.make_atom(env, "ok"),
        schema_bin,
    );
}

/// Get journal entries since a sequence number via the core bridge (fdb_render_journal).
/// Parameters: DbRef, Since (integer)
/// Returns: {ok, JournalJson} | {error, Reason}
export fn journal(env: ?*beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    if (argc != 2) {
        return beam.make_badarg(env);
    }

    // Get database handle from resource
    const db_ptr = beam.get_resource(env, argv[0], DbHandle, db_handle_type) catch {
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, "invalid_handle"),
        );
    };

    // SAFETY: db_ptr comes from beam.get_resource() which retrieves the pointer
    // originally stored by beam.alloc_resource() in db_open. The NIF resource system
    // guarantees the pointer is valid while the resource reference is live. Alignment
    // is met because DbHandle was heap-allocated by allocator.create(DbHandle).
    const db: *DbHandle = @ptrCast(@alignCast(db_ptr));

    // Get the 'since' sequence number
    var since_val: c_int = undefined;
    // Use beam.make_int to check — we need to extract the integer from term.
    // The NIF C API provides enif_get_int for this.
    since_val = nif_get_int(env, argv[1]) orelse {
        return beam.make_badarg(env);
    };

    const since: u64 = if (since_val >= 0)
        @intCast(since_val)
    else
        0; // Negative since is treated as "from the beginning"

    // Render journal entries via the core bridge
    const opts: LgRenderOpts = .{
        .format = 0, // JSON
        .include_metadata = true,
    };
    var out_text: LgBlob = .{ .ptr = null, .len = 0 };
    var out_err: LgBlob = .{ .ptr = null, .len = 0 };

    const status = fdb_render_journal(db.fdb, since, opts, &out_text, &out_err);

    // Free error blob regardless of outcome
    if (out_err.ptr != null) fdb_blob_free(&out_err);

    if (status != @intFromEnum(FdbStatus.ok)) {
        if (out_text.ptr != null) fdb_blob_free(&out_text);
        return beam.make_tuple2(env,
            beam.make_atom(env, "error"),
            beam.make_atom(env, status_to_atom(status)),
        );
    }

    // Copy journal data into a BEAM binary
    const journal_bin = blk: {
        if (out_text.ptr != null and out_text.len > 0) {
            // SAFETY: out_text.ptr is non-null and out_text.len > 0 (checked above).
            // The bridge guarantees the pointer is valid until fdb_blob_free() is called.
            const text_slice = out_text.ptr.?[0..out_text.len];
            break :blk beam.make_binary(env, text_slice) catch {
                fdb_blob_free(&out_text);
                return beam.make_tuple2(env,
                    beam.make_atom(env, "error"),
                    beam.make_atom(env, "alloc_failed"),
                );
            };
        } else {
            // No journal entries — return empty JSON array
            const empty_array = [_]u8{ '[', ']' };
            break :blk beam.make_binary(env, &empty_array) catch {
                return beam.make_tuple2(env,
                    beam.make_atom(env, "error"),
                    beam.make_atom(env, "alloc_failed"),
                );
            };
        }
    };

    // Free the bridge blob now that data is copied
    if (out_text.ptr != null) fdb_blob_free(&out_text);

    return beam.make_tuple2(env,
        beam.make_atom(env, "ok"),
        journal_bin,
    );
}

/// Helper: extract a C int from a BEAM term. Returns null if the term is not an integer.
fn nif_get_int(e: ?*beam.env, t: beam.term) ?c_int {
    var val: c_int = undefined;
    if (enif_get_int(e, t, &val) == 0) {
        return null;
    }
    return val;
}

// Additional extern needed for integer extraction
extern fn enif_get_int(env: ?*beam.env, term: beam.term, ip: *c_int) callconv(.c) c_int;

//==============================================================================
// NIF Initialization
//==============================================================================

const nif_funcs = [_]beam.ErlNifFunc{
    .{ .name = "version", .arity = 0, .fptr = version, .flags = 0 },
    .{ .name = "db_open", .arity = 1, .fptr = db_open, .flags = 0 },
    .{ .name = "db_close", .arity = 1, .fptr = db_close, .flags = 0 },
    .{ .name = "txn_begin", .arity = 2, .fptr = txn_begin, .flags = 0 },
    .{ .name = "txn_commit", .arity = 1, .fptr = txn_commit, .flags = 0 },
    .{ .name = "txn_abort", .arity = 1, .fptr = txn_abort, .flags = 0 },
    .{ .name = "apply", .arity = 2, .fptr = apply, .flags = 0 },
    .{ .name = "schema", .arity = 1, .fptr = schema, .flags = 0 },
    .{ .name = "journal", .arity = 2, .fptr = journal, .flags = 0 },
};

export fn nif_init(env: ?*beam.env, priv_data: [*c]?*anyopaque, load_info: beam.term) c_int {
    _ = priv_data;
    _ = load_info;

    // Check env is valid
    if (env == null) {
        return 1;
    }

    // Register resource types
    db_handle_type = beam.open_resource_type(env, "db_handle", null) catch {
        return 1;
    };

    txn_handle_type = beam.open_resource_type(env, "txn_handle", null) catch {
        return 1;
    };

    return 0;
}

export const nif_entry = beam.ErlNifEntry{
    .major = beam.ERL_NIF_MAJOR_VERSION,
    .minor = beam.ERL_NIF_MINOR_VERSION,
    .name = "lith_nif",
    .num_of_funcs = nif_funcs.len,
    // SAFETY: nif_funcs is a file-level const array of ErlNifFunc structs with
    // stable lifetime (static storage). The @constCast is required because the
    // ErlNifEntry C ABI expects a mutable pointer, but the BEAM runtime only
    // reads from this array. The @ptrCast converts [*]ErlNifFunc to [*c]const
    // ErlNifFunc to match the C ABI pointer convention.
    .funcs = @ptrCast(@constCast(&nif_funcs)),
    .load = nif_init,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(beam.ErlNifResourceTypeInit),
};
