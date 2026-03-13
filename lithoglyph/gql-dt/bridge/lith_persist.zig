// SPDX-License-Identifier: PMPL-1.0
// SPDX-FileCopyrightText: 2025 hyperpolymath
//
// lith_persist.zig - Lith persistent storage backend (minimal)
//
// Provides basic persistence for FQLdt using global state.
// Exports C ABI functions for Lean 4's @[extern] declarations.

const std = @import("std");
const types = @import("lith_types.zig");

const LithStatus = types.LithStatus;

// ============================================================================
// Global State
// ============================================================================

var initialized: bool = false;
var db_path_buf: [256]u8 = undefined;
var db_path_len: usize = 0;
var dirty: bool = false;
var debug_init_counter: i32 = 0; // Debug: incremented each time lith_init runs

// Simple row counter per table (using fixed table slots)
const MAX_TABLES: usize = 16;
var table_names: [MAX_TABLES][64]u8 = undefined;
var table_name_lens: [MAX_TABLES]usize = [_]usize{0} ** MAX_TABLES;
var table_row_counts: [MAX_TABLES]u64 = [_]u64{0} ** MAX_TABLES;
var table_next_ids: [MAX_TABLES]u64 = [_]u64{1} ** MAX_TABLES;
var num_tables: usize = 0;

// ============================================================================
// Helper Functions
// ============================================================================

fn findTableIndex(name: []const u8) ?usize {
    for (0..num_tables) |i| {
        if (table_name_lens[i] == name.len) {
            if (std.mem.eql(u8, table_names[i][0..table_name_lens[i]], name)) {
                return i;
            }
        }
    }
    return null;
}

fn createTable(name: []const u8) ?usize {
    if (num_tables >= MAX_TABLES or name.len > 64) return null;
    const idx = num_tables;
    @memcpy(table_names[idx][0..name.len], name);
    table_name_lens[idx] = name.len;
    table_row_counts[idx] = 0;
    table_next_ids[idx] = 1;
    num_tables += 1;
    return idx;
}

fn getOrCreateTable(name: []const u8) ?usize {
    if (findTableIndex(name)) |idx| return idx;
    return createTable(name);
}

// ============================================================================
// Exported C ABI Functions
// ============================================================================

/// Initialize database with file path
/// Returns: 0 = success, -99 = error, 42 = special marker for fresh init
pub fn lith_init(path_ptr: ?[*]const u8, path_len: usize) i32 {
    debug_init_counter += 1; // Track calls

    if (initialized) return 0; // Already initialized

    if (path_ptr) |ptr| {
        if (path_len > 0 and path_len <= db_path_buf.len) {
            @memcpy(db_path_buf[0..path_len], ptr[0..path_len]);
            db_path_len = path_len;
        }
    } else {
        const default = "gqldt.db";
        @memcpy(db_path_buf[0..default.len], default);
        db_path_len = default.len;
    }

    initialized = true;
    dirty = false;
    return 42; // Special marker: fresh initialization
}

/// Debug: get init counter value (takes dummy parameter to prevent caching)
pub fn lith_debug_init_counter(dummy: i32) i32 {
    _ = dummy;
    return debug_init_counter;
}

/// Debug: fresh test function - increments counter and returns it
var test_counter: i32 = 100;
pub fn lith_test_fresh(input: i32) i32 {
    test_counter += input;
    return test_counter;
}

/// Close database
pub fn lith_close() LithStatus {
    if (!initialized) return .ok;

    // Reset all state
    num_tables = 0;
    for (0..MAX_TABLES) |i| {
        table_name_lens[i] = 0;
        table_row_counts[i] = 0;
        table_next_ids[i] = 1;
    }

    initialized = false;
    dirty = false;
    return .ok;
}

/// Insert a row into a table
pub fn lith_insert_row(
    table_ptr: ?[*]const u8,
    table_len: usize,
    cols_ptr: ?[*]const u8,
    cols_len: usize,
    vals_ptr: ?[*]const u8,
    vals_len: usize,
    actor_ptr: ?[*]const u8,
    actor_len: usize,
    rationale_ptr: ?[*]const u8,
    rationale_len: usize,
    timestamp: u64,
    row_id: *u64,
) LithStatus {
    _ = cols_ptr;
    _ = cols_len;
    _ = vals_ptr;
    _ = vals_len;
    _ = actor_ptr;
    _ = actor_len;
    _ = rationale_ptr;
    _ = rationale_len;
    _ = timestamp;

    if (!initialized) {
        _ = lith_init(null, 0);
    }

    const table_name = if (table_ptr) |p|
        if (table_len > 0) p[0..table_len] else return .type_error
    else
        return .type_error;

    const idx = getOrCreateTable(table_name) orelse return .out_of_memory;

    row_id.* = table_next_ids[idx];
    table_next_ids[idx] += 1;
    table_row_counts[idx] += 1;
    dirty = true;

    return .ok;
}

/// Get row count for a table
pub fn lith_table_count(table_ptr: ?[*]const u8, table_len: usize) u64 {
    if (!initialized) return 0;

    const table_name = if (table_ptr) |p|
        if (table_len > 0) p[0..table_len] else return 0
    else
        return 0;

    const idx = findTableIndex(table_name) orelse return 0;
    return table_row_counts[idx];
}

/// Delete a row from a table
pub fn lith_delete_row(
    table_ptr: ?[*]const u8,
    table_len: usize,
    row_id: u64,
) LithStatus {
    _ = row_id;

    if (!initialized) return .generic_error;

    const table_name = if (table_ptr) |p|
        if (table_len > 0) p[0..table_len] else return .type_error
    else
        return .type_error;

    const idx = findTableIndex(table_name) orelse return .type_error;

    if (table_row_counts[idx] > 0) {
        table_row_counts[idx] -= 1;
        dirty = true;
        return .ok;
    }

    return .generic_error;
}

/// Save database to disk (stub - marks as clean)
pub fn lith_save(dummy: i32) LithStatus {
    _ = dummy;
    if (!initialized) return .generic_error;
    dirty = false;
    return .ok;
}

/// Check if database is initialized (takes dummy to prevent caching)
pub fn lith_is_init(dummy: i32) bool {
    _ = dummy;
    return initialized;
}

/// Debug: force set initialized for testing
pub fn lith_debug_set_init(val: bool) void {
    initialized = val;
}

/// Debug: get initialized as integer (for debugging Lean FFI)
pub fn lith_debug_init_status() i32 {
    return if (initialized) 1 else 0;
}

// ============================================================================
// Tests
// ============================================================================

test "basic persistence" {
    try std.testing.expectEqual(LithStatus.ok, lith_init(null, 0));
    try std.testing.expect(lith_is_init());

    var row_id: u64 = 0;
    try std.testing.expectEqual(LithStatus.ok, lith_insert_row(
        "test",
        4,
        null,
        0,
        null,
        0,
        "actor",
        5,
        "reason",
        6,
        0,
        &row_id,
    ));
    try std.testing.expectEqual(@as(u64, 1), row_id);
    try std.testing.expectEqual(@as(u64, 1), lith_table_count("test", 4));

    try std.testing.expectEqual(LithStatus.ok, lith_save());
    try std.testing.expectEqual(LithStatus.ok, lith_close());
    try std.testing.expect(!lith_is_init());
}
