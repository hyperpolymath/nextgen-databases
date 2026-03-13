// SPDX-License-Identifier: PMPL-1.0-or-later
// Form.Bridge - CBOR Encoding/Decoding
//
// Minimal CBOR implementation following RFC 8949.
// Supports deterministic encoding per Section 4.2.
//
// Part of Lithoglyph: Stone-carved data for the ages.

const std = @import("std");
const types = @import("types.zig");

// ============================================================
// CBOR Major Types
// ============================================================

pub const MajorType = enum(u3) {
    unsigned = 0,
    negative = 1,
    bytes = 2,
    text = 3,
    array = 4,
    map = 5,
    tag = 6,
    simple = 7,
};

// ============================================================
// CBOR Encoder
// ============================================================

pub const Encoder = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Encoder {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Encoder) void {
        self.buffer.deinit();
    }

    pub fn finish(self: *Encoder) []const u8 {
        return self.buffer.items;
    }

    pub fn reset(self: *Encoder) void {
        self.buffer.clearRetainingCapacity();
    }

    // Write major type with argument
    fn writeTypeArg(self: *Encoder, major: MajorType, arg: u64) !void {
        const base: u8 = @as(u8, @intFromEnum(major)) << 5;

        if (arg < 24) {
            try self.buffer.append(base | @as(u8, @truncate(arg)));
        } else if (arg <= 0xFF) {
            try self.buffer.append(base | 24);
            try self.buffer.append(@truncate(arg));
        } else if (arg <= 0xFFFF) {
            try self.buffer.append(base | 25);
            try self.buffer.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u16, @truncate(arg))));
        } else if (arg <= 0xFFFFFFFF) {
            try self.buffer.append(base | 26);
            try self.buffer.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, @truncate(arg))));
        } else {
            try self.buffer.append(base | 27);
            try self.buffer.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u64, arg)));
        }
    }

    // Encode unsigned integer
    pub fn encodeUint(self: *Encoder, value: u64) !void {
        try self.writeTypeArg(.unsigned, value);
    }

    // Encode negative integer
    pub fn encodeNint(self: *Encoder, value: i64) !void {
        const n: u64 = @bitCast(-1 - value);
        try self.writeTypeArg(.negative, n);
    }

    // Encode integer (signed or unsigned)
    pub fn encodeInt(self: *Encoder, value: i64) !void {
        if (value >= 0) {
            try self.encodeUint(@bitCast(value));
        } else {
            try self.encodeNint(value);
        }
    }

    // Encode byte string
    pub fn encodeBytes(self: *Encoder, data: []const u8) !void {
        try self.writeTypeArg(.bytes, data.len);
        try self.buffer.appendSlice(data);
    }

    // Encode text string
    pub fn encodeText(self: *Encoder, text: []const u8) !void {
        try self.writeTypeArg(.text, text.len);
        try self.buffer.appendSlice(text);
    }

    // Begin array (definite length)
    pub fn beginArray(self: *Encoder, len: usize) !void {
        try self.writeTypeArg(.array, len);
    }

    // Begin map (definite length)
    pub fn beginMap(self: *Encoder, len: usize) !void {
        try self.writeTypeArg(.map, len);
    }

    // Encode tag
    pub fn encodeTag(self: *Encoder, tag: u64) !void {
        try self.writeTypeArg(.tag, tag);
    }

    // Encode Lith-specific tag
    pub fn encodeLithTag(self: *Encoder, tag: types.CborTag) !void {
        try self.encodeTag(@intFromEnum(tag));
    }

    // Encode null
    pub fn encodeNull(self: *Encoder) !void {
        try self.buffer.append(0xF6);
    }

    // Encode boolean
    pub fn encodeBool(self: *Encoder, value: bool) !void {
        try self.buffer.append(if (value) 0xF5 else 0xF4);
    }

    // Encode float (smallest representation per RFC 8949 §4.2)
    pub fn encodeFloat(self: *Encoder, value: f64) !void {
        // Check if it fits in half precision
        const half: f16 = @floatCast(value);
        if (@as(f64, @floatCast(half)) == value) {
            try self.buffer.append(0xF9);
            try self.buffer.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u16, @bitCast(half))));
            return;
        }

        // Check if it fits in single precision
        const single: f32 = @floatCast(value);
        if (@as(f64, @floatCast(single)) == value) {
            try self.buffer.append(0xFA);
            try self.buffer.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, @bitCast(single))));
            return;
        }

        // Use double precision
        try self.buffer.append(0xFB);
        try self.buffer.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u64, @bitCast(value))));
    }

    // Encode a simple document (map of string -> any)
    pub fn encodeDocument(self: *Encoder, fields: anytype) !void {
        const info = @typeInfo(@TypeOf(fields));
        const struct_info = info.@"struct";

        try self.beginMap(struct_info.fields.len);

        inline for (struct_info.fields) |field| {
            try self.encodeText(field.name);
            const value = @field(fields, field.name);
            try self.encodeValue(value);
        }
    }

    // Encode any value (comptime type dispatch)
    pub fn encodeValue(self: *Encoder, value: anytype) !void {
        const T = @TypeOf(value);

        if (T == bool) {
            try self.encodeBool(value);
        } else if (@typeInfo(T) == .int) {
            try self.encodeInt(@intCast(value));
        } else if (@typeInfo(T) == .float) {
            try self.encodeFloat(@floatCast(value));
        } else if (T == []const u8) {
            try self.encodeText(value);
        } else if (@typeInfo(T) == .pointer) {
            if (@typeInfo(T).pointer.size == .Slice) {
                if (@typeInfo(T).pointer.child == u8) {
                    try self.encodeText(value);
                } else {
                    try self.beginArray(value.len);
                    for (value) |item| {
                        try self.encodeValue(item);
                    }
                }
            }
        } else if (@typeInfo(T) == .optional) {
            if (value) |v| {
                try self.encodeValue(v);
            } else {
                try self.encodeNull();
            }
        } else if (@typeInfo(T) == .@"struct") {
            try self.encodeDocument(value);
        } else {
            @compileError("unsupported type for CBOR encoding: " ++ @typeName(T));
        }
    }
};

// ============================================================
// CBOR Decoder
// ============================================================

pub const DecodeError = error{
    UnexpectedEof,
    InvalidType,
    InvalidValue,
    OutOfMemory,
};

pub const Decoder = struct {
    data: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) Decoder {
        return .{
            .data = data,
            .pos = 0,
            .allocator = allocator,
        };
    }

    fn remaining(self: *Decoder) []const u8 {
        return self.data[self.pos..];
    }

    fn readByte(self: *Decoder) !u8 {
        if (self.pos >= self.data.len) return error.UnexpectedEof;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Decoder, n: usize) ![]const u8 {
        if (self.pos + n > self.data.len) return error.UnexpectedEof;
        const slice = self.data[self.pos .. self.pos + n];
        self.pos += n;
        return slice;
    }

    fn readArg(self: *Decoder, additional: u5) !u64 {
        if (additional < 24) return additional;
        switch (additional) {
            24 => return try self.readByte(),
            25 => {
                const bytes = try self.readBytes(2);
                return std.mem.bigToNative(u16, std.mem.bytesToValue(u16, bytes[0..2]));
            },
            26 => {
                const bytes = try self.readBytes(4);
                return std.mem.bigToNative(u32, std.mem.bytesToValue(u32, bytes[0..4]));
            },
            27 => {
                const bytes = try self.readBytes(8);
                return std.mem.bigToNative(u64, std.mem.bytesToValue(u64, bytes[0..8]));
            },
            else => return error.InvalidValue,
        }
    }

    pub fn readTypeArg(self: *Decoder) !struct { major: MajorType, arg: u64 } {
        const b = try self.readByte();
        const major: MajorType = @enumFromInt(@as(u3, @truncate(b >> 5)));
        const additional: u5 = @truncate(b);
        const arg = try self.readArg(additional);
        return .{ .major = major, .arg = arg };
    }

    pub fn decodeUint(self: *Decoder) !u64 {
        const ta = try self.readTypeArg();
        if (ta.major != .unsigned) return error.InvalidType;
        return ta.arg;
    }

    pub fn decodeInt(self: *Decoder) !i64 {
        const ta = try self.readTypeArg();
        switch (ta.major) {
            .unsigned => return @bitCast(ta.arg),
            .negative => return -1 - @as(i64, @bitCast(ta.arg)),
            else => return error.InvalidType,
        }
    }

    pub fn decodeText(self: *Decoder) ![]const u8 {
        const ta = try self.readTypeArg();
        if (ta.major != .text) return error.InvalidType;
        return try self.readBytes(@intCast(ta.arg));
    }

    pub fn decodeBytes(self: *Decoder) ![]const u8 {
        const ta = try self.readTypeArg();
        if (ta.major != .bytes) return error.InvalidType;
        return try self.readBytes(@intCast(ta.arg));
    }

    pub fn decodeArrayLen(self: *Decoder) !usize {
        const ta = try self.readTypeArg();
        if (ta.major != .array) return error.InvalidType;
        return @intCast(ta.arg);
    }

    pub fn decodeMapLen(self: *Decoder) !usize {
        const ta = try self.readTypeArg();
        if (ta.major != .map) return error.InvalidType;
        return @intCast(ta.arg);
    }

    pub fn decodeTag(self: *Decoder) !u64 {
        const ta = try self.readTypeArg();
        if (ta.major != .tag) return error.InvalidType;
        return ta.arg;
    }

    pub fn decodeBool(self: *Decoder) !bool {
        const b = try self.readByte();
        switch (b) {
            0xF4 => return false,
            0xF5 => return true,
            else => return error.InvalidType,
        }
    }

    pub fn isNull(self: *Decoder) !bool {
        if (self.pos >= self.data.len) return error.UnexpectedEof;
        if (self.data[self.pos] == 0xF6) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    pub fn skip(self: *Decoder) !void {
        const ta = try self.readTypeArg();
        switch (ta.major) {
            .unsigned, .negative => {},
            .bytes, .text => {
                _ = try self.readBytes(@intCast(ta.arg));
            },
            .array => {
                var i: usize = 0;
                while (i < ta.arg) : (i += 1) {
                    try self.skip();
                }
            },
            .map => {
                var i: usize = 0;
                while (i < ta.arg) : (i += 1) {
                    try self.skip(); // key
                    try self.skip(); // value
                }
            },
            .tag => {
                try self.skip();
            },
            .simple => {
                // Handle floats
                const additional: u5 = @truncate(self.data[self.pos - 1]);
                switch (additional) {
                    25 => _ = try self.readBytes(2),
                    26 => _ = try self.readBytes(4),
                    27 => _ = try self.readBytes(8),
                    else => {},
                }
            },
        }
    }
};

// ============================================================
// Helper Functions
// ============================================================

// Encode a provenance payload
pub fn encodeProvenance(
    allocator: std.mem.Allocator,
    actor_id: []const u8,
    actor_type: []const u8,
    rationale: []const u8,
    timestamp: []const u8,
) ![]u8 {
    var encoder = Encoder.init(allocator);
    errdefer encoder.deinit();

    try encoder.encodeLithTag(.provenance);
    try encoder.beginMap(3);

    // actor
    try encoder.encodeText("actor");
    try encoder.encodeLithTag(.actor);
    try encoder.beginMap(2);
    try encoder.encodeText("id");
    try encoder.encodeText(actor_id);
    try encoder.encodeText("type");
    try encoder.encodeText(actor_type);

    // rationale
    try encoder.encodeText("rationale");
    try encoder.encodeText(rationale);

    // timestamp
    try encoder.encodeText("timestamp");
    try encoder.encodeTag(0); // datetime tag
    try encoder.encodeText(timestamp);

    const result = try allocator.dupe(u8, encoder.finish());
    encoder.deinit();
    return result;
}

// Encode an error blob
pub fn encodeError(
    allocator: std.mem.Allocator,
    code: i32,
    message: []const u8,
) ![]u8 {
    var encoder = Encoder.init(allocator);
    errdefer encoder.deinit();

    try encoder.beginMap(2);
    try encoder.encodeText("code");
    try encoder.encodeInt(code);
    try encoder.encodeText("message");
    try encoder.encodeText(message);

    const result = try allocator.dupe(u8, encoder.finish());
    encoder.deinit();
    return result;
}

// ============================================================
// Tests
// ============================================================

test "encode unsigned integers" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.encodeUint(0);
    try encoder.encodeUint(23);
    try encoder.encodeUint(24);
    try encoder.encodeUint(255);
    try encoder.encodeUint(256);

    const result = encoder.finish();

    try std.testing.expectEqual(@as(u8, 0x00), result[0]); // 0
    try std.testing.expectEqual(@as(u8, 0x17), result[1]); // 23
    try std.testing.expectEqual(@as(u8, 0x18), result[2]); // 24 prefix
    try std.testing.expectEqual(@as(u8, 0x18), result[3]); // 24 value
    try std.testing.expectEqual(@as(u8, 0x18), result[4]); // 255 prefix
    try std.testing.expectEqual(@as(u8, 0xFF), result[5]); // 255 value
}

test "encode text string" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.encodeText("hello");

    const result = encoder.finish();

    try std.testing.expectEqual(@as(u8, 0x65), result[0]); // text(5)
    try std.testing.expectEqualStrings("hello", result[1..6]);
}

test "encode simple map" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.beginMap(2);
    try encoder.encodeText("name");
    try encoder.encodeText("Lith");
    try encoder.encodeText("version");
    try encoder.encodeUint(1);

    const result = encoder.finish();

    try std.testing.expectEqual(@as(u8, 0xA2), result[0]); // map(2)
}

test "decode unsigned integer" {
    const data = [_]u8{ 0x18, 0x64 }; // 100
    var decoder = Decoder.init(std.testing.allocator, &data);

    const value = try decoder.decodeUint();
    try std.testing.expectEqual(@as(u64, 100), value);
}

test "decode text string" {
    const data = [_]u8{ 0x65, 'h', 'e', 'l', 'l', 'o' };
    var decoder = Decoder.init(std.testing.allocator, &data);

    const text = try decoder.decodeText();
    try std.testing.expectEqualStrings("hello", text);
}

test "encode provenance" {
    const result = try encodeProvenance(
        std.testing.allocator,
        "user_123",
        "human",
        "Adding test data",
        "2026-01-11T12:00:00Z",
    );
    defer std.testing.allocator.free(result);

    // Verify it starts with provenance tag
    try std.testing.expectEqual(@as(u8, 0xD9), result[0]); // tag (2-byte)
}
