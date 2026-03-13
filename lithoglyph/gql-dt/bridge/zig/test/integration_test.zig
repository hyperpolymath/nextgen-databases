// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 hyperpolymath
//
// Integration tests for Zig FFI bridge

const std = @import("std");
const main = @import("main");

test "fdb_insert stub returns ok" {
    // Mock database handle (in production, would be created by Lith)
    var db: main.FdbDb = undefined;
    const db_ptr = @as(*main.FdbDb, @ptrCast(&db));

    const collection = "test_collection";
    const document = "{\"id\": 1, \"value\": 42}";
    const proof = "{}"; // Empty proof for stub

    const status = main.fdb_insert(
        db_ptr,
        collection,
        document.ptr,
        document.len,
        proof.ptr,
        proof.len,
    );

    try std.testing.expectEqual(@as(c_int, 0), status);
}

test "fdb_register_constraint_checker stub" {
    var db: main.FdbDb = undefined;
    const db_ptr = @as(*main.FdbDb, @ptrCast(&db));

    const checker = struct {
        fn check(doc: [*]const u8, len: usize) callconv(.C) bool {
            _ = doc;
            _ = len;
            return true;
        }
    }.check;

    const status = main.fdb_register_constraint_checker(db_ptr, checker);

    try std.testing.expectEqual(@as(c_int, 0), status);
}
