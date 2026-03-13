-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Abstract Syntax Tree with Dependent Types
-- Type-safe representation of GQL-DT queries

import FbqlDt.Types
import FbqlDt.Types.BoundedNat
import FbqlDt.Types.NonEmptyString
import FbqlDt.Provenance
import FbqlDt.Prompt

namespace FbqlDt.AST

open Types Provenance Prompt

-- ============================================================================
-- Type Inference Support
-- ============================================================================

/-- Inferred type from literals (before type checking)

    Used by GQL parser to represent values before schema lookup.
-/
inductive InferredType where
  | nat : Nat → InferredType
  | int : Int → InferredType
  | string : String → InferredType
  | bool : Bool → InferredType
  | float : Float → InferredType
  deriving Repr

-- ToString instance for InferredType
def inferredTypeToString : InferredType → String
  | .nat n => s!"Nat({n})"
  | .int i => s!"Int({i})"
  | .string s => s!"String(\"{s}\")"
  | .bool b => s!"Bool({b})"
  | .float f => s!"Float({f})"

instance : ToString InferredType where
  toString := inferredTypeToString

-- Inhabited instance for InferredType (default: nat 0)
instance : Inhabited InferredType where
  default := .nat 0

-- ============================================================================
-- Core Type Definitions (Ordered by Dependencies)
-- ============================================================================

-- Type expressions (indexed by actual Lean 4 types)
-- NO DEPENDENCIES - Define first
inductive TypeExpr where
  | nat : TypeExpr
  | int : TypeExpr
  | string : TypeExpr
  | bool : TypeExpr
  | float : TypeExpr
  | uuid : TypeExpr
  | timestamp : TypeExpr
  -- Refinement types
  | boundedNat : (min max : Nat) → TypeExpr
  | boundedFloat : (min max : Float) → TypeExpr
  | nonEmptyString : TypeExpr
  | confidence : TypeExpr
  -- Dependent types
  | vector : TypeExpr → Nat → TypeExpr
  | promptScores : TypeExpr
  -- Note: Provenance tracking via TrackedValue wrapper, not a type constructor
  deriving Repr

-- ToString instance for TypeExpr
def typeExprToString : TypeExpr → String
  | .nat => "Nat"
  | .int => "Int"
  | .string => "String"
  | .bool => "Bool"
  | .float => "Float"
  | .uuid => "UUID"
  | .timestamp => "Timestamp"
  | .boundedNat min max => s!"BoundedNat {min} {max}"
  | .boundedFloat min max => s!"BoundedFloat {min} {max}"
  | .nonEmptyString => "NonEmptyString"
  | .confidence => "Confidence"
  | .vector t n => s!"Vector ({typeExprToString t}) {n}"
  | .promptScores => "PromptScores"

instance : ToString TypeExpr where
  toString := typeExprToString

-- DecidableEq instance for TypeExpr
-- Note: Floats use bitwise equality (Float.beq) which may not match mathematical equality
def typeExprBeq : TypeExpr → TypeExpr → Bool
  | .nat, .nat => true
  | .int, .int => true
  | .string, .string => true
  | .bool, .bool => true
  | .float, .float => true
  | .uuid, .uuid => true
  | .timestamp, .timestamp => true
  | .boundedNat min1 max1, .boundedNat min2 max2 => min1 == min2 && max1 == max2
  | .boundedFloat min1 max1, .boundedFloat min2 max2 => min1.beq min2 && max1.beq max2
  | .nonEmptyString, .nonEmptyString => true
  | .confidence, .confidence => true
  | .vector t1 n1, .vector t2 n2 => typeExprBeq t1 t2 && n1 == n2
  | .promptScores, .promptScores => true
  | _, _ => false

instance : BEq TypeExpr where
  beq := typeExprBeq

-- Normal form levels
-- NO DEPENDENCIES
inductive NormalForm where
  | nf1 : NormalForm
  | nf2 : NormalForm
  | nf3 : NormalForm
  | bcnf : NormalForm
  | nf4 : NormalForm
  deriving Repr

-- ToString for NormalForm
instance : ToString NormalForm where
  toString
    | .nf1 => "1NF"
    | .nf2 => "2NF"
    | .nf3 => "3NF"
    | .bcnf => "BCNF"
    | .nf4 => "4NF"

-- Type-safe values indexed by their types
-- DEPENDS ON: TypeExpr
inductive TypedValue : TypeExpr → Type where
  | nat : Nat → TypedValue .nat
  | int : Int → TypedValue .int
  | string : String → TypedValue .string
  | bool : Bool → TypedValue .bool
  | float : Float → TypedValue .float
  | boundedNat : (min max : Nat) → BoundedNat min max → TypedValue (.boundedNat min max)
  | nonEmptyString : NonEmptyString → TypedValue .nonEmptyString
  | promptScores : PromptScores → TypedValue .promptScores

-- Provenance-tracked values (wrapper around TypedValue)
-- Separates provenance from type system to avoid nested inductive issue
structure TrackedValue (t : TypeExpr) where
  value : TypedValue t
  timestamp : Nat  -- Unix timestamp
  actorId : ActorId  -- Who made the change
  rationale : Rationale  -- Why was it changed

-- Manual Repr for TrackedValue (can't auto-derive with dependent types)
instance {t : TypeExpr} : Repr (TrackedValue t) where
  reprPrec tv _ := "TrackedValue { timestamp := " ++ repr tv.timestamp ++ ", actor := " ++ repr tv.actorId ++ " }"

-- Row: list of typed values (optionally with provenance)
-- DEPENDS ON: TypeExpr, TypedValue, TrackedValue
def Row := List (String × Σ t : TypeExpr, TypedValue t)
def TrackedRow := List (String × Σ t : TypeExpr, TrackedValue t)

-- Constraints with proofs
-- DEPENDS ON: Row
inductive Constraint where
  | check : String → (row : Row) → Prop → Constraint
  | foreignKey : String → String → Constraint
  | unique : List String → Constraint

-- Manual Repr for Constraint (can't auto-derive with Prop field)
instance : Repr Constraint where
  reprPrec
    | .check name _ _, _ => "Constraint.check " ++ repr name
    | .foreignKey src dst, _ => "Constraint.foreignKey " ++ repr src ++ " " ++ repr dst
    | .unique cols, _ => "Constraint.unique " ++ repr cols

-- Column definition with type-level constraints
-- DEPENDS ON: TypeExpr
structure ColumnDef where
  name : String
  type : TypeExpr
  isPrimaryKey : Bool
  isUnique : Bool
  deriving Repr

-- Schema definition with dependent types
-- DEPENDS ON: ColumnDef, Constraint, NormalForm
structure Schema where
  name : String
  columns : List ColumnDef
  constraints : List Constraint
  normalForm : Option NormalForm
  deriving Repr

-- Type refinement: filters results to those satisfying predicate
structure TypeRefinement (α : Type) where
  predicate : α → Prop
  proof : ∀ x : α, Decidable (predicate x)

-- Manual Repr for TypeRefinement (contains Prop/proof fields)
instance {α : Type} : Repr (TypeRefinement α) where
  reprPrec _ _ := "TypeRefinement { ... }"

-- SELECT components (defined before SelectStmt uses them)
inductive SelectList where
  | star : SelectList
  | columns : List String → SelectList
  | typed : (t : Type) → TypeRefinement t → SelectList
  deriving Repr

structure TableRef where
  name : String
  alias : Option String
  deriving Repr

structure FromClause where
  tables : List TableRef
  deriving Repr

-- Conditions with type checking
inductive Condition where
  | eq : {t : TypeExpr} → TypedValue t → TypedValue t → Condition
  | lt : {t : TypeExpr} → TypedValue t → TypedValue t → Condition
  | and : Condition → Condition → Condition
  | or : Condition → Condition → Condition
  | not : Condition → Condition

-- Manual Repr for Condition (simplified to avoid recursion issues)
partial def reprCondition : Condition → String
  | .eq _ _ => "Condition.eq"
  | .lt _ _ => "Condition.lt"
  | .and c1 c2 => "Condition.and (" ++ reprCondition c1 ++ ") (" ++ reprCondition c2 ++ ")"
  | .or c1 c2 => "Condition.or (" ++ reprCondition c1 ++ ") (" ++ reprCondition c2 ++ ")"
  | .not c => "Condition.not (" ++ reprCondition c ++ ")"

instance : Repr Condition where
  reprPrec c _ := reprCondition c

-- Manual Repr for sigma types (needed for Assignment and InsertStmt)
instance {t : TypeExpr} : Repr (TypedValue t) where
  reprPrec
    | .nat n, _ => "TypedValue.nat " ++ repr n
    | .int i, _ => "TypedValue.int " ++ repr i
    | .string s, _ => "TypedValue.string " ++ repr s
    | .bool b, _ => "TypedValue.bool " ++ repr b
    | .float f, _ => "TypedValue.float " ++ repr f
    | .boundedNat _ _ _, _ => "TypedValue.boundedNat"
    | .nonEmptyString _, _ => "TypedValue.nonEmptyString"
    | .promptScores _, _ => "TypedValue.promptScores"

-- Repr for the sigma type itself
instance : Repr (Σ t : TypeExpr, TypedValue t) where
  reprPrec sigma _ := match sigma with
    | ⟨t, _⟩ => "(Σ " ++ repr t ++ ", value)"

-- Inhabited for the sigma type (default: nat with value 0)
instance : Inhabited (Σ t : TypeExpr, TypedValue t) where
  default := ⟨.nat, .nat 0⟩

-- Assignment for UPDATE statements
structure Assignment where
  column : String
  value : Σ t : TypeExpr, TypedValue t
  deriving Repr

-- Type-safe INSERT statement
structure InsertStmt (schema : Schema) where
  table : String
  columns : List String
  values : List (Σ t : TypeExpr, TypedValue t)
  rationale : Rationale
  addedBy : Option ActorId
  -- Type safety proof: values match column types
  typesMatch : ∀ i, i < values.length →
    ∃ col ∈ schema.columns,
      col.name = columns.get! i ∧
      (values.get! i).1 = col.type
  -- Provenance proof: rationale is non-empty (automatic via Rationale type)

-- Manual Repr for InsertStmt (can't auto-derive with proof fields)
instance {schema : Schema} : Repr (InsertStmt schema) where
  reprPrec stmt _ := "InsertStmt { table := " ++ repr stmt.table ++ ", columns := " ++ repr stmt.columns ++ " }"

-- Type-safe SELECT statement with result type
structure SelectStmt (resultType : Type) where
  selectList : SelectList
  from_ : FromClause  -- Underscore to avoid keyword conflict
  where_ : Option Condition
  returning : Option (TypeRefinement resultType)

-- Manual Repr for SelectStmt
instance {resultType : Type} : Repr (SelectStmt resultType) where
  reprPrec stmt _ := "SelectStmt { from := " ++ repr stmt.from_ ++ " }"

/-- WHERE clause with optional proof obligation

    Parser produces simplified (String × String × InferredType) representation
    which is later type-checked against schema to produce full Condition.
-/
structure WhereClause where
  predicate : (String × String × InferredType)  -- Simplified: (column, op, value)
  proof : Unit → True  -- Placeholder for proof obligation
  deriving Repr

/-- ORDER BY clause with column names and directions -/
structure OrderByClause where
  columns : List (String × String)  -- (column, direction: "ASC" or "DESC")
  deriving Repr

-- Type-safe UPDATE statement
structure UpdateStmt (schema : Schema) where
  table : String
  assignments : List Assignment
  where_ : Condition
  rationale : Rationale
  -- Type safety: assignments match column types
  typesMatch : ∀ a ∈ assignments,
    ∃ col ∈ schema.columns,
      col.name = a.column ∧
      a.value.1 = col.type

-- Manual Repr for UpdateStmt (can't auto-derive with proof fields)
instance {schema : Schema} : Repr (UpdateStmt schema) where
  reprPrec stmt _ := "UpdateStmt { table := " ++ repr stmt.table ++ ", assignments := " ++ repr stmt.assignments ++ " }"

-- Type-safe DELETE statement
structure DeleteStmt where
  table : String
  where_ : Condition
  rationale : Rationale
  deriving Repr

-- Proof obligations for INSERT (simplified)
-- Note: In practice, these would be checked at compile-time by the type system
structure InsertProofObligation {schema : Schema} (stmt : InsertStmt schema) where
  -- Rationale is non-empty (automatically satisfied by Rationale type)
  -- Type constraints are enforced by the dependent types
  -- This structure can be extended with additional custom proof obligations

-- Helper: check if value satisfies type constraints
def satisfiesConstraints {t : TypeExpr} (v : TypedValue t) : Prop :=
  match t, v with
  | .boundedNat min max, .boundedNat _ _ bn => bn.val ≥ min ∧ bn.val ≤ max
  | .nonEmptyString, .nonEmptyString nes => nes.val.length > 0
  | _, _ => True  -- Other types checked structurally

end FbqlDt.AST
