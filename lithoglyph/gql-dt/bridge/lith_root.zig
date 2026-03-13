// SPDX-License-Identifier: PMPL-1.0
// SPDX-FileCopyrightText: 2025 hyperpolymath
//
// lith_root.zig - Root module for Lith FFI bridge
//
// Re-exports all FFI functions from sub-modules.

const std = @import("std");
const types = @import("lith_types.zig");

// ============================================================================
// Re-export types
// ============================================================================

pub const LithStatus = types.LithStatus;
pub const ProofBlob = types.ProofBlob;
pub const ProofResult = types.ProofResult;
pub const PromptScoresC = types.PromptScoresC;

// ============================================================================
// From lith_insert.zig
// ============================================================================

const insert = @import("lith_insert.zig");

export fn lith_verify_proof(
    proof_data: ?[*]const u8,
    proof_len: usize,
    result: *types.ProofResult,
) types.LithStatus {
    return insert.lith_verify_proof(proof_data, proof_len, result);
}

export fn lith_insert(
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
) types.LithStatus {
    return insert.lith_insert(
        table_ptr, table_len, column_ptr, column_len,
        value_ptr, value_size, proof_data, proof_len,
        actor_ptr, actor_len, timestamp_millis,
        rationale_ptr, rationale_len, response,
    );
}

export fn lith_get_scores(
    proof_data: ?[*]const u8,
    proof_len: usize,
    scores: *types.PromptScoresC,
) types.LithStatus {
    return insert.lith_get_scores(proof_data, proof_len, scores);
}

export fn lith_timestamp_now() u64 {
    return insert.lith_timestamp_now();
}

export fn lith_validate_non_empty(
    str_ptr: ?[*]const u8,
    str_len: usize,
) bool {
    return insert.lith_validate_non_empty(str_ptr, str_len);
}

export fn lith_compute_overall(
    provenance: u8,
    replicability: u8,
    objective: u8,
    methodology: u8,
    publication: u8,
    transparency: u8,
) u8 {
    return insert.lith_compute_overall(provenance, replicability, objective, methodology, publication, transparency);
}

export fn lith_get_last_error(
    buf: [*]u8,
    buf_len: usize,
) usize {
    return insert.lith_get_last_error(buf, buf_len);
}

// ============================================================================
// From lith_persist.zig
// ============================================================================

const persist = @import("lith_persist.zig");

export fn lith_init(path_ptr: ?[*]const u8, path_len: usize) i32 {
    return persist.lith_init(path_ptr, path_len);
}

export fn lith_close() types.LithStatus {
    return persist.lith_close();
}

export fn lith_save(dummy: i32) types.LithStatus {
    return persist.lith_save(dummy);
}

export fn lith_is_init(dummy: i32) u8 {
    return if (persist.lith_is_init(dummy)) 1 else 0;
}

export fn lith_table_count(table_ptr: ?[*]const u8, table_len: usize) u64 {
    return persist.lith_table_count(table_ptr, table_len);
}

export fn lith_insert_row(
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
) types.LithStatus {
    return persist.lith_insert_row(
        table_ptr, table_len, cols_ptr, cols_len,
        vals_ptr, vals_len, actor_ptr, actor_len,
        rationale_ptr, rationale_len, timestamp, row_id,
    );
}

export fn lith_delete_row(
    table_ptr: ?[*]const u8,
    table_len: usize,
    row_id: u64,
) types.LithStatus {
    return persist.lith_delete_row(table_ptr, table_len, row_id);
}

/// Debug: return a magic number to verify FFI is working
export fn lith_debug_magic() i32 {
    return 42424242;
}

/// Debug: return init counter (takes dummy to prevent caching)
export fn lith_debug_init_counter(dummy: i32) i32 {
    return persist.lith_debug_init_counter(dummy);
}

/// Debug: fresh test - takes input, adds to counter, returns result
export fn lith_test_fresh(input: i32) i32 {
    return persist.lith_test_fresh(input);
}
