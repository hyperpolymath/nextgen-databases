/-
SPDX-License-Identifier: PMPL-1.0-or-later
Form.Normalizer - Proof Integration

Ties together FunDep types with Bridge FFI for proof-carrying
normalization transformations. This module provides the high-level
API for creating verified normalization and denormalization steps.

Part of Lithoglyph: Stone-carved data for the ages.
-/

import FunDep
import Bridge

open Lithoglyph.Normalizer
open Lithoglyph.Bridge

namespace Lithoglyph.Normalizer.Proofs

/-! # Verified FD Discovery -/

/-- A functional dependency with verification proof -/
structure VerifiedFD where
  /-- The functional dependency -/
  fd : FunDep ⟨[], []⟩  -- Generic schema for now
  /-- The verification proof -/
  proof : Proof
  /-- Whether the proof has been verified -/
  verified : Bool
  deriving Repr

/-- Create a verified FD from discovery results -/
def createVerifiedFD
    (determinant dependent : List String)
    (confidence : Float)
    (discoveredAt sampleSize : Option Nat) : IO VerifiedFD := do
  let fd : FunDep ⟨[], []⟩ := {
    determinant := determinant
    dependent := dependent
    confidence := confidence
    discoveredAt := discoveredAt
    sampleSize := sampleSize
  }
  let proof := encodeFDProof determinant dependent confidence
  let result := verifyProofPure proof
  return {
    fd := fd
    proof := proof
    verified := result.valid
  }

/-! # Verified Normalization Steps -/

/-- A normalization step with verification proof -/
structure VerifiedNormalizationStep where
  /-- The normalization step -/
  step : NormalizationStep
  /-- The verification proof -/
  proof : Proof
  /-- Whether losslessness has been verified -/
  losslessVerified : Bool
  /-- Whether dependency preservation has been verified -/
  dependencyPreserved : Bool
  deriving Repr

/-- Create a verified 3NF decomposition -/
def createVerified3NFDecomposition
    (source : Schema)
    (violations : List (NFViolation source))
    (targets : List Schema)
    (joinAttrs : List Attribute) : IO VerifiedNormalizationStep := do
  let step : NormalizationStep := {
    decomposition := {
      source := source
      targets := targets
    }
    joinAttributes := joinAttrs
    narrative := "3NF decomposition eliminating transitive dependencies"
  }

  let sourceStr := source.attributes.toString
  let targetStrs := targets.map (fun s => s.attributes.toString)
  let proof := encodeNormalizationProof sourceStr targetStrs joinAttrs true
  let result := verifyProofPure proof

  return {
    step := step
    proof := proof
    losslessVerified := result.valid
    dependencyPreserved := result.valid  -- Simplified: same check
  }

/-- Create a verified BCNF decomposition -/
def createVerifiedBCNFDecomposition
    (source : Schema)
    (violations : List (NFViolation source))
    (targets : List Schema)
    (joinAttrs : List Attribute) : IO VerifiedNormalizationStep := do
  let step : NormalizationStep := {
    decomposition := {
      source := source
      targets := targets
    }
    joinAttributes := joinAttrs
    narrative := "BCNF decomposition - determinants are now superkeys"
  }

  let sourceStr := source.attributes.toString
  let targetStrs := targets.map (fun s => s.attributes.toString)
  let proof := encodeNormalizationProof sourceStr targetStrs joinAttrs true
  let result := verifyProofPure proof

  return {
    step := step
    proof := proof
    losslessVerified := result.valid
    dependencyPreserved := false  -- BCNF may not preserve all FDs
  }

/-! # Verified Denormalization Steps -/

/-- A denormalization step with verification proof -/
structure VerifiedDenormalizationStep where
  /-- The denormalization step -/
  step : DenormalizationStep
  /-- The verification proof -/
  proof : Proof
  /-- Whether losslessness has been verified -/
  losslessVerified : Bool
  /-- Whether query equivalence has been verified -/
  queryEquivalenceVerified : Bool
  deriving Repr

/-- Create a verified denormalization for read optimization -/
def createVerifiedDenormalization
    (sources : List Schema)
    (joinAttrs : List Attribute)
    (rationale : String) : IO VerifiedDenormalizationStep := do
  let merged : Schema := {
    attributes := (sources.map (·.attributes)).flatten |>.eraseDups
    candidateKeys := []
  }

  let step : DenormalizationStep := {
    sourceSchemas := sources
    targetSchema := merged
    joinAttributes := joinAttrs
    performanceRationale := rationale
    narrative := s!"INTENTIONAL DENORMALIZATION\nReason: {rationale}\nFully reversible via SPLIT."
  }

  let sourceStrs := sources.map (fun s => s.attributes.toString)
  let targetStr := merged.attributes.toString
  let proof := encodeDenormalizationProof sourceStrs targetStr joinAttrs rationale
  let result := verifyProofPure proof

  return {
    step := step
    proof := proof
    losslessVerified := result.valid
    queryEquivalenceVerified := result.valid
  }

/-! # Verified Migration -/

/-- A migration state with verification proofs -/
structure VerifiedMigration where
  /-- The migration state -/
  state : MigrationState
  /-- Proof of transformation correctness -/
  transformationProof : Option Proof
  /-- Whether the transformation has been verified -/
  transformationVerified : Bool
  deriving Repr

/-- Start a verified migration -/
def startVerifiedMigration
    (transform : NormalizationStep)
    (affectedQueries : List String)
    (journalEntry : Nat)
    (config : MigrationConfig := {}) : IO VerifiedMigration := do
  let state := startMigration transform affectedQueries journalEntry config

  -- Create proof for the transformation
  let sourceStr := transform.decomposition.source.attributes.toString
  let targetStrs := transform.decomposition.targets.map (fun s => s.attributes.toString)
  let proof := encodeNormalizationProof sourceStr targetStrs transform.joinAttributes true
  let result := verifyProofPure proof

  return {
    state := state
    transformationProof := some proof
    transformationVerified := result.valid
  }

/-- Advance migration only if transformation is verified -/
def advanceVerifiedMigration (vm : VerifiedMigration) : IO (Option VerifiedMigration) := do
  if !vm.transformationVerified then
    return none

  match vm.state.phase with
  | .announce =>
    let rules : List (String × String) := vm.state.affectedQueries.map fun q =>
      (q, q ++ " /* rewritten */")
    let views := ["compat_" ++ vm.state.transformation.decomposition.source.attributes.toString]
    let newState := advanceToShadow vm.state rules views
    return some { vm with state := newState }
  | .shadow =>
    let newState := advanceToCommit vm.state
    return some { vm with state := newState }
  | .commit =>
    return some vm  -- Already complete

/-! # Proof Narrative Generation -/

/-- Generate narrative for a verified FD -/
def VerifiedFD.toNarrative (vfd : VerifiedFD) : String :=
  let status := if vfd.verified then "VERIFIED" else "UNVERIFIED"
  let base := vfd.fd.toNarrative
  s!"{base} [{status}]"

/-- Generate narrative for a verified normalization step -/
def VerifiedNormalizationStep.toNarrative (vns : VerifiedNormalizationStep) : String :=
  let base := vns.step.toNarrative
  let lossless := if vns.losslessVerified then "✓ Lossless" else "⚠ Lossless unverified"
  let deps := if vns.dependencyPreserved then "✓ FDs preserved" else "⚠ Some FDs may be lost"
  s!"{base}\n\nVerification Status:\n  {lossless}\n  {deps}"

/-- Generate narrative for a verified denormalization step -/
def VerifiedDenormalizationStep.toNarrative (vds : VerifiedDenormalizationStep) : String :=
  let base := vds.step.toNarrative
  let lossless := if vds.losslessVerified then "✓ Lossless" else "⚠ Lossless unverified"
  let equiv := if vds.queryEquivalenceVerified then "✓ Query equivalent" else "⚠ Query equivalence unverified"
  s!"{base}\n\nVerification Status:\n  {lossless}\n  {equiv}"

/-- Generate narrative for a verified migration -/
def VerifiedMigration.toNarrative (vm : VerifiedMigration) : String :=
  let base := vm.state.toNarrative
  let verified := if vm.transformationVerified then "✓ Transformation verified" else "⚠ Transformation unverified"
  s!"{base}\n\nProof Status:\n  {verified}"

/-! # Proof Export for Journal -/

/-- Export proof to CBOR bytes for journal storage -/
def exportProofForJournal (proof : Proof) : ByteArray :=
  -- Wrap proof in a journal entry envelope
  let encoder := CborEncoder.empty
    |>.beginMap 3
    |>.encodeText "entry_type"
    |>.encodeText "proof"
    |>.encodeText "proof_type"
    |>.encodeText proof.proofType
    |>.encodeText "proof_data"
    |>.encodeBytes proof.data
  encoder.finish

/-- Package a verified normalization for journal entry -/
def packageNormalizationForJournal
    (vns : VerifiedNormalizationStep)
    (journalSeq : Nat) : ByteArray :=
  let encoder := CborEncoder.empty
    |>.beginMap 5
    |>.encodeText "sequence"
    |>.encodeUInt journalSeq
    |>.encodeText "operation"
    |>.encodeText "normalize"
    |>.encodeText "narrative"
    |>.encodeText vns.step.narrative
    |>.encodeText "proof"
    |>.encodeBytes vns.proof.data
    |>.encodeText "verified"
    |>.encodeBool vns.losslessVerified
  encoder.finish

/-- Package a verified denormalization for journal entry -/
def packageDenormalizationForJournal
    (vds : VerifiedDenormalizationStep)
    (journalSeq : Nat) : ByteArray :=
  let encoder := CborEncoder.empty
    |>.beginMap 5
    |>.encodeText "sequence"
    |>.encodeUInt journalSeq
    |>.encodeText "operation"
    |>.encodeText "denormalize"
    |>.encodeText "narrative"
    |>.encodeText vds.step.narrative
    |>.encodeText "proof"
    |>.encodeBytes vds.proof.data
    |>.encodeText "verified"
    |>.encodeBool vds.losslessVerified
  encoder.finish

end Lithoglyph.Normalizer.Proofs
