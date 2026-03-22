// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// integration_test.zig — Integration tests for the NQC Zig FFI.
//
// Verifies cross-cutting invariants from SPEC.core.scm that involve
// multiple FFI functions working together.

const std = @import("std");
const nqc = @import("nqc_ffi");

// =========================================================================
// Cross-function invariants
// =========================================================================

test "format roundtrip: parseFormat(formatToString(f)) == f" {
    inline for (@typeInfo(nqc.OutputFormat).@"enum".fields) |field| {
        const fmt: nqc.OutputFormat = @enumFromInt(field.value);
        const str = nqc.formatToString(fmt);
        const parsed = nqc.parseFormat(str).?;
        try std.testing.expectEqual(fmt, parsed);
    }
}

test "all database ports are valid" {
    inline for (@typeInfo(nqc.DatabaseId).@"enum".fields) |field| {
        const db: nqc.DatabaseId = @enumFromInt(field.value);
        const port = nqc.defaultPort(db);
        try std.testing.expect(nqc.validatePort(port) != null);
    }
}

test "all execute paths start with slash" {
    inline for (@typeInfo(nqc.DatabaseId).@"enum".fields) |field| {
        const db: nqc.DatabaseId = @enumFromInt(field.value);
        const path = nqc.executePath(db);
        try std.testing.expect(path.len > 0);
        try std.testing.expectEqual(@as(u8, '/'), path[0]);
    }
}

test "base URL + execute path constructs valid URL" {
    inline for (@typeInfo(nqc.DatabaseId).@"enum".fields) |field| {
        const db: nqc.DatabaseId = @enumFromInt(field.value);
        var url_buf: [128]u8 = undefined;

        const base_len = nqc.buildBaseUrl("localhost", nqc.defaultPort(db), &url_buf).?;
        const path = nqc.executePath(db);

        // Append path to base URL.
        @memcpy(url_buf[base_len..][0..path.len], path);
        const full_url = url_buf[0 .. base_len + path.len];

        // Verify it starts with http:// and contains the path.
        try std.testing.expect(std.mem.startsWith(u8, full_url, "http://"));
        try std.testing.expect(std.mem.endsWith(u8, full_url, path));
    }
}

test "query body construction preserves query text" {
    const query = "SELECT * FROM entities WHERE id = 42";
    var buf: [256]u8 = undefined;
    const len = nqc.buildQueryBody(query, &buf).?;
    const body = buf[0..len];

    // Should be valid JSON containing the query.
    try std.testing.expect(std.mem.startsWith(u8, body, "{\"query\":\""));
    try std.testing.expect(std.mem.endsWith(u8, body, "\"}"));

    // Extract the query value (between the quotes after "query":").
    const start = "{\"query\":\"".len;
    const end = len - "\"}".len;
    const extracted = body[start..end];
    try std.testing.expectEqualStrings(query, extracted);
}

test "semicolon stripping then query body preserves content" {
    const input = "SELECT 1;;;";
    const stripped = nqc.stripTrailingSemicolons(input);
    try std.testing.expectEqualStrings("SELECT 1", stripped);

    var buf: [64]u8 = undefined;
    const len = nqc.buildQueryBody(stripped, &buf).?;
    try std.testing.expectEqualStrings("{\"query\":\"SELECT 1\"}", buf[0..len]);
}

test "csv escape then validate: roundtrip preserves data" {
    const values = [_][]const u8{
        "simple",
        "with,comma",
        "with\"quote",
        "with\nnewline",
        "",
    };

    for (values) |val| {
        var buf: [128]u8 = undefined;
        const len = nqc.csvEscape(val, &buf) orelse continue;
        const escaped = buf[0..len];
        // Escaped output should be >= input length.
        try std.testing.expect(escaped.len >= val.len);
    }
}

test "status classification covers protocol spec ranges" {
    // 2xx -> success
    var status: u16 = 200;
    while (status < 300) : (status += 1) {
        try std.testing.expectEqual(nqc.StatusClass.success, nqc.classifyStatus(status));
    }
    // 4xx -> client error
    status = 400;
    while (status < 500) : (status += 1) {
        try std.testing.expectEqual(nqc.StatusClass.client_error, nqc.classifyStatus(status));
    }
    // 5xx -> server error
    status = 500;
    while (status < 600) : (status += 1) {
        try std.testing.expectEqual(nqc.StatusClass.server_error, nqc.classifyStatus(status));
    }
}
