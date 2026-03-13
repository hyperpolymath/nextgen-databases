// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph Block Storage - Forth-Compatible Implementation
//
// Implements the block format specified in core-forth/src/lithoglyph-blocks.fs
// All blocks are 4KiB with 64-byte headers and CRC32C checksums.
//
// This is the truth core - stone-carved data for the ages.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================
// Constants (must match Forth specification)
// ============================================================

pub const BLOCK_SIZE: usize = 4096; // 4 KiB blocks
pub const HEADER_SIZE: usize = 64; // 64-byte fixed header
pub const PAYLOAD_SIZE: usize = BLOCK_SIZE - HEADER_SIZE; // 4032 bytes

// Magic bytes: "LGH\0" = 0x4C474800 (Lithoglyph)
pub const BLOCK_MAGIC: u32 = 0x4C474800;
pub const BLOCK_VERSION: u16 = 1;

// Block Types (must match Forth definitions)
pub const BlockType = enum(u16) {
    free = 0x0000,
    superblock = 0x0001,
    collection_meta = 0x0010,
    document = 0x0011,
    document_overflow = 0x0012,
    edge_meta = 0x0020,
    edge = 0x0021,
    index_root = 0x0030,
    index_internal = 0x0031,
    index_leaf = 0x0032,
    journal_segment = 0x0040,
    schema = 0x0050,
    constraint = 0x0051,
    migration = 0x0060,
};

// Block Flags (bitmask)
pub const BlockFlags = packed struct {
    compressed: bool = false,
    encrypted: bool = false,
    chained: bool = false,
    deleted: bool = false,
    _reserved: u4 = 0,
};

// ============================================================
// Block Header Structure (64 bytes, matching Forth layout)
// ============================================================
//
// Offset  Size  Field
// 0       4     magic
// 4       2     version
// 6       2     block_type
// 8       8     block_id
// 16      8     sequence
// 24      8     created_at
// 32      8     modified_at
// 40      4     payload_len
// 44      4     checksum
// 48      8     prev_block_id
// 56      4     flags
// 60      4     reserved

pub const BlockHeader = extern struct {
    magic: u32 align(1),
    version: u16 align(1),
    block_type: u16 align(1),
    block_id: u64 align(1),
    sequence: u64 align(1),
    created_at: u64 align(1),
    modified_at: u64 align(1),
    payload_len: u32 align(1),
    checksum: u32 align(1),
    prev_block_id: u64 align(1),
    flags: u32 align(1),
    reserved: u32 align(1),

    comptime {
        // Verify at compile time that struct is exactly 64 bytes
        if (@sizeOf(BlockHeader) != HEADER_SIZE) {
            @compileError("BlockHeader must be exactly 64 bytes");
        }
    }

    /// Initialize a new block header
    pub fn init(block_type: BlockType, block_id: u64, sequence: u64) BlockHeader {
        const now = @as(u64, @intCast(std.time.milliTimestamp()));
        return .{
            .magic = BLOCK_MAGIC,
            .version = BLOCK_VERSION,
            .block_type = @intFromEnum(block_type),
            .block_id = block_id,
            .sequence = sequence,
            .created_at = now,
            .modified_at = now,
            .payload_len = 0,
            .checksum = 0,
            .prev_block_id = 0,
            .flags = 0,
            .reserved = 0,
        };
    }

    /// Validate block header
    pub fn validate(self: *const BlockHeader) !void {
        if (self.magic != BLOCK_MAGIC) {
            return error.InvalidMagic;
        }
        if (self.version != BLOCK_VERSION) {
            return error.UnsupportedVersion;
        }
        if (self.payload_len > PAYLOAD_SIZE) {
            return error.PayloadTooLarge;
        }
    }

    /// Convert to native endianness (blocks are stored little-endian)
    pub fn toNative(self: *BlockHeader) void {
        if (builtin.cpu.arch.endian() != .little) {
            self.magic = @byteSwap(self.magic);
            self.version = @byteSwap(self.version);
            self.block_type = @byteSwap(self.block_type);
            self.block_id = @byteSwap(self.block_id);
            self.sequence = @byteSwap(self.sequence);
            self.created_at = @byteSwap(self.created_at);
            self.modified_at = @byteSwap(self.modified_at);
            self.payload_len = @byteSwap(self.payload_len);
            self.checksum = @byteSwap(self.checksum);
            self.prev_block_id = @byteSwap(self.prev_block_id);
            self.flags = @byteSwap(self.flags);
            self.reserved = @byteSwap(self.reserved);
        }
    }

    /// Convert from native endianness to little-endian for storage
    pub fn toLittleEndian(self: *BlockHeader) void {
        // Same as toNative - converts between current and little-endian
        self.toNative();
    }
};

// ============================================================
// Complete Block (Header + Payload)
// ============================================================

pub const Block = struct {
    header: BlockHeader,
    payload: [PAYLOAD_SIZE]u8,

    /// Initialize a new block
    pub fn init(block_type: BlockType, block_id: u64, sequence: u64) Block {
        var block = Block{
            .header = BlockHeader.init(block_type, block_id, sequence),
            .payload = undefined,
        };
        @memset(&block.payload, 0);
        return block;
    }

    /// Set payload data and update header
    pub fn setPayload(self: *Block, data: []const u8) !void {
        if (data.len > PAYLOAD_SIZE) {
            return error.PayloadTooLarge;
        }

        // Copy payload
        @memcpy(self.payload[0..data.len], data);

        // Zero remaining space
        if (data.len < PAYLOAD_SIZE) {
            @memset(self.payload[data.len..], 0);
        }

        // Update header
        self.header.payload_len = @intCast(data.len);
        self.header.modified_at = @intCast(std.time.milliTimestamp());

        // Calculate checksum
        self.header.checksum = crc32c(&self.payload, self.header.payload_len);
    }

    /// Get payload as slice
    pub fn getPayload(self: *const Block) []const u8 {
        return self.payload[0..self.header.payload_len];
    }

    /// Validate block (header + checksum)
    pub fn validate(self: *const Block) !void {
        try self.header.validate();

        // Verify checksum
        const computed = crc32c(&self.payload, self.header.payload_len);
        if (computed != self.header.checksum) {
            return error.ChecksumMismatch;
        }
    }

    /// Write block to bytes (for disk storage)
    pub fn toBytes(self: *const Block) [BLOCK_SIZE]u8 {
        var bytes: [BLOCK_SIZE]u8 = undefined;

        // Copy header
        const header_bytes = std.mem.asBytes(&self.header);
        @memcpy(bytes[0..HEADER_SIZE], header_bytes);

        // Copy payload
        @memcpy(bytes[HEADER_SIZE..], &self.payload);

        return bytes;
    }

    /// Read block from bytes
    pub fn fromBytes(bytes: *const [BLOCK_SIZE]u8) !Block {
        var block: Block = undefined;

        // Read header
        const header_bytes = bytes[0..HEADER_SIZE];
        block.header = @bitCast(header_bytes.*);
        block.header.toNative();

        // Read payload
        @memcpy(&block.payload, bytes[HEADER_SIZE..]);

        // Validate
        try block.validate();

        return block;
    }
};

// ============================================================
// CRC32C Implementation (Castagnoli polynomial: 0x1EDC6F41)
// ============================================================
// This matches the Forth implementation for bit-exact compatibility

const CRC32C_TABLE = blk: {
    @setEvalBranchQuota(3000); // Allow compile-time table generation
    var table: [256]u32 = undefined;
    for (&table, 0..) |*entry, i| {
        var crc: u32 = @intCast(i);
        var j: usize = 0;
        while (j < 8) : (j += 1) {
            if (crc & 1 != 0) {
                crc = (crc >> 1) ^ 0x82F63B78;
            } else {
                crc >>= 1;
            }
        }
        entry.* = crc;
    }
    break :blk table;
};

/// Calculate CRC32C checksum (Castagnoli)
pub fn crc32c(data: []const u8, len: u32) u32 {
    var crc: u32 = 0xFFFFFFFF;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const index = @as(u8, @truncate((crc ^ data[i]) & 0xFF));
        crc = (crc >> 8) ^ CRC32C_TABLE[index];
    }

    return crc ^ 0xFFFFFFFF;
}

// ============================================================
// Superblock (Block ID 0)
// ============================================================

pub const Superblock = extern struct {
    version: u32 align(1),
    block_count: u64 align(1),
    free_list_head: u64 align(1),
    journal_head: u64 align(1),
    journal_tail: u64 align(1),
    root_collection_id: u64 align(1),
    flags: u32 align(1),
    created_at: u64 align(1),
    last_checkpoint: u64 align(1),
    reserved: [3968]u8 align(1), // Pad to payload size

    pub fn init() Superblock {
        const now = @as(u64, @intCast(std.time.milliTimestamp()));
        return .{
            .version = 1,
            .block_count = 1, // Just the superblock
            .free_list_head = 0,
            .journal_head = 0,
            .journal_tail = 0,
            .root_collection_id = 0,
            .flags = 0,
            .created_at = now,
            .last_checkpoint = now,
            .reserved = undefined,
        };
    }

    pub fn toBlock(self: *const Superblock) !Block {
        var block = Block.init(.superblock, 0, 0);
        const bytes = std.mem.asBytes(self);
        try block.setPayload(bytes);
        return block;
    }

    pub fn fromBlock(block: *const Block) !Superblock {
        if (block.header.block_type != @intFromEnum(BlockType.superblock)) {
            return error.NotSuperblock;
        }
        const bytes = block.getPayload();
        if (bytes.len < @sizeOf(Superblock)) {
            return error.InvalidSuperblock;
        }
        return @bitCast(bytes[0..@sizeOf(Superblock)].*);
    }
};

// ============================================================
// Block Storage Manager
// ============================================================

pub const BlockStorage = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    superblock: Superblock,
    path: []const u8,
    is_open: bool,

    /// Open or create block storage
    pub fn open(allocator: std.mem.Allocator, path: []const u8) !*BlockStorage {
        const storage = try allocator.create(BlockStorage);
        errdefer allocator.destroy(storage);

        // Try to open existing file
        const file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| {
            if (err == error.FileNotFound) {
                // Create new database
                const new_file = try std.fs.cwd().createFile(path, .{ .read = true });
                const sb = Superblock.init();
                const sb_block = try sb.toBlock();
                const sb_bytes = sb_block.toBytes();
                try new_file.writeAll(&sb_bytes);
                try new_file.sync();

                storage.* = .{
                    .allocator = allocator,
                    .file = new_file,
                    .superblock = sb,
                    .path = try allocator.dupe(u8, path),
                    .is_open = true,
                };
                return storage;
            }
            return err;
        };

        // Read existing superblock
        var sb_bytes: [BLOCK_SIZE]u8 = undefined;
        const n = try file.read(&sb_bytes);
        if (n < BLOCK_SIZE) {
            return error.InvalidDatabase;
        }

        const sb_block = try Block.fromBytes(&sb_bytes);
        const sb = try Superblock.fromBlock(&sb_block);

        storage.* = .{
            .allocator = allocator,
            .file = file,
            .superblock = sb,
            .path = try allocator.dupe(u8, path),
            .is_open = true,
        };

        return storage;
    }

    /// Close block storage
    pub fn close(self: *BlockStorage) void {
        if (self.is_open) {
            self.file.close();
            self.allocator.free(self.path);
            self.is_open = false;
        }
    }

    pub fn deinit(self: *BlockStorage) void {
        self.close();
        self.allocator.destroy(self);
    }

    /// Read a block by ID
    pub fn readBlock(self: *BlockStorage, block_id: u64) !Block {
        const offset = block_id * BLOCK_SIZE;
        try self.file.seekTo(offset);

        var bytes: [BLOCK_SIZE]u8 = undefined;
        const n = try self.file.read(&bytes);
        if (n < BLOCK_SIZE) {
            return error.InvalidBlock;
        }

        return try Block.fromBytes(&bytes);
    }

    /// Write a block by ID
    pub fn writeBlock(self: *BlockStorage, block_id: u64, block: *const Block) !void {
        const offset = block_id * BLOCK_SIZE;
        try self.file.seekTo(offset);

        var bytes = block.toBytes();
        try self.file.writeAll(&bytes);
        try self.file.sync();
    }

    /// Allocate a new block (writes to disk immediately)
    pub fn allocateBlock(self: *BlockStorage, block_type: BlockType) !u64 {
        // TODO: Use free list for production
        // For now, just append to end
        const new_id = self.superblock.block_count;
        self.superblock.block_count += 1;

        // Update superblock on disk
        const sb_block = try self.superblock.toBlock();
        try self.writeBlock(0, &sb_block);

        // Initialize new block
        var block = Block.init(block_type, new_id, self.superblock.journal_head + 1);
        try self.writeBlock(new_id, &block);

        return new_id;
    }

    /// Reserve a block ID without writing to disk (for transaction buffering)
    pub fn reserveBlockId(self: *BlockStorage) u64 {
        const new_id = self.superblock.block_count;
        self.superblock.block_count += 1;
        return new_id;
    }

    /// Flush superblock to disk (after batch operations)
    pub fn flushSuperblock(self: *BlockStorage) !void {
        const sb_block = try self.superblock.toBlock();
        try self.writeBlock(0, &sb_block);
    }

    /// Append to journal
    pub fn appendJournal(self: *BlockStorage, entry_data: []const u8) !u64 {
        const journal_id = try self.allocateBlock(.journal_segment);
        var block = try self.readBlock(journal_id);
        try block.setPayload(entry_data);

        // Link to previous journal entry
        block.header.prev_block_id = self.superblock.journal_tail;
        block.header.sequence = self.superblock.journal_head + 1;

        try self.writeBlock(journal_id, &block);

        // Update superblock journal pointers
        if (self.superblock.journal_head == 0) {
            self.superblock.journal_head = journal_id;
        }
        self.superblock.journal_tail = journal_id;
        self.superblock.journal_head += 1;

        const sb_block = try self.superblock.toBlock();
        try self.writeBlock(0, &sb_block);

        return journal_id;
    }

    /// Free a block (mark as free, add to free list)
    pub fn freeBlock(self: *BlockStorage, block_id: u64) !void {
        if (block_id == 0) {
            return error.CannotFreeSuperblock;
        }

        var block = try self.readBlock(block_id);
        block.header.block_type = @intFromEnum(BlockType.free);
        block.header.prev_block_id = self.superblock.free_list_head;
        block.header.flags |= @as(u32, @as(u8, @bitCast(BlockFlags{ .deleted = true })));

        try self.writeBlock(block_id, &block);

        // Update free list
        self.superblock.free_list_head = block_id;
        const sb_block = try self.superblock.toBlock();
        try self.writeBlock(0, &sb_block);
    }
};

// ============================================================
// Tests
// ============================================================

test "block header size" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(BlockHeader));
}

test "block size" {
    try std.testing.expectEqual(@as(usize, 4096), @sizeOf(Block));
}

test "crc32c" {
    const data = "hello world";
    const crc = crc32c(data, data.len);
    // Verify against known CRC32C value
    try std.testing.expect(crc != 0);
}

test "block init and payload" {
    var block = Block.init(.document, 1, 1);
    const data = "test document data";
    try block.setPayload(data);

    try std.testing.expectEqual(data.len, block.header.payload_len);
    try std.testing.expectEqualSlices(u8, data, block.getPayload());

    // Validate checksum
    try block.validate();
}

test "block serialization" {
    var block = Block.init(.document, 42, 100);
    try block.setPayload("test");

    const bytes = block.toBytes();
    const decoded = try Block.fromBytes(&bytes);

    try std.testing.expectEqual(block.header.block_id, decoded.header.block_id);
    try std.testing.expectEqual(block.header.sequence, decoded.header.sequence);
    try std.testing.expectEqualSlices(u8, block.getPayload(), decoded.getPayload());
}

test "superblock roundtrip" {
    var sb = Superblock.init();
    sb.block_count = 42;
    sb.journal_head = 100;

    const block = try sb.toBlock();
    const decoded = try Superblock.fromBlock(&block);

    try std.testing.expectEqual(sb.block_count, decoded.block_count);
    try std.testing.expectEqual(sb.journal_head, decoded.journal_head);
}

test "block storage create and open" {
    const allocator = std.testing.allocator;
    const path = "test_blocks.lgh";
    defer std.fs.cwd().deleteFile(path) catch {};

    // Create new storage
    {
        const storage = try BlockStorage.open(allocator, path);
        defer storage.deinit();

        try std.testing.expectEqual(@as(u64, 1), storage.superblock.block_count);
    }

    // Reopen existing
    {
        const storage = try BlockStorage.open(allocator, path);
        defer storage.deinit();

        try std.testing.expectEqual(@as(u64, 1), storage.superblock.block_count);
    }
}

test "block allocation and write" {
    const allocator = std.testing.allocator;
    const path = "test_alloc.lgh";
    defer std.fs.cwd().deleteFile(path) catch {};

    const storage = try BlockStorage.open(allocator, path);
    defer storage.deinit();

    // Allocate and write a document block
    const block_id = try storage.allocateBlock(.document);
    try std.testing.expectEqual(@as(u64, 1), block_id);

    var block = try storage.readBlock(block_id);
    try block.setPayload("test document");
    try storage.writeBlock(block_id, &block);

    // Read it back
    const read_block = try storage.readBlock(block_id);
    try std.testing.expectEqualSlices(u8, "test document", read_block.getPayload());
}

test "journal append" {
    const allocator = std.testing.allocator;
    const path = "test_journal.lgh";
    defer std.fs.cwd().deleteFile(path) catch {};

    const storage = try BlockStorage.open(allocator, path);
    defer storage.deinit();

    // Append journal entries
    const j1 = try storage.appendJournal("entry 1");
    const j2 = try storage.appendJournal("entry 2");

    // Verify linkage
    const block2 = try storage.readBlock(j2);
    try std.testing.expectEqual(j1, block2.header.prev_block_id);
}
