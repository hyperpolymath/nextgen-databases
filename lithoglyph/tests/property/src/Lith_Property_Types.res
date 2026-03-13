// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Property Test Types
 *
 * Type definitions for property-based testing
 */

/** Arbitrary value generator */
type arbitrary<'a> = {
  generate: unit => 'a,
  shrink: 'a => array<'a>,
}

/** Property test result */
type propertyResult =
  | Passed({iterations: int})
  | Failed({iteration: int, counterexample: string, shrunk: option<string>})
  | Errored({iteration: int, error: string})

/** Property test configuration */
type propertyConfig = {
  iterations: int,
  seed: option<int>,
  maxShrinks: int,
  verbose: bool,
}

/** Default property config */
let defaultConfig: propertyConfig = {
  iterations: 100,
  seed: None,
  maxShrinks: 100,
  verbose: false,
}

/** GQL statement types for generation */
type gqlStatementType =
  | Select
  | Insert
  | Update
  | Delete
  | Create
  | Drop
  | Explain
  | Introspect

/** All statement types */
let allStatementTypes: array<gqlStatementType> = [
  Select,
  Insert,
  Update,
  Delete,
  Create,
  Drop,
  Explain,
  Introspect,
]

/** Statement type to string */
let statementTypeToString = (st: gqlStatementType): string =>
  switch st {
  | Select => "SELECT"
  | Insert => "INSERT"
  | Update => "UPDATE"
  | Delete => "DELETE"
  | Create => "CREATE"
  | Drop => "DROP"
  | Explain => "EXPLAIN"
  | Introspect => "INTROSPECT"
  }

/** Comparison operators */
type compareOp =
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  | Like
  | In

/** Compare op to string */
let compareOpToString = (op: compareOp): string =>
  switch op {
  | Eq => "="
  | Ne => "!="
  | Lt => "<"
  | Le => "<="
  | Gt => ">"
  | Ge => ">="
  | Like => "LIKE"
  | In => "IN"
  }

/** All compare ops */
let allCompareOps: array<compareOp> = [Eq, Ne, Lt, Le, Gt, Ge, Like, In]

/** Test suite summary */
type suiteSummary = {passed: int, failed: int, errored: int}

/** Value types for generation */
type rec valueType =
  | StringVal(string)
  | IntVal(int)
  | FloatVal(float)
  | BoolVal(bool)
  | NullVal
  | ArrayVal(array<valueType>)

/** Value to GQL string */
let rec valueToString = (v: valueType): string =>
  switch v {
  | StringVal(s) => `"${s}"`
  | IntVal(i) => Int.toString(i)
  | FloatVal(f) => Float.toString(f)
  | BoolVal(b) => b ? "true" : "false"
  | NullVal => "null"
  | ArrayVal(arr) => "[" ++ arr->Array.map(valueToString)->Array.join(", ") ++ "]"
  }
