// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// Zig FFI Bridge - Main Module
// Bidirectional FFI: Lean 4 ↔ Zig ↔ Lith Forth core

const std = @import("std");

/// Status code for FFI operations
pub const LithStatus = enum(i32) {
    ok = 0,
    error_null_pointer = 1,
    error_invalid_proof = 2,
    error_type_mismatch = 3,
    error_constraint_violation = 4,
    error_out_of_memory = 5,

    pub fn toC(self: LithStatus) c_int {
        return @intFromEnum(self);
    }
};

/// Opaque database handle (non-null guaranteed by Lean 4 types)
pub const LithDb = opaque {};

/// FFI-safe string view (non-owning)
pub const LithString = struct {
    data: [*]const u8,
    len: usize,

    pub fn fromSlice(slice: []const u8) LithString {
        return .{ .data = slice.ptr, .len = slice.len };
    }

    pub fn toSlice(self: LithString) []const u8 {
        return self.data[0..self.len];
    }
};

/// Forward: Lean 4 → Zig → Lith
/// Insert operation with proof blob
export fn lith_insert(
    db: *LithDb,
    collection: [*:0]const u8,
    document: [*]const u8,
    doc_len: usize,
    proof_blob: [*]const u8,
    proof_len: usize,
) callconv(.C) c_int {
    _ = db;
    _ = collection;
    _ = document;
    _ = doc_len;
    _ = proof_blob;
    _ = proof_len;

    // TODO: Implement actual insertion
    // 1. Deserialize proof blob (CBOR)
    // 2. Verify proof against schema
    // 3. Insert into Lith via Forth FFI
    // 4. Return status

    return LithStatus.ok.toC();
}

/// Reverse: Lith → Zig → Lean 4
/// Register constraint checker callback
export fn lith_register_constraint_checker(
    db: *LithDb,
    checker: *const fn (doc: [*]const u8, len: usize) callconv(.C) bool,
) callconv(.C) c_int {
    _ = db;
    _ = checker;

    // TODO: Implement callback registration
    // Store function pointer for later invocation
    // When Lith validates data, call this Lean 4 checker

    return LithStatus.ok.toC();
}

/// Get discovered functional dependencies
export fn lith_get_discovered_fds(
    db: *LithDb,
    collection: [*:0]const u8,
    out_fds: *[*]u8,
    out_len: *usize,
) callconv(.C) c_int {
    _ = db;
    _ = collection;
    _ = out_fds;
    _ = out_len;

    // TODO: Implement FD discovery
    // 1. Query Lith for collection statistics
    // 2. Run FD discovery algorithm (DFD, TANE, etc.)
    // 3. Serialize FDs to CBOR
    // 4. Return pointer + length

    return LithStatus.ok.toC();
}

/// Verify normalization proof
export fn lith_verify_normalization_proof(
    db: *LithDb,
    step_blob: [*]const u8,
    step_len: usize,
    proof_blob: [*]const u8,
    proof_len: usize,
) callconv(.C) c_int {
    _ = db;
    _ = step_blob;
    _ = step_len;
    _ = proof_blob;
    _ = proof_len;

    // TODO: Implement proof verification
    // 1. Deserialize normalization step
    // 2. Deserialize Lean 4 proof
    // 3. Verify proof is valid for step
    // 4. Return status

    return LithStatus.ok.toC();
}

/// Free memory allocated by FFI functions
export fn lith_free(ptr: [*]u8, len: usize) callconv(.C) void {
    const allocator = std.heap.c_allocator;
    const slice = ptr[0..len];
    allocator.free(slice);
}

test "LithStatus roundtrip" {
    const status = LithStatus.ok;
    try std.testing.expectEqual(@as(c_int, 0), status.toC());
}

test "LithString conversion" {
    const str = "Hello, Lith!";
    const lith_str = LithString.fromSlice(str);
    try std.testing.expectEqualSlices(u8, str, lith_str.toSlice());
}
