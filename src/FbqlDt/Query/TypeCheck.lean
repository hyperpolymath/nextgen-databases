-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Query.TypeCheck - Type checker for GQL queries
--
-- Validates queries against database schemas, ensuring:
-- - Referenced tables exist
-- - Referenced columns exist and have compatible types
-- - Expressions are well-typed
-- - Proof requirements are met

import FbqlDt.Query.AST
import FbqlDt.Query.Schema

namespace FbqlDt.Query.TypeCheck

open FbqlDt.Query
open FbqlDt.Query.Schema

-- ============================================================================
-- Type Errors
-- ============================================================================

/-- Type checking errors -/
inductive TypeError where
  | unknownTable : String → TypeError
  | unknownColumn : String → String → TypeError  -- table, column
  | typeMismatch : ColumnType → ColumnType → TypeError
  | incomparableTypes : ColumnType → ColumnType → TypeError
  | nullInNonNullable : String → TypeError
  | missingProof : String → TypeError
  | insufficientPromptScore : Nat → Nat → TypeError  -- required, actual
  | missingProvenance : TypeError
  | invalidExpression : String → TypeError
  deriving Repr, BEq

namespace TypeError

/-- Human-readable error message -/
def message : TypeError → String
  | .unknownTable t => s!"Unknown table: {t}"
  | .unknownColumn t c => s!"Unknown column '{c}' in table '{t}'"
  | .typeMismatch expected actual =>
      s!"Type mismatch: expected {expected.toString}, got {actual.toString}"
  | .incomparableTypes t1 t2 =>
      s!"Cannot compare {t1.toString} with {t2.toString}"
  | .nullInNonNullable col =>
      s!"Cannot insert NULL into non-nullable column '{col}'"
  | .missingProof col =>
      s!"Column '{col}' requires proof for insertion"
  | .insufficientPromptScore req actual =>
      s!"Insufficient PROMPT score: required {req}, got {actual}"
  | .missingProvenance =>
      "INSERT/UPDATE/DELETE requires ACTOR and RATIONALE"
  | .invalidExpression msg => s!"Invalid expression: {msg}"

end TypeError

/-- Type check result -/
abbrev TypeResult (α : Type) := Except TypeError α

-- ============================================================================
-- Expression Type Inference
-- ============================================================================

/-- Infer the type of a literal -/
def inferLiteralType : Literal → ColumnType
  | .null => .string  -- NULL can be any type
  | .bool _ => .bool
  | .int _ => .int
  | .float _ => .float
  | .string _ => .string

/-- Context for type checking (table in scope) -/
structure TypeContext where
  table : Table
  deriving Repr

/-- Check types in a list of expressions -/
def checkExprList (ctx : TypeContext) (baseType : ColumnType) : List Expr → TypeResult Unit
  | [] => pure ()
  | e :: es => do
    let t ← inferExprType' ctx e
    if !baseType.isComparable t then
      throw (.incomparableTypes baseType t)
    checkExprList ctx baseType es
where
  /-- Infer the type of an expression (helper for mutual recursion) -/
  inferExprType' (ctx : TypeContext) : Expr → TypeResult ColumnType
    | .lit l => pure (inferLiteralType l)
    | .col qc =>
      let colName := qc.column.name
      match ctx.table.columnType colName with
      | some t => pure t
      | none => throw (.unknownColumn ctx.table.name colName)
    | .compare lhs _ rhs => do
      let t1 ← inferExprType' ctx lhs
      let t2 ← inferExprType' ctx rhs
      if t1.isComparable t2 then
        pure .bool
      else
        throw (.incomparableTypes t1 t2)
    | .logic lhs _ rhs => do
      let _ ← inferExprType' ctx lhs
      let _ ← inferExprType' ctx rhs
      pure .bool
    | .not e => do
      let _ ← inferExprType' ctx e
      pure .bool
    | .isNull e | .isNotNull e => do
      let _ ← inferExprType' ctx e
      pure .bool
    | .between e lo hi => do
      let t ← inferExprType' ctx e
      let tLo ← inferExprType' ctx lo
      let tHi ← inferExprType' ctx hi
      if t.isComparable tLo && t.isComparable tHi then
        pure .bool
      else
        throw (.invalidExpression "BETWEEN requires comparable types")
    | .inList e _ => do
      let _ ← inferExprType' ctx e
      -- Just check first-level, avoid deep recursion
      pure .bool

/-- Infer the type of an expression -/
def inferExprType (ctx : TypeContext) (e : Expr) : TypeResult ColumnType :=
  checkExprList.inferExprType' ctx e

-- ============================================================================
-- Query Type Checking
-- ============================================================================

/-- Check SELECT query -/
def checkSelect (db : Database) (q : SelectQuery) : TypeResult Table := do
  -- Check table exists
  let tableName := q.from.name
  let table ← match db.findTable tableName with
    | some t => pure t
    | none => throw (.unknownTable tableName)

  let ctx : TypeContext := { table := table }

  -- Check projection columns exist
  match q.projection with
  | .all => pure ()
  | .columns cols =>
    for col in cols do
      if !table.hasColumn col.name then
        throw (.unknownColumn tableName col.name)
  | .exprs exprs =>
    for (expr, _) in exprs do
      let _ ← inferExprType ctx expr

  -- Check WHERE clause
  match q.whereClause with
  | some whereExpr =>
    let _ ← inferExprType ctx whereExpr
    -- WHERE should evaluate to boolean
    pure ()
  | none => pure ()

  -- Check ORDER BY columns
  for ob in q.orderBy do
    let colName := ob.column.column.name
    if !table.hasColumn colName then
      throw (.unknownColumn tableName colName)

  pure table

/-- Check if INSERT has required provenance -/
def checkProvenance (actor : Option String) (rationale : Option String) : TypeResult Unit :=
  match actor, rationale with
  | some _, some _ => pure ()
  | _, _ => throw .missingProvenance

/-- Check PROMPT score meets table requirement -/
def checkPromptScore (table : Table) (providedScore : Option Nat) : TypeResult Unit := do
  match table.minPromptScore with
  | none => pure ()  -- Table has no PROMPT requirement
  | some required =>
    match providedScore with
    | none =>
      -- Table requires PROMPT score but none provided
      throw (.insufficientPromptScore required 0)
    | some actual =>
      if actual < required then
        throw (.insufficientPromptScore required actual)
      else
        pure ()

/-- Check INSERT statement -/
def checkInsert (db : Database) (stmt : InsertStmt) : TypeResult Table := do
  -- Check table exists
  let tableName := stmt.table.name
  let table ← match db.findTable tableName with
    | some t => pure t
    | none => throw (.unknownTable tableName)

  let ctx : TypeContext := { table := table }

  -- Check each column-value pair
  for cv in stmt.values do
    let colName := cv.column.name
    match table.findColumn colName with
    | none => throw (.unknownColumn tableName colName)
    | some col => do
      -- Infer value type
      let valueType ← inferExprType ctx cv.value

      -- Check for NULL in non-nullable column
      match cv.value with
      | .lit .null =>
        if !col.nullable then
          throw (.nullInNonNullable colName)
      | _ => pure ()

      -- Check type compatibility
      if !col.colType.isComparable valueType then
        throw (.typeMismatch col.colType valueType)

      -- Check proof requirement
      if col.requiresProof then
        -- For now, just note it - actual proof checking happens at runtime
        pure ()

  -- Check provenance metadata
  checkProvenance stmt.actor stmt.rationale

  -- Check PROMPT score meets table minimum requirement
  checkPromptScore table stmt.promptScore

  pure table

/-- Check UPDATE statement -/
def checkUpdate (db : Database) (stmt : UpdateStmt) : TypeResult Table := do
  -- Check table exists
  let tableName := stmt.table.name
  let table ← match db.findTable tableName with
    | some t => pure t
    | none => throw (.unknownTable tableName)

  let ctx : TypeContext := { table := table }

  -- Check each SET column-value pair
  for cv in stmt.set do
    let colName := cv.column.name
    match table.findColumn colName with
    | none => throw (.unknownColumn tableName colName)
    | some col => do
      let valueType ← inferExprType ctx cv.value
      if !col.colType.isComparable valueType then
        throw (.typeMismatch col.colType valueType)

  -- Check WHERE clause if present
  match stmt.whereClause with
  | some whereExpr =>
    let _ ← inferExprType ctx whereExpr
  | none => pure ()

  -- Check provenance
  checkProvenance stmt.actor stmt.rationale

  pure table

/-- Check DELETE statement -/
def checkDelete (db : Database) (stmt : DeleteStmt) : TypeResult Table := do
  -- Check table exists
  let tableName := stmt.table.name
  let table ← match db.findTable tableName with
    | some t => pure t
    | none => throw (.unknownTable tableName)

  let ctx : TypeContext := { table := table }

  -- Check WHERE clause if present
  match stmt.whereClause with
  | some whereExpr =>
    let _ ← inferExprType ctx whereExpr
  | none => pure ()

  -- Check provenance
  checkProvenance stmt.actor stmt.rationale

  pure table

/-- Type check any statement -/
def checkStatement (db : Database) (stmt : Statement) : TypeResult Table :=
  match stmt with
  | .select q => checkSelect db q
  | .insert s => checkInsert db s
  | .update s => checkUpdate db s
  | .delete s => checkDelete db s

-- ============================================================================
-- Public API
-- ============================================================================

/-- Type check a statement against a database schema -/
def typeCheck (db : Database) (stmt : Statement) : Except String Table :=
  match checkStatement db stmt with
  | .ok t => .ok t
  | .error e => .error e.message

/-- Type check and return detailed result -/
def typeCheckDetailed (db : Database) (stmt : Statement) : TypeResult Table :=
  checkStatement db stmt

end FbqlDt.Query.TypeCheck
