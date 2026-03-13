-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Type Inference for GQL (User Tier)
-- Infers dependent types from simple SQL-like syntax

import FbqlDt.AST
import FbqlDt.Types
import FbqlDt.TypeSafe

namespace FbqlDt.TypeInference

open AST Types TypeSafe

/-!
# Type Inference for GQL

The GQL parser allows users to write simple SQL-like queries without
explicit type annotations. The type inference engine:

1. Infers dependent types from literals and expressions
2. Generates proof obligations automatically
3. Attempts to auto-prove using tactics (omega, decide)
4. Falls back to runtime validation if proofs fail

**Example:**
```sql
-- GQL (user writes)
INSERT INTO evidence (title, prompt_provenance)
VALUES ('ONS Data', 95)
RATIONALE 'Official statistics';

-- Inferred to (GQL-DT internal)
INSERT INTO evidence (
  title : NonEmptyString,
  prompt_provenance : BoundedNat 0 100
)
VALUES (
  NonEmptyString.mk 'ONS Data' (by decide),
  BoundedNat.mk 0 100 95 (by omega) (by omega)
)
RATIONALE "Official statistics";
```
-/

-- ============================================================================
-- Literal Type Inference
-- ============================================================================

-- InferredType moved to AST.lean to avoid circular dependencies

/-- Result of type inference -/
structure InferenceResult where
  inferredType : TypeExpr
  value : InferredType
  canAutoProve : Bool  -- Can we auto-generate proofs?
  deriving Repr

/-- Infer NonEmptyString from string literal -/
def inferNonEmptyString (s : String) : InferenceResult :=
  if s.length > 0 then
    { inferredType := .nonEmptyString,
      value := .string s,
      canAutoProve := true }  -- Can use (by decide)
  else
    { inferredType := .string,  -- Fall back to plain String
      value := .string s,
      canAutoProve := false }

/-- Infer BoundedNat from natural number if it fits bounds -/
def inferBoundedNat (n : Nat) (min max : Nat) : InferenceResult :=
  if min ≤ n ∧ n ≤ max then
    { inferredType := .boundedNat min max,
      value := .nat n,
      canAutoProve := true }  -- Can use (by omega)
  else
    { inferredType := .nat,  -- Fall back to plain Nat
      value := .nat n,
      canAutoProve := false }

/-- Infer Confidence from number in [0, 100] -/
def inferConfidence (n : Nat) : InferenceResult :=
  if 0 ≤ n ∧ n ≤ 100 then
    { inferredType := .confidence,
      value := .nat n,
      canAutoProve := true }
  else
    { inferredType := .nat,
      value := .nat n,
      canAutoProve := false }

-- ============================================================================
-- Schema-Guided Inference
-- ============================================================================

/-- Infer type based on schema column definition

    This is the key function: given a value and expected column type,
    attempt to infer the dependent type and generate proofs.
-/
def inferTypeFromSchema
  (columnType : TypeExpr)
  (value : InferredType)
  : Except String InferenceResult :=
  match columnType, value with
  -- NonEmptyString expected, string literal given
  | .nonEmptyString, .string s =>
      if s.length > 0 then
        .ok { inferredType := .nonEmptyString,
              value := .string s,
              canAutoProve := true }
      else
        .error s!"Empty string not allowed for NonEmptyString column"

  -- BoundedNat expected, nat literal given
  | .boundedNat min max, .nat n =>
      if min ≤ n ∧ n ≤ max then
        .ok { inferredType := .boundedNat min max,
              value := .nat n,
              canAutoProve := true }
      else
        .error s!"Value {n} out of bounds [{min}, {max}]"

  -- Confidence expected, nat literal given
  | .confidence, .nat n =>
      if 0 ≤ n ∧ n ≤ 100 then
        .ok { inferredType := .confidence,
              value := .nat n,
              canAutoProve := true }
      else
        .error s!"Confidence value {n} must be in [0, 100]"

  -- Plain types (no refinement)
  | .nat, .nat n =>
      .ok { inferredType := .nat,
            value := .nat n,
            canAutoProve := true }

  | .string, .string s =>
      .ok { inferredType := .string,
            value := .string s,
            canAutoProve := true }

  | .bool, .bool b =>
      .ok { inferredType := .bool,
            value := .bool b,
            canAutoProve := true }

  -- Type mismatch
  | expected, actual =>
      .error s!"Type mismatch: expected {expected}, got {actual}"

-- ============================================================================
-- Proof Generation
-- ============================================================================

/-- Auto-proof strategy -/
inductive ProofStrategy where
  | decide : ProofStrategy    -- Use (by decide) for decidable propositions
  | omega : ProofStrategy     -- Use (by omega) for linear arithmetic
  | simp : ProofStrategy      -- Use (by simp) for simplification
-- PROOF_TODO: Replace sorry with actual proof
  | admit : ProofStrategy     -- Give up, use sorry (runtime check instead)
  deriving Repr, BEq

/-- Determine which proof tactic to use -/
def selectProofStrategy (result : InferenceResult) : ProofStrategy :=
  match result.inferredType with
  | .nonEmptyString => .decide  -- String.length > 0 is decidable
  | .boundedNat _ _ => .omega   -- min ≤ n ∧ n ≤ max uses linear arithmetic
  | .confidence => .omega       -- 0 ≤ n ∧ n ≤ 100 uses linear arithmetic
  | _ => .admit  -- No proof needed

/-- Generate proof term (as string for now, actual Expr later) -/
def generateProofTerm (strategy : ProofStrategy) : String :=
  match strategy with
  | .decide => "by decide"
  | .omega => "by omega"
  | .simp => "by simp"
-- PROOF_TODO: Replace sorry with actual proof
  | .admit => "sorry"  -- Will be runtime-checked instead

-- ============================================================================
-- Full INSERT Inference
-- ============================================================================

/-- Infer types for an INSERT statement -/
structure InferredInsert where
  table : String
  columns : List String
  inferredValues : List InferenceResult
  rationale : String
  deriving Repr

/-- Perform type inference for INSERT statement -/
def inferInsert
  (schema : Schema)
  (table : String)
  (columns : List String)
  (values : List InferredType)
  (rationale : String)
  : Except String InferredInsert := do

  -- 1. Find schema
  let schemaTable? := schema.columns.isEmpty  -- TODO: Real schema lookup
  if schemaTable? then
    throw s!"Table {table} not found in schema"

  -- 2. Check column count matches
  if columns.length ≠ values.length then
    throw s!"Column count ({columns.length}) doesn't match value count ({values.length})"

  -- 3. Infer type for each value based on column
  let mut inferredValues : List InferenceResult := []
  for i in [:columns.length] do
    let colName := columns.get! i
    let value := values.get! i

    -- Find column in schema
    let col? := schema.columns.find? (·.name = colName)
    match col? with
    | none => throw s!"Column {colName} not found in schema"
    | some col =>
        -- Infer type from schema
        let inferred ← inferTypeFromSchema col.type value
        inferredValues := inferred :: inferredValues

  -- 4. Return inferred INSERT
  return {
    table := table,
    columns := columns,
    inferredValues := inferredValues.reverse,
    rationale := rationale
  }

-- ============================================================================
-- Error Messages with Suggestions
-- ============================================================================

/-- Generate helpful error message for type inference failure -/
def formatInferenceError (error : String) (suggestion : String) : String :=
  s!"{error}\n\nSuggestion: {suggestion}"

/-- Suggest fix for out-of-bounds value -/
def suggestBoundsFix (value : Nat) (min max : Nat) : String :=
  if value < min then
    s!"Value {value} is below minimum {min}. Try a value between {min} and {max}."
  else
    s!"Value {value} exceeds maximum {max}. Try a value between {min} and {max}."

/-- Suggest fix for empty string -/
def suggestNonEmptyFix : String :=
  "String cannot be empty. Please provide a non-empty value."

-- ============================================================================
-- Runtime Validation Fallback
-- ============================================================================

/-- Runtime validation for cases where auto-proof fails -/
def runtimeValidate (result : InferenceResult) : Bool :=
  match result.inferredType, result.value with
  | .nonEmptyString, .string s => s.length > 0
  | .boundedNat min max, .nat n => min ≤ n ∧ n ≤ max
  | .confidence, .nat n => 0 ≤ n ∧ n ≤ 100
  | _, _ => true  -- No validation needed

/-- Validate inferred INSERT at runtime -/
def runtimeValidateInsert (insert : InferredInsert) : Except String Unit := do
  for result in insert.inferredValues do
    if !runtimeValidate result then
      throw s!"Runtime validation failed for {result.inferredType}"
  return ()

-- ============================================================================
-- Examples
-- ============================================================================

/-- Example: Infer INSERT with all valid values -/
def exampleInferValid : Except String InferredInsert :=
  inferInsert
    evidenceSchema
    "evidence"
    ["title", "prompt_provenance"]
    [.string "ONS Data", .nat 95]
    "Official statistics"

/-- Example: Infer INSERT with out-of-bounds value -/
def exampleInferInvalid : Except String InferredInsert :=
  inferInsert
    evidenceSchema
    "evidence"
    ["title", "prompt_provenance"]
    [.string "ONS Data", .nat 150]  -- Out of bounds!
    "Official statistics"

-- Test examples
#eval exampleInferValid  -- Should succeed
#eval exampleInferInvalid  -- Should fail with helpful error

-- ============================================================================
-- Integration with Parser
-- ============================================================================

/-- Parse GQL literal to InferredType -/
def parseLiteral (literal : String) : Except String InferredType :=
  -- Try to parse as number
  if let some n := literal.toNat? then
    .ok (.nat n)
  -- Try to parse as string (remove quotes)
  else if literal.startsWith "'" && literal.endsWith "'" then
    let s := literal.drop 1 |>.dropRight 1
    .ok (.string s)
  -- Try to parse as bool
  else if literal = "true" then
    .ok (.bool true)
  else if literal = "false" then
    .ok (.bool false)
  else
    .error s!"Cannot parse literal: {literal}"

/-- Parse GQL INSERT and perform type inference -/
def parseGQLInsert
  (schema : Schema)
  (query : String)
  : Except String InferredInsert := do
  -- TODO: Actual parser
  -- For now, assume query is already parsed to components
  .error "Parser not yet implemented"

end FbqlDt.TypeInference
