//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Search operations.
////
//// This module provides multi-modal search capabilities against VeriSimDB,
//// including full-text search, vector similarity search, spatial radius and
//// bounding-box queries, nearest-neighbour lookups, and relationship traversal.

import gleam/float
import gleam/int
import gleam/json
import gleam/option.{type Option}
import verisimdb_client.{type Client}
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{type Modality, type SearchResult}

/// Parameters for a full-text search query.
pub type TextSearchParams {
  TextSearchParams(
    query: String,
    modalities: List(Modality),
    limit: Int,
    offset: Int,
  )
}

/// Parameters for a vector similarity search.
pub type VectorSearchParams {
  VectorSearchParams(
    vector: List(Float),
    model: String,
    top_k: Int,
    threshold: Float,
  )
}

/// Parameters for a spatial radius search (point + distance).
pub type SpatialRadiusParams {
  SpatialRadiusParams(
    latitude: Float,
    longitude: Float,
    radius_km: Float,
    limit: Int,
  )
}

/// Parameters for a spatial bounding-box search.
pub type SpatialBoundsParams {
  SpatialBoundsParams(
    min_lat: Float,
    min_lon: Float,
    max_lat: Float,
    max_lon: Float,
    limit: Int,
  )
}

/// Parameters for a nearest-neighbour search by hexad ID.
pub type NearestParams {
  NearestParams(hexad_id: String, top_k: Int, modality: Modality)
}

/// Parameters for a relationship traversal search.
pub type RelatedParams {
  RelatedParams(
    hexad_id: String,
    rel_type: Option(String),
    depth: Int,
    limit: Int,
  )
}

/// Perform a full-text search across hexad content.
///
/// Returns a list of SearchResult items ranked by relevance, or an error.
pub fn text(
  client: Client,
  params: TextSearchParams,
) -> Result(List(SearchResult), VeriSimError) {
  let body =
    json.to_string(json.object([
      #("query", json.string(params.query)),
      #(
        "modalities",
        json.array(params.modalities, fn(m) {
          json.string(types.modality_to_string(m))
        }),
      ),
      #("limit", json.int(params.limit)),
      #("offset", json.int(params.offset)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/search/text", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_search_results(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Perform a vector similarity search using a query embedding.
///
/// Returns a list of SearchResult items ranked by cosine similarity, or an error.
pub fn vector(
  client: Client,
  params: VectorSearchParams,
) -> Result(List(SearchResult), VeriSimError) {
  let body =
    json.to_string(json.object([
      #("vector", json.array(params.vector, json.float)),
      #("model", json.string(params.model)),
      #("top_k", json.int(params.top_k)),
      #("threshold", json.float(params.threshold)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/search/vector", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_search_results(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Find hexads within a given radius of a geographic point.
///
/// Returns a list of SearchResult items within the radius, or an error.
pub fn spatial_radius(
  client: Client,
  params: SpatialRadiusParams,
) -> Result(List(SearchResult), VeriSimError) {
  let body =
    json.to_string(json.object([
      #("latitude", json.float(params.latitude)),
      #("longitude", json.float(params.longitude)),
      #("radius_km", json.float(params.radius_km)),
      #("limit", json.int(params.limit)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/search/spatial/radius", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_search_results(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Find hexads within a rectangular bounding box.
///
/// Returns a list of SearchResult items within the bounds, or an error.
pub fn spatial_bounds(
  client: Client,
  params: SpatialBoundsParams,
) -> Result(List(SearchResult), VeriSimError) {
  let body =
    json.to_string(json.object([
      #("min_lat", json.float(params.min_lat)),
      #("min_lon", json.float(params.min_lon)),
      #("max_lat", json.float(params.max_lat)),
      #("max_lon", json.float(params.max_lon)),
      #("limit", json.int(params.limit)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/search/spatial/bounds", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_search_results(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Find the nearest neighbours of a given hexad.
///
/// Returns a list of SearchResult items ordered by proximity, or an error.
pub fn nearest(
  client: Client,
  params: NearestParams,
) -> Result(List(SearchResult), VeriSimError) {
  let body =
    json.to_string(json.object([
      #("hexad_id", json.string(params.hexad_id)),
      #("top_k", json.int(params.top_k)),
      #("modality", json.string(types.modality_to_string(params.modality))),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/search/nearest", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_search_results(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Traverse relationships from a given hexad.
///
/// Returns a list of SearchResult items connected by relationships, or an error.
pub fn related(
  client: Client,
  params: RelatedParams,
) -> Result(List(SearchResult), VeriSimError) {
  let base_fields = [
    #("hexad_id", json.string(params.hexad_id)),
    #("depth", json.int(params.depth)),
    #("limit", json.int(params.limit)),
  ]
  let fields = case params.rel_type {
    option.Some(rt) -> [#("rel_type", json.string(rt)), ..base_fields]
    option.None -> base_fields
  }
  let body = json.to_string(json.object(fields))
  case verisimdb_client.do_post(client, "/api/v1/search/related", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_search_results(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

// ---------------------------------------------------------------------------
// Internal JSON decoding helpers (stub)
// ---------------------------------------------------------------------------

/// Decode search results from a JSON response body.
/// TODO: Implement full JSON decoding with gleam_json decoders.
fn decode_search_results(
  body: String,
) -> Result(List(SearchResult), VeriSimError) {
  Error(error.SerializationError(
    "SearchResult JSON decoding not yet implemented (scaffold)",
  ))
}
