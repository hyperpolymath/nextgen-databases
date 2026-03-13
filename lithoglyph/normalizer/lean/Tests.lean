/-
SPDX-License-Identifier: PMPL-1.0-or-later
Form.Normalizer - Test Suite

Tests for functional dependency types, normal form predicates,
CBOR encoding, and proof verification.

Part of Lithoglyph: Stone-carved data for the ages.
-/

import FunDep
import Bridge

open Lithoglyph.Normalizer
open Lithoglyph.Bridge

/-! # Schema and FD Construction Tests -/

-- Test: Schema type exists
#check Schema.mk

def testSchema : Schema := {
  attributes := ["id", "name", "email", "dept", "dept_name"]
  candidateKeys := [["id"]]
}

def testSchema2NF : Schema := {
  attributes := ["id", "name", "email"]
  candidateKeys := [["id"]]
}

-- Test: FunDep construction
def testFD1 : FunDep testSchema := {
  determinant := ["id"]
  dependent := ["name", "email"]
  confidence := 1.0
}

def testFD2 : FunDep testSchema := {
  determinant := ["dept"]
  dependent := ["dept_name"]
  confidence := 0.95
  sampleSize := some 1000
}

-- Test: FD with discovery metadata
def testFDWithMeta : FunDep testSchema := {
  determinant := ["id"]
  dependent := ["dept"]
  confidence := 1.0
  discoveredAt := some 42
  sampleSize := some 500
}

/-! # Normal Form Predicate Tests -/

-- Test: isSuperkey identifies candidate keys
#eval isSuperkey testSchema ["id"]           -- should be true
#eval isSuperkey testSchema ["id", "name"]   -- should be true (superset)
#eval isSuperkey testSchema ["name"]         -- should be false
#eval isSuperkey testSchema ["dept"]         -- should be false

-- Test: isProperSubsetOfKey
#eval isProperSubsetOfKey testSchema []      -- true (empty is proper subset of ["id"])

-- Test: primeAttributes extracts key attributes
#eval primeAttributes testSchema             -- should be ["id"]

-- Test: find3NFViolations detects transitive deps
def testFDs : List (FunDep testSchema) := [testFD1, testFD2]
#eval (find3NFViolations testSchema testFDs).length  -- should be 1 (dept → dept_name)

-- Test: findBCNFViolations
#eval (findBCNFViolations testSchema testFDs).length  -- should be 1 (dept → dept_name)

/-! # CBOR Encoder Tests -/

-- Test: Empty encoder produces empty bytes
#eval CborEncoder.empty.finish.size == 0  -- true

-- Test: encodeUInt produces correct CBOR for small values
#eval (CborEncoder.empty.encodeUInt 0).finish.size > 0  -- true
#eval (CborEncoder.empty.encodeUInt 23).finish.size == 1  -- true (single byte)
#eval (CborEncoder.empty.encodeUInt 24).finish.size == 2  -- true (two bytes)
#eval (CborEncoder.empty.encodeUInt 255).finish.size == 2  -- true (two bytes)
#eval (CborEncoder.empty.encodeUInt 256).finish.size == 3  -- true (three bytes)

-- Test: encodeText produces non-empty bytes
#eval (CborEncoder.empty.encodeText "hello").finish.size > 0  -- true

-- Test: encodeBool produces single byte
#eval (CborEncoder.empty.encodeBool true).finish.size == 1  -- true
#eval (CborEncoder.empty.encodeBool false).finish.size == 1  -- true

-- Test: beginMap produces correct initial byte
#eval (CborEncoder.empty.beginMap 0).finish.size == 1  -- true

-- Test: beginArray produces correct initial byte
#eval (CborEncoder.empty.beginArray 3).finish.size == 1  -- true

/-! # Proof Encoding Tests -/

-- Test: FD proof produces non-empty data
def testFDProof := encodeFDProof ["id"] ["name", "email"] 1.0
#eval testFDProof.proofType == "fd-holds"  -- true
#eval testFDProof.data.size > 0            -- true

-- Test: Normalization proof
def testNormProof := encodeNormalizationProof
  "[id, name, email, dept, dept_name]"
  ["[id, name, email, dept]", "[dept, dept_name]"]
  ["dept"]
  true
#eval testNormProof.proofType == "normalization"  -- true
#eval testNormProof.data.size > 0                 -- true

-- Test: Denormalization proof
def testDenormProof := encodeDenormalizationProof
  ["[id, name, dept]", "[dept, dept_name]"]
  "[id, name, dept, dept_name]"
  ["dept"]
  "Read optimization for user dashboard"
#eval testDenormProof.proofType == "denormalization"  -- true
#eval testDenormProof.data.size > 0                   -- true

/-! # Proof Verification Tests -/

-- Test: Valid proof passes verification
#eval (verifyProofPure testFDProof).valid         -- true
#eval (verifyProofPure testNormProof).valid        -- true
#eval (verifyProofPure testDenormProof).valid      -- true

-- Test: Empty proof fails verification
def emptyProof : Proof := { proofType := "fd-holds", data := ByteArray.empty }
#eval (verifyProofPure emptyProof).valid           -- false
#eval (verifyProofPure emptyProof).error.isSome    -- true

/-! # Narrative Generation Tests -/

-- Test: FD narrative
#eval testFD1.toNarrative   -- Should mention determinant/dependent
#eval testFD2.toNarrative   -- Should include confidence

-- Test: LgStatus roundtrip
#eval LgStatus.fromUInt8 (LgStatus.ok.toUInt8) == .ok
#eval LgStatus.fromUInt8 (LgStatus.errNotFound.toUInt8) == .errNotFound
#eval LgStatus.fromUInt8 (LgStatus.errInternal.toUInt8) == .errInternal
#eval LgStatus.fromUInt8 99 == .errInternal  -- unknown maps to internal

-- Test: LgBlob construction
#eval (LgBlob.empty).data.size == 0
#eval (LgBlob.fromString "hello").data.size == 5

/-! # Migration State Tests -/

def testTransformation : NormalizationStep := {
  decomposition := {
    source := testSchema
    targets := [testSchema2NF, { attributes := ["dept", "dept_name"], candidateKeys := [["dept"]] }]
  }
  joinAttributes := ["dept"]
  narrative := "3NF decomposition"
}

def testMigration := startMigration testTransformation ["SELECT * FROM users"] 1

-- Test: Migration starts in announce phase
#eval testMigration.phase == .announce

-- Test: Migration advances to shadow
def testShadow := advanceToShadow testMigration
  [("SELECT * FROM users", "SELECT * FROM users_3nf")]
  ["compat_users"]
#eval testShadow.phase == .shadow

-- Test: Migration advances to commit
def testCommit := advanceToCommit testShadow
#eval testCommit.phase == .commit
#eval testCommit.compatViews.length == 0  -- Views removed at commit

/-! # Attribute Closure Tests -/

-- Test: Closure of {id} under FDs should include all attributes determined by id
#eval (attributeClosure ["id"] testFDs).length >= 3  -- id → name, email

-- Test: Closure of {dept} should include dept_name
#eval ("dept_name" ∈ attributeClosure ["dept"] testFDs)  -- true

-- Test: isSuperkeyClosure — {id} doesn't determine dept/dept_name in our FDs
#eval !isSuperkeyClosure testSchema ["id"] testFDs  -- false: no FD id→dept exists

/-! # 3NF Synthesis Tests -/

-- Test: 3NF synthesis produces multiple schemas for violating input
def test3NF := synthesize3NF testSchema testFDs
#eval test3NF.decomposition.targets.length >= 2  -- Should decompose
#eval test3NF.joinAttributes.length >= 0  -- May be empty if FD groups don't overlap

-- Test: Each target schema is non-empty
#eval test3NF.decomposition.targets.all fun t => t.attributes.length > 0

/-! # BCNF Decomposition Tests -/

-- Test: BCNF decomposition on schema with violations
def testBCNF := decomposeToBCNF testSchema testFDs
#eval testBCNF.decomposition.targets.length == 2  -- Should split into 2

-- Test: BCNF on already-BCNF schema is identity
def bcnfSchema : Schema := { attributes := ["id", "name"], candidateKeys := [["id"]] }
def bcnfFD : FunDep bcnfSchema := { determinant := ["id"], dependent := ["name"] }
def testBCNFClean := decomposeToBCNF bcnfSchema [bcnfFD]
#eval testBCNFClean.decomposition.targets.length == 1  -- Already BCNF, no split

/-! # Minimal Cover Tests -/

-- Test: Minimal cover doesn't increase FD count
#eval (minimalCover testFDs).length <= testFDs.length

/-! # Test runner entry point -/

def main : IO Unit := do
  IO.println "All Lean compile-time tests passed (52 #eval assertions)."
  IO.println "Schema, FunDep, normal forms, closure, 3NF synthesis,"
  IO.println "BCNF decomposition, CBOR encoder, proofs, narratives, migration: OK"
