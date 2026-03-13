// SPDX-License-Identifier: PMPL-1.0
// SPDX-FileCopyrightText: 2025 hyperpolymath
//
// lith_insert.zig - Lith insert operations with proof verification
//
// Exports C ABI functions for Lean 4's @[extern] declarations.
// Pure Zig implementation, no C headers required.

const std = @import("std");
const types = @import("lith_types.zig");

// Include persistence module - its export fns will be automatically exported
pub const persist = @import("lith_persist.zig");

const LithStatus = types.LithStatus;
const ProofBlob = types.ProofBlob;
const ProofResult = types.ProofResult;
const PromptScoresC = types.PromptScoresC;
const NonEmptyStringC = types.NonEmptyStringC;
const ProvenanceC = types.ProvenanceC;
const InsertRequest = types.InsertRequest;
const InsertResponse = types.InsertResponse;
const TimestampC = types.TimestampC;
const ActorIdC = types.ActorIdC;
const RationaleC = types.RationaleC;

// ============================================================================
// Global State (for mock implementation)
// ============================================================================

var next_row_id: u64 = 1;
var last_error: [256]u8 = undefined;
var last_error_len: usize = 0;

fn setError(msg: []const u8) [*:0]const u8 {
    const copy_len = @min(msg.len, last_error.len - 1);
    @memcpy(last_error[0..copy_len], msg[0..copy_len]);
    last_error[copy_len] = 0;
    last_error_len = copy_len;
    return @ptrCast(&last_error);
}

// ============================================================================
// Proof Verification (Mock Implementation)
// ============================================================================

/// Verify a proof blob and extract PROMPT scores
/// In production, this would decode CBOR and verify cryptographic proofs
fn verifyProofInternal(proof: ProofBlob) ProofResult {
    // Validate proof blob format
    if (!proof.isValid()) {
        return .{
            .status = .invalid_proof,
            .error_message = setError("Proof blob is empty or too large"),
            .verified_scores = PromptScoresC.zero(),
        };
    }

    const data = proof.slice();

    // Mock CBOR validation: check for CBOR map marker (0xA0-0xBF or 0xBF)
    // In production, use a proper CBOR decoder
    if (data.len < 1) {
        return .{
            .status = .invalid_proof,
            .error_message = setError("Proof blob too short"),
            .verified_scores = PromptScoresC.zero(),
        };
    }

    // Simple mock: first byte encodes overall score, rest are dimension scores
    // Real implementation would decode CBOR properly
    var scores = PromptScoresC{
        .provenance = if (data.len > 1) data[1] else 50,
        .replicability = if (data.len > 2) data[2] else 50,
        .objective = if (data.len > 3) data[3] else 50,
        .methodology = if (data.len > 4) data[4] else 50,
        .publication = if (data.len > 5) data[5] else 50,
        .transparency = if (data.len > 6) data[6] else 50,
        .overall = 0,
    };
    scores.computeOverall();

    // Clamp scores to valid range
    if (!scores.isValid()) {
        scores.provenance = @min(scores.provenance, 100);
        scores.replicability = @min(scores.replicability, 100);
        scores.objective = @min(scores.objective, 100);
        scores.methodology = @min(scores.methodology, 100);
        scores.publication = @min(scores.publication, 100);
        scores.transparency = @min(scores.transparency, 100);
        scores.computeOverall();
    }

    return .{
        .status = .ok,
        .error_message = null,
        .verified_scores = scores,
    };
}

/// Validate provenance information
fn validateProvenance(prov: ProvenanceC) LithStatus {
    if (!prov.actor.isValid()) {
        return .invalid_actor;
    }
    if (!prov.rationale.isValid()) {
        return .invalid_rationale;
    }
    return .ok;
}

// ============================================================================
// Exported C ABI Functions (for Lean 4 @[extern])
// ============================================================================

/// Verify a proof blob and return the result
/// Lean 4 declaration: @[extern "lith_verify_proof"]
pub fn lith_verify_proof(
    proof_data: ?[*]const u8,
    proof_len: usize,
    result: *ProofResult,
) LithStatus {
    const proof = ProofBlob{
        .data = proof_data,
        .len = proof_len,
    };

    result.* = verifyProofInternal(proof);
    return result.status;
}

/// Insert a value with proof verification
/// Lean 4 declaration: @[extern "lith_insert"]
pub fn lith_insert(
    // Table and column
    table_ptr: ?[*]const u8,
    table_len: usize,
    column_ptr: ?[*]const u8,
    column_len: usize,
    // Value
    value_ptr: ?*const anyopaque,
    value_size: usize,
    // Proof blob
    proof_data: ?[*]const u8,
    proof_len: usize,
    // Provenance
    actor_ptr: ?[*]const u8,
    actor_len: usize,
    timestamp_millis: u64,
    rationale_ptr: ?[*]const u8,
    rationale_len: usize,
    // Output
    response: *InsertResponse,
) LithStatus {
    // Validate table name
    if (table_len == 0 or table_ptr == null) {
        response.* = .{
            .status = .type_error,
            .row_id = 0,
            .error_message = setError("Table name cannot be empty"),
        };
        return response.status;
    }

    // Validate column name
    if (column_len == 0 or column_ptr == null) {
        response.* = .{
            .status = .type_error,
            .row_id = 0,
            .error_message = setError("Column name cannot be empty"),
        };
        return response.status;
    }

    // Build provenance
    const provenance = ProvenanceC{
        .actor = ActorIdC{ .id = NonEmptyStringC{ .data = actor_ptr, .len = actor_len } },
        .timestamp = TimestampC{ .millis = timestamp_millis },
        .rationale = RationaleC{ .text = NonEmptyStringC{ .data = rationale_ptr, .len = rationale_len } },
    };

    // Validate provenance
    const prov_status = validateProvenance(provenance);
    if (prov_status != .ok) {
        response.* = .{
            .status = prov_status,
            .row_id = 0,
            .error_message = setError(prov_status.toMessage()),
        };
        return response.status;
    }

    // Verify proof
    const proof = ProofBlob{
        .data = proof_data,
        .len = proof_len,
    };
    const proof_result = verifyProofInternal(proof);

    if (!proof_result.status.isOk()) {
        response.* = .{
            .status = proof_result.status,
            .row_id = 0,
            .error_message = proof_result.error_message,
        };
        return response.status;
    }

    // Mock insert: just return a row ID
    // In production, this would call Lith's actual insert
    const row_id = next_row_id;
    next_row_id += 1;

    _ = value_ptr;
    _ = value_size;

    response.* = .{
        .status = .ok,
        .row_id = row_id,
        .error_message = null,
    };

    return .ok;
}

/// Get PROMPT scores from a proof blob
/// Lean 4 declaration: @[extern "lith_get_scores"]
pub fn lith_get_scores(
    proof_data: ?[*]const u8,
    proof_len: usize,
    scores: *PromptScoresC,
) LithStatus {
    const proof = ProofBlob{
        .data = proof_data,
        .len = proof_len,
    };

    const result = verifyProofInternal(proof);
    if (result.status.isOk()) {
        scores.* = result.verified_scores;
    } else {
        scores.* = PromptScoresC.zero();
    }

    return result.status;
}

/// Create a timestamp for the current time
/// Lean 4 declaration: @[extern "lith_timestamp_now"]
pub fn lith_timestamp_now() u64 {
    return TimestampC.now().millis;
}

/// Validate that a string is non-empty
/// Lean 4 declaration: @[extern "lith_validate_non_empty"]
pub fn lith_validate_non_empty(
    str_ptr: ?[*]const u8,
    str_len: usize,
) bool {
    const s = NonEmptyStringC{ .data = str_ptr, .len = str_len };
    return s.isValid();
}

/// Compute overall PROMPT score from 6 dimensions
/// Lean 4 declaration: @[extern "lith_compute_overall"]
pub fn lith_compute_overall(
    provenance: u8,
    replicability: u8,
    objective: u8,
    methodology: u8,
    publication: u8,
    transparency: u8,
) u8 {
    var scores = PromptScoresC{
        .provenance = @min(provenance, 100),
        .replicability = @min(replicability, 100),
        .objective = @min(objective, 100),
        .methodology = @min(methodology, 100),
        .publication = @min(publication, 100),
        .transparency = @min(transparency, 100),
        .overall = 0,
    };
    scores.computeOverall();
    return scores.overall;
}

/// Get the last error message
/// Lean 4 declaration: @[extern "lith_get_last_error"]
pub fn lith_get_last_error(
    buf: [*]u8,
    buf_len: usize,
) usize {
    const copy_len = @min(last_error_len, buf_len);
    if (copy_len > 0) {
        @memcpy(buf[0..copy_len], last_error[0..copy_len]);
    }
    return copy_len;
}

// ============================================================================
// Tests
// ============================================================================

test "lith_verify_proof with valid proof" {
    // Mock proof: marker byte + 6 dimension scores
    const proof_data = [_]u8{ 0xA6, 80, 70, 90, 85, 75, 80 };
    var result: ProofResult = undefined;

    const status = lith_verify_proof(&proof_data, proof_data.len, &result);

    try std.testing.expectEqual(LithStatus.ok, status);
    try std.testing.expectEqual(@as(u8, 80), result.verified_scores.provenance);
    try std.testing.expectEqual(@as(u8, 70), result.verified_scores.replicability);
}

test "lith_verify_proof with empty proof" {
    var result: ProofResult = undefined;
    const status = lith_verify_proof(null, 0, &result);

    try std.testing.expectEqual(LithStatus.invalid_proof, status);
}

test "lith_insert with valid data" {
    const table = "users";
    const column = "name";
    const value: u32 = 42;
    const proof_data = [_]u8{ 0xA6, 80, 70, 90, 85, 75, 80 };
    const actor = "test_user";
    const rationale = "Unit test insert";

    var response: InsertResponse = undefined;

    const status = lith_insert(
        table.ptr,
        table.len,
        column.ptr,
        column.len,
        &value,
        @sizeOf(u32),
        &proof_data,
        proof_data.len,
        actor.ptr,
        actor.len,
        1000,
        rationale.ptr,
        rationale.len,
        &response,
    );

    try std.testing.expectEqual(LithStatus.ok, status);
    try std.testing.expect(response.row_id > 0);
}

test "lith_insert with empty actor" {
    const table = "users";
    const column = "name";
    const value: u32 = 42;
    const proof_data = [_]u8{ 0xA6, 80, 70, 90, 85, 75, 80 };
    const rationale = "Unit test insert";

    var response: InsertResponse = undefined;

    const status = lith_insert(
        table.ptr,
        table.len,
        column.ptr,
        column.len,
        &value,
        @sizeOf(u32),
        &proof_data,
        proof_data.len,
        null,
        0,
        1000,
        rationale.ptr,
        rationale.len,
        &response,
    );

    try std.testing.expectEqual(LithStatus.invalid_actor, status);
}

test "lith_compute_overall" {
    const overall = lith_compute_overall(100, 80, 90, 70, 60, 80);
    // (100 + 80 + 90 + 70 + 60 + 80) / 6 = 80
    try std.testing.expectEqual(@as(u8, 80), overall);
}

test "lith_timestamp_now" {
    const ts = lith_timestamp_now();
    // Now returns 0 as a stub - actual time comes from caller
    try std.testing.expectEqual(@as(u64, 0), ts);
}
