// SPDX-License-Identifier: PMPL-1.0-or-later
const std = @import("std");
const c = @cImport({
    @cInclude("erl_nif.h");
});
const semantic = @import("semantic_ffi.zig");

const c_allocator = std.heap.c_allocator;

const HostCallError = error{
    NotFound,
    InvalidArgument,
    InternalError,
    OutOfMemory,
};

const LookupApiResponse = struct {
    knot_name: []const u8 = "",
    descriptor_version: []const u8 = "",
    descriptor_hash: []const u8 = "",
    quandle_key: []const u8 = "",
    crossing_number: i32 = 0,
    writhe: i32 = 0,
    determinant: ?i32 = null,
    signature: ?i32 = null,
    quandle_generator_count: ?i32 = null,
    quandle_relation_count: ?i32 = null,
    colouring_count_3: ?i32 = null,
    colouring_count_5: ?i32 = null,
};

const EquivalenceApiResponse = struct {
    name: []const u8 = "",
    descriptor_hash: []const u8 = "",
    quandle_key: []const u8 = "",
    strong_candidates: []const []const u8 = &.{},
    weak_candidates: []const []const u8 = &.{},
    combined_candidates: []const []const u8 = &.{},
};

var empty_name_ptrs = [_][*]const u8{"".ptr};
var empty_name_lens = [_]usize{0};

fn make_atom(env: ?*c.ErlNifEnv, name: [*:0]const u8) c.ERL_NIF_TERM {
    return c.enif_make_atom(env, name);
}

fn make_binary(env: ?*c.ErlNifEnv, bytes: []const u8) c.ERL_NIF_TERM {
    var term: c.ERL_NIF_TERM = 0;
    const ptr = c.enif_make_new_binary(env, bytes.len, &term);
    if (bytes.len > 0 and ptr != null) {
        @memcpy(@as([*]u8, @ptrCast(ptr))[0..bytes.len], bytes);
    }
    return term;
}

fn make_error(env: ?*c.ErlNifEnv, reason: [*:0]const u8) c.ERL_NIF_TERM {
    var terms = [_]c.ERL_NIF_TERM{
        make_atom(env, "error"),
        make_atom(env, reason),
    };
    return c.enif_make_tuple_from_array(env, &terms, terms.len);
}

fn make_ok(env: ?*c.ErlNifEnv, payload: c.ERL_NIF_TERM) c.ERL_NIF_TERM {
    var terms = [_]c.ERL_NIF_TERM{
        make_atom(env, "ok"),
        payload,
    };
    return c.enif_make_tuple_from_array(env, &terms, terms.len);
}

fn put_map(env: ?*c.ErlNifEnv, map: c.ERL_NIF_TERM, key: [*:0]const u8, value: c.ERL_NIF_TERM) c.ERL_NIF_TERM {
    var next_map: c.ERL_NIF_TERM = map;
    _ = c.enif_make_map_put(env, map, make_atom(env, key), value, &next_map);
    return next_map;
}

fn inspect_input_binary(env: ?*c.ErlNifEnv, term: c.ERL_NIF_TERM) ?[]const u8 {
    var bin: c.ErlNifBinary = undefined;
    if (c.enif_inspect_binary(env, term, &bin) == 0) return null;
    return @as([*]const u8, @ptrCast(bin.data))[0..bin.size];
}

fn is_safe_name(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        if (std.ascii.isAlphanumeric(ch)) continue;
        if (ch == '_' or ch == '-' or ch == '.') continue;
        return false;
    }
    return true;
}

fn status_from_host_error(err: HostCallError) semantic.SemanticStatus {
    return switch (err) {
        error.NotFound => .not_found,
        error.InvalidArgument => .invalid_argument,
        else => .internal_error,
    };
}

fn nif_reason_from_semantic_error(err: semantic.SemanticError) [*:0]const u8 {
    return switch (err) {
        error.NotFound => "not_found",
        error.InvalidArgument => "invalid_argument",
        error.InternalError => "internal_error",
    };
}

fn is_stub_mode() bool {
    const mode = std.process.getEnvVarOwned(c_allocator, "QDB_NIF_MODE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return true,
        else => return true,
    };
    defer c_allocator.free(mode);
    return !std.ascii.eqlIgnoreCase(mode, "live");
}

fn get_base_url() HostCallError![]u8 {
    return std.process.getEnvVarOwned(c_allocator, "QDB_API_BASE_URL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => c_allocator.dupe(u8, "http://127.0.0.1:8080") catch error.OutOfMemory,
        error.OutOfMemory => error.OutOfMemory,
        else => error.InternalError,
    };
}

fn build_endpoint_url(path_prefix: []const u8, name: []const u8) HostCallError![]u8 {
    if (!is_safe_name(name)) return error.InvalidArgument;

    const base_url = try get_base_url();
    defer c_allocator.free(base_url);

    const trimmed = std.mem.trimRight(u8, base_url, "/");
    return std.fmt.allocPrint(c_allocator, "{s}{s}{s}", .{ trimmed, path_prefix, name }) catch error.OutOfMemory;
}

fn fetch_json(url: []const u8, body: *std.Io.Writer.Allocating) HostCallError!void {
    var client: std.http.Client = .{ .allocator = c_allocator };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &body.writer,
    }) catch return error.InternalError;

    const status_code: u16 = @intFromEnum(result.status);
    if (status_code == 404) return error.NotFound;
    if (status_code >= 400 and status_code < 500) return error.InvalidArgument;
    if (status_code != 200) return error.InternalError;
}

fn copy_string(value: []const u8, out_ptr: *[*]const u8, out_len: *usize) HostCallError!void {
    if (value.len == 0) {
        out_ptr.* = "".ptr;
        out_len.* = 0;
        return;
    }
    const mem = c_allocator.alloc(u8, value.len) catch return error.OutOfMemory;
    @memcpy(mem, value);
    out_ptr.* = mem.ptr;
    out_len.* = mem.len;
}

fn free_string(ptr: [*]const u8, len: usize) void {
    if (len == 0) return;
    c_allocator.free(@as([*]u8, @ptrCast(@constCast(ptr)))[0..len]);
}

fn copy_string_list(values: []const []const u8, out_ptrs: *[*][*]const u8, out_lens: *[*]const usize, out_count: *usize) HostCallError!void {
    if (values.len == 0) {
        out_ptrs.* = @ptrCast(&empty_name_ptrs);
        out_lens.* = @ptrCast(&empty_name_lens);
        out_count.* = 0;
        return;
    }

    const ptrs = c_allocator.alloc([*]const u8, values.len) catch return error.OutOfMemory;
    errdefer c_allocator.free(ptrs);

    const lens = c_allocator.alloc(usize, values.len) catch return error.OutOfMemory;
    errdefer c_allocator.free(lens);

    var i: usize = 0;
    errdefer {
        var j: usize = 0;
        while (j < i) : (j += 1) {
            free_string(ptrs[j], lens[j]);
        }
    }

    while (i < values.len) : (i += 1) {
        const v = values[i];
        if (v.len == 0) {
            ptrs[i] = "".ptr;
            lens[i] = 0;
        } else {
            const mem = c_allocator.alloc(u8, v.len) catch return error.OutOfMemory;
            @memcpy(mem, v);
            ptrs[i] = mem.ptr;
            lens[i] = mem.len;
        }
    }

    out_ptrs.* = ptrs.ptr;
    out_lens.* = lens.ptr;
    out_count.* = values.len;
}

fn populate_descriptor_from_lookup_response(data: LookupApiResponse, out: *semantic.SemanticDescriptorView) HostCallError!void {
    out.* = std.mem.zeroes(semantic.SemanticDescriptorView);
    errdefer qdb_semantic_release_descriptor(out);

    try copy_string(data.knot_name, &out.knot_name_ptr, &out.knot_name_len);
    try copy_string(data.descriptor_version, &out.descriptor_version_ptr, &out.descriptor_version_len);
    try copy_string(data.descriptor_hash, &out.descriptor_hash_ptr, &out.descriptor_hash_len);
    try copy_string(data.quandle_key, &out.quandle_key_ptr, &out.quandle_key_len);

    out.crossing_number = data.crossing_number;
    out.writhe = data.writhe;

    if (data.determinant) |v| {
        out.determinant = v;
        out.has_determinant = true;
    }
    if (data.signature) |v| {
        out.signature = v;
        out.has_signature = true;
    }
    if (data.quandle_generator_count) |v| {
        out.quandle_generator_count = v;
        out.has_quandle_generator_count = true;
    }
    if (data.quandle_relation_count) |v| {
        out.quandle_relation_count = v;
        out.has_quandle_relation_count = true;
    }
    if (data.colouring_count_3) |v| {
        out.colouring_count_3 = v;
        out.has_colouring_count_3 = true;
    }
    if (data.colouring_count_5) |v| {
        out.colouring_count_5 = v;
        out.has_colouring_count_5 = true;
    }
}

fn populate_equivalence_from_response(data: EquivalenceApiResponse, out: *semantic.SemanticEquivalenceView) HostCallError!void {
    out.* = std.mem.zeroes(semantic.SemanticEquivalenceView);
    errdefer qdb_semantic_release_equivalence(out);

    try copy_string(data.name, &out.name_ptr, &out.name_len);
    try copy_string(data.descriptor_hash, &out.descriptor_hash_ptr, &out.descriptor_hash_len);
    try copy_string(data.quandle_key, &out.quandle_key_ptr, &out.quandle_key_len);
    try copy_string_list(data.strong_candidates, &out.strong_names_ptr, &out.strong_name_lengths_ptr, &out.strong_count);
    try copy_string_list(data.weak_candidates, &out.weak_names_ptr, &out.weak_name_lengths_ptr, &out.weak_count);
    try copy_string_list(data.combined_candidates, &out.combined_names_ptr, &out.combined_name_lengths_ptr, &out.combined_count);
}

fn populate_descriptor_stub(name: []const u8, out: *semantic.SemanticDescriptorView) HostCallError!void {
    const data = LookupApiResponse{
        .knot_name = name,
        .descriptor_version = "stub-v1",
        .descriptor_hash = "",
        .quandle_key = "",
        .crossing_number = 0,
        .writhe = 0,
    };
    try populate_descriptor_from_lookup_response(data, out);
}

fn populate_equivalence_stub(name: []const u8, out: *semantic.SemanticEquivalenceView) HostCallError!void {
    const one = [_][]const u8{name};
    const data = EquivalenceApiResponse{
        .name = name,
        .descriptor_hash = "",
        .quandle_key = "",
        .strong_candidates = one[0..],
        .weak_candidates = &.{},
        .combined_candidates = one[0..],
    };
    try populate_equivalence_from_response(data, out);
}

pub export fn qdb_semantic_lookup(name_ptr: [*]const u8, name_len: usize, out_descriptor: *semantic.SemanticDescriptorView) callconv(.c) semantic.SemanticStatus {
    out_descriptor.* = std.mem.zeroes(semantic.SemanticDescriptorView);

    if (name_len == 0) return .invalid_argument;
    const name = name_ptr[0..name_len];
    if (!is_safe_name(name)) return .invalid_argument;

    if (is_stub_mode()) {
        populate_descriptor_stub(name, out_descriptor) catch return .internal_error;
        return .ok;
    }

    var body: std.Io.Writer.Allocating = .init(c_allocator);
    defer body.deinit();

    const url = build_endpoint_url("/api/semantic/", name) catch |err| return status_from_host_error(err);
    defer c_allocator.free(url);

    fetch_json(url, &body) catch |err| return status_from_host_error(err);

    var parsed = std.json.parseFromSlice(LookupApiResponse, c_allocator, body.written(), .{
        .ignore_unknown_fields = true,
    }) catch return .internal_error;
    defer parsed.deinit();

    populate_descriptor_from_lookup_response(parsed.value, out_descriptor) catch return .internal_error;
    return .ok;
}

pub export fn qdb_semantic_equivalents(name_ptr: [*]const u8, name_len: usize, out_equivalence: *semantic.SemanticEquivalenceView) callconv(.c) semantic.SemanticStatus {
    out_equivalence.* = std.mem.zeroes(semantic.SemanticEquivalenceView);

    if (name_len == 0) return .invalid_argument;
    const name = name_ptr[0..name_len];
    if (!is_safe_name(name)) return .invalid_argument;

    if (is_stub_mode()) {
        populate_equivalence_stub(name, out_equivalence) catch return .internal_error;
        return .ok;
    }

    var body: std.Io.Writer.Allocating = .init(c_allocator);
    defer body.deinit();

    const url = build_endpoint_url("/api/semantic-equivalents/", name) catch |err| return status_from_host_error(err);
    defer c_allocator.free(url);

    fetch_json(url, &body) catch |err| return status_from_host_error(err);

    var parsed = std.json.parseFromSlice(EquivalenceApiResponse, c_allocator, body.written(), .{
        .ignore_unknown_fields = true,
    }) catch return .internal_error;
    defer parsed.deinit();

    populate_equivalence_from_response(parsed.value, out_equivalence) catch return .internal_error;
    return .ok;
}

pub export fn qdb_semantic_release_descriptor(view: *semantic.SemanticDescriptorView) callconv(.c) void {
    free_string(view.knot_name_ptr, view.knot_name_len);
    free_string(view.descriptor_version_ptr, view.descriptor_version_len);
    free_string(view.descriptor_hash_ptr, view.descriptor_hash_len);
    free_string(view.quandle_key_ptr, view.quandle_key_len);
    view.* = std.mem.zeroes(semantic.SemanticDescriptorView);
}

fn free_string_list(ptrs: [*][*]const u8, lens: [*]const usize, count: usize) void {
    if (count == 0) return;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        free_string(ptrs[i], lens[i]);
    }

    c_allocator.free(ptrs[0..count]);
    c_allocator.free(@as([*]usize, @ptrCast(@constCast(lens)))[0..count]);
}

pub export fn qdb_semantic_release_equivalence(view: *semantic.SemanticEquivalenceView) callconv(.c) void {
    free_string(view.name_ptr, view.name_len);
    free_string(view.descriptor_hash_ptr, view.descriptor_hash_len);
    free_string(view.quandle_key_ptr, view.quandle_key_len);
    free_string_list(view.strong_names_ptr, view.strong_name_lengths_ptr, view.strong_count);
    free_string_list(view.weak_names_ptr, view.weak_name_lengths_ptr, view.weak_count);
    free_string_list(view.combined_names_ptr, view.combined_name_lengths_ptr, view.combined_count);
    view.* = std.mem.zeroes(semantic.SemanticEquivalenceView);
}

fn make_optional_int(env: ?*c.ErlNifEnv, has_value: bool, value: i32) c.ERL_NIF_TERM {
    if (!has_value) return make_atom(env, "nil");
    return c.enif_make_int(env, value);
}

fn make_string_list_term(env: ?*c.ErlNifEnv, ptrs: [*][*]const u8, lens: [*]const usize, count: usize) c.ERL_NIF_TERM {
    if (count == 0) return c.enif_make_list(env, 0);
    if (count > std.math.maxInt(c_uint)) return c.enif_make_list(env, 0);

    const terms = c_allocator.alloc(c.ERL_NIF_TERM, count) catch return c.enif_make_list(env, 0);
    defer c_allocator.free(terms);

    var i: usize = 0;
    while (i < count) : (i += 1) {
        terms[i] = make_binary(env, ptrs[i][0..lens[i]]);
    }
    return c.enif_make_list_from_array(env, terms.ptr, @intCast(count));
}

fn nif_semantic_lookup(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    if (argc != 1) return make_error(env, "badarity");

    const name = inspect_input_binary(env, argv[0]) orelse return make_error(env, "invalid_argument");

    var view = semantic.semantic_lookup(name) catch |err| return make_error(env, nif_reason_from_semantic_error(err));
    defer semantic.release_descriptor(&view);

    var payload = c.enif_make_new_map(env);
    payload = put_map(env, payload, "name", make_binary(env, view.knot_name_ptr[0..view.knot_name_len]));
    payload = put_map(env, payload, "descriptor_version", make_binary(env, view.descriptor_version_ptr[0..view.descriptor_version_len]));
    payload = put_map(env, payload, "descriptor_hash", make_binary(env, view.descriptor_hash_ptr[0..view.descriptor_hash_len]));
    payload = put_map(env, payload, "quandle_key", make_binary(env, view.quandle_key_ptr[0..view.quandle_key_len]));
    payload = put_map(env, payload, "crossing_number", c.enif_make_int(env, view.crossing_number));
    payload = put_map(env, payload, "writhe", c.enif_make_int(env, view.writhe));
    payload = put_map(env, payload, "determinant", make_optional_int(env, view.has_determinant, view.determinant));
    payload = put_map(env, payload, "signature", make_optional_int(env, view.has_signature, view.signature));
    payload = put_map(env, payload, "quandle_generator_count", make_optional_int(env, view.has_quandle_generator_count, view.quandle_generator_count));
    payload = put_map(env, payload, "quandle_relation_count", make_optional_int(env, view.has_quandle_relation_count, view.quandle_relation_count));
    payload = put_map(env, payload, "colouring_count_3", make_optional_int(env, view.has_colouring_count_3, view.colouring_count_3));
    payload = put_map(env, payload, "colouring_count_5", make_optional_int(env, view.has_colouring_count_5, view.colouring_count_5));

    return make_ok(env, payload);
}

fn nif_semantic_equivalents(env: ?*c.ErlNifEnv, argc: c_int, argv: [*c]const c.ERL_NIF_TERM) callconv(.c) c.ERL_NIF_TERM {
    if (argc != 1) return make_error(env, "badarity");

    const name = inspect_input_binary(env, argv[0]) orelse return make_error(env, "invalid_argument");

    var view = semantic.semantic_equivalents(name) catch |err| return make_error(env, nif_reason_from_semantic_error(err));
    defer semantic.release_equivalence(&view);

    var payload = c.enif_make_new_map(env);
    payload = put_map(env, payload, "name", make_binary(env, view.name_ptr[0..view.name_len]));
    payload = put_map(env, payload, "descriptor_hash", make_binary(env, view.descriptor_hash_ptr[0..view.descriptor_hash_len]));
    payload = put_map(env, payload, "quandle_key", make_binary(env, view.quandle_key_ptr[0..view.quandle_key_len]));
    payload = put_map(env, payload, "strong_candidates", make_string_list_term(env, view.strong_names_ptr, view.strong_name_lengths_ptr, view.strong_count));
    payload = put_map(env, payload, "weak_candidates", make_string_list_term(env, view.weak_names_ptr, view.weak_name_lengths_ptr, view.weak_count));
    payload = put_map(env, payload, "combined_candidates", make_string_list_term(env, view.combined_names_ptr, view.combined_name_lengths_ptr, view.combined_count));
    payload = put_map(env, payload, "count", c.enif_make_int(env, @intCast(view.combined_count)));

    return make_ok(env, payload);
}

var nif_funcs = [_]c.ErlNifFunc{
    .{
        .name = "semantic_lookup",
        .arity = 1,
        .fptr = nif_semantic_lookup,
        .flags = c.ERL_NIF_DIRTY_JOB_CPU_BOUND,
    },
    .{
        .name = "semantic_equivalents",
        .arity = 1,
        .fptr = nif_semantic_equivalents,
        .flags = c.ERL_NIF_DIRTY_JOB_CPU_BOUND,
    },
};

var nif_entry = c.ErlNifEntry{
    .major = c.ERL_NIF_MAJOR_VERSION,
    .minor = c.ERL_NIF_MINOR_VERSION,
    .name = "Elixir.QuandleDBNif.Native",
    .num_of_funcs = @intCast(nif_funcs.len),
    .funcs = @ptrCast(&nif_funcs),
    .load = null,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = c.ERL_NIF_VM_VARIANT,
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(c.ErlNifResourceTypeInit),
    .min_erts = c.ERL_NIF_MIN_ERTS_VERSION,
};

pub export fn nif_init() callconv(.c) ?*c.ErlNifEntry {
    return &nif_entry;
}
