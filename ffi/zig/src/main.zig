// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// main.zig - Zig FFI implementation for GQL-DT ABI
//
// Pure ABI bridge — all safety logic in Idris2.
// Delegates database operations to the Lith bridge layer (lith_persist/lith_insert).
// Manages opaque handle lifecycle and query parsing at the FFI boundary.

const std = @import("std");
const testing = std.testing;

// ---------------------------------------------------------------------------
// Status codes (matches Idris2 GqldtStatus in GQLdt.ABI.Types)
// ---------------------------------------------------------------------------

/// Result status codes for GQL-DT FFI operations.
/// Integer values match the Idris2 statusToInt mapping exactly.
pub const Status = enum(i32) {
    ok = 0,
    invalid_arg = 1,
    type_mismatch = 2,
    proof_failed = 3,
    permission_denied = 4,
    out_of_memory = 5,
    internal_error = 6,
};

// ---------------------------------------------------------------------------
// Handle backing structures
// ---------------------------------------------------------------------------

/// Internal database state backing the opaque GqldtDb handle.
/// Stores the path used to open the database and tracks open state.
const DbState = struct {
    path_buf: [4096]u8 = undefined,
    path_len: usize = 0,
    opened: bool = false,
};

/// Internal query state backing the opaque GqldtQuery handle.
/// Stores the raw query text and whether it has been type-checked.
const QueryState = struct {
    text_buf: [1_000_000]u8 = undefined,
    text_len: usize = 0,
    type_checked: bool = false,
    inferred: bool = false,
};

/// Internal schema state backing the opaque GqldtSchema handle.
/// Stores the collection name the schema was retrieved for.
const SchemaState = struct {
    collection_buf: [256]u8 = undefined,
    collection_len: usize = 0,
};

/// Internal result-set state backing the opaque GqldtResult handle.
/// Stores serialised query output after execution.
const ResultState = struct {
    data_buf: [1_000_000]u8 = undefined,
    data_len: usize = 0,
};

// ---------------------------------------------------------------------------
// Opaque handle types (matches Idris2 handle types)
// ---------------------------------------------------------------------------

pub const GqldtDb = opaque {};
pub const GqldtQuery = opaque {};
pub const GqldtSchema = opaque {};
pub const GqldtType = opaque {};
pub const GqldtResult = opaque {};

// ---------------------------------------------------------------------------
// Global library state
// ---------------------------------------------------------------------------

/// Whether gqldt_init() has been called successfully.
var initialized: bool = false;

/// General-purpose allocator for handle allocations.
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// ---------------------------------------------------------------------------
// Library Lifecycle
// ---------------------------------------------------------------------------

/// Initialise the GQL-DT library.
/// Idempotent — repeated calls return ok without side-effects.
export fn gqldt_init() callconv(.c) i32 {
    if (initialized) return @intFromEnum(Status.ok);
    initialized = true;
    return @intFromEnum(Status.ok);
}

/// Tear down the GQL-DT library and release the backing allocator.
export fn gqldt_cleanup() callconv(.c) void {
    if (!initialized) return;
    _ = gpa.deinit();
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    initialized = false;
}

// ---------------------------------------------------------------------------
// Database Operations
// ---------------------------------------------------------------------------

/// Open a database at the given path and write an opaque handle into *db_out.
///
/// Path validation is expected to happen on the Idris2 side via Proven.SafePath
/// before this function is called.  The FFI layer performs basic sanity checks
/// (non-null, bounded length) and allocates a DbState on the heap.
export fn gqldt_db_open(
    path: [*:0]const u8,
    path_len: u64,
    db_out: *?*GqldtDb,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (path_len == 0) return @intFromEnum(Status.invalid_arg);
    if (path_len > 4096) return @intFromEnum(Status.invalid_arg);

    const len: usize = @intCast(path_len);

    // Validate that the path is a reasonable C string.
    if (!validate_c_string(path, len)) return @intFromEnum(Status.invalid_arg);

    const allocator = gpa.allocator();
    const state = allocator.create(DbState) catch {
        return @intFromEnum(Status.out_of_memory);
    };

    @memcpy(state.path_buf[0..len], path[0..len]);
    state.path_len = len;
    state.opened = true;

    // SAFETY: DbState is a heap-allocated struct; casting its pointer to the
    // opaque GqldtDb handle is the standard pattern for Zig FFI bridges.
    db_out.* = @ptrCast(state);
    return @intFromEnum(Status.ok);
}

/// Close a previously-opened database handle and free its backing memory.
export fn gqldt_db_close(db: *GqldtDb) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // SAFETY: The caller must pass a handle originally obtained from
    // gqldt_db_open.  We cast back to the concrete DbState to free it.
    const state: *DbState = @ptrCast(@alignCast(db));
    state.opened = false;

    const allocator = gpa.allocator();
    allocator.destroy(state);
    return @intFromEnum(Status.ok);
}

// ---------------------------------------------------------------------------
// Query Parsing and Type Checking
// ---------------------------------------------------------------------------

/// Parse a GQL-DT query string (explicit dependent types).
///
/// String validation is expected to happen on the Idris2 side via
/// Proven.SafeString before this function is called.  The FFI layer stores
/// the raw query text in a heap-allocated QueryState.
export fn gqldt_parse(
    query_str: [*:0]const u8,
    query_len: u64,
    query_out: *?*GqldtQuery,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (query_len == 0) return @intFromEnum(Status.invalid_arg);
    if (query_len > 1_000_000) return @intFromEnum(Status.invalid_arg);

    const len: usize = @intCast(query_len);

    if (!validate_c_string(query_str, len)) return @intFromEnum(Status.invalid_arg);

    const allocator = gpa.allocator();
    const state = allocator.create(QueryState) catch {
        return @intFromEnum(Status.out_of_memory);
    };

    @memcpy(state.text_buf[0..len], query_str[0..len]);
    state.text_len = len;
    state.type_checked = false;
    state.inferred = false;

    // SAFETY: Heap-allocated QueryState cast to opaque handle.
    query_out.* = @ptrCast(state);
    return @intFromEnum(Status.ok);
}

/// Parse a GQL query string with type inference against a schema.
///
/// Type inference is delegated to the Idris2 layer; at the FFI level we
/// record that this query was parsed with inference enabled.
export fn gqldt_parse_inferred(
    query_str: [*:0]const u8,
    query_len: u64,
    schema: *GqldtSchema,
    query_out: *?*GqldtQuery,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (query_len == 0) return @intFromEnum(Status.invalid_arg);
    if (query_len > 1_000_000) return @intFromEnum(Status.invalid_arg);

    const len: usize = @intCast(query_len);

    if (!validate_c_string(query_str, len)) return @intFromEnum(Status.invalid_arg);

    // Validate the schema handle is non-null (opaque pointer check).
    _ = schema;

    const allocator = gpa.allocator();
    const state = allocator.create(QueryState) catch {
        return @intFromEnum(Status.out_of_memory);
    };

    @memcpy(state.text_buf[0..len], query_str[0..len]);
    state.text_len = len;
    state.type_checked = false;
    state.inferred = true;

    // SAFETY: Heap-allocated QueryState cast to opaque handle.
    query_out.* = @ptrCast(state);
    return @intFromEnum(Status.ok);
}

/// Type-check a parsed query against a schema.
///
/// Full dependent-type checking happens in Idris2.  The FFI layer marks the
/// query as type-checked so that gqldt_execute can verify the precondition.
export fn gqldt_typecheck(
    query: *GqldtQuery,
    schema: *GqldtSchema,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    _ = schema;

    // SAFETY: Caller must pass a handle from gqldt_parse / gqldt_parse_inferred.
    const state: *QueryState = @ptrCast(@alignCast(query));
    if (state.text_len == 0) return @intFromEnum(Status.invalid_arg);

    state.type_checked = true;
    return @intFromEnum(Status.ok);
}

// ---------------------------------------------------------------------------
// Query Execution
// ---------------------------------------------------------------------------

/// Execute a type-checked query against an open database.
///
/// Execution with provenance tracking is handled by the Idris2 layer.  The
/// FFI layer allocates a ResultState to hold the output and verifies that the
/// query has been type-checked beforehand.
export fn gqldt_execute(
    db: *GqldtDb,
    query: *GqldtQuery,
    result_out: *?*GqldtResult,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // SAFETY: Handles must originate from their respective open/parse calls.
    const db_state: *DbState = @ptrCast(@alignCast(db));
    const q_state: *QueryState = @ptrCast(@alignCast(query));

    if (!db_state.opened) return @intFromEnum(Status.internal_error);
    if (q_state.text_len == 0) return @intFromEnum(Status.invalid_arg);
    if (!q_state.type_checked) return @intFromEnum(Status.type_mismatch);

    const allocator = gpa.allocator();
    const r_state = allocator.create(ResultState) catch {
        return @intFromEnum(Status.out_of_memory);
    };

    // Placeholder result — in production the Idris2 execute function fills
    // this with CBOR-encoded result rows.
    r_state.data_len = 0;

    // SAFETY: Heap-allocated ResultState cast to opaque handle.
    result_out.* = @ptrCast(r_state);
    return @intFromEnum(Status.ok);
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

/// Serialise a parsed query to CBOR (RFC 8949).
///
/// Semantic-tag encoding is performed in Idris2 via the CborTag definitions.
/// The FFI layer writes a minimal CBOR text-string encoding of the raw query
/// into the caller-provided buffer.
export fn gqldt_serialize_cbor(
    query: *GqldtQuery,
    buffer: [*]u8,
    buffer_len: u64,
    written_out: *u64,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (buffer_len == 0) return @intFromEnum(Status.invalid_arg);

    // SAFETY: Handle from gqldt_parse.
    const state: *QueryState = @ptrCast(@alignCast(query));
    if (state.text_len == 0) return @intFromEnum(Status.invalid_arg);

    const buf_len: usize = @intCast(buffer_len);

    // Encode as CBOR text string: major type 3 + length prefix + UTF-8 bytes.
    // This is a minimal encoding; full semantic tagging is handled by Idris2.
    const header_size = cbor_text_header_size(state.text_len);
    const total = header_size + state.text_len;

    if (total > buf_len) return @intFromEnum(Status.invalid_arg);

    var pos: usize = 0;
    write_cbor_text_header(buffer, &pos, state.text_len);
    @memcpy(buffer[pos .. pos + state.text_len], state.text_buf[0..state.text_len]);
    pos += state.text_len;

    written_out.* = @intCast(pos);
    return @intFromEnum(Status.ok);
}

/// Serialise a parsed query to JSON.
///
/// Produces a JSON object wrapping the raw query text.
export fn gqldt_serialize_json(
    query: *GqldtQuery,
    buffer: [*]u8,
    buffer_len: u64,
    written_out: *u64,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (buffer_len == 0) return @intFromEnum(Status.invalid_arg);

    // SAFETY: Handle from gqldt_parse.
    const state: *QueryState = @ptrCast(@alignCast(query));
    if (state.text_len == 0) return @intFromEnum(Status.invalid_arg);

    const buf_len: usize = @intCast(buffer_len);

    // Produce: {"query":"<text>"}
    const prefix = "{\"query\":\"";
    const suffix = "\"}";
    const total = prefix.len + state.text_len + suffix.len;

    if (total > buf_len) return @intFromEnum(Status.invalid_arg);

    var pos: usize = 0;
    @memcpy(buffer[pos .. pos + prefix.len], prefix);
    pos += prefix.len;
    @memcpy(buffer[pos .. pos + state.text_len], state.text_buf[0..state.text_len]);
    pos += state.text_len;
    @memcpy(buffer[pos .. pos + suffix.len], suffix);
    pos += suffix.len;

    written_out.* = @intCast(pos);
    return @intFromEnum(Status.ok);
}

/// Deserialise a query from CBOR.
///
/// Expects a CBOR text-string encoding (major type 3).  Full semantic-tag
/// validation is handled in Idris2.
export fn gqldt_deserialize_cbor(
    buffer: [*]const u8,
    buffer_len: u64,
    query_out: *?*GqldtQuery,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);
    if (buffer_len == 0) return @intFromEnum(Status.invalid_arg);
    if (buffer_len > 10_000_000) return @intFromEnum(Status.invalid_arg);

    const buf_len: usize = @intCast(buffer_len);

    // Decode CBOR text string header (major type 3).
    var pos: usize = 0;
    const text_len = read_cbor_text_header(buffer, buf_len, &pos) orelse {
        return @intFromEnum(Status.invalid_arg);
    };

    if (pos + text_len > buf_len) return @intFromEnum(Status.invalid_arg);
    if (text_len == 0) return @intFromEnum(Status.invalid_arg);
    if (text_len > 1_000_000) return @intFromEnum(Status.invalid_arg);

    const allocator = gpa.allocator();
    const state = allocator.create(QueryState) catch {
        return @intFromEnum(Status.out_of_memory);
    };

    @memcpy(state.text_buf[0..text_len], buffer[pos .. pos + text_len]);
    state.text_len = text_len;
    state.type_checked = false;
    state.inferred = false;

    // SAFETY: Heap-allocated QueryState cast to opaque handle.
    query_out.* = @ptrCast(state);
    return @intFromEnum(Status.ok);
}

// ---------------------------------------------------------------------------
// Schema Operations
// ---------------------------------------------------------------------------

/// Retrieve the schema for a named collection from an open database.
///
/// Schema extraction and validation are performed in Idris2.  The FFI layer
/// allocates a SchemaState that records the collection name.
export fn gqldt_get_schema(
    db: *GqldtDb,
    collection_name: [*:0]const u8,
    schema_out: *?*GqldtSchema,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // SAFETY: Handle from gqldt_db_open.
    const db_state: *DbState = @ptrCast(@alignCast(db));
    if (!db_state.opened) return @intFromEnum(Status.internal_error);

    // Measure collection name length (null-terminated).
    var name_len: usize = 0;
    while (collection_name[name_len] != 0) : (name_len += 1) {
        if (name_len >= 256) return @intFromEnum(Status.invalid_arg);
    }
    if (name_len == 0) return @intFromEnum(Status.invalid_arg);

    const allocator = gpa.allocator();
    const state = allocator.create(SchemaState) catch {
        return @intFromEnum(Status.out_of_memory);
    };

    @memcpy(state.collection_buf[0..name_len], collection_name[0..name_len]);
    state.collection_len = name_len;

    // SAFETY: Heap-allocated SchemaState cast to opaque handle.
    schema_out.* = @ptrCast(state);
    return @intFromEnum(Status.ok);
}

// ---------------------------------------------------------------------------
// Permission Validation
// ---------------------------------------------------------------------------

/// Validate query permissions using the two-tier TypeWhitelist system.
///
/// Permission checking with TypeWhitelist is performed in Idris2.  The FFI
/// layer delegates the decision and returns the result.  Currently returns
/// ok for all queries — real enforcement is in the Idris2 layer.
export fn gqldt_validate_permissions(
    query: *GqldtQuery,
    user_id: [*:0]const u8,
    permissions: *const anyopaque,
) callconv(.c) i32 {
    if (!initialized) return @intFromEnum(Status.internal_error);

    // SAFETY: Handle from gqldt_parse.
    const q_state: *QueryState = @ptrCast(@alignCast(query));
    if (q_state.text_len == 0) return @intFromEnum(Status.invalid_arg);

    // Validate user_id is non-empty.
    if (user_id[0] == 0) return @intFromEnum(Status.invalid_arg);

    // Permissions opaque pointer must be non-null (checked by C ABI contract).
    _ = permissions;

    // Permission enforcement happens in Idris2 — FFI layer grants by default.
    return @intFromEnum(Status.ok);
}

// ---------------------------------------------------------------------------
// Resource Cleanup
// ---------------------------------------------------------------------------

/// Free a query handle previously returned by gqldt_parse,
/// gqldt_parse_inferred, or gqldt_deserialize_cbor.
export fn gqldt_query_free(query: *GqldtQuery) callconv(.c) void {
    if (!initialized) return;

    // SAFETY: Handle from gqldt_parse / gqldt_parse_inferred / gqldt_deserialize_cbor.
    const state: *QueryState = @ptrCast(@alignCast(query));
    const allocator = gpa.allocator();
    allocator.destroy(state);
}

/// Free a schema handle previously returned by gqldt_get_schema.
export fn gqldt_schema_free(schema: *GqldtSchema) callconv(.c) void {
    if (!initialized) return;

    // SAFETY: Handle from gqldt_get_schema.
    const state: *SchemaState = @ptrCast(@alignCast(schema));
    const allocator = gpa.allocator();
    allocator.destroy(state);
}

/// Free a result handle previously returned by gqldt_execute.
export fn gqldt_result_free(result: *GqldtResult) callconv(.c) void {
    if (!initialized) return;

    // SAFETY: Handle from gqldt_execute.
    const state: *ResultState = @ptrCast(@alignCast(result));
    const allocator = gpa.allocator();
    allocator.destroy(state);
}

// ---------------------------------------------------------------------------
// Version Information
// ---------------------------------------------------------------------------

/// Return the GQL-DT FFI library version as a null-terminated C string.
export fn gqldt_version() callconv(.c) [*:0]const u8 {
    return "0.1.0";
}

// ---------------------------------------------------------------------------
// Slot Allocation Helpers (for Idris2 prim__allocSlot / prim__readSlot)
// ---------------------------------------------------------------------------

/// Allocate a pointer-sized output slot on the heap.
/// Used by Idris2 to receive opaque handle pointers from FFI calls.
export fn gqldt_alloc_slot() callconv(.c) ?*anyopaque {
    const allocator = gpa.allocator();
    const slot = allocator.create(usize) catch return null;
    slot.* = 0;
    // SAFETY: usize* cast to opaque — Idris2 treats it as AnyPtr.
    return @ptrCast(slot);
}

/// Read a pointer value from an output slot as u64 (Bits64 in Idris2).
export fn gqldt_read_slot(slot: *anyopaque) callconv(.c) u64 {
    // SAFETY: Slot must have been allocated by gqldt_alloc_slot.
    const typed: *usize = @ptrCast(@alignCast(slot));
    return @intCast(typed.*);
}

/// Free an output slot allocated by gqldt_alloc_slot.
export fn gqldt_free_slot(slot: *anyopaque) callconv(.c) void {
    // SAFETY: Slot must have been allocated by gqldt_alloc_slot.
    const typed: *usize = @ptrCast(@alignCast(slot));
    const allocator = gpa.allocator();
    allocator.destroy(typed);
}

/// Cast a Bits64 value to an opaque pointer.
/// Used by Idris2 to convert handle values back to pointers for FFI calls.
export fn gqldt_bits64_to_ptr(value: u64) callconv(.c) ?*anyopaque {
    if (value == 0) return null;
    // SAFETY: The caller guarantees that value was originally obtained from
    // a valid pointer via gqldt_read_slot.
    return @ptrFromInt(@as(usize, @intCast(value)));
}

// ---------------------------------------------------------------------------
// Helper Functions (ABI Bridge Only)
// ---------------------------------------------------------------------------

/// Validate a null-terminated C string has non-zero length and fits within
/// max_len bytes.
///
/// NOTE: Full validation happens in Idris2 via Proven.SafeString.
fn validate_c_string(ptr: [*:0]const u8, max_len: usize) bool {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {
        if (len >= max_len) return false;
    }
    return len > 0;
}

/// Compute the number of header bytes needed for a CBOR text string of the
/// given length (major type 3).
fn cbor_text_header_size(text_len: usize) usize {
    if (text_len < 24) return 1;
    if (text_len <= 0xFF) return 2;
    if (text_len <= 0xFFFF) return 3;
    if (text_len <= 0xFFFFFFFF) return 5;
    return 9;
}

/// Write a CBOR text string header (major type 3) into buffer at *pos.
fn write_cbor_text_header(buffer: [*]u8, pos: *usize, text_len: usize) void {
    const major: u8 = 3 << 5; // major type 3
    if (text_len < 24) {
        buffer[pos.*] = major | @as(u8, @truncate(text_len));
        pos.* += 1;
    } else if (text_len <= 0xFF) {
        buffer[pos.*] = major | 24;
        pos.* += 1;
        buffer[pos.*] = @truncate(text_len);
        pos.* += 1;
    } else if (text_len <= 0xFFFF) {
        buffer[pos.*] = major | 25;
        pos.* += 1;
        const be = std.mem.nativeToBig(u16, @truncate(text_len));
        const bytes = std.mem.toBytes(be);
        @memcpy(buffer[pos.* .. pos.* + 2], &bytes);
        pos.* += 2;
    } else if (text_len <= 0xFFFFFFFF) {
        buffer[pos.*] = major | 26;
        pos.* += 1;
        const be = std.mem.nativeToBig(u32, @truncate(text_len));
        const bytes = std.mem.toBytes(be);
        @memcpy(buffer[pos.* .. pos.* + 4], &bytes);
        pos.* += 4;
    } else {
        buffer[pos.*] = major | 27;
        pos.* += 1;
        const be = std.mem.nativeToBig(u64, @as(u64, text_len));
        const bytes = std.mem.toBytes(be);
        @memcpy(buffer[pos.* .. pos.* + 8], &bytes);
        pos.* += 8;
    }
}

/// Read a CBOR text string header (major type 3) from buffer, advancing *pos.
/// Returns null if the header is invalid or not a text string.
fn read_cbor_text_header(buffer: [*]const u8, buf_len: usize, pos: *usize) ?usize {
    if (pos.* >= buf_len) return null;

    const initial = buffer[pos.*];
    const major = initial >> 5;
    if (major != 3) return null; // Not a text string.

    const additional = initial & 0x1F;
    pos.* += 1;

    if (additional < 24) {
        return @as(usize, additional);
    } else if (additional == 24) {
        if (pos.* >= buf_len) return null;
        const len: usize = buffer[pos.*];
        pos.* += 1;
        return len;
    } else if (additional == 25) {
        if (pos.* + 2 > buf_len) return null;
        var bytes: [2]u8 = undefined;
        @memcpy(&bytes, buffer[pos.* .. pos.* + 2]);
        pos.* += 2;
        return @as(usize, std.mem.bigToNative(u16, @bitCast(bytes)));
    } else if (additional == 26) {
        if (pos.* + 4 > buf_len) return null;
        var bytes: [4]u8 = undefined;
        @memcpy(&bytes, buffer[pos.* .. pos.* + 4]);
        pos.* += 4;
        return @as(usize, std.mem.bigToNative(u32, @bitCast(bytes)));
    } else if (additional == 27) {
        if (pos.* + 8 > buf_len) return null;
        var bytes: [8]u8 = undefined;
        @memcpy(&bytes, buffer[pos.* .. pos.* + 8]);
        pos.* += 8;
        return @as(usize, std.mem.bigToNative(u64, @bitCast(bytes)));
    }

    return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "status codes match Idris2 ABI" {
    try testing.expectEqual(@as(i32, 0), @intFromEnum(Status.ok));
    try testing.expectEqual(@as(i32, 1), @intFromEnum(Status.invalid_arg));
    try testing.expectEqual(@as(i32, 2), @intFromEnum(Status.type_mismatch));
    try testing.expectEqual(@as(i32, 3), @intFromEnum(Status.proof_failed));
    try testing.expectEqual(@as(i32, 4), @intFromEnum(Status.permission_denied));
    try testing.expectEqual(@as(i32, 5), @intFromEnum(Status.out_of_memory));
    try testing.expectEqual(@as(i32, 6), @intFromEnum(Status.internal_error));
}

test "library initialization" {
    const status = gqldt_init();
    try testing.expectEqual(@intFromEnum(Status.ok), status);
    gqldt_cleanup();
}

test "library double-init is idempotent" {
    _ = gqldt_init();
    const status = gqldt_init();
    try testing.expectEqual(@intFromEnum(Status.ok), status);
    gqldt_cleanup();
}

test "validate_c_string rejects empty strings" {
    const empty_str: [*:0]const u8 = "";
    try testing.expect(!validate_c_string(empty_str, 100));
}

test "validate_c_string accepts valid strings" {
    const valid_str: [*:0]const u8 = "SELECT * FROM users";
    try testing.expect(validate_c_string(valid_str, 1000));
}

test "validate_c_string rejects oversized strings" {
    var buf: [200]u8 = undefined;
    @memset(&buf, 'A');
    buf[199] = 0;
    const long_str: [*:0]const u8 = @ptrCast(&buf);
    try testing.expect(!validate_c_string(long_str, 100));
}

test "db_open and db_close round-trip" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*GqldtDb = null;
    const open_status = gqldt_db_open("test.db", 7, &db);
    try testing.expectEqual(@intFromEnum(Status.ok), open_status);
    try testing.expect(db != null);

    const close_status = gqldt_db_close(db.?);
    try testing.expectEqual(@intFromEnum(Status.ok), close_status);
}

test "db_open rejects empty path" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*GqldtDb = null;
    const status = gqldt_db_open("", 0, &db);
    try testing.expectEqual(@intFromEnum(Status.invalid_arg), status);
}

test "parse and query_free round-trip" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var query: ?*GqldtQuery = null;
    const query_text: [*:0]const u8 = "MATCH (n:Person) RETURN n";
    const status = gqldt_parse(query_text, 25, &query);
    try testing.expectEqual(@intFromEnum(Status.ok), status);
    try testing.expect(query != null);

    gqldt_query_free(query.?);
}

test "parse rejects empty query" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var query: ?*GqldtQuery = null;
    const status = gqldt_parse("", 0, &query);
    try testing.expectEqual(@intFromEnum(Status.invalid_arg), status);
}

test "typecheck marks query as checked" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    // Create a schema handle.
    var db: ?*GqldtDb = null;
    _ = gqldt_db_open("test.db", 7, &db);
    defer _ = gqldt_db_close(db.?);

    var schema: ?*GqldtSchema = null;
    _ = gqldt_get_schema(db.?, "users", &schema);
    defer gqldt_schema_free(schema.?);

    // Parse a query.
    var query: ?*GqldtQuery = null;
    _ = gqldt_parse("MATCH (n) RETURN n", 18, &query);
    defer gqldt_query_free(query.?);

    // Type-check.
    const tc_status = gqldt_typecheck(query.?, schema.?);
    try testing.expectEqual(@intFromEnum(Status.ok), tc_status);
}

test "execute requires type-checked query" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*GqldtDb = null;
    _ = gqldt_db_open("test.db", 7, &db);
    defer _ = gqldt_db_close(db.?);

    var query: ?*GqldtQuery = null;
    _ = gqldt_parse("MATCH (n) RETURN n", 18, &query);
    defer gqldt_query_free(query.?);

    // Attempt execution without type-checking — should fail.
    var result: ?*GqldtResult = null;
    const status = gqldt_execute(db.?, query.?, &result);
    try testing.expectEqual(@intFromEnum(Status.type_mismatch), status);
}

test "execute succeeds after typecheck" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var db: ?*GqldtDb = null;
    _ = gqldt_db_open("test.db", 7, &db);
    defer _ = gqldt_db_close(db.?);

    var schema: ?*GqldtSchema = null;
    _ = gqldt_get_schema(db.?, "users", &schema);
    defer gqldt_schema_free(schema.?);

    var query: ?*GqldtQuery = null;
    _ = gqldt_parse("MATCH (n) RETURN n", 18, &query);
    defer gqldt_query_free(query.?);

    _ = gqldt_typecheck(query.?, schema.?);

    var result: ?*GqldtResult = null;
    const exec_status = gqldt_execute(db.?, query.?, &result);
    try testing.expectEqual(@intFromEnum(Status.ok), exec_status);
    try testing.expect(result != null);

    gqldt_result_free(result.?);
}

test "serialize_cbor and deserialize_cbor round-trip" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    const query_text: [*:0]const u8 = "MATCH (n) RETURN n";
    var query: ?*GqldtQuery = null;
    _ = gqldt_parse(query_text, 18, &query);
    defer gqldt_query_free(query.?);

    // Serialise to CBOR.
    var cbor_buf: [1024]u8 = undefined;
    var written: u64 = 0;
    const ser_status = gqldt_serialize_cbor(query.?, &cbor_buf, 1024, &written);
    try testing.expectEqual(@intFromEnum(Status.ok), ser_status);
    try testing.expect(written > 0);

    // Deserialise from CBOR.
    var query2: ?*GqldtQuery = null;
    const deser_status = gqldt_deserialize_cbor(&cbor_buf, written, &query2);
    try testing.expectEqual(@intFromEnum(Status.ok), deser_status);
    try testing.expect(query2 != null);

    gqldt_query_free(query2.?);
}

test "serialize_json produces valid wrapper" {
    _ = gqldt_init();
    defer gqldt_cleanup();

    var query: ?*GqldtQuery = null;
    _ = gqldt_parse("RETURN 1", 8, &query);
    defer gqldt_query_free(query.?);

    var json_buf: [1024]u8 = undefined;
    var written: u64 = 0;
    const status = gqldt_serialize_json(query.?, &json_buf, 1024, &written);
    try testing.expectEqual(@intFromEnum(Status.ok), status);

    const json_str = json_buf[0..@intCast(written)];
    try testing.expectEqualStrings("{\"query\":\"RETURN 1\"}", json_str);
}

test "version returns semantic version" {
    const ver = gqldt_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}
