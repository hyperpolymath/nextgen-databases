// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Core type definitions.
//
// This module defines all data structures exchanged between the ReScript client
// SDK and the VeriSimDB server. Types are defined as ReScript records and
// variants, designed for direct JSON serialization via the JSON module.
//
// The central entity is the Hexad — a six-faceted data object unifying graph,
// vector, tensor, semantic, document, temporal, provenance, and spatial modalities.

// --------------------------------------------------------------------------
// Fetch API response type (used by VeriSimClient)
// --------------------------------------------------------------------------

/** Minimal representation of the Fetch API Response object. */
type fetchResponse = {
  ok: bool,
  status: int,
  statusText: string,
}

// --------------------------------------------------------------------------
// Modality
// --------------------------------------------------------------------------

/** The eight data modalities supported by VeriSimDB hexads. */
type modality =
  | Graph
  | Vector
  | Tensor
  | Semantic
  | Document
  | Temporal
  | Provenance
  | Spatial

/** Convert a modality variant to its JSON string representation. */
let modalityToString = (m: modality): string => {
  switch m {
  | Graph => "graph"
  | Vector => "vector"
  | Tensor => "tensor"
  | Semantic => "semantic"
  | Document => "document"
  | Temporal => "temporal"
  | Provenance => "provenance"
  | Spatial => "spatial"
  }
}

/** Parse a modality from its JSON string representation. */
let modalityFromString = (s: string): option<modality> => {
  switch s {
  | "graph" => Some(Graph)
  | "vector" => Some(Vector)
  | "tensor" => Some(Tensor)
  | "semantic" => Some(Semantic)
  | "document" => Some(Document)
  | "temporal" => Some(Temporal)
  | "provenance" => Some(Provenance)
  | "spatial" => Some(Spatial)
  | _ => None
  }
}

// --------------------------------------------------------------------------
// Modality status
// --------------------------------------------------------------------------

/** Which modalities are active on a given hexad. */
type modalityStatus = {
  graph: bool,
  vector: bool,
  tensor: bool,
  semantic: bool,
  document: bool,
  temporal: bool,
  provenance: bool,
  spatial: bool,
}

// --------------------------------------------------------------------------
// Hexad status
// --------------------------------------------------------------------------

/** The lifecycle state of a hexad. */
type hexadStatus =
  | Active
  | Archived
  | Draft
  | Deleted

// --------------------------------------------------------------------------
// Graph modality data
// --------------------------------------------------------------------------

/** A directed edge between two hexads in the graph modality. */
type graphEdge = {
  source: string,
  target: string,
  relType: string,
  weight: float,
  metadata: Dict.t<string>,
}

/** Graph-modality data for a hexad: edges and node properties. */
type graphData = {
  edges: array<graphEdge>,
  properties: Dict.t<string>,
}

// --------------------------------------------------------------------------
// Vector modality data
// --------------------------------------------------------------------------

/** Embedding vector data for vector-modality operations. */
type vectorData = {
  embedding: array<float>,
  model: string,
  dimensions: int,
}

// --------------------------------------------------------------------------
// Tensor modality data
// --------------------------------------------------------------------------

/** Multi-dimensional tensor data reference. */
type tensorData = {
  shape: array<int>,
  dtype: string,
  dataRef: string,
}

// --------------------------------------------------------------------------
// Document modality data
// --------------------------------------------------------------------------

/** Document-modality content: text, format, and language metadata. */
type documentContent = {
  text: string,
  format: string,
  language: string,
  metadata: Dict.t<string>,
}

// --------------------------------------------------------------------------
// Spatial modality data
// --------------------------------------------------------------------------

/** Spatial-modality coordinates and geometry. */
type spatialData = {
  latitude: float,
  longitude: float,
  altitude: option<float>,
  geometry: option<string>,
  crs: string,
}

// --------------------------------------------------------------------------
// Hexad (core entity)
// --------------------------------------------------------------------------

/** The core entity in VeriSimDB — a multi-modal data object. */
type hexad = {
  id: string,
  status: hexadStatus,
  modalities: modalityStatus,
  createdAt: string,
  updatedAt: string,
  metadata: Dict.t<string>,
  graphData: option<graphData>,
  vectorData: option<vectorData>,
  tensorData: option<tensorData>,
  content: option<documentContent>,
  spatialData: option<spatialData>,
}

// --------------------------------------------------------------------------
// Hexad input (for create/update)
// --------------------------------------------------------------------------

/** Input structure for creating or updating a hexad. */
type hexadInput = {
  graphData: option<graphData>,
  vectorData: option<vectorData>,
  tensorData: option<tensorData>,
  content: option<documentContent>,
  spatialData: option<spatialData>,
  metadata: Dict.t<string>,
  modalities: array<modality>,
}

// --------------------------------------------------------------------------
// Drift types
// --------------------------------------------------------------------------

/** Drift score measurement for a hexad. Score ranges from 0.0 to 1.0. */
type driftScore = {
  hexadId: string,
  score: float,
  components: Dict.t<float>,
  measuredAt: string,
  baselineAt: string,
}

/** Drift level classification. */
type driftLevel =
  | Stable
  | Low
  | Moderate
  | High
  | Critical

/** Drift status report with classification and score. */
type driftStatusReport = {
  hexadId: string,
  level: driftLevel,
  score: driftScore,
  message: string,
}

// --------------------------------------------------------------------------
// Provenance types
// --------------------------------------------------------------------------

/** A single event in a hexad's provenance chain. */
type provenanceEvent = {
  eventId: string,
  hexadId: string,
  eventType: string,
  actor: string,
  timestamp: string,
  details: Dict.t<string>,
  parentId: option<string>,
}

/** The complete provenance chain for a hexad. */
type provenanceChain = {
  hexadId: string,
  events: array<provenanceEvent>,
  verified: bool,
}

/** Input for recording a new provenance event. */
type provenanceEventInput = {
  eventType: string,
  actor: string,
  details: Dict.t<string>,
}

// --------------------------------------------------------------------------
// Pagination
// --------------------------------------------------------------------------

/** Paginated response wrapping a list of hexads. */
type paginatedResponse = {
  items: array<hexad>,
  total: int,
  page: int,
  perPage: int,
  totalPages: int,
}

// --------------------------------------------------------------------------
// Search types
// --------------------------------------------------------------------------

/** A search result pairing a hexad with a relevance score. */
type searchResult = {
  hexad: hexad,
  score: float,
}

// --------------------------------------------------------------------------
// VQL types
// --------------------------------------------------------------------------

/** Result of a VQL query execution. */
type vqlResult = {
  columns: array<string>,
  rows: array<array<string>>,
  count: int,
  elapsedMs: float,
}

/** Query execution plan explanation for a VQL statement. */
type vqlExplanation = {
  query: string,
  plan: string,
  cost: float,
  warnings: array<string>,
}

// --------------------------------------------------------------------------
// Federation types
// --------------------------------------------------------------------------

/** A remote VeriSimDB node in a federated cluster. */
type federationPeer = {
  peerId: string,
  name: string,
  url: string,
  status: string,
  lastSeen: string,
  metadata: Dict.t<string>,
}

/** Result from a single peer in a federated query. */
type peerQueryResult = {
  peerId: string,
  peerName: string,
  result: vqlResult,
  elapsedMs: float,
  error: option<string>,
}

/** Aggregated result from a federated query across multiple peers. */
type federatedQueryResult = {
  results: array<peerQueryResult>,
  total: int,
  elapsedMs: float,
}
