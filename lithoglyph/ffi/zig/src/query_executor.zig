// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// query_executor.zig - Simple FQL Query Executor in Zig
//
// This is a minimal implementation for M5. Later it will call Factor runtime.

const std = @import("std");
const json = std.json;

pub const QueryResult = struct {
    status: []const u8,
    data: ?std.json.Parsed(std.json.Value) = null,
    error_message: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *QueryResult) void {
        if (self.data) |*d| {
            d.deinit();
        }
    }
};

pub const SimpleExecutor = struct {
    allocator: std.mem.Allocator,
    // In-memory storage for M5 (will be replaced by Forth in M6)
    collections: std.StringHashMap(std.ArrayList(std.json.Value)),

    pub fn init(allocator: std.mem.Allocator) !SimpleExecutor {
        return SimpleExecutor{
            .allocator = allocator,
            .collections = std.StringHashMap(std.ArrayList(std.json.Value)).init(allocator),
        };
    }

    pub fn deinit(self: *SimpleExecutor) void {
        var it = self.collections.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.collections.deinit();
    }

    /// Execute a simple FQL query (hardcoded for M5)
    pub fn execute(self: *SimpleExecutor, query: []const u8) !QueryResult {
        // Simple query parsing - just check for keywords
        if (std.mem.indexOf(u8, query, "SELECT") != null) {
            return try self.executeSelect(query);
        } else if (std.mem.indexOf(u8, query, "INSERT") != null) {
            return try self.executeInsert(query);
        } else if (std.mem.indexOf(u8, query, "CREATE") != null) {
            return try self.executeCreate(query);
        } else {
            return QueryResult{
                .status = "error",
                .error_message = "Unknown query type",
                .allocator = self.allocator,
            };
        }
    }

    fn executeSelect(self: *SimpleExecutor, query: []const u8) !QueryResult {
        _ = query;

        // Hardcoded response for M5 testing
        const response =
            \\{
            \\  "status": "ok",
            \\  "collection": "evidence",
            \\  "count": 1,
            \\  "rows": [
            \\    {
            \\      "id": "1",
            \\      "title": "Test Evidence",
            \\      "score": 95
            \\    }
            \\  ]
            \\}
        ;

        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response,
            .{},
        );

        return QueryResult{
            .status = "ok",
            .data = parsed,
            .allocator = self.allocator,
        };
    }

    fn executeInsert(self: *SimpleExecutor, query: []const u8) !QueryResult {
        _ = query;

        // Hardcoded response for M5 testing
        const response =
            \\{
            \\  "status": "ok",
            \\  "document_id": "abc123",
            \\  "collection": "evidence"
            \\}
        ;

        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response,
            .{},
        );

        return QueryResult{
            .status = "ok",
            .data = parsed,
            .allocator = self.allocator,
        };
    }

    fn executeCreate(self: *SimpleExecutor, query: []const u8) !QueryResult {
        _ = query;

        // Hardcoded response for M5 testing
        const response =
            \\{
            \\  "status": "ok",
            \\  "collection": "evidence",
            \\  "schema_version": 1
            \\}
        ;

        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response,
            .{},
        );

        return QueryResult{
            .status = "ok",
            .data = parsed,
            .allocator = self.allocator,
        };
    }
};

test "simple executor - select" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try SimpleExecutor.init(allocator);
    defer executor.deinit();

    var result = try executor.execute("SELECT * FROM evidence");
    defer result.deinit();

    try testing.expectEqualStrings("ok", result.status);
    try testing.expect(result.data != null);
}

test "simple executor - insert" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try SimpleExecutor.init(allocator);
    defer executor.deinit();

    var result = try executor.execute("INSERT INTO evidence VALUES (...)");
    defer result.deinit();

    try testing.expectEqualStrings("ok", result.status);
}
