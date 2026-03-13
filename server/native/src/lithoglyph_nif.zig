// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Lithoglyph NIF - Erlang/BEAM Native Implemented Functions
//
// Bridges Lith's Zig storage engine to the Erlang runtime via NIFs.
// Uses core_bridge module import (not extern linking) for type safety.
// All data is passed as CBOR-encoded binaries.

const std = @import("std");
const core = @import("core_bridge");
const erl_nif = @cImport({
    @cInclude("erl_nif.h");
});

// Re-export core types for clarity
const LgBlob = core.LgBlob;
const LgStatus = core.LgStatus;
const LgResult = core.LgResult;
const LgTxnMode = core.LgTxnMode;
const LgRenderOpts = core.LgRenderOpts;

// NIF function signature type (matches erl_nif.h expectations)
const NifEnv = ?*erl_nif.ErlNifEnv;
const NifTerm = erl_nif.ERL_NIF_TERM;
const NifArgs = [*c]const NifTerm;

// ============================================================
// Resource Types for BEAM
// ============================================================

var db_resource_type: ?*erl_nif.ErlNifResourceType = null;
var txn_resource_type: ?*erl_nif.ErlNifResourceType = null;

const DbResource = struct {
    handle: ?*anyopaque,
};

const TxnResource = struct {
    handle: ?*anyopaque,
    db: *DbResource,
};

fn db_resource_dtor(_: NifEnv, obj: ?*anyopaque) callconv(.c) void {
    const res: *DbResource = @ptrCast(@alignCast(obj orelse return));
    if (res.handle) |h| {
        // SAFETY: handle was created by lith_db_open which returns *LgDb as *anyopaque
        _ = core.lith_db_close(@ptrCast(h));
        res.handle = null;
    }
}

fn txn_resource_dtor(_: NifEnv, obj: ?*anyopaque) callconv(.c) void {
    const res: *TxnResource = @ptrCast(@alignCast(obj orelse return));
    if (res.handle) |h| {
        // SAFETY: handle was created by lith_txn_begin which returns *LgTxn as *anyopaque
        _ = core.lith_txn_abort(@ptrCast(h));
        res.handle = null;
    }
}

// ============================================================
// NIF Helper Functions
// ============================================================

fn make_atom(env: NifEnv, name: []const u8) NifTerm {
    var atom: erl_nif.ERL_NIF_TERM = undefined;
    if (erl_nif.enif_make_existing_atom_len(env, name.ptr, name.len, &atom, erl_nif.ERL_NIF_LATIN1) != 0) {
        return atom;
    }
    return erl_nif.enif_make_atom_len(env, name.ptr, name.len);
}

fn make_ok(env: NifEnv, term: NifTerm) NifTerm {
    return erl_nif.enif_make_tuple2(env, make_atom(env, "ok"), term);
}

fn make_error(env: NifEnv, reason: []const u8) NifTerm {
    return erl_nif.enif_make_tuple2(env, make_atom(env, "error"), make_atom(env, reason));
}

fn make_error_with_message(env: NifEnv, reason: []const u8, msg: []const u8) NifTerm {
    var bin: erl_nif.ErlNifBinary = undefined;
    if (erl_nif.enif_alloc_binary(msg.len, &bin) == 0) {
        return make_error(env, reason);
    }
    @memcpy(bin.data[0..msg.len], msg);
    const msg_term = erl_nif.enif_make_binary(env, &bin);
    return erl_nif.enif_make_tuple3(env, make_atom(env, "error"), make_atom(env, reason), msg_term);
}

fn blob_to_binary(env: NifEnv, blob: LgBlob) ?erl_nif.ERL_NIF_TERM {
    if (blob.ptr) |data| {
        var bin: erl_nif.ErlNifBinary = undefined;
        if (erl_nif.enif_alloc_binary(blob.len, &bin) == 0) {
            return null;
        }
        @memcpy(bin.data[0..blob.len], data[0..blob.len]);
        return erl_nif.enif_make_binary(env, &bin);
    }
    var empty_bin = erl_nif.ErlNifBinary{ .size = 0, .data = null };
    return erl_nif.enif_make_binary(env, &empty_bin);
}

fn status_to_atom(status: LgStatus) []const u8 {
    return switch (status) {
        .ok => "ok",
        .err_internal => "internal_error",
        .err_not_found => "not_found",
        .err_invalid_argument => "invalid_argument",
        .err_out_of_memory => "out_of_memory",
        .err_not_implemented => "not_implemented",
        .err_txn_not_active => "txn_not_active",
        .err_txn_already_committed => "txn_already_committed",
    };
}

// ============================================================
// NIF Functions
// ============================================================

/// Get Lith version
fn nif_version(env: NifEnv, _: c_int, _: NifArgs) callconv(.c) NifTerm {
    const version = core.lith_version();
    const major = version / 10000;
    const minor = (version % 10000) / 100;
    const patch = version % 100;

    return erl_nif.enif_make_tuple3(
        env,
        erl_nif.enif_make_uint(env, major),
        erl_nif.enif_make_uint(env, minor),
        erl_nif.enif_make_uint(env, patch),
    );
}

/// Open a Lith database
fn nif_db_open(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 1) return make_error(env, "badarg");

    var path_bin: erl_nif.ErlNifBinary = undefined;
    if (erl_nif.enif_inspect_binary(env, argv[0], &path_bin) == 0) {
        return make_error(env, "badarg");
    }

    // Allocate resource
    const res: *DbResource = @ptrCast(@alignCast(
        erl_nif.enif_alloc_resource(db_resource_type, @sizeOf(DbResource)) orelse
            return make_error(env, "alloc_failed"),
    ));

    var err_blob: LgBlob = LgBlob.empty();
    const status = core.lith_db_open(
        path_bin.data,
        path_bin.size,
        null,
        0,
        @ptrCast(&res.handle),
        &err_blob,
    );

    if (status != .ok) {
        erl_nif.enif_release_resource(res);
        if (err_blob.ptr) |_| {
            const msg = err_blob.ptr.?[0..err_blob.len];
            var blob_copy = err_blob;
            defer core.lith_blob_free(&blob_copy);
            return make_error_with_message(env, status_to_atom(status), msg);
        }
        return make_error(env, status_to_atom(status));
    }

    const term = erl_nif.enif_make_resource(env, res);
    erl_nif.enif_release_resource(res);
    return make_ok(env, term);
}

/// Close a Lith database
fn nif_db_close(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 1) return make_error(env, "badarg");

    var res: *DbResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], db_resource_type, @ptrCast(&res)) == 0) {
        return make_error(env, "badarg");
    }

    if (res.handle) |h| {
        // SAFETY: handle was created by lith_db_open
        const status = core.lith_db_close(@ptrCast(h));
        res.handle = null;
        if (status != .ok) {
            return make_error(env, status_to_atom(status));
        }
    }

    return make_atom(env, "ok");
}

/// Begin a transaction
fn nif_txn_begin(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 2) return make_error(env, "badarg");

    var db_res: *DbResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], db_resource_type, @ptrCast(&db_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (db_res.handle == null) {
        return make_error(env, "db_closed");
    }

    // Parse mode atom
    var mode_buf: [32]u8 = undefined;
    const mode_len = erl_nif.enif_get_atom(env, argv[1], &mode_buf, mode_buf.len, erl_nif.ERL_NIF_LATIN1);
    if (mode_len == 0) return make_error(env, "badarg");

    const mode_str = mode_buf[0 .. @as(usize, @intCast(mode_len)) - 1];
    const mode: LgTxnMode = if (std.mem.eql(u8, mode_str, "read_only"))
        .read_only
    else if (std.mem.eql(u8, mode_str, "read_write"))
        .read_write
    else
        return make_error(env, "invalid_mode");

    // Allocate transaction resource
    const txn_res: *TxnResource = @ptrCast(@alignCast(
        erl_nif.enif_alloc_resource(txn_resource_type, @sizeOf(TxnResource)) orelse
            return make_error(env, "alloc_failed"),
    ));

    txn_res.db = db_res;

    var err_blob: LgBlob = LgBlob.empty();
    // SAFETY: db_res.handle was created by lith_db_open; txn_res.handle receives *LgTxn
    const status = core.lith_txn_begin(@ptrCast(db_res.handle), mode, @ptrCast(&txn_res.handle), &err_blob);

    if (status != .ok) {
        erl_nif.enif_release_resource(txn_res);
        return make_error(env, status_to_atom(status));
    }

    const term = erl_nif.enif_make_resource(env, txn_res);
    erl_nif.enif_release_resource(txn_res);
    return make_ok(env, term);
}

/// Commit a transaction
fn nif_txn_commit(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 1) return make_error(env, "badarg");

    var txn_res: *TxnResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], txn_resource_type, @ptrCast(&txn_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (txn_res.handle == null) {
        return make_error(env, "txn_closed");
    }

    var err_blob: LgBlob = LgBlob.empty();
    // SAFETY: txn_res.handle was created by lith_txn_begin
    const status = core.lith_txn_commit(@ptrCast(txn_res.handle), &err_blob);
    txn_res.handle = null;

    if (status != .ok) {
        return make_error(env, status_to_atom(status));
    }

    return make_atom(env, "ok");
}

/// Abort a transaction
fn nif_txn_abort(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 1) return make_error(env, "badarg");

    var txn_res: *TxnResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], txn_resource_type, @ptrCast(&txn_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (txn_res.handle) |h| {
        // SAFETY: handle was created by lith_txn_begin
        _ = core.lith_txn_abort(@ptrCast(h));
        txn_res.handle = null;
    }

    return make_atom(env, "ok");
}

/// Apply an operation (CBOR-encoded)
fn nif_apply(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 2) return make_error(env, "badarg");

    var txn_res: *TxnResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], txn_resource_type, @ptrCast(&txn_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (txn_res.handle == null) {
        return make_error(env, "txn_closed");
    }

    var op_bin: erl_nif.ErlNifBinary = undefined;
    if (erl_nif.enif_inspect_binary(env, argv[1], &op_bin) == 0) {
        return make_error(env, "badarg");
    }

    // SAFETY: txn_res.handle was created by lith_txn_begin
    const result = core.lith_apply(@ptrCast(txn_res.handle), op_bin.data, op_bin.size);

    if (result.status != .ok) {
        if (result.error_blob.ptr) |_| {
            if (blob_to_binary(env, result.error_blob)) |err_term| {
                return erl_nif.enif_make_tuple3(
                    env,
                    make_atom(env, "error"),
                    make_atom(env, status_to_atom(result.status)),
                    err_term,
                );
            }
        }
        return make_error(env, status_to_atom(result.status));
    }

    // Build success response with result and provenance
    const result_term = blob_to_binary(env, result.data) orelse
        return make_error(env, "encoding_failed");

    if (result.provenance.ptr != null) {
        const prov_term = blob_to_binary(env, result.provenance) orelse
            return make_ok(env, result_term);

        return erl_nif.enif_make_tuple3(
            env,
            make_atom(env, "ok"),
            result_term,
            prov_term,
        );
    }

    return make_ok(env, result_term);
}

/// Get schema information
fn nif_schema(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 1) return make_error(env, "badarg");

    var db_res: *DbResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], db_resource_type, @ptrCast(&db_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (db_res.handle == null) {
        return make_error(env, "db_closed");
    }

    var schema_blob: LgBlob = LgBlob.empty();
    var err_blob: LgBlob = LgBlob.empty();
    // SAFETY: db_res.handle was created by lith_db_open
    const status = core.lith_introspect_schema(@ptrCast(db_res.handle), &schema_blob, &err_blob);

    if (status != .ok) {
        return make_error(env, status_to_atom(status));
    }

    const schema_term = blob_to_binary(env, schema_blob) orelse
        return make_error(env, "encoding_failed");

    return make_ok(env, schema_term);
}

/// Get journal entries since a sequence number
fn nif_journal(env: NifEnv, argc: c_int, argv: NifArgs) callconv(.c) NifTerm {
    if (argc != 2) return make_error(env, "badarg");

    var db_res: *DbResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], db_resource_type, @ptrCast(&db_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (db_res.handle == null) {
        return make_error(env, "db_closed");
    }

    var since: c_ulong = undefined;
    if (erl_nif.enif_get_ulong(env, argv[1], &since) == 0) {
        return make_error(env, "badarg");
    }

    var journal_blob: LgBlob = LgBlob.empty();
    var err_blob: LgBlob = LgBlob.empty();
    const opts = LgRenderOpts{ .format = 0, .include_metadata = true };
    // SAFETY: db_res.handle was created by lith_db_open
    const status = core.lith_render_journal(@ptrCast(db_res.handle), since, opts, &journal_blob, &err_blob);

    if (status != .ok) {
        return make_error(env, status_to_atom(status));
    }

    const journal_term = blob_to_binary(env, journal_blob) orelse
        return make_error(env, "encoding_failed");

    return make_ok(env, journal_term);
}

// ============================================================
// NIF Table and Initialization
// ============================================================

var nif_funcs = [_]erl_nif.ErlNifFunc{
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

fn load(env: NifEnv, _: [*c]?*anyopaque, _: erl_nif.ERL_NIF_TERM) callconv(.c) c_int {
    db_resource_type = erl_nif.enif_open_resource_type(
        env,
        null,
        "lith_db",
        db_resource_dtor,
        erl_nif.ERL_NIF_RT_CREATE,
        null,
    );

    txn_resource_type = erl_nif.enif_open_resource_type(
        env,
        null,
        "lith_txn",
        txn_resource_dtor,
        erl_nif.ERL_NIF_RT_CREATE,
        null,
    );

    if (db_resource_type == null or txn_resource_type == null) {
        return -1;
    }

    return 0;
}

pub export const lith_nif_init = erl_nif.ErlNifEntry{
    .major = erl_nif.ERL_NIF_MAJOR_VERSION,
    .minor = erl_nif.ERL_NIF_MINOR_VERSION,
    .name = "lith_nif",
    .num_of_funcs = nif_funcs.len,
    .funcs = &nif_funcs,
    .load = load,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = "beam.vanilla",
    .options = 0,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(erl_nif.ErlNifResourceTypeInit),
    .min_erts = "erts-13.0",
};
