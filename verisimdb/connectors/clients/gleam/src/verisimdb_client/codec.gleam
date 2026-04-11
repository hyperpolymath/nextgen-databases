//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — JSON codec module.
////
//// Centralised JSON encoding and decoding for all VeriSimDB types.
//// Uses gleam/json for encoding and gleam/dynamic/decode for type-safe
//// deserialization of API responses. Every modality's data is fully
//// serialized and deserialized — no stubs.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{
  type DriftLevel, type DriftScore, type DriftStatusReport,
  type DocumentContent, type FederatedQueryResult, type FederationPeer,
  type GraphData, type GraphEdge, type Modality, type ModalityStatus, type Octad,
  type OctadInput, type OctadStatus, type PaginatedResponse,
  type PeerQueryResult, type ProvenanceChain, type ProvenanceEvent,
  type SearchResult, type SpatialData, type TensorData, type VectorData,
  type VclExplanation, type VclResult,
}

// ==========================================================================
// Shared helpers
// ==========================================================================

/// Encode a Dict(String, String) as a JSON object of string values.
pub fn encode_string_dict(d: Dict(String, String)) -> json.Json {
  json.object(
    d
    |> dict.to_list
    |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
  )
}

/// Encode a Dict(String, Float) as a JSON object of float values.
fn encode_float_dict(d: Dict(String, Float)) -> json.Json {
  json.object(
    d
    |> dict.to_list
    |> list.map(fn(pair) { #(pair.0, json.float(pair.1)) }),
  )
}

/// Encode an optional value: produces json.null() when None.
fn encode_optional(
  opt: Option(a),
  encoder: fn(a) -> json.Json,
) -> json.Json {
  case opt {
    Some(val) -> encoder(val)
    None -> json.null()
  }
}

/// Decode a JSON string body using a decoder, wrapping errors as SerializationError.
fn parse_json(
  body: String,
  decoder: decode.Decoder(a),
) -> Result(a, VeriSimError) {
  case json.parse(body, decoder) {
    Ok(value) -> Ok(value)
    Error(err) ->
      Error(error.SerializationError(
        "JSON decode error: " <> decode_error_to_string(err),
      ))
  }
}

/// Convert a decode error to a human-readable string.
fn decode_error_to_string(err: json.DecodeError) -> String {
  case err {
    json.UnexpectedFormat(_decode_errors) -> "unexpected JSON format"
    json.UnexpectedEndOfInput -> "unexpected end of JSON input"
    json.UnexpectedByte(byte) -> "unexpected byte: " <> byte
    json.UnexpectedSequence(seq) -> "unexpected sequence: " <> seq
  }
}

/// Decoder for a Dict(String, String) from a JSON object.
fn string_dict_decoder() -> decode.Decoder(Dict(String, String)) {
  decode.dict(decode.string, decode.string)
}

/// Decoder for a Dict(String, Float) from a JSON object.
fn float_dict_decoder() -> decode.Decoder(Dict(String, Float)) {
  decode.dict(decode.string, decode.float)
}

/// Decoder for an optional field that may be null or absent.
fn optional_field(
  name: String,
  inner: decode.Decoder(a),
) -> decode.Decoder(Option(a)) {
  decode.optional_field(name, None, decode.optional(inner))
}

// ==========================================================================
// Modality encoding/decoding
// ==========================================================================

/// Encode a Modality to its JSON string.
fn encode_modality(modality: Modality) -> json.Json {
  json.string(types.modality_to_string(modality))
}

/// Decoder for a Modality from a JSON string.
fn modality_decoder() -> decode.Decoder(Modality) {
  decode.string
  |> decode.then(fn(s) {
    case types.modality_from_string(s) {
      Some(m) -> decode.success(m)
      None -> decode.failure(types.Graph, "Modality")
    }
  })
}

// ==========================================================================
// OctadStatus encoding/decoding
// ==========================================================================

/// Encode an OctadStatus to its JSON string representation.
fn encode_octad_status(status: OctadStatus) -> json.Json {
  json.string(case status {
    types.Active -> "active"
    types.Archived -> "archived"
    types.Draft -> "draft"
    types.Deleted -> "deleted"
  })
}

/// Decoder for an OctadStatus from a JSON string.
fn octad_status_decoder() -> decode.Decoder(OctadStatus) {
  decode.string
  |> decode.then(fn(s) {
    case s {
      "active" -> decode.success(types.Active)
      "archived" -> decode.success(types.Archived)
      "draft" -> decode.success(types.Draft)
      "deleted" -> decode.success(types.Deleted)
      _ -> decode.failure(types.Active, "OctadStatus")
    }
  })
}

// ==========================================================================
// ModalityStatus encoding/decoding
// ==========================================================================

/// Encode a ModalityStatus as a JSON object with boolean fields.
fn encode_modality_status(ms: ModalityStatus) -> json.Json {
  json.object([
    #("graph", json.bool(ms.graph)),
    #("vector", json.bool(ms.vector)),
    #("tensor", json.bool(ms.tensor)),
    #("semantic", json.bool(ms.semantic)),
    #("document", json.bool(ms.document)),
    #("temporal", json.bool(ms.temporal)),
    #("provenance", json.bool(ms.provenance)),
    #("spatial", json.bool(ms.spatial)),
  ])
}

/// Decoder for a ModalityStatus from a JSON object.
fn modality_status_decoder() -> decode.Decoder(ModalityStatus) {
  decode.into({
    use graph <- decode.parameter
    use vector <- decode.parameter
    use tensor <- decode.parameter
    use semantic <- decode.parameter
    use document <- decode.parameter
    use temporal <- decode.parameter
    use provenance <- decode.parameter
    use spatial <- decode.parameter
    types.ModalityStatus(
      graph: graph,
      vector: vector,
      tensor: tensor,
      semantic: semantic,
      document: document,
      temporal: temporal,
      provenance: provenance,
      spatial: spatial,
    )
  })
  |> decode.field("graph", decode.bool)
  |> decode.field("vector", decode.bool)
  |> decode.field("tensor", decode.bool)
  |> decode.field("semantic", decode.bool)
  |> decode.field("document", decode.bool)
  |> decode.field("temporal", decode.bool)
  |> decode.field("provenance", decode.bool)
  |> decode.field("spatial", decode.bool)
}

// ==========================================================================
// GraphEdge encoding/decoding
// ==========================================================================

/// Encode a GraphEdge as a JSON object.
fn encode_graph_edge(edge: GraphEdge) -> json.Json {
  json.object([
    #("source", json.string(edge.source)),
    #("target", json.string(edge.target)),
    #("rel_type", json.string(edge.rel_type)),
    #("weight", json.float(edge.weight)),
    #("metadata", encode_string_dict(edge.metadata)),
  ])
}

/// Decoder for a GraphEdge from a JSON object.
fn graph_edge_decoder() -> decode.Decoder(GraphEdge) {
  decode.into({
    use source <- decode.parameter
    use target <- decode.parameter
    use rel_type <- decode.parameter
    use weight <- decode.parameter
    use metadata <- decode.parameter
    types.GraphEdge(
      source: source,
      target: target,
      rel_type: rel_type,
      weight: weight,
      metadata: metadata,
    )
  })
  |> decode.field("source", decode.string)
  |> decode.field("target", decode.string)
  |> decode.field("rel_type", decode.string)
  |> decode.field("weight", decode.float)
  |> decode.field("metadata", string_dict_decoder())
}

// ==========================================================================
// GraphData encoding/decoding
// ==========================================================================

/// Encode GraphData as a JSON object.
fn encode_graph_data(data: GraphData) -> json.Json {
  json.object([
    #("edges", json.array(data.edges, encode_graph_edge)),
    #("properties", encode_string_dict(data.properties)),
  ])
}

/// Decoder for GraphData from a JSON object.
fn graph_data_decoder() -> decode.Decoder(GraphData) {
  decode.into({
    use edges <- decode.parameter
    use properties <- decode.parameter
    types.GraphData(edges: edges, properties: properties)
  })
  |> decode.field("edges", decode.list(graph_edge_decoder()))
  |> decode.field("properties", string_dict_decoder())
}

// ==========================================================================
// VectorData encoding/decoding
// ==========================================================================

/// Encode VectorData as a JSON object.
fn encode_vector_data(data: VectorData) -> json.Json {
  json.object([
    #("embedding", json.array(data.embedding, json.float)),
    #("model", json.string(data.model)),
    #("dimensions", json.int(data.dimensions)),
  ])
}

/// Decoder for VectorData from a JSON object.
fn vector_data_decoder() -> decode.Decoder(VectorData) {
  decode.into({
    use embedding <- decode.parameter
    use model <- decode.parameter
    use dimensions <- decode.parameter
    types.VectorData(embedding: embedding, model: model, dimensions: dimensions)
  })
  |> decode.field("embedding", decode.list(decode.float))
  |> decode.field("model", decode.string)
  |> decode.field("dimensions", decode.int)
}

// ==========================================================================
// TensorData encoding/decoding
// ==========================================================================

/// Encode TensorData as a JSON object.
fn encode_tensor_data(data: TensorData) -> json.Json {
  json.object([
    #("shape", json.array(data.shape, json.int)),
    #("dtype", json.string(data.dtype)),
    #("data_ref", json.string(data.data_ref)),
  ])
}

/// Decoder for TensorData from a JSON object.
fn tensor_data_decoder() -> decode.Decoder(TensorData) {
  decode.into({
    use shape <- decode.parameter
    use dtype <- decode.parameter
    use data_ref <- decode.parameter
    types.TensorData(shape: shape, dtype: dtype, data_ref: data_ref)
  })
  |> decode.field("shape", decode.list(decode.int))
  |> decode.field("dtype", decode.string)
  |> decode.field("data_ref", decode.string)
}

// ==========================================================================
// DocumentContent encoding/decoding
// ==========================================================================

/// Encode DocumentContent as a JSON object.
fn encode_document_content(doc: DocumentContent) -> json.Json {
  json.object([
    #("text", json.string(doc.text)),
    #("format", json.string(doc.format)),
    #("language", json.string(doc.language)),
    #("metadata", encode_string_dict(doc.metadata)),
  ])
}

/// Decoder for DocumentContent from a JSON object.
fn document_content_decoder() -> decode.Decoder(DocumentContent) {
  decode.into({
    use text <- decode.parameter
    use format <- decode.parameter
    use language <- decode.parameter
    use metadata <- decode.parameter
    types.DocumentContent(
      text: text,
      format: format,
      language: language,
      metadata: metadata,
    )
  })
  |> decode.field("text", decode.string)
  |> decode.field("format", decode.string)
  |> decode.field("language", decode.string)
  |> decode.field("metadata", string_dict_decoder())
}

// ==========================================================================
// SpatialData encoding/decoding
// ==========================================================================

/// Encode SpatialData as a JSON object.
fn encode_spatial_data(data: SpatialData) -> json.Json {
  json.object([
    #("latitude", json.float(data.latitude)),
    #("longitude", json.float(data.longitude)),
    #("altitude", encode_optional(data.altitude, json.float)),
    #("geometry", encode_optional(data.geometry, json.string)),
    #("crs", json.string(data.crs)),
  ])
}

/// Decoder for SpatialData from a JSON object.
fn spatial_data_decoder() -> decode.Decoder(SpatialData) {
  decode.into({
    use latitude <- decode.parameter
    use longitude <- decode.parameter
    use altitude <- decode.parameter
    use geometry <- decode.parameter
    use crs <- decode.parameter
    types.SpatialData(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      geometry: geometry,
      crs: crs,
    )
  })
  |> decode.field("latitude", decode.float)
  |> decode.field("longitude", decode.float)
  |> optional_field("altitude", decode.float)
  |> optional_field("geometry", decode.string)
  |> decode.field("crs", decode.string)
}

// ==========================================================================
// Octad encoding/decoding
// ==========================================================================

/// Encode a full Octad as a JSON string.
pub fn encode_octad(octad: Octad) -> String {
  json.to_string(json.object([
    #("id", json.string(octad.id)),
    #("status", encode_octad_status(octad.status)),
    #("modalities", encode_modality_status(octad.modalities)),
    #("created_at", json.string(octad.created_at)),
    #("updated_at", json.string(octad.updated_at)),
    #("metadata", encode_string_dict(octad.metadata)),
    #("graph_data", encode_optional(octad.graph_data, encode_graph_data)),
    #("vector_data", encode_optional(octad.vector_data, encode_vector_data)),
    #("tensor_data", encode_optional(octad.tensor_data, encode_tensor_data)),
    #("content", encode_optional(octad.content, encode_document_content)),
    #("spatial_data", encode_optional(octad.spatial_data, encode_spatial_data)),
  ]))
}

/// Decoder for a full Octad from a JSON object.
fn octad_decoder() -> decode.Decoder(Octad) {
  decode.into({
    use id <- decode.parameter
    use status <- decode.parameter
    use modalities <- decode.parameter
    use created_at <- decode.parameter
    use updated_at <- decode.parameter
    use metadata <- decode.parameter
    use graph_data <- decode.parameter
    use vector_data <- decode.parameter
    use tensor_data <- decode.parameter
    use content <- decode.parameter
    use spatial_data <- decode.parameter
    types.Octad(
      id: id,
      status: status,
      modalities: modalities,
      created_at: created_at,
      updated_at: updated_at,
      metadata: metadata,
      graph_data: graph_data,
      vector_data: vector_data,
      tensor_data: tensor_data,
      content: content,
      spatial_data: spatial_data,
    )
  })
  |> decode.field("id", decode.string)
  |> decode.field("status", octad_status_decoder())
  |> decode.field("modalities", modality_status_decoder())
  |> decode.field("created_at", decode.string)
  |> decode.field("updated_at", decode.string)
  |> decode.field("metadata", string_dict_decoder())
  |> optional_field("graph_data", graph_data_decoder())
  |> optional_field("vector_data", vector_data_decoder())
  |> optional_field("tensor_data", tensor_data_decoder())
  |> optional_field("content", document_content_decoder())
  |> optional_field("spatial_data", spatial_data_decoder())
}

/// Decode an Octad from a JSON response body string.
pub fn decode_octad(body: String) -> Result(Octad, VeriSimError) {
  parse_json(body, octad_decoder())
}

// ==========================================================================
// OctadInput encoding
// ==========================================================================

/// Encode an OctadInput as a JSON string for create/update requests.
/// Serializes all 8 modality data fields when present, plus metadata
/// and the active modality list.
pub fn encode_octad_input(input: OctadInput) -> String {
  json.to_string(json.object([
    #(
      "modalities",
      json.array(input.modalities, encode_modality),
    ),
    #("metadata", encode_string_dict(input.metadata)),
    #("graph_data", encode_optional(input.graph_data, encode_graph_data)),
    #("vector_data", encode_optional(input.vector_data, encode_vector_data)),
    #("tensor_data", encode_optional(input.tensor_data, encode_tensor_data)),
    #("content", encode_optional(input.content, encode_document_content)),
    #("spatial_data", encode_optional(input.spatial_data, encode_spatial_data)),
  ]))
}

// ==========================================================================
// PaginatedResponse decoding
// ==========================================================================

/// Decoder for a PaginatedResponse from a JSON object.
fn paginated_response_decoder() -> decode.Decoder(PaginatedResponse) {
  decode.into({
    use items <- decode.parameter
    use total <- decode.parameter
    use page <- decode.parameter
    use per_page <- decode.parameter
    use total_pages <- decode.parameter
    types.PaginatedResponse(
      items: items,
      total: total,
      page: page,
      per_page: per_page,
      total_pages: total_pages,
    )
  })
  |> decode.field("items", decode.list(octad_decoder()))
  |> decode.field("total", decode.int)
  |> decode.field("page", decode.int)
  |> decode.field("per_page", decode.int)
  |> decode.field("total_pages", decode.int)
}

/// Decode a PaginatedResponse from a JSON response body string.
pub fn decode_paginated_response(
  body: String,
) -> Result(PaginatedResponse, VeriSimError) {
  parse_json(body, paginated_response_decoder())
}

// ==========================================================================
// SearchResult decoding
// ==========================================================================

/// Decoder for a SearchResult from a JSON object.
fn search_result_decoder() -> decode.Decoder(SearchResult) {
  decode.into({
    use octad <- decode.parameter
    use score <- decode.parameter
    types.SearchResult(octad: octad, score: score)
  })
  |> decode.field("octad", octad_decoder())
  |> decode.field("score", decode.float)
}

/// Decode a list of SearchResult from a JSON response body string.
pub fn decode_search_results(
  body: String,
) -> Result(List(SearchResult), VeriSimError) {
  parse_json(body, decode.list(search_result_decoder()))
}

// ==========================================================================
// DriftScore encoding/decoding
// ==========================================================================

/// Decoder for a DriftScore from a JSON object.
fn drift_score_decoder() -> decode.Decoder(DriftScore) {
  decode.into({
    use octad_id <- decode.parameter
    use score <- decode.parameter
    use components <- decode.parameter
    use measured_at <- decode.parameter
    use baseline_at <- decode.parameter
    types.DriftScore(
      octad_id: octad_id,
      score: score,
      components: components,
      measured_at: measured_at,
      baseline_at: baseline_at,
    )
  })
  |> decode.field("octad_id", decode.string)
  |> decode.field("score", decode.float)
  |> decode.field("components", float_dict_decoder())
  |> decode.field("measured_at", decode.string)
  |> decode.field("baseline_at", decode.string)
}

/// Decode a DriftScore from a JSON response body string.
pub fn decode_drift_score(
  body: String,
) -> Result(DriftScore, VeriSimError) {
  parse_json(body, drift_score_decoder())
}

// ==========================================================================
// DriftLevel decoding
// ==========================================================================

/// Decoder for a DriftLevel from a JSON string.
fn drift_level_decoder() -> decode.Decoder(DriftLevel) {
  decode.string
  |> decode.then(fn(s) {
    case s {
      "stable" -> decode.success(types.DriftStable)
      "low" -> decode.success(types.DriftLow)
      "moderate" -> decode.success(types.DriftModerate)
      "high" -> decode.success(types.DriftHigh)
      "critical" -> decode.success(types.DriftCritical)
      _ -> decode.failure(types.DriftStable, "DriftLevel")
    }
  })
}

// ==========================================================================
// DriftStatusReport decoding
// ==========================================================================

/// Decoder for a DriftStatusReport from a JSON object.
fn drift_status_report_decoder() -> decode.Decoder(DriftStatusReport) {
  decode.into({
    use octad_id <- decode.parameter
    use level <- decode.parameter
    use score <- decode.parameter
    use message <- decode.parameter
    types.DriftStatusReport(
      octad_id: octad_id,
      level: level,
      score: score,
      message: message,
    )
  })
  |> decode.field("octad_id", decode.string)
  |> decode.field("level", drift_level_decoder())
  |> decode.field("score", drift_score_decoder())
  |> decode.field("message", decode.string)
}

/// Decode a DriftStatusReport from a JSON response body string.
pub fn decode_drift_status_report(
  body: String,
) -> Result(DriftStatusReport, VeriSimError) {
  parse_json(body, drift_status_report_decoder())
}

// ==========================================================================
// ProvenanceEvent encoding/decoding
// ==========================================================================

/// Decoder for a ProvenanceEvent from a JSON object.
fn provenance_event_decoder() -> decode.Decoder(types.ProvenanceEvent) {
  decode.into({
    use event_id <- decode.parameter
    use octad_id <- decode.parameter
    use event_type <- decode.parameter
    use actor <- decode.parameter
    use timestamp <- decode.parameter
    use details <- decode.parameter
    use parent_id <- decode.parameter
    types.ProvenanceEvent(
      event_id: event_id,
      octad_id: octad_id,
      event_type: event_type,
      actor: actor,
      timestamp: timestamp,
      details: details,
      parent_id: parent_id,
    )
  })
  |> decode.field("event_id", decode.string)
  |> decode.field("octad_id", decode.string)
  |> decode.field("event_type", decode.string)
  |> decode.field("actor", decode.string)
  |> decode.field("timestamp", decode.string)
  |> decode.field("details", string_dict_decoder())
  |> optional_field("parent_id", decode.string)
}

/// Decode a ProvenanceEvent from a JSON response body string.
pub fn decode_provenance_event(
  body: String,
) -> Result(types.ProvenanceEvent, VeriSimError) {
  parse_json(body, provenance_event_decoder())
}

// ==========================================================================
// ProvenanceChain decoding
// ==========================================================================

/// Decoder for a ProvenanceChain from a JSON object.
fn provenance_chain_decoder() -> decode.Decoder(types.ProvenanceChain) {
  decode.into({
    use octad_id <- decode.parameter
    use events <- decode.parameter
    use verified <- decode.parameter
    types.ProvenanceChain(
      octad_id: octad_id,
      events: events,
      verified: verified,
    )
  })
  |> decode.field("octad_id", decode.string)
  |> decode.field("events", decode.list(provenance_event_decoder()))
  |> decode.field("verified", decode.bool)
}

/// Decode a ProvenanceChain from a JSON response body string.
pub fn decode_provenance_chain(
  body: String,
) -> Result(types.ProvenanceChain, VeriSimError) {
  parse_json(body, provenance_chain_decoder())
}

// ==========================================================================
// VclResult decoding
// ==========================================================================

/// Decoder for a VclResult from a JSON object.
fn vcl_result_decoder() -> decode.Decoder(VclResult) {
  decode.into({
    use columns <- decode.parameter
    use rows <- decode.parameter
    use count <- decode.parameter
    use elapsed_ms <- decode.parameter
    types.VclResult(
      columns: columns,
      rows: rows,
      count: count,
      elapsed_ms: elapsed_ms,
    )
  })
  |> decode.field("columns", decode.list(decode.string))
  |> decode.field("rows", decode.list(decode.list(decode.string)))
  |> decode.field("count", decode.int)
  |> decode.field("elapsed_ms", decode.float)
}

/// Decode a VclResult from a JSON response body string.
pub fn decode_vcl_result(
  body: String,
) -> Result(VclResult, VeriSimError) {
  parse_json(body, vcl_result_decoder())
}

// ==========================================================================
// VclExplanation decoding
// ==========================================================================

/// Decoder for a VclExplanation from a JSON object.
fn vcl_explanation_decoder() -> decode.Decoder(VclExplanation) {
  decode.into({
    use query <- decode.parameter
    use plan <- decode.parameter
    use cost <- decode.parameter
    use warnings <- decode.parameter
    types.VclExplanation(
      query: query,
      plan: plan,
      cost: cost,
      warnings: warnings,
    )
  })
  |> decode.field("query", decode.string)
  |> decode.field("plan", decode.string)
  |> decode.field("cost", decode.float)
  |> decode.field("warnings", decode.list(decode.string))
}

/// Decode a VclExplanation from a JSON response body string.
pub fn decode_vcl_explanation(
  body: String,
) -> Result(VclExplanation, VeriSimError) {
  parse_json(body, vcl_explanation_decoder())
}

// ==========================================================================
// FederationPeer decoding
// ==========================================================================

/// Decoder for a FederationPeer from a JSON object.
fn federation_peer_decoder() -> decode.Decoder(FederationPeer) {
  decode.into({
    use peer_id <- decode.parameter
    use name <- decode.parameter
    use url <- decode.parameter
    use status <- decode.parameter
    use last_seen <- decode.parameter
    use metadata <- decode.parameter
    types.FederationPeer(
      peer_id: peer_id,
      name: name,
      url: url,
      status: status,
      last_seen: last_seen,
      metadata: metadata,
    )
  })
  |> decode.field("peer_id", decode.string)
  |> decode.field("name", decode.string)
  |> decode.field("url", decode.string)
  |> decode.field("status", decode.string)
  |> decode.field("last_seen", decode.string)
  |> decode.field("metadata", string_dict_decoder())
}

/// Decode a FederationPeer from a JSON response body string.
pub fn decode_federation_peer(
  body: String,
) -> Result(FederationPeer, VeriSimError) {
  parse_json(body, federation_peer_decoder())
}

/// Decode a list of FederationPeer from a JSON response body string.
pub fn decode_federation_peers(
  body: String,
) -> Result(List(FederationPeer), VeriSimError) {
  parse_json(body, decode.list(federation_peer_decoder()))
}

// ==========================================================================
// PeerQueryResult decoding
// ==========================================================================

/// Decoder for a PeerQueryResult from a JSON object.
fn peer_query_result_decoder() -> decode.Decoder(PeerQueryResult) {
  decode.into({
    use peer_id <- decode.parameter
    use peer_name <- decode.parameter
    use result <- decode.parameter
    use elapsed_ms <- decode.parameter
    use error <- decode.parameter
    types.PeerQueryResult(
      peer_id: peer_id,
      peer_name: peer_name,
      result: result,
      elapsed_ms: elapsed_ms,
      error: error,
    )
  })
  |> decode.field("peer_id", decode.string)
  |> decode.field("peer_name", decode.string)
  |> decode.field("result", vcl_result_decoder())
  |> decode.field("elapsed_ms", decode.float)
  |> optional_field("error", decode.string)
}

// ==========================================================================
// FederatedQueryResult decoding
// ==========================================================================

/// Decoder for a FederatedQueryResult from a JSON object.
fn federated_query_result_decoder() -> decode.Decoder(FederatedQueryResult) {
  decode.into({
    use results <- decode.parameter
    use total <- decode.parameter
    use elapsed_ms <- decode.parameter
    types.FederatedQueryResult(
      results: results,
      total: total,
      elapsed_ms: elapsed_ms,
    )
  })
  |> decode.field("results", decode.list(peer_query_result_decoder()))
  |> decode.field("total", decode.int)
  |> decode.field("elapsed_ms", decode.float)
}

/// Decode a FederatedQueryResult from a JSON response body string.
pub fn decode_federated_query_result(
  body: String,
) -> Result(FederatedQueryResult, VeriSimError) {
  parse_json(body, federated_query_result_decoder())
}

// ==========================================================================
// ProvenanceEventInput encoding
// ==========================================================================

/// Encode a ProvenanceEventInput as a JSON string for POST requests.
pub fn encode_provenance_event_input(
  input: types.ProvenanceEventInput,
) -> String {
  json.to_string(json.object([
    #("event_type", json.string(input.event_type)),
    #("actor", json.string(input.actor)),
    #("details", encode_string_dict(input.details)),
  ]))
}
