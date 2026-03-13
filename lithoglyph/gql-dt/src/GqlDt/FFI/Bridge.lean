-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- GqlDt.FFI.Bridge - Lean 4 bindings to Zig FFI bridge
--
-- This module provides @[extern] declarations for the Zig FFI functions
-- defined in bridge/lith_insert.zig. These allow Lean 4 to call into the
-- Lithoglyph FFI layer for proof verification and database operations.

namespace GqlDt.FFI

-- ============================================================================
-- Status Codes (mirrors LithStatus in Zig)
-- ============================================================================

/-- Result status for Lithoglyph operations -/
inductive LithStatus where
  | ok : LithStatus
  | invalidProof : LithStatus
  | proofFailed : LithStatus
  | typeError : LithStatus
  | invalidActor : LithStatus
  | invalidRationale : LithStatus
  | invalidTimestamp : LithStatus
  | outOfMemory : LithStatus
  | genericError : LithStatus
  deriving Repr, BEq

namespace LithStatus

/-- Convert from raw C ABI integer -/
def fromInt (i : Int) : LithStatus :=
  if i == 0 then .ok
  else if i == 42 then .ok  -- Special marker: fresh initialization success
  else if i == -1 then .invalidProof
  else if i == -2 then .proofFailed
  else if i == -3 then .typeError
  else if i == -4 then .invalidActor
  else if i == -5 then .invalidRationale
  else if i == -6 then .invalidTimestamp
  else if i == -7 then .outOfMemory
  else .genericError

/-- Convert to raw C ABI integer -/
def toInt (s : LithStatus) : Int :=
  match s with
  | .ok => 0
  | .invalidProof => -1
  | .proofFailed => -2
  | .typeError => -3
  | .invalidActor => -4
  | .invalidRationale => -5
  | .invalidTimestamp => -6
  | .outOfMemory => -7
  | .genericError => -99

/-- Check if status indicates success -/
def isOk (s : LithStatus) : Bool := s == .ok

/-- Get human-readable error message -/
def message (s : LithStatus) : String :=
  match s with
  | .ok => "Success"
  | .invalidProof => "Invalid proof blob format"
  | .proofFailed => "Proof verification failed"
  | .typeError => "Type constraint violation"
  | .invalidActor => "Actor ID is empty or invalid"
  | .invalidRationale => "Rationale is empty or invalid"
  | .invalidTimestamp => "Invalid timestamp"
  | .outOfMemory => "Memory allocation failed"
  | .genericError => "Unknown error"

end LithStatus

-- ============================================================================
-- PROMPT Scores (C ABI compatible structure)
-- ============================================================================

/-- PROMPT scores structure for C ABI -/
structure PromptScoresFFI where
  provenance : UInt8
  replicability : UInt8
  objective : UInt8
  methodology : UInt8
  publication : UInt8
  transparency : UInt8
  overall : UInt8
  deriving Repr

namespace PromptScoresFFI

/-- Create zero-initialized scores -/
def zero : PromptScoresFFI := {
  provenance := 0
  replicability := 0
  objective := 0
  methodology := 0
  publication := 0
  transparency := 0
  overall := 0
}

/-- Check if all scores are within valid range [0, 100] -/
def isValid (s : PromptScoresFFI) : Bool :=
  s.provenance ≤ 100 &&
  s.replicability ≤ 100 &&
  s.objective ≤ 100 &&
  s.methodology ≤ 100 &&
  s.publication ≤ 100 &&
  s.transparency ≤ 100 &&
  s.overall ≤ 100

end PromptScoresFFI

-- ============================================================================
-- Insert Response (C ABI compatible structure)
-- ============================================================================

/-- Response from insert operation -/
structure InsertResponseFFI where
  statusCode : Int
  rowId : UInt64
  deriving Repr

namespace InsertResponseFFI

/-- Get status as LithStatus enum -/
def status (r : InsertResponseFFI) : LithStatus :=
  LithStatus.fromInt r.statusCode

/-- Check if insert succeeded -/
def isOk (r : InsertResponseFFI) : Bool :=
  r.statusCode == 0

end InsertResponseFFI

-- ============================================================================
-- External Function Declarations
-- ============================================================================

/-- Compute overall PROMPT score from 6 dimensions.
    Calls Zig function: lith_compute_overall -/
@[extern "lith_compute_overall"]
opaque computeOverallFFI (
  provenance : UInt8
) (replicability : UInt8
) (objective : UInt8
) (methodology : UInt8
) (publication : UInt8
) (transparency : UInt8
) : UInt8

/-- Get current timestamp in milliseconds.
    Calls Zig function: lith_timestamp_now -/
@[extern "lith_timestamp_now"]
opaque timestampNowFFI : Unit → UInt64

-- ============================================================================
-- High-Level Wrappers
-- ============================================================================

/-- Compute overall PROMPT score from individual dimensions -/
def computeOverall (p r o m pub t : Nat) : Nat :=
  let p' : UInt8 := if p > 100 then 100 else p.toUInt8
  let r' : UInt8 := if r > 100 then 100 else r.toUInt8
  let o' : UInt8 := if o > 100 then 100 else o.toUInt8
  let m' : UInt8 := if m > 100 then 100 else m.toUInt8
  let pub' : UInt8 := if pub > 100 then 100 else pub.toUInt8
  let t' : UInt8 := if t > 100 then 100 else t.toUInt8
  (computeOverallFFI p' r' o' m' pub' t').toNat

/-- Get current timestamp -/
def timestampNow : IO UInt64 := do
  pure (timestampNowFFI ())

-- ============================================================================
-- Result Types
-- ============================================================================

/-- Result of a proof verification -/
structure ProofVerifyResult where
  status : LithStatus
  scores : PromptScoresFFI
  deriving Repr

/-- Result of an insert operation -/
structure InsertResult where
  status : LithStatus
  rowId : Option UInt64
  errorMessage : Option String
  deriving Repr

namespace InsertResult

/-- Create success result -/
def success (rowId : UInt64) : InsertResult := {
  status := .ok
  rowId := some rowId
  errorMessage := none
}

/-- Create failure result -/
def failure (status : LithStatus) (msg : String) : InsertResult := {
  status := status
  rowId := none
  errorMessage := some msg
}

end InsertResult

-- ============================================================================
-- Persistence Functions (Lithoglyph Backend)
-- ============================================================================

/-- Initialize database with null path (uses default)
    Lean 4: @[extern "lith_init"] -/
@[extern "lith_init"]
opaque lithInitFFI : USize → USize → Int32

/-- Close database and save
    Lean 4: @[extern "lith_close"] -/
@[extern "lith_close"]
opaque lithCloseFFI (u : Unit) : Int32

/-- Save database to disk (takes dummy to prevent caching)
    Lean 4: @[extern "lith_save"] -/
@[extern "lith_save"]
opaque lithSaveFFI (dummy : Int32) : Int32

/-- Check if database is initialized (takes dummy to prevent caching)
    Lean 4: @[extern "lith_is_init"] -/
@[extern "lith_is_init"]
opaque lithIsInitFFI (dummy : Int32) : UInt8

/-- Get row count for a table (pass null for now)
    Lean 4: @[extern "lith_table_count"] -/
@[extern "lith_table_count"]
opaque lithTableCountFFI (tablePtr : USize) (len : USize) : UInt64

/-- Debug: return magic number to verify FFI works
    Lean 4: @[extern "lith_debug_magic"] -/
@[extern "lith_debug_magic"]
opaque lithDebugMagicFFI (u : Unit) : Int32

/-- Debug: return init counter (takes dummy to prevent caching)
    Lean 4: @[extern "lith_debug_init_counter"] -/
@[extern "lith_debug_init_counter"]
opaque lithDebugInitCounterFFI (dummy : Int32) : Int32

/-- Debug: test fresh function - takes input, adds to counter, returns result
    Lean 4: @[extern "lith_test_fresh"] -/
@[extern "lith_test_fresh"]
opaque lithTestFreshFFI (input : Int32) : Int32

-- ============================================================================
-- High-Level Persistence API
-- ============================================================================

/-- Initialize the Lithoglyph backend (uses default path) -/
def initDB (_path : String := "gqldt.db") : IO LithStatus := do
  -- Pass null pointer (0) to use default path
  -- Use IO.pure to lift the pure FFI call into IO
  pure (LithStatus.fromInt (lithInitFFI 0 0).toInt)

/-- Close the Lithoglyph backend -/
def closeDB : IO LithStatus := do
  pure (LithStatus.fromInt (lithCloseFFI ()).toInt)

/-- Save database to disk -/
def saveDB (dummy : Int32 := 0) : IO LithStatus := do
  pure (LithStatus.fromInt (lithSaveFFI dummy).toInt)

/-- Check if database is initialized -/
def isDBInit (dummy : Int32 := 0) : IO Bool := do
  pure (lithIsInitFFI dummy != 0)

/-- Get row count for a table (returns 0 for now, pending proper FFI) -/
def tableCount (_table : String) : IO Nat := do
  -- Pass null to avoid FFI pointer issues
  pure (lithTableCountFFI 0 0).toNat

/-- Debug: return magic number to verify FFI works (should be 42424242) -/
def debugMagic : IO Int32 := do
  pure (lithDebugMagicFFI ())

/-- Debug: return init counter (should be 1+ after initDB) -/
def debugInitCounter (dummy : Int32 := 0) : IO Int32 := do
  pure (lithDebugInitCounterFFI dummy)

/-- Debug: test fresh function - tests if FFI calls with args execute each time -/
def testFresh (input : Int32) : IO Int32 := do
  pure (lithTestFreshFFI input)

end GqlDt.FFI
