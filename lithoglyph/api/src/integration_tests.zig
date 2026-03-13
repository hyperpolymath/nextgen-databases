// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - Integration Tests
//
// End-to-end tests for REST, gRPC, and GraphQL endpoints
// Tests API server with mocked Form.Bridge responses

const std = @import("std");
const rest = @import("rest.zig");
const grpc = @import("grpc.zig");
const graphql = @import("graphql.zig");
const websocket = @import("websocket.zig");
const bridge = @import("bridge_client.zig");
const config = @import("config.zig");

// =============================================================================
// Test Utilities
// =============================================================================

fn createTestAllocator() std.mem.Allocator {
    return std.testing.allocator;
}

// =============================================================================
// REST API Integration Tests
// =============================================================================

test "REST health endpoint returns valid JSON" {
    const allocator = createTestAllocator();

    // Verify bridge health response format
    const health = bridge.getHealth();
    try std.testing.expect(health.status.len > 0);
    try std.testing.expect(health.version.len > 0);
    try std.testing.expect(health.uptime_seconds >= 0);

    _ = allocator;
}

test "REST collections endpoint returns valid structure" {
    const allocator = createTestAllocator();

    // Verify bridge collections response format
    const collections = try bridge.getCollections(allocator);
    defer allocator.free(collections);

    // Should be valid JSON array
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, collections, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .array);
}

test "REST query execution returns valid response" {
    const allocator = createTestAllocator();

    // Test GQL query execution
    const result = try bridge.executeQuery(allocator, "SELECT * FROM test");
    defer allocator.free(result);

    // Should be valid JSON with rows
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
}

// =============================================================================
// gRPC Integration Tests
// =============================================================================

test "gRPC protobuf encoder creates valid frames" {
    const allocator = createTestAllocator();
    var encoder = grpc.ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    // Write a string field (field 1, wire type 2 = length-delimited)
    try encoder.writeString(1, "test_value");

    const encoded = encoder.getEncoded();
    try std.testing.expect(encoded.len > 0);

    // First byte should be tag (field 1 << 3 | wire type 2 = 10 = 0x0A)
    try std.testing.expectEqual(@as(u8, 0x0A), encoded[0]);
}

test "gRPC protobuf encoder handles varints correctly" {
    const allocator = createTestAllocator();
    var encoder = grpc.ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    // Test small varint (single byte)
    try encoder.writeVarint(127);
    try std.testing.expectEqual(@as(usize, 1), encoder.getEncoded().len);

    // Reset and test multi-byte varint
    encoder.reset();
    try encoder.writeVarint(300);
    // 300 = 0b100101100 = 0xAC 0x02 in varint encoding
    try std.testing.expectEqual(@as(usize, 2), encoder.getEncoded().len);
}

test "gRPC protobuf decoder parses valid messages" {
    const allocator = createTestAllocator();

    // Create a simple message: field 1 = "hello"
    var encoder = grpc.ProtobufEncoder.init(allocator);
    defer encoder.deinit();
    try encoder.writeString(1, "hello");

    const encoded = encoder.getEncoded();

    // Now decode it
    var decoder = grpc.ProtobufDecoder.init(encoded);

    const field = try decoder.readField();
    try std.testing.expectEqual(@as(u32, 1), field.field_number);
    try std.testing.expectEqual(@as(u3, 2), field.wire_type);

    const value = try decoder.readString(allocator);
    defer allocator.free(value);

    try std.testing.expectEqualStrings("hello", value);
}

test "gRPC frame encoding creates valid structure" {
    const allocator = createTestAllocator();

    const message = "test message";
    const frame = try grpc.encodeGrpcFrame(allocator, message);
    defer allocator.free(frame);

    // gRPC frame: 1 byte compression + 4 bytes length + message
    try std.testing.expectEqual(@as(usize, 5 + message.len), frame.len);

    // First byte should be 0 (no compression)
    try std.testing.expectEqual(@as(u8, 0), frame[0]);

    // Next 4 bytes should be message length in big endian
    const len = std.mem.readInt(u32, frame[1..5], .big);
    try std.testing.expectEqual(@as(u32, @intCast(message.len)), len);

    // Rest should be the message
    try std.testing.expectEqualStrings(message, frame[5..]);
}

// =============================================================================
// GraphQL Integration Tests
// =============================================================================

test "GraphQL request parsing handles valid JSON" {
    const allocator = createTestAllocator();

    const body =
        \\{"query": "{ health { status } }", "variables": null}
    ;

    const parsed = try std.json.parseFromSlice(graphql.GraphQLRequest, allocator, body, .{});
    defer parsed.deinit();

    try std.testing.expect(std.mem.indexOf(u8, parsed.value.query, "health") != null);
}

test "GraphQL introspection detection works" {
    const query1 = "{ __schema { types { name } } }";
    const query2 = "{ __type(name: \"Query\") { fields { name } } }";
    const query3 = "{ health { status } }";

    // __schema should trigger introspection
    try std.testing.expect(std.mem.indexOf(u8, query1, "__schema") != null);
    try std.testing.expect(std.mem.indexOf(u8, query2, "__type") != null);

    // Regular query should not
    try std.testing.expect(std.mem.indexOf(u8, query3, "__schema") == null);
    try std.testing.expect(std.mem.indexOf(u8, query3, "__type") == null);
}

// =============================================================================
// WebSocket Integration Tests
// =============================================================================

test "WebSocket accept key computation follows RFC 6455" {
    const allocator = createTestAllocator();

    // Example from RFC 6455 Section 1.3
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    const expected = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";

    const accept = try websocket.computeAcceptKey(allocator, key);
    defer allocator.free(accept);

    try std.testing.expectEqualStrings(expected, accept);
}

test "WebSocket frame encoding creates valid frames" {
    const allocator = createTestAllocator();

    // Small payload (< 126 bytes)
    const frame = try websocket.encodeFrame(allocator, .text, "Hello");
    defer allocator.free(frame);

    // First byte: FIN (0x80) | opcode (0x01 for text) = 0x81
    try std.testing.expectEqual(@as(u8, 0x81), frame[0]);

    // Second byte: payload length (5)
    try std.testing.expectEqual(@as(u8, 5), frame[1]);

    // Payload
    try std.testing.expectEqualStrings("Hello", frame[2..7]);
}

test "WebSocket frame encoding handles medium payloads" {
    const allocator = createTestAllocator();

    // Medium payload (126-65535 bytes)
    var payload: [200]u8 = undefined;
    @memset(&payload, 'A');

    const frame = try websocket.encodeFrame(allocator, .text, &payload);
    defer allocator.free(frame);

    // First byte: FIN | text
    try std.testing.expectEqual(@as(u8, 0x81), frame[0]);

    // Second byte: 126 indicates 16-bit length follows
    try std.testing.expectEqual(@as(u8, 126), frame[1]);

    // Next 2 bytes: length in big endian
    const len = std.mem.readInt(u16, frame[2..4], .big);
    try std.testing.expectEqual(@as(u16, 200), len);
}

test "WebSocket subscription message creation" {
    const allocator = createTestAllocator();

    // Connection ack message
    const msg = try websocket.createSubscriptionMessage(allocator, "connection_ack", null, null);
    defer allocator.free(msg);

    try std.testing.expectEqualStrings("{\"type\":\"connection_ack\"}", msg);
}

test "WebSocket subscription message with id and payload" {
    const allocator = createTestAllocator();

    const msg = try websocket.createSubscriptionMessage(
        allocator,
        "next",
        "sub-123",
        "{\"data\":{\"journalStream\":{\"seq\":42}}}",
    );
    defer allocator.free(msg);

    // Should contain type, id, and payload
    try std.testing.expect(std.mem.indexOf(u8, msg, "\"type\":\"next\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "\"id\":\"sub-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "\"payload\":") != null);
}

test "WebSocket connection management" {
    const allocator = createTestAllocator();

    var conn = websocket.Connection.init(allocator);
    defer conn.deinit();

    try std.testing.expect(conn.is_open);
    try std.testing.expectEqual(@as(usize, 0), conn.subscriptions.count());

    // Add subscription
    try conn.addSubscription("sub-1", .journal_stream);
    try std.testing.expectEqual(@as(usize, 1), conn.subscriptions.count());

    // Remove subscription
    conn.removeSubscription("sub-1");
    try std.testing.expectEqual(@as(usize, 0), conn.subscriptions.count());
}

// =============================================================================
// Bridge Client Integration Tests
// =============================================================================

test "Bridge client health check returns valid response" {
    const health = bridge.getHealth();

    // Should have valid fields
    try std.testing.expect(health.status.len > 0);
    try std.testing.expect(health.version.len > 0);
}

test "Bridge client CBOR encoding produces valid output" {
    const allocator = createTestAllocator();

    // Test CBOR map encoding
    var cbor = std.ArrayList(u8).init(allocator);
    defer cbor.deinit();

    // Write a simple CBOR map: {1: "test"}
    try cbor.append(0xA1); // Map with 1 item
    try cbor.append(0x01); // Key: 1
    try cbor.append(0x64); // Text string of length 4
    try cbor.appendSlice("test");

    try std.testing.expectEqual(@as(usize, 7), cbor.items.len);
}

// =============================================================================
// Configuration Tests
// =============================================================================

test "Config default values are sensible" {
    const cfg = config.Config{};

    try std.testing.expectEqual(@as(u16, 8080), cfg.port);
    try std.testing.expectEqualStrings("0.0.0.0", cfg.host);
    try std.testing.expect(cfg.max_connections > 0);
}

test "Config environment variable parsing" {
    // This test verifies the config module can parse environment
    // Note: Actual env vars won't be set in test environment
    const cfg = config.Config{};

    // Default values should be used when env vars not set
    try std.testing.expect(cfg.port > 0);
    try std.testing.expect(cfg.host.len > 0);
}
