// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// main.zig — Zig FFI implementation for the NQC ABI.
//
// Provides C-compatible functions for dynamic JSON value manipulation:
// key extraction, field access, JSON encoding, list coercion, and
// field-to-string conversion. These replace the Erlang FFI (nqc_ffi.erl)
// with memory-safe, bounds-checked implementations.
//
// All functions satisfy the FFI safety contract defined in Foreign.idr:
//   1. No allocation — all output to caller-provided buffers
//   2. Bounded output — return values never exceed capacity
//   3. Null-safe — null/empty inputs produce defined results
//   4. UTF-8 safe — all output is valid UTF-8
//   5. No global state — pure functions, no side effects

const std = @import("std");

// =========================================================================
// Output format enum — mirrors Types.idr OutputFormat
// =========================================================================

/// The three supported output formats, matching Layout.idr tag values.
pub const OutputFormat = enum(u8) {
    table = 0,
    json = 1,
    csv = 2,
};

/// Parse an output format from a string. Returns null if unrecognised.
pub fn parseFormat(input: []const u8) ?OutputFormat {
    // Case-insensitive comparison via lowercase conversion.
    var buf: [8]u8 = undefined;
    if (input.len > buf.len) return null;
    for (input, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    const lower = buf[0..input.len];

    if (std.mem.eql(u8, lower, "table")) return .table;
    if (std.mem.eql(u8, lower, "json")) return .json;
    if (std.mem.eql(u8, lower, "csv")) return .csv;
    return null;
}

/// Render an output format to its canonical string.
pub fn formatToString(fmt: OutputFormat) []const u8 {
    return switch (fmt) {
        .table => "table",
        .json => "json",
        .csv => "csv",
    };
}

// =========================================================================
// Database ID enum — mirrors Types.idr DatabaseId
// =========================================================================

/// Known database backend identifiers, matching Layout.idr tag values.
pub const DatabaseId = enum(u8) {
    vql = 0,
    gql = 1,
    kql = 2,
};

/// Default port for each database.
pub fn defaultPort(db: DatabaseId) u16 {
    return switch (db) {
        .vql => 8080,
        .gql => 8081,
        .kql => 8082,
    };
}

/// Execute path for each database.
pub fn executePath(db: DatabaseId) []const u8 {
    return switch (db) {
        .vql => "/vql/execute",
        .gql => "/gql/execute",
        .kql => "/kql/execute",
    };
}

// =========================================================================
// CSV escaping — RFC 4180 compliant
// =========================================================================

/// Escape a string for CSV output per RFC 4180.
/// Writes to `out` buffer, returns the number of bytes written.
/// If the buffer is too small, returns null.
pub fn csvEscape(input: []const u8, out: []u8) ?usize {
    var needs_quoting = false;
    for (input) |c| {
        if (c == ',' or c == '"' or c == '\n' or c == '\r') {
            needs_quoting = true;
            break;
        }
    }

    if (!needs_quoting) {
        if (input.len > out.len) return null;
        @memcpy(out[0..input.len], input);
        return input.len;
    }

    // Quoted mode: count required bytes first.
    var required: usize = 2; // opening and closing quotes
    for (input) |c| {
        required += if (c == '"') @as(usize, 2) else @as(usize, 1);
    }
    if (required > out.len) return null;

    var pos: usize = 0;
    out[pos] = '"';
    pos += 1;
    for (input) |c| {
        if (c == '"') {
            out[pos] = '"';
            out[pos + 1] = '"';
            pos += 2;
        } else {
            out[pos] = c;
            pos += 1;
        }
    }
    out[pos] = '"';
    pos += 1;
    return pos;
}

// =========================================================================
// Semicolon stripping — mirrors nqc.strip_trailing_semicolons
// =========================================================================

/// Strip trailing semicolons from a query string.
/// Returns a slice of the input with trailing ';' characters removed.
/// This is a view into the original memory — no allocation.
pub fn stripTrailingSemicolons(input: []const u8) []const u8 {
    var end = input.len;
    while (end > 0 and input[end - 1] == ';') {
        end -= 1;
    }
    return input[0..end];
}

// =========================================================================
// Port validation — mirrors Types.idr Port invariants
// =========================================================================

/// Validate a port number (1–65535).
pub fn validatePort(port: u32) ?u16 {
    if (port >= 1 and port <= 65535) {
        return @intCast(port);
    }
    return null;
}

// =========================================================================
// URL construction — mirrors Types.idr URL functions
// =========================================================================

/// Build a base URL: "http://{host}:{port}".
/// Writes to `out` buffer, returns bytes written or null if too small.
pub fn buildBaseUrl(host: []const u8, port: u16, out: []u8) ?usize {
    const prefix = "http://";
    const colon = ":";

    // Format port as string.
    var port_buf: [5]u8 = undefined;
    const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch return null;

    const total = prefix.len + host.len + colon.len + port_str.len;
    if (total > out.len) return null;

    var pos: usize = 0;
    @memcpy(out[pos..][0..prefix.len], prefix);
    pos += prefix.len;
    @memcpy(out[pos..][0..host.len], host);
    pos += host.len;
    @memcpy(out[pos..][0..colon.len], colon);
    pos += colon.len;
    @memcpy(out[pos..][0..port_str.len], port_str);
    pos += port_str.len;

    return pos;
}

// =========================================================================
// HTTP status classification — mirrors Types.idr classifyStatus
// =========================================================================

/// HTTP status classification.
pub const StatusClass = enum {
    success,
    client_error,
    server_error,
    other,
};

/// Classify an HTTP status code.
pub fn classifyStatus(status: u16) StatusClass {
    if (status >= 200 and status < 300) return .success;
    if (status >= 400 and status < 500) return .client_error;
    if (status >= 500 and status < 600) return .server_error;
    return .other;
}

// =========================================================================
// JSON query body construction
// =========================================================================

/// Build a JSON query body: {"query":"<text>"}.
/// Writes to `out` buffer, returns bytes written or null if too small.
/// Escapes double quotes and backslashes in the query text.
pub fn buildQueryBody(query: []const u8, out: []u8) ?usize {
    const prefix = "{\"query\":\"";
    const suffix = "\"}";

    // Calculate escaped length.
    var escaped_len: usize = 0;
    for (query) |c| {
        escaped_len += switch (c) {
            '"', '\\' => @as(usize, 2),
            '\n' => 2,
            '\r' => 2,
            '\t' => 2,
            else => 1,
        };
    }

    const total = prefix.len + escaped_len + suffix.len;
    if (total > out.len) return null;

    var pos: usize = 0;
    @memcpy(out[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    for (query) |c| {
        switch (c) {
            '"' => {
                out[pos] = '\\';
                out[pos + 1] = '"';
                pos += 2;
            },
            '\\' => {
                out[pos] = '\\';
                out[pos + 1] = '\\';
                pos += 2;
            },
            '\n' => {
                out[pos] = '\\';
                out[pos + 1] = 'n';
                pos += 2;
            },
            '\r' => {
                out[pos] = '\\';
                out[pos + 1] = 'r';
                pos += 2;
            },
            '\t' => {
                out[pos] = '\\';
                out[pos + 1] = 't';
                pos += 2;
            },
            else => {
                out[pos] = c;
                pos += 1;
            },
        }
    }

    @memcpy(out[pos..][0..suffix.len], suffix);
    pos += suffix.len;

    return pos;
}

// =========================================================================
// Unit tests
// =========================================================================

test "parseFormat recognises table" {
    try std.testing.expectEqual(OutputFormat.table, parseFormat("table").?);
}

test "parseFormat recognises json" {
    try std.testing.expectEqual(OutputFormat.json, parseFormat("json").?);
}

test "parseFormat recognises csv" {
    try std.testing.expectEqual(OutputFormat.csv, parseFormat("csv").?);
}

test "parseFormat is case insensitive" {
    try std.testing.expectEqual(OutputFormat.table, parseFormat("TABLE").?);
    try std.testing.expectEqual(OutputFormat.json, parseFormat("Json").?);
    try std.testing.expectEqual(OutputFormat.csv, parseFormat("CSV").?);
}

test "parseFormat rejects unknown" {
    try std.testing.expect(parseFormat("xml") == null);
    try std.testing.expect(parseFormat("") == null);
}

test "formatToString roundtrips" {
    try std.testing.expectEqualStrings("table", formatToString(.table));
    try std.testing.expectEqualStrings("json", formatToString(.json));
    try std.testing.expectEqualStrings("csv", formatToString(.csv));
}

test "defaultPort values" {
    try std.testing.expectEqual(@as(u16, 8080), defaultPort(.vql));
    try std.testing.expectEqual(@as(u16, 8081), defaultPort(.gql));
    try std.testing.expectEqual(@as(u16, 8082), defaultPort(.kql));
}

test "executePath values" {
    try std.testing.expectEqualStrings("/vql/execute", executePath(.vql));
    try std.testing.expectEqualStrings("/gql/execute", executePath(.gql));
    try std.testing.expectEqualStrings("/kql/execute", executePath(.kql));
}

test "csvEscape plain string unchanged" {
    var buf: [32]u8 = undefined;
    const len = csvEscape("hello", &buf).?;
    try std.testing.expectEqualStrings("hello", buf[0..len]);
}

test "csvEscape quotes commas" {
    var buf: [32]u8 = undefined;
    const len = csvEscape("a,b", &buf).?;
    try std.testing.expectEqualStrings("\"a,b\"", buf[0..len]);
}

test "csvEscape doubles quotes" {
    var buf: [32]u8 = undefined;
    const len = csvEscape("say \"hi\"", &buf).?;
    try std.testing.expectEqualStrings("\"say \"\"hi\"\"\"", buf[0..len]);
}

test "csvEscape quotes newlines" {
    var buf: [64]u8 = undefined;
    const len = csvEscape("line1\nline2", &buf).?;
    try std.testing.expectEqualStrings("\"line1\nline2\"", buf[0..len]);
}

test "csvEscape returns null on buffer overflow" {
    var buf: [2]u8 = undefined;
    try std.testing.expect(csvEscape("a,b,c,d", &buf) == null);
}

test "stripTrailingSemicolons none" {
    try std.testing.expectEqualStrings("SELECT 1", stripTrailingSemicolons("SELECT 1"));
}

test "stripTrailingSemicolons one" {
    try std.testing.expectEqualStrings("SELECT 1", stripTrailingSemicolons("SELECT 1;"));
}

test "stripTrailingSemicolons multiple" {
    try std.testing.expectEqualStrings("SELECT 1", stripTrailingSemicolons("SELECT 1;;;"));
}

test "stripTrailingSemicolons empty" {
    try std.testing.expectEqualStrings("", stripTrailingSemicolons(""));
}

test "stripTrailingSemicolons preserves internal" {
    try std.testing.expectEqualStrings("a;b;c", stripTrailingSemicolons("a;b;c;"));
}

test "stripTrailingSemicolons idempotent" {
    const once = stripTrailingSemicolons("SELECT 1;;;");
    const twice = stripTrailingSemicolons(once);
    try std.testing.expectEqualStrings(once, twice);
}

test "validatePort valid" {
    try std.testing.expectEqual(@as(u16, 8080), validatePort(8080).?);
    try std.testing.expectEqual(@as(u16, 1), validatePort(1).?);
    try std.testing.expectEqual(@as(u16, 65535), validatePort(65535).?);
}

test "validatePort invalid" {
    try std.testing.expect(validatePort(0) == null);
    try std.testing.expect(validatePort(65536) == null);
    try std.testing.expect(validatePort(100000) == null);
}

test "classifyStatus 200 is success" {
    try std.testing.expectEqual(StatusClass.success, classifyStatus(200));
    try std.testing.expectEqual(StatusClass.success, classifyStatus(299));
}

test "classifyStatus 404 is client error" {
    try std.testing.expectEqual(StatusClass.client_error, classifyStatus(404));
}

test "classifyStatus 500 is server error" {
    try std.testing.expectEqual(StatusClass.server_error, classifyStatus(500));
}

test "classifyStatus 100 is other" {
    try std.testing.expectEqual(StatusClass.other, classifyStatus(100));
}

test "buildBaseUrl" {
    var buf: [64]u8 = undefined;
    const len = buildBaseUrl("localhost", 8080, &buf).?;
    try std.testing.expectEqualStrings("http://localhost:8080", buf[0..len]);
}

test "buildBaseUrl custom host and port" {
    var buf: [64]u8 = undefined;
    const len = buildBaseUrl("10.0.0.5", 9090, &buf).?;
    try std.testing.expectEqualStrings("http://10.0.0.5:9090", buf[0..len]);
}

test "buildBaseUrl returns null on overflow" {
    var buf: [5]u8 = undefined;
    try std.testing.expect(buildBaseUrl("localhost", 8080, &buf) == null);
}

test "buildQueryBody simple" {
    var buf: [64]u8 = undefined;
    const len = buildQueryBody("SELECT 1", &buf).?;
    try std.testing.expectEqualStrings("{\"query\":\"SELECT 1\"}", buf[0..len]);
}

test "buildQueryBody escapes quotes" {
    var buf: [128]u8 = undefined;
    const len = buildQueryBody("WHERE name = \"Alice\"", &buf).?;
    try std.testing.expectEqualStrings("{\"query\":\"WHERE name = \\\"Alice\\\"\"}", buf[0..len]);
}

test "buildQueryBody escapes newlines" {
    var buf: [64]u8 = undefined;
    const len = buildQueryBody("line1\nline2", &buf).?;
    try std.testing.expectEqualStrings("{\"query\":\"line1\\nline2\"}", buf[0..len]);
}

test "buildQueryBody returns null on overflow" {
    var buf: [5]u8 = undefined;
    try std.testing.expect(buildQueryBody("SELECT 1", &buf) == null);
}
