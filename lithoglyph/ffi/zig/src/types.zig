// SPDX-License-Identifier: PMPL-1.0-or-later
// Form.Bridge - Type Definitions

const std = @import("std");

// ============================================================
// Blob Encoding
// ============================================================

pub const BlobEncoding = enum(u8) {
    cbor = 0,
    cbor_compressed = 1,
    reserved = 255,
};

// ============================================================
// Blob Structure
// ============================================================

pub const FdbBlob = extern struct {
    data: ?[*]const u8,
    len: usize,
    encoding: BlobEncoding,
    _padding: [7]u8 = [_]u8{0} ** 7,

    pub fn empty() FdbBlob {
        return .{
            .data = null,
            .len = 0,
            .encoding = .cbor,
        };
    }

    pub fn fromSlice(slice: []const u8) FdbBlob {
        return .{
            .data = slice.ptr,
            .len = slice.len,
            .encoding = .cbor,
        };
    }

    pub fn toSlice(self: FdbBlob) ?[]const u8 {
        if (self.data) |ptr| {
            return ptr[0..self.len];
        }
        return null;
    }
};

// ============================================================
// Status Codes
// ============================================================

pub const FdbStatus = enum(i32) {
    ok = 0,

    // Database errors (1xxx)
    err_db_not_found = 1001,
    err_db_already_open = 1002,
    err_db_corrupted = 1003,
    err_db_version_mismatch = 1004,

    // Transaction errors (2xxx)
    err_txn_not_active = 2001,
    err_txn_already_committed = 2002,
    err_txn_already_aborted = 2003,
    err_txn_conflict = 2004,

    // Document errors (3xxx)
    err_doc_not_found = 3001,
    err_doc_already_exists = 3002,
    err_doc_validation_failed = 3003,

    // Collection errors (4xxx)
    err_collection_not_found = 4001,
    err_collection_already_exists = 4002,

    // Schema errors (5xxx)
    err_schema_violation = 5001,
    err_constraint_violation = 5002,

    // Internal errors (9xxx)
    err_internal = 9001,
    err_out_of_memory = 9002,
    err_invalid_argument = 9003,
    err_not_implemented = 9004,

    pub fn isOk(self: FdbStatus) bool {
        return self == .ok;
    }

    pub fn isError(self: FdbStatus) bool {
        return @intFromEnum(self) > 0;
    }
};

// ============================================================
// Transaction Mode
// ============================================================

pub const FdbTxnMode = enum(u8) {
    read_only = 0,
    read_write = 1,
};

// ============================================================
// Operation Types
// ============================================================

pub const FdbOpType = enum(u16) {
    // Document operations
    doc_insert = 0x0001,
    doc_update = 0x0002,
    doc_delete = 0x0003,
    doc_replace = 0x0004,

    // Edge operations
    edge_insert = 0x0010,
    edge_delete = 0x0011,
    edge_update = 0x0012,

    // Collection operations
    collection_create = 0x0020,
    collection_drop = 0x0021,

    // Schema operations
    schema_create = 0x0030,
    schema_alter = 0x0031,

    // Constraint operations
    constraint_add = 0x0040,
    constraint_drop = 0x0041,

    // Index operations
    index_create = 0x0050,
    index_drop = 0x0051,

    // Query operations
    query_select = 0x0100,
    query_aggregate = 0x0101,
    query_explain = 0x0102,
};

// ============================================================
// Block Types
// ============================================================

pub const FdbBlockType = enum(u16) {
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

// ============================================================
// CBOR Tags (Lith-specific)
// ============================================================

pub const CborTag = enum(u64) {
    datetime = 0,
    uri = 32,
    self_described = 55799,
    block_reference = 39001,
    document_id = 39002,
    collection_name = 39003,
    provenance = 39004,
    actor = 39005,
    prompt_score = 39006,
    functional_dependency = 39007,
    proof = 39008,
};

// ============================================================
// Render Options
// ============================================================

pub const FdbRenderOpts = extern struct {
    include_provenance: bool = true,
    include_timestamps: bool = true,
    pretty_print: bool = false,
    max_depth: u32 = 10,
    _padding: [3]u8 = [_]u8{0} ** 3,
};

// ============================================================
// Result Structure
// ============================================================

pub const FdbResult = extern struct {
    result_blob: FdbBlob,
    provenance_blob: FdbBlob,
    status: FdbStatus,
    _padding: [4]u8 = [_]u8{0} ** 4,
    err_blob: FdbBlob,

    pub fn ok(result: FdbBlob) FdbResult {
        return .{
            .result_blob = result,
            .provenance_blob = FdbBlob.empty(),
            .status = .ok,
            .err_blob = FdbBlob.empty(),
        };
    }

    pub fn okWithProvenance(result: FdbBlob, provenance: FdbBlob) FdbResult {
        return .{
            .result_blob = result,
            .provenance_blob = provenance,
            .status = .ok,
            .err_blob = FdbBlob.empty(),
        };
    }

    pub fn err(status: FdbStatus, err_blob: FdbBlob) FdbResult {
        return .{
            .result_blob = FdbBlob.empty(),
            .provenance_blob = FdbBlob.empty(),
            .status = status,
            .err_blob = err_blob,
        };
    }
};

// ============================================================
// Tests
// ============================================================

test "FdbBlob empty" {
    const blob = FdbBlob.empty();
    try std.testing.expectEqual(@as(?[*]const u8, null), blob.data);
    try std.testing.expectEqual(@as(usize, 0), blob.len);
}

test "FdbBlob fromSlice" {
    const data = "test data";
    const blob = FdbBlob.fromSlice(data);
    try std.testing.expectEqual(@as(usize, 9), blob.len);

    if (blob.toSlice()) |slice| {
        try std.testing.expectEqualStrings("test data", slice);
    } else {
        try std.testing.expect(false);
    }
}

test "FdbStatus" {
    try std.testing.expect(FdbStatus.ok.isOk());
    try std.testing.expect(!FdbStatus.ok.isError());
    try std.testing.expect(!FdbStatus.err_doc_not_found.isOk());
    try std.testing.expect(FdbStatus.err_doc_not_found.isError());
}
