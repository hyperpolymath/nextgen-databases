// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Search operations.
//
// This module provides multi-modal search capabilities against VeriSimDB,
// including full-text search, vector similarity search, spatial radius and
// bounding-box queries, nearest-neighbour lookups, and relationship traversal.

module verisimdb_client

import json

// TextSearchParams configures a full-text search query.
pub struct TextSearchParams {
pub:
	query      string
	modalities []Modality
	limit      int = 20
	offset     int
}

// VectorSearchParams configures a vector similarity search.
pub struct VectorSearchParams {
pub:
	vector []f64
	model  string
	top_k  int = 10
	threshold f64 = 0.0
}

// SpatialRadiusParams configures a spatial radius search (point + distance).
pub struct SpatialRadiusParams {
pub:
	latitude  f64
	longitude f64
	radius_km f64
	limit     int = 20
}

// SpatialBoundsParams configures a spatial bounding-box search.
pub struct SpatialBoundsParams {
pub:
	min_lat f64
	min_lon f64
	max_lat f64
	max_lon f64
	limit   int = 20
}

// NearestParams configures a nearest-neighbour search by hexad ID.
pub struct NearestParams {
pub:
	hexad_id string
	top_k    int = 10
	modality Modality = .vector
}

// RelatedParams configures a relationship traversal search.
pub struct RelatedParams {
pub:
	hexad_id  string
	rel_type  ?string
	depth     int = 1
	limit     int = 20
}

// search_text performs a full-text search across hexad content.
//
// Parameters:
//   c      — The authenticated Client.
//   params — The text search parameters including query string and filters.
//
// Returns:
//   A list of SearchResult items ranked by relevance, or an error on failure.
pub fn (c Client) search_text(params TextSearchParams) ![]SearchResult {
	body := json.encode(params)
	resp := c.do_post('/api/v1/search/text', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode([]SearchResult, resp.body)
}

// search_vector performs a vector similarity search using a query embedding.
//
// Parameters:
//   c      — The authenticated Client.
//   params — The vector search parameters including the query vector.
//
// Returns:
//   A list of SearchResult items ranked by cosine similarity, or an error.
pub fn (c Client) search_vector(params VectorSearchParams) ![]SearchResult {
	body := json.encode(params)
	resp := c.do_post('/api/v1/search/vector', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode([]SearchResult, resp.body)
}

// search_spatial_radius finds hexads within a given radius of a point.
//
// Parameters:
//   c      — The authenticated Client.
//   params — Latitude, longitude, and radius in kilometres.
//
// Returns:
//   A list of SearchResult items within the radius, or an error.
pub fn (c Client) search_spatial_radius(params SpatialRadiusParams) ![]SearchResult {
	body := json.encode(params)
	resp := c.do_post('/api/v1/search/spatial/radius', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode([]SearchResult, resp.body)
}

// search_spatial_bounds finds hexads within a rectangular bounding box.
//
// Parameters:
//   c      — The authenticated Client.
//   params — The bounding box defined by min/max latitude and longitude.
//
// Returns:
//   A list of SearchResult items within the bounds, or an error.
pub fn (c Client) search_spatial_bounds(params SpatialBoundsParams) ![]SearchResult {
	body := json.encode(params)
	resp := c.do_post('/api/v1/search/spatial/bounds', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode([]SearchResult, resp.body)
}

// search_nearest finds the nearest neighbours of a given hexad.
//
// Parameters:
//   c      — The authenticated Client.
//   params — The hexad ID and number of neighbours to return.
//
// Returns:
//   A list of SearchResult items ordered by proximity, or an error.
pub fn (c Client) search_nearest(params NearestParams) ![]SearchResult {
	body := json.encode(params)
	resp := c.do_post('/api/v1/search/nearest', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode([]SearchResult, resp.body)
}

// search_related traverses relationships from a given hexad.
//
// Parameters:
//   c      — The authenticated Client.
//   params — The source hexad ID, optional relationship type filter, and traversal depth.
//
// Returns:
//   A list of SearchResult items connected by the specified relationships, or an error.
pub fn (c Client) search_related(params RelatedParams) ![]SearchResult {
	body := json.encode(params)
	resp := c.do_post('/api/v1/search/related', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode([]SearchResult, resp.body)
}
