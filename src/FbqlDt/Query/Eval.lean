-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Query.Eval - Query evaluation engine for GQL
--
-- Executes type-checked queries against an in-memory store.
-- Enforces proof requirements and tracks provenance.

import FbqlDt.Query.AST
import FbqlDt.Query.Schema
import FbqlDt.Query.Store
import FbqlDt.Query.TypeCheck

namespace FbqlDt.Query.Eval

open FbqlDt.Query
open FbqlDt.Query.Schema
open FbqlDt.Query.Store
open FbqlDt.Query.TypeCheck

-- ============================================================================
-- Evaluation Errors
-- ============================================================================

/-- Runtime evaluation errors -/
inductive EvalError where
  | tableNotFound : String → EvalError
  | columnNotFound : String → EvalError
  | typeMismatch : String → EvalError
  | nullViolation : String → EvalError
  | proofRequired : String → EvalError
  | insufficientScore : Nat → Nat → EvalError
  | divisionByZero : EvalError
  | internalError : String → EvalError
  deriving Repr, BEq

namespace EvalError

def message : EvalError → String
  | .tableNotFound t => s!"Table not found: {t}"
  | .columnNotFound c => s!"Column not found: {c}"
  | .typeMismatch msg => s!"Type mismatch: {msg}"
  | .nullViolation col => s!"NULL violation in column: {col}"
  | .proofRequired col => s!"Proof required for column: {col}"
  | .insufficientScore req got => s!"PROMPT score {got} below required {req}"
  | .divisionByZero => "Division by zero"
  | .internalError msg => s!"Internal error: {msg}"

end EvalError

/-- Evaluation result type -/
abbrev EvalResult (α : Type) := Except EvalError α

-- ============================================================================
-- Expression Evaluation
-- ============================================================================

/-- Convert AST literal to store value -/
def literalToValue : Literal → Value
  | .null => .null
  | .bool b => .bool b
  | .int i => .int i
  | .float f => .float f
  | .string s => .string s

/-- Evaluate an expression against a row -/
def evalExpr (row : Row) : Expr → EvalResult Value
  | .lit l => pure (literalToValue l)
  | .col qc =>
    let colName := qc.column.name
    match row.getValue colName with
    | some v => pure v
    | none => throw (.columnNotFound colName)
  | .compare lhs op rhs => do
    let v1 ← evalExpr row lhs
    let v2 ← evalExpr row rhs
    pure (.bool (compareValues v1 op v2))
  | .logic lhs op rhs => do
    let v1 ← evalExpr row lhs
    let v2 ← evalExpr row rhs
    match v1, v2 with
    | .bool b1, .bool b2 =>
      match op with
      | .and => pure (.bool (b1 && b2))
      | .or => pure (.bool (b1 || b2))
    | _, _ => throw (.typeMismatch "Logic operation requires boolean operands")
  | .not e => do
    let v ← evalExpr row e
    match v with
    | .bool b => pure (.bool (!b))
    | _ => throw (.typeMismatch "NOT requires boolean operand")
  | .isNull e => do
    let v ← evalExpr row e
    pure (.bool (v == .null))
  | .isNotNull e => do
    let v ← evalExpr row e
    pure (.bool (v != .null))
  | .between e lo hi => do
    let v ← evalExpr row e
    let vLo ← evalExpr row lo
    let vHi ← evalExpr row hi
    pure (.bool (compareValues vLo .le v && compareValues v .le vHi))
  | .inList e _ => do
    let _ ← evalExpr row e
    -- Simplified: just check the expression is valid
    -- Full IN list evaluation would need separate helper
    pure (.bool false)
where
  /-- Compare two values -/
  compareValues (v1 : Value) (op : CompOp) (v2 : Value) : Bool :=
    match v1, v2, op with
    | .null, _, _ | _, .null, _ => false  -- NULL comparisons are false
    | .int i1, .int i2, .eq => i1 == i2
    | .int i1, .int i2, .neq => i1 != i2
    | .int i1, .int i2, .lt => i1 < i2
    | .int i1, .int i2, .le => i1 <= i2
    | .int i1, .int i2, .gt => i1 > i2
    | .int i1, .int i2, .ge => i1 >= i2
    | .float f1, .float f2, .eq => f1 == f2
    | .float f1, .float f2, .neq => f1 != f2
    | .float f1, .float f2, .lt => f1 < f2
    | .float f1, .float f2, .le => f1 <= f2
    | .float f1, .float f2, .gt => f1 > f2
    | .float f1, .float f2, .ge => f1 >= f2
    | .string s1, .string s2, .eq => s1 == s2
    | .string s1, .string s2, .neq => s1 != s2
    | .string s1, .string s2, .lt => s1 < s2
    | .string s1, .string s2, .le => s1 <= s2
    | .string s1, .string s2, .gt => s1 > s2
    | .string s1, .string s2, .ge => s1 >= s2
    | .bool b1, .bool b2, .eq => b1 == b2
    | .bool b1, .bool b2, .neq => b1 != b2
    | _, _, _ => false

/-- Check if a row matches a WHERE clause -/
def rowMatches (row : Row) (whereClause : Option Expr) : EvalResult Bool :=
  match whereClause with
  | none => pure true
  | some expr => do
    let v ← evalExpr row expr
    match v with
    | .bool b => pure b
    | _ => throw (.typeMismatch "WHERE clause must evaluate to boolean")

-- ============================================================================
-- Query Execution
-- ============================================================================

/-- Execute a SELECT query -/
def execSelect (db : DatabaseStore) (q : SelectQuery) : EvalResult ResultSet := do
  let tableName := q.from.name
  match db.getTable tableName with
  | none => throw (.tableNotFound tableName)
  | some tableStore =>
    -- Filter rows by WHERE clause
    let filteredRows ← tableStore.allRows.filterM (rowMatches · q.whereClause)

    -- Get column names for projection
    let cols := match q.projection with
      | .all => tableStore.schema.columnNames
      | .columns cs => cs.map (·.name)
      | .exprs _ => tableStore.schema.columnNames  -- TODO: handle aliases

    -- Apply ORDER BY (simplified: single column, ASC only for now)
    let sortedRows := match q.orderBy.head? with
      | none => filteredRows
      | some ob =>
        let colName := ob.column.column.name
        filteredRows.toArray.qsort (fun r1 r2 =>
          match r1.getValue colName, r2.getValue colName with
          | some (.int i1), some (.int i2) =>
            if ob.direction == .asc then i1 < i2 else i1 > i2
          | some (.string s1), some (.string s2) =>
            if ob.direction == .asc then s1 < s2 else s1 > s2
          | _, _ => false
        ) |>.toList

    -- Apply LIMIT and OFFSET
    let offsetRows := match q.offset with
      | none => sortedRows
      | some n => sortedRows.drop n
    let limitedRows := match q.limit with
      | none => offsetRows
      | some n => offsetRows.take n

    pure (ResultSet.fromRows cols limitedRows)

/-- Execute an INSERT statement -/
def execInsert (db : DatabaseStore) (stmt : InsertStmt)
    : EvalResult (DatabaseStore × MutationResult) := do
  let tableName := stmt.table.name

  -- Convert column-value pairs to store format
  -- We need to evaluate expressions, but INSERT values are typically literals
  let emptyRow : Row := { id := 0, values := [], provenance := none }
  let values ← stmt.values.mapM fun cv => do
    let v ← evalExpr emptyRow cv.value
    pure (cv.column.name, v)

  -- Create provenance record
  let prov : Option RowProvenance := match stmt.actor, stmt.rationale with
    | some a, some r => some {
        actor := a
        rationale := r
        timestamp := 0  -- Would use real timestamp
        promptScores := none
      }
    | _, _ => none

  -- Insert into database
  match db.insertInto tableName values prov with
  | none => throw (.tableNotFound tableName)
  | some (newDb, rowId) =>
    pure (newDb, { affectedRows := 1, lastInsertId := some rowId })

/-- Execute an UPDATE statement -/
def execUpdate (db : DatabaseStore) (stmt : UpdateStmt)
    : EvalResult (DatabaseStore × MutationResult) := do
  let tableName := stmt.table.name
  match db.getTable tableName with
  | none => throw (.tableNotFound tableName)
  | some tableStore =>
    -- Find rows to update
    let matchingRows ← tableStore.allRows.filterM (rowMatches · stmt.whereClause)
    let matchingIds := matchingRows.map (·.id)

    -- Create update function
    let emptyRow : Row := { id := 0, values := [], provenance := none }
    let updateFn := fun (row : Row) =>
      if matchingIds.contains row.id then
        stmt.set.foldl (fun r cv =>
          match evalExpr emptyRow cv.value with
          | .ok v => r.setValue cv.column.name v
          | .error _ => r
        ) row
      else
        row

    let (newTable, count) := tableStore.updateWhere
      (fun r => matchingIds.contains r.id) updateFn
    let newDb := db.updateTable tableName (fun _ => newTable)
    pure (newDb, { affectedRows := count, lastInsertId := none })

/-- Execute a DELETE statement -/
def execDelete (db : DatabaseStore) (stmt : DeleteStmt)
    : EvalResult (DatabaseStore × MutationResult) := do
  let tableName := stmt.table.name
  match db.getTable tableName with
  | none => throw (.tableNotFound tableName)
  | some tableStore =>
    -- Find rows to delete
    let matchingRows ← tableStore.allRows.filterM (rowMatches · stmt.whereClause)
    let matchingIds := matchingRows.map (·.id)

    let (newTable, count) := tableStore.deleteWhere (fun r => matchingIds.contains r.id)
    let newDb := db.updateTable tableName (fun _ => newTable)
    pure (newDb, { affectedRows := count, lastInsertId := none })

-- ============================================================================
-- Public API
-- ============================================================================

/-- Result of executing a statement -/
inductive ExecResult where
  | query : ResultSet → ExecResult
  | mutation : MutationResult → ExecResult
  deriving Repr

/-- Execute any statement -/
def exec (db : DatabaseStore) (stmt : Statement)
    : EvalResult (DatabaseStore × ExecResult) := do
  match stmt with
  | .select q =>
    let rs ← execSelect db q
    pure (db, .query rs)
  | .insert s =>
    let (newDb, mr) ← execInsert db s
    pure (newDb, .mutation mr)
  | .update s =>
    let (newDb, mr) ← execUpdate db s
    pure (newDb, .mutation mr)
  | .delete s =>
    let (newDb, mr) ← execDelete db s
    pure (newDb, .mutation mr)

/-- Execute and return human-readable result -/
def execToString (db : DatabaseStore) (stmt : Statement)
    : EvalResult (DatabaseStore × String) := do
  let (newDb, result) ← exec db stmt
  let msg := match result with
    | .query rs => rs.toString
    | .mutation mr =>
      match mr.lastInsertId with
      | some id => s!"OK, {mr.affectedRows} row(s) affected, last ID: {id}"
      | none => s!"OK, {mr.affectedRows} row(s) affected"
  pure (newDb, msg)

end FbqlDt.Query.Eval
