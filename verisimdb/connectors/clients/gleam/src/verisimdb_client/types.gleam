//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Core type definitions.
////
//// This module defines all data structures exchanged between the Gleam client
//// SDK and the VeriSimDB server. Types are defined as Gleam custom types,
//// designed for use with gleam_json for serialization/deserialization.
////
//// The central entity is the Octad — a six-faceted data object unifying graph,
//// vector, tensor, semantic, document, temporal, provenance, and spatial modalities.

import gleam/dict.{type Dict}
import gleam/option.{type Option}

// ---------------------------------------------------------------------------
// Modality
// ---------------------------------------------------------------------------

/// The eight data modalities supported by VeriSimDB octads.
/// A single octad can participate in multiple modalities simultaneously.
pub type Modality {
  Graph
  Vector
  Tensor
  Semantic
  Document
  Temporal
  Provenance
  Spatial
}

/// Convert a modality to its JSON string representation.
pub fn modality_to_string(modality: Modality) -> String {
  case modality {
    Graph -> "graph"
    Vector -> "vector"
    Tensor -> "tensor"
    Semantic -> "semantic"
    Document -> "document"
    Temporal -> "temporal"
    Provenance -> "provenance"
    Spatial -> "spatial"
  }
}

/// Parse a modality from its JSON string representation.
pub fn modality_from_string(s: String) -> Option(Modality) {
  case s {
    "graph" -> option.Some(Graph)
    "vector" -> option.Some(Vector)
    "tensor" -> option.Some(Tensor)
    "semantic" -> option.Some(Semantic)
    "document" -> option.Some(Document)
    "temporal" -> option.Some(Temporal)
    "provenance" -> option.Some(Provenance)
    "spatial" -> option.Some(Spatial)
    _ -> option.None
  }
}

// ---------------------------------------------------------------------------
// Modality status
// ---------------------------------------------------------------------------

/// Which modalities are active on a given octad.
pub type ModalityStatus {
  ModalityStatus(
    graph: Bool,
    vector: Bool,
    tensor: Bool,
    semantic: Bool,
    document: Bool,
    temporal: Bool,
    provenance: Bool,
    spatial: Bool,
  )
}

/// Default modality status with all modalities disabled.
pub fn default_modality_status() -> ModalityStatus {
  ModalityStatus(
    graph: False,
    vector: False,
    tensor: False,
    semantic: False,
    document: False,
    temporal: False,
    provenance: False,
    spatial: False,
  )
}

// ---------------------------------------------------------------------------
// Octad status
// ---------------------------------------------------------------------------

/// Lifecycle state of a octad.
pub type OctadStatus {
  Active
  Archived
  Draft
  Deleted
}

// ---------------------------------------------------------------------------
// Graph modality data
// ---------------------------------------------------------------------------

/// A directed edge between two octads in the graph modality.
pub type GraphEdge {
  GraphEdge(
    source: String,
    target: String,
    rel_type: String,
    weight: Float,
    metadata: Dict(String, String),
  )
}

/// Graph-modality data: edges and node properties.
pub type GraphData {
  GraphData(edges: List(GraphEdge), properties: Dict(String, String))
}

// ---------------------------------------------------------------------------
// Vector modality data
// ---------------------------------------------------------------------------

/// Embedding vector for vector-modality operations.
pub type VectorData {
  VectorData(embedding: List(Float), model: String, dimensions: Int)
}

// ---------------------------------------------------------------------------
// Tensor modality data
// ---------------------------------------------------------------------------

/// Multi-dimensional tensor data reference.
pub type TensorData {
  TensorData(shape: List(Int), dtype: String, data_ref: String)
}

// ---------------------------------------------------------------------------
// Document modality data
// ---------------------------------------------------------------------------

/// Document-modality content: text, format, and language metadata.
pub type DocumentContent {
  DocumentContent(
    text: String,
    format: String,
    language: String,
    metadata: Dict(String, String),
  )
}

// ---------------------------------------------------------------------------
// Spatial modality data
// ---------------------------------------------------------------------------

/// Spatial-modality coordinates and geometry.
pub type SpatialData {
  SpatialData(
    latitude: Float,
    longitude: Float,
    altitude: Option(Float),
    geometry: Option(String),
    crs: String,
  )
}

// ---------------------------------------------------------------------------
// Octad (core entity)
// ---------------------------------------------------------------------------

/// The core entity in VeriSimDB — a multi-modal data object.
pub type Octad {
  Octad(
    id: String,
    status: OctadStatus,
    modalities: ModalityStatus,
    created_at: String,
    updated_at: String,
    metadata: Dict(String, String),
    graph_data: Option(GraphData),
    vector_data: Option(VectorData),
    tensor_data: Option(TensorData),
    content: Option(DocumentContent),
    spatial_data: Option(SpatialData),
  )
}

// ---------------------------------------------------------------------------
// Octad input (for create/update)
// ---------------------------------------------------------------------------

/// Input structure for creating or updating a octad.
pub type OctadInput {
  OctadInput(
    graph_data: Option(GraphData),
    vector_data: Option(VectorData),
    tensor_data: Option(TensorData),
    content: Option(DocumentContent),
    spatial_data: Option(SpatialData),
    metadata: Dict(String, String),
    modalities: List(Modality),
  )
}

// ---------------------------------------------------------------------------
// Drift types
// ---------------------------------------------------------------------------

/// Drift score measurement. Score ranges from 0.0 (no drift) to 1.0 (maximum).
pub type DriftScore {
  DriftScore(
    octad_id: String,
    score: Float,
    components: Dict(String, Float),
    measured_at: String,
    baseline_at: String,
  )
}

/// Drift level classification.
pub type DriftLevel {
  DriftStable
  DriftLow
  DriftModerate
  DriftHigh
  DriftCritical
}

/// Drift status report with classification and score.
pub type DriftStatusReport {
  DriftStatusReport(
    octad_id: String,
    level: DriftLevel,
    score: DriftScore,
    message: String,
  )
}

// ---------------------------------------------------------------------------
// Provenance types
// ---------------------------------------------------------------------------

/// A single event in a octad's provenance chain.
pub type ProvenanceEvent {
  ProvenanceEvent(
    event_id: String,
    octad_id: String,
    event_type: String,
    actor: String,
    timestamp: String,
    details: Dict(String, String),
    parent_id: Option(String),
  )
}

/// Complete provenance chain for a octad.
pub type ProvenanceChain {
  ProvenanceChain(
    octad_id: String,
    events: List(ProvenanceEvent),
    verified: Bool,
  )
}

/// Input for recording a new provenance event.
pub type ProvenanceEventInput {
  ProvenanceEventInput(
    event_type: String,
    actor: String,
    details: Dict(String, String),
  )
}

// ---------------------------------------------------------------------------
// Pagination
// ---------------------------------------------------------------------------

/// Paginated response wrapping a list of octads.
pub type PaginatedResponse {
  PaginatedResponse(
    items: List(Octad),
    total: Int,
    page: Int,
    per_page: Int,
    total_pages: Int,
  )
}

// ---------------------------------------------------------------------------
// Search types
// ---------------------------------------------------------------------------

/// A search result pairing a octad with a relevance score.
pub type SearchResult {
  SearchResult(octad: Octad, score: Float)
}

// ---------------------------------------------------------------------------
// VQL types
// ---------------------------------------------------------------------------

/// Result of a VQL query execution.
pub type VqlResult {
  VqlResult(
    columns: List(String),
    rows: List(List(String)),
    count: Int,
    elapsed_ms: Float,
  )
}

/// Query execution plan for a VQL statement.
pub type VqlExplanation {
  VqlExplanation(
    query: String,
    plan: String,
    cost: Float,
    warnings: List(String),
  )
}

// ---------------------------------------------------------------------------
// Federation types
// ---------------------------------------------------------------------------

/// A remote VeriSimDB node in a federated cluster.
pub type FederationPeer {
  FederationPeer(
    peer_id: String,
    name: String,
    url: String,
    status: String,
    last_seen: String,
    metadata: Dict(String, String),
  )
}

/// Result from a single peer in a federated query.
pub type PeerQueryResult {
  PeerQueryResult(
    peer_id: String,
    peer_name: String,
    result: VqlResult,
    elapsed_ms: Float,
    error: Option(String),
  )
}

/// Aggregated result from a federated query.
pub type FederatedQueryResult {
  FederatedQueryResult(
    results: List(PeerQueryResult),
    total: Int,
    elapsed_ms: Float,
  )
}
