// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// bridge.zig — C-compatible FFI bridge for typeql-experimental
//
// Skeletal implementation of the ABI/FFI standard. This bridge will
// expose the Idris2 type checker's validation functions to non-Idris2
// consumers via a C-compatible interface.
//
// Architecture (per hyperpolymath ABI/FFI standard):
//   Idris2 (src/abi/) → defines the ABI (types, proofs)
//   Zig (ffi/zig/)    → implements C-compatible FFI
//   C headers         → generated bridge (in generated/abi/)

const std = @import("std");

// ============================================================================
// Effect labels (mirrors Core.idr EffectLabel)
// ============================================================================

/// Effect labels matching the Idris2 kernel's EffectLabel type.
pub const EffectLabel = enum(u8) {
    read = 0,
    write = 1,
    cite = 2,
    audit = 3,
    transform = 4,
    federate = 5,
};

// ============================================================================
// Session states (mirrors Session.idr SessionState)
// ============================================================================

/// Session protocol states matching the Idris2 kernel's SessionState type.
pub const SessionState = enum(u8) {
    fresh = 0,
    authenticated = 1,
    in_transaction = 2,
    committed = 3,
    rolled_back = 4,
    closed = 5,
};

// ============================================================================
// Transaction states (mirrors Modal.idr TxState)
// ============================================================================

/// Transaction scope states for modal types.
pub const TxState = enum(u8) {
    tx_fresh = 0,
    tx_active = 1,
    tx_committed = 2,
    tx_rolled_back = 3,
    tx_snapshot = 4,
};

// ============================================================================
// Extension annotations (mirrors Checker.idr ExtensionAnnotations)
// ============================================================================

/// C-compatible representation of VQL-dt++ extension annotations.
/// Each field uses a sentinel value to indicate "not present":
/// -1 for integers, null for pointers.
pub const ExtensionAnnotations = extern struct {
    /// CONSUME AFTER n USE (-1 = not present)
    consume_after: i32,
    /// WITH SESSION protocol (null = not present)
    session_protocol: ?[*:0]const u8,
    /// EFFECTS count (-1 = not present)
    effects_count: i32,
    /// EFFECTS labels (null = not present)
    effects: ?[*]const EffectLabel,
    /// IN TRANSACTION state (-1 = not present)
    tx_state: i32,
    /// PROOF ATTACHED theorem name (null = not present)
    proof_attached: ?[*:0]const u8,
    /// USAGE LIMIT n (-1 = not present)
    usage_limit: i32,
};

// ============================================================================
// Validation result
// ============================================================================

/// Result of validating extension annotations.
pub const ValidationResult = extern struct {
    /// 0 = success, non-zero = error code
    error_code: i32,
    /// Error message (null if success)
    error_message: ?[*:0]const u8,
};

// ============================================================================
// C-ABI exported functions
// ============================================================================

/// Validate a set of extension annotations.
/// Returns a ValidationResult with error_code = 0 on success.
///
/// This is a skeletal implementation — the real validation logic will
/// call into the Idris2 kernel when the FFI bridge is fully wired.
export fn tql_validate(annotations: *const ExtensionAnnotations) ValidationResult {
    // CONSUME AFTER must be positive if present
    if (annotations.consume_after != -1 and annotations.consume_after <= 0) {
        return .{
            .error_code = 1,
            .error_message = "CONSUME AFTER count must be positive",
        };
    }

    // USAGE LIMIT must be positive if present
    if (annotations.usage_limit != -1 and annotations.usage_limit <= 0) {
        return .{
            .error_code = 2,
            .error_message = "USAGE LIMIT must be positive",
        };
    }

    // USAGE LIMIT >= CONSUME AFTER when both present
    if (annotations.consume_after != -1 and annotations.usage_limit != -1) {
        if (annotations.usage_limit < annotations.consume_after) {
            return .{
                .error_code = 3,
                .error_message = "USAGE LIMIT must be >= CONSUME AFTER",
            };
        }
    }

    return .{ .error_code = 0, .error_message = null };
}

/// Get the version string of the bridge.
export fn tql_version() [*:0]const u8 {
    return "typeql-experimental 0.1.0";
}

// ============================================================================
// Tests
// ============================================================================

test "validate: empty annotations pass" {
    const ann = ExtensionAnnotations{
        .consume_after = -1,
        .session_protocol = null,
        .effects_count = -1,
        .effects = null,
        .tx_state = -1,
        .proof_attached = null,
        .usage_limit = -1,
    };
    const result = tql_validate(&ann);
    try std.testing.expectEqual(@as(i32, 0), result.error_code);
}

test "validate: consume_after=0 fails" {
    const ann = ExtensionAnnotations{
        .consume_after = 0,
        .session_protocol = null,
        .effects_count = -1,
        .effects = null,
        .tx_state = -1,
        .proof_attached = null,
        .usage_limit = -1,
    };
    const result = tql_validate(&ann);
    try std.testing.expectEqual(@as(i32, 1), result.error_code);
}

test "validate: usage_limit < consume_after fails" {
    const ann = ExtensionAnnotations{
        .consume_after = 10,
        .session_protocol = null,
        .effects_count = -1,
        .effects = null,
        .tx_state = -1,
        .proof_attached = null,
        .usage_limit = 5,
    };
    const result = tql_validate(&ann);
    try std.testing.expectEqual(@as(i32, 3), result.error_code);
}

test "validate: valid full annotations pass" {
    const ann = ExtensionAnnotations{
        .consume_after = 1,
        .session_protocol = "ReadOnlyProtocol",
        .effects_count = 2,
        .effects = null,
        .tx_state = @intFromEnum(TxState.tx_active),
        .proof_attached = "IntegrityTheorem",
        .usage_limit = 100,
    };
    const result = tql_validate(&ann);
    try std.testing.expectEqual(@as(i32, 0), result.error_code);
}

test "version string" {
    const ver = tql_version();
    try std.testing.expect(ver[0] == 't');
}
