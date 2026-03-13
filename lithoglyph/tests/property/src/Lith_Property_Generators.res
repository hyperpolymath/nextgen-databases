// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

/**
 * Lith Property Test Generators
 *
 * Random value generators for property-based testing.
 *
 * SECURITY NOTE: All identifiers and values are sanitized before being
 * interpolated into GQL statements. Even though test generators draw
 * from hardcoded safe arrays, we use parameterized-style construction
 * and input validation to demonstrate safe query patterns. This prevents
 * SQL/GQL injection if generators are ever extended to accept external
 * input (e.g. from fuzz harnesses or user-supplied seeds).
 */

open Lith_Property_Types

/** Random number generator state */
type rng = {mutable seed: int}

/** Create RNG with seed */
let makeRng = (seed: int): rng => {seed: seed}

/** Generate next random int (LCG algorithm) */
let nextInt = (rng: rng): int => {
  // Linear Congruential Generator (mask to 31 bits to stay in int range)
  rng.seed = land(rng.seed * 1103515245 + 12345, 0x7FFFFFFF)
  rng.seed
}

/** Generate random int in range [min, max) */
let intInRange = (rng: rng, ~min: int, ~max: int): int => {
  let range = max - min
  if range <= 0 {
    min
  } else {
    min + mod(abs(nextInt(rng)), range)
  }
}

/** Generate random float in range [0, 1) */
let float01 = (rng: rng): float => {
  Float.fromInt(abs(nextInt(rng))) /. 2147483648.0
}

/** Generate random bool */
let bool = (rng: rng): bool => {
  mod(nextInt(rng), 2) == 0
}

/** Pick random element from array */
let pick = (rng: rng, arr: array<'a>): option<'a> => {
  let len = Array.length(arr)
  if len == 0 {
    None
  } else {
    Some(arr[intInRange(rng, ~min=0, ~max=len)]->Option.getExn)
  }
}

// =============================================================================
// Input Sanitization — prevents GQL injection in generated queries
// =============================================================================

/**
 * Validate that an identifier contains only safe characters (alphanumeric
 * and underscores). Rejects anything that could alter query structure.
 * Returns the identifier unchanged if valid, or a safe fallback otherwise.
 */
let sanitizeIdentifier = (raw: string): string => {
  let isAlphaNumUnderscore = (ch: string): bool => {
    let code = ch->String.charCodeAt(0)->Option.getOr(0.0)->Float.toInt
    // a-z, A-Z, 0-9, _
    (code >= 97 && code <= 122) ||
    (code >= 65 && code <= 90) ||
    (code >= 48 && code <= 57) ||
    code == 95
  }
  let len = String.length(raw)
  if len == 0 {
    "_sanitized_empty"
  } else {
    let allSafe = ref(true)
    for i in 0 to len - 1 {
      let ch = String.charAt(raw, i)
      if !isAlphaNumUnderscore(ch) {
        allSafe := false
      }
    }
    if allSafe.contents {
      raw
    } else {
      "_sanitized_fallback"
    }
  }
}

/**
 * Escape a string value for safe interpolation into GQL string literals.
 * Escapes backslashes, double quotes, and control characters that could
 * break out of a quoted string context.
 */
let escapeStringValue = (raw: string): string => {
  raw
  ->String.replaceAll("\\", "\\\\")
  ->String.replaceAll("\"", "\\\"")
  ->String.replaceAll("\n", "\\n")
  ->String.replaceAll("\r", "\\r")
  ->String.replaceAll("\t", "\\t")
}

// =============================================================================
// Parameterized Query Builder — structured construction instead of raw concat
// =============================================================================

/**
 * Represents a parameterized GQL statement. Parameters are bound separately
 * from the query template, preventing injection even if values contain
 * GQL metacharacters.
 */
type paramValue =
  | PString(string)
  | PInt(int)
  | PFloat(float)
  | PBool(bool)
  | PNull

/** A parameterized query with named placeholders */
type paramQuery = {
  template: string,
  params: array<(string, paramValue)>,
}

/** Render a paramValue to a safe GQL literal */
let paramValueToGql = (pv: paramValue): string =>
  switch pv {
  | PString(s) => `"${escapeStringValue(s)}"`
  | PInt(i) => Int.toString(i)
  | PFloat(f) => Float.toString(f)
  | PBool(b) => b ? "true" : "false"
  | PNull => "null"
  }

/**
 * Render a parameterized query by substituting placeholders with safe values.
 * Placeholders use the format $name in the template.
 */
let renderParamQuery = (pq: paramQuery): string => {
  let result = ref(pq.template)
  pq.params->Array.forEach(((name, value)) => {
    result := result.contents->String.replaceAll(`$${name}`, paramValueToGql(value))
  })
  result.contents
}

// =============================================================================
// Generators — use sanitization and parameterized construction
// =============================================================================

/** Generate random identifier (valid GQL identifier) */
let identifier = (rng: rng): string => {
  let prefixes = ["user", "post", "article", "product", "order", "item", "comment", "tag", "category"]
  let suffixes = ["", "s", "_data", "_info", "_record"]
  let prefix = pick(rng, prefixes)->Option.getOr("item")
  let suffix = pick(rng, suffixes)->Option.getOr("")
  sanitizeIdentifier(prefix ++ suffix)
}

/** Generate random field name */
let fieldName = (rng: rng): string => {
  let fields = [
    "id", "name", "title", "description", "content", "status",
    "created_at", "updated_at", "author", "email", "price",
    "quantity", "active", "published", "category_id", "user_id",
  ]
  sanitizeIdentifier(pick(rng, fields)->Option.getOr("field"))
}

/** Generate random string value */
let stringValue = (rng: rng): string => {
  let words = ["hello", "world", "test", "example", "sample", "data", "value"]
  let len = intInRange(rng, ~min=1, ~max=4)
  let result = []
  for _ in 1 to len {
    result->Array.push(pick(rng, words)->Option.getOr("word"))->ignore
  }
  result->Array.join(" ")
}

/** Generate random value type */
let valueType = (rng: rng): valueType => {
  let choice = intInRange(rng, ~min=0, ~max=5)
  switch choice {
  | 0 => StringVal(stringValue(rng))
  | 1 => IntVal(intInRange(rng, ~min=-1000, ~max=1000))
  | 2 => FloatVal(float01(rng) *. 1000.0)
  | 3 => BoolVal(bool(rng))
  | 4 => NullVal
  | _ => StringVal(stringValue(rng))
  }
}

/** Convert a valueType to a paramValue for safe binding */
let valueTypeToParam = (v: valueType): paramValue =>
  switch v {
  | StringVal(s) => PString(s)
  | IntVal(i) => PInt(i)
  | FloatVal(f) => PFloat(f)
  | BoolVal(b) => PBool(b)
  | NullVal => PNull
  | ArrayVal(_) => PString("[array]") // Arrays use dedicated syntax
  }

/** Generate random comparison operator */
let compareOp = (rng: rng): compareOp => {
  pick(rng, allCompareOps)->Option.getOr(Eq)
}

/** Generate random WHERE clause using parameterized values */
let whereClause = (rng: rng): string => {
  let field = fieldName(rng)
  let op = compareOp(rng)
  let value = valueType(rng)
  let safeValue = paramValueToGql(valueTypeToParam(value))
  `${field} ${compareOpToString(op)} ${safeValue}`
}

/** Generate random SELECT statement using parameterized construction */
let selectStatement = (rng: rng): string => {
  let collection = identifier(rng)
  let numFields = intInRange(rng, ~min=1, ~max=4)
  let fields = []
  for _ in 1 to numFields {
    fields->Array.push(fieldName(rng))->ignore
  }
  let fieldList = fields->Array.join(", ")

  let hasWhere = bool(rng)
  let hasLimit = bool(rng)

  let base = `SELECT ${fieldList} FROM ${collection}`
  let withWhere = hasWhere ? `${base} WHERE ${whereClause(rng)}` : base
  let withLimit = hasLimit
    ? `${withWhere} LIMIT ${Int.toString(intInRange(rng, ~min=1, ~max=100))}`
    : withWhere

  withLimit
}

/** Generate random INSERT statement using parameterized values */
let insertStatement = (rng: rng): string => {
  let collection = identifier(rng)
  let numFields = intInRange(rng, ~min=1, ~max=4)
  let pairs = []
  for _ in 1 to numFields {
    let field = fieldName(rng)
    let value = valueType(rng)
    let safeValue = paramValueToGql(valueTypeToParam(value))
    pairs->Array.push(`"${escapeStringValue(field)}": ${safeValue}`)->ignore
  }
  let document = "{" ++ pairs->Array.join(", ") ++ "}"
  `INSERT INTO ${collection} ${document}`
}

/** Generate random UPDATE statement using parameterized values */
let updateStatement = (rng: rng): string => {
  let collection = identifier(rng)
  let numFields = intInRange(rng, ~min=1, ~max=3)
  let pairs = []
  for _ in 1 to numFields {
    let field = fieldName(rng)
    let value = valueType(rng)
    let safeValue = paramValueToGql(valueTypeToParam(value))
    pairs->Array.push(`"${escapeStringValue(field)}": ${safeValue}`)->ignore
  }
  let setClause = "{" ++ pairs->Array.join(", ") ++ "}"
  `UPDATE ${collection} SET ${setClause} WHERE ${whereClause(rng)}`
}

/** Generate random DELETE statement with sanitized identifiers */
let deleteStatement = (rng: rng): string => {
  let collection = identifier(rng)
  `DELETE FROM ${collection} WHERE ${whereClause(rng)}`
}

/** Generate random CREATE statement with sanitized identifiers */
let createStatement = (rng: rng): string => {
  let collection = identifier(rng)
  let isEdge = bool(rng)
  let collType = isEdge ? "EDGE COLLECTION" : "COLLECTION"
  `CREATE ${collType} ${collection}`
}

/** Generate random DROP statement with sanitized identifiers */
let dropStatement = (rng: rng): string => {
  let collection = identifier(rng)
  `DROP COLLECTION ${collection}`
}

/** Generate random EXPLAIN statement (wraps a safe SELECT) */
let explainStatement = (rng: rng): string => {
  let inner = selectStatement(rng)
  let verbose = bool(rng)
  let analyze = bool(rng)

  let prefix = switch (analyze, verbose) {
  | (true, true) => "EXPLAIN ANALYZE VERBOSE"
  | (true, false) => "EXPLAIN ANALYZE"
  | (false, true) => "EXPLAIN VERBOSE"
  | (false, false) => "EXPLAIN"
  }

  `${prefix} ${inner}`
}

/** Generate random INTROSPECT statement with sanitized target */
let introspectStatement = (rng: rng): string => {
  let targets = ["SCHEMA", "CONSTRAINTS", "COLLECTIONS", "JOURNAL"]
  let target = pick(rng, targets)->Option.getOr("SCHEMA")

  switch target {
  | "SCHEMA" | "CONSTRAINTS" => {
      let collection = identifier(rng)
      `INTROSPECT ${target} ${collection}`
    }
  | _ => `INTROSPECT ${target}`
  }
}

/** Generate random GQL statement (all branches use safe construction) */
let gqlStatement = (rng: rng): string => {
  let stmtType = pick(rng, allStatementTypes)->Option.getOr(Select)
  switch stmtType {
  | Select => selectStatement(rng)
  | Insert => insertStatement(rng)
  | Update => updateStatement(rng)
  | Delete => deleteStatement(rng)
  | Create => createStatement(rng)
  | Drop => dropStatement(rng)
  | Explain => explainStatement(rng)
  | Introspect => introspectStatement(rng)
  }
}

/** Generate array of random statements */
let gqlStatements = (rng: rng, count: int): array<string> => {
  let result = []
  for _ in 1 to count {
    result->Array.push(gqlStatement(rng))->ignore
  }
  result
}
