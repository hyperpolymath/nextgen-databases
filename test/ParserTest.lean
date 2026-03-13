-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- ParserTest.lean - Tests for GQL Parser
--
-- Run with: lake build && lean --run test/ParserTest.lean

import FqlDt.Query

open FqlDt.Query
open FqlDt.Query.Parser

/-- Test SELECT * FROM table -/
def testSelectAll : IO Unit := do
  IO.println "Testing SELECT * FROM users..."
  match parseSelect "SELECT * FROM users" with
  | .ok q =>
    IO.println s!"  ✓ Parsed: table = {q.from.name}, projection = all"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Test SELECT with columns -/
def testSelectColumns : IO Unit := do
  IO.println "Testing SELECT id, name FROM users..."
  match parseSelect "SELECT id, name FROM users" with
  | .ok q =>
    IO.println s!"  ✓ Parsed: table = {q.from.name}"
    match q.projection with
    | .columns cols =>
      IO.println s!"    columns = {cols.map (·.name)}"
    | _ =>
      IO.println "    (unexpected projection type)"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Test SELECT with WHERE clause -/
def testSelectWhere : IO Unit := do
  IO.println "Testing SELECT * FROM users WHERE id = 1..."
  match parseSelect "SELECT * FROM users WHERE id = 1" with
  | .ok q =>
    IO.println s!"  ✓ Parsed: table = {q.from.name}"
    match q.whereClause with
    | some _ =>
      IO.println "    where = (expression present)"
    | none =>
      IO.println "    where = none"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Test INSERT statement -/
def testInsert : IO Unit := do
  IO.println "Testing INSERT INTO users SET name = \"Alice\"..."
  match parse "INSERT INTO users SET name = \"Alice\"" with
  | .ok stmt =>
    match stmt with
    | .insert i =>
      IO.println s!"  ✓ Parsed INSERT: table = {i.table.name}"
      IO.println s!"    values count = {i.values.length}"
    | _ =>
      IO.println "  ✗ Got wrong statement type"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Test INSERT with provenance -/
def testInsertProvenance : IO Unit := do
  IO.println "Testing INSERT with ACTOR and RATIONALE..."
  let query := "INSERT INTO data SET value = 42 ACTOR \"system\" RATIONALE \"Initial data\""
  match parse query with
  | .ok stmt =>
    match stmt with
    | .insert i =>
      IO.println s!"  ✓ Parsed INSERT: table = {i.table.name}"
      IO.println s!"    actor = {repr i.actor}"
      IO.println s!"    rationale = {repr i.rationale}"
    | _ =>
      IO.println "  ✗ Got wrong statement type"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Test UPDATE statement -/
def testUpdate : IO Unit := do
  IO.println "Testing UPDATE users SET name = \"Bob\" WHERE id = 1..."
  match parse "UPDATE users SET name = \"Bob\" WHERE id = 1" with
  | .ok stmt =>
    match stmt with
    | .update u =>
      IO.println s!"  ✓ Parsed UPDATE: table = {u.table.name}"
      IO.println s!"    set count = {u.set.length}"
      IO.println s!"    has where = {u.whereClause.isSome}"
    | _ =>
      IO.println "  ✗ Got wrong statement type"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Test DELETE statement -/
def testDelete : IO Unit := do
  IO.println "Testing DELETE FROM users WHERE id = 1..."
  match parse "DELETE FROM users WHERE id = 1" with
  | .ok stmt =>
    match stmt with
    | .delete d =>
      IO.println s!"  ✓ Parsed DELETE: table = {d.table.name}"
      IO.println s!"    has where = {d.whereClause.isSome}"
    | _ =>
      IO.println "  ✗ Got wrong statement type"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Test expression parsing -/
def testExpressions : IO Unit := do
  IO.println "Testing expressions..."

  -- Simple comparison
  match parseExpr "x = 1" with
  | .ok _ => IO.println "  ✓ x = 1"
  | .error e => IO.println s!"  ✗ x = 1: {e}"

  -- String comparison
  match parseExpr "name = \"Alice\"" with
  | .ok _ => IO.println "  ✓ name = \"Alice\""
  | .error e => IO.println s!"  ✗ name = \"Alice\": {e}"

  -- AND expression
  match parseExpr "a = 1 AND b = 2" with
  | .ok _ => IO.println "  ✓ a = 1 AND b = 2"
  | .error e => IO.println s!"  ✗ a = 1 AND b = 2: {e}"

  -- OR expression
  match parseExpr "a = 1 OR b = 2" with
  | .ok _ => IO.println "  ✓ a = 1 OR b = 2"
  | .error e => IO.println s!"  ✗ a = 1 OR b = 2: {e}"

  -- Comparison operators
  match parseExpr "x > 10" with
  | .ok _ => IO.println "  ✓ x > 10"
  | .error e => IO.println s!"  ✗ x > 10: {e}"

  match parseExpr "x <= 100" with
  | .ok _ => IO.println "  ✓ x <= 100"
  | .error e => IO.println s!"  ✗ x <= 100: {e}"

/-- Test SELECT with ORDER BY and LIMIT -/
def testSelectAdvanced : IO Unit := do
  IO.println "Testing SELECT with ORDER BY and LIMIT..."
  match parseSelect "SELECT * FROM users ORDER BY name LIMIT 10" with
  | .ok q =>
    IO.println s!"  ✓ Parsed: table = {q.from.name}"
    IO.println s!"    orderBy count = {q.orderBy.length}"
    IO.println s!"    limit = {repr q.limit}"
  | .error e =>
    IO.println s!"  ✗ Failed: {e}"

/-- Main test runner -/
def main : IO Unit := do
  IO.println "═══════════════════════════════════════════════"
  IO.println "  GQL Parser Tests"
  IO.println "═══════════════════════════════════════════════"
  IO.println ""

  testSelectAll
  IO.println ""

  testSelectColumns
  IO.println ""

  testSelectWhere
  IO.println ""

  testSelectAdvanced
  IO.println ""

  testInsert
  IO.println ""

  testInsertProvenance
  IO.println ""

  testUpdate
  IO.println ""

  testDelete
  IO.println ""

  testExpressions
  IO.println ""

  IO.println "═══════════════════════════════════════════════"
  IO.println "  Parser tests completed"
  IO.println "═══════════════════════════════════════════════"
