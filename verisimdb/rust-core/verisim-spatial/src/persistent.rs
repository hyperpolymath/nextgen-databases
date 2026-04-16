// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent spatial store backed by redb via verisim-storage.
//
// Stores spatial data in redb for durability. On open(), all entries are
// scanned into an in-memory HashMap cache for fast brute-force queries.
// Writes go to redb first (durable), then update the cache.
//
// Uses tokio::sync::RwLock to match the async locking pattern of the
// InMemorySpatialStore.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use tracing::{debug, info, instrument};
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{
    haversine_distance, BoundingBox, Coordinates, SpatialData, SpatialError, SpatialSearchResult,
    SpatialStore,
};

/// Persistent spatial store: redb for durability, async RwLock cache for fast
/// brute-force spatial queries.
///
/// A production deployment would rebuild an R-tree from the cached data.
/// Currently uses the same brute-force approach as InMemorySpatialStore.
pub struct RedbSpatialStore {
    /// Typed store for spatial data, keyed by entity_id.
    store: TypedStore<RedbBackend>,
    /// In-memory cache of all spatial data.
    data: Arc<tokio::sync::RwLock<HashMap<String, SpatialData>>>,
}

impl RedbSpatialStore {
    /// Open (or create) a persistent spatial store at the given path.
    ///
    /// On open, all existing spatial data is scanned from redb into the
    /// in-memory cache so that reads and spatial queries never hit disk.
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, SpatialError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| SpatialError::IoError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "spatial");

        let entries: Vec<(String, SpatialData)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| SpatialError::IoError(format!("scan: {}", e)))?;

        let mut cache = HashMap::new();
        for (id, data) in entries {
            cache.insert(id, data);
        }

        info!(count = cache.len(), "Loaded spatial store from redb");
        Ok(Self {
            store,
            data: Arc::new(tokio::sync::RwLock::new(cache)),
        })
    }
}

#[async_trait]
impl SpatialStore for RedbSpatialStore {
    #[instrument(skip(self, data))]
    async fn index(&self, entity_id: &str, data: SpatialData) -> Result<(), SpatialError> {
        // Validate coordinates even if SpatialData was constructed directly.
        if !(-90.0..=90.0).contains(&data.coordinates.latitude)
            || !(-180.0..=180.0).contains(&data.coordinates.longitude)
        {
            return Err(SpatialError::InvalidCoordinates(format!(
                "lat={}, lon={} out of WGS84 range",
                data.coordinates.latitude, data.coordinates.longitude
            )));
        }

        // Write to redb first (durable).
        self.store
            .put(entity_id, &data)
            .await
            .map_err(|e| SpatialError::IoError(format!("put: {}", e)))?;

        // Update cache.
        let mut cache = self.data.write().await;
        cache.insert(entity_id.to_string(), data);
        debug!(entity_id = %entity_id, "Spatial data indexed (persistent)");
        Ok(())
    }

    async fn get(&self, entity_id: &str) -> Result<Option<SpatialData>, SpatialError> {
        let cache = self.data.read().await;
        Ok(cache.get(entity_id).cloned())
    }

    async fn delete(&self, entity_id: &str) -> Result<(), SpatialError> {
        // Delete from redb first.
        self.store
            .delete(entity_id)
            .await
            .map_err(|e| SpatialError::IoError(format!("delete: {}", e)))?;
        // Then remove from cache.
        let mut cache = self.data.write().await;
        cache.remove(entity_id);
        Ok(())
    }

    async fn search_radius(
        &self,
        center: &Coordinates,
        radius_km: f64,
        limit: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let cache = self.data.read().await;
        let mut results: Vec<SpatialSearchResult> = cache
            .iter()
            .filter_map(|(id, data)| {
                let dist = haversine_distance(center, &data.coordinates);
                if dist <= radius_km {
                    Some(SpatialSearchResult {
                        entity_id: id.clone(),
                        data: data.clone(),
                        distance_km: dist,
                    })
                } else {
                    None
                }
            })
            .collect();

        results.sort_by(|a, b| {
            a.distance_km
                .partial_cmp(&b.distance_km)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results.truncate(limit);
        Ok(results)
    }

    async fn search_within(
        &self,
        bounds: &BoundingBox,
        limit: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let cache = self.data.read().await;
        let center = Coordinates::new_unchecked(
            (bounds.min_lat + bounds.max_lat) / 2.0,
            (bounds.min_lon + bounds.max_lon) / 2.0,
            None,
        );

        let mut results: Vec<SpatialSearchResult> = cache
            .iter()
            .filter_map(|(id, data)| {
                let lat = data.coordinates.latitude;
                let lon = data.coordinates.longitude;
                if lat >= bounds.min_lat
                    && lat <= bounds.max_lat
                    && lon >= bounds.min_lon
                    && lon <= bounds.max_lon
                {
                    Some(SpatialSearchResult {
                        entity_id: id.clone(),
                        data: data.clone(),
                        distance_km: haversine_distance(&center, &data.coordinates),
                    })
                } else {
                    None
                }
            })
            .collect();

        results.sort_by(|a, b| {
            a.distance_km
                .partial_cmp(&b.distance_km)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results.truncate(limit);
        Ok(results)
    }

    async fn nearest(
        &self,
        point: &Coordinates,
        k: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let cache = self.data.read().await;
        let mut results: Vec<SpatialSearchResult> = cache
            .iter()
            .map(|(id, data)| SpatialSearchResult {
                entity_id: id.clone(),
                data: data.clone(),
                distance_km: haversine_distance(point, &data.coordinates),
            })
            .collect();

        results.sort_by(|a, b| {
            a.distance_km
                .partial_cmp(&b.distance_km)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results.truncate(k);
        Ok(results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_persistent_spatial_roundtrip() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("spatial.redb");

        // Write data in one session.
        {
            let store = RedbSpatialStore::open(&path).await.expect("TODO: handle error");
            let london = SpatialData::point(51.5074, -0.1278, Some(11.0)).expect("TODO: handle error");
            store.index("london", london).await.expect("TODO: handle error");

            let paris = SpatialData::point(48.8566, 2.3522, None).expect("TODO: handle error");
            store.index("paris", paris).await.expect("TODO: handle error");
        }

        // Reopen and verify data survived.
        {
            let store = RedbSpatialStore::open(&path).await.expect("TODO: handle error");

            let london = store.get("london").await.expect("TODO: handle error").expect("TODO: handle error");
            assert!((london.coordinates.latitude - 51.5074).abs() < 0.001);
            assert!((london.coordinates.longitude - (-0.1278)).abs() < 0.001);

            let paris = store.get("paris").await.expect("TODO: handle error").expect("TODO: handle error");
            assert!((paris.coordinates.latitude - 48.8566).abs() < 0.001);

            // Test radius search — 500 km from London should find both cities.
            let center = Coordinates::new(51.5074, -0.1278, None).expect("TODO: handle error");
            let results = store.search_radius(&center, 500.0, 10).await.expect("TODO: handle error");
            assert_eq!(results.len(), 2);
            assert_eq!(results[0].entity_id, "london");

            // Test bounding box — Western Europe.
            let bounds = BoundingBox {
                min_lat: 45.0,
                min_lon: -5.0,
                max_lat: 55.0,
                max_lon: 10.0,
            };
            let bbox_results = store.search_within(&bounds, 10).await.expect("TODO: handle error");
            assert_eq!(bbox_results.len(), 2);

            // Test nearest.
            let nearest = store.nearest(&center, 1).await.expect("TODO: handle error");
            assert_eq!(nearest.len(), 1);
            assert_eq!(nearest[0].entity_id, "london");
        }
    }

    #[tokio::test]
    async fn test_persistent_spatial_delete() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("spatial-del.redb");

        let store = RedbSpatialStore::open(&path).await.expect("TODO: handle error");
        let data = SpatialData::point(51.5074, -0.1278, None).expect("TODO: handle error");
        store.index("london", data).await.expect("TODO: handle error");

        store.delete("london").await.expect("TODO: handle error");
        assert!(store.get("london").await.expect("TODO: handle error").is_none());
    }

    #[tokio::test]
    async fn test_persistent_spatial_invalid_coordinates() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("spatial-invalid.redb");

        let store = RedbSpatialStore::open(&path).await.expect("TODO: handle error");
        let bad = SpatialData {
            coordinates: Coordinates::new_unchecked(999.0, 0.0, None),
            geometry_type: crate::GeometryType::Point,
            srid: 4326,
            properties: HashMap::new(),
        };

        let result = store.index("bad", bad).await;
        assert!(matches!(result, Err(SpatialError::InvalidCoordinates(_))));
    }
}
