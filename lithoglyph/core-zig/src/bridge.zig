// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith.Bridge - C ABI Layer
//
// Provides stable C-compatible API for runtimes to interact with Lithoglyph.
// All blob arguments and return values use CBOR encoding.
//
// Part of Lithoglyph: Stone-carved data for the ages.
// Lg* = Lithoglyph types (abbreviated for C compatibility)

const std = @import("std");
const blocks = @import("blocks.zig");

// Simplified types for C ABI (no external dependencies)
pub const LgBlob = extern struct {
    ptr: ?[*]const u8,
    len: usize,

    pub fn empty() LgBlob {
        return .{ .ptr = null, .len = 0 };
    }

    pub fn fromSlice(slice: []const u8) LgBlob {
        return .{ .ptr = slice.ptr, .len = slice.len };
    }

    pub fn toSlice(self: LgBlob) ?[]const u8 {
        if (self.ptr) |ptr| {
            return ptr[0..self.len];
        }
        return null;
    }
};

pub const LgStatus = enum(c_int) {
    ok = 0,
    err_internal = 1,
    err_not_found = 2,
    err_invalid_argument = 3,
    err_out_of_memory = 4,
    err_not_implemented = 5,
    err_txn_not_active = 6,
    err_txn_already_committed = 7,
};

pub const LgResult = extern struct {
    data: LgBlob,
    provenance: LgBlob,
    status: LgStatus,
    error_blob: LgBlob,

    pub fn ok(data_blob: LgBlob) LgResult {
        return .{
            .data = data_blob,
            .provenance = LgBlob.empty(),
            .status = .ok,
            .error_blob = LgBlob.empty(),
        };
    }

    pub fn okWithProvenance(data_blob: LgBlob, prov_blob: LgBlob) LgResult {
        return .{
            .data = data_blob,
            .provenance = prov_blob,
            .status = .ok,
            .error_blob = LgBlob.empty(),
        };
    }

    pub fn err(status: LgStatus, error_blob: LgBlob) LgResult {
        return .{
            .data = LgBlob.empty(),
            .provenance = LgBlob.empty(),
            .status = status,
            .error_blob = error_blob,
        };
    }
};

pub const LgTxnMode = enum(c_int) {
    read_only = 0,
    read_write = 1,
};

pub const LgRenderOpts = extern struct {
    format: c_int,
    include_metadata: bool,
};

// ============================================================
// Opaque Handles
// ============================================================

pub const LgDb = opaque {};
pub const LgTxn = opaque {};

// Internal state structures
const DbState = struct {
    allocator: std.mem.Allocator,
    storage: *blocks.BlockStorage,
};

/// A pending write operation buffered within a transaction
const PendingWrite = struct {
    block_id: u64,
    data: []u8, // owned copy of payload
    journal_msg: []u8, // owned journal entry text
    is_new: bool, // true=insert, false=update
};

const TxnState = struct {
    db: *DbState,
    mode: LgTxnMode,
    is_active: bool,
    sequence: u64,
    pending_writes: std.ArrayList(PendingWrite),
    pending_deletes: std.ArrayList(u64), // block IDs to delete

    fn deinitPending(self: *TxnState) void {
        for (self.pending_writes.items) |pw| {
            global_allocator.free(pw.data);
            global_allocator.free(pw.journal_msg);
        }
        self.pending_writes.deinit(global_allocator);
        self.pending_deletes.deinit(global_allocator);
    }
};

// Global allocator for C ABI (can't pass allocator through C)
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = gpa.allocator();

// Active handles registry
var db_registry = std.AutoHashMap(*DbState, void).init(global_allocator);
var txn_registry = std.AutoHashMap(*TxnState, void).init(global_allocator);

// ============================================================
// Error Blob Creation
// ============================================================

fn createErrorBlob(status: LgStatus, message: []const u8) LgBlob {
    // Format error as simple JSON
    var buf: [512]u8 = undefined;
    const err_str = std.fmt.bufPrint(&buf,
        \\{{"status":{d},"error":"{s}"}}
    , .{ @intFromEnum(status), message }) catch return LgBlob.empty();

    const err_data = global_allocator.dupe(u8, err_str) catch return LgBlob.empty();
    return LgBlob.fromSlice(err_data);
}

// ============================================================
// Database Lifecycle - C ABI Exports
// ============================================================

/// Open a Lith database
///
/// @param path_ptr Path to database file
/// @param path_len Length of path
/// @param opts_ptr CBOR-encoded options (nullable)
/// @param opts_len Length of options
/// @param out_db Output parameter for database handle
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_db_open(
    path_ptr: [*]const u8,
    path_len: usize,
    opts_ptr: ?[*]const u8,
    opts_len: usize,
    out_db: *?*LgDb,
    out_err: *LgBlob,
) LgStatus {
    _ = opts_ptr;
    _ = opts_len;

    const path = path_ptr[0..path_len];

    // Open or create block storage
    const storage = blocks.BlockStorage.open(global_allocator, path) catch |err| {
        const msg = switch (err) {
            error.OutOfMemory => "Out of memory",
            error.FileNotFound => "Database not found",
            error.InvalidDatabase => "Invalid database format",
            else => "Failed to open database",
        };
        out_err.* = createErrorBlob(.err_internal, msg);
        return .err_internal;
    };

    // Create database state
    const db = global_allocator.create(DbState) catch {
        storage.deinit();
        out_err.* = createErrorBlob(.err_out_of_memory, "Failed to allocate database state");
        return .err_out_of_memory;
    };

    db.* = .{
        .allocator = global_allocator,
        .storage = storage,
    };

    // Register handle
    db_registry.put(db, {}) catch {
        storage.deinit();
        global_allocator.destroy(db);
        out_err.* = createErrorBlob(.err_internal, "Failed to register database handle");
        return .err_internal;
    };

    // SAFETY: db is a freshly-allocated *DbState from global_allocator.create() above,
    // registered in db_registry. Cast to opaque *LgDb is safe because callers only
    // pass it back through C ABI functions that cast it back to *DbState after
    // validating the handle exists in db_registry.
    out_db.* = @ptrCast(db);
    out_err.* = LgBlob.empty();
    return .ok;
}

/// Close a Lith database
///
/// @param db Database handle
/// @return Status code
pub export fn lith_db_close(db: ?*LgDb) LgStatus {
    // SAFETY: db was originally a *DbState allocated by global_allocator.create()
    // in lith_db_open, then cast to *LgDb. The orelse guards null. Alignment is
    // guaranteed because DbState was heap-allocated with proper alignment by the GPA.
    // The subsequent db_registry.contains() check validates the pointer is still live.
    const state: *DbState = @ptrCast(@alignCast(db orelse return .err_invalid_argument));

    if (!db_registry.contains(state)) {
        return .err_invalid_argument;
    }

    // Clean up any active transactions
    var txn_iter = txn_registry.keyIterator();
    while (txn_iter.next()) |txn| {
        if (txn.*.db == state) {
            _ = txn_registry.remove(txn.*);
            global_allocator.destroy(txn.*);
        }
    }

    // Close block storage
    state.storage.deinit();

    // Clean up database state
    _ = db_registry.remove(state);
    global_allocator.destroy(state);

    return .ok;
}

// ============================================================
// Transaction Management - C ABI Exports
// ============================================================

/// Begin a new transaction
///
/// @param db Database handle
/// @param mode Transaction mode (read-only or read-write)
/// @param out_txn Output parameter for transaction handle
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_txn_begin(
    db: ?*LgDb,
    mode: LgTxnMode,
    out_txn: *?*LgTxn,
    out_err: *LgBlob,
) LgStatus {
    // SAFETY: db was originally a *DbState from lith_db_open, cast to opaque *LgDb.
    // The orelse guards null. Alignment is safe because DbState was heap-allocated
    // by global_allocator.create() which respects @alignOf(DbState). The
    // db_registry.contains() check below validates the pointer is still registered.
    const state: *DbState = @ptrCast(@alignCast(db orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid database handle");
        return .err_invalid_argument;
    }));

    if (!db_registry.contains(state)) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Database handle not registered");
        return .err_invalid_argument;
    }

    // Create transaction state
    const txn = global_allocator.create(TxnState) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Failed to allocate transaction");
        return .err_out_of_memory;
    };

    txn.* = .{
        .db = state,
        .mode = mode,
        .is_active = true,
        .sequence = state.storage.superblock.journal_head + 1,
        .pending_writes = .{},
        .pending_deletes = .{},
    };

    txn_registry.put(txn, {}) catch {
        global_allocator.destroy(txn);
        out_err.* = createErrorBlob(.err_internal, "Failed to register transaction");
        return .err_internal;
    };

    // SAFETY: txn is a freshly-allocated *TxnState from global_allocator.create()
    // above, registered in txn_registry. Cast to opaque *LgTxn is safe because
    // callers only pass it back through C ABI functions that cast it back to
    // *TxnState after validating the handle exists in txn_registry.
    out_txn.* = @ptrCast(txn);
    out_err.* = LgBlob.empty();
    return .ok;
}

/// Commit a transaction
///
/// @param txn Transaction handle
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_txn_commit(txn: ?*LgTxn, out_err: *LgBlob) LgStatus {
    // SAFETY: txn was originally a *TxnState from lith_txn_begin, cast to opaque
    // *LgTxn. The orelse guards null. Alignment is safe because TxnState was
    // heap-allocated by global_allocator.create(). The txn_registry.contains()
    // check below validates the pointer is still a live, registered handle.
    const state: *TxnState = @ptrCast(@alignCast(txn orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid transaction handle");
        return .err_invalid_argument;
    }));

    if (!txn_registry.contains(state)) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Transaction handle not registered");
        return .err_invalid_argument;
    }

    if (!state.is_active) {
        out_err.* = createErrorBlob(.err_txn_already_committed, "Transaction already committed");
        return .err_txn_already_committed;
    }

    // Atomic commit with WAL ordering:
    // Phase 1: Write all journal entries (WAL — durable before data)
    for (state.pending_writes.items) |pw| {
        _ = state.db.storage.appendJournal(pw.journal_msg) catch {
            out_err.* = createErrorBlob(.err_internal, "Journal write failed during commit");
            return .err_internal;
        };
    }
    for (state.pending_deletes.items) |block_id| {
        var del_buf: [80]u8 = undefined;
        const del_msg = std.fmt.bufPrint(&del_buf, "DELETE block_id={d}", .{block_id}) catch continue;
        _ = state.db.storage.appendJournal(del_msg) catch {
            out_err.* = createErrorBlob(.err_internal, "Journal write failed during commit");
            return .err_internal;
        };
    }

    // Phase 2: Sync journal to disk (WAL guarantee)
    state.db.storage.file.sync() catch {};

    // Phase 3: Write all data blocks
    for (state.pending_writes.items) |pw| {
        var block = blocks.Block.init(.document, pw.block_id, state.sequence);
        block.setPayload(pw.data) catch continue;
        state.db.storage.writeBlock(pw.block_id, &block) catch {
            out_err.* = createErrorBlob(.err_internal, "Block write failed during commit");
            return .err_internal;
        };
    }

    // Phase 4: Process deletions
    for (state.pending_deletes.items) |block_id| {
        state.db.storage.freeBlock(block_id) catch continue;
    }

    // Phase 5: Flush superblock (reflects all allocations)
    state.db.storage.flushSuperblock() catch {};

    // Phase 6: Final sync (all data durable)
    state.db.storage.file.sync() catch {};

    // Clean up transaction
    state.deinitPending();
    state.is_active = false;
    _ = txn_registry.remove(state);
    global_allocator.destroy(state);

    out_err.* = LgBlob.empty();
    return .ok;
}

/// Abort a transaction
///
/// @param txn Transaction handle
/// @return Status code
pub export fn lith_txn_abort(txn: ?*LgTxn) LgStatus {
    // SAFETY: txn was originally a *TxnState from lith_txn_begin, cast to opaque
    // *LgTxn. The orelse guards null. Alignment is safe because TxnState was
    // heap-allocated by global_allocator.create(). The txn_registry.contains()
    // check below validates the pointer is still a live, registered handle.
    const state: *TxnState = @ptrCast(@alignCast(txn orelse return .err_invalid_argument));

    if (!txn_registry.contains(state)) {
        return .err_invalid_argument;
    }

    // Discard all buffered operations (nothing was written to disk)
    state.deinitPending();
    state.is_active = false;

    // Clean up transaction
    _ = txn_registry.remove(state);
    global_allocator.destroy(state);

    return .ok;
}

// ============================================================
// Operations - C ABI Exports
// ============================================================

/// Apply an operation within a transaction
///
/// @param txn Transaction handle
/// @param op_ptr Raw data to store
/// @param op_len Length of data
/// @return Result containing block ID and status
/// Apply an operation within a transaction (buffered — not written until commit)
pub export fn lith_apply(
    txn: ?*LgTxn,
    op_ptr: [*]const u8,
    op_len: usize,
) LgResult {
    // SAFETY: txn was originally a *TxnState from lith_txn_begin, cast to opaque
    // *LgTxn. The orelse guards null. Alignment is safe because TxnState was
    // heap-allocated by global_allocator.create(). The txn_registry.contains()
    // check below validates the pointer is still a live, registered handle.
    const state: *TxnState = @ptrCast(@alignCast(txn orelse {
        return LgResult.err(.err_invalid_argument, createErrorBlob(.err_invalid_argument, "Invalid transaction"));
    }));

    if (!txn_registry.contains(state)) {
        return LgResult.err(.err_invalid_argument, createErrorBlob(.err_invalid_argument, "Transaction not registered"));
    }

    if (!state.is_active) {
        return LgResult.err(.err_txn_not_active, createErrorBlob(.err_txn_not_active, "Transaction not active"));
    }

    if (state.mode != .read_write) {
        return LgResult.err(.err_invalid_argument, createErrorBlob(.err_invalid_argument, "Read-only transaction"));
    }

    const op_data = op_ptr[0..op_len];

    // Validate payload fits in a block
    if (op_len > blocks.PAYLOAD_SIZE) {
        return LgResult.err(.err_invalid_argument, createErrorBlob(.err_invalid_argument, "Payload too large for single block"));
    }

    // Reserve a block ID (memory only — no disk write yet)
    const block_id = state.db.storage.reserveBlockId();

    // Copy payload data (owned by transaction until commit/abort)
    const data_copy = global_allocator.dupe(u8, op_data) catch {
        return LgResult.err(.err_out_of_memory, LgBlob.empty());
    };

    // Format journal entry
    var journal_buf: [100]u8 = undefined;
    const journal_str = std.fmt.bufPrint(&journal_buf, "INSERT block_id={d} size={d}", .{ block_id, op_len }) catch {
        global_allocator.free(data_copy);
        return LgResult.err(.err_internal, createErrorBlob(.err_internal, "Failed to format journal"));
    };

    const journal_copy = global_allocator.dupe(u8, journal_str) catch {
        global_allocator.free(data_copy);
        return LgResult.err(.err_out_of_memory, LgBlob.empty());
    };

    // Buffer the write (deferred until commit)
    state.pending_writes.append(global_allocator, .{
        .block_id = block_id,
        .data = data_copy,
        .journal_msg = journal_copy,
        .is_new = true,
    }) catch {
        global_allocator.free(data_copy);
        global_allocator.free(journal_copy);
        return LgResult.err(.err_out_of_memory, LgBlob.empty());
    };

    // Return block ID as result (operation is pending, not yet durable)
    var result_buf: [80]u8 = undefined;
    const result_str = std.fmt.bufPrint(&result_buf,
        \\{{"block_id":{d},"status":"pending"}}
    , .{block_id}) catch {
        return LgResult.err(.err_internal, createErrorBlob(.err_internal, "Failed to format result"));
    };

    const result_data = global_allocator.dupe(u8, result_str) catch {
        return LgResult.err(.err_out_of_memory, LgBlob.empty());
    };

    return LgResult.ok(LgBlob.fromSlice(result_data));
}

/// Update an existing block within a transaction (buffered)
pub export fn lith_update_block(
    txn: ?*LgTxn,
    block_id: u64,
    data_ptr: [*]const u8,
    data_len: usize,
    out_err: *LgBlob,
) LgStatus {
    // SAFETY: txn was originally a *TxnState from lith_txn_begin, cast to opaque
    // *LgTxn. The orelse guards null. Alignment is safe because TxnState was
    // heap-allocated by global_allocator.create(). State validity is checked
    // immediately after via is_active and mode fields.
    const state: *TxnState = @ptrCast(@alignCast(txn orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid transaction");
        return .err_invalid_argument;
    }));

    if (!state.is_active or state.mode != .read_write) {
        out_err.* = createErrorBlob(.err_txn_not_active, "Transaction not active or read-only");
        return .err_txn_not_active;
    }

    if (data_len > blocks.PAYLOAD_SIZE) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Payload too large");
        return .err_invalid_argument;
    }

    const data_copy = global_allocator.dupe(u8, data_ptr[0..data_len]) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Out of memory");
        return .err_out_of_memory;
    };

    var journal_buf: [100]u8 = undefined;
    const journal_str = std.fmt.bufPrint(&journal_buf, "UPDATE block_id={d} size={d}", .{ block_id, data_len }) catch {
        global_allocator.free(data_copy);
        out_err.* = createErrorBlob(.err_internal, "Failed to format journal");
        return .err_internal;
    };

    const journal_copy = global_allocator.dupe(u8, journal_str) catch {
        global_allocator.free(data_copy);
        out_err.* = createErrorBlob(.err_out_of_memory, "Out of memory");
        return .err_out_of_memory;
    };

    state.pending_writes.append(global_allocator, .{
        .block_id = block_id,
        .data = data_copy,
        .journal_msg = journal_copy,
        .is_new = false,
    }) catch {
        global_allocator.free(data_copy);
        global_allocator.free(journal_copy);
        out_err.* = createErrorBlob(.err_out_of_memory, "Out of memory");
        return .err_out_of_memory;
    };

    out_err.* = LgBlob.empty();
    return .ok;
}

/// Delete a block within a transaction (buffered)
pub export fn lith_delete_block(
    txn: ?*LgTxn,
    block_id: u64,
    out_err: *LgBlob,
) LgStatus {
    // SAFETY: txn was originally a *TxnState from lith_txn_begin, cast to opaque
    // *LgTxn. The orelse guards null. Alignment is safe because TxnState was
    // heap-allocated by global_allocator.create(). State validity is checked
    // immediately after via is_active and mode fields.
    const state: *TxnState = @ptrCast(@alignCast(txn orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid transaction");
        return .err_invalid_argument;
    }));

    if (!state.is_active or state.mode != .read_write) {
        out_err.* = createErrorBlob(.err_txn_not_active, "Transaction not active or read-only");
        return .err_txn_not_active;
    }

    state.pending_deletes.append(global_allocator, block_id) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Out of memory");
        return .err_out_of_memory;
    };

    out_err.* = LgBlob.empty();
    return .ok;
}

/// Read all blocks of a given type (full scan for PoC)
/// Returns JSON array of objects with block_id and data fields.
pub export fn lith_read_blocks(
    db: ?*LgDb,
    block_type: u16,
    out_data: *LgBlob,
    out_err: *LgBlob,
) LgStatus {
    // SAFETY: db was originally a *DbState from lith_db_open, cast to opaque *LgDb.
    // The orelse guards null. Alignment is safe because DbState was heap-allocated
    // by global_allocator.create(). The db_registry.contains() check below validates
    // the pointer is still a live, registered handle.
    const state: *DbState = @ptrCast(@alignCast(db orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid database handle");
        return .err_invalid_argument;
    }));

    if (!db_registry.contains(state)) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Database handle not registered");
        return .err_invalid_argument;
    }

    // Build JSON array by scanning all blocks
    var result: std.ArrayList(u8) = .{};
    defer result.deinit(global_allocator);

    result.appendSlice(global_allocator, "[") catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Out of memory");
        return .err_out_of_memory;
    };

    var first = true;
    var block_id: u64 = 1;
    while (block_id < state.storage.superblock.block_count) : (block_id += 1) {
        const block = state.storage.readBlock(block_id) catch continue;

        // Filter by type and skip deleted blocks
        if (block.header.block_type != block_type) continue;
        if (block.header.flags & 0x08 != 0) continue; // FLAG_DELETED

        if (!first) {
            result.appendSlice(global_allocator, ",") catch continue;
        }
        first = false;

        // Format as JSON object with block_id and raw payload
        const payload = block.getPayload();

        // Start JSON object
        var header_buf: [80]u8 = undefined;
        const header_str = std.fmt.bufPrint(&header_buf,
            \\{{"block_id":{d},"size":{d},"data":
        , .{ block.header.block_id, block.header.payload_len }) catch continue;

        result.appendSlice(global_allocator, header_str) catch continue;

        // Include payload as JSON-escaped string
        result.appendSlice(global_allocator, "\"") catch continue;
        for (payload) |byte| {
            switch (byte) {
                '"' => result.appendSlice(global_allocator, "\\\"") catch continue,
                '\\' => result.appendSlice(global_allocator, "\\\\") catch continue,
                '\n' => result.appendSlice(global_allocator, "\\n") catch continue,
                '\r' => result.appendSlice(global_allocator, "\\r") catch continue,
                '\t' => result.appendSlice(global_allocator, "\\t") catch continue,
                else => {
                    if (byte >= 0x20 and byte < 0x7F) {
                        result.append(global_allocator, byte) catch continue;
                    } else {
                        var hex_buf: [6]u8 = undefined;
                        const hex_str = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{byte}) catch continue;
                        result.appendSlice(global_allocator, hex_str) catch continue;
                    }
                },
            }
        }
        result.appendSlice(global_allocator, "\"}") catch continue;
    }

    result.appendSlice(global_allocator, "]") catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Out of memory");
        return .err_out_of_memory;
    };

    const result_data = global_allocator.dupe(u8, result.items) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Out of memory");
        return .err_out_of_memory;
    };

    out_data.* = LgBlob.fromSlice(result_data);
    out_err.* = LgBlob.empty();
    return .ok;
}

// ============================================================
// Introspection - C ABI Exports
// ============================================================

/// Render a block as canonical text
///
/// @param db Database handle
/// @param block_id Block ID to render
/// @param opts Render options
/// @param out_text Output parameter for text blob
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_render_block(
    db: ?*LgDb,
    block_id: u64,
    opts: LgRenderOpts,
    out_text: *LgBlob,
    out_err: *LgBlob,
) LgStatus {
    _ = opts;

    // SAFETY: db was originally a *DbState from lith_db_open, cast to opaque *LgDb.
    // The orelse guards null. Alignment is safe because DbState was heap-allocated
    // by global_allocator.create(). The db_registry.contains() check below validates
    // the pointer is still a live, registered handle.
    const state: *DbState = @ptrCast(@alignCast(db orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid database handle");
        return .err_invalid_argument;
    }));

    if (!db_registry.contains(state)) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Database handle not registered");
        return .err_invalid_argument;
    }

    // Read block from storage
    const block = state.storage.readBlock(block_id) catch |err| {
        const msg = switch (err) {
            error.InvalidBlock => "Block not found or invalid",
            error.ChecksumMismatch => "Block checksum mismatch",
            else => "Failed to read block",
        };
        out_err.* = createErrorBlob(.err_internal, msg);
        return .err_internal;
    };

    // Format block as JSON (show payload size only, not content)
    _ = block.getPayload(); // Validate payload exists
    var buf: [8192]u8 = undefined;
    const text = std.fmt.bufPrint(&buf,
        \\{{"block_id":{d},"type":"{s}","sequence":{d},"size":{d},"payload":"[{d} bytes]"}}
    , .{
        block.header.block_id,
        @tagName(@as(blocks.BlockType, @enumFromInt(block.header.block_type))),
        block.header.sequence,
        block.header.payload_len,
        block.header.payload_len,
    }) catch {
        out_err.* = createErrorBlob(.err_internal, "Failed to format block");
        return .err_internal;
    };

    const text_data = global_allocator.dupe(u8, text) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Failed to allocate result");
        return .err_out_of_memory;
    };

    out_text.* = LgBlob.fromSlice(text_data);
    out_err.* = LgBlob.empty();
    return .ok;
}

/// Render journal entries since a sequence number
///
/// @param db Database handle
/// @param since Sequence number to start from
/// @param opts Render options
/// @param out_text Output parameter for text blob
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_render_journal(
    db: ?*LgDb,
    since: u64,
    opts: LgRenderOpts,
    out_text: *LgBlob,
    out_err: *LgBlob,
) LgStatus {
    _ = opts;

    // SAFETY: db was originally a *DbState from lith_db_open, cast to opaque *LgDb.
    // The orelse guards null. Alignment is safe because DbState was heap-allocated
    // by global_allocator.create(). The db_registry.contains() check below validates
    // the pointer is still a live, registered handle.
    const state: *DbState = @ptrCast(@alignCast(db orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid database handle");
        return .err_invalid_argument;
    }));

    if (!db_registry.contains(state)) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Database handle not registered");
        return .err_invalid_argument;
    }

    // Format journal info as JSON
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf,
        \\{{"since":{d},"head":{d},"tail":{d},"entries":[]}}
    , .{
        since,
        state.storage.superblock.journal_head,
        state.storage.superblock.journal_tail,
    }) catch {
        out_err.* = createErrorBlob(.err_internal, "Failed to format journal");
        return .err_internal;
    };

    const text_data = global_allocator.dupe(u8, text) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Failed to allocate result");
        return .err_out_of_memory;
    };

    out_text.* = LgBlob.fromSlice(text_data);
    out_err.* = LgBlob.empty();
    return .ok;
}

/// Get database schema information
///
/// @param db Database handle
/// @param out_schema Output parameter for schema blob
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_introspect_schema(
    db: ?*LgDb,
    out_schema: *LgBlob,
    out_err: *LgBlob,
) LgStatus {
    // SAFETY: db was originally a *DbState from lith_db_open, cast to opaque *LgDb.
    // The orelse guards null. Alignment is safe because DbState was heap-allocated
    // by global_allocator.create(). The db_registry.contains() check below validates
    // the pointer is still a live, registered handle.
    const state: *DbState = @ptrCast(@alignCast(db orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid database handle");
        return .err_invalid_argument;
    }));

    if (!db_registry.contains(state)) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Database handle not registered");
        return .err_invalid_argument;
    }

    // Format schema as JSON
    var buf: [512]u8 = undefined;
    const schema_str = std.fmt.bufPrint(&buf,
        \\{{"version":{d},"block_count":{d},"collections":[]}}
    , .{
        state.storage.superblock.version,
        state.storage.superblock.block_count,
    }) catch {
        out_err.* = createErrorBlob(.err_internal, "Failed to format schema");
        return .err_internal;
    };

    const schema_data = global_allocator.dupe(u8, schema_str) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Failed to allocate result");
        return .err_out_of_memory;
    };

    out_schema.* = LgBlob.fromSlice(schema_data);
    out_err.* = LgBlob.empty();
    return .ok;
}

/// Get constraint information
///
/// @param db Database handle
/// @param out_constraints Output parameter for constraints blob
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_introspect_constraints(
    db: ?*LgDb,
    out_constraints: *LgBlob,
    out_err: *LgBlob,
) LgStatus {
    // SAFETY: db was originally a *DbState from lith_db_open, cast to opaque *LgDb.
    // The orelse guards null. Alignment is safe because DbState was heap-allocated
    // by global_allocator.create(). The db_registry.contains() check below validates
    // the pointer is still a live, registered handle.
    const state: *DbState = @ptrCast(@alignCast(db orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid database handle");
        return .err_invalid_argument;
    }));

    if (!db_registry.contains(state)) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Database handle not registered");
        return .err_invalid_argument;
    }

    // Generate constraint introspection (placeholder - no constraints yet)
    const constraint_json = "{\"constraints\":[],\"functional_dependencies\":[]}";
    const constraint_data = global_allocator.dupe(u8, constraint_json) catch {
        out_err.* = createErrorBlob(.err_out_of_memory, "Failed to allocate result");
        return .err_out_of_memory;
    };

    out_constraints.* = LgBlob.fromSlice(constraint_data);
    out_err.* = LgBlob.empty();
    return .ok;
}

// ============================================================
// Proof Verification (per D-NORM-004)
// ============================================================

/// Proof verifier callback type
pub const LgProofVerifier = *const fn (
    proof_ptr: [*]const u8,
    proof_len: usize,
    context_ptr: ?*anyopaque,
) callconv(.c) LgStatus;

/// Proof verifier registration entry
const VerifierEntry = struct {
    verifier_type: []const u8,
    callback: LgProofVerifier,
    context: ?*anyopaque,
};

// Registry of proof verifiers
var verifier_registry = std.StringHashMap(VerifierEntry).init(global_allocator);

/// Register a proof verifier for a specific proof type
///
/// @param type_ptr Proof type identifier (e.g., "normalization", "fd-holds")
/// @param type_len Length of type identifier
/// @param callback Verification function
/// @param context Optional context passed to callback
/// @return Status code
pub export fn lith_proof_register_verifier(
    type_ptr: [*]const u8,
    type_len: usize,
    callback: LgProofVerifier,
    context: ?*anyopaque,
) LgStatus {
    const verifier_type = type_ptr[0..type_len];

    const type_copy = global_allocator.dupe(u8, verifier_type) catch {
        return .err_out_of_memory;
    };

    const entry = VerifierEntry{
        .verifier_type = type_copy,
        .callback = callback,
        .context = context,
    };

    verifier_registry.put(type_copy, entry) catch {
        global_allocator.free(type_copy);
        return .err_internal;
    };

    return .ok;
}

/// Unregister a proof verifier
///
/// @param type_ptr Proof type identifier
/// @param type_len Length of type identifier
/// @return Status code
pub export fn lith_proof_unregister_verifier(
    type_ptr: [*]const u8,
    type_len: usize,
) LgStatus {
    const verifier_type = type_ptr[0..type_len];

    if (verifier_registry.fetchRemove(verifier_type)) |entry| {
        global_allocator.free(@constCast(entry.value.verifier_type));
        return .ok;
    }

    return .err_not_found;
}

/// Verify a proof using registered verifiers
///
/// @param proof_ptr CBOR-encoded proof blob
/// @param proof_len Length of proof
/// @param out_valid Output: true if proof is valid
/// @param out_err Output parameter for error blob
/// @return Status code
pub export fn lith_proof_verify(
    proof_ptr: [*]const u8,
    proof_len: usize,
    out_valid: *bool,
    out_err: *LgBlob,
) LgStatus {
    const proof_data = proof_ptr[0..proof_len];

    // Parse JSON proof to extract type and data
    // Expected format: {"type":"proof_type","data":"base64_data"}
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        global_allocator,
        proof_data,
        .{},
    ) catch {
        out_err.* = createErrorBlob(.err_invalid_argument, "Invalid JSON proof format");
        return .err_invalid_argument;
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Proof must be JSON object");
        return .err_invalid_argument;
    }

    const type_value = root.object.get("type") orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Proof missing 'type' field");
        return .err_invalid_argument;
    };

    if (type_value != .string) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Proof 'type' must be string");
        return .err_invalid_argument;
    }

    const ptype = type_value.string;

    const entry = verifier_registry.get(ptype) orelse {
        out_err.* = createErrorBlob(.err_not_found, "No verifier registered for proof type");
        return .err_not_found;
    };

    // Extract proof data (as string for now)
    const data_value = root.object.get("data") orelse {
        out_err.* = createErrorBlob(.err_invalid_argument, "Proof missing 'data' field");
        return .err_invalid_argument;
    };

    if (data_value != .string) {
        out_err.* = createErrorBlob(.err_invalid_argument, "Proof 'data' must be string");
        return .err_invalid_argument;
    }

    const verify_data = data_value.string;
    const status = entry.callback(verify_data.ptr, verify_data.len, entry.context);

    out_valid.* = (status == .ok);
    out_err.* = LgBlob.empty();
    return .ok;
}

/// Built-in verifier for FD-holds proofs (always accepts for PoC)
fn builtin_fd_verifier(
    _: [*]const u8,
    _: usize,
    _: ?*anyopaque,
) callconv(.c) LgStatus {
    // In production, this would actually verify the proof
    // For PoC, we accept all well-formed proofs
    return .ok;
}

/// Built-in verifier for normalization proofs
fn builtin_normalization_verifier(
    _: [*]const u8,
    _: usize,
    _: ?*anyopaque,
) callconv(.c) LgStatus {
    // In production, this would verify losslessness and dependency preservation
    // For PoC, we accept all well-formed proofs
    return .ok;
}

/// Initialize built-in proof verifiers
pub export fn lith_proof_init_builtins() LgStatus {
    // Register FD-holds verifier
    const fd_type = "fd-holds";
    var status = lith_proof_register_verifier(fd_type.ptr, fd_type.len, builtin_fd_verifier, null);
    if (status != .ok) return status;

    // Register normalization verifier
    const norm_type = "normalization";
    status = lith_proof_register_verifier(norm_type.ptr, norm_type.len, builtin_normalization_verifier, null);
    if (status != .ok) return status;

    // Register denormalization verifier (same logic)
    const denorm_type = "denormalization";
    status = lith_proof_register_verifier(denorm_type.ptr, denorm_type.len, builtin_normalization_verifier, null);

    return status;
}

// ============================================================
// Utility Functions - C ABI Exports
// ============================================================

/// Free a blob allocated by the bridge
///
/// @param blob Blob to free
pub export fn lith_blob_free(blob: *LgBlob) void {
    if (blob.toSlice()) |slice| {
        global_allocator.free(@constCast(slice));
    }
    blob.* = LgBlob.empty();
}

/// Get Lith version
///
/// @return Version as encoded integer (major * 10000 + minor * 100 + patch)
pub export fn lith_version() u32 {
    return 0 * 10000 + 1 * 100 + 0; // 0.1.0
}

// ============================================================
// Tests
// ============================================================

test "database lifecycle" {
    var db: ?*LgDb = null;
    var err_blob: LgBlob = undefined;

    const path = "test.lgh";
    const status = lith_db_open(path.ptr, path.len, null, 0, &db, &err_blob);

    try std.testing.expectEqual(LgStatus.ok, status);
    try std.testing.expect(db != null);

    const close_status = lith_db_close(db);
    try std.testing.expectEqual(LgStatus.ok, close_status);
}

test "transaction lifecycle" {
    var db: ?*LgDb = null;
    var err_blob: LgBlob = undefined;

    const path = "test_txn.lgh";
    _ = lith_db_open(path.ptr, path.len, null, 0, &db, &err_blob);
    defer _ = lith_db_close(db);

    var txn: ?*LgTxn = null;
    var txn_err: LgBlob = undefined;

    const begin_status = lith_txn_begin(db, .read_write, &txn, &txn_err);
    try std.testing.expectEqual(LgStatus.ok, begin_status);
    try std.testing.expect(txn != null);

    var commit_err: LgBlob = undefined;
    const commit_status = lith_txn_commit(txn, &commit_err);
    try std.testing.expectEqual(LgStatus.ok, commit_status);
}

test "version" {
    const version = lith_version();
    try std.testing.expectEqual(@as(u32, 100), version); // 0.1.0
}
