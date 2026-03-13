# GQL-dt Normalization Types

**Version**: 0.1.0
**Status**: Specification
**Date**: 2026-01-11
**License**: MPL-2.0

## Overview

This specification defines dependent types for encoding functional dependencies, normal forms, and proof-carrying schema normalization in GQL-dt. These types enable:

- **Compile-time verification** that schemas satisfy target normal forms
- **Proof-carrying normalization** with equivalence guarantees
- **Type-safe schema evolution** with reversibility
- **Integration with Form.Normalizer** for automatic FD discovery

## Table of Contents

1. [Functional Dependencies](#1-functional-dependencies)
2. [Normal Form Predicates](#2-normal-form-predicates)
3. [Normalization Steps](#3-normalization-steps)
4. [Multi-Valued Dependencies](#4-multi-valued-dependencies)
5. [Integration with Form.Normalizer](#5-integration-with-formnormalizer)
6. [GQL Syntax Extensions](#6-gql-syntax-extensions)
7. [Complete Examples](#7-complete-examples)

---

## 1. Functional Dependencies

### 1.1 Core Types

```lean
/-- An attribute in a schema -/
structure Attribute where
  name : String
  type : GQLType
  deriving DecidableEq

/-- A set of attributes -/
abbrev AttrSet := List Attribute

/-- A functional dependency X → Y -/
structure FunDep (S : Schema) where
  determinant : AttrSet      -- X (left-hand side)
  dependent : AttrSet        -- Y (right-hand side)
  det_in_schema : determinant ⊆ S.attributes
  dep_in_schema : dependent ⊆ S.attributes

/-- Proof that an FD holds in a relation -/
structure FDHolds (fd : FunDep S) (r : Relation S) : Prop where
  proof : ∀ t1 t2 : Tuple S,
    (∀ a ∈ fd.determinant, t1.get a = t2.get a) →
    (∀ a ∈ fd.dependent, t1.get a = t2.get a)
```

### 1.2 FD Properties

```lean
/-- A trivial FD (Y ⊆ X) -/
def FunDep.isTrivial (fd : FunDep S) : Prop :=
  fd.dependent ⊆ fd.determinant

/-- The determinant is a superkey -/
def FunDep.determinantIsSuperkey (fd : FunDep S) (keys : List AttrSet) : Prop :=
  ∃ k ∈ keys, k ⊆ fd.determinant

/-- The dependent attributes are all prime (part of some candidate key) -/
def FunDep.dependentIsPrime (fd : FunDep S) (keys : List AttrSet) : Prop :=
  ∀ a ∈ fd.dependent, ∃ k ∈ keys, a ∈ k

/-- Partial dependency: determinant is proper subset of a key -/
def FunDep.isPartial (fd : FunDep S) (keys : List AttrSet) : Prop :=
  ∃ k ∈ keys, fd.determinant ⊂ k ∧ ¬(fd.dependent ⊆ fd.determinant)

/-- Transitive dependency: X → Y → Z where Y is not a superkey -/
def FunDep.isTransitive (fd1 fd2 : FunDep S) (keys : List AttrSet) : Prop :=
  fd1.dependent = fd2.determinant ∧
  ¬fd2.determinantIsSuperkey keys
```

### 1.3 Armstrong's Axioms

```lean
/-- Reflexivity: If Y ⊆ X, then X → Y -/
theorem fd_reflexivity (X Y : AttrSet) (h : Y ⊆ X) :
    FDHolds ⟨X, Y, hX, hY⟩ r := by
  constructor
  intro t1 t2 hdet a ha
  exact hdet a (h ha)

/-- Augmentation: If X → Y, then XZ → YZ -/
theorem fd_augmentation (fd : FunDep S) (Z : AttrSet) (h : FDHolds fd r) :
    FDHolds ⟨fd.determinant ++ Z, fd.dependent ++ Z, _, _⟩ r := by
  constructor
  intro t1 t2 hdet a ha
  cases List.mem_append.mp ha with
  | inl hy => exact h.proof t1 t2 (fun b hb => hdet b (List.mem_append_left Z hb)) a hy
  | inr hz => exact hdet a (List.mem_append_right fd.determinant hz)

/-- Transitivity: If X → Y and Y → Z, then X → Z -/
theorem fd_transitivity (fd1 : FunDep S) (fd2 : FunDep S)
    (h1 : FDHolds fd1 r) (h2 : FDHolds fd2 r) (heq : fd1.dependent = fd2.determinant) :
    FDHolds ⟨fd1.determinant, fd2.dependent, _, _⟩ r := by
  constructor
  intro t1 t2 hdet a ha
  have hmid : ∀ b ∈ fd2.determinant, t1.get b = t2.get b := by
    intro b hb
    rw [← heq] at hb
    exact h1.proof t1 t2 hdet b hb
  exact h2.proof t1 t2 hmid a ha
```

### 1.4 Discovered FDs with Confidence

```lean
/-- An FD discovered from data with a confidence score -/
structure DiscoveredFD (S : Schema) where
  fd : FunDep S
  confidence : BoundedFloat 0.0 1.0
  sampleSize : Nat
  discoveredAt : Timestamp
  journalEntry : JournalEntryId

/-- An approximate FD (confidence < 1.0) -/
def DiscoveredFD.isApproximate (dfd : DiscoveredFD S) : Prop :=
  dfd.confidence.val < 1.0

/-- Threshold for treating approximate FD as exact -/
def approximateFDThreshold : Float := 0.99
```

---

## 2. Normal Form Predicates

### 2.1 First Normal Form (1NF)

```lean
/-- All attributes have atomic (non-composite, non-repeating) types -/
def FirstNormalForm (S : Schema) : Prop :=
  ∀ attr ∈ S.attributes, attr.type.isAtomic

/-- Atomic type check -/
def GQLType.isAtomic : GQLType → Bool
  | .Int => true
  | .Float => true
  | .String => true
  | .Bool => true
  | .UUID => true
  | .Timestamp => true
  | .Array _ => false      -- Not atomic
  | .Object _ => false     -- Not atomic
  | .Option t => t.isAtomic
  | _ => true
```

### 2.2 Second Normal Form (2NF)

```lean
/-- 1NF + no partial dependencies on candidate keys -/
def SecondNormalForm (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) : Prop :=
  FirstNormalForm S ∧
  ∀ fd ∈ fds, ¬fd.isPartial keys

/-- Equivalently: all non-prime attributes fully depend on entire key -/
def SecondNormalForm' (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) : Prop :=
  FirstNormalForm S ∧
  ∀ fd ∈ fds, ∀ a ∈ fd.dependent,
    (∃ k ∈ keys, a ∈ k) ∨  -- a is prime
    (∀ k ∈ keys, fd.determinant ⊇ k)  -- determinant contains full key

theorem second_nf_equiv (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) :
    SecondNormalForm S fds keys ↔ SecondNormalForm' S fds keys := by
  sorry -- Proof of equivalence
```

### 2.3 Third Normal Form (3NF)

```lean
/-- 2NF + no transitive dependencies on candidate keys -/
def ThirdNormalForm (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) : Prop :=
  SecondNormalForm S fds keys ∧
  ∀ fd ∈ fds,
    fd.isTrivial ∨
    fd.determinantIsSuperkey keys ∨
    fd.dependentIsPrime keys

/-- Alternative definition: every non-trivial FD has superkey determinant or prime dependent -/
def ThirdNormalForm' (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) : Prop :=
  FirstNormalForm S ∧
  ∀ fd ∈ fds, ¬fd.isTrivial →
    fd.determinantIsSuperkey keys ∨ fd.dependentIsPrime keys
```

### 2.4 Boyce-Codd Normal Form (BCNF)

```lean
/-- Every non-trivial FD has a superkey as determinant -/
def BCNF (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) : Prop :=
  FirstNormalForm S ∧
  ∀ fd ∈ fds, fd.isTrivial ∨ fd.determinantIsSuperkey keys

/-- BCNF implies 3NF -/
theorem bcnf_implies_3nf (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) :
    BCNF S fds keys → ThirdNormalForm S fds keys := by
  intro ⟨h1nf, hbcnf⟩
  constructor
  · constructor
    · exact h1nf
    · intro fd hfd
      cases hbcnf fd hfd with
      | inl htriv => left; exact htriv
      | inr hsuper => right; left; exact hsuper
  · intro fd hfd
    cases hbcnf fd hfd with
    | inl htriv => left; exact htriv
    | inr hsuper => right; left; exact hsuper

/-- 3NF does not imply BCNF (counterexample exists) -/
-- The classic counterexample: R(A, B, C) with FDs {AB → C, C → B}
-- This is in 3NF but not BCNF because C → B and C is not a superkey
```

### 2.5 Normal Form Hierarchy

```lean
/-- The normal form of a schema -/
inductive NormalForm where
  | unnormalized : NormalForm
  | first : NormalForm
  | second : NormalForm
  | third : NormalForm
  | bcnf : NormalForm
  | fourth : NormalForm  -- See MVD section
  | fifth : NormalForm   -- Join dependencies (future)
  deriving DecidableEq, Ord

/-- Determine the highest normal form a schema satisfies -/
def Schema.normalForm (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) : NormalForm :=
  if BCNF S fds keys then .bcnf
  else if ThirdNormalForm S fds keys then .third
  else if SecondNormalForm S fds keys then .second
  else if FirstNormalForm S then .first
  else .unnormalized

/-- Normal form ordering -/
instance : LE NormalForm where
  le a b := a.toNat ≤ b.toNat
  where
    toNat : NormalForm → Nat
      | .unnormalized => 0
      | .first => 1
      | .second => 2
      | .third => 3
      | .bcnf => 4
      | .fourth => 5
      | .fifth => 6
```

---

## 3. Normalization Steps

### 3.1 Schema Transformation

```lean
/-- A transformation from one schema to another -/
structure SchemaTransform where
  source : Schema
  target : Schema
  /-- Forward transformation function -/
  forward : Relation source → Relation target
  /-- Inverse transformation function -/
  inverse : Relation target → Relation source

/-- Proof that a transformation is lossless (reversible) -/
structure LosslessTransform (t : SchemaTransform) : Prop where
  roundTrip : ∀ r : Relation t.source, t.inverse (t.forward r) = r

/-- Proof that a transformation preserves all FDs -/
structure PreservesFDs (t : SchemaTransform) (fds : List (FunDep t.source)) : Prop where
  preserved : ∀ fd ∈ fds, ∃ fd' : FunDep t.target,
    FDHolds fd r → FDHolds fd' (t.forward r)
```

### 3.2 Normalization Step

```lean
/-- A single normalization step with proofs -/
structure NormalizationStep where
  transform : SchemaTransform
  /-- The source normal form -/
  sourceNF : NormalForm
  /-- The target normal form (must be higher) -/
  targetNF : NormalForm
  /-- Proof that target NF is higher -/
  improves : sourceNF < targetNF
  /-- Proof the transformation is lossless -/
  lossless : LosslessTransform transform
  /-- Which FDs are preserved (may lose some in BCNF decomposition) -/
  fdPreservation : FDPreservationStatus
  /-- Narrative explanation -/
  rationale : NonEmptyString

/-- FD preservation status -/
inductive FDPreservationStatus where
  | allPreserved : PreservesFDs t fds → FDPreservationStatus
  | somePreserved : (preserved : List (FunDep source)) →
                    (lost : List (FunDep source)) →
                    (lostRationale : NonEmptyString) →
                    FDPreservationStatus
```

### 3.3 Decomposition Operations

```lean
/-- Decompose a schema by splitting on a violating FD -/
def decomposeOn (S : Schema) (fd : FunDep S) : SchemaTransform :=
  let s1Attrs := fd.determinant ++ fd.dependent
  let s2Attrs := fd.determinant ++ (S.attributes.filter (· ∉ fd.dependent))
  {
    source := S
    target := Schema.product (Schema.mk s1Attrs) (Schema.mk s2Attrs)
    forward := fun r =>
      let r1 := r.project s1Attrs
      let r2 := r.project s2Attrs
      Relation.product r1 r2
    inverse := fun rProd =>
      let (r1, r2) := Relation.unproduct rProd
      r1.naturalJoin r2 fd.determinant
  }

/-- Theorem: decomposition on FD is lossless if FD holds -/
theorem decomposition_lossless (S : Schema) (fd : FunDep S) (r : Relation S)
    (h : FDHolds fd r) :
    LosslessTransform (decomposeOn S fd) := by
  constructor
  intro r
  -- The key insight: natural join on determinant reconstructs original
  -- because the FD guarantees no spurious tuples
  sorry
```

### 3.4 Normalization Algorithms

```lean
/-- Normalize to 3NF using synthesis algorithm (preserves all FDs) -/
def normalizeTo3NF (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) :
    List NormalizationStep :=
  sorry -- Implementation of 3NF synthesis

/-- Normalize to BCNF using decomposition (may lose FDs) -/
def normalizeToBCNF (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet) :
    List NormalizationStep :=
  sorry -- Implementation of BCNF decomposition

/-- Combined normalization with strategy choice -/
inductive NormalizationStrategy where
  | to3NF : NormalizationStrategy      -- Preserve all FDs
  | toBCNF : NormalizationStrategy     -- Stricter, may lose FDs
  | toBCNFPreferPreserving : NormalizationStrategy  -- BCNF if no FD loss, else 3NF

def normalize (S : Schema) (fds : List (FunDep S)) (keys : List AttrSet)
    (strategy : NormalizationStrategy) : List NormalizationStep :=
  match strategy with
  | .to3NF => normalizeTo3NF S fds keys
  | .toBCNF => normalizeToBCNF S fds keys
  | .toBCNFPreferPreserving =>
      let bcnfSteps := normalizeToBCNF S fds keys
      if bcnfSteps.all (·.fdPreservation.isAllPreserved) then bcnfSteps
      else normalizeTo3NF S fds keys
```

---

## 4. Multi-Valued Dependencies

### 4.1 MVD Definition

```lean
/-- A multi-valued dependency X →→ Y -/
structure MVD (S : Schema) where
  determinant : AttrSet
  dependent : AttrSet
  det_in_schema : determinant ⊆ S.attributes
  dep_in_schema : dependent ⊆ S.attributes
  /-- Y is disjoint from X -/
  disjoint : determinant ∩ dependent = []

/-- MVD holds in a relation: tuple swapping property -/
structure MVDHolds (mvd : MVD S) (r : Relation S) : Prop where
  proof : ∀ t1 t2 : Tuple S,
    (∀ a ∈ mvd.determinant, t1.get a = t2.get a) →
    ∃ t3 : Tuple S, t3 ∈ r ∧
      (∀ a ∈ mvd.determinant, t3.get a = t1.get a) ∧
      (∀ a ∈ mvd.dependent, t3.get a = t1.get a) ∧
      (∀ a ∈ S.attributes \ (mvd.determinant ++ mvd.dependent), t3.get a = t2.get a)

/-- Every FD implies an MVD -/
theorem fd_implies_mvd (fd : FunDep S) (h : FDHolds fd r) :
    MVDHolds ⟨fd.determinant, fd.dependent, _, _, _⟩ r := by
  sorry

/-- Trivial MVD -/
def MVD.isTrivial (mvd : MVD S) : Prop :=
  mvd.dependent ⊆ mvd.determinant ∨
  mvd.determinant ++ mvd.dependent = S.attributes
```

### 4.2 Fourth Normal Form (4NF)

```lean
/-- BCNF + no non-trivial MVDs where determinant is not a superkey -/
def FourthNormalForm (S : Schema) (fds : List (FunDep S)) (mvds : List (MVD S))
    (keys : List AttrSet) : Prop :=
  BCNF S fds keys ∧
  ∀ mvd ∈ mvds, mvd.isTrivial ∨ mvd.determinantIsSuperkey keys
  where
    determinantIsSuperkey (mvd : MVD S) := ∃ k ∈ keys, k ⊆ mvd.determinant

/-- 4NF implies BCNF -/
theorem fourth_nf_implies_bcnf (S : Schema) (fds : List (FunDep S)) (mvds : List (MVD S))
    (keys : List AttrSet) :
    FourthNormalForm S fds mvds keys → BCNF S fds keys := by
  intro ⟨hbcnf, _⟩
  exact hbcnf
```

---

## 5. Integration with Form.Normalizer

### 5.1 Bidirectional FFI

```zig
/// Zig FFI for normalization proofs
/// Forward: Form.Normalizer → GQL-dt (for proof verification)
pub export fn fdb_verify_normalization_proof(
    db: *FdbDb,
    step_blob: [*]const u8,
    step_len: usize,
    proof_blob: [*]const u8,
    proof_len: usize,
) callconv(.C) FdbStatus;

/// Reverse: GQL-dt → Form.Normalizer (register proof checker)
pub export fn fdb_register_normalization_verifier(
    db: *FdbDb,
    verifier: *const fn (
        source_schema: [*]const u8,
        target_schema: [*]const u8,
        proof: [*]const u8,
        proof_len: usize,
    ) callconv(.C) bool,
) callconv(.C) FdbStatus;

/// Get discovered FDs as typed structures
pub export fn fdb_get_discovered_fds(
    db: *FdbDb,
    collection: [*:0]const u8,
    out_fds: *[*]u8,
    out_len: *usize,
) callconv(.C) FdbStatus;
```

### 5.2 Proof Obligations

```lean
/-- Required proofs for applying a normalization step -/
structure NormalizationProofObligation (step : NormalizationStep) where
  /-- Proof that source schema exists -/
  sourceExists : SchemaExists step.transform.source
  /-- Proof that transformation is lossless -/
  lossless : LosslessTransform step.transform
  /-- Proof that target achieves claimed normal form -/
  achievesTarget : step.targetNF.satisfiedBy step.transform.target step.fds step.keys
  /-- Authorization to apply -/
  authorized : AuthorizedToNormalize actor step.transform.source

/-- Verify proof obligation before applying -/
def verifyNormalization (step : NormalizationStep)
    (proof : NormalizationProofObligation step) : IO (Except String Unit) := do
  -- Verify all proof components
  if ¬proof.lossless.verify then
    return .error "Lossless proof verification failed"
  if ¬proof.achievesTarget.verify then
    return .error "Target normal form proof failed"
  return .ok ()
```

---

## 6. GQL Syntax Extensions

### 6.1 Schema Definition with Normal Form

```gql
-- Declare target normal form
CREATE COLLECTION employees (
  employee_id : UUID PRIMARY KEY,
  name : NonEmptyString,
  department : NonEmptyString,
  dept_location : NonEmptyString,
  salary : BoundedNat 0 10000000
) WITH DEPENDENT_TYPES
  TARGET_NORMAL_FORM BCNF;  -- Compile error if schema violates BCNF
```

### 6.2 Functional Dependency Declaration

```gql
-- Explicit FD declaration
CREATE COLLECTION employees (
  employee_id : UUID PRIMARY KEY,
  name : NonEmptyString,
  department : NonEmptyString,
  dept_location : NonEmptyString
) WITH DEPENDENT_TYPES
  FUNCTIONAL_DEPENDENCIES (
    employee_id -> name, department, salary;
    department -> dept_location
  );

-- Type checker: Warning - transitive dependency violates 3NF
```

### 6.3 Normalization Commands

```gql
-- Discover FDs
DISCOVER DEPENDENCIES
FROM employees
SAMPLE 10000
CONFIDENCE 0.95
RETURNING (List (DiscoveredFD EmployeeSchema));

-- Check normal form
CHECK NORMAL_FORM employees
AGAINST BCNF
RETURNING (Either
  (proof : BCNF EmployeeSchema discoveredFDs keys)
  (violations : List (FunDep EmployeeSchema)));

-- Propose normalization
PROPOSE NORMALIZATION employees
TO BCNF
STRATEGY PreferPreserving
RETURNING (List NormalizationStep);

-- Apply normalization with proof
APPLY NORMALIZATION proposal_id
WITH_PROOF {
  lossless: by decomposition_lossless,
  achieves_bcnf: by bcnf_decomposition_correct,
  authorized: AdminAuth.normalize
}
RATIONALE "Eliminating transitive dependency department -> dept_location";
```

---

## 7. Complete Examples

### 7.1 Employee Schema Normalization

```gql
-- Initial schema (2NF, violates 3NF)
CREATE COLLECTION employees_raw (
  employee_id : UUID PRIMARY KEY,
  name : NonEmptyString,
  department : NonEmptyString,
  dept_location : NonEmptyString,  -- Transitive dependency!
  salary : BoundedNat 0 10000000
) WITH DEPENDENT_TYPES;

-- Discover FDs
DISCOVER DEPENDENCIES FROM employees_raw
RETURNING discovered_fds;

-- Result:
-- [
--   { determinant: [employee_id], dependent: [name, department, salary], confidence: 1.0 },
--   { determinant: [department], dependent: [dept_location], confidence: 0.998 }
-- ]

-- Check normal form
CHECK NORMAL_FORM employees_raw AGAINST 3NF
RETURNING nf_check;

-- Result: Left (violations: [department -> dept_location is transitive])

-- Propose fix
PROPOSE NORMALIZATION employees_raw TO 3NF
RETURNING proposal;

-- Result:
-- NormalizationStep {
--   transform: decomposeOn employees_raw (department -> dept_location),
--   sourceNF: second,
--   targetNF: third,
--   lossless: <proof>,
--   fdPreservation: allPreserved <proof>,
--   rationale: "Split transitive dependency: department determines dept_location"
-- }

-- Apply with proof
APPLY NORMALIZATION proposal
WITH_PROOF {
  lossless: by decomposition_lossless employees_raw fd h,
  achieves_3nf: by third_nf_after_decomposition,
  all_fds_preserved: by synthesis_preserves_fds
}
RATIONALE "Normalizing to 3NF to eliminate update anomalies";

-- Result: Two new collections
-- employees(employee_id, name, department, salary)  -- 3NF
-- departments(department, dept_location)             -- 3NF
```

### 7.2 Type-Safe Query After Normalization

```gql
-- Query across normalized tables (type-safe join)
SELECT (
  e : Employee | e.salary > 50000,
  d : Department
)
FROM employees e
  JOIN departments d ON e.department = d.department
WHERE d.dept_location = 'London'
RETURNING (List (Employee × Department) |
           ∀ (e, d) ∈ result, e.salary > 50000 ∧ d.dept_location = 'London');

-- Type proves all results satisfy conditions!
```

### 7.3 Reversible Normalization

```gql
-- Apply normalization
APPLY NORMALIZATION proposal
WITH_INVERSE (
  DENORMALIZE employees, departments
  INTO employees_raw
  ON department
)
WITH_PROOF {
  inverse_correct: by natural_join_inverse,
  roundtrip: by decomposition_join_identity
}
RATIONALE "Normalizing to 3NF";

-- Later: Rollback if needed
ROLLBACK NORMALIZATION proposal
REASON "Performance regression in reporting queries"
WITH_PROOF {
  inverse_exists: proposal.lossless,
  authorized: AdminAuth.denormalize
};
```

---

## Appendix A: Proof Tactics

```lean
namespace Lithoglyph.Normalization.Tactics

/-- Solve FD-related goals -/
syntax "fd_tactic" : tactic
macro_rules
  | `(tactic| fd_tactic) => `(tactic|
      first
      | apply fd_reflexivity
      | apply fd_augmentation
      | apply fd_transitivity
      | omega)

/-- Solve normal form goals -/
syntax "nf_tactic" : tactic
macro_rules
  | `(tactic| nf_tactic) => `(tactic|
      first
      | apply bcnf_implies_3nf
      | apply third_nf_after_decomposition
      | constructor <;> fd_tactic)

/-- Solve lossless decomposition goals -/
syntax "lossless_tactic" : tactic
macro_rules
  | `(tactic| lossless_tactic) => `(tactic|
      first
      | apply decomposition_lossless
      | apply natural_join_inverse
      | simp [decomposeOn, SchemaTransform.forward, SchemaTransform.inverse])

end Lithoglyph.Normalization.Tactics
```

---

## Appendix B: Error Messages

### B.1 Normal Form Violation

```
NORMAL FORM VIOLATION at line 5:

  CREATE COLLECTION employees (...) TARGET_NORMAL_FORM BCNF

Schema violates BCNF:
  Functional dependency: department → dept_location
  Determinant [department] is not a superkey

Candidate keys: [[employee_id]]
Non-superkey determinants: [[department]]

Suggestions:
• Remove TARGET_NORMAL_FORM BCNF
• Split collection: PROPOSE NORMALIZATION employees TO BCNF
• Make department a key: PRIMARY KEY (employee_id, department)
```

### B.2 Missing Proof

```
PROOF OBLIGATION FAILED at line 12:

  APPLY NORMALIZATION proposal WITH_PROOF { ... }

Missing proof: lossless

The normalization step requires proof that the transformation
is lossless (can be reversed without data loss).

Expected: LosslessTransform (decomposeOn employees fd)
Missing: roundTrip proof

Suggestions:
• Add: lossless: by decomposition_lossless employees fd h
• Provide manual proof: lossless: by { intro r; simp [decomposeOn]; ... }
```

---

**Document Status**: Specification

**See Also**:
- [Lithoglyph Self-Normalizing Specification](https://github.com/hyperpolymath/lithoglyph/blob/main/spec/self-normalizing.adoc)
- [GQL Dependent Types Complete Specification](./GQL_Dependent_Types_Complete_Specification.md)
- [Form.Normalizer Architecture](https://github.com/hyperpolymath/lithoglyph/blob/main/ARCHITECTURE.adoc)
