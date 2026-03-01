// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// TQLAst.res — Extended AST types for VQL-dt++ (TypeQL-experimental)
//
// Defines the AST nodes for the six new extension clauses that augment
// standard VQL queries. These types mirror the Idris2 kernel types but
// in a form suitable for parser output.

// ============================================================================
// VQL Base Types (adapted from VeriSimDB VQLParser.res)
// ============================================================================

// VQL modalities — the octad (8 modalities).
type modality =
  | Graph
  | Vector
  | Tensor
  | Semantic
  | Document
  | Temporal
  | Provenance
  | Spatial
  | All

// Data source for a query.
type source =
  | Hexad(string)
  | Federation(string, option<driftPolicy>)
  | Store(string)
  | Reflect

and driftPolicy =
  | Strict
  | Repair
  | Tolerate
  | Latest

// Comparison operators.
type operator =
  | Eq
  | Neq
  | Gt
  | Lt
  | Gte
  | Lte
  | Like
  | Contains
  | Matches

// Literal values.
type rec literal =
  | String(string)
  | Int(int)
  | Float(float)
  | Bool(bool)
  | Array(array<literal>)

// Field reference: MODALITY.field_name
type fieldRef = {
  modality: modality,
  field: string,
}

// Aggregate functions.
type aggregateFunc =
  | Count
  | Sum
  | Avg
  | Min
  | Max

// Aggregate expressions.
type aggregateExpr =
  | CountAll
  | AggregateField(aggregateFunc, fieldRef)

// Sort direction.
type sortDirection =
  | Asc
  | Desc

// ORDER BY item.
type orderByItem = {
  field: fieldRef,
  direction: sortDirection,
}

// Conditions (simplified for extension parsing).
type condition =
  | Simple(simpleCondition)
  | And(condition, condition)
  | Or(condition, condition)
  | Not(condition)

and simpleCondition =
  | FulltextContains(string)
  | FulltextMatches(string)
  | FieldCondition(string, operator, literal)

// Proof types from VQL PROOF clause.
type proofType =
  | Existence
  | Citation
  | Access
  | Integrity
  | ProvenanceProof
  | Custom

// Proof specification.
type proofSpec = {
  proofType: proofType,
  contractName: string,
  customParams: option<array<(string, string)>>,
}

// ============================================================================
// Extension 1: Linear Types — CONSUME AFTER N USE
// ============================================================================

// Specifies how many times a connection/resource can be used before
// it must be released. Maps to Idris2 QTT quantity annotations.
type usageSpec = {
  count: int, // Must be positive (>= 1)
}

// ============================================================================
// Extension 2: Session Types — WITH SESSION protocol
// ============================================================================

// Named session protocol that constrains the allowed state transitions.
type sessionProtocol =
  | ReadOnlyProtocol
  | MutationProtocol
  | StreamProtocol
  | BatchProtocol
  | CustomProtocol(string)

// ============================================================================
// Extension 3: Effect Systems — EFFECTS { Read, Write, ... }
// ============================================================================

// Individual effect labels.
type effectLabel =
  | ReadEffect
  | WriteEffect
  | CiteEffect
  | AuditEffect
  | TransformEffect
  | FederateEffect
  | CustomEffect(string)

// Declared effect set for a query.
type effectDecl = {
  effects: array<effectLabel>,
}

// ============================================================================
// Extension 4: Modal Types — IN TRANSACTION state
// ============================================================================

// Transaction scope states.
type transactionState =
  | TxFresh
  | TxActive
  | TxCommitted
  | TxRolledBack
  | TxReadSnapshot
  | TxCustom(string)

// Modal scoping declaration.
type modalDecl = {
  state: transactionState,
}

// ============================================================================
// Extension 5: Proof-Carrying Code — PROOF ATTACHED theorem
// ============================================================================

// A theorem to attach to query results.
type theoremRef = {
  name: string,
  params: option<array<(string, string)>>,
}

// ============================================================================
// Extension 6: Quantitative Type Theory — USAGE LIMIT n
// ============================================================================

// Resource budget for the entire query plan.
type usageLimit = {
  limit: int, // Must be positive (>= 1)
}

// ============================================================================
// Extension Annotations (all optional)
// ============================================================================

// Collected extension annotations from a VQL-dt++ query.
// Each field is None if the corresponding clause was not present.
type extensionAnnotations = {
  consumeAfter: option<usageSpec>,
  sessionProtocol: option<sessionProtocol>,
  declaredEffects: option<effectDecl>,
  modalScope: option<modalDecl>,
  proofAttached: option<theoremRef>,
  usageLimit: option<usageLimit>,
}

// Construct empty annotations (no extension clauses).
let emptyAnnotations: extensionAnnotations = {
  consumeAfter: None,
  sessionProtocol: None,
  declaredEffects: None,
  modalScope: None,
  proofAttached: None,
  usageLimit: None,
}

// ============================================================================
// Extended Query AST
// ============================================================================

// A standard VQL query (base, before extensions).
type baseQuery = {
  modalities: array<modality>,
  projections: option<array<fieldRef>>,
  aggregates: option<array<aggregateExpr>>,
  source: source,
  where: option<condition>,
  groupBy: option<array<fieldRef>>,
  having: option<condition>,
  proof: option<array<proofSpec>>,
  orderBy: option<array<orderByItem>>,
  limit: option<int>,
  offset: option<int>,
}

// A VQL-dt++ extended query = base VQL query + extension annotations.
type extendedQuery = {
  base: baseQuery,
  extensions: extensionAnnotations,
}

// ============================================================================
// String Representations (for debugging and error messages)
// ============================================================================

let showModality = (m: modality): string => {
  switch m {
  | Graph => "GRAPH"
  | Vector => "VECTOR"
  | Tensor => "TENSOR"
  | Semantic => "SEMANTIC"
  | Document => "DOCUMENT"
  | Temporal => "TEMPORAL"
  | Provenance => "PROVENANCE"
  | Spatial => "SPATIAL"
  | All => "*"
  }
}

let showSessionProtocol = (p: sessionProtocol): string => {
  switch p {
  | ReadOnlyProtocol => "ReadOnlyProtocol"
  | MutationProtocol => "MutationProtocol"
  | StreamProtocol => "StreamProtocol"
  | BatchProtocol => "BatchProtocol"
  | CustomProtocol(name) => name
  }
}

let showEffectLabel = (e: effectLabel): string => {
  switch e {
  | ReadEffect => "Read"
  | WriteEffect => "Write"
  | CiteEffect => "Cite"
  | AuditEffect => "Audit"
  | TransformEffect => "Transform"
  | FederateEffect => "Federate"
  | CustomEffect(name) => name
  }
}

let showTransactionState = (s: transactionState): string => {
  switch s {
  | TxFresh => "Fresh"
  | TxActive => "Active"
  | TxCommitted => "Committed"
  | TxRolledBack => "RolledBack"
  | TxReadSnapshot => "ReadSnapshot"
  | TxCustom(name) => name
  }
}

let showProofType = (pt: proofType): string => {
  switch pt {
  | Existence => "EXISTENCE"
  | Citation => "CITATION"
  | Access => "ACCESS"
  | Integrity => "INTEGRITY"
  | ProvenanceProof => "PROVENANCE"
  | Custom => "CUSTOM"
  }
}
