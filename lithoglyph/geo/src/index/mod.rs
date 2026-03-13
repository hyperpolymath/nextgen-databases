// SPDX-License-Identifier: PMPL-1.0-or-later
//! Spatial indexing using R-tree
//!
//! This module provides spatial indexing for Lith documents.
//! The index is a materialized projection - Lith remains the source of truth.

mod rtree;

pub use rtree::SpatialIndex;

use geo::Point;
use serde::{Deserialize, Serialize};

/// A spatial entry linking a location to a Lith document
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialEntry {
    /// Lith document ID
    pub lithoglyph_id: String,
    /// Location coordinates
    pub location: Point<f64>,
    /// When this entry was indexed
    pub indexed_at: chrono::DateTime<chrono::Utc>,
}

impl SpatialEntry {
    /// Create a new spatial entry
    pub fn new(lithoglyph_id: String, lat: f64, lon: f64) -> Self {
        Self {
            lithoglyph_id,
            location: Point::new(lon, lat), // geo uses (x, y) = (lon, lat)
            indexed_at: chrono::Utc::now(),
        }
    }

    /// Get latitude
    pub fn lat(&self) -> f64 {
        self.location.y()
    }

    /// Get longitude
    pub fn lon(&self) -> f64 {
        self.location.x()
    }
}

/// Result of a spatial query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialQueryResult {
    /// The matched entry
    pub entry: SpatialEntry,
    /// Distance from query point (if applicable)
    pub distance_km: Option<f64>,
}

/// Bounding box for spatial queries
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct BoundingBox {
    pub min_lat: f64,
    pub min_lon: f64,
    pub max_lat: f64,
    pub max_lon: f64,
}

impl BoundingBox {
    /// Create a bounding box from coordinates
    pub fn new(min_lat: f64, min_lon: f64, max_lat: f64, max_lon: f64) -> Self {
        Self {
            min_lat,
            min_lon,
            max_lat,
            max_lon,
        }
    }

    /// Check if a point is within this bounding box
    pub fn contains(&self, lat: f64, lon: f64) -> bool {
        lat >= self.min_lat && lat <= self.max_lat && lon >= self.min_lon && lon <= self.max_lon
    }
}
