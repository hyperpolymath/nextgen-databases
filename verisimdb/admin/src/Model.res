// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

/// Model -- Application state for the VeriSimDB Admin panel.
///
/// Holds the complete UI state including server connection status, octad
/// entity listings, VCL console state, drift detection results, telemetry
/// metrics, and Gossamer capability tokens.
///
/// VeriSimDB's octad model: each entity exists simultaneously across 8
/// modalities (Graph, Vector, Tensor, Semantic, Document, Temporal,
/// Provenance, Spatial). The admin panel provides visibility into all
/// modalities and their drift status.

/// Connection status to the VeriSimDB backend (Rust core + Elixir layer).
type serverStatus =
  | /// Successfully connected to the VeriSimDB Rust core.
    Connected
  | /// No connection -- server unreachable or not started.
    Disconnected
  | /// Connection attempt in progress.
    Connecting

/// Summary of an octad entity for the sidebar list.
/// Contains just enough information for browsing; full detail is loaded
/// on selection via `getEntity`.
type octadSummary = {
  /// Unique octad entity identifier (UUID).
  id: string,
  /// Human-readable title (from the Document modality).
  title: string,
  /// Number of active modalities (out of 8).
  activeModalities: int,
  /// Overall drift score (0.0 = no drift, 1.0 = maximum drift).
  driftScore: float,
}

/// Drift information for a specific entity.
/// Each field represents the divergence between two modalities.
type driftInfo = {
  /// ID of the entity this drift info belongs to.
  entityId: string,
  /// Embedding-to-semantic content divergence.
  semanticVectorDrift: float,
  /// Graph structure vs document content divergence.
  graphDocumentDrift: float,
  /// Version history consistency issues.
  temporalConsistencyDrift: float,
  /// Tensor representation divergence.
  tensorDrift: float,
  /// Type constraint violations.
  schemaDrift: float,
  /// Overall data quality metric.
  qualityDrift: float,
}

/// Telemetry aggregate from the Elixir orchestration layer.
type telemetryData = {
  /// Raw JSON string of the full telemetry report.
  raw: string,
  /// Whether telemetry collection is enabled on the server.
  enabled: bool,
}

/// Capability token status for Gossamer security.
/// Each capability must be explicitly granted by the runtime before use.
type capabilityStatus =
  | /// Not yet requested from the runtime.
    NotRequested
  | /// Request sent, awaiting runtime grant.
    Pending
  | /// Granted with a token. The float is the token value.
    Granted(float)
  | /// Runtime denied the capability request.
    Denied

/// The active tab in the entity detail view, selecting which modality
/// to display prominently.
type detailTab =
  | /// Show all modalities in a summary grid.
    Overview
  | /// Graph triples and property graph edges.
    Graph
  | /// Vector embedding visualisation.
    Vector
  | /// Tensor multi-dimensional representation.
    Tensor
  | /// Semantic type annotations and proof blobs.
    Semantic
  | /// Full-text searchable content.
    Document
  | /// Version history and time-series.
    Temporal
  | /// Origin tracking and transformation chain.
    Provenance
  | /// Geospatial coordinates and geometries.
    Spatial

/// Complete application state.
type model = {
  /// Current server connection status.
  status: serverStatus,
  /// Paginated list of octad entity summaries for the sidebar.
  octads: array<octadSummary>,
  /// Total octad count (for pagination display).
  octadTotal: int,
  /// Current pagination offset.
  octadOffset: int,
  /// Page size for octad listing.
  octadLimit: int,
  /// Currently selected entity ID for detail view.
  selectedEntity: option<string>,
  /// Full JSON detail of the selected entity (all 8 modalities).
  entityDetail: option<string>,
  /// Active tab in the entity detail view.
  detailTab: detailTab,
  /// VCL console: current input text.
  vclInput: string,
  /// VCL console: result of the last executed query.
  vclResult: option<string>,
  /// VCL console: whether a query is currently executing.
  vclExecuting: bool,
  /// Drift status for the currently selected entity.
  driftStatus: option<driftInfo>,
  /// Aggregate telemetry data from the Elixir layer.
  telemetry: option<telemetryData>,
  /// Orchestration layer status (raw JSON).
  orchStatus: option<string>,
  /// Network capability token -- required for ALL API calls.
  networkCap: capabilityStatus,
  /// Filesystem capability token -- required for exports.
  filesystemCap: capabilityStatus,
  /// Clipboard capability token -- required for VCL copying.
  clipboardCap: capabilityStatus,
  /// Error message to display in the UI, if any.
  error: option<string>,
  /// Whether the capability grant panel is visible.
  showCapPanel: bool,
}

/// Initial application state. Starts with no capabilities granted,
/// forcing the user to explicitly authorise network, filesystem, and
/// clipboard access through the Gossamer capability token system.
let initial: model = {
  status: Disconnected,
  octads: [],
  octadTotal: 0,
  octadOffset: 0,
  octadLimit: 50,
  selectedEntity: None,
  entityDetail: None,
  detailTab: Overview,
  vclInput: "",
  vclResult: None,
  vclExecuting: false,
  driftStatus: None,
  telemetry: None,
  orchStatus: None,
  networkCap: NotRequested,
  filesystemCap: NotRequested,
  clipboardCap: NotRequested,
  error: None,
  showCapPanel: true,
}
