// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith ReScript Client - Type Definitions

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

/** Query result */
type queryResult = {
  rows: array<row>,
  rowCount: int,
  journalSeq: int,
  provenance?: provenance,
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
  provenance?: provenance,
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

/** Confidence level for discovered dependencies */
type confidenceLevel =
  | @as("HIGH") High
  | @as("MEDIUM") Medium
  | @as("LOW") Low

/** Functional dependency */
type functionalDependency = {
  determinant: array<string>,
  dependent: string,
  confidence: confidenceLevel,
  sampleSize: int,
}

/** Normal form analysis result */
type normalFormAnalysis = {
  currentForm: normalForm,
  targetForm: normalForm,
  violations: array<string>,
  recommendations: array<string>,
}

// =============================================================================
// Migration Types
// =============================================================================

/** Migration phase */
type migrationPhase =
  | @as("ANNOUNCE") Announce
  | @as("SHADOW") Shadow
  | @as("COMMIT") Commit
  | @as("ROLLBACK") Rollback

/** Migration status */
type migrationStatus = {
  id: string,
  phase: migrationPhase,
  collection: string,
  startedAt: string,
  narrative: string,
}

// =============================================================================
// Request/Response Types
// =============================================================================

/** Query request */
type queryRequest = {
  fdql: string,
  provenance?: provenance,
  explain?: bool,
}

/** Create collection request */
type createCollectionRequest = {
  name: string,
  @as("type") collectionType: collectionType,
  schema?: JSON.t,
}

/** Health status */
type healthStatus =
  | @as("HEALTHY") Healthy
  | @as("DEGRADED") Degraded
  | @as("UNHEALTHY") Unhealthy

/** Health response */
type healthResponse = {
  status: healthStatus,
  version: string,
  uptimeSeconds: int,
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

/** Client configuration */
type config = {
  baseUrl: string,
  auth?: authMethod,
  timeout?: int,
  retries?: int,
}
