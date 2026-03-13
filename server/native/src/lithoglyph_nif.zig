// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith NIF - Erlang/BEAM Native Implemented Functions
//
// Bridges Lith's Zig C ABI to the Erlang runtime via NIFs.
// All data is passed as CBOR-encoded binaries.

const std = @import("std");
const erl_nif = @cImport({
    @cInclude("erl_nif.h");
});

// Lith C ABI imports (linked at build time)
extern fn fdb_version() u32;
extern fn fdb_db_open(
    path_ptr: [*]const u8,
    path_len: usize,
    opts_ptr: ?[*]const u8,
    opts_len: usize,
    out_db: *?*anyopaque,
    out_err: *FdbBlob,
) FdbStatus;
extern fn fdb_db_close(db: ?*anyopaque) FdbStatus;
extern fn fdb_txn_begin(
    db: ?*anyopaque,
    mode: FdbTxnMode,
    out_txn: *?*anyopaque,
    out_err: *FdbBlob,
) FdbStatus;
extern fn fdb_txn_commit(txn: ?*anyopaque, out_err: *FdbBlob) FdbStatus;
extern fn fdb_txn_abort(txn: ?*anyopaque) FdbStatus;
extern fn fdb_apply(
    txn: ?*anyopaque,
    op_ptr: [*]const u8,
    op_len: usize,
) FdbResult;
extern fn fdb_render_journal(
    db: ?*anyopaque,
    since: u64,
    opts: FdbRenderOpts,
    out_text: *FdbBlob,
    out_err: *FdbBlob,
) FdbStatus;
extern fn fdb_introspect_schema(
    db: ?*anyopaque,
    out_schema: *FdbBlob,
    out_err: *FdbBlob,
) FdbStatus;
extern fn fdb_blob_free(blob: *FdbBlob) void;

// Lith types (must match types.zig)
const FdbBlob = extern struct {
    data: ?[*]const u8,
    len: usize,
    encoding: u8,
    _padding: [7]u8 = [_]u8{0} ** 7,
};

const FdbStatus = enum(i32) {
    ok = 0,
    err_db_not_found = 1001,
    err_db_already_open = 1002,
    err_db_corrupted = 1003,
    err_txn_not_active = 2001,
    err_txn_already_committed = 2002,
    err_doc_not_found = 3001,
    err_collection_not_found = 4001,
    err_schema_violation = 5001,
    err_internal = 9001,
    err_out_of_memory = 9002,
    err_invalid_argument = 9003,
    err_not_implemented = 9004,
};

const FdbTxnMode = enum(u8) {
    read_only = 0,
    read_write = 1,
};

const FdbRenderOpts = extern struct {
    include_provenance: bool = true,
    include_timestamps: bool = true,
    pretty_print: bool = false,
    max_depth: u32 = 10,
    _padding: [3]u8 = [_]u8{0} ** 3,
};

const FdbResult = extern struct {
    result_blob: FdbBlob,
    provenance_blob: FdbBlob,
    status: FdbStatus,
    _padding: [4]u8 = [_]u8{0} ** 4,
    err_blob: FdbBlob,
};

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

fn db_resource_dtor(_: *erl_nif.ErlNifEnv, obj: *anyopaque) callconv(.C) void {
    const res: *DbResource = @ptrCast(@alignCast(obj));
    if (res.handle) |h| {
        _ = fdb_db_close(h);
        res.handle = null;
    }
}

fn txn_resource_dtor(_: *erl_nif.ErlNifEnv, obj: *anyopaque) callconv(.C) void {
    const res: *TxnResource = @ptrCast(@alignCast(obj));
    if (res.handle) |h| {
        _ = fdb_txn_abort(h);
        res.handle = null;
    }
}

// ============================================================
// NIF Helper Functions
// ============================================================

fn make_atom(env: *erl_nif.ErlNifEnv, name: []const u8) erl_nif.ERL_NIF_TERM {
    var atom: erl_nif.ERL_NIF_TERM = undefined;
    if (erl_nif.enif_make_existing_atom_len(env, name.ptr, name.len, &atom, erl_nif.ERL_NIF_LATIN1) != 0) {
        return atom;
    }
    return erl_nif.enif_make_atom_len(env, name.ptr, name.len);
}

fn make_ok(env: *erl_nif.ErlNifEnv, term: erl_nif.ERL_NIF_TERM) erl_nif.ERL_NIF_TERM {
    return erl_nif.enif_make_tuple2(env, make_atom(env, "ok"), term);
}

fn make_error(env: *erl_nif.ErlNifEnv, reason: []const u8) erl_nif.ERL_NIF_TERM {
    return erl_nif.enif_make_tuple2(env, make_atom(env, "error"), make_atom(env, reason));
}

fn make_error_with_message(env: *erl_nif.ErlNifEnv, reason: []const u8, msg: []const u8) erl_nif.ERL_NIF_TERM {
    var bin: erl_nif.ErlNifBinary = undefined;
    if (erl_nif.enif_alloc_binary(msg.len, &bin) == 0) {
        return make_error(env, reason);
    }
    @memcpy(bin.data[0..msg.len], msg);
    const msg_term = erl_nif.enif_make_binary(env, &bin);
    return erl_nif.enif_make_tuple3(env, make_atom(env, "error"), make_atom(env, reason), msg_term);
}

fn blob_to_binary(env: *erl_nif.ErlNifEnv, blob: FdbBlob) ?erl_nif.ERL_NIF_TERM {
    if (blob.data) |data| {
        var bin: erl_nif.ErlNifBinary = undefined;
        if (erl_nif.enif_alloc_binary(blob.len, &bin) == 0) {
            return null;
        }
        @memcpy(bin.data[0..blob.len], data[0..blob.len]);
        return erl_nif.enif_make_binary(env, &bin);
    }
    return erl_nif.enif_make_binary(env, &erl_nif.ErlNifBinary{ .size = 0, .data = null });
}

fn status_to_atom(status: FdbStatus) []const u8 {
    return switch (status) {
        .ok => "ok",
        .err_db_not_found => "db_not_found",
        .err_db_already_open => "db_already_open",
        .err_db_corrupted => "db_corrupted",
        .err_txn_not_active => "txn_not_active",
        .err_txn_already_committed => "txn_already_committed",
        .err_doc_not_found => "doc_not_found",
        .err_collection_not_found => "collection_not_found",
        .err_schema_violation => "schema_violation",
        .err_internal => "internal_error",
        .err_out_of_memory => "out_of_memory",
        .err_invalid_argument => "invalid_argument",
        .err_not_implemented => "not_implemented",
    };
}

// ============================================================
// NIF Functions
// ============================================================

/// Get Lith version
fn nif_version(env: *erl_nif.ErlNifEnv, _: c_int, _: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
    const version = fdb_version();
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
fn nif_db_open(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
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

    var err_blob: FdbBlob = undefined;
    const status = fdb_db_open(
        path_bin.data,
        path_bin.size,
        null,
        0,
        &res.handle,
        &err_blob,
    );

    if (status != .ok) {
        erl_nif.enif_release_resource(res);
        if (err_blob.data) |_| {
            const msg = err_blob.data.?[0..err_blob.len];
            var blob_copy = err_blob;
            defer fdb_blob_free(&blob_copy);
            return make_error_with_message(env, status_to_atom(status), msg);
        }
        return make_error(env, status_to_atom(status));
    }

    const term = erl_nif.enif_make_resource(env, res);
    erl_nif.enif_release_resource(res);
    return make_ok(env, term);
}

/// Close a Lith database
fn nif_db_close(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
    if (argc != 1) return make_error(env, "badarg");

    var res: *DbResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], db_resource_type, @ptrCast(&res)) == 0) {
        return make_error(env, "badarg");
    }

    if (res.handle) |h| {
        const status = fdb_db_close(h);
        res.handle = null;
        if (status != .ok) {
            return make_error(env, status_to_atom(status));
        }
    }

    return make_atom(env, "ok");
}

/// Begin a transaction
fn nif_txn_begin(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
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
    const mode: FdbTxnMode = if (std.mem.eql(u8, mode_str, "read_only"))
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

    var err_blob: FdbBlob = undefined;
    const status = fdb_txn_begin(db_res.handle, mode, &txn_res.handle, &err_blob);

    if (status != .ok) {
        erl_nif.enif_release_resource(txn_res);
        return make_error(env, status_to_atom(status));
    }

    const term = erl_nif.enif_make_resource(env, txn_res);
    erl_nif.enif_release_resource(txn_res);
    return make_ok(env, term);
}

/// Commit a transaction
fn nif_txn_commit(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
    if (argc != 1) return make_error(env, "badarg");

    var txn_res: *TxnResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], txn_resource_type, @ptrCast(&txn_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (txn_res.handle == null) {
        return make_error(env, "txn_closed");
    }

    var err_blob: FdbBlob = undefined;
    const status = fdb_txn_commit(txn_res.handle, &err_blob);
    txn_res.handle = null;

    if (status != .ok) {
        return make_error(env, status_to_atom(status));
    }

    return make_atom(env, "ok");
}

/// Abort a transaction
fn nif_txn_abort(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
    if (argc != 1) return make_error(env, "badarg");

    var txn_res: *TxnResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], txn_resource_type, @ptrCast(&txn_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (txn_res.handle) |h| {
        _ = fdb_txn_abort(h);
        txn_res.handle = null;
    }

    return make_atom(env, "ok");
}

/// Apply an operation (CBOR-encoded)
fn nif_apply(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
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

    const result = fdb_apply(txn_res.handle, op_bin.data, op_bin.size);

    if (result.status != .ok) {
        if (result.err_blob.data) |_| {
            if (blob_to_binary(env, result.err_blob)) |err_term| {
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
    const result_term = blob_to_binary(env, result.result_blob) orelse
        return make_error(env, "encoding_failed");

    if (result.provenance_blob.data != null) {
        const prov_term = blob_to_binary(env, result.provenance_blob) orelse
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
fn nif_schema(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
    if (argc != 1) return make_error(env, "badarg");

    var db_res: *DbResource = undefined;
    if (erl_nif.enif_get_resource(env, argv[0], db_resource_type, @ptrCast(&db_res)) == 0) {
        return make_error(env, "badarg");
    }

    if (db_res.handle == null) {
        return make_error(env, "db_closed");
    }

    var schema_blob: FdbBlob = undefined;
    var err_blob: FdbBlob = undefined;
    const status = fdb_introspect_schema(db_res.handle, &schema_blob, &err_blob);

    if (status != .ok) {
        return make_error(env, status_to_atom(status));
    }

    const schema_term = blob_to_binary(env, schema_blob) orelse
        return make_error(env, "encoding_failed");

    return make_ok(env, schema_term);
}

/// Get journal entries since a sequence number
fn nif_journal(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.C) erl_nif.ERL_NIF_TERM {
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

    var journal_blob: FdbBlob = undefined;
    var err_blob: FdbBlob = undefined;
    const opts = FdbRenderOpts{};
    const status = fdb_render_journal(db_res.handle, since, opts, &journal_blob, &err_blob);

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

const nif_funcs = [_]erl_nif.ErlNifFunc{
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

fn load(env: *erl_nif.ErlNifEnv, _: *?*anyopaque, _: erl_nif.ERL_NIF_TERM) callconv(.C) c_int {
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
    .name = "Elixir.Lith.NIF",
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
