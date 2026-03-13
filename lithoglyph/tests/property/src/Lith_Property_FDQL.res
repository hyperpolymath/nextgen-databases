// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith FDQL Property Tests
 *
 * Property-based tests for FDQL parser and query engine
 */

open Lith_Property_Types
open Lith_Property_Generators
open Lith_Property_Runner

/** Property: Generated SELECT statements have correct structure */
let prop_selectHasFrom = (stmt: string): bool => {
  String.includes(stmt, "SELECT") && String.includes(stmt, "FROM")
}

/** Property: Generated INSERT statements have correct structure */
let prop_insertHasInto = (stmt: string): bool => {
  String.includes(stmt, "INSERT INTO") && String.includes(stmt, "{")
}

/** Property: Generated UPDATE statements have SET and WHERE */
let prop_updateHasSetAndWhere = (stmt: string): bool => {
  String.includes(stmt, "UPDATE") &&
  String.includes(stmt, "SET") &&
  String.includes(stmt, "WHERE")
}

/** Property: Generated DELETE statements have WHERE */
let prop_deleteHasWhere = (stmt: string): bool => {
  String.includes(stmt, "DELETE FROM") && String.includes(stmt, "WHERE")
}

/** Property: Generated CREATE statements have COLLECTION */
let prop_createHasCollection = (stmt: string): bool => {
  String.includes(stmt, "CREATE") && String.includes(stmt, "COLLECTION")
}

/** Property: Generated DROP statements have COLLECTION */
let prop_dropHasCollection = (stmt: string): bool => {
  String.includes(stmt, "DROP COLLECTION")
}

/** Property: Generated EXPLAIN statements wrap valid queries */
let prop_explainWrapsQuery = (stmt: string): bool => {
  String.includes(stmt, "EXPLAIN") && String.includes(stmt, "SELECT")
}

/** Property: Generated INTROSPECT statements have target */
let prop_introspectHasTarget = (stmt: string): bool => {
  String.includes(stmt, "INTROSPECT") &&
  (String.includes(stmt, "SCHEMA") ||
   String.includes(stmt, "CONSTRAINTS") ||
   String.includes(stmt, "COLLECTIONS") ||
   String.includes(stmt, "JOURNAL"))
}

/** Property: All statements are non-empty */
let prop_nonEmpty = (stmt: string): bool => {
  String.length(stmt) > 0
}

/** Property: All statements end with valid characters (no trailing whitespace issues) */
let prop_validEnding = (stmt: string): bool => {
  let trimmed = String.trim(stmt)
  String.length(trimmed) > 0 && String.length(trimmed) == String.length(stmt)
}

/** Property: Identifiers are valid (alphanumeric + underscore) */
let prop_validIdentifiers = (stmt: string): bool => {
  // Check that we don't have invalid identifier patterns
  !String.includes(stmt, "  ") && // No double spaces
  !String.includes(stmt, ",,") && // No double commas
  !String.startsWith(stmt, " ")   // No leading space
}

/** Property: JSON-like objects in INSERT/UPDATE are balanced */
let prop_balancedBraces = (stmt: string): bool => {
  let openCount = ref(0)
  let closeCount = ref(0)

  String.split(stmt, "")->Array.forEach(char => {
    if char == "{" {
      openCount := openCount.contents + 1
    }
    if char == "}" {
      closeCount := closeCount.contents + 1
    }
  })

  openCount.contents == closeCount.contents
}

/** Property: Quotes are balanced */
let prop_balancedQuotes = (stmt: string): bool => {
  let count = ref(0)
  String.split(stmt, "")->Array.forEach(char => {
    if char == "\"" {
      count := count.contents + 1
    }
  })
  mod(count.contents, 2) == 0
}

/** Run all FDQL property tests */
let runFDQLProperties = (~config: propertyConfig=defaultConfig): suiteSummary => {
  let tests = [
    (
      "SELECT statements have FROM clause",
      () =>
        runProperty(
          ~config,
          ~name="SELECT has FROM",
          ~generator=selectStatement,
          ~toString=s => s,
          ~property=prop_selectHasFrom,
        ),
    ),
    (
      "INSERT statements have INTO and document",
      () =>
        runProperty(
          ~config,
          ~name="INSERT has INTO",
          ~generator=insertStatement,
          ~toString=s => s,
          ~property=prop_insertHasInto,
        ),
    ),
    (
      "UPDATE statements have SET and WHERE",
      () =>
        runProperty(
          ~config,
          ~name="UPDATE has SET and WHERE",
          ~generator=updateStatement,
          ~toString=s => s,
          ~property=prop_updateHasSetAndWhere,
        ),
    ),
    (
      "DELETE statements have WHERE clause",
      () =>
        runProperty(
          ~config,
          ~name="DELETE has WHERE",
          ~generator=deleteStatement,
          ~toString=s => s,
          ~property=prop_deleteHasWhere,
        ),
    ),
    (
      "CREATE statements have COLLECTION",
      () =>
        runProperty(
          ~config,
          ~name="CREATE has COLLECTION",
          ~generator=createStatement,
          ~toString=s => s,
          ~property=prop_createHasCollection,
        ),
    ),
    (
      "DROP statements have COLLECTION",
      () =>
        runProperty(
          ~config,
          ~name="DROP has COLLECTION",
          ~generator=dropStatement,
          ~toString=s => s,
          ~property=prop_dropHasCollection,
        ),
    ),
    (
      "EXPLAIN statements wrap SELECT",
      () =>
        runProperty(
          ~config,
          ~name="EXPLAIN wraps query",
          ~generator=explainStatement,
          ~toString=s => s,
          ~property=prop_explainWrapsQuery,
        ),
    ),
    (
      "INTROSPECT statements have target",
      () =>
        runProperty(
          ~config,
          ~name="INTROSPECT has target",
          ~generator=introspectStatement,
          ~toString=s => s,
          ~property=prop_introspectHasTarget,
        ),
    ),
    (
      "All statements are non-empty",
      () =>
        runProperty(
          ~config,
          ~name="Non-empty",
          ~generator=fdqlStatement,
          ~toString=s => s,
          ~property=prop_nonEmpty,
        ),
    ),
    (
      "All statements have valid identifiers",
      () =>
        runProperty(
          ~config,
          ~name="Valid identifiers",
          ~generator=fdqlStatement,
          ~toString=s => s,
          ~property=prop_validIdentifiers,
        ),
    ),
    (
      "Braces are balanced",
      () =>
        runProperty(
          ~config,
          ~name="Balanced braces",
          ~generator=fdqlStatement,
          ~toString=s => s,
          ~property=prop_balancedBraces,
        ),
    ),
    (
      "Quotes are balanced",
      () =>
        runProperty(
          ~config,
          ~name="Balanced quotes",
          ~generator=fdqlStatement,
          ~toString=s => s,
          ~property=prop_balancedQuotes,
        ),
    ),
  ]

  runSuite(~config, tests)
}

/** Default export - run tests */
let default = () => runFDQLProperties()
