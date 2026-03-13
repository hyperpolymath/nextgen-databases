// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - WebSocket Handler
//
// WebSocket support for GraphQL subscriptions and real-time journal streaming

const std = @import("std");
const config = @import("config.zig");
const bridge = @import("bridge_client.zig");

const log = std.log.scoped(.websocket);

// WebSocket opcodes
const Opcode = enum(u4) {
    continuation = 0,
    text = 1,
    binary = 2,
    close = 8,
    ping = 9,
    pong = 10,
};

// Active subscriptions
pub const Subscription = struct {
    id: []const u8,
    subscription_type: SubscriptionType,
    last_seq: u64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Subscription) void {
        self.allocator.free(self.id);
    }
};

pub const SubscriptionType = enum {
    journal_stream,
    collection_changes,
    migration_progress,
};

// WebSocket connection state
pub const Connection = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.StringHashMap(Subscription),
    is_open: bool,

    pub fn init(allocator: std.mem.Allocator) Connection {
        return .{
            .allocator = allocator,
            .subscriptions = std.StringHashMap(Subscription).init(allocator),
            .is_open = true,
        };
    }

    pub fn deinit(self: *Connection) void {
        var iter = self.subscriptions.valueIterator();
        while (iter.next()) |sub| {
            sub.deinit();
        }
        self.subscriptions.deinit();
    }

    pub fn addSubscription(self: *Connection, id: []const u8, sub_type: SubscriptionType) !void {
        const id_copy = try self.allocator.dupe(u8, id);
        try self.subscriptions.put(id_copy, .{
            .id = id_copy,
            .subscription_type = sub_type,
            .last_seq = 0,
            .allocator = self.allocator,
        });
    }

    pub fn removeSubscription(self: *Connection, id: []const u8) void {
        if (self.subscriptions.fetchRemove(id)) |entry| {
            var sub = entry.value;
            sub.deinit();
        }
    }
};

/// Check if a request is a WebSocket upgrade request
pub fn isUpgradeRequest(request: *std.http.Server.Request) bool {
    const upgrade = getHeader(request, "upgrade") orelse return false;
    return std.ascii.eqlIgnoreCase(upgrade, "websocket");
}

/// Handle WebSocket upgrade and connection
pub fn handleUpgrade(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    cfg: *const config.Config,
) !void {
    _ = cfg;

    // Validate WebSocket upgrade request
    const key = getHeader(request, "sec-websocket-key") orelse {
        try sendBadRequest(request, "Missing Sec-WebSocket-Key header");
        return;
    };

    const version = getHeader(request, "sec-websocket-version") orelse "13";
    if (!std.mem.eql(u8, version, "13")) {
        try sendBadRequest(request, "Unsupported WebSocket version");
        return;
    }

    // Calculate accept key
    const accept_key = try computeAcceptKey(allocator, key);
    defer allocator.free(accept_key);

    // Send upgrade response
    request.respond("", .{
        .status = .switching_protocols,
        .extra_headers = &.{
            .{ .name = "upgrade", .value = "websocket" },
            .{ .name = "connection", .value = "Upgrade" },
            .{ .name = "sec-websocket-accept", .value = accept_key },
            .{ .name = "sec-websocket-protocol", .value = "graphql-ws" },
        },
    }) catch {};

    log.info("WebSocket connection upgraded", .{});

    // Note: After upgrade, the connection should be handled differently
    // The HTTP server needs to hand off the raw socket to WebSocket handling
    // This is a simplified implementation - full WebSocket handling would
    // require access to the underlying socket for bidirectional communication
}

/// Compute WebSocket accept key from client key
fn computeAcceptKey(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    // Concatenate key + magic
    var combined = try allocator.alloc(u8, key.len + magic.len);
    defer allocator.free(combined);
    @memcpy(combined[0..key.len], key);
    @memcpy(combined[key.len..], magic);

    // SHA-1 hash
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(combined, &hash, .{});

    // Base64 encode
    const encoded_len = std.base64.standard.Encoder.calcSize(20);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, &hash);

    return encoded;
}

/// Encode a WebSocket frame
pub fn encodeFrame(allocator: std.mem.Allocator, opcode: Opcode, payload: []const u8) ![]const u8 {
    // Calculate frame size
    const header_size: usize = if (payload.len < 126)
        2
    else if (payload.len < 65536)
        4
    else
        10;

    var frame = try allocator.alloc(u8, header_size + payload.len);

    // First byte: FIN bit (1) + opcode
    frame[0] = 0x80 | @intFromEnum(opcode);

    // Second byte: mask bit (0 for server) + payload length
    if (payload.len < 126) {
        frame[1] = @intCast(payload.len);
    } else if (payload.len < 65536) {
        frame[1] = 126;
        std.mem.writeInt(u16, frame[2..4], @intCast(payload.len), .big);
    } else {
        frame[1] = 127;
        std.mem.writeInt(u64, frame[2..10], payload.len, .big);
    }

    // Payload
    @memcpy(frame[header_size..], payload);

    return frame;
}

/// Create a GraphQL subscription message (graphql-ws protocol)
pub fn createSubscriptionMessage(
    allocator: std.mem.Allocator,
    msg_type: []const u8,
    id: ?[]const u8,
    payload: ?[]const u8,
) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();
    const writer = buffer.writer();

    try writer.writeAll("{\"type\":\"");
    try writer.writeAll(msg_type);
    try writer.writeAll("\"");

    if (id) |i| {
        try writer.writeAll(",\"id\":\"");
        try writer.writeAll(i);
        try writer.writeAll("\"");
    }

    if (payload) |p| {
        try writer.writeAll(",\"payload\":");
        try writer.writeAll(p);
    }

    try writer.writeAll("}");

    return try buffer.toOwnedSlice();
}

/// Parse a GraphQL subscription message
pub const SubscriptionMessage = struct {
    msg_type: []const u8,
    id: ?[]const u8,
    payload: ?[]const u8,
};

pub fn parseSubscriptionMessage(allocator: std.mem.Allocator, data: []const u8) !SubscriptionMessage {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch {
        return error.InvalidJson;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    const msg_type = if (root.get("type")) |t| switch (t) {
        .string => |s| s,
        else => return error.InvalidMessageType,
    } else return error.MissingType;

    const id = if (root.get("id")) |i| switch (i) {
        .string => |s| s,
        else => null,
    } else null;

    // For payload, we'd need to stringify it - simplified for now
    const payload: ?[]const u8 = null;

    return .{
        .msg_type = msg_type,
        .id = id,
        .payload = payload,
    };
}

/// Create a journal entry notification
pub fn createJournalNotification(
    allocator: std.mem.Allocator,
    sub_id: []const u8,
    entry: bridge.JournalEntry,
) ![]const u8 {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    const writer = payload.writer();

    try writer.print(
        \\{{"data":{{"journalStream":{{"seq":{d},"timestamp":"{s}","operation":"{s}"
    , .{ entry.sequence, entry.timestamp, entry.operation });

    if (entry.collection) |col| {
        try writer.print(",\"collection\":\"{s}\"", .{col});
    }

    try writer.writeAll("}}}}");

    return try createSubscriptionMessage(allocator, "next", sub_id, payload.items);
}

// =============================================================================
// Helper Functions
// =============================================================================

fn getHeader(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var iter = request.iterateHeaders();
    while (iter.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            return header.value;
        }
    }
    return null;
}

fn sendBadRequest(request: *std.http.Server.Request, message: []const u8) !void {
    _ = message;
    request.respond(
        \\{"error":"bad_request"}
    , .{
        .status = .bad_request,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}

// =============================================================================
// Tests
// =============================================================================

test "websocket accept key computation" {
    const allocator = std.testing.allocator;

    // Example from RFC 6455
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    const accept = try computeAcceptKey(allocator, key);
    defer allocator.free(accept);

    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept);
}

test "websocket frame encoding" {
    const allocator = std.testing.allocator;

    // Small payload
    const frame = try encodeFrame(allocator, .text, "Hello");
    defer allocator.free(frame);

    try std.testing.expectEqual(@as(u8, 0x81), frame[0]); // FIN + text
    try std.testing.expectEqual(@as(u8, 5), frame[1]); // Length
    try std.testing.expectEqualStrings("Hello", frame[2..7]);
}

test "subscription message creation" {
    const allocator = std.testing.allocator;

    const msg = try createSubscriptionMessage(allocator, "connection_ack", null, null);
    defer allocator.free(msg);

    try std.testing.expectEqualStrings("{\"type\":\"connection_ack\"}", msg);
}
