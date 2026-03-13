-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Query.Schema - Database schema definitions
--
-- Defines table schemas, column types, and constraints for GQL type checking.

import FbqlDt.Types.BoundedNat
import FbqlDt.Prompt.PromptScores

namespace FbqlDt.Query.Schema

-- ============================================================================
-- Column Types
-- ============================================================================

/-- SQL-like column types with GQL extensions -/
inductive ColumnType where
  | int : ColumnType
  | float : ColumnType
  | string : ColumnType
  | bool : ColumnType
  | timestamp : ColumnType
  -- GQL extensions: bounded types with compile-time constraints
  | boundedInt : Int → Int → ColumnType      -- min, max
  | boundedNat : Nat → Nat → ColumnType      -- min, max
  | nonEmptyString : ColumnType
  | promptScore : ColumnType                  -- 0-100 score
  deriving Repr, BEq

namespace ColumnType

/-- Human-readable type name -/
def toString : ColumnType → String
  | .int => "INT"
  | .float => "FLOAT"
  | .string => "STRING"
  | .bool => "BOOL"
  | .timestamp => "TIMESTAMP"
  | .boundedInt lo hi => s!"INT[{lo}..{hi}]"
  | .boundedNat lo hi => s!"NAT[{lo}..{hi}]"
  | .nonEmptyString => "NONEMPTY_STRING"
  | .promptScore => "PROMPT_SCORE"

/-- Check if type is numeric -/
def isNumeric : ColumnType → Bool
  | .int | .float | .boundedInt _ _ | .boundedNat _ _ | .promptScore => true
  | _ => false

/-- Check if type is comparable with another -/
def isComparable (t1 t2 : ColumnType) : Bool :=
  match t1, t2 with
  | .int, .int | .int, .boundedInt _ _ | .boundedInt _ _, .int => true
  | .boundedInt _ _, .boundedInt _ _ => true
  | .float, .float => true
  | .string, .string | .string, .nonEmptyString | .nonEmptyString, .string => true
  | .nonEmptyString, .nonEmptyString => true
  | .bool, .bool => true
  | .timestamp, .timestamp => true
  | .boundedNat _ _, .boundedNat _ _ => true
  | .promptScore, .promptScore => true
  | .promptScore, .boundedNat _ _ | .boundedNat _ _, .promptScore => true
  | _, _ => false

end ColumnType

-- ============================================================================
-- Column Constraints
-- ============================================================================

/-- Constraints that can be applied to columns -/
inductive Constraint where
  | notNull : Constraint
  | unique : Constraint
  | primaryKey : Constraint
  | foreignKey : String → String → Constraint  -- table, column
  | check : String → Constraint                 -- expression as string (for display)
  | requiresProof : Constraint                  -- GQL: requires proof for insertion
  deriving Repr, BEq

-- ============================================================================
-- Column Definition
-- ============================================================================

/-- A column in a table schema -/
structure Column where
  name : String
  colType : ColumnType
  nullable : Bool := true
  constraints : List Constraint := []
  deriving Repr

namespace Column

/-- Check if column is a primary key -/
def isPrimaryKey (c : Column) : Bool :=
  c.constraints.any fun
    | .primaryKey => true
    | _ => false

/-- Check if column requires proof for insertion -/
def requiresProof (c : Column) : Bool :=
  c.constraints.any fun
    | .requiresProof => true
    | _ => false

end Column

-- ============================================================================
-- Table Schema
-- ============================================================================

/-- A table schema definition -/
structure Table where
  name : String
  columns : List Column
  -- GQL extension: minimum PROMPT score required for insertions
  minPromptScore : Option Nat := none
  deriving Repr

namespace Table

/-- Find a column by name -/
def findColumn (t : Table) (name : String) : Option Column :=
  t.columns.find? (·.name == name)

/-- Get column type by name -/
def columnType (t : Table) (name : String) : Option ColumnType :=
  t.findColumn name |>.map (·.colType)

/-- Get list of column names -/
def columnNames (t : Table) : List String :=
  t.columns.map (·.name)

/-- Check if table has a column -/
def hasColumn (t : Table) (name : String) : Bool :=
  t.columns.any (·.name == name)

/-- Get primary key columns -/
def primaryKeyColumns (t : Table) : List Column :=
  t.columns.filter (·.isPrimaryKey)

/-- Get columns requiring proof -/
def proofColumns (t : Table) : List Column :=
  t.columns.filter (·.requiresProof)

end Table

-- ============================================================================
-- Database Schema
-- ============================================================================

/-- A complete database schema -/
structure Database where
  name : String
  tables : List Table
  deriving Repr

namespace Database

/-- Find a table by name -/
def findTable (db : Database) (name : String) : Option Table :=
  db.tables.find? (·.name == name)

/-- Check if database has a table -/
def hasTable (db : Database) (name : String) : Bool :=
  db.tables.any (·.name == name)

/-- Get list of table names -/
def tableNames (db : Database) : List String :=
  db.tables.map (·.name)

/-- Create an empty database -/
def empty (name : String) : Database :=
  { name := name, tables := [] }

/-- Add a table to the database -/
def addTable (db : Database) (t : Table) : Database :=
  { db with tables := db.tables ++ [t] }

end Database

-- ============================================================================
-- Example Schema
-- ============================================================================

/-- Example: users table schema -/
def usersTable : Table := {
  name := "users"
  columns := [
    { name := "id", colType := .int, nullable := false,
      constraints := [.primaryKey, .notNull] },
    { name := "name", colType := .nonEmptyString, nullable := false,
      constraints := [.notNull] },
    { name := "email", colType := .string, nullable := false,
      constraints := [.notNull, .unique] },
    { name := "age", colType := .boundedNat 0 150, nullable := true },
    { name := "score", colType := .promptScore, nullable := true,
      constraints := [.requiresProof] },
    { name := "created_at", colType := .timestamp, nullable := false }
  ]
  minPromptScore := some 50
}

/-- Example: data table with strict provenance -/
def dataTable : Table := {
  name := "data"
  columns := [
    { name := "id", colType := .int, nullable := false,
      constraints := [.primaryKey] },
    { name := "value", colType := .float, nullable := false,
      constraints := [.requiresProof] },
    { name := "confidence", colType := .boundedNat 0 100, nullable := false,
      constraints := [.requiresProof] },
    { name := "source", colType := .nonEmptyString, nullable := false }
  ]
  minPromptScore := some 70
}

/-- Example database -/
def exampleDb : Database := {
  name := "example"
  tables := [usersTable, dataTable]
}

end FbqlDt.Query.Schema
