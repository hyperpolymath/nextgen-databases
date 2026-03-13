// SPDX-License-Identifier: PMPL-1.0
// SPDX-FileCopyrightText: 2025 hyperpolymath
//
// fdb_root.zig - Root module for Lith FFI bridge
//
// Re-exports all FFI functions from sub-modules.

const std = @import("std");
const types = @import("fdb_types.zig");

// ============================================================================
// Re-export types
// ============================================================================

pub const FdbStatus = types.FdbStatus;
pub const ProofBlob = types.ProofBlob;
pub const ProofResult = types.ProofResult;
pub const PromptScoresC = types.PromptScoresC;

// ============================================================================
// From fdb_insert.zig
// ============================================================================

const insert = @import("fdb_insert.zig");

export fn fdb_verify_proof(
    proof_data: ?[*]const u8,
    proof_len: usize,
    result: *types.ProofResult,
) types.FdbStatus {
    return insert.fdb_verify_proof(proof_data, proof_len, result);
}

export fn fdb_insert(
    table_ptr: ?[*]const u8,
    table_len: usize,
    column_ptr: ?[*]const u8,
    column_len: usize,
    value_ptr: ?*const anyopaque,
    value_size: usize,
    proof_data: ?[*]const u8,
    proof_len: usize,
    actor_ptr: ?[*]const u8,
    actor_len: usize,
    timestamp_millis: u64,
    rationale_ptr: ?[*]const u8,
    rationale_len: usize,
    response: *types.InsertResponse,
) types.FdbStatus {
    return insert.fdb_insert(
        table_ptr, table_len, column_ptr, column_len,
        value_ptr, value_size, proof_data, proof_len,
        actor_ptr, actor_len, timestamp_millis,
        rationale_ptr, rationale_len, response,
    );
}

export fn fdb_get_scores(
    proof_data: ?[*]const u8,
    proof_len: usize,
    scores: *types.PromptScoresC,
) types.FdbStatus {
    return insert.fdb_get_scores(proof_data, proof_len, scores);
}

export fn fdb_timestamp_now() u64 {
    return insert.fdb_timestamp_now();
}

export fn fdb_validate_non_empty(
    str_ptr: ?[*]const u8,
    str_len: usize,
) bool {
    return insert.fdb_validate_non_empty(str_ptr, str_len);
}

export fn fdb_compute_overall(
    provenance: u8,
    replicability: u8,
    objective: u8,
    methodology: u8,
    publication: u8,
    transparency: u8,
) u8 {
    return insert.fdb_compute_overall(provenance, replicability, objective, methodology, publication, transparency);
}

export fn fdb_get_last_error(
    buf: [*]u8,
    buf_len: usize,
) usize {
    return insert.fdb_get_last_error(buf, buf_len);
}

// ============================================================================
// From fdb_persist.zig
// ============================================================================

const persist = @import("fdb_persist.zig");

export fn fdb_init(path_ptr: ?[*]const u8, path_len: usize) i32 {
    return persist.fdb_init(path_ptr, path_len);
}

export fn fdb_close() types.FdbStatus {
    return persist.fdb_close();
}

export fn fdb_save(dummy: i32) types.FdbStatus {
    return persist.fdb_save(dummy);
}

export fn fdb_is_init(dummy: i32) u8 {
    return if (persist.fdb_is_init(dummy)) 1 else 0;
}

export fn fdb_table_count(table_ptr: ?[*]const u8, table_len: usize) u64 {
    return persist.fdb_table_count(table_ptr, table_len);
}

export fn fdb_insert_row(
    table_ptr: ?[*]const u8,
    table_len: usize,
    cols_ptr: ?[*]const u8,
    cols_len: usize,
    vals_ptr: ?[*]const u8,
    vals_len: usize,
    actor_ptr: ?[*]const u8,
    actor_len: usize,
    rationale_ptr: ?[*]const u8,
    rationale_len: usize,
    timestamp: u64,
    row_id: *u64,
) types.FdbStatus {
    return persist.fdb_insert_row(
        table_ptr, table_len, cols_ptr, cols_len,
        vals_ptr, vals_len, actor_ptr, actor_len,
        rationale_ptr, rationale_len, timestamp, row_id,
    );
}

export fn fdb_delete_row(
    table_ptr: ?[*]const u8,
    table_len: usize,
    row_id: u64,
) types.FdbStatus {
    return persist.fdb_delete_row(table_ptr, table_len, row_id);
}

/// Debug: return a magic number to verify FFI is working
export fn fdb_debug_magic() i32 {
    return 42424242;
}

/// Debug: return init counter (takes dummy to prevent caching)
export fn fdb_debug_init_counter(dummy: i32) i32 {
    return persist.fdb_debug_init_counter(dummy);
}

/// Debug: fresh test - takes input, adds to counter, returns result
export fn fdb_test_fresh(input: i32) i32 {
    return persist.fdb_test_fresh(input);
}
