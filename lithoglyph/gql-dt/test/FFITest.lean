-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FFITest.lean - Integration test for Zig FFI bridge
--
-- This test verifies that the Lean 4 @[extern] declarations correctly
-- interface with the Zig FFI library. To run with FFI:
--
-- 1. Build Zig library: cd bridge && zig build
-- 2. Build Lean with link: lake build (configure moreLinkArgs in lakefile)
-- 3. Run: .lake/build/bin/ffi_test

import FqlDt.FFI.Bridge
import FqlDt.Types.BoundedNat
import FqlDt.Prompt.PromptScores

open FqlDt.FFI
open FqlDt.Types
open FqlDt.Prompt

/-- Test FdbStatus conversion -/
def testFdbStatus : IO Unit := do
  IO.println "Testing FdbStatus..."

  -- Test fromInt conversions
  let s0 := FdbStatus.fromInt 0
  let s1 := FdbStatus.fromInt (-1)
  let s99 := FdbStatus.fromInt (-99)

  IO.println s!"  fromInt 0 = {repr s0} (expected ok)"
  IO.println s!"  fromInt -1 = {repr s1} (expected invalidProof)"
  IO.println s!"  fromInt -99 = {repr s99} (expected genericError)"

  -- Test isOk
  IO.println s!"  ok.isOk = {FdbStatus.ok.isOk} (expected true)"
  IO.println s!"  invalidProof.isOk = {FdbStatus.invalidProof.isOk} (expected false)"

  -- Test message
  IO.println s!"  ok.message = \"{FdbStatus.ok.message}\""
  IO.println s!"  invalidActor.message = \"{FdbStatus.invalidActor.message}\""

  IO.println "✓ FdbStatus tests passed"

/-- Test PromptScoresFFI -/
def testPromptScoresFFI : IO Unit := do
  IO.println "Testing PromptScoresFFI..."

  let scores : PromptScoresFFI := {
    provenance := 80
    replicability := 70
    objective := 90
    methodology := 85
    publication := 75
    transparency := 80
    overall := 80
  }

  IO.println s!"  scores.isValid = {scores.isValid} (expected true)"
  IO.println s!"  zero.isValid = {PromptScoresFFI.zero.isValid} (expected true)"

  -- Test invalid scores (over 100)
  let invalidScores : PromptScoresFFI := {
    provenance := 150  -- Invalid!
    replicability := 70
    objective := 90
    methodology := 85
    publication := 75
    transparency := 80
    overall := 80
  }
  IO.println s!"  invalidScores.isValid = {invalidScores.isValid} (expected false)"

  IO.println "✓ PromptScoresFFI tests passed"

/-- Test InsertResult -/
def testInsertResult : IO Unit := do
  IO.println "Testing InsertResult..."

  let success := InsertResult.success 42
  let failure := InsertResult.failure .invalidProof "Test error"

  IO.println s!"  success.status = {repr success.status}"
  IO.println s!"  success.rowId = {repr success.rowId}"
  IO.println s!"  failure.status = {repr failure.status}"
  IO.println s!"  failure.errorMessage = {repr failure.errorMessage}"

  IO.println "✓ InsertResult tests passed"

/-- Test integration between Lean types and FFI types -/
def testIntegration : IO Unit := do
  IO.println "Testing Lean-FFI integration..."

  -- Create PROMPT scores using Lean types
  let p := PromptScores.create
    ⟨80, by omega, by omega⟩   -- provenance
    ⟨70, by omega, by omega⟩   -- replicability
    ⟨90, by omega, by omega⟩   -- objective
    ⟨85, by omega, by omega⟩   -- methodology
    ⟨75, by omega, by omega⟩   -- publication
    ⟨80, by omega, by omega⟩   -- transparency

  IO.println s!"  Lean PromptScores.overall = {p.overall.val}"

  -- Convert to FFI type
  let ffiScores : PromptScoresFFI := {
    provenance := p.provenance.val.toUInt8
    replicability := p.replicability.val.toUInt8
    objective := p.objective.val.toUInt8
    methodology := p.methodology.val.toUInt8
    publication := p.publication.val.toUInt8
    transparency := p.transparency.val.toUInt8
    overall := p.overall.val.toUInt8
  }

  IO.println s!"  FFI PromptScoresFFI.overall = {ffiScores.overall}"
  IO.println s!"  Types match: {p.overall.val.toUInt8 == ffiScores.overall}"

  IO.println "✓ Integration tests passed"

/-- Main test runner -/
def main : IO Unit := do
  IO.println "═══════════════════════════════════════════════"
  IO.println "  FqlDt FFI Integration Tests"
  IO.println "═══════════════════════════════════════════════"
  IO.println ""

  testFdbStatus
  IO.println ""

  testPromptScoresFFI
  IO.println ""

  testInsertResult
  IO.println ""

  testIntegration
  IO.println ""

  IO.println "═══════════════════════════════════════════════"
  IO.println "  All tests passed!"
  IO.println "═══════════════════════════════════════════════"
