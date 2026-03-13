// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - gRPC Handler
//
// gRPC over HTTP/2 with Protocol Buffers
// Implements the Lithoglyph gRPC service defined in proto/lithoglyph.proto

const std = @import("std");
const config = @import("config.zig");
const bridge = @import("bridge_client.zig");

const log = std.log.scoped(.grpc);

pub fn handleRequest(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    cfg: *const config.Config,
) !void {
    _ = cfg;

    const path = request.head.target;

    // gRPC uses POST with specific content-type
    if (request.head.method != .POST) {
        try sendGrpcError(allocator, request, 12, "Unimplemented: Only POST supported");
        return;
    }

    // Check content-type
    const content_type = getHeader(request, "content-type") orelse "";
    if (!std.mem.startsWith(u8, content_type, "application/grpc")) {
        try sendGrpcError(allocator, request, 3, "Invalid content-type for gRPC");
        return;
    }

    // Route to service method
    // Path format: /grpc/lithoglyph.v1.Lithoglyph/MethodName
    if (std.mem.indexOf(u8, path, "/lithoglyph.v1.Lithoglyph/")) |idx| {
        const method = path[idx + "/lithoglyph.v1.Lithoglyph/".len ..];
        try routeGrpcMethod(allocator, request, method);
    } else {
        try sendGrpcError(allocator, request, 12, "Unknown service");
    }
}

fn routeGrpcMethod(allocator: std.mem.Allocator, request: *std.http.Server.Request, method: []const u8) !void {
    log.info("gRPC method: {s}", .{method});

    // Read request body (gRPC frame)
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(body);

    // Parse gRPC frame: 1 byte compression + 4 bytes length + message
    if (body.len < 5) {
        try sendGrpcError(allocator, request, 3, "Invalid gRPC frame");
        return;
    }

    const compressed = body[0] != 0;
    if (compressed) {
        try sendGrpcError(allocator, request, 12, "Compression not supported");
        return;
    }

    const msg_len = std.mem.readInt(u32, body[1..5], .big);
    if (body.len < 5 + msg_len) {
        try sendGrpcError(allocator, request, 3, "Incomplete gRPC message");
        return;
    }

    const msg_data = body[5 .. 5 + msg_len];

    // Route to method handler
    if (std.mem.eql(u8, method, "Query")) {
        try handleQuery(allocator, request, msg_data);
    } else if (std.mem.eql(u8, method, "ListCollections")) {
        try handleListCollections(allocator, request);
    } else if (std.mem.eql(u8, method, "GetCollection")) {
        try handleGetCollection(allocator, request, msg_data);
    } else if (std.mem.eql(u8, method, "CreateCollection")) {
        try handleCreateCollection(allocator, request, msg_data);
    } else if (std.mem.eql(u8, method, "GetJournal")) {
        try handleGetJournal(allocator, request, msg_data);
    } else if (std.mem.eql(u8, method, "DiscoverDependencies")) {
        try handleDiscoverDependencies(allocator, request, msg_data);
    } else if (std.mem.eql(u8, method, "AnalyzeNormalForm")) {
        try handleAnalyzeNormalForm(allocator, request, msg_data);
    } else if (std.mem.eql(u8, method, "StartMigration")) {
        try handleStartMigration(allocator, request, msg_data);
    } else if (std.mem.eql(u8, method, "Health")) {
        try handleHealth(allocator, request);
    } else {
        try sendGrpcError(allocator, request, 12, "Unimplemented method");
    }
}

// =============================================================================
// Protobuf Encoding Helpers
// =============================================================================

const ProtobufEncoder = struct {
    buffer: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) ProtobufEncoder {
        return .{ .buffer = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *ProtobufEncoder) void {
        self.buffer.deinit();
    }

    fn writeVarint(self: *ProtobufEncoder, value: u64) !void {
        var v = value;
        while (v >= 0x80) {
            try self.buffer.append(@as(u8, @truncate(v)) | 0x80);
            v >>= 7;
        }
        try self.buffer.append(@as(u8, @truncate(v)));
    }

    fn writeTag(self: *ProtobufEncoder, field: u32, wire_type: u3) !void {
        try self.writeVarint(@as(u64, field) << 3 | wire_type);
    }

    fn writeString(self: *ProtobufEncoder, field: u32, value: []const u8) !void {
        try self.writeTag(field, 2); // Length-delimited
        try self.writeVarint(value.len);
        try self.buffer.appendSlice(value);
    }

    fn writeInt64(self: *ProtobufEncoder, field: u32, value: i64) !void {
        try self.writeTag(field, 0); // Varint
        try self.writeVarint(@bitCast(value));
    }

    fn writeUint64(self: *ProtobufEncoder, field: u32, value: u64) !void {
        try self.writeTag(field, 0); // Varint
        try self.writeVarint(value);
    }

    fn writeUint32(self: *ProtobufEncoder, field: u32, value: u32) !void {
        try self.writeTag(field, 0); // Varint
        try self.writeVarint(value);
    }

    fn writeBool(self: *ProtobufEncoder, field: u32, value: bool) !void {
        try self.writeTag(field, 0); // Varint
        try self.writeVarint(if (value) 1 else 0);
    }

    fn writeEnum(self: *ProtobufEncoder, field: u32, value: i32) !void {
        try self.writeTag(field, 0); // Varint
        try self.writeVarint(@bitCast(@as(i64, value)));
    }

    fn writeBytes(self: *ProtobufEncoder, field: u32, value: []const u8) !void {
        try self.writeTag(field, 2); // Length-delimited
        try self.writeVarint(value.len);
        try self.buffer.appendSlice(value);
    }

    fn writeMessage(self: *ProtobufEncoder, field: u32, msg: []const u8) !void {
        try self.writeTag(field, 2); // Length-delimited
        try self.writeVarint(msg.len);
        try self.buffer.appendSlice(msg);
    }

    fn finish(self: *ProtobufEncoder) []const u8 {
        return self.buffer.items;
    }
};

const ProtobufDecoder = struct {
    data: []const u8,
    pos: usize,

    fn init(data: []const u8) ProtobufDecoder {
        return .{ .data = data, .pos = 0 };
    }

    fn readVarint(self: *ProtobufDecoder) !u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        while (self.pos < self.data.len) {
            const b = self.data[self.pos];
            self.pos += 1;
            result |= @as(u64, b & 0x7F) << shift;
            if (b < 0x80) return result;
            shift += 7;
            if (shift >= 64) return error.VarintOverflow;
        }
        return error.UnexpectedEof;
    }

    fn readTag(self: *ProtobufDecoder) !struct { field: u32, wire_type: u3 } {
        const v = try self.readVarint();
        return .{
            .field = @truncate(v >> 3),
            .wire_type = @truncate(v & 0x7),
        };
    }

    fn readString(self: *ProtobufDecoder) ![]const u8 {
        const len = try self.readVarint();
        if (self.pos + len > self.data.len) return error.UnexpectedEof;
        const result = self.data[self.pos .. self.pos + @as(usize, @intCast(len))];
        self.pos += @intCast(len);
        return result;
    }

    fn skipField(self: *ProtobufDecoder, wire_type: u3) !void {
        switch (wire_type) {
            0 => _ = try self.readVarint(), // Varint
            1 => self.pos += 8, // 64-bit
            2 => { // Length-delimited
                const len = try self.readVarint();
                self.pos += @intCast(len);
            },
            5 => self.pos += 4, // 32-bit
            else => return error.UnknownWireType,
        }
    }

    fn hasMore(self: *ProtobufDecoder) bool {
        return self.pos < self.data.len;
    }
};

// =============================================================================
// gRPC Method Handlers
// =============================================================================

fn handleQuery(allocator: std.mem.Allocator, request: *std.http.Server.Request, msg_data: []const u8) !void {
    // Parse QueryRequest: fdql (1), explain (2), analyze (3), verbose (4), provenance (5)
    var decoder = ProtobufDecoder.init(msg_data);
    var fdql: []const u8 = "";
    var explain = false;

    while (decoder.hasMore()) {
        const tag = try decoder.readTag();
        switch (tag.field) {
            1 => fdql = try decoder.readString(), // fdql
            2 => explain = (try decoder.readVarint()) != 0, // explain
            else => try decoder.skipField(tag.wire_type),
        }
    }

    if (fdql.len == 0) {
        try sendGrpcError(allocator, request, 3, "Missing fdql field");
        return;
    }

    log.info("gRPC Query: {s}", .{fdql});

    // Execute via bridge
    if (explain) {
        // Return explain plan
        var encoder = ProtobufEncoder.init(allocator);
        defer encoder.deinit();

        // QueryResponse.plan (field 2)
        var plan_encoder = ProtobufEncoder.init(allocator);
        defer plan_encoder.deinit();
        try plan_encoder.writeString(4, "Full scan with filter"); // rationale
        try encoder.writeMessage(2, plan_encoder.finish());

        try sendGrpcResponse(allocator, request, encoder.finish());
        return;
    }

    var result = bridge.executeQuery(fdql, null) catch |err| {
        log.err("Query failed: {}", .{err});
        try sendGrpcError(allocator, request, 13, "Query execution failed");
        return;
    };
    defer result.deinit(allocator);

    // Build QueryResponse
    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, result.data); // rows (JSON for now)
    try encoder.writeUint64(3, result.rows_affected); // row_count

    try sendGrpcResponse(allocator, request, encoder.finish());
}

fn handleListCollections(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    const collections = bridge.listCollections() catch |err| {
        log.err("ListCollections failed: {}", .{err});
        try sendGrpcError(allocator, request, 13, "Failed to list collections");
        return;
    };
    defer allocator.free(collections);

    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    // ListCollectionsResponse: collections (1), total (2)
    for (collections) |col| {
        var col_encoder = ProtobufEncoder.init(allocator);
        defer col_encoder.deinit();
        try col_encoder.writeString(1, col.name); // name
        try col_encoder.writeEnum(2, 0); // type = DOCUMENT
        try col_encoder.writeUint64(4, col.document_count); // document_count
        try encoder.writeMessage(1, col_encoder.finish());
    }
    try encoder.writeUint32(2, @intCast(collections.len)); // total

    try sendGrpcResponse(allocator, request, encoder.finish());
}

fn handleGetCollection(allocator: std.mem.Allocator, request: *std.http.Server.Request, msg_data: []const u8) !void {
    var decoder = ProtobufDecoder.init(msg_data);
    var name: []const u8 = "";

    while (decoder.hasMore()) {
        const tag = try decoder.readTag();
        switch (tag.field) {
            1 => name = try decoder.readString(),
            else => try decoder.skipField(tag.wire_type),
        }
    }

    const collection = bridge.getCollection(name) catch |err| {
        log.err("GetCollection failed: {}", .{err});
        try sendGrpcError(allocator, request, 13, "Failed to get collection");
        return;
    };

    if (collection) |col| {
        var encoder = ProtobufEncoder.init(allocator);
        defer encoder.deinit();
        try encoder.writeString(1, col.name);
        try encoder.writeEnum(2, 0); // DOCUMENT
        try encoder.writeUint64(4, col.document_count);
        try sendGrpcResponse(allocator, request, encoder.finish());
    } else {
        try sendGrpcError(allocator, request, 5, "Collection not found");
    }
}

fn handleCreateCollection(allocator: std.mem.Allocator, request: *std.http.Server.Request, msg_data: []const u8) !void {
    var decoder = ProtobufDecoder.init(msg_data);
    var name: []const u8 = "";
    var schema: []const u8 = "{}";

    while (decoder.hasMore()) {
        const tag = try decoder.readTag();
        switch (tag.field) {
            1 => name = try decoder.readString(),
            3 => schema = try decoder.readString(), // schema_json
            else => try decoder.skipField(tag.wire_type),
        }
    }

    bridge.createCollection(name, schema) catch |err| {
        log.err("CreateCollection failed: {}", .{err});
        const msg = switch (err) {
            error.NotImplemented => "Collection creation not yet implemented",
            else => "Failed to create collection",
        };
        try sendGrpcError(allocator, request, 12, msg);
        return;
    };

    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();
    try encoder.writeString(1, name);
    try encoder.writeEnum(2, 0); // DOCUMENT
    try encoder.writeUint64(4, 0); // document_count
    try sendGrpcResponse(allocator, request, encoder.finish());
}

fn handleGetJournal(allocator: std.mem.Allocator, request: *std.http.Server.Request, msg_data: []const u8) !void {
    var decoder = ProtobufDecoder.init(msg_data);
    var since: u64 = 0;
    var limit: u32 = 100;

    while (decoder.hasMore()) {
        const tag = try decoder.readTag();
        switch (tag.field) {
            1 => since = try decoder.readVarint(),
            2 => limit = @truncate(try decoder.readVarint()),
            else => try decoder.skipField(tag.wire_type),
        }
    }

    const entries = bridge.getJournal(since, limit) catch |err| {
        log.err("GetJournal failed: {}", .{err});
        try sendGrpcError(allocator, request, 13, "Failed to get journal");
        return;
    };
    defer allocator.free(entries);

    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    for (entries) |entry| {
        var entry_encoder = ProtobufEncoder.init(allocator);
        defer entry_encoder.deinit();
        try entry_encoder.writeUint64(1, entry.sequence);
        try entry_encoder.writeString(2, entry.timestamp);
        try entry_encoder.writeString(3, entry.operation);
        if (entry.collection) |col| {
            try entry_encoder.writeString(4, col);
        }
        try encoder.writeMessage(1, entry_encoder.finish());
    }

    try sendGrpcResponse(allocator, request, encoder.finish());
}

fn handleDiscoverDependencies(allocator: std.mem.Allocator, request: *std.http.Server.Request, msg_data: []const u8) !void {
    // Parse DiscoverDependenciesRequest: collection (1), sample_size (2)
    var decoder = ProtobufDecoder.init(msg_data);
    var collection: []const u8 = "";
    var sample_size: u32 = 1000;

    while (decoder.hasMore()) {
        const tag = try decoder.readTag();
        switch (tag.field) {
            1 => collection = try decoder.readString(),
            2 => sample_size = @truncate(try decoder.readVarint()),
            else => try decoder.skipField(tag.wire_type),
        }
    }

    if (collection.len == 0) {
        try sendGrpcError(allocator, request, 3, "Missing collection field");
        return;
    }

    const deps = bridge.discoverDependencies(collection, sample_size) catch |err| {
        log.err("DiscoverDependencies failed for {s}: {}", .{ collection, err });
        const msg = switch (err) {
            error.NotImplemented => "Dependency discovery not yet implemented in bridge",
            error.NotInitialized => "Database not initialized",
            else => "Failed to discover dependencies",
        };
        // gRPC status 12 = UNIMPLEMENTED for NotImplemented, 13 = INTERNAL otherwise
        const code: u8 = switch (err) {
            error.NotImplemented => 12,
            else => 13,
        };
        try sendGrpcError(allocator, request, code, msg);
        return;
    };
    defer allocator.free(deps);

    // Build DiscoverDependenciesResponse
    // collection (1), dependencies repeated (2)
    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, collection);
    for (deps) |dep| {
        // Encode each FunctionalDependency as a sub-message
        // FunctionalDependency: determinant repeated (1), dependent (2), confidence (3)
        var dep_encoder = ProtobufEncoder.init(allocator);
        defer dep_encoder.deinit();
        for (dep.determinant) |det| {
            try dep_encoder.writeString(1, det);
        }
        try dep_encoder.writeString(2, dep.dependent);
        // Encode confidence as fixed32 (IEEE 754 float)
        try dep_encoder.writeTag(3, 5); // wire type 5 = 32-bit
        const conf_bits: u32 = @bitCast(dep.confidence);
        try dep_encoder.buffer.appendSlice(&std.mem.toBytes(conf_bits));
        try encoder.writeMessage(2, dep_encoder.finish());
    }

    try sendGrpcResponse(allocator, request, encoder.finish());
}

fn handleAnalyzeNormalForm(allocator: std.mem.Allocator, request: *std.http.Server.Request, msg_data: []const u8) !void {
    // Parse AnalyzeNormalFormRequest: collection (1)
    var decoder = ProtobufDecoder.init(msg_data);
    var collection: []const u8 = "";

    while (decoder.hasMore()) {
        const tag = try decoder.readTag();
        switch (tag.field) {
            1 => collection = try decoder.readString(),
            else => try decoder.skipField(tag.wire_type),
        }
    }

    if (collection.len == 0) {
        try sendGrpcError(allocator, request, 3, "Missing collection field");
        return;
    }

    const analysis = bridge.analyzeNormalForm(collection) catch |err| {
        log.err("AnalyzeNormalForm failed for {s}: {}", .{ collection, err });
        const msg = switch (err) {
            error.NotImplemented => "Normal form analysis not yet implemented in bridge",
            error.NotInitialized => "Database not initialized",
            else => "Failed to analyze normal form",
        };
        const code: u8 = switch (err) {
            error.NotImplemented => 12,
            else => 13,
        };
        try sendGrpcError(allocator, request, code, msg);
        return;
    };

    // Build AnalyzeNormalFormResponse
    // collection (1), current_form enum (2), violations repeated string (3), suggestions repeated string (4)
    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, collection);

    // Map current_form string to enum value
    // NormalForm enum: UNF=0, 1NF=1, 2NF=2, 3NF=3, BCNF=4, 4NF=5, 5NF=6
    const form_enum: i32 = if (std.mem.eql(u8, analysis.current_form, "UNF"))
        0
    else if (std.mem.eql(u8, analysis.current_form, "1NF"))
        1
    else if (std.mem.eql(u8, analysis.current_form, "2NF"))
        2
    else if (std.mem.eql(u8, analysis.current_form, "3NF"))
        3
    else if (std.mem.eql(u8, analysis.current_form, "BCNF"))
        4
    else if (std.mem.eql(u8, analysis.current_form, "4NF"))
        5
    else if (std.mem.eql(u8, analysis.current_form, "5NF"))
        6
    else
        0; // Default to UNF for unknown forms

    try encoder.writeEnum(2, form_enum);

    for (analysis.violations) |violation| {
        try encoder.writeString(3, violation);
    }
    for (analysis.suggestions) |suggestion| {
        try encoder.writeString(4, suggestion);
    }

    try sendGrpcResponse(allocator, request, encoder.finish());
}

fn handleStartMigration(allocator: std.mem.Allocator, request: *std.http.Server.Request, msg_data: []const u8) !void {
    // Parse StartMigrationRequest: collection (1), target_schema (2)
    var decoder = ProtobufDecoder.init(msg_data);
    var collection: []const u8 = "";
    var target_schema: []const u8 = "{}";

    while (decoder.hasMore()) {
        const tag = try decoder.readTag();
        switch (tag.field) {
            1 => collection = try decoder.readString(),
            2 => target_schema = try decoder.readString(),
            else => try decoder.skipField(tag.wire_type),
        }
    }

    if (collection.len == 0) {
        try sendGrpcError(allocator, request, 3, "Missing collection field");
        return;
    }

    const migration = bridge.startMigration(collection, target_schema) catch |err| {
        log.err("StartMigration failed for {s}: {}", .{ collection, err });
        const msg = switch (err) {
            error.NotImplemented => "Migration not yet implemented in bridge",
            error.NotInitialized => "Database not initialized",
            else => "Failed to start migration",
        };
        const code: u8 = switch (err) {
            error.NotImplemented => 12,
            else => 13,
        };
        try sendGrpcError(allocator, request, code, msg);
        return;
    };

    // Build StartMigrationResponse
    // id (1), phase enum (2), collection (3), narrative (4)
    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, migration.id);

    // MigrationPhase enum: ANNOUNCE=0, SHADOW=1, SHADOW_COMPLETE=2, COMPLETE=3, ABORTED=4
    const phase_enum: i32 = switch (migration.state) {
        .announced => 0,
        .shadow_running => 1,
        .shadow_complete => 2,
        .committed => 3,
        .aborted => 4,
    };
    try encoder.writeEnum(2, phase_enum);
    try encoder.writeString(3, migration.source_collection);
    try encoder.writeString(4, migration.created_at);

    try sendGrpcResponse(allocator, request, encoder.finish());
}

fn handleHealth(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    const health = bridge.getHealth();

    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    // HealthResponse: status (1), version (2), uptime_seconds (3)
    try encoder.writeEnum(1, if (std.mem.eql(u8, health.status, "healthy")) 0 else 1);
    try encoder.writeString(2, health.version);
    try encoder.writeUint64(3, health.uptime_seconds);

    try sendGrpcResponse(allocator, request, encoder.finish());
}

// =============================================================================
// gRPC Response Helpers
// =============================================================================

fn sendGrpcResponse(allocator: std.mem.Allocator, request: *std.http.Server.Request, data: []const u8) !void {
    // gRPC uses length-prefixed messages
    // Format: 1 byte compression flag + 4 bytes length + data
    var frame = try allocator.alloc(u8, 5 + data.len);
    defer allocator.free(frame);

    frame[0] = 0; // No compression
    std.mem.writeInt(u32, frame[1..5], @intCast(data.len), .big);
    @memcpy(frame[5..], data);

    request.respond(frame, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/grpc+proto" },
            .{ .name = "grpc-status", .value = "0" },
        },
    }) catch {};
}

fn sendGrpcError(allocator: std.mem.Allocator, request: *std.http.Server.Request, code: u8, message: []const u8) !void {
    _ = allocator;

    var code_buf: [8]u8 = undefined;
    const code_str = std.fmt.bufPrint(&code_buf, "{d}", .{code}) catch "0";

    // gRPC conveys error details via grpc-status and grpc-message trailers
    request.respond("", .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/grpc+proto" },
            .{ .name = "grpc-status", .value = code_str },
            .{ .name = "grpc-message", .value = message },
        },
    }) catch {};
}

fn getHeader(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var iter = request.iterateHeaders();
    while (iter.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            return header.value;
        }
    }
    return null;
}

test "grpc path parsing" {
    const path = "/grpc/lithoglyph.v1.Lithoglyph/Query";
    if (std.mem.indexOf(u8, path, "/lithoglyph.v1.Lithoglyph/")) |idx| {
        const method = path[idx + "/lithoglyph.v1.Lithoglyph/".len ..];
        try std.testing.expectEqualStrings("Query", method);
    } else {
        return error.TestFailed;
    }
}

test "protobuf varint encoding" {
    const allocator = std.testing.allocator;
    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeVarint(150);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x96, 0x01 }, encoder.finish());
}

test "protobuf string encoding" {
    const allocator = std.testing.allocator;
    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, "test");
    // Field 1, wire type 2 = 0x0a, length 4
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x0a, 0x04, 't', 'e', 's', 't' }, encoder.finish());
}
