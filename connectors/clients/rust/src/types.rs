// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Core data types for the VeriSimDB client SDK.
//!
//! These types mirror the VeriSimDB JSON Schema and cover the full octad of
//! modalities: Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance,
//! and Spatial. Every struct derives `Serialize` and `Deserialize` so it can be
//! round-tripped through the REST API transparently.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Modality enum
// ---------------------------------------------------------------------------

/// The eight modalities supported by VeriSimDB's octad data model.
///
/// Each hexad entity can participate in any combination of these modalities,
/// enabling truly multi-modal storage and querying.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Modality {
    /// Graph relationships (nodes, edges, properties).
    Graph,
    /// Dense vector embeddings for similarity search.
    Vector,
    /// Multi-dimensional tensor data (ML feature stores, etc.).
    Tensor,
    /// Semantic triples and ontology-backed knowledge.
    Semantic,
    /// Unstructured or semi-structured document content.
    Document,
    /// Time-series and temporal event data.
    Temporal,
    /// Immutable provenance / lineage chains.
    Provenance,
    /// Geospatial coordinates, regions, and geometries.
    Spatial,
}

// ---------------------------------------------------------------------------
// ModalityStatus
// ---------------------------------------------------------------------------

/// Boolean flags indicating which modalities are currently active for a hexad.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ModalityStatus {
    /// Whether graph data is present.
    pub graph: bool,
    /// Whether vector embeddings are present.
    pub vector: bool,
    /// Whether tensor data is present.
    pub tensor: bool,
    /// Whether semantic triples are present.
    pub semantic: bool,
    /// Whether document content is present.
    pub document: bool,
    /// Whether temporal events are present.
    pub temporal: bool,
    /// Whether provenance records are present.
    pub provenance: bool,
    /// Whether spatial geometry is present.
    pub spatial: bool,
}

// ---------------------------------------------------------------------------
// HexadStatus
// ---------------------------------------------------------------------------

/// Lightweight status summary for a hexad entity, returned by list/search
/// endpoints that do not need full payloads.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadStatus {
    /// Unique identifier.
    pub id: String,
    /// Creation timestamp.
    pub created_at: DateTime<Utc>,
    /// Last modification timestamp.
    pub modified_at: DateTime<Utc>,
    /// Optimistic concurrency version counter.
    pub version: u64,
    /// Per-modality activation flags.
    pub modality_status: ModalityStatus,
}

// ---------------------------------------------------------------------------
// Hexad (full entity)
// ---------------------------------------------------------------------------

/// A complete hexad entity encompassing all eight modality payloads.
///
/// This is the primary read model returned by `get_hexad` and single-entity
/// search results.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hexad {
    /// Unique identifier (UUID v4).
    pub id: String,
    /// Human-readable label.
    pub name: String,
    /// Optional free-text description.
    pub description: Option<String>,
    /// Creation timestamp.
    pub created_at: DateTime<Utc>,
    /// Last modification timestamp.
    pub modified_at: DateTime<Utc>,
    /// Optimistic concurrency version counter.
    pub version: u64,
    /// Per-modality activation flags.
    pub modality_status: ModalityStatus,
    /// Arbitrary user-defined metadata.
    pub metadata: Option<serde_json::Value>,
    /// Graph modality payload.
    pub graph: Option<serde_json::Value>,
    /// Vector modality payload.
    pub vector: Option<serde_json::Value>,
    /// Tensor modality payload.
    pub tensor: Option<serde_json::Value>,
    /// Semantic modality payload.
    pub semantic: Option<serde_json::Value>,
    /// Document modality payload.
    pub document: Option<serde_json::Value>,
    /// Temporal modality payload.
    pub temporal: Option<serde_json::Value>,
    /// Provenance modality payload.
    pub provenance: Option<serde_json::Value>,
    /// Spatial modality payload.
    pub spatial: Option<serde_json::Value>,
}

// ---------------------------------------------------------------------------
// HexadInput (create / update payload)
// ---------------------------------------------------------------------------

/// Input payload for creating or updating a hexad entity.
///
/// All fields are optional so that partial updates are possible. The server
/// merges the provided fields into the existing entity on update.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HexadInput {
    /// Human-readable label.
    pub name: Option<String>,
    /// Free-text description.
    pub description: Option<String>,
    /// Arbitrary user-defined metadata.
    pub metadata: Option<serde_json::Value>,
    /// Graph modality input.
    pub graph: Option<HexadGraphInput>,
    /// Vector modality input.
    pub vector: Option<HexadVectorInput>,
    /// Tensor modality input.
    pub tensor: Option<HexadTensorInput>,
    /// Semantic modality input.
    pub semantic: Option<HexadSemanticInput>,
    /// Document modality input.
    pub document: Option<HexadDocumentInput>,
    /// Temporal modality input.
    pub temporal: Option<HexadTemporalInput>,
    /// Provenance modality input.
    pub provenance: Option<HexadProvenanceInput>,
    /// Spatial modality input.
    pub spatial: Option<HexadSpatialInput>,
}

// ---------------------------------------------------------------------------
// Per-modality input structs
// ---------------------------------------------------------------------------

/// Graph modality input: nodes, edges, and properties.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadGraphInput {
    /// List of node identifiers to associate with this hexad.
    pub nodes: Option<Vec<String>>,
    /// List of edges, each a (source, target, label) triple.
    pub edges: Option<Vec<GraphEdge>>,
    /// Arbitrary graph-level properties.
    pub properties: Option<serde_json::Value>,
}

/// A single directed edge in the graph modality.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphEdge {
    /// Source node identifier.
    pub source: String,
    /// Target node identifier.
    pub target: String,
    /// Edge label / relationship type.
    pub label: String,
    /// Optional edge-level properties.
    pub properties: Option<serde_json::Value>,
}

/// Vector modality input: dense embeddings for similarity search.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadVectorInput {
    /// The embedding vector (list of f32 values).
    pub embedding: Vec<f32>,
    /// Dimensionality (inferred from `embedding.len()` if omitted).
    pub dimensions: Option<usize>,
    /// The model or algorithm that produced this embedding.
    pub model: Option<String>,
}

/// Tensor modality input: multi-dimensional numeric data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadTensorInput {
    /// Flattened tensor data.
    pub data: Vec<f64>,
    /// Shape of the tensor (e.g. `[3, 224, 224]`).
    pub shape: Vec<usize>,
    /// Data type label (e.g. "float32", "int64").
    pub dtype: Option<String>,
}

/// Semantic modality input: RDF-style triples and ontology references.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadSemanticInput {
    /// Semantic triples (subject, predicate, object).
    pub triples: Option<Vec<SemanticTriple>>,
    /// Ontology URI this entity conforms to.
    pub ontology: Option<String>,
    /// Free-form semantic annotations.
    pub annotations: Option<serde_json::Value>,
}

/// A single semantic triple.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SemanticTriple {
    /// Subject URI or identifier.
    pub subject: String,
    /// Predicate URI or identifier.
    pub predicate: String,
    /// Object URI, identifier, or literal value.
    pub object: String,
}

/// Document modality input: unstructured / semi-structured content.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadDocumentInput {
    /// The document body (plain text, HTML, Markdown, etc.).
    pub content: String,
    /// MIME type of the content (e.g. "text/plain", "application/json").
    pub content_type: Option<String>,
    /// Language code (e.g. "en", "fr").
    pub language: Option<String>,
    /// Document-level metadata (author, tags, etc.).
    pub metadata: Option<serde_json::Value>,
}

/// Provenance modality input: lineage and audit trail events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadProvenanceInput {
    /// The type of provenance event (e.g. "creation", "transformation", "derivation").
    pub event_type: String,
    /// The agent (user, service, pipeline) that triggered the event.
    pub agent: String,
    /// Human-readable description of what happened.
    pub description: Option<String>,
    /// References to source entities this was derived from.
    pub source_ids: Option<Vec<String>>,
    /// Arbitrary event-level metadata.
    pub metadata: Option<serde_json::Value>,
}

/// Spatial modality input: geospatial coordinates and geometries.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadSpatialInput {
    /// Latitude in decimal degrees (WGS 84).
    pub latitude: Option<f64>,
    /// Longitude in decimal degrees (WGS 84).
    pub longitude: Option<f64>,
    /// Altitude in metres above mean sea level.
    pub altitude: Option<f64>,
    /// GeoJSON geometry object for complex shapes.
    pub geometry: Option<serde_json::Value>,
    /// Coordinate reference system identifier (default: "EPSG:4326").
    pub crs: Option<String>,
}

/// Temporal modality input: time-series events and temporal metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadTemporalInput {
    /// The timestamp of the event.
    pub timestamp: DateTime<Utc>,
    /// Duration in milliseconds (for interval events).
    pub duration_ms: Option<u64>,
    /// Recurrence rule (iCal RRULE format).
    pub recurrence: Option<String>,
    /// Timezone identifier (e.g. "Europe/London").
    pub timezone: Option<String>,
    /// Arbitrary temporal metadata.
    pub metadata: Option<serde_json::Value>,
}

// ---------------------------------------------------------------------------
// DriftScore
// ---------------------------------------------------------------------------

/// Drift score for a hexad entity, measuring how far its modality data has
/// diverged from its normalised baseline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriftScore {
    /// The hexad entity identifier.
    pub entity_id: String,
    /// Aggregate drift score across all active modalities (0.0 = no drift).
    pub overall_score: f64,
    /// Per-modality drift scores keyed by modality name.
    pub modality_scores: HashMap<String, f64>,
    /// When the drift was last computed.
    pub last_checked: DateTime<Utc>,
    /// Whether the entity should be re-normalised.
    pub needs_normalization: bool,
}

// ---------------------------------------------------------------------------
// ProvenanceEvent
// ---------------------------------------------------------------------------

/// A single immutable event in a hexad's provenance chain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProvenanceEvent {
    /// Unique event identifier.
    pub id: Option<String>,
    /// The hexad entity this event belongs to.
    pub entity_id: String,
    /// Event type (e.g. "creation", "transformation", "derivation").
    pub event_type: String,
    /// The agent that triggered the event.
    pub agent: String,
    /// Human-readable description.
    pub description: Option<String>,
    /// When the event occurred.
    pub timestamp: Option<DateTime<Utc>>,
    /// References to predecessor events or source entities.
    pub source_ids: Option<Vec<String>>,
    /// Arbitrary event metadata.
    pub metadata: Option<serde_json::Value>,
}

// ---------------------------------------------------------------------------
// FederationResult
// ---------------------------------------------------------------------------

/// A single result from a federated cross-instance query.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationResult {
    /// The peer store that produced this result.
    pub store_id: String,
    /// The matched hexad entity.
    pub entity: Hexad,
    /// Relevance or similarity score (interpretation depends on query type).
    pub score: Option<f64>,
    /// Latency in milliseconds for this peer's response.
    pub latency_ms: Option<u64>,
}

// ---------------------------------------------------------------------------
// ErrorResponse
// ---------------------------------------------------------------------------

/// Standard error response body from the VeriSimDB REST API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    /// Machine-readable error code.
    pub error: String,
    /// Human-readable error message.
    pub message: String,
    /// Optional details (validation errors, stack traces in debug mode, etc.).
    pub details: Option<serde_json::Value>,
}

// ---------------------------------------------------------------------------
// PaginatedResponse<T>
// ---------------------------------------------------------------------------

/// Generic wrapper for paginated list responses.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginatedResponse<T> {
    /// The result items for the current page.
    pub data: Vec<T>,
    /// Total number of matching items across all pages.
    pub total: usize,
    /// Number of items per page.
    pub limit: usize,
    /// Zero-based offset of the current page.
    pub offset: usize,
    /// Whether more pages are available after this one.
    pub has_more: bool,
}
