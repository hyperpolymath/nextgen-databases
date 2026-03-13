// SPDX-License-Identifier: PMPL-1.0
// SPDX-FileCopyrightText: 2025 hyperpolymath
//
// fdb_types.zig - Core types for Lith FFI bridge
//
// These types mirror the Lean 4 definitions and provide the C ABI
// interface for Lean's @[extern] declarations. Pure Zig, no C headers.

const std = @import("std");

// ============================================================================
// Status Codes
// ============================================================================

/// Result status for Lith operations
pub const FdbStatus = enum(i32) {
    /// Operation succeeded
    ok = 0,
    /// Invalid proof blob format
    invalid_proof = -1,
    /// Proof verification failed
    proof_failed = -2,
    /// Type constraint violation
    type_error = -3,
    /// Actor ID is empty or invalid
    invalid_actor = -4,
    /// Rationale is empty or invalid
    invalid_rationale = -5,
    /// Timestamp is invalid
    invalid_timestamp = -6,
    /// Memory allocation failed
    out_of_memory = -7,
    /// Generic error
    generic_error = -99,

    pub fn isOk(self: FdbStatus) bool {
        return self == .ok;
    }

    pub fn toMessage(self: FdbStatus) []const u8 {
        return switch (self) {
            .ok => "Success",
            .invalid_proof => "Invalid proof blob format",
            .proof_failed => "Proof verification failed",
            .type_error => "Type constraint violation",
            .invalid_actor => "Actor ID is empty or invalid",
            .invalid_rationale => "Rationale is empty or invalid",
            .invalid_timestamp => "Invalid timestamp",
            .out_of_memory => "Memory allocation failed",
            .generic_error => "Unknown error",
        };
    }
};

// ============================================================================
// Proof Blob Types
// ============================================================================

/// Maximum size for proof blobs (64KB)
pub const MAX_PROOF_SIZE: usize = 64 * 1024;

/// A CBOR-encoded proof blob containing type proofs
/// Format: CBOR map with keys for each proof component
pub const ProofBlob = extern struct {
    /// Pointer to CBOR-encoded proof data (nullable)
    data: ?[*]const u8,
    /// Length of the proof data in bytes
    len: usize,

    pub fn isEmpty(self: ProofBlob) bool {
        return self.len == 0 or self.data == null;
    }

    pub fn isValid(self: ProofBlob) bool {
        return !self.isEmpty() and self.len <= MAX_PROOF_SIZE;
    }

    pub fn slice(self: ProofBlob) []const u8 {
        if (self.data) |ptr| {
            if (self.len > 0) return ptr[0..self.len];
        }
        return &[_]u8{};
    }
};

/// Result of proof verification
pub const ProofResult = extern struct {
    /// Status code
    status: FdbStatus,
    /// Error message (null-terminated, or null if ok)
    error_message: ?[*:0]const u8,
    /// Verified dimension scores (only valid if status == ok)
    verified_scores: PromptScoresC,
};

// ============================================================================
// PROMPT Score Types (C ABI compatible)
// ============================================================================

/// A single PROMPT dimension score (0-100)
pub const PromptDimensionC = extern struct {
    value: u8,

    pub fn isValid(self: PromptDimensionC) bool {
        return self.value <= 100;
    }

    pub fn fromU8(v: u8) PromptDimensionC {
        return .{ .value = if (v > 100) 100 else v };
    }
};

/// Complete PROMPT scores with all 6 dimensions
pub const PromptScoresC = extern struct {
    provenance: u8,
    replicability: u8,
    objective: u8,
    methodology: u8,
    publication: u8,
    transparency: u8,
    overall: u8,

    pub fn computeOverall(self: *PromptScoresC) void {
        const sum: u32 = @as(u32, self.provenance) +
            @as(u32, self.replicability) +
            @as(u32, self.objective) +
            @as(u32, self.methodology) +
            @as(u32, self.publication) +
            @as(u32, self.transparency);
        self.overall = @intCast(sum / 6);
    }

    pub fn isValid(self: PromptScoresC) bool {
        return self.provenance <= 100 and
            self.replicability <= 100 and
            self.objective <= 100 and
            self.methodology <= 100 and
            self.publication <= 100 and
            self.transparency <= 100 and
            self.overall <= 100;
    }

    pub fn zero() PromptScoresC {
        return .{
            .provenance = 0,
            .replicability = 0,
            .objective = 0,
            .methodology = 0,
            .publication = 0,
            .transparency = 0,
            .overall = 0,
        };
    }
};

// ============================================================================
// Provenance Types (C ABI compatible)
// ============================================================================

/// A non-empty string reference (borrowed, not owned)
pub const NonEmptyStringC = extern struct {
    /// Pointer to UTF-8 string data (not null-terminated, nullable)
    data: ?[*]const u8,
    /// Length in bytes (must be > 0 for valid strings)
    len: usize,

    pub fn isEmpty(self: NonEmptyStringC) bool {
        return self.len == 0 or self.data == null;
    }

    pub fn isValid(self: NonEmptyStringC) bool {
        return !self.isEmpty();
    }

    pub fn slice(self: NonEmptyStringC) []const u8 {
        if (self.data) |ptr| {
            if (self.len > 0) return ptr[0..self.len];
        }
        return &[_]u8{};
    }

    pub fn fromSlice(s: []const u8) NonEmptyStringC {
        return .{
            .data = s.ptr,
            .len = s.len,
        };
    }
};

/// Unix timestamp in milliseconds
pub const TimestampC = extern struct {
    millis: u64,

    /// Get current timestamp
    /// Note: Returns 0 as FFI stub - actual time should be provided by caller
    pub fn now() TimestampC {
        // For FFI, we expect caller to provide timestamp from Lean side
        // This is a stub that returns 0
        return .{ .millis = 0 };
    }

    pub fn epoch() TimestampC {
        return .{ .millis = 0 };
    }

    pub fn isBefore(self: TimestampC, other: TimestampC) bool {
        return self.millis < other.millis;
    }
};

/// Actor identifier (who performed the operation)
pub const ActorIdC = extern struct {
    id: NonEmptyStringC,

    pub fn isValid(self: ActorIdC) bool {
        return self.id.isValid();
    }
};

/// Rationale for the operation (why it was performed)
pub const RationaleC = extern struct {
    text: NonEmptyStringC,

    pub fn isValid(self: RationaleC) bool {
        return self.text.isValid();
    }
};

/// Complete provenance information for a tracked value
pub const ProvenanceC = extern struct {
    actor: ActorIdC,
    timestamp: TimestampC,
    rationale: RationaleC,

    pub fn isValid(self: ProvenanceC) bool {
        return self.actor.isValid() and self.rationale.isValid();
    }
};

// ============================================================================
// Tracked Value Types
// ============================================================================

/// A tracked value with provenance (generic over value pointer)
pub const TrackedValueC = extern struct {
    /// Pointer to the actual value data
    value_ptr: ?*anyopaque,
    /// Size of the value in bytes
    value_size: usize,
    /// Provenance information
    provenance: ProvenanceC,
    /// PROMPT scores for this value
    scores: PromptScoresC,
};

// ============================================================================
// Insert Request/Response Types
// ============================================================================

/// Request to insert a value with proof
pub const InsertRequest = extern struct {
    /// Table name (non-empty)
    table: NonEmptyStringC,
    /// Column name (non-empty)
    column: NonEmptyStringC,
    /// Value data pointer
    value_ptr: ?*const anyopaque,
    /// Value size in bytes
    value_size: usize,
    /// Proof blob (CBOR-encoded)
    proof: ProofBlob,
    /// Provenance information
    provenance: ProvenanceC,
};

/// Response from insert operation
pub const InsertResponse = extern struct {
    /// Status code
    status: FdbStatus,
    /// Row ID if successful (0 otherwise)
    row_id: u64,
    /// Error message if failed
    error_message: ?[*:0]const u8,
};

// ============================================================================
// Tests
// ============================================================================

test "FdbStatus codes" {
    try std.testing.expect(FdbStatus.ok.isOk());
    try std.testing.expect(!FdbStatus.invalid_proof.isOk());
    try std.testing.expectEqualStrings("Success", FdbStatus.ok.toMessage());
}

test "PromptScoresC compute overall" {
    var scores = PromptScoresC{
        .provenance = 100,
        .replicability = 80,
        .objective = 90,
        .methodology = 70,
        .publication = 60,
        .transparency = 80,
        .overall = 0,
    };
    scores.computeOverall();
    // (100 + 80 + 90 + 70 + 60 + 80) / 6 = 480 / 6 = 80
    try std.testing.expectEqual(@as(u8, 80), scores.overall);
}

test "NonEmptyStringC validation" {
    const valid = NonEmptyStringC.fromSlice("hello");
    try std.testing.expect(valid.isValid());
    try std.testing.expectEqualStrings("hello", valid.slice());

    const empty = NonEmptyStringC{ .data = null, .len = 0 };
    try std.testing.expect(!empty.isValid());
}

test "TimestampC ordering" {
    const t1 = TimestampC{ .millis = 1000 };
    const t2 = TimestampC{ .millis = 2000 };
    try std.testing.expect(t1.isBefore(t2));
    try std.testing.expect(!t2.isBefore(t1));
}
