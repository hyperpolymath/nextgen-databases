// SPDX-License-Identifier: PMPL-1.0-or-later
//! R-tree spatial index implementation

use super::{BoundingBox, SpatialEntry, SpatialQueryResult};
use geo::{HaversineDistance, Point};
use rstar::{primitives::GeomWithData, RTree, AABB};
use std::sync::RwLock;
use tracing::info;

/// Type alias for R-tree entries
type RTreeEntry = GeomWithData<[f64; 2], String>;

/// Spatial index using R-tree for efficient spatial queries
pub struct SpatialIndex {
    /// The R-tree index
    tree: RwLock<RTree<RTreeEntry>>,
    /// Maximum memory limit in MB
    max_memory_mb: usize,
    /// Index statistics
    stats: RwLock<IndexStats>,
}

/// Statistics about the spatial index
#[derive(Debug, Clone, Default)]
pub struct IndexStats {
    /// Number of entries in the index
    pub entry_count: usize,
    /// Last rebuild timestamp
    pub last_rebuild: Option<chrono::DateTime<chrono::Utc>>,
    /// Approximate memory usage in bytes
    pub memory_bytes: usize,
}

impl SpatialIndex {
    /// Create a new empty spatial index
    pub fn new(max_memory_mb: usize) -> Self {
        Self {
            tree: RwLock::new(RTree::new()),
            max_memory_mb,
            stats: RwLock::new(IndexStats::default()),
        }
    }

    /// Insert an entry into the index
    pub fn insert(&self, entry: SpatialEntry) {
        let point = [entry.lon(), entry.lat()];
        let rtree_entry = GeomWithData::new(point, entry.lithoglyph_id);

        let mut tree = self.tree.write().unwrap();
        tree.insert(rtree_entry);

        let mut stats = self.stats.write().unwrap();
        stats.entry_count += 1;
    }

    /// Bulk insert entries (more efficient than individual inserts)
    pub fn bulk_insert(&self, entries: Vec<SpatialEntry>) {
        let rtree_entries: Vec<RTreeEntry> = entries
            .into_iter()
            .map(|e| GeomWithData::new([e.lon(), e.lat()], e.lithoglyph_id))
            .collect();

        let count = rtree_entries.len();
        let new_tree = RTree::bulk_load(rtree_entries);

        let mut tree = self.tree.write().unwrap();
        *tree = new_tree;

        let mut stats = self.stats.write().unwrap();
        stats.entry_count = count;
        stats.last_rebuild = Some(chrono::Utc::now());

        info!("Spatial index rebuilt with {} entries", count);
    }

    /// Clear the index
    pub fn clear(&self) {
        let mut tree = self.tree.write().unwrap();
        *tree = RTree::new();

        let mut stats = self.stats.write().unwrap();
        stats.entry_count = 0;
    }

    /// Query entries within a bounding box
    pub fn query_bbox(&self, bbox: BoundingBox) -> Vec<SpatialQueryResult> {
        let tree = self.tree.read().unwrap();

        let aabb = AABB::from_corners([bbox.min_lon, bbox.min_lat], [bbox.max_lon, bbox.max_lat]);

        tree.locate_in_envelope(&aabb)
            .map(|entry| {
                let [lon, lat] = *entry.geom();
                SpatialQueryResult {
                    entry: SpatialEntry::new(entry.data.clone(), lat, lon),
                    distance_km: None,
                }
            })
            .collect()
    }

    /// Query entries within a radius of a point
    pub fn query_radius(&self, lat: f64, lon: f64, radius_km: f64) -> Vec<SpatialQueryResult> {
        let tree = self.tree.read().unwrap();
        let center = Point::new(lon, lat);

        // Convert km to approximate degrees for initial bbox filter
        // 1 degree latitude ≈ 111 km
        let degree_radius = radius_km / 111.0;

        let bbox = AABB::from_corners(
            [lon - degree_radius, lat - degree_radius],
            [lon + degree_radius, lat + degree_radius],
        );

        tree.locate_in_envelope(&bbox)
            .filter_map(|entry| {
                let [entry_lon, entry_lat] = *entry.geom();
                let entry_point = Point::new(entry_lon, entry_lat);

                // Calculate actual distance using Haversine formula
                let distance_m = center.haversine_distance(&entry_point);
                let distance_km = distance_m / 1000.0;

                if distance_km <= radius_km {
                    Some(SpatialQueryResult {
                        entry: SpatialEntry::new(entry.data.clone(), entry_lat, entry_lon),
                        distance_km: Some(distance_km),
                    })
                } else {
                    None
                }
            })
            .collect()
    }

    /// Find k nearest neighbors to a point
    pub fn query_nearest(&self, lat: f64, lon: f64, k: usize) -> Vec<SpatialQueryResult> {
        let tree = self.tree.read().unwrap();
        let center = Point::new(lon, lat);

        tree.nearest_neighbor_iter(&[lon, lat])
            .take(k)
            .map(|entry| {
                let [entry_lon, entry_lat] = *entry.geom();
                let entry_point = Point::new(entry_lon, entry_lat);
                let distance_km = center.haversine_distance(&entry_point) / 1000.0;

                SpatialQueryResult {
                    entry: SpatialEntry::new(entry.data.clone(), entry_lat, entry_lon),
                    distance_km: Some(distance_km),
                }
            })
            .collect()
    }

    /// Get index statistics
    pub fn stats(&self) -> IndexStats {
        self.stats.read().unwrap().clone()
    }

    /// Get entry count
    pub fn len(&self) -> usize {
        self.tree.read().unwrap().size()
    }

    /// Check if index is empty
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_insert_and_query_bbox() {
        let index = SpatialIndex::new(512);

        // Insert London
        index.insert(SpatialEntry::new("doc_london".to_string(), 51.5074, -0.1278));
        // Insert Paris
        index.insert(SpatialEntry::new("doc_paris".to_string(), 48.8566, 2.3522));
        // Insert Berlin
        index.insert(SpatialEntry::new("doc_berlin".to_string(), 52.5200, 13.4050));

        // Query for Western Europe (should get London and Paris)
        let bbox = BoundingBox::new(45.0, -5.0, 55.0, 5.0);
        let results = index.query_bbox(bbox);

        assert_eq!(results.len(), 2);
        let ids: Vec<_> = results.iter().map(|r| &r.entry.lithoglyph_id).collect();
        assert!(ids.contains(&&"doc_london".to_string()));
        assert!(ids.contains(&&"doc_paris".to_string()));
    }

    #[test]
    fn test_query_radius() {
        let index = SpatialIndex::new(512);

        // Insert cities
        index.insert(SpatialEntry::new("doc_london".to_string(), 51.5074, -0.1278));
        index.insert(SpatialEntry::new("doc_paris".to_string(), 48.8566, 2.3522));

        // Query within 50km of London center (should only get London)
        let results = index.query_radius(51.5074, -0.1278, 50.0);

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].entry.lithoglyph_id, "doc_london");
        assert!(results[0].distance_km.unwrap() < 1.0); // Should be very close
    }

    #[test]
    fn test_query_nearest() {
        let index = SpatialIndex::new(512);

        index.insert(SpatialEntry::new("doc_1".to_string(), 51.5, -0.1));
        index.insert(SpatialEntry::new("doc_2".to_string(), 51.6, -0.1));
        index.insert(SpatialEntry::new("doc_3".to_string(), 51.7, -0.1));

        // Find 2 nearest to (51.55, -0.1)
        let results = index.query_nearest(51.55, -0.1, 2);

        assert_eq!(results.len(), 2);
        // Should be doc_1 (51.5) and doc_2 (51.6), both ~5.5km away
    }
}
