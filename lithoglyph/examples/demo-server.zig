// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph Phase 4 Demo - Minimal HTTP server demonstrating complete stack
//
// Architecture demonstrated:
// HTTP Request → Zig Server → Bridge FFI → BlockStorage → Persistent .lgh files

const std = @import("std");

// FFI types matching our Phase 3 bindings
const LgBlob = extern struct {
    ptr: ?[*]const u8,
    len: usize,

    fn empty() LgBlob {
        return .{ .ptr = null, .len = 0 };
    }

    fn toSlice(self: LgBlob) ?[]const u8 {
        if (self.ptr) |p| return p[0..self.len];
        return null;
    }
};

const LgStatus = enum(c_int) {
    ok = 0,
    err_internal = 1,
    err_not_found = 2,
    err_invalid_argument = 3,
    err_out_of_memory = 4,
    err_not_implemented = 5,
    err_txn_not_active = 6,
    err_txn_already_committed = 7,
};

const LgResult = extern struct {
    value: LgBlob,
    err: LgBlob,
    status: LgStatus,
};

// External FFI functions (from libbridge.so)
extern fn fdb_version() c_int;
extern fn fdb_db_open(
    path: [*]const u8,
    path_len: usize,
    opts: ?[*]const u8,
    opts_len: usize,
    out_db: *?*anyopaque,
    out_err: *LgBlob,
) LgStatus;
extern fn fdb_db_close(db: ?*anyopaque) void;
extern fn fdb_txn_begin(
    db: ?*anyopaque,
    read_only: bool,
    out_txn: *?*anyopaque,
    out_err: *LgBlob,
) LgStatus;
extern fn fdb_txn_commit(txn: ?*anyopaque, out_err: *LgBlob) LgStatus;
extern fn fdb_apply(txn: ?*anyopaque, op: [*]const u8, op_len: usize) LgResult;
extern fn fdb_introspect_schema(
    db: ?*anyopaque,
    out_schema: *LgBlob,
    out_err: *LgBlob,
) LgStatus;
extern fn fdb_blob_free(blob: *LgBlob) void;

// Global state
var db: ?*anyopaque = null;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

pub fn main() !void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("===========================================\n", .{});
    std.debug.print("Lithoglyph Phase 4 Demo Server\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("Bridge version: {d}\n", .{fdb_version()});

    // Open database
    const db_path = "demo.lgh";
    var err_blob = LgBlob.empty();

    const status = fdb_db_open(
        db_path.ptr,
        db_path.len,
        null,
        0,
        &db,
        &err_blob,
    );

    if (status != .ok) {
        if (err_blob.toSlice()) |err| {
            std.debug.print("Failed to open database: {s}\n", .{err});
        }
        return error.DatabaseOpenFailed;
    }

    std.debug.print("Database opened: {s}\n", .{db_path});
    std.debug.print("DB handle: {*}\n\n", .{db});

    defer {
        if (db) |d| {
            fdb_db_close(d);
            std.debug.print("\nDatabase closed\n", .{});
        }
    }

    // Simple HTTP server
    const address = try std.net.Address.parseIp("127.0.0.1", 8080);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    std.debug.print("Server listening on http://127.0.0.1:8080\n", .{});
    std.debug.print("\nEndpoints:\n", .{});
    std.debug.print("  GET  /health    - Health check\n", .{});
    std.debug.print("  GET  /version   - Bridge version\n", .{});
    std.debug.print("  POST /insert    - Insert document\n", .{});
    std.debug.print("  GET  /schema    - Introspect schema\n", .{});
    std.debug.print("\n===========================================\n\n", .{});

    // Accept connections
    while (true) {
        const conn = try listener.accept();
        _ = try std.Thread.spawn(.{}, handleConnection, .{ allocator, conn });
    }
}

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection) void {
    defer conn.stream.close();

    var buf: [4096]u8 = undefined;
    const bytes_read = conn.stream.read(&buf) catch return;
    if (bytes_read == 0) return;

    const request = buf[0..bytes_read];

    // Parse HTTP request line
    var lines = std.mem.splitScalar(u8, request, '\n');
    const first_line = lines.next() orelse return;

    var parts = std.mem.splitScalar(u8, first_line, ' ');
    const method = parts.next() orelse return;
    const path = parts.next() orelse return;

    std.debug.print("[{s}] {s}\n", .{ method, path });

    // Route requests
    if (std.mem.eql(u8, path, "/health")) {
        handleHealth(conn.stream) catch {};
    } else if (std.mem.eql(u8, path, "/version")) {
        handleVersion(conn.stream) catch {};
    } else if (std.mem.eql(u8, path, "/insert")) {
        handleInsert(allocator, conn.stream, request) catch {};
    } else if (std.mem.eql(u8, path, "/schema")) {
        handleSchema(conn.stream) catch {};
    } else {
        send404(conn.stream) catch {};
    }
}

fn handleHealth(stream: std.net.Stream) !void {
    const response =
        \\HTTP/1.1 200 OK
        \\Content-Type: application/json
        \\Connection: close
        \\
        \\{"status":"healthy","database":"open","bridge_version":100}
    ;
    _ = try stream.writeAll(response);
}

fn handleVersion(stream: std.net.Stream) !void {
    var buf: [256]u8 = undefined;
    const version = fdb_version();
    const json = try std.fmt.bufPrint(&buf,
        \\HTTP/1.1 200 OK
        \\Content-Type: application/json
        \\Connection: close
        \\
        \\{{"version":{d}}}
    , .{version});
    _ = try stream.writeAll(json);
}

fn handleInsert(allocator: std.mem.Allocator, stream: std.net.Stream, request: []const u8) !void {
    _ = allocator;

    // Begin transaction
    var txn: ?*anyopaque = null;
    var err_blob = LgBlob.empty();

    var status = fdb_txn_begin(db, false, &txn, &err_blob);
    if (status != .ok) {
        const error_response =
            \\HTTP/1.1 500 Internal Server Error
            \\Content-Type: application/json
            \\Connection: close
            \\
            \\{"error":"transaction_failed"}
        ;
        _ = try stream.writeAll(error_response);
        return;
    }

    // Extract body (simplified - just use placeholder)
    _ = request;
    const op = "{\"op\":\"insert\",\"collection\":\"demo\",\"doc\":{\"name\":\"test\"}}";

    // Apply operation
    const result = fdb_apply(txn, op.ptr, op.len);

    if (result.status != .ok) {
        const error_response =
            \\HTTP/1.1 500 Internal Server Error
            \\Content-Type: application/json
            \\Connection: close
            \\
            \\{"error":"apply_failed"}
        ;
        _ = try stream.writeAll(error_response);
        return;
    }

    // Commit
    status = fdb_txn_commit(txn, &err_blob);
    if (status != .ok) {
        const error_response =
            \\HTTP/1.1 500 Internal Server Error
            \\Content-Type: application/json
            \\Connection: close
            \\
            \\{"error":"commit_failed"}
        ;
        _ = try stream.writeAll(error_response);
        return;
    }

    const success_response =
        \\HTTP/1.1 200 OK
        \\Content-Type: application/json
        \\Connection: close
        \\
        \\{"status":"ok","inserted":true}
    ;
    _ = try stream.writeAll(success_response);
}

fn handleSchema(stream: std.net.Stream) !void {
    var schema_blob = LgBlob.empty();
    var err_blob = LgBlob.empty();

    const status = fdb_introspect_schema(db, &schema_blob, &err_blob);

    if (status != .ok) {
        const error_response =
            \\HTTP/1.1 500 Internal Server Error
            \\Content-Type: application/json
            \\Connection: close
            \\
            \\{"error":"introspection_failed"}
        ;
        _ = try stream.writeAll(error_response);
        return;
    }

    defer fdb_blob_free(&schema_blob);

    const schema_data = schema_blob.toSlice() orelse "{}";

    const response_header =
        \\HTTP/1.1 200 OK
        \\Content-Type: application/json
        \\Connection: close
        \\
        \\
    ;
    _ = try stream.writeAll(response_header);
    _ = try stream.writeAll(schema_data);
}

fn send404(stream: std.net.Stream) !void {
    const response =
        \\HTTP/1.1 404 Not Found
        \\Content-Type: application/json
        \\Connection: close
        \\
        \\{"error":"not_found"}
    ;
    _ = try stream.writeAll(response);
}
