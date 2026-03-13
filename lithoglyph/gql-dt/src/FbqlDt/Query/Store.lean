-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Query.Store - In-memory data store for GQL
--
-- Provides a simple in-memory storage backend for query execution.
-- Each value is tracked with provenance and PROMPT scores.

import FbqlDt.Query.Schema
import FbqlDt.Provenance.Tracked
import FbqlDt.Prompt.PromptScores

namespace FbqlDt.Query.Store

open FbqlDt.Query.Schema
open FbqlDt.Provenance
open FbqlDt.Prompt

-- ============================================================================
-- Value Types
-- ============================================================================

/-- A stored value with optional provenance -/
inductive Value where
  | null : Value
  | bool : Bool → Value
  | int : Int → Value
  | float : Float → Value
  | string : String → Value
  deriving Repr, BEq, Inhabited

namespace Value

/-- Convert to string for display -/
def toString : Value → String
  | .null => "NULL"
  | .bool b => if b then "TRUE" else "FALSE"
  | .int i => s!"{i}"
  | .float f => s!"{f}"
  | .string s => s!"\"{s}\""

/-- Check if value matches a column type -/
def matchesType (v : Value) (t : ColumnType) : Bool :=
  match v, t with
  | .null, _ => true  -- NULL matches any type
  | .bool _, .bool => true
  | .int _, .int => true
  | .int i, .boundedInt lo hi => lo <= i && i <= hi
  | .int i, .boundedNat lo hi => 0 <= i && i.toNat >= lo && i.toNat <= hi
  | .int i, .promptScore => 0 <= i && i <= 100
  | .float _, .float => true
  | .string _, .string => true
  | .string s, .nonEmptyString => !s.isEmpty
  | _, _ => false

end Value

-- ============================================================================
-- Row Types
-- ============================================================================

/-- Provenance metadata for a row -/
structure RowProvenance where
  actor : String
  rationale : String
  timestamp : Nat  -- Unix timestamp in ms
  promptScores : Option (Nat × Nat × Nat × Nat × Nat × Nat)  -- P R O M P T
  deriving Repr, BEq

/-- A row in a table -/
structure Row where
  id : Nat
  values : List (String × Value)  -- column name -> value
  provenance : Option RowProvenance
  deriving Repr

namespace Row

/-- Get value by column name -/
def getValue (r : Row) (col : String) : Option Value :=
  r.values.find? (·.1 == col) |>.map (·.2)

/-- Set value by column name -/
def setValue (r : Row) (col : String) (v : Value) : Row :=
  let newValues := r.values.map fun (c, val) =>
    if c == col then (c, v) else (c, val)
  { r with values := newValues }

/-- Check if row has a column -/
def hasColumn (r : Row) (col : String) : Bool :=
  r.values.any (·.1 == col)

end Row

-- ============================================================================
-- Table Store
-- ============================================================================

/-- An in-memory table with rows -/
structure TableStore where
  schema : Table
  rows : List Row
  nextId : Nat
  deriving Repr

namespace TableStore

/-- Create empty table store -/
def empty (schema : Table) : TableStore := {
  schema := schema
  rows := []
  nextId := 1
}

/-- Get row count -/
def count (t : TableStore) : Nat := t.rows.length

/-- Find row by ID -/
def findById (t : TableStore) (id : Nat) : Option Row :=
  t.rows.find? (·.id == id)

/-- Insert a row -/
def insert (t : TableStore) (values : List (String × Value))
    (prov : Option RowProvenance) : TableStore × Nat :=
  let row : Row := {
    id := t.nextId
    values := values
    provenance := prov
  }
  ({ t with rows := t.rows ++ [row], nextId := t.nextId + 1 }, t.nextId)

/-- Delete rows matching predicate -/
def deleteWhere (t : TableStore) (pred : Row → Bool) : TableStore × Nat :=
  let (keep, delete) := t.rows.partition (fun r => !pred r)
  ({ t with rows := keep }, delete.length)

/-- Update rows matching predicate -/
def updateWhere (t : TableStore) (pred : Row → Bool)
    (update : Row → Row) : TableStore × Nat :=
  let updated := t.rows.map fun r =>
    if pred r then update r else r
  let count := t.rows.filter pred |>.length
  ({ t with rows := updated }, count)

/-- Get all rows -/
def allRows (t : TableStore) : List Row := t.rows

/-- Filter rows -/
def filter (t : TableStore) (pred : Row → Bool) : List Row :=
  t.rows.filter pred

end TableStore

-- ============================================================================
-- Database Store
-- ============================================================================

/-- An in-memory database with multiple tables -/
structure DatabaseStore where
  schema : Database
  tables : List (String × TableStore)
  deriving Repr

namespace DatabaseStore

/-- Create empty database store from schema -/
def fromSchema (db : Database) : DatabaseStore := {
  schema := db
  tables := db.tables.map fun t => (t.name, TableStore.empty t)
}

/-- Get table store by name -/
def getTable (db : DatabaseStore) (name : String) : Option TableStore :=
  db.tables.find? (·.1 == name) |>.map (·.2)

/-- Update a table store -/
def updateTable (db : DatabaseStore) (name : String)
    (f : TableStore → TableStore) : DatabaseStore :=
  let newTables := db.tables.map fun (n, t) =>
    if n == name then (n, f t) else (n, t)
  { db with tables := newTables }

/-- Insert into a table -/
def insertInto (db : DatabaseStore) (tableName : String)
    (values : List (String × Value)) (prov : Option RowProvenance)
    : Option (DatabaseStore × Nat) :=
  match db.getTable tableName with
  | none => none
  | some t =>
    let (newTable, rowId) := t.insert values prov
    some (db.updateTable tableName (fun _ => newTable), rowId)

/-- Get row count for a table -/
def tableCount (db : DatabaseStore) (name : String) : Option Nat :=
  db.getTable name |>.map (·.count)

end DatabaseStore

-- ============================================================================
-- Query Results
-- ============================================================================

/-- A query result set -/
structure ResultSet where
  columns : List String
  rows : List (List Value)
  rowCount : Nat
  deriving Repr

namespace ResultSet

/-- Empty result set -/
def empty : ResultSet := {
  columns := []
  rows := []
  rowCount := 0
}

/-- Create from rows with specific columns -/
def fromRows (cols : List String) (rows : List Row) : ResultSet := {
  columns := cols
  rows := rows.map fun r =>
    cols.map fun c => r.getValue c |>.getD .null
  rowCount := rows.length
}

/-- Pretty print result set -/
def toString (rs : ResultSet) : String :=
  if rs.rowCount == 0 then
    "(0 rows)"
  else
    let header := String.intercalate " | " rs.columns
    let separator := String.mk (List.replicate header.length '-')
    let rowStrs := rs.rows.map fun row =>
      String.intercalate " | " (row.map Value.toString)
    s!"{header}\n{separator}\n{String.intercalate "\n" rowStrs}\n({rs.rowCount} rows)"

end ResultSet

/-- Result of a mutation (INSERT/UPDATE/DELETE) -/
structure MutationResult where
  affectedRows : Nat
  lastInsertId : Option Nat
  deriving Repr

end FbqlDt.Query.Store
