// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

/// VeriSimDbCmd -- Backend command dispatch for the VeriSimDB Admin panel.
///
/// Each function wraps a Gossamer IPC call to the VeriSimDB backend. Commands
/// target either the Rust core API (default port 8080) or the Elixir
/// orchestration layer (default port 4080). All commands require a valid
/// network capability token obtained from the Gossamer runtime via
/// `Capabilities.requestNetworkAccess()`.
///
/// The commands map to VeriSimDB's REST API:
///   Rust core (port 8080, prefix /api/v1):
///     - Health:       GET  /health
///     - VCL:          POST /vcl/execute
///     - Octads:       GET  /octads, GET /octads/{id}, POST /octads, DELETE /octads/{id}
///     - Drift:        GET  /drift/entity/{id}
///     - Normaliser:   POST /normalizer/trigger/{id}
///
///   Elixir orchestration (port 4080):
///     - Telemetry:    GET  /telemetry
///     - Orch status:  GET  /status
///
/// Gossamer acts as the network proxy -- the webview never makes direct
/// HTTP calls. Instead, each command goes through IPC to the Gossamer
/// Zig runtime, which holds the network capability and forwards the
/// request to the VeriSimDB backend.

/// Base URL for the VeriSimDB Rust core API.
/// In production this comes from server config; defaults to local dev port.
let _rustBaseUrl = "http://localhost:8080/api/v1"

/// Base URL for the VeriSimDB Elixir orchestration layer.
/// Runs on a separate port from the Rust core.
let _elixirBaseUrl = "http://localhost:4080"

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

/// Check the VeriSimDB Rust core health endpoint.
///
/// Maps to: GET /health
/// Returns the server's health status including uptime and version.
let checkHealth = (token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_check_health",
    {"url": `${_rustBaseUrl}/health`},
    token,
  )
}

// ---------------------------------------------------------------------------
// VCL Console
// ---------------------------------------------------------------------------

/// Execute a VCL (VeriSim Query Language) query against the database.
///
/// Maps to: POST /vcl/execute
/// VCL supports octad queries across all 8 modalities with proof
/// generation and drift-aware consistency.
///
/// @param query - The VCL query string to execute
let queryVcl = (query: string, token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_query_vcl",
    {"url": `${_rustBaseUrl}/vcl/execute`, "query": query},
    token,
  )
}

// ---------------------------------------------------------------------------
// Octad management
// ---------------------------------------------------------------------------

/// List octad entities with pagination.
///
/// Maps to: GET /octads?limit=N&offset=M
/// Returns a JSON array of octad entity summaries (ID, title, modality
/// status flags, drift score).
///
/// @param limit  - Maximum number of entities to return
/// @param offset - Offset for pagination
let listOctads = (limit: int, offset: int, token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_list_octads",
    {"url": `${_rustBaseUrl}/octads?limit=${Int.toString(limit)}&offset=${Int.toString(offset)}`},
    token,
  )
}

/// Get a single octad entity with full detail across all 8 modalities.
///
/// Maps to: GET /octads/{id}
/// Returns the complete octad snapshot: graph triples, vector embedding,
/// tensor data, semantic annotations, document content, temporal versions,
/// provenance chain, and spatial coordinates.
///
/// @param id - The octad entity UUID
let getEntity = (id: string, token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_get_entity",
    {"url": `${_rustBaseUrl}/octads/${id}`},
    token,
  )
}

/// Create a new octad entity.
///
/// Maps to: POST /octads
/// Creates an entity with the provided modality data. At minimum,
/// a document title is required. Other modalities are populated
/// automatically or can be provided explicitly.
///
/// @param entityJson - JSON string with octad input fields
let createOctad = (entityJson: string, token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_create_octad",
    {"url": `${_rustBaseUrl}/octads`, "body": entityJson},
    token,
  )
}

/// Delete an octad entity.
///
/// Maps to: DELETE /octads/{id}
/// Removes the entity and all its modality data. This is irreversible
/// (unless temporal versioning provides recovery).
///
/// @param id - The octad entity UUID to delete
let deleteOctad = (id: string, token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_delete_octad",
    {"url": `${_rustBaseUrl}/octads/${id}`, "method": "DELETE"},
    token,
  )
}

// ---------------------------------------------------------------------------
// Drift detection
// ---------------------------------------------------------------------------

/// Get the drift status for a specific entity.
///
/// Maps to: GET /drift/entity/{id}
/// Returns per-modality drift scores: semantic_vector_drift,
/// graph_document_drift, temporal_consistency_drift, tensor_drift,
/// schema_drift, quality_drift.
///
/// @param id - The octad entity UUID
let getDrift = (id: string, token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_get_drift",
    {"url": `${_rustBaseUrl}/drift/entity/${id}`},
    token,
  )
}

/// Trigger normalisation for a drifted entity.
///
/// Maps to: POST /normalizer/trigger/{id}
/// The normaliser identifies the most authoritative modality,
/// regenerates drifted modalities from it, validates consistency,
/// and updates all modalities atomically.
///
/// @param id - The octad entity UUID to normalise
let triggerNormalise = (id: string, token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_trigger_normalise",
    {"url": `${_rustBaseUrl}/normalizer/trigger/${id}`, "method": "POST"},
    token,
  )
}

// ---------------------------------------------------------------------------
// Telemetry (Elixir orchestration layer)
// ---------------------------------------------------------------------------

/// Get aggregate telemetry from the Elixir orchestration layer.
///
/// Maps to: GET /telemetry (port 4080)
/// Returns opt-in aggregate metrics: modality heatmap, query patterns,
/// drift reports, performance summary, federation health. No PII.
let getTelemetry = (token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_get_telemetry",
    {"url": `${_elixirBaseUrl}/telemetry`},
    token,
  )
}

// ---------------------------------------------------------------------------
// Orchestration status (Elixir layer)
// ---------------------------------------------------------------------------

/// Get the orchestration layer status.
///
/// Maps to: GET /status (port 4080)
/// Returns consensus state, federation adapter count, and telemetry
/// enabled flag from the Elixir OTP supervision tree.
let getOrchStatus = (token: float): promise<string> => {
  RuntimeBridge.invokeWithToken(
    "verisimdb_get_orch_status",
    {"url": `${_elixirBaseUrl}/status`},
    token,
  )
}
