// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Core type definitions.
//
// This module defines the data structures exchanged between the V client SDK and
// the VeriSimDB server. All types are designed to match the VeriSimDB JSON Schema
// and can be serialized/deserialized via V's built-in json module.
//
// The central entity in VeriSimDB is the Hexad — a six-faceted data object that
// unifies graph, vector, tensor, semantic, document, temporal, provenance, and
// spatial modalities. Each hexad tracks its own drift score (a measure of how
// much its embeddings or relationships have diverged over time) and maintains
// a full provenance chain.

module verisimdb_client

// Modality enumerates the eight data modalities supported by VeriSimDB hexads.
// A single hexad can participate in multiple modalities simultaneously.
pub enum Modality {
	graph
	vector
	tensor
	semantic
	document
	temporal
	provenance
	spatial
}

// modality_to_string converts a Modality enum value to its JSON string representation.
pub fn modality_to_string(m Modality) string {
	return match m {
		.graph { 'graph' }
		.vector { 'vector' }
		.tensor { 'tensor' }
		.semantic { 'semantic' }
		.document { 'document' }
		.temporal { 'temporal' }
		.provenance { 'provenance' }
		.spatial { 'spatial' }
	}
}

// ModalityStatus indicates which modalities are active on a given hexad.
pub struct ModalityStatus {
pub mut:
	graph      bool
	vector     bool
	tensor     bool
	semantic   bool
	document   bool
	temporal   bool
	provenance bool
	spatial    bool
}

// HexadStatus represents the lifecycle state of a hexad.
pub enum HexadStatus {
	active
	archived
	draft
	deleted
}

// Hexad is the core entity in VeriSimDB — a six-faceted data object that unifies
// multiple modalities (graph, vector, tensor, semantic, document, temporal,
// provenance, spatial) into a single addressable record.
pub struct Hexad {
pub:
	id           string
	status       HexadStatus
	modalities   ModalityStatus
	created_at   string // ISO 8601 timestamp
	updated_at   string // ISO 8601 timestamp
	metadata     map[string]string
pub mut:
	graph_data   ?GraphData
	vector_data  ?VectorData
	tensor_data  ?TensorData
	content      ?DocumentContent
	spatial_data ?SpatialData
}

// GraphData holds graph-modality information for a hexad, including
// edges (relationships) and node properties.
pub struct GraphData {
pub mut:
	edges      []GraphEdge
	properties map[string]string
}

// GraphEdge represents a directed relationship between two hexads.
pub struct GraphEdge {
pub:
	source    string
	target    string
	rel_type  string
	weight    f64
	metadata  map[string]string
}

// VectorData holds the embedding vector for vector-modality operations
// such as similarity search and nearest-neighbour queries.
pub struct VectorData {
pub:
	embedding  []f64
	model      string // name of embedding model used
	dimensions int
}

// TensorData holds multi-dimensional tensor data for tensor-modality operations.
pub struct TensorData {
pub:
	shape    []int
	dtype    string // e.g. "float32", "float64", "int32"
	data_ref string // reference URI to tensor storage
}

// DocumentContent holds document-modality content: raw text, structured fields,
// and optional format metadata.
pub struct DocumentContent {
pub:
	text     string
	format   string // e.g. "plain", "markdown", "html"
	language string // ISO 639-1 language code
	metadata map[string]string
}

// SpatialData holds spatial-modality coordinates and geometry information.
pub struct SpatialData {
pub:
	latitude  f64
	longitude f64
	altitude  ?f64
	geometry  ?string // GeoJSON geometry string
	crs       string  // coordinate reference system, e.g. "EPSG:4326"
}

// HexadInput is the input structure for creating or updating a hexad.
// Optional fields are represented as V optionals.
pub struct HexadInput {
pub:
	graph_data   ?GraphData
	vector_data  ?VectorData
	tensor_data  ?TensorData
	content      ?DocumentContent
	spatial_data ?SpatialData
	metadata     map[string]string
	modalities   []Modality
}

// DriftScore represents the drift measurement for a hexad.
// Drift quantifies how much a hexad's embeddings or relationships have
// diverged from their original or reference state over time.
pub struct DriftScore {
pub:
	hexad_id     string
	score        f64   // 0.0 (no drift) to 1.0 (maximum drift)
	components   map[string]f64
	measured_at  string // ISO 8601
	baseline_at  string // ISO 8601
}

// DriftStatus describes the current drift classification for a hexad.
pub enum DriftLevel {
	stable
	low
	moderate
	high
	critical
}

// DriftStatusReport bundles a drift score with its classification level.
pub struct DriftStatusReport {
pub:
	hexad_id string
	level    DriftLevel
	score    DriftScore
	message  string
}

// ProvenanceEvent represents a single event in a hexad's provenance chain.
// The provenance chain provides an immutable audit trail of all mutations
// applied to a hexad over its lifetime.
pub struct ProvenanceEvent {
pub:
	event_id   string
	hexad_id   string
	event_type string // e.g. "created", "updated", "merged", "split"
	actor      string
	timestamp  string // ISO 8601
	details    map[string]string
	parent_id  ?string // previous event in the chain
}

// ProvenanceChain is the complete provenance history for a hexad.
pub struct ProvenanceChain {
pub:
	hexad_id string
	events   []ProvenanceEvent
	verified bool
}

// PaginatedResponse wraps a list of hexads with pagination metadata.
pub struct PaginatedResponse {
pub:
	items       []Hexad
	total       int
	page        int
	per_page    int
	total_pages int
}

// SearchResult wraps a hexad with a relevance score from a search query.
pub struct SearchResult {
pub:
	hexad Hexad
	score f64
}

// VqlResult holds the result of a VQL (VeriSimDB Query Language) execution.
pub struct VqlResult {
pub:
	columns []string
	rows    [][]string
	count   int
	elapsed_ms f64
}

// VqlExplanation provides the query plan for a VQL statement.
pub struct VqlExplanation {
pub:
	query    string
	plan     string
	cost     f64
	warnings []string
}

// FederationPeer represents a remote VeriSimDB node in a federated cluster.
pub struct FederationPeer {
pub:
	peer_id   string
	name      string
	url       string
	status    string // "active", "inactive", "syncing"
	last_seen string // ISO 8601
	metadata  map[string]string
}
