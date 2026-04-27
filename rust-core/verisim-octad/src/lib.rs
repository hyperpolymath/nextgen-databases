// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Octad Entity
//!
//! One entity, eight synchronized representations (the octad).
//! The Octad is the fundamental unit of VeriSimDB — each entity exists
//! simultaneously across all eight modalities, maintaining cross-modal
//! consistency: Graph, Vector, Tensor, Semantic, Document, Temporal,
//! Provenance, and Spatial.

#![forbid(unsafe_code)]
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

// Re-export modality types — all eight modalities
pub use verisim_document::{Document, DocumentStore};
pub use verisim_graph::{GraphEdge, GraphNode, GraphObject, GraphStore};
pub use verisim_provenance::{
    InMemoryProvenanceStore, ProvenanceChain, ProvenanceError, ProvenanceEventType,
    ProvenanceRecord, ProvenanceStore,
};
pub use verisim_semantic::{ProofBlob, Provenance, SemanticAnnotation, SemanticStore, SemanticType, SemanticValue};
pub use verisim_spatial::{
    BoundingBox, Coordinates, GeometryType, InMemorySpatialStore, SpatialData,
    SpatialSearchResult, SpatialStore,
};
pub use verisim_tensor::{Tensor, TensorStore};
pub use verisim_temporal::{TemporalStore, TimeRange, Version};
pub use verisim_vector::{Embedding, VectorStore};

// In-memory store implementation
mod store;
pub use store::{OctadSnapshot, InMemoryOctadStore};

// Homoiconicity: queries as octads
pub mod query_octad;
pub use query_octad::{QueryOctadBuilder, QueryExecution};

// Optional RAM promotion for acceleration (disabled by default)
pub mod ram_promotion;
pub use ram_promotion::{PromotionManager, Modality, PromotionDecision, PromotionEvent};

// ACID transaction manager for cross-modality atomicity
pub mod transaction;
pub use transaction::{IsolationLevel, LockType, TransactionManager, TransactionError, TransactionState};

// WAL types (re-exported for external use)
pub use verisim_wal::{SyncMode, WalEntry, WalModality, WalOperation, WalWriter};

/// Octad errors
#[derive(Error, Debug)]
pub enum OctadError {
    #[error("Entity not found: {0}")]
    NotFound(String),

    #[error("Modality error in {modality}: {message}")]
    ModalityError { modality: String, message: String },

    #[error("Consistency violation: {0}")]
    ConsistencyViolation(String),

    #[error("Validation error: {0}")]
    ValidationError(String),
}

/// Unique identifier for a Octad entity
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct OctadId(pub String);

impl OctadId {
    /// Create a new Octad ID
    pub fn new(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    /// Generate a new UUID-based ID
    pub fn generate() -> Self {
        Self(uuid::Uuid::new_v4().to_string())
    }

    /// Get the ID as a string reference
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Convert to IRI for graph modality
    pub fn to_iri(&self, base: &str) -> String {
        format!("{}/{}", base.trim_end_matches('/'), self.0)
    }
}

impl std::fmt::Display for OctadId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for OctadId {
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl From<&str> for OctadId {
    fn from(s: &str) -> Self {
        Self(s.to_string())
    }
}

/// Status of a Octad entity across modalities
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadStatus {
    /// Entity ID
    pub id: OctadId,
    /// When the entity was created (ingestion time, set by the database)
    pub created_at: DateTime<Utc>,
    /// When last modified (ingestion time)
    pub modified_at: DateTime<Utc>,
    /// Caller-supplied real-world observation time, distinct from `created_at`.
    /// `created_at` records when the entity entered the database; `observed_at`
    /// records when the underlying event happened in the territory the entity
    /// represents (e.g. an email's `Date:` header). Optional because not every
    /// entity has a meaningful real-world timestamp.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub observed_at: Option<DateTime<Utc>>,
    /// Current version
    pub version: u64,
    /// Status per modality
    pub modality_status: ModalityStatus,
}

/// Status of each modality for an entity (octad: 8 modalities)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ModalityStatus {
    pub graph: bool,
    pub vector: bool,
    pub tensor: bool,
    pub semantic: bool,
    pub document: bool,
    pub temporal: bool,
    pub provenance: bool,
    pub spatial: bool,
}

impl ModalityStatus {
    /// Check if all eight modalities are populated
    pub fn is_complete(&self) -> bool {
        self.graph
            && self.vector
            && self.tensor
            && self.semantic
            && self.document
            && self.temporal
            && self.provenance
            && self.spatial
    }

    /// Get list of missing modalities
    pub fn missing(&self) -> Vec<&'static str> {
        let mut missing = Vec::new();
        if !self.graph { missing.push("graph"); }
        if !self.vector { missing.push("vector"); }
        if !self.tensor { missing.push("tensor"); }
        if !self.semantic { missing.push("semantic"); }
        if !self.document { missing.push("document"); }
        if !self.temporal { missing.push("temporal"); }
        if !self.provenance { missing.push("provenance"); }
        if !self.spatial { missing.push("spatial"); }
        missing
    }
}

/// Input data for creating/updating a Octad
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct OctadInput {
    /// Graph relationships (optional)
    pub graph: Option<OctadGraphInput>,
    /// Vector embedding (optional)
    pub vector: Option<OctadVectorInput>,
    /// Tensor data (optional)
    pub tensor: Option<OctadTensorInput>,
    /// Semantic annotations (optional)
    pub semantic: Option<OctadSemanticInput>,
    /// Document content (optional)
    pub document: Option<OctadDocumentInput>,
    /// Temporal observation time (optional). When supplied, `OctadStatus.observed_at`
    /// is populated. Distinct from the version snapshot (which the database always
    /// writes at ingestion time): this is the territory's clock, not the database's.
    pub temporal: Option<OctadTemporalInput>,
    /// Provenance event (optional)
    pub provenance: Option<OctadProvenanceInput>,
    /// Spatial coordinates (optional)
    pub spatial: Option<OctadSpatialInput>,
    /// Additional metadata
    pub metadata: HashMap<String, String>,
}


/// Graph modality input
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadGraphInput {
    /// Outgoing relationships
    pub relationships: Vec<(String, String)>, // (predicate, target_id)
}

/// Vector modality input
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadVectorInput {
    /// Embedding vector
    pub embedding: Vec<f32>,
    /// Embedding model used
    pub model: Option<String>,
}

/// Tensor modality input
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadTensorInput {
    /// Tensor shape
    pub shape: Vec<usize>,
    /// Tensor data
    pub data: Vec<f64>,
}

/// Semantic modality input
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadSemanticInput {
    /// Type IRIs
    pub types: Vec<String>,
    /// Properties
    pub properties: HashMap<String, String>,
}

/// Document modality input
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadDocumentInput {
    /// Document title
    pub title: String,
    /// Document body
    pub body: String,
    /// Additional fields
    pub fields: HashMap<String, String>,
}

/// Temporal modality input — the entity's real-world observation time
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadTemporalInput {
    /// When the underlying event happened in the territory the entity represents
    /// (e.g. an email's `Date:` header). UTC; callers must convert from local
    /// timezones before submission.
    pub observed_at: DateTime<Utc>,
}

/// Provenance modality input — records a lineage event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadProvenanceInput {
    /// Event type (created, modified, imported, normalized, etc.)
    pub event_type: String,
    /// Who or what caused this event
    pub actor: String,
    /// Optional source identifier (URL, upstream entity, file path)
    pub source: Option<String>,
    /// Human-readable description of the event
    pub description: String,
}

/// Spatial modality input — geospatial coordinates and geometry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadSpatialInput {
    /// Latitude in decimal degrees (WGS84)
    pub latitude: f64,
    /// Longitude in decimal degrees (WGS84)
    pub longitude: f64,
    /// Altitude in metres (optional)
    pub altitude: Option<f64>,
    /// Geometry type (Point, LineString, Polygon, etc.) — defaults to Point
    pub geometry_type: Option<String>,
    /// Spatial Reference System Identifier — defaults to 4326 (WGS84)
    pub srid: Option<u32>,
    /// Arbitrary spatial properties (address, region, accuracy, etc.)
    #[serde(default)]
    pub properties: HashMap<String, String>,
}

/// A complete Octad entity with all modality data (octad: 8 modalities)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Octad {
    /// Entity ID
    pub id: OctadId,
    /// Status
    pub status: OctadStatus,
    /// Graph node
    pub graph_node: Option<GraphNode>,
    /// Vector embedding
    pub embedding: Option<Embedding>,
    /// Tensor data
    pub tensor: Option<Tensor>,
    /// Semantic annotation
    pub semantic: Option<SemanticAnnotation>,
    /// Document
    pub document: Option<Document>,
    /// Version history info
    pub version_count: u64,
    /// Provenance chain length (number of recorded events)
    pub provenance_chain_length: u64,
    /// Spatial data (coordinates, geometry, SRID)
    pub spatial_data: Option<SpatialData>,
}

/// Octad store - manages entities across all modalities
#[async_trait]
pub trait OctadStore: Send + Sync {
    /// Create a new Octad entity
    async fn create(&self, input: OctadInput) -> Result<Octad, OctadError>;

    /// Update an existing Octad
    async fn update(&self, id: &OctadId, input: OctadInput) -> Result<Octad, OctadError>;

    /// Get a Octad by ID
    async fn get(&self, id: &OctadId) -> Result<Option<Octad>, OctadError>;

    /// Delete a Octad
    async fn delete(&self, id: &OctadId) -> Result<(), OctadError>;

    /// Get Octad status
    async fn status(&self, id: &OctadId) -> Result<Option<OctadStatus>, OctadError>;

    /// Search by vector similarity
    async fn search_similar(&self, embedding: &[f32], k: usize) -> Result<Vec<Octad>, OctadError>;

    /// Search by document text
    async fn search_text(&self, query: &str, limit: usize) -> Result<Vec<Octad>, OctadError>;

    /// Query by graph relationship
    async fn query_related(&self, id: &OctadId, predicate: &str) -> Result<Vec<Octad>, OctadError>;

    /// Get version at a specific point in time
    async fn at_time(&self, id: &OctadId, time: DateTime<Utc>) -> Result<Option<Octad>, OctadError>;

    /// List octads with pagination
    async fn list(&self, limit: usize, offset: usize) -> Result<Vec<Octad>, OctadError>;
}

/// Configuration for Octad store
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OctadConfig {
    /// Base IRI for graph nodes
    pub base_iri: String,
    /// Vector embedding dimension
    pub vector_dimension: usize,
    /// Whether to enforce full modality population
    pub require_complete: bool,
}

impl Default for OctadConfig {
    fn default() -> Self {
        Self {
            base_iri: "https://verisim.db/entity".to_string(),
            vector_dimension: 384,
            require_complete: false,
        }
    }
}

/// Builder for creating Octad inputs
pub struct OctadBuilder {
    input: OctadInput,
}

impl OctadBuilder {
    /// Create a new builder
    pub fn new() -> Self {
        Self {
            input: OctadInput::default(),
        }
    }

    /// Add graph relationships
    pub fn with_relationships(mut self, relationships: Vec<(&str, &str)>) -> Self {
        self.input.graph = Some(OctadGraphInput {
            relationships: relationships
                .into_iter()
                .map(|(p, t)| (p.to_string(), t.to_string()))
                .collect(),
        });
        self
    }

    /// Add vector embedding
    pub fn with_embedding(mut self, embedding: Vec<f32>) -> Self {
        self.input.vector = Some(OctadVectorInput {
            embedding,
            model: None,
        });
        self
    }

    /// Add tensor data
    pub fn with_tensor(mut self, shape: Vec<usize>, data: Vec<f64>) -> Self {
        self.input.tensor = Some(OctadTensorInput { shape, data });
        self
    }

    /// Add semantic types
    pub fn with_types(mut self, types: Vec<&str>) -> Self {
        let existing = self.input.semantic.take().unwrap_or(OctadSemanticInput {
            types: Vec::new(),
            properties: HashMap::new(),
        });
        self.input.semantic = Some(OctadSemanticInput {
            types: types.into_iter().map(|t| t.to_string()).collect(),
            properties: existing.properties,
        });
        self
    }

    /// Add document content
    pub fn with_document(mut self, title: &str, body: &str) -> Self {
        self.input.document = Some(OctadDocumentInput {
            title: title.to_string(),
            body: body.to_string(),
            fields: HashMap::new(),
        });
        self
    }

    /// Add provenance event
    pub fn with_provenance(mut self, event_type: &str, actor: &str, description: &str) -> Self {
        self.input.provenance = Some(OctadProvenanceInput {
            event_type: event_type.to_string(),
            actor: actor.to_string(),
            source: None,
            description: description.to_string(),
        });
        self
    }

    /// Add spatial coordinates (WGS84 point)
    pub fn with_spatial(mut self, latitude: f64, longitude: f64) -> Self {
        self.input.spatial = Some(OctadSpatialInput {
            latitude,
            longitude,
            altitude: None,
            geometry_type: None,
            srid: None,
            properties: HashMap::new(),
        });
        self
    }

    /// Add real-world observation time (territory clock, not database ingestion time)
    pub fn with_observed_at(mut self, observed_at: DateTime<Utc>) -> Self {
        self.input.temporal = Some(OctadTemporalInput { observed_at });
        self
    }

    /// Add metadata
    pub fn with_metadata(mut self, key: &str, value: &str) -> Self {
        self.input.metadata.insert(key.to_string(), value.to_string());
        self
    }

    /// Build the input
    pub fn build(self) -> OctadInput {
        self.input
    }
}

impl Default for OctadBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_octad_id() {
        let id = OctadId::new("test-123");
        assert_eq!(id.as_str(), "test-123");
        assert_eq!(id.to_iri("https://example.org"), "https://example.org/test-123");
    }

    #[test]
    fn test_octad_builder() {
        let input = OctadBuilder::new()
            .with_document("Test", "Test content")
            .with_embedding(vec![0.1, 0.2, 0.3])
            .with_types(vec!["https://example.org/Person"])
            .with_metadata("source", "test")
            .build();

        assert!(input.document.is_some());
        assert!(input.vector.is_some());
        assert!(input.semantic.is_some());
        assert_eq!(input.metadata.get("source"), Some(&"test".to_string()));
    }

    #[test]
    fn test_modality_status() {
        let mut status = ModalityStatus::default();
        assert!(!status.is_complete());
        assert_eq!(status.missing().len(), 8);

        status.graph = true;
        status.vector = true;
        status.tensor = true;
        status.semantic = true;
        status.document = true;
        status.temporal = true;
        status.provenance = true;
        status.spatial = true;

        assert!(status.is_complete());
        assert!(status.missing().is_empty());
    }
}
