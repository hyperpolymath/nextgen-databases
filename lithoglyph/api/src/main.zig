// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - Multi-Protocol (REST, gRPC, GraphQL)

const std = @import("std");
const builtin = @import("builtin");

const config = @import("config.zig");
const router = @import("router.zig");
const rest = @import("rest.zig");
const grpc = @import("grpc.zig");
const graphql = @import("graphql.zig");
const metrics = @import("metrics.zig");
const auth = @import("auth.zig");
const bridge_client = @import("bridge_client.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

const log = std.log.scoped(.lithoglyph_server);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse configuration
    const cfg = try config.load(allocator);
    defer cfg.deinit();

    log.info("Lithoglyph API Server v{s}", .{cfg.version});
    log.info("Listening on {s}:{d}", .{ cfg.host, cfg.port });

    // Initialize metrics
    try metrics.init(allocator);
    defer metrics.deinit();

    // Initialize authentication
    try auth.init(allocator, cfg);
    defer auth.deinit();

    // Initialize Form.Bridge connection
    bridge_client.init(allocator, cfg) catch |err| {
        log.warn("Failed to initialize bridge client: {} - running in degraded mode", .{err});
    };
    defer bridge_client.deinit();

    // Create TCP listener (Zig 0.15.2 API)
    const address = try std.net.Address.parseIp(cfg.host, cfg.port);
    var tcp_server = try address.listen(.{
        .reuse_address = true,
    });
    defer tcp_server.deinit();

    log.info("Server started successfully", .{});
    log.info("  REST API:    http://{s}:{d}/v1/", .{ cfg.host, cfg.port });
    log.info("  gRPC:        http://{s}:{d}/grpc/", .{ cfg.host, cfg.port });
    log.info("  GraphQL:     http://{s}:{d}/graphql", .{ cfg.host, cfg.port });
    log.info("  Health:      http://{s}:{d}/v1/health", .{ cfg.host, cfg.port });
    log.info("  Metrics:     http://{s}:{d}/v1/metrics", .{ cfg.host, cfg.port });

    // Accept connections
    while (true) {
        const conn = tcp_server.accept() catch |err| {
            log.err("Accept error: {}", .{err});
            continue;
        };

        // Spawn handler thread
        _ = try std.Thread.spawn(.{}, handleConnection, .{ allocator, conn, cfg });
    }
}

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection, cfg: *const config.Config) void {
    defer conn.stream.close();

    // Create HTTP server from connection stream (Zig 0.15.2 API)
    var recv_buffer: [8192]u8 = undefined;
    var send_buffer: [8192]u8 = undefined;
    var conn_reader = conn.stream.reader(&recv_buffer);
    var conn_writer = conn.stream.writer(&send_buffer);
    var http = std.http.Server.init(conn_reader.interface(), &conn_writer.interface);

    while (http.reader.state == .ready) {
        var request = http.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                log.err("Receive error: {s}", .{@errorName(err)});
                return;
            },
        };

        handleRequest(allocator, &request, cfg) catch |err| {
            log.err("Handle error: {s}", .{@errorName(err)});
            return;
        };
    }
}

fn handleRequest(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    cfg: *const config.Config,
) !void {
    const start_time = std.time.nanoTimestamp();
    defer {
        const elapsed = std.time.nanoTimestamp() - start_time;
        metrics.recordLatency(elapsed);
    }

    metrics.incrementRequests();

    const path = request.head.target;

    // Route to appropriate handler
    if (std.mem.startsWith(u8, path, "/v1/")) {
        // REST API
        try rest.handleRequest(allocator, request, cfg);
    } else if (std.mem.startsWith(u8, path, "/grpc/")) {
        // gRPC (HTTP/2 with protobuf)
        try grpc.handleRequest(allocator, request, cfg);
    } else if (std.mem.startsWith(u8, path, "/graphql")) {
        // GraphQL
        try graphql.handleRequest(allocator, request, cfg);
    } else {
        // 404
        try sendNotFound(request);
    }
}

fn sendNotFound(request: *std.http.Server.Request) !void {
    const body =
        \\{"error":"not_found","message":"Resource not found"}
    ;

    request.respond(body, .{
        .status = .not_found,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}

test "server initialization" {
    // Basic test to ensure compilation
    const allocator = std.testing.allocator;
    _ = allocator;
}
