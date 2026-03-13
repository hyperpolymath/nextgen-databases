// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - Bridge Client
//
// Wraps Form.Bridge FFI calls for the API server, converting between
// JSON (HTTP) and CBOR (bridge) formats.

const std = @import("std");
const config = @import("config.zig");

const log = std.log.scoped(.bridge_client);

// FFI type definitions (matching bridge.zig)
pub const FdbBlob = extern struct {
    ptr: ?[*]const u8,
    len: usize,

    pub fn empty() FdbBlob {
        return .{ .ptr = null, .len = 0 };
    }

    pub fn fromSlice(data: []const u8) FdbBlob {
        return .{ .ptr = data.ptr, .len = data.len };
    }

    pub fn toSlice(self: FdbBlob) ?[]const u8 {
        if (self.ptr) |p| {
            return p[0..self.len];
        }
        return null;
    }
};

pub const FdbStatus = enum(i32) {
    ok = 0,
    err_invalid_argument = -1,
    err_not_found = -2,
    err_io_error = -3,
    err_out_of_memory = -4,
    err_internal = -5,
    err_txn_not_active = -6,
    err_txn_already_committed = -7,
    err_constraint_violation = -8,
    err_not_implemented = -100,
};

pub const FdbResult = extern struct {
    result: FdbBlob,
    provenance: FdbBlob,
    status: FdbStatus,
    error_blob: FdbBlob,
};

pub const FdbTxnMode = enum(u8) {
    read_only = 0,
    read_write = 1,
};

pub const FdbRenderOpts = extern struct {
    include_provenance: bool = true,
    canonical: bool = true,
    pretty: bool = false,
};

// Opaque handles
pub const FdbDb = opaque {};
pub const FdbTxn = opaque {};

// External bridge functions (linked from core-zig)
extern fn fdb_db_open(
    path_ptr: [*]const u8,
    path_len: usize,
    opts_ptr: ?[*]const u8,
    opts_len: usize,
    out_db: *?*FdbDb,
    out_err: *FdbBlob,
) FdbStatus;

extern fn fdb_db_close(db: ?*FdbDb) FdbStatus;

extern fn fdb_txn_begin(
    db: ?*FdbDb,
    mode: FdbTxnMode,
    out_txn: *?*FdbTxn,
    out_err: *FdbBlob,
) FdbStatus;

extern fn fdb_txn_commit(txn: ?*FdbTxn, out_err: *FdbBlob) FdbStatus;
extern fn fdb_txn_abort(txn: ?*FdbTxn) FdbStatus;

extern fn fdb_apply(
    txn: ?*FdbTxn,
    op_ptr: [*]const u8,
    op_len: usize,
) FdbResult;

extern fn fdb_introspect_schema(
    db: ?*FdbDb,
    out_schema: *FdbBlob,
    out_err: *FdbBlob,
) FdbStatus;

extern fn fdb_introspect_constraints(
    db: ?*FdbDb,
    out_constraints: *FdbBlob,
    out_err: *FdbBlob,
) FdbStatus;

extern fn fdb_render_journal(
    db: ?*FdbDb,
    since: u64,
    opts: FdbRenderOpts,
    out_text: *FdbBlob,
    out_err: *FdbBlob,
) FdbStatus;

extern fn fdb_render_block(
    db: ?*FdbDb,
    block_id: u64,
    opts: FdbRenderOpts,
    out_text: *FdbBlob,
    out_err: *FdbBlob,
) FdbStatus;

extern fn fdb_proof_verify(
    proof_ptr: [*]const u8,
    proof_len: usize,
    out_valid: *bool,
    out_err: *FdbBlob,
) FdbStatus;

extern fn fdb_proof_init_builtins() FdbStatus;
extern fn fdb_blob_free(blob: *FdbBlob) void;
extern fn fdb_version() u32;

// =============================================================================
// Bridge Client
// =============================================================================

var allocator: std.mem.Allocator = undefined;
var db_handle: ?*FdbDb = null;
var is_initialized: bool = false;

pub fn init(alloc: std.mem.Allocator, cfg: *const config.Config) !void {
    allocator = alloc;

    // Initialize built-in proof verifiers
    const verifier_status = fdb_proof_init_builtins();
    if (verifier_status != .ok) {
        log.warn("Failed to initialize proof verifiers: {}", .{verifier_status});
    }

    // Open database
    var err_blob: FdbBlob = FdbBlob.empty();
    const status = fdb_db_open(
        cfg.db_path.ptr,
        cfg.db_path.len,
        null,
        0,
        &db_handle,
        &err_blob,
    );

    if (status != .ok) {
        if (err_blob.toSlice()) |err_data| {
            log.err("Failed to open database: {s}", .{err_data});
            fdb_blob_free(&err_blob);
        }
        return error.DatabaseOpenFailed;
    }

    is_initialized = true;
    log.info("Bridge client initialized, database: {s}", .{cfg.db_path});
}

pub fn deinit() void {
    if (db_handle) |db| {
        _ = fdb_db_close(db);
        db_handle = null;
    }
    is_initialized = false;
}

pub fn isInitialized() bool {
    return is_initialized;
}

// =============================================================================
// Query Execution
// =============================================================================

pub const QueryResult = struct {
    data: []const u8,
    provenance: ?[]const u8,
    rows_affected: u64,

    pub fn deinit(self: *QueryResult, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        if (self.provenance) |p| {
            alloc.free(p);
        }
    }
};

pub fn executeQuery(fdql: []const u8, provenance: ?QueryProvenance) !QueryResult {
    if (!is_initialized) {
        return error.NotInitialized;
    }

    // Begin transaction
    var txn: ?*FdbTxn = null;
    var txn_err: FdbBlob = FdbBlob.empty();

    const txn_status = fdb_txn_begin(db_handle, .read_write, &txn, &txn_err);
    if (txn_status != .ok) {
        if (txn_err.toSlice()) |err| {
            log.err("Transaction begin failed: {s}", .{err});
            fdb_blob_free(&txn_err);
        }
        return error.TransactionFailed;
    }
    defer {
        if (txn != null) {
            _ = fdb_txn_abort(txn);
        }
    }

    // Encode operation as CBOR (simplified - just wrap GQL string)
    var op_buffer: [4096]u8 = undefined;
    const op_len = encodeFdqlOperation(&op_buffer, fdql, provenance) catch {
        return error.EncodingFailed;
    };

    // Execute operation
    const result = fdb_apply(txn, &op_buffer, op_len);

    if (result.status != .ok) {
        if (result.error_blob.toSlice()) |err| {
            log.err("Apply failed: {s}", .{err});
        }
        return error.ApplyFailed;
    }

    // Commit transaction
    var commit_err: FdbBlob = FdbBlob.empty();
    const commit_status = fdb_txn_commit(txn, &commit_err);
    txn = null; // Mark as consumed

    if (commit_status != .ok) {
        if (commit_err.toSlice()) |err| {
            log.err("Commit failed: {s}", .{err});
            fdb_blob_free(&commit_err);
        }
        return error.CommitFailed;
    }

    // Convert result to JSON
    const json_data = try cborToJson(allocator, result.result.toSlice() orelse &[_]u8{});
    var prov_json: ?[]const u8 = null;
    if (result.provenance.toSlice()) |prov_cbor| {
        prov_json = cborToJson(allocator, prov_cbor) catch null;
    }

    return QueryResult{
        .data = json_data,
        .provenance = prov_json,
        .rows_affected = 1, // Placeholder
    };
}

pub const QueryProvenance = struct {
    actor: ?[]const u8 = null,
    rationale: ?[]const u8 = null,
};

// =============================================================================
// Schema Operations
// =============================================================================

pub const CollectionInfo = struct {
    name: []const u8,
    schema_version: u32,
    document_count: u64,
};

pub fn listCollections() ![]CollectionInfo {
    if (!is_initialized) {
        return error.NotInitialized;
    }

    var schema_blob: FdbBlob = FdbBlob.empty();
    var err_blob: FdbBlob = FdbBlob.empty();

    const status = fdb_introspect_schema(db_handle, &schema_blob, &err_blob);
    if (status != .ok) {
        if (err_blob.toSlice()) |err| {
            log.err("Schema introspection failed: {s}", .{err});
            fdb_blob_free(&err_blob);
        }
        return error.IntrospectionFailed;
    }
    defer fdb_blob_free(&schema_blob);

    // Parse CBOR schema response (placeholder - return empty list)
    const collections = try allocator.alloc(CollectionInfo, 0);
    return collections;
}

pub fn getCollection(name: []const u8) !?CollectionInfo {
    const collections = try listCollections();
    defer allocator.free(collections);

    for (collections) |col| {
        if (std.mem.eql(u8, col.name, name)) {
            return col;
        }
    }
    return null;
}

pub fn createCollection(name: []const u8, schema_json: []const u8) !void {
    _ = name;
    _ = schema_json;
    // Create collection via GQL CREATE COLLECTION statement
    // For now, placeholder
    return error.NotImplemented;
}

pub fn dropCollection(name: []const u8) !void {
    _ = name;
    // Drop collection via GQL DROP COLLECTION statement
    // For now, placeholder
    return error.NotImplemented;
}

// =============================================================================
// Journal Operations
// =============================================================================

pub const JournalEntry = struct {
    sequence: u64,
    timestamp: []const u8,
    operation: []const u8,
    collection: ?[]const u8,
    actor: ?[]const u8,
};

pub fn getJournal(since: u64, limit: u32) ![]JournalEntry {
    if (!is_initialized) {
        return error.NotInitialized;
    }

    var journal_blob: FdbBlob = FdbBlob.empty();
    var err_blob: FdbBlob = FdbBlob.empty();

    const opts = FdbRenderOpts{
        .include_provenance = true,
        .canonical = true,
        .pretty = false,
    };

    const status = fdb_render_journal(db_handle, since, opts, &journal_blob, &err_blob);
    if (status != .ok) {
        if (err_blob.toSlice()) |err| {
            log.err("Journal render failed: {s}", .{err});
            fdb_blob_free(&err_blob);
        }
        return error.JournalRenderFailed;
    }
    defer fdb_blob_free(&journal_blob);

    // Parse CBOR journal response (placeholder - return empty list)
    _ = limit;
    const entries = try allocator.alloc(JournalEntry, 0);
    return entries;
}

// =============================================================================
// Normalization Operations
// =============================================================================

pub const FunctionalDependency = struct {
    determinant: []const []const u8,
    dependent: []const u8,
    confidence: f32,
};

pub const NormalFormAnalysis = struct {
    current_form: []const u8,
    violations: []const []const u8,
    suggestions: []const []const u8,
};

pub fn discoverDependencies(collection: []const u8, sample_size: u32) ![]FunctionalDependency {
    _ = collection;
    _ = sample_size;
    // Calls Form.Normalizer via bridge
    return error.NotImplemented;
}

pub fn analyzeNormalForm(collection: []const u8) !NormalFormAnalysis {
    _ = collection;
    return error.NotImplemented;
}

// =============================================================================
// Migration Operations
// =============================================================================

pub const MigrationState = enum {
    announced,
    shadow_running,
    shadow_complete,
    committed,
    aborted,
};

pub const Migration = struct {
    id: []const u8,
    state: MigrationState,
    source_collection: []const u8,
    target_schema: []const u8,
    created_at: []const u8,
};

pub fn startMigration(source: []const u8, target_schema: []const u8) !Migration {
    _ = source;
    _ = target_schema;
    return error.NotImplemented;
}

pub fn getMigration(id: []const u8) !?Migration {
    _ = id;
    return error.NotImplemented;
}

pub fn advanceMigration(id: []const u8, action: MigrationAction) !void {
    _ = id;
    _ = action;
    return error.NotImplemented;
}

pub const MigrationAction = enum {
    start_shadow,
    commit,
    abort,
};

// =============================================================================
// Health Check
// =============================================================================

pub const HealthStatus = struct {
    status: []const u8,
    version: []const u8,
    uptime_seconds: u64,
    journal_head: u64,
    collections_count: u32,
};

pub fn getHealth() HealthStatus {
    const version_num = fdb_version();
    const major = version_num / 10000;
    const minor = (version_num % 10000) / 100;
    const patch = version_num % 100;

    var version_buf: [32]u8 = undefined;
    const version_str = std.fmt.bufPrint(&version_buf, "{}.{}.{}", .{ major, minor, patch }) catch "0.0.0";

    return HealthStatus{
        .status = if (is_initialized) "healthy" else "degraded",
        .version = version_str,
        .uptime_seconds = 0, // Would need to track start time
        .journal_head = 0, // Would need to query from db
        .collections_count = 0,
    };
}

// =============================================================================
// CBOR Encoding/Decoding Helpers
// =============================================================================

fn encodeFdqlOperation(buffer: []u8, fdql: []const u8, prov: ?QueryProvenance) !usize {
    // Simplified CBOR encoding for GQL operation
    // In production, would use proper CBOR encoder

    // CBOR map with 2-3 entries
    var offset: usize = 0;

    // Map header (0xa2 = map of 2 items, 0xa3 = map of 3 items)
    const has_prov = prov != null and (prov.?.actor != null or prov.?.rationale != null);
    buffer[offset] = if (has_prov) 0xa3 else 0xa2;
    offset += 1;

    // Key: "op"
    buffer[offset] = 0x62; // text of 2 bytes
    offset += 1;
    buffer[offset] = 'o';
    offset += 1;
    buffer[offset] = 'p';
    offset += 1;

    // Value: "query"
    buffer[offset] = 0x65; // text of 5 bytes
    offset += 1;
    @memcpy(buffer[offset .. offset + 5], "query");
    offset += 5;

    // Key: "fdql"
    buffer[offset] = 0x64; // text of 4 bytes
    offset += 1;
    @memcpy(buffer[offset .. offset + 4], "fdql");
    offset += 4;

    // Value: fdql string
    if (fdql.len < 24) {
        buffer[offset] = @as(u8, 0x60) + @as(u8, @intCast(fdql.len));
        offset += 1;
    } else if (fdql.len < 256) {
        buffer[offset] = 0x78; // text with 1-byte length
        offset += 1;
        buffer[offset] = @intCast(fdql.len);
        offset += 1;
    } else {
        buffer[offset] = 0x79; // text with 2-byte length
        offset += 1;
        buffer[offset] = @intCast(fdql.len >> 8);
        offset += 1;
        buffer[offset] = @intCast(fdql.len & 0xFF);
        offset += 1;
    }
    @memcpy(buffer[offset .. offset + fdql.len], fdql);
    offset += fdql.len;

    // Optional provenance
    if (has_prov) {
        // Key: "prov"
        buffer[offset] = 0x64;
        offset += 1;
        @memcpy(buffer[offset .. offset + 4], "prov");
        offset += 4;

        // Value: map with actor/rationale (simplified)
        buffer[offset] = 0xa0; // empty map for now
        offset += 1;
    }

    return offset;
}

fn cborToJson(alloc: std.mem.Allocator, cbor_data: []const u8) ![]const u8 {
    // Simplified CBOR to JSON conversion
    // In production, would use proper CBOR decoder

    if (cbor_data.len == 0) {
        return try alloc.dupe(u8, "{}");
    }

    // For PoC, return placeholder JSON based on first byte
    const first = cbor_data[0];

    if (first >= 0xa0 and first <= 0xbf) {
        // Map - return as object
        return try alloc.dupe(u8, "{\"status\":\"ok\"}");
    } else if (first >= 0x80 and first <= 0x9f) {
        // Array
        return try alloc.dupe(u8, "[]");
    } else {
        return try alloc.dupe(u8, "{}");
    }
}

// =============================================================================
// Tests
// =============================================================================

test "health check without init" {
    const health = getHealth();
    try std.testing.expectEqualStrings("degraded", health.status);
}

test "query without init fails" {
    const result = executeQuery("SELECT * FROM test", null);
    try std.testing.expectError(error.NotInitialized, result);
}
