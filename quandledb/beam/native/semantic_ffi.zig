// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Local mirror of ../../src/ffi/semantic_ffi.zig for BEAM native builds.
// Keep this file interface-compatible with the shared semantic FFI contract.
const std = @import("std");
const builtin = @import("builtin");

pub const SemanticStatus = enum(c_int) {
    ok = 0,
    not_found = 1,
    invalid_argument = 2,
    internal_error = 3,
};

pub const SemanticError = error{
    NotFound,
    InvalidArgument,
    InternalError,
};

pub const SemanticDescriptorView = extern struct {
    knot_name_ptr: [*]const u8,
    knot_name_len: usize,
    descriptor_version_ptr: [*]const u8,
    descriptor_version_len: usize,
    descriptor_hash_ptr: [*]const u8,
    descriptor_hash_len: usize,
    quandle_key_ptr: [*]const u8,
    quandle_key_len: usize,
    crossing_number: i32,
    writhe: i32,
    determinant: i32,
    has_determinant: bool,
    signature: i32,
    has_signature: bool,
    quandle_generator_count: i32,
    has_quandle_generator_count: bool,
    quandle_relation_count: i32,
    has_quandle_relation_count: bool,
    colouring_count_3: i32,
    has_colouring_count_3: bool,
    colouring_count_5: i32,
    has_colouring_count_5: bool,
};

pub const SemanticEquivalenceView = extern struct {
    name_ptr: [*]const u8,
    name_len: usize,
    descriptor_hash_ptr: [*]const u8,
    descriptor_hash_len: usize,
    quandle_key_ptr: [*]const u8,
    quandle_key_len: usize,
    strong_names_ptr: [*][*]const u8,
    strong_name_lengths_ptr: [*]const usize,
    strong_count: usize,
    weak_names_ptr: [*][*]const u8,
    weak_name_lengths_ptr: [*]const usize,
    weak_count: usize,
    combined_names_ptr: [*][*]const u8,
    combined_name_lengths_ptr: [*]const usize,
    combined_count: usize,
};

pub extern fn qdb_semantic_lookup(name_ptr: [*]const u8, name_len: usize, out_descriptor: *SemanticDescriptorView) SemanticStatus;
pub extern fn qdb_semantic_equivalents(name_ptr: [*]const u8, name_len: usize, out_equivalence: *SemanticEquivalenceView) SemanticStatus;
pub extern fn qdb_semantic_release_descriptor(view: *SemanticDescriptorView) void;
pub extern fn qdb_semantic_release_equivalence(view: *SemanticEquivalenceView) void;

fn host_semantic_lookup(name_ptr: [*]const u8, name_len: usize, out_descriptor: *SemanticDescriptorView) SemanticStatus {
    if (comptime builtin.is_test) return .internal_error;
    return qdb_semantic_lookup(name_ptr, name_len, out_descriptor);
}

fn host_semantic_equivalents(name_ptr: [*]const u8, name_len: usize, out_equivalence: *SemanticEquivalenceView) SemanticStatus {
    if (comptime builtin.is_test) return .internal_error;
    return qdb_semantic_equivalents(name_ptr, name_len, out_equivalence);
}

fn status_to_error(status: SemanticStatus) SemanticError!void {
    return switch (status) {
        .ok => {},
        .not_found => error.NotFound,
        .invalid_argument => error.InvalidArgument,
        .internal_error => error.InternalError,
    };
}

pub fn semantic_lookup(name: []const u8) SemanticError!SemanticDescriptorView {
    if (name.len == 0) return error.InvalidArgument;
    var out = std.mem.zeroes(SemanticDescriptorView);
    try status_to_error(host_semantic_lookup(name.ptr, name.len, &out));
    return out;
}

pub fn semantic_equivalents(name: []const u8) SemanticError!SemanticEquivalenceView {
    if (name.len == 0) return error.InvalidArgument;
    var out = std.mem.zeroes(SemanticEquivalenceView);
    try status_to_error(host_semantic_equivalents(name.ptr, name.len, &out));
    return out;
}

pub fn release_descriptor(view: *SemanticDescriptorView) void {
    qdb_semantic_release_descriptor(view);
}

pub fn release_equivalence(view: *SemanticEquivalenceView) void {
    qdb_semantic_release_equivalence(view);
}
