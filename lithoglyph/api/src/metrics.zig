// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - Prometheus Metrics

const std = @import("std");

var allocator: std.mem.Allocator = undefined;
var start_time: i64 = 0;

// Counters
var requests_total: u64 = 0;
var requests_by_status: [5]u64 = .{ 0, 0, 0, 0, 0 }; // 2xx, 3xx, 4xx, 5xx, other
var requests_by_protocol: [3]u64 = .{ 0, 0, 0 }; // REST, gRPC, GraphQL

// Histograms (simplified - just buckets)
var latency_buckets: [10]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
const latency_bounds = [_]i64{ 1_000_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000, 100_000_000, 250_000_000, 500_000_000, 1_000_000_000, std.math.maxInt(i64) }; // ns

// Gauges
var active_connections: u64 = 0;
var active_migrations: u64 = 0;

pub fn init(alloc: std.mem.Allocator) !void {
    allocator = alloc;
    start_time = std.time.timestamp();
}

pub fn deinit() void {
    // Nothing to clean up
}

pub fn incrementRequests() void {
    _ = @atomicRmw(u64, &requests_total, .Add, 1, .seq_cst);
}

pub fn recordStatus(status: std.http.Status) void {
    const code = @intFromEnum(status);
    const bucket: usize = if (code >= 200 and code < 300)
        0
    else if (code >= 300 and code < 400)
        1
    else if (code >= 400 and code < 500)
        2
    else if (code >= 500 and code < 600)
        3
    else
        4;

    _ = @atomicRmw(u64, &requests_by_status[bucket], .Add, 1, .seq_cst);
}

pub fn recordProtocol(protocol: Protocol) void {
    _ = @atomicRmw(u64, &requests_by_protocol[@intFromEnum(protocol)], .Add, 1, .seq_cst);
}

pub const Protocol = enum(u2) {
    rest = 0,
    grpc = 1,
    graphql = 2,
};

pub fn recordLatency(latency_ns: i64) void {
    for (latency_bounds, 0..) |bound, i| {
        if (latency_ns <= bound) {
            _ = @atomicRmw(u64, &latency_buckets[i], .Add, 1, .seq_cst);
            break;
        }
    }
}

pub fn incrementConnections() void {
    _ = @atomicRmw(u64, &active_connections, .Add, 1, .seq_cst);
}

pub fn decrementConnections() void {
    _ = @atomicRmw(u64, &active_connections, .Sub, 1, .seq_cst);
}

pub fn setActiveMigrations(count: u64) void {
    @atomicStore(u64, &active_migrations, count, .seq_cst);
}

pub fn getPrometheus(alloc: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(alloc);
    const writer = buffer.writer();

    const uptime = std.time.timestamp() - start_time;

    // Write metrics in Prometheus format
    try writer.print(
        \\# HELP lithoglyph_requests_total Total number of requests
        \\# TYPE lithoglyph_requests_total counter
        \\lithoglyph_requests_total {d}
        \\
        \\# HELP lithoglyph_requests_by_status Requests by HTTP status code range
        \\# TYPE lithoglyph_requests_by_status counter
        \\lithoglyph_requests_by_status{{status="2xx"}} {d}
        \\lithoglyph_requests_by_status{{status="3xx"}} {d}
        \\lithoglyph_requests_by_status{{status="4xx"}} {d}
        \\lithoglyph_requests_by_status{{status="5xx"}} {d}
        \\
        \\# HELP lithoglyph_requests_by_protocol Requests by protocol
        \\# TYPE lithoglyph_requests_by_protocol counter
        \\lithoglyph_requests_by_protocol{{protocol="rest"}} {d}
        \\lithoglyph_requests_by_protocol{{protocol="grpc"}} {d}
        \\lithoglyph_requests_by_protocol{{protocol="graphql"}} {d}
        \\
        \\# HELP lithoglyph_request_duration_seconds Request latency histogram
        \\# TYPE lithoglyph_request_duration_seconds histogram
        \\lithoglyph_request_duration_seconds_bucket{{le="0.001"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="0.005"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="0.01"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="0.025"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="0.05"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="0.1"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="0.25"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="0.5"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="1.0"}} {d}
        \\lithoglyph_request_duration_seconds_bucket{{le="+Inf"}} {d}
        \\
        \\# HELP lithoglyph_active_connections Current number of active connections
        \\# TYPE lithoglyph_active_connections gauge
        \\lithoglyph_active_connections {d}
        \\
        \\# HELP lithoglyph_active_migrations Current number of active migrations
        \\# TYPE lithoglyph_active_migrations gauge
        \\lithoglyph_active_migrations {d}
        \\
        \\# HELP lithoglyph_uptime_seconds Server uptime in seconds
        \\# TYPE lithoglyph_uptime_seconds gauge
        \\lithoglyph_uptime_seconds {d}
        \\
        \\# HELP lithoglyph_info Server version information
        \\# TYPE lithoglyph_info gauge
        \\lithoglyph_info{{version="0.0.4"}} 1
        \\
    , .{
        requests_total,
        requests_by_status[0],
        requests_by_status[1],
        requests_by_status[2],
        requests_by_status[3],
        requests_by_protocol[0],
        requests_by_protocol[1],
        requests_by_protocol[2],
        latency_buckets[0],
        latency_buckets[0] + latency_buckets[1],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2] + latency_buckets[3],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2] + latency_buckets[3] + latency_buckets[4],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2] + latency_buckets[3] + latency_buckets[4] + latency_buckets[5],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2] + latency_buckets[3] + latency_buckets[4] + latency_buckets[5] + latency_buckets[6],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2] + latency_buckets[3] + latency_buckets[4] + latency_buckets[5] + latency_buckets[6] + latency_buckets[7],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2] + latency_buckets[3] + latency_buckets[4] + latency_buckets[5] + latency_buckets[6] + latency_buckets[7] + latency_buckets[8],
        latency_buckets[0] + latency_buckets[1] + latency_buckets[2] + latency_buckets[3] + latency_buckets[4] + latency_buckets[5] + latency_buckets[6] + latency_buckets[7] + latency_buckets[8] + latency_buckets[9],
        active_connections,
        active_migrations,
        uptime,
    });

    return buffer.toOwnedSlice();
}

test "metrics increment" {
    try init(std.testing.allocator);
    defer deinit();

    incrementRequests();
    incrementRequests();

    try std.testing.expectEqual(@as(u64, 2), requests_total);
}
