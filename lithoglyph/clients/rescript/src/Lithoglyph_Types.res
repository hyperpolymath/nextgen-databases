// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>
//
// Lithoglyph ReScript Client - Type Definitions
// Stone-carved data for the ages: narrative-first, reversible, audit-grade database
//
// Compatible with Deno runtime (not Node/npm)

// =============================================================================
// Core Types
// =============================================================================

/** Provenance metadata for audit trail */
type provenance = {
  actor: string,
  rationale: string,
  timestamp?: string,
  source?: string,
}

/** Query result row */
type row = Dict.t<JSON.t>

/** Timing information for query execution */
type timing = {
  parseMs: float,
  planMs: float,
  executeMs: float,
  totalMs: float,
}

/** Query result from FDQL execution */
type queryResult = {
  rows: array<row>,
  rowCount: int,
  journalSeq: int,
  provenance?: provenance,
  timing?: timing,
}

/** Collection type */
type collectionType =
  | @as("DOCUMENT") Document
  | @as("EDGE") Edge
  | @as("SCHEMA") Schema

/** Collection metadata */
type collection = {
  name: string,
  @as("type") collectionType: collectionType,
  documentCount: int,
  normalForm?: string,
  schema?: JSON.t,
}

/** Journal operation type */
type journalOperation =
  | @as("INSERT") Insert
  | @as("UPDATE") Update
  | @as("DELETE") Delete
  | @as("CREATE_COLLECTION") CreateCollection
  | @as("DROP_COLLECTION") DropCollection
  | @as("MIGRATION_START") MigrationStart
  | @as("MIGRATION_COMMIT") MigrationCommit

/** Journal entry */
type journalEntry = {
  seq: int,
  timestamp: string,
  operation: journalOperation,
  collection?: string,
  documentId?: string,
  before?: JSON.t,
  after?: JSON.t,
  provenance?: provenance,
  inverse?: string,
}

/** Journal response with pagination */
type journalResponse = {
  entries: array<journalEntry>,
  hasMore: bool,
  nextSeq?: int,
}

// =============================================================================
// Normalization Types
// =============================================================================

/** Normal form level */
type normalForm =
  | @as("1NF") NF1
  | @as("2NF") NF2
  | @as("3NF") NF3
  | @as("BCNF") BCNF

/** Confidence tier for discovered dependencies */
type confidenceTier =
  | @as("HIGH") High
  | @as("MEDIUM") Medium
  | @as("LOW") Low

/** Functional dependency */
type functionalDependency = {
  determinant: array<string>,
  dependent: string,
  confidence: float,
  tier: confidenceTier,
}

/** Discover result with FDs and candidate keys */
type discoverResult = {
  collection: string,
  functionalDependencies: array<functionalDependency>,
  candidateKeys: array<array<string>>,
}

/** Violation type */
type violationType =
  | @as("PARTIAL_DEPENDENCY") PartialDependency
  | @as("TRANSITIVE_DEPENDENCY") TransitiveDependency
  | @as("BCNF_VIOLATION") BcnfViolation

/** Schema violation */
type violation = {
  @as("type") violationType: violationType,
  description: string,
  affectedFields: array<string>,
}

/** Recommendation action */
type recommendationAction =
  | @as("DECOMPOSE") Decompose
  | @as("ADD_CONSTRAINT") AddConstraint
  | @as("DENORMALIZE") Denormalize

/** Schema recommendation */
type recommendation = {
  action: recommendationAction,
  description: string,
  targetForm?: normalForm,
  migrationSteps: array<string>,
}

/** Normal form analysis result */
type analyzeResult = {
  collection: string,
  currentForm: normalForm,
  violations: array<violation>,
  recommendations: array<recommendation>,
}

// =============================================================================
// Migration Types
// =============================================================================

/** Migration phase */
type migrationPhase =
  | @as("ANNOUNCE") Announce
  | @as("SHADOW") Shadow
  | @as("COMMIT") Commit
  | @as("COMPLETE") Complete
  | @as("ABORTED") Aborted
  | @as("ROLLBACK") Rollback

/** Migration status */
type migrationStatus = {
  id: string,
  collection: string,
  phase: migrationPhase,
  startedAt: string,
  narrative: string,
}

/** Migration progress (for WebSocket subscription) */
type migrationProgress = {
  migrationId: string,
  phase: migrationPhase,
  progress: float,
  message: string,
}

// =============================================================================
// EXPLAIN Types
// =============================================================================

/** Plan step type */
type stepType =
  | @as("SCAN") Scan
  | @as("FILTER") Filter
  | @as("PROJECT") Project
  | @as("LIMIT") Limit
  | @as("TRAVERSE") Traverse
  | @as("INSERT") StepInsert
  | @as("UPDATE") StepUpdate
  | @as("DELETE") StepDelete

/** Query plan step */
type planStep = {
  @as("type") stepType: stepType,
  collection?: string,
  expression?: string,
  count?: int,
  details?: JSON.t,
}

/** Query plan */
type queryPlan = {
  steps: array<planStep>,
  estimatedCost: float,
  rationale?: string,
}

/** EXPLAIN result */
type explainResult = {
  plan: queryPlan,
  timing?: timing,
  verboseOutput?: string,
}

// =============================================================================
// Health Types
// =============================================================================

/** Health status */
type healthStatus =
  | @as("HEALTHY") Healthy
  | @as("DEGRADED") Degraded
  | @as("UNHEALTHY") Unhealthy

/** Check status */
type checkStatus =
  | @as("PASS") Pass
  | @as("FAIL") Fail

/** Health check */
type healthCheck = {
  name: string,
  status: checkStatus,
}

/** Health response */
type healthResponse = {
  status: healthStatus,
  version: string,
  uptimeSeconds: int,
  checks?: array<healthCheck>,
}

// =============================================================================
// Error Types
// =============================================================================

/** API error */
type apiError = {
  code: string,
  message: string,
  details?: JSON.t,
}

/** Result type for API calls */
type result<'a> = Result.t<'a, apiError>

// =============================================================================
// Client Configuration
// =============================================================================

/** Authentication method */
type authMethod =
  | NoAuth
  | ApiKey(string)
  | Bearer(string)

/** Protocol to use when communicating with the server */
type protocol =
  | REST
  | GraphQL

/** Client configuration */
type config = {
  baseUrl: string,
  auth?: authMethod,
  timeout?: int,
  retries?: int,
  protocol?: protocol,
}

// =============================================================================
// GraphQL Types
// =============================================================================

/** GraphQL request */
type graphqlRequest = {
  query: string,
  operationName?: string,
  variables?: JSON.t,
}

/** GraphQL error */
type graphqlError = {
  message: string,
  locations?: array<{line: int, column: int}>,
  path?: array<string>,
}

/** GraphQL response */
type graphqlResponse = {
  data?: JSON.t,
  errors?: array<graphqlError>,
}

// =============================================================================
// WebSocket / Subscription Types
// =============================================================================

/** Subscription type for real-time streaming */
type subscriptionType =
  | JournalStream
  | QueryStream
  | MigrationProgressStream

/** Subscription message from the server */
type subscriptionMessage<'a> = {
  @as("type") msgType: string,
  id?: string,
  payload?: 'a,
}
