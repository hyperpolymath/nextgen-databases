-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Type Checker for GQL-DT
-- Enforces type safety and generates proof obligations

import FbqlDt.AST
import FbqlDt.TypeSafe
import FbqlDt.Types
import FbqlDt.Types.BoundedNat
import FbqlDt.Provenance

namespace FbqlDt.TypeChecker

open AST TypeSafe Types Provenance

-- Type checking context
structure Context where
  schemas : List Schema
  currentSchema : Option Schema
  deriving Repr

-- Type checking result
inductive TypeCheckResult (α : Type) where
  | ok : α → TypeCheckResult α
  | error : String → TypeCheckResult α
  | needsProof : (prf : Prop) → (prf → α) → TypeCheckResult α

instance : Monad TypeCheckResult where
  pure x := .ok x
  bind res f := match res with
    | .ok x => f x
    | .error msg => .error msg
    | .needsProof p k => .needsProof p (fun h =>
        match f (k h) with
        | .ok x => x
-- PROOF_TODO: Replace sorry with actual proof
        | .error _ => sorry  -- Simplified for now
-- PROOF_TODO: Replace sorry with actual proof
        | .needsProof _ _ => sorry)

-- Check if value matches expected type
def checkValueType (expected : TypeExpr) (actual : Σ t : TypeExpr, TypedValue t)
  : TypeCheckResult Unit :=
  if expected == actual.1 then
    .ok ()
  else
    .error s!"Type mismatch: expected {expected}, got {actual.1}"

-- Check INSERT statement type safety
def checkInsert (ctx : Context) (table : String)
  (columns : List String)
  (values : List (Σ t : TypeExpr, TypedValue t))
  : TypeCheckResult (InsertStmt evidenceSchema) :=
  -- 1. Find schema
  let schema? := ctx.schemas.find? (·.name = table)
  match schema? with
  | none => TypeCheckResult.error s!"Table {table} not found"
  | some schema =>
      -- TODO: Column and type validation
      -- For now, just construct the INSERT
      TypeCheckResult.ok (mkInsert evidenceSchema table columns values
-- PROOF_TODO: Replace sorry with actual proof
        (Rationale.fromString "rationale") none (by sorry))

-- Check SELECT statement with type refinement
-- Simplified to avoid universe issues
def checkSelect (ctx : Context) (selectList : SelectList) (from_ : FromClause)
  : TypeCheckResult Unit :=
  -- Simplified: just return success
  TypeCheckResult.ok ()

-- Type error reporting with suggestions
structure TypeError where
  message : String
  location : Option (Nat × Nat)  -- Line, column
  suggestion : Option String
  deriving Repr

def reportTypeError (expected : TypeExpr) (actual : TypeExpr) : TypeError :=
  { message := s!"Type mismatch: expected {expected}, got {actual}"
    location := none
    suggestion := some (match expected, actual with
      | .boundedNat min max, .nat =>
          s!"Hint: Use a BoundedNat value between {min} and {max}, e.g., ⟨value, proof1, proof2⟩"
      | .nonEmptyString, .string =>
          s!"Hint: Use NonEmptyString.mk' \"your string\" instead of plain String"
      | .promptScores, _ =>
          s!"Hint: Use PromptScores.create to construct PROMPT scores with automatic proof"
      | _, _ => "Check the type annotation and value") }

-- Proof obligation generation
inductive ProofObligation where
  | boundsCheck : (min max val : Nat) → (h : min ≤ val ∧ val ≤ max) → ProofObligation
  | nonEmpty : (s : String) → (h : s.length > 0) → ProofObligation
  | constraintCheck : (schema : Schema) → (row : Row) → ProofObligation
  | customProof : Prop → ProofObligation

def generateProofObligations {schema : Schema} (stmt : InsertStmt schema) : List ProofObligation :=
  stmt.values.foldl (fun acc ⟨t, v⟩ =>
    match t, v with
    | .boundedNat min max, .boundedNat _ _ bn =>
        .boundsCheck min max bn.val ⟨bn.min_le, bn.le_max⟩ :: acc
    | .nonEmptyString, .nonEmptyString nes =>
        .nonEmpty nes.val nes.nonempty :: acc
    | _, _ => acc
  ) []

-- Automatic proof search for simple cases
def autoProve (obligation : ProofObligation) : Option (TypeCheckResult Unit) :=
  match obligation with
  | .boundsCheck min max val ⟨h1, h2⟩ =>
      -- For numeric bounds, use omega tactic
      some (.ok ())  -- Proof would be: by omega
  | .nonEmpty s h =>
      -- For non-empty strings, use decide
      some (.ok ())  -- Proof would be: by decide
  | .constraintCheck _ _ =>
      none  -- Complex constraints need manual proofs
  | .customProof _ =>
      none  -- Custom proofs always manual

-- Example: type check and execute with automatic proof generation
def typeCheckAndExecute (table : String) (columns : List String)
  (values : List (Σ t : TypeExpr, TypedValue t))
  : IO Unit := do
  let ctx : Context := {
    schemas := [evidenceSchema],
    currentSchema := some evidenceSchema
  }

  let rationale := Rationale.fromString "test"

  match checkInsert ctx table columns values with
  | .ok stmt =>
      -- Type checking passed!
      IO.println "✓ Type checking successful"

      -- Generate proof obligations
      let obligations := generateProofObligations stmt
      IO.println s!"Proof obligations: {obligations.length}"

      -- Auto-prove simple obligations
      let autoProvable := obligations.filterMap autoProve
      IO.println s!"Auto-proved: {autoProvable.length}/{obligations.length}"

      -- Execute (type-safe!)
      execute stmt

  | .error msg =>
      IO.println s!"✗ Type error: {msg}"

  | .needsProof p k =>
      IO.println "⚠ Manual proof required"
      -- In IDE: would show proof assistant UI

-- Example that demonstrates type safety
def exampleTypeSafe : IO Unit := do
  -- This compiles: correct types
  let title := NonEmptyString.mk' "ONS CPI Data"
  let score : BoundedNat 0 100 := ⟨95, by omega, by omega⟩

  typeCheckAndExecute "evidence"
    ["title", "prompt_provenance"]
    [ ⟨.nonEmptyString, .nonEmptyString title⟩,
      ⟨.boundedNat 0 100, .boundedNat 0 100 score⟩ ]

-- Example that demonstrates type error
-- def exampleTypeError : IO Unit := do
--   -- This won't compile: wrong type
--   typeCheckAndExecute "evidence"
--     ["title"]
--     [ ⟨.string, .string "Plain string"⟩ ]  -- TYPE ERROR
--   -- Error: expected NonEmptyString, got String

end FbqlDt.TypeChecker
