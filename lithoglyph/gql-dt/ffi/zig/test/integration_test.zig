// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// GQL-DT Integration Tests
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI.
// They exercise the exported C-ABI functions end-to-end.

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn gqldt_init() callconv(.c) i32;
extern fn gqldt_cleanup() callconv(.c) void;
extern fn gqldt_db_open(path: [*:0]const u8, path_len: u64, db_out: *?*anyopaque) callconv(.c) i32;
extern fn gqldt_db_close(db: *anyopaque) callconv(.c) i32;
extern fn gqldt_parse(query_str: [*:0]const u8, query_len: u64, query_out: *?*anyopaque) callconv(.c) i32;
extern fn gqldt_parse_inferred(query_str: [*:0]const u8, query_len: u64, schema: *anyopaque, query_out: *?*anyopaque) callconv(.c) i32;
extern fn gqldt_typecheck(query: *anyopaque, schema: *anyopaque) callconv(.c) i32;
extern fn gqldt_execute(db: *anyopaque, query: *anyopaque, result_out: *?*anyopaque) callconv(.c) i32;
extern fn gqldt_get_schema(db: *anyopaque, collection_name: [*:0]const u8, schema_out: *?*anyopaque) callconv(.c) i32;
extern fn gqldt_query_free(query: *anyopaque) callconv(.c) void;
extern fn gqldt_schema_free(schema: *anyopaque) callconv(.c) void;
extern fn gqldt_result_free(result: *anyopaque) callconv(.c) void;
extern fn gqldt_serialize_cbor(query: *anyopaque, buffer: [*]u8, buffer_len: u64, written_out: *u64) callconv(.c) i32;
extern fn gqldt_serialize_json(query: *anyopaque, buffer: [*]u8, buffer_len: u64, written_out: *u64) callconv(.c) i32;
extern fn gqldt_deserialize_cbor(buffer: [*]const u8, buffer_len: u64, query_out: *?*anyopaque) callconv(.c) i32;
extern fn gqldt_validate_permissions(query: *anyopaque, user_id: [*:0]const u8, permissions: *const anyopaque) callconv(.c) i32;
extern fn gqldt_version() callconv(.c) [*:0]const u8;
extern fn gqldt_alloc_slot() callconv(.c) ?*anyopaque;
extern fn gqldt_read_slot(slot: *anyopaque) callconv(.c) u64;
extern fn gqldt_free_slot(slot: *anyopaque) callconv(.c) void;
extern fn gqldt_bits64_to_ptr(value: u64) callconv(.c) ?*anyopaque;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "init and cleanup" {
    const status = gqldt_init();
    try testing.expectEqual(@as(i32, 0), status);
    gqldt_cleanup();
}

test "double init is idempotent" {
    _ = gqldt_init();
    const status = gqldt_init();
    try testing.expectEqual(@as(i32, 0), status);
    gqldt_cleanup();
}

//==============================================================================
// Database Operations
//==============================================================================

test "db_open and db_close" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*anyopaque = null;
    const open_status = gqldt_db_open("test.db", 7, &db);
    try testing.expectEqual(@as(i32, 0), open_status);
    try testing.expect(db != null);

    const close_status = gqldt_db_close(db.?);
    try testing.expectEqual(@as(i32, 0), close_status);
}

test "db_open rejects empty path" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*anyopaque = null;
    const status = gqldt_db_open("", 0, &db);
    try testing.expectEqual(@as(i32, 1), status); // invalid_arg
}

test "db_open rejects oversized path" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*anyopaque = null;
    const status = gqldt_db_open("x", 5000, &db);
    try testing.expectEqual(@as(i32, 1), status); // invalid_arg
}

//==============================================================================
// Query Parsing
//==============================================================================

test "parse valid query" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var query: ?*anyopaque = null;
    const status = gqldt_parse("MATCH (n:Person) RETURN n", 25, &query);
    try testing.expectEqual(@as(i32, 0), status);
    try testing.expect(query != null);

    gqldt_query_free(query.?);
}

test "parse rejects empty query" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var query: ?*anyopaque = null;
    const status = gqldt_parse("", 0, &query);
    try testing.expectEqual(@as(i32, 1), status); // invalid_arg
}

//==============================================================================
// Type Checking and Execution
//==============================================================================

test "full pipeline: open -> schema -> parse -> typecheck -> execute" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    // Open database.
    var db: ?*anyopaque = null;
    _ = gqldt_db_open("pipeline.db", 11, &db);
    defer gqldt_db_close(db.?);

    // Get schema.
    var schema: ?*anyopaque = null;
    _ = gqldt_get_schema(db.?, "nodes", &schema);
    defer gqldt_schema_free(schema.?);

    // Parse query.
    var query: ?*anyopaque = null;
    _ = gqldt_parse("MATCH (n) RETURN n", 18, &query);
    defer gqldt_query_free(query.?);

    // Type-check.
    const tc_status = gqldt_typecheck(query.?, schema.?);
    try testing.expectEqual(@as(i32, 0), tc_status);

    // Execute.
    var result: ?*anyopaque = null;
    const exec_status = gqldt_execute(db.?, query.?, &result);
    try testing.expectEqual(@as(i32, 0), exec_status);
    try testing.expect(result != null);

    gqldt_result_free(result.?);
}

test "execute without typecheck fails" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*anyopaque = null;
    _ = gqldt_db_open("test.db", 7, &db);
    defer gqldt_db_close(db.?);

    var query: ?*anyopaque = null;
    _ = gqldt_parse("MATCH (n) RETURN n", 18, &query);
    defer gqldt_query_free(query.?);

    var result: ?*anyopaque = null;
    const status = gqldt_execute(db.?, query.?, &result);
    try testing.expectEqual(@as(i32, 2), status); // type_mismatch
}

//==============================================================================
// Serialization
//==============================================================================

test "serialize to CBOR and back" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var query: ?*anyopaque = null;
    _ = gqldt_parse("RETURN 42", 9, &query);
    defer gqldt_query_free(query.?);

    var cbor_buf: [1024]u8 = undefined;
    var written: u64 = 0;
    const ser_status = gqldt_serialize_cbor(query.?, &cbor_buf, 1024, &written);
    try testing.expectEqual(@as(i32, 0), ser_status);
    try testing.expect(written > 0);

    var query2: ?*anyopaque = null;
    const deser_status = gqldt_deserialize_cbor(&cbor_buf, written, &query2);
    try testing.expectEqual(@as(i32, 0), deser_status);
    try testing.expect(query2 != null);

    gqldt_query_free(query2.?);
}

test "serialize to JSON" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var query: ?*anyopaque = null;
    _ = gqldt_parse("RETURN 1", 8, &query);
    defer gqldt_query_free(query.?);

    var json_buf: [1024]u8 = undefined;
    var written: u64 = 0;
    const status = gqldt_serialize_json(query.?, &json_buf, 1024, &written);
    try testing.expectEqual(@as(i32, 0), status);

    const json_str = json_buf[0..@intCast(written)];
    try testing.expectEqualStrings("{\"query\":\"RETURN 1\"}", json_str);
}

//==============================================================================
// Slot Allocation Helpers
//==============================================================================

test "alloc_slot and free_slot" {
    const slot = gqldt_alloc_slot() orelse return error.SlotAllocFailed;
    const value = gqldt_read_slot(slot);
    try testing.expectEqual(@as(u64, 0), value); // initially zero
    gqldt_free_slot(slot);
}

test "bits64_to_ptr null returns null" {
    const ptr = gqldt_bits64_to_ptr(0);
    try testing.expect(ptr == null);
}

//==============================================================================
// Version
//==============================================================================

test "version string is semantic version" {
    const ver = gqldt_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}
