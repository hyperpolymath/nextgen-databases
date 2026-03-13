-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Query.AST - Abstract Syntax Tree for GQL queries
--
-- Defines the core AST types for the Lithoglyph Query Language.
-- GQL is designed for proof-carrying queries with provenance tracking.

import FbqlDt.Types.NonEmptyString
import FbqlDt.Prompt.PromptScores

namespace FbqlDt.Query

-- ============================================================================
-- Identifiers
-- ============================================================================

/-- Table name identifier -/
structure TableName where
  name : String
  deriving Repr, BEq, Inhabited

/-- Column name identifier -/
structure ColumnName where
  name : String
  deriving Repr, BEq, Inhabited

/-- Qualified column reference (table.column) -/
structure QualifiedColumn where
  table : Option TableName
  column : ColumnName
  deriving Repr, BEq

namespace QualifiedColumn

def unqualified (col : String) : QualifiedColumn :=
  { table := none, column := { name := col } }

def qualified (tbl col : String) : QualifiedColumn :=
  { table := some { name := tbl }, column := { name := col } }

end QualifiedColumn

-- ============================================================================
-- Literal Values
-- ============================================================================

/-- Literal values in GQL expressions -/
inductive Literal where
  | null : Literal
  | bool : Bool → Literal
  | int : Int → Literal
  | float : Float → Literal
  | string : String → Literal
  deriving Repr, BEq

namespace Literal

def toString : Literal → String
  | .null => "NULL"
  | .bool b => if b then "TRUE" else "FALSE"
  | .int i => s!"{i}"
  | .float f => s!"{f}"
  | .string s => s!"\"{s}\""

end Literal

-- ============================================================================
-- Expressions
-- ============================================================================

/-- Comparison operators -/
inductive CompOp where
  | eq : CompOp      -- =
  | neq : CompOp     -- != or <>
  | lt : CompOp      -- <
  | le : CompOp      -- <=
  | gt : CompOp      -- >
  | ge : CompOp      -- >=
  deriving Repr, BEq

/-- Logical operators -/
inductive LogicOp where
  | and : LogicOp
  | or : LogicOp
  deriving Repr, BEq

/-- GQL expressions -/
inductive Expr where
  | lit : Literal → Expr
  | col : QualifiedColumn → Expr
  | compare : Expr → CompOp → Expr → Expr
  | logic : Expr → LogicOp → Expr → Expr
  | not : Expr → Expr
  | isNull : Expr → Expr
  | isNotNull : Expr → Expr
  | between : Expr → Expr → Expr → Expr
  | inList : Expr → List Expr → Expr
  deriving Repr, BEq

namespace Expr

/-- Create a column reference expression -/
def column (name : String) : Expr :=
  .col (QualifiedColumn.unqualified name)

/-- Create a qualified column reference expression -/
def qualColumn (table column : String) : Expr :=
  .col (QualifiedColumn.qualified table column)

/-- Create a literal integer expression -/
def intLit (i : Int) : Expr :=
  .lit (.int i)

/-- Create a literal string expression -/
def strLit (s : String) : Expr :=
  .lit (.string s)

/-- Create a literal boolean expression -/
def boolLit (b : Bool) : Expr :=
  .lit (.bool b)

/-- Create an equality comparison -/
def eq (lhs rhs : Expr) : Expr :=
  .compare lhs .eq rhs

/-- Create an AND expression -/
def «and» (lhs rhs : Expr) : Expr :=
  .logic lhs .and rhs

/-- Create an OR expression -/
def «or» (lhs rhs : Expr) : Expr :=
  .logic lhs .or rhs

end Expr

-- ============================================================================
-- SELECT Projections
-- ============================================================================

/-- What to select in a query -/
inductive Projection where
  | all : Projection                          -- SELECT *
  | columns : List ColumnName → Projection    -- SELECT col1, col2, ...
  | exprs : List (Expr × Option String) → Projection  -- SELECT expr AS alias, ...
  deriving Repr

-- ============================================================================
-- ORDER BY
-- ============================================================================

/-- Sort direction -/
inductive SortDir where
  | asc : SortDir
  | desc : SortDir
  deriving Repr, BEq

/-- ORDER BY clause item -/
structure OrderBy where
  column : QualifiedColumn
  direction : SortDir
  deriving Repr

-- ============================================================================
-- Query Types
-- ============================================================================

/-- SELECT query -/
structure SelectQuery where
  projection : Projection
  «from» : TableName
  whereClause : Option Expr
  orderBy : List OrderBy
  limit : Option Nat
  offset : Option Nat
  deriving Repr

/-- Column value for INSERT -/
structure ColumnValue where
  column : ColumnName
  value : Expr
  deriving Repr

/-- INSERT statement -/
structure InsertStmt where
  table : TableName
  values : List ColumnValue
  -- Provenance metadata (required for GQL)
  actor : Option String
  rationale : Option String
  -- Optional PROMPT score (0-100) for data quality enforcement
  promptScore : Option Nat
  deriving Repr

/-- UPDATE statement -/
structure UpdateStmt where
  table : TableName
  set : List ColumnValue
  whereClause : Option Expr
  -- Provenance metadata
  actor : Option String
  rationale : Option String
  deriving Repr

/-- DELETE statement -/
structure DeleteStmt where
  table : TableName
  whereClause : Option Expr
  -- Provenance metadata
  actor : Option String
  rationale : Option String
  deriving Repr

/-- Top-level GQL statement -/
inductive Statement where
  | select : SelectQuery → Statement
  | insert : InsertStmt → Statement
  | update : UpdateStmt → Statement
  | delete : DeleteStmt → Statement
  deriving Repr

namespace Statement

/-- Check if statement is a query (SELECT) -/
def isQuery : Statement → Bool
  | .select _ => true
  | _ => false

/-- Check if statement is a mutation (INSERT/UPDATE/DELETE) -/
def isMutation : Statement → Bool
  | .select _ => false
  | _ => true

end Statement

end FbqlDt.Query
