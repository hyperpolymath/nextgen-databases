// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph NIF Implementation in Zig
//
// This implements the C-compatible ABI defined in ../../../src/abi/Foreign.idr
// All functions follow the memory layout guarantees from ../../../src/abi/Layout.idr

const std = @import("std");
const c = @cImport({
    @cInclude("erl_nif.h");
});

// Opaque handle types (matching Idris2 ABI and Lithoglyph)
const LithDb = opaque {};
const LithTxn = opaque {};

const DbHandle = LithDb;
const TxnHandle = LithTxn;

// Lithoglyph types (C ABI compatible)
const LithStatus = enum(i32) {
    ok = 0,
    err_db_not_found = 1001,
    err_db_already_open = 1002,
    err_txn_not_active = 2001,
    err_txn_already_committed = 2002,
    err_invalid_argument = 9003,
    err_internal = 9001,
    err_out_of_memory = 9002,
    err_not_implemented = 9004,
};

const LithTxnMode = enum(u8) {
    read_only = 0,
    read_write = 1,
};

const BlobEncoding = enum(u8) {
    cbor = 0,
    cbor_compressed = 1,
    reserved = 255,
};

const LithBlob = extern struct {
    data: ?[*]const u8,
    len: usize,
    encoding: BlobEncoding,
    _padding: [7]u8,

    fn empty() LithBlob {
        return .{
            .data = null,
            .len = 0,
            .encoding = .cbor,
            ._padding = [_]u8{0} ** 7,
        };
    }

    fn toSlice(self: LithBlob) ?[]const u8 {
        if (self.data) |ptr| {
            return ptr[0..self.len];
        }
        return null;
    }
};

const LithResult = extern struct {
    result_blob: LithBlob,
    provenance_blob: LithBlob,
    status: LithStatus,
    _padding: [4]u8,
    err_blob: LithBlob,
};

// Extern declarations for Lithoglyph C API
extern fn lith_db_open(
    path_ptr: [*]const u8,
    path_len: usize,
    opts_ptr: ?[*]const u8,
    opts_len: usize,
    out_db: *?*LithDb,
    out_err: *LithBlob,
) LithStatus;

extern fn lith_db_close(db: ?*LithDb) LithStatus;

extern fn lith_txn_begin(
    db: ?*LithDb,
    mode: LithTxnMode,
    out_txn: *?*LithTxn,
    out_err: *LithBlob,
) LithStatus;

extern fn lith_txn_commit(txn: ?*LithTxn, out_err: *LithBlob) LithStatus;

extern fn lith_txn_abort(txn: ?*LithTxn) LithStatus;

extern fn lith_apply(
    txn: ?*LithTxn,
    op_ptr: [*]const u8,
    op_len: usize,
) LithResult;

// Version struct (matching Idris2 Version record)
const Version = extern struct {
    major: u8,
    minor: u8,
    patch: u8,
};

// Block ID (u64)
const BlockId = u64;

// Timestamp (u64 - Unix epoch microseconds)
const Timestamp = u64;

// Global allocator for the NIF
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// ============================================================================
// Exported C-compatible functions (matching Idris2 Foreign.idr)
// ============================================================================

/// Get NIF version
export fn lithoglyph_nif_version(major: *u8, minor: *u8, patch: *u8) void {
    // Lithoglyph NIF version 0.1.0
    major.* = 0;
    minor.* = 1;
    patch.* = 0;
}

/// Open database connection
/// Returns: DbHandle pointer or NULL on error
export fn lithoglyph_nif_db_open(path: [*:0]const u8) ?*DbHandle {
    const path_slice = std.mem.span(path);

    var out_db: ?*LithDb = null;
    var out_err: LithBlob = undefined;

    const status = lith_db_open(
        path_slice.ptr,
        path_slice.len,
        null, // opts_ptr
        0,    // opts_len
        &out_db,
        &out_err,
    );

    if (status != .ok) {
        // Log error if available
        if (out_err.toSlice()) |err_slice| {
            std.log.err("Failed to open database: {s}", .{err_slice});
        }
        return null;
    }

    return out_db;
}

/// Close database connection
/// Returns: 0 on success, -1 on error
export fn lithoglyph_nif_db_close(handle: *DbHandle) c_int {
    const status = lith_db_close(handle);
    return if (status == .ok) 0 else -1;
}

/// Begin transaction
/// mode: 0 = ReadOnly, 1 = ReadWrite
/// Returns: TxnHandle pointer or NULL on error
export fn lithoglyph_nif_txn_begin(handle: *DbHandle, mode_int: u32) ?*TxnHandle {
    const mode: LithTxnMode = if (mode_int == 0) .read_only else .read_write;

    var out_txn: ?*LithTxn = null;
    var out_err: LithBlob = undefined;

    const status = lith_txn_begin(
        handle,
        mode,
        &out_txn,
        &out_err,
    );

    if (status != .ok) {
        if (out_err.toSlice()) |err_slice| {
            std.log.err("Failed to begin transaction: {s}", .{err_slice});
        }
        return null;
    }

    return out_txn;
}

/// Commit transaction
/// Returns: 0 on success, -1 on error
export fn lithoglyph_nif_txn_commit(handle: *TxnHandle) c_int {
    var out_err: LithBlob = undefined;
    const status = lith_txn_commit(handle, &out_err);

    if (status != .ok) {
        if (out_err.toSlice()) |err_slice| {
            std.log.err("Failed to commit transaction: {s}", .{err_slice});
        }
        return -1;
    }

    return 0;
}

/// Abort transaction
/// Returns: 0 on success, -1 on error
export fn lithoglyph_nif_txn_abort(handle: *TxnHandle) c_int {
    const status = lith_txn_abort(handle);
    return if (status == .ok) 0 else -1;
}

/// Apply operation to transaction
/// Input: transaction handle, operation CBOR buffer, operation length
/// Output: block_id (u64), has_provenance (bool/u32), provenance_hash (32 bytes)
/// Returns: 0 on success, -1 on error
export fn lithoglyph_nif_apply(
    handle: *TxnHandle,
    op_buffer: [*]const u8,
    op_length: u32,
    block_id_out: *u64,
    has_provenance_out: *u32,
    provenance_buffer: [*]u8,
) c_int {
    // Call Lithoglyph apply
    const result = lith_apply(
        handle,
        op_buffer,
        op_length,
    );

    if (result.status != .ok) {
        if (result.err_blob.toSlice()) |err_slice| {
            std.log.err("Failed to apply operation: {s}", .{err_slice});
        }
        return -1;
    }

    // Extract block ID from result blob (CBOR-encoded)
    if (result.result_blob.toSlice()) |result_data| {
        // TODO: Parse CBOR to extract doc_id
        // For now, use a placeholder block ID
        block_id_out.* = 0x1;
        _ = result_data;
    } else {
        block_id_out.* = 0;
    }

    // Check if provenance is present
    if (result.provenance_blob.toSlice()) |prov_data| {
        has_provenance_out.* = 1;
        // Copy provenance data (first 32 bytes as hash)
        const copy_len = @min(prov_data.len, 32);
        @memcpy(provenance_buffer[0..copy_len], prov_data[0..copy_len]);
        if (copy_len < 32) {
            @memset(provenance_buffer[copy_len..32], 0);
        }
    } else {
        has_provenance_out.* = 0;
        @memset(provenance_buffer[0..32], 0);
    }

    return 0;
}

/// Get database schema (CBOR-encoded)
/// Input: database handle, output buffer, max buffer size
/// Returns: actual data length, or 0 on error
export fn lithoglyph_nif_schema(
    handle: *DbHandle,
    buffer: [*]u8,
    max_size: u32,
) u32 {
    // TODO: Implement schema retrieval from Lithoglyph
    // For now, return empty CBOR map {}
    const empty_map = [_]u8{
        0xA0, // CBOR: {} (empty map)
    };

    if (max_size < empty_map.len) {
        return 0; // Buffer too small
    }

    @memcpy(buffer[0..empty_map.len], &empty_map);

    _ = handle;

    return @intCast(empty_map.len);
}

/// Get journal entries since timestamp
/// Input: database handle, since timestamp, output buffer, max buffer size
/// Returns: actual data length, or 0 on error
export fn lithoglyph_nif_journal(
    handle: *DbHandle,
    since: u64,
    buffer: [*]u8,
    max_size: u32,
) u32 {
    // TODO: Implement journal retrieval from Lithoglyph
    // For now, return empty CBOR array []
    const empty_array = [_]u8{
        0x80, // CBOR: [] (empty array)
    };

    if (max_size < empty_array.len) {
        return 0; // Buffer too small
    }

    @memcpy(buffer[0..empty_array.len], &empty_array);

    _ = handle;
    _ = since;

    return @intCast(empty_array.len);
}

// ============================================================================
// Erlang NIF initialization (for loading as Erlang NIF)
// ============================================================================

// NIF function table
const nif_funcs = [_]c.ErlNifFunc{
    .{ .name = "version", .arity = 0, .fptr = nif_version, .flags = 0 },
    .{ .name = "db_open", .arity = 1, .fptr = nif_db_open, .flags = 0 },
    .{ .name = "db_close", .arity = 1, .fptr = nif_db_close, .flags = 0 },
    .{ .name = "txn_begin", .arity = 2, .fptr = nif_txn_begin, .flags = 0 },
    .{ .name = "txn_commit", .arity = 1, .fptr = nif_txn_commit, .flags = 0 },
    .{ .name = "txn_abort", .arity = 1, .fptr = nif_txn_abort, .flags = 0 },
    .{ .name = "apply", .arity = 2, .fptr = nif_apply, .flags = 0 },
    .{ .name = "schema", .arity = 1, .fptr = nif_schema, .flags = 0 },
    .{ .name = "journal", .arity = 2, .fptr = nif_journal, .flags = 0 },
};

// Erlang NIF wrapper functions
fn nif_version(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;

    var major: u8 = undefined;
    var minor: u8 = undefined;
    var patch: u8 = undefined;

    lithoglyph_nif_version(&major, &minor, &patch);

    return c.enif_make_tuple3(
        env,
        c.enif_make_uint(env, major),
        c.enif_make_uint(env, minor),
        c.enif_make_uint(env, patch),
    );
}

fn nif_db_open(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;

    var path_binary: c.ErlNifBinary = undefined;
    if (c.enif_inspect_binary(env, argv[0], &path_binary) == 0) {
        return c.enif_make_badarg(env);
    }

    // TODO: Convert binary to null-terminated string properly
    // For now, assume path fits in a fixed buffer
    var path_buf: [4096]u8 = undefined;
    const path_len = @min(path_binary.size, path_buf.len - 1);
    @memcpy(path_buf[0..path_len], path_binary.data[0..path_len]);
    path_buf[path_len] = 0; // Null terminate

    const handle = lithoglyph_nif_db_open(@ptrCast(&path_buf));

    if (handle) |h| {
        // TODO: Create resource term for handle
        // For now, return dummy term
        _ = h;
        return c.enif_make_atom(env, "ok");
    } else {
        return c.enif_make_tuple2(
            env,
            c.enif_make_atom(env, "error"),
            c.enif_make_atom(env, "failed_to_open"),
        );
    }
}

fn nif_db_close(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // TODO: Extract resource handle from argv[0]
    return c.enif_make_atom(env, "ok");
}

fn nif_txn_begin(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // TODO: Implement NIF wrapper
    return c.enif_make_atom(env, "ok");
}

fn nif_txn_commit(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // TODO: Implement NIF wrapper
    return c.enif_make_atom(env, "ok");
}

fn nif_txn_abort(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // TODO: Implement NIF wrapper
    return c.enif_make_atom(env, "ok");
}

fn nif_apply(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // TODO: Implement NIF wrapper
    return c.enif_make_atom(env, "ok");
}

fn nif_schema(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // TODO: Implement NIF wrapper
    return c.enif_make_atom(env, "ok");
}

fn nif_journal(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // TODO: Implement NIF wrapper
    return c.enif_make_atom(env, "ok");
}

// NIF load function
fn nif_load(env: ?*c.ErlNifEnv, priv_data: [*c]?*anyopaque, load_info: c.ERL_NIF_TERM) callconv(.c) c_int {
    _ = env;
    _ = priv_data;
    _ = load_info;
    // TODO: Initialize resource types
    return 0;
}

// NIF unload function
fn nif_unload(env: ?*c.ErlNifEnv, priv_data: ?*anyopaque) callconv(.c) void {
    _ = env;
    _ = priv_data;
    // Cleanup if needed
}

// NIF entry point
export const lithoglyph_nif_entry = c.ErlNifEntry{
    .major = c.ERL_NIF_MAJOR_VERSION,
    .minor = c.ERL_NIF_MINOR_VERSION,
    .name = "lithoglyph_nif",
    .num_of_funcs = nif_funcs.len,
    .funcs = @ptrCast(@constCast(&nif_funcs)),
    .load = nif_load,
    .reload = null,
    .upgrade = null,
    .unload = nif_unload,
    .vm_variant = "beam.vanilla",
    .options = 0,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(c.ErlNifResourceTypeInit),
};

// Tests
test "version" {
    var major: u8 = undefined;
    var minor: u8 = undefined;
    var patch: u8 = undefined;

    lithoglyph_nif_version(&major, &minor, &patch);

    try std.testing.expectEqual(@as(u8, 0), major);
    try std.testing.expectEqual(@as(u8, 1), minor);
    try std.testing.expectEqual(@as(u8, 0), patch);
}

test "db lifecycle" {
    const handle = lithoglyph_nif_db_open("/tmp/test.db");
    try std.testing.expect(handle != null);

    const result = lithoglyph_nif_db_close(handle.?);
    try std.testing.expectEqual(@as(c_int, 0), result);
}
