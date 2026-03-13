-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- Main.lean - GQLdt CLI/REPL
--
-- Interactive query interface for the Lithoglyph Query Language.
-- Demonstrates dependently-typed queries with provenance tracking.

import FbqlDt.Query
import FbqlDt.FFI

open FqlDt.Query
open FqlDt.Query.Parser
open FqlDt.Query.Schema
open FqlDt.Query.Store
open FqlDt.Query.TypeCheck
open FqlDt.Query.Eval
open FqlDt.FFI

-- ============================================================================
-- Default Schema
-- ============================================================================

/-- Default example schema for the REPL -/
def defaultSchema : Database := {
  name := "fqldt_demo"
  tables := [
    {
      name := "users"
      columns := [
        { name := "id", colType := .int, nullable := false,
          constraints := [.primaryKey, .notNull] },
        { name := "name", colType := .nonEmptyString, nullable := false,
          constraints := [.notNull] },
        { name := "email", colType := .string, nullable := false,
          constraints := [.notNull, .unique] },
        { name := "age", colType := .boundedNat 0 150, nullable := true },
        { name := "verified", colType := .bool, nullable := false }
      ]
      minPromptScore := some 50
    },
    {
      name := "data"
      columns := [
        { name := "id", colType := .int, nullable := false,
          constraints := [.primaryKey] },
        { name := "value", colType := .float, nullable := false,
          constraints := [.requiresProof] },
        { name := "confidence", colType := .boundedNat 0 100, nullable := false },
        { name := "source", colType := .nonEmptyString, nullable := false }
      ]
      minPromptScore := some 70
    },
    {
      name := "measurements"
      columns := [
        { name := "id", colType := .int, nullable := false,
          constraints := [.primaryKey] },
        { name := "sensor_id", colType := .int, nullable := false },
        { name := "reading", colType := .float, nullable := false },
        { name := "unit", colType := .string, nullable := false },
        { name := "quality_score", colType := .promptScore, nullable := true }
      ]
    }
  ]
}

-- ============================================================================
-- REPL Commands
-- ============================================================================

/-- Built-in REPL commands -/
inductive ReplCommand where
  | help : ReplCommand
  | schema : ReplCommand
  | tables : ReplCommand
  | describe : String → ReplCommand
  | save : ReplCommand
  | quit : ReplCommand
  | query : String → ReplCommand
  deriving Repr

/-- Parse a REPL command -/
def parseCommand (input : String) : ReplCommand :=
  let trimmed := input.trim
  if trimmed == ".help" || trimmed == "?" then .help
  else if trimmed == ".schema" then .schema
  else if trimmed == ".tables" then .tables
  else if trimmed == ".save" then .save
  else if trimmed.startsWith ".describe " then
    .describe (trimmed.drop 10)
  else if trimmed == ".quit" || trimmed == ".exit" || trimmed == "\\q" then .quit
  else .query trimmed

-- ============================================================================
-- REPL Output
-- ============================================================================

/-- Print help message -/
def printHelp : IO Unit := do
  IO.println "GQLdt - Dependently-Typed Lithoglyph Query Language"
  IO.println ""
  IO.println "Commands:"
  IO.println "  .help, ?          Show this help message"
  IO.println "  .schema           Show database schema"
  IO.println "  .tables           List all tables"
  IO.println "  .describe TABLE   Show table structure"
  IO.println "  .save             Save database to disk"
  IO.println "  .quit, .exit, \\q  Exit the REPL (auto-saves)"
  IO.println ""
  IO.println "SQL-like Queries (with provenance):"
  IO.println "  SELECT * FROM table [WHERE expr] [ORDER BY col] [LIMIT n]"
  IO.println "  INSERT INTO table SET col=val, ... ACTOR \"who\" RATIONALE \"why\""
  IO.println "  UPDATE table SET col=val WHERE expr ACTOR \"who\" RATIONALE \"why\""
  IO.println "  DELETE FROM table WHERE expr ACTOR \"who\" RATIONALE \"why\""
  IO.println ""
  IO.println "Note: INSERT/UPDATE/DELETE require ACTOR and RATIONALE for provenance."

/-- Print table list -/
def printTables (db : Database) : IO Unit := do
  IO.println "Tables:"
  for t in db.tables do
    IO.println s!"  {t.name} ({t.columns.length} columns)"

/-- Print schema overview -/
def printSchema (db : Database) : IO Unit := do
  IO.println s!"Database: {db.name}"
  IO.println ""
  for t in db.tables do
    IO.println s!"Table: {t.name}"
    for c in t.columns do
      let nullable := if c.nullable then "NULL" else "NOT NULL"
      let constraints := c.constraints.map fun
        | .primaryKey => "PK"
        | .unique => "UNIQUE"
        | .notNull => ""
        | .requiresProof => "PROOF"
        | .foreignKey t c => s!"FK({t}.{c})"
        | .check e => s!"CHECK({e})"
      let constraintStr := String.intercalate " " (constraints.filter (· != ""))
      IO.println s!"  {c.name}: {c.colType.toString} {nullable} {constraintStr}"
    match t.minPromptScore with
    | some s => IO.println s!"  [Requires PROMPT score >= {s}]"
    | none => pure ()
    IO.println ""

-- Helper for padding
def rightpad (s : String) (n : Nat) : String :=
  if s.length >= n then s
  else s ++ String.mk (List.replicate (n - s.length) ' ')

/-- Describe a single table -/
def describeTable (db : Database) (name : String) : IO Unit := do
  match db.findTable name with
  | none => IO.println s!"Error: Table '{name}' not found"
  | some t =>
    IO.println s!"Table: {t.name}"
    IO.println (String.mk (List.replicate 50 '-'))
    for c in t.columns do
      let nullable := if c.nullable then "YES" else "NO"
      IO.println s!"  {rightpad c.name 15} {rightpad c.colType.toString 20} Null: {nullable}"
    IO.println ""
    -- Print constraints
    let hasConstraints := t.columns.any (fun c => !c.constraints.isEmpty)
    if hasConstraints then
      IO.println "Constraints:"
      for c in t.columns do
        for constr in c.constraints do
          match constr with
          | .primaryKey => IO.println s!"  PRIMARY KEY ({c.name})"
          | .unique => IO.println s!"  UNIQUE ({c.name})"
          | .requiresProof => IO.println s!"  REQUIRES PROOF ({c.name})"
          | _ => pure ()

-- ============================================================================
-- Query Execution
-- ============================================================================

/-- Execute a query and return result string -/
def executeQuery (db : Database) (store : DatabaseStore) (input : String)
    : IO (DatabaseStore × String) := do
  -- Parse the query
  match parse input with
  | .error parseErr =>
    pure (store, s!"Parse error: {parseErr}")
  | .ok stmt =>
    -- Type check
    match typeCheck db stmt with
    | .error typeErr =>
      pure (store, s!"Type error: {typeErr}")
    | .ok _ =>
      -- Execute
      match execToString store stmt with
      | .error evalErr =>
        pure (store, s!"Execution error: {evalErr.message}")
      | .ok (newStore, result) =>
        pure (newStore, result)

-- ============================================================================
-- REPL Loop
-- ============================================================================

/-- Run the REPL loop -/
partial def replLoop (db : Database) (store : DatabaseStore) : IO Unit := do
  IO.print "fqldt> "
  let stdin ← IO.getStdin
  let input ← stdin.getLine

  if input.isEmpty then
    replLoop db store
  else
    let cmd := parseCommand input
    match cmd with
    | .quit =>
      -- Auto-save on quit
      let ts ← IO.monoMsNow
      let status ← saveDB ts.toInt32
      if status.isOk then
        IO.println "Database saved."
      IO.println "Goodbye!"
    | .save =>
      let ts ← IO.monoMsNow
      let status ← saveDB ts.toInt32
      if status.isOk then
        IO.println "Database saved to fqldt.db"
      else
        IO.println s!"Save failed: {status.message}"
      replLoop db store
    | .help =>
      printHelp
      replLoop db store
    | .schema =>
      printSchema db
      replLoop db store
    | .tables =>
      printTables db
      replLoop db store
    | .describe name =>
      describeTable db name
      replLoop db store
    | .query q =>
      if q.isEmpty then
        replLoop db store
      else
        let (newStore, result) ← executeQuery db store q
        IO.println result
        IO.println ""
        replLoop db newStore

-- ============================================================================
-- Main Entry Point
-- ============================================================================

def main (args : List String) : IO Unit := do
  IO.println "╔════════════════════════════════════════════════════════════════╗"
  IO.println "║  GQLdt - Dependently-Typed Lithoglyph Query Language  v1.0.0       ║"
  IO.println "║  Type .help for commands, .quit to exit                        ║"
  IO.println "╚════════════════════════════════════════════════════════════════╝"
  IO.println ""

  -- Check for --help flag
  if args.contains "--help" || args.contains "-h" then
    printHelp
    return

  -- Initialize FFI persistence backend
  let dbPath := args.find? (·.startsWith "--db=")
    |>.map (·.drop 5)
    |>.getD "fqldt.db"

  -- Initialize FFI persistence backend
  let initResult := FqlDt.FFI.fdbInitFFI 0 dbPath.length.toUSize
  let initStatus := FdbStatus.fromInt initResult.toInt
  if !initStatus.isOk then
    IO.println s!"Warning: FFI backend init failed: {initStatus.message}"
    IO.println "Running in memory-only mode."

  -- Initialize schema and store
  let db := defaultSchema
  let store := DatabaseStore.fromSchema db

  IO.println s!"Loaded schema: {db.name} with {db.tables.length} tables"
  IO.println s!"Database file: {dbPath}"
  IO.println "Type .tables to list tables, .schema for full schema"
  IO.println ""

  -- Start REPL
  replLoop db store

  -- Cleanup FFI on exit
  let _ ← closeDB
