// SPDX-License-Identifier: PMPL-1.0-or-later
// BEAM NIF API - Zig bindings for Erlang NIF
//
// Provides Zig-friendly wrappers for the Erlang NIF C API

const std = @import("std");

// Opaque types from erl_nif.h (avoid @cImport to prevent inline function issues)
pub const env = opaque {};
pub const term = c_ulong;

// Binary structure (matches ErlNifBinary)
pub const binary = extern struct {
    size: usize,
    data: [*]u8,
};

// Resource type (opaque)
pub const resource_type = opaque {};

// NIF function pointer
pub const ErlNifFunc = extern struct {
    name: [*:0]const u8,
    arity: c_uint,
    fptr: *const fn (?*env, c_int, [*c]const term) callconv(.c) term,
    flags: c_uint,
};

// Resource type initialization
pub const ErlNifResourceTypeInit = extern struct {
    dtor: ?*const fn (?*env, ?*anyopaque) callconv(.c) void,
    stop: ?*const fn (?*env, ?*anyopaque, term, [*c]c_int) callconv(.c) void,
    down: ?*const fn (?*env, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void,
};

// NIF entry structure
pub const ErlNifEntry = extern struct {
    major: c_int,
    minor: c_int,
    name: [*:0]const u8,
    num_of_funcs: c_int,
    funcs: [*c]const ErlNifFunc,
    load: ?*const fn (?*env, [*c]?*anyopaque, term) callconv(.c) c_int,
    reload: ?*const fn (?*env, [*c]?*anyopaque, term) callconv(.c) c_int,
    upgrade: ?*const fn (?*env, [*c]?*anyopaque, [*c]?*anyopaque, term) callconv(.c) c_int,
    unload: ?*const fn (?*env, ?*anyopaque) callconv(.c) void,
    vm_variant: [*:0]const u8,
    options: c_uint,
    sizeof_ErlNifResourceTypeInit: usize,
};

// NIF API version
pub const ERL_NIF_MAJOR_VERSION = 2;
pub const ERL_NIF_MINOR_VERSION = 16;

// Encoding constants
const ERL_NIF_LATIN1 = 1;

// Resource flags
const ERL_NIF_RT_CREATE = 1;
const ERL_NIF_RT_TAKEOVER = 2;

// External NIF functions (direct C ABI)
extern fn enif_make_atom(env: ?*env, name: [*:0]const u8) callconv(.c) term;
extern fn enif_make_badarg(env: ?*env) callconv(.c) term;
extern fn enif_make_int(env: ?*env, i: c_int) callconv(.c) term;
extern fn enif_get_atom(env: ?*env, t: term, buf: [*]u8, len: c_uint, encoding: c_uint) callconv(.c) c_uint;
extern fn enif_get_resource(env: ?*env, t: term, resource_type: ?*resource_type, objp: *?*anyopaque) callconv(.c) c_int;
extern fn enif_alloc_resource(resource_type: ?*resource_type, size: usize) callconv(.c) ?*anyopaque;
extern fn enif_release_resource(obj: *anyopaque) callconv(.c) void;
extern fn enif_make_resource(env: ?*env, obj: *anyopaque) callconv(.c) term;
// Destructor function type for resources
pub const ErlNifResourceDtor = fn (?*env, ?*anyopaque) callconv(.c) void;

extern fn enif_open_resource_type(env: ?*env, module_str: ?[*:0]const u8, name: [*:0]const u8, dtor: ?*const ErlNifResourceDtor, flags: c_uint, tried: ?*c_uint) callconv(.c) ?*resource_type;
extern fn enif_inspect_binary(env: ?*env, term: term, bin: *binary) callconv(.c) c_int;
extern fn enif_alloc_binary(size: usize, bin: *binary) callconv(.c) c_int;
extern fn enif_make_binary(env: ?*env, bin: *const binary) callconv(.c) term;

// C helper functions (from nif_helpers.c - wrappers for inline functions)
extern fn nif_make_tuple2(env: ?*env, t1: term, t2: term) callconv(.c) term;
extern fn nif_make_tuple3(env: ?*env, t1: term, t2: term, t3: term) callconv(.c) term;

// Zig-friendly wrappers
pub fn make_atom(e: ?*env, name: [*:0]const u8) term {
    return enif_make_atom(e, name);
}

pub fn make_badarg(e: ?*env) term {
    return enif_make_badarg(e);
}

pub fn make_int(e: ?*env, i: c_int) term {
    return enif_make_int(e, i);
}

pub fn make_tuple2(e: ?*env, t1: term, t2: term) term {
    return nif_make_tuple2(e, t1, t2);
}

pub fn make_tuple3(e: ?*env, t1: term, t2: term, t3: term) term {
    return nif_make_tuple3(e, t1, t2, t3);
}

pub fn get_atom(e: ?*env, t: term, buf: []u8) usize {
    const len = enif_get_atom(e, t, buf.ptr, @intCast(buf.len), ERL_NIF_LATIN1);
    return if (len > 0) @intCast(len - 1) else 0;
}

pub fn get_binary(e: ?*env, t: term, bin: *binary) c_int {
    return enif_inspect_binary(e, t, bin);
}

pub fn make_binary(e: ?*env, data: []const u8) !term {
    var bin: binary = undefined;
    if (enif_alloc_binary(data.len, &bin) == 0) {
        return error.AllocFailed;
    }
    @memcpy(bin.data[0..data.len], data);
    return enif_make_binary(e, &bin);
}

pub fn get_resource(e: ?*env, t: term, comptime T: type, rt: ?*resource_type) !*anyopaque {
    _ = T;
    var obj: ?*anyopaque = null;
    if (enif_get_resource(e, t, rt, &obj) == 0) {
        return error.InvalidResource;
    }
    return obj orelse error.NullResource;
}

pub fn alloc_resource(e: ?*env, obj: anytype, rt: ?*resource_type) !term {
    const T = @TypeOf(obj.*);
    const res_ptr = enif_alloc_resource(rt, @sizeOf(T)) orelse return error.AllocFailed;
    // SAFETY: res_ptr comes from enif_alloc_resource() which allocates @sizeOf(T)
    // bytes with alignment sufficient for any C type. Since T is a Zig struct used
    // as a NIF resource, the BEAM allocator guarantees at least max_align_t alignment
    // which satisfies @alignOf(T). The pointer is valid until enif_release_resource().
    const typed_ptr: *T = @ptrCast(@alignCast(res_ptr));
    typed_ptr.* = obj.*;
    return enif_make_resource(e, res_ptr);
}

pub fn open_resource_type(e: ?*env, name: [*:0]const u8, dtor: ?*const ErlNifResourceDtor) !?*resource_type {
    const rt = enif_open_resource_type(e, null, name, dtor, ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER, null);
    return rt orelse error.OpenFailed;
}
