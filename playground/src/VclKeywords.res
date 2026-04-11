// SPDX-License-Identifier: PMPL-1.0-or-later
// VCL keyword definitions shared across syntax highlighting, completion, and linting.
// Updated for the octad architecture (8 modalities) and 11 proof types.

let keywords = [
  "SELECT", "FROM", "WHERE", "PROOF", "LIMIT", "OFFSET", "ORDER", "BY",
  "GROUP", "HAVING", "AS", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE",
  "EXISTS", "CONTAINS", "SIMILAR", "TO", "TRAVERSE", "DEPTH", "THRESHOLD",
  "DRIFT", "CONSISTENCY", "AT", "TIME", "EXPLAIN", "INSERT", "UPDATE",
  "DELETE", "SET", "INTO", "VALUES", "CREATE", "DROP", "ALTER", "JOIN",
  "ON", "WITH", "FEDERATION", "STORE", "HEXAD", "ALL", "ASC", "DESC",
  "COUNT", "SUM", "AVG", "MIN", "MAX", "DISTINCT", "ANALYZE",
  "SHOW", "STATUS", "SEARCH", "TEXT", "RELATED", "WITHIN", "RADIUS",
  "BOUNDS", "NEAREST", "REFLECT",
]

/// Octad modalities — 8 stores that form the core of each entity.
let modalities = [
  "GRAPH", "VECTOR", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL",
  "PROVENANCE", "SPATIAL",
]

/// All 11 proof types supported by the VCL-DT type checker.
let proofTypes = [
  "EXISTENCE", "CONSISTENCY", "INTEGRITY", "PROVENANCE",
  "FRESHNESS", "ACCESS", "CITATION", "CUSTOM",
  "ZKP", "PROVEN", "SANCTIFY",
]

/// VCL-DT specific keywords (only active in VCL-DT mode).
let vclDtKeywords = [
  "PROOF", "THRESHOLD", "VERIFY", "CERTIFY", "ATTEST",
  "WITNESS", "CIRCUIT", "COMMITMENT",
]

let isKeyword = word => keywords->Array.includes(String.toUpperCase(word))
let isModality = word => modalities->Array.includes(String.toUpperCase(word))
let isProofType = word => proofTypes->Array.includes(String.toUpperCase(word))
