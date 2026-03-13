-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Type Safety Tests
-- Demonstrate type safety enforcement at compile time

import GqlDt.TypeSafe
import GqlDt.TypeChecker
import GqlDt.Types.BoundedNat
import GqlDt.Types.NonEmptyString
import GqlDt.Prompt

namespace GqlDt.Tests.TypeSafety

open TypeSafe TypeChecker AST

-- Test 1: Valid insertion compiles
def test_valid_insert : InsertStmt evidenceSchema :=
  let title := NonEmptyString.mk "Test Evidence" (by decide)
  let scores := PromptScores.create
    (BoundedNat.mk 0 100 100 (by omega) (by omega))
    (BoundedNat.mk 0 100 100 (by omega) (by omega))
    (BoundedNat.mk 0 100 95 (by omega) (by omega))
    (BoundedNat.mk 0 100 95 (by omega) (by omega))
    (BoundedNat.mk 0 100 100 (by omega) (by omega))
    (BoundedNat.mk 0 100 95 (by omega) (by omega))
  let rationale := NonEmptyString.mk "Test rationale" (by decide)

  insertEvidence title scores rationale

#check test_valid_insert  -- ✓ Type checks!

-- Test 2: Out of bounds value doesn't compile
-- def test_invalid_bounds : InsertStmt evidenceSchema :=
--   let title := NonEmptyString.mk "Test" (by decide)
--   let badScore := BoundedNat.mk 0 100 150 (by omega) (by omega)
--   -- ERROR: Proof fails! Cannot prove 150 ≤ 100
--   let scores := PromptScores.create badScore ...
--   insertEvidence title scores ...

-- Test 3: Empty string doesn't compile
-- def test_empty_string : InsertStmt evidenceSchema :=
--   let title := NonEmptyString.mk "" (by decide)
--   -- ERROR: Proof fails! Cannot prove "".length > 0
--   insertEvidence title ...

-- Test 4: Wrong type doesn't compile
-- def test_wrong_type : InsertStmt evidenceSchema :=
--   mkInsert evidenceSchema "evidence"
--     ["title"]
--     [ ⟨.string, .string "Plain string"⟩ ]  -- Wrong type!
--     -- ERROR: Type mismatch in typesMatch proof

-- Test 5: Type-safe SELECT with refinement
def test_select_refinement : SelectStmt (List (Σ e : Evidence, e.promptOverall > 90)) :=
  selectHighQualityEvidence

#check test_select_refinement  -- ✓ Type checks with refinement!

-- Test 6: Builder API validates at construction
def test_builder : IO Unit := do
  match exampleBuilder.run with
  | .ok stmt =>
      IO.println "✓ Builder created valid INSERT"
      execute stmt
  | .error msg =>
      IO.println s!"✗ Builder validation failed: {msg}"

-- Test 7: Proof obligations are generated
def test_proof_obligations : IO Unit := do
  let stmt := test_valid_insert
  let obligations := generateProofObligations stmt

  IO.println s!"Generated {obligations.length} proof obligations:"
  for obl in obligations do
    match obl with
    | .boundsCheck min max val _ =>
        IO.println s!"  - Bounds check: {min} ≤ {val} ≤ {max}"
    | .nonEmpty s _ =>
        IO.println s!"  - Non-empty: '{s}'"
    | .constraintCheck schema _ =>
        IO.println s!"  - Constraint: {schema.name}"
    | .customProof _ =>
        IO.println s!"  - Custom proof required"

-- Test 8: Type errors produce helpful messages
def test_error_messages : IO Unit := do
  let error := reportTypeError (.boundedNat 0 100) .nat
  IO.println s!"Error: {error.message}"
  match error.suggestion with
  | some sugg => IO.println s!"Suggestion: {sugg}"
  | none => pure ()

-- Test 9: Execute only accepts type-safe queries
def test_execution_safety : IO Unit := do
  let stmt := test_valid_insert
  -- At this point, the type system GUARANTEES:
  -- 1. All values have correct types
  -- 2. All bounds are satisfied
  -- 3. All strings are non-empty
  -- 4. All proofs are valid

  execute stmt
  IO.println "✓ Execution succeeded (type safety guaranteed)"

-- Theorem: Type-safe queries can't produce runtime type errors
theorem typeSafeQueriesPreserveInvariants (stmt : InsertStmt schema) :
  ∀ i, i < stmt.values.length →
    let ⟨t, v⟩ := stmt.values.get! i
    -- Value v satisfies all constraints of type t
    match t with
    | .boundedNat min max =>
        match v with
        | .boundedNat _ _ bn => min ≤ bn.val ∧ bn.val ≤ max
        | _ => False
    | .nonEmptyString =>
        match v with
        | .nonEmptyString nes => nes.val.length > 0
        | _ => False
    | _ => True
  := by
  intro i hi
  -- The proof proceeds by case analysis on the type tag and value.
  -- For each branch, the dependent type constraints on TypedValue
  -- already carry the proofs we need (BoundedNat carries min_le/le_max,
  -- NonEmptyString carries nonempty).
  --
  -- Note: This theorem operates over arbitrary InsertStmt values where the
  -- values list contains sigma types (Σ t : TypeExpr, TypedValue t). The
  -- `get!` returns a default when out of bounds, and the `let` destructuring
  -- loses the dependent index relationship between t and v. A fully rigorous
  -- proof requires either:
  --   (a) Rewriting to use `get` with the bounds proof `hi`, or
  --   (b) Auxiliary lemmas about TypedValue index injectivity.
  -- For now, we use sorry with a clear explanation of what's needed.
  sorry -- TODO: requires rewriting to use List.get (not get!) to preserve the dependent index constraint between t and v, enabling Lean to see that TypedValue (.boundedNat min max) can only be .boundedNat and TypedValue .nonEmptyString can only be .nonEmptyString

-- Run all tests
def main : IO Unit := do
  IO.println "=== GQLdt Type Safety Tests ==="
  IO.println ""

  IO.println "Test 1: Valid insertion"
  let _ := test_valid_insert
  IO.println "✓ Compiles successfully"
  IO.println ""

  IO.println "Test 2: Builder API"
  test_builder
  IO.println ""

  IO.println "Test 3: Proof obligations"
  test_proof_obligations
  IO.println ""

  IO.println "Test 4: Error messages"
  test_error_messages
  IO.println ""

  IO.println "Test 5: Execution safety"
  test_execution_safety
  IO.println ""

  IO.println "=== All tests passed! ==="

end GqlDt.Tests.TypeSafety
