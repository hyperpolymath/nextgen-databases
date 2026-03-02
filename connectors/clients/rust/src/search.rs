// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Search operations across VeriSimDB's multi-modal hexad entities.
//!
//! Supports full-text search, vector similarity (k-NN), graph-relational
//! traversal, and geospatial queries (radius, bounding box, nearest-neighbour).

use serde::Serialize;

use crate::client::VeriSimClient;
use crate::error::Result;
use crate::types::Hexad;

// ---------------------------------------------------------------------------
// Internal request bodies
// ---------------------------------------------------------------------------

/// Body for vector similarity search requests.
#[derive(Debug, Serialize)]
struct VectorSearchRequest {
    vector: Vec<f32>,
    k: usize,
}

/// Body for radius-based spatial search.
#[derive(Debug, Serialize)]
struct SpatialRadiusRequest {
    latitude: f64,
    longitude: f64,
    radius_km: f64,
    limit: usize,
}

/// Body for bounding-box spatial search.
#[derive(Debug, Serialize)]
struct SpatialBoundsRequest {
    min_lat: f64,
    min_lon: f64,
    max_lat: f64,
    max_lon: f64,
    limit: usize,
}

/// Body for nearest-neighbour spatial search.
#[derive(Debug, Serialize)]
struct SpatialNearestRequest {
    latitude: f64,
    longitude: f64,
    k: usize,
}

impl VeriSimClient {
    /// Full-text search across hexad names, descriptions, and document content.
    ///
    /// # Arguments
    ///
    /// * `query` — The search query string (supports simple keyword matching).
    /// * `limit` — Maximum number of results to return.
    pub async fn search_text(&self, query: &str, limit: usize) -> Result<Vec<Hexad>> {
        let path = format!(
            "/api/v1/search/text?q={}&limit={limit}",
            urlencoding_encode(query)
        );
        self.get(&path).await
    }

    /// Vector similarity search (k-nearest neighbours).
    ///
    /// Finds the `k` hexads whose stored vector embeddings are closest to the
    /// provided `vector` (cosine similarity by default).
    ///
    /// # Arguments
    ///
    /// * `vector` — The query embedding.
    /// * `k`      — Number of nearest neighbours to return.
    pub async fn search_vector(&self, vector: &[f32], k: usize) -> Result<Vec<Hexad>> {
        let body = VectorSearchRequest {
            vector: vector.to_vec(),
            k,
        };
        self.post("/api/v1/search/vector", &body).await
    }

    /// Find hexads related to the given entity via graph edges.
    ///
    /// Traverses one hop of the graph modality and returns all directly
    /// connected hexads.
    ///
    /// # Arguments
    ///
    /// * `id` — The hexad identifier to find relations for.
    pub async fn search_related(&self, id: &str) -> Result<Vec<Hexad>> {
        let path = format!("/api/v1/search/related/{id}");
        self.get(&path).await
    }

    /// Spatial search: find hexads within a given radius of a point.
    ///
    /// # Arguments
    ///
    /// * `lat`       — Centre latitude (WGS 84 decimal degrees).
    /// * `lon`       — Centre longitude (WGS 84 decimal degrees).
    /// * `radius_km` — Search radius in kilometres.
    /// * `limit`     — Maximum number of results.
    pub async fn search_spatial_radius(
        &self,
        lat: f64,
        lon: f64,
        radius_km: f64,
        limit: usize,
    ) -> Result<Vec<Hexad>> {
        let body = SpatialRadiusRequest {
            latitude: lat,
            longitude: lon,
            radius_km,
            limit,
        };
        self.post("/api/v1/search/spatial/radius", &body).await
    }

    /// Spatial search: find hexads within a rectangular bounding box.
    ///
    /// # Arguments
    ///
    /// * `min_lat` — Southern boundary latitude.
    /// * `min_lon` — Western boundary longitude.
    /// * `max_lat` — Northern boundary latitude.
    /// * `max_lon` — Eastern boundary longitude.
    /// * `limit`   — Maximum number of results.
    pub async fn search_spatial_bounds(
        &self,
        min_lat: f64,
        min_lon: f64,
        max_lat: f64,
        max_lon: f64,
        limit: usize,
    ) -> Result<Vec<Hexad>> {
        let body = SpatialBoundsRequest {
            min_lat,
            min_lon,
            max_lat,
            max_lon,
            limit,
        };
        self.post("/api/v1/search/spatial/bounds", &body).await
    }

    /// Spatial search: find the `k` nearest hexads to a given point.
    ///
    /// # Arguments
    ///
    /// * `lat` — Query point latitude (WGS 84 decimal degrees).
    /// * `lon` — Query point longitude (WGS 84 decimal degrees).
    /// * `k`   — Number of nearest neighbours to return.
    pub async fn search_spatial_nearest(
        &self,
        lat: f64,
        lon: f64,
        k: usize,
    ) -> Result<Vec<Hexad>> {
        let body = SpatialNearestRequest {
            latitude: lat,
            longitude: lon,
            k,
        };
        self.post("/api/v1/search/spatial/nearest", &body).await
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal percent-encoding for query string values.
///
/// This avoids pulling in a full `percent-encoding` crate for a single use.
fn urlencoding_encode(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                output.push(byte as char);
            }
            _ => {
                output.push('%');
                output.push_str(&format!("{byte:02X}"));
            }
        }
    }
    output
}
