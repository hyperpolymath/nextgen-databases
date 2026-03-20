// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent spatial store backed by redb via verisim-storage.
// Stores spatial data in redb, rebuilds R-tree index on startup.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use tracing::info;
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{BoundingBox, Coordinates, SpatialData, SpatialError, SpatialSearchResult, SpatialStore};

/// Persistent spatial store: redb for durability, in-memory brute-force for queries.
/// R-tree index would be rebuilt from redb data on startup (currently brute-force).
pub struct RedbSpatialStore {
    store: TypedStore<RedbBackend>,
    cache: Arc<RwLock<HashMap<String, SpatialData>>>,
}

impl RedbSpatialStore {
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, SpatialError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| SpatialError::StorageError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "spatial");

        let entries: Vec<(String, SpatialData)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| SpatialError::StorageError(format!("scan: {}", e)))?;

        let mut cache = HashMap::new();
        for (id, data) in entries {
            cache.insert(id, data);
        }

        info!(count = cache.len(), "Loaded spatial store from redb");
        Ok(Self { store, cache: Arc::new(RwLock::new(cache)) })
    }

    fn haversine_distance(a: &Coordinates, b: &Coordinates) -> f64 {
        let r = 6371.0; // Earth radius in km
        let dlat = (b.latitude - a.latitude).to_radians();
        let dlon = (b.longitude - a.longitude).to_radians();
        let a_lat = a.latitude.to_radians();
        let b_lat = b.latitude.to_radians();
        let hav = (dlat / 2.0).sin().powi(2) + a_lat.cos() * b_lat.cos() * (dlon / 2.0).sin().powi(2);
        2.0 * r * hav.sqrt().asin()
    }
}

#[async_trait]
impl SpatialStore for RedbSpatialStore {
    async fn put(&self, data: &SpatialData) -> Result<(), SpatialError> {
        self.store.put(&data.entity_id, data).await
            .map_err(|e| SpatialError::StorageError(format!("put: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| SpatialError::LockPoisoned)?;
        c.insert(data.entity_id.clone(), data.clone());
        Ok(())
    }

    async fn get(&self, entity_id: &str) -> Result<Option<SpatialData>, SpatialError> {
        let c = self.cache.read().map_err(|_| SpatialError::LockPoisoned)?;
        Ok(c.get(entity_id).cloned())
    }

    async fn delete(&self, entity_id: &str) -> Result<(), SpatialError> {
        self.store.delete(entity_id).await
            .map_err(|e| SpatialError::StorageError(format!("delete: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| SpatialError::LockPoisoned)?;
        c.remove(entity_id);
        Ok(())
    }

    async fn search_radius(&self, center: &Coordinates, radius_km: f64, limit: usize) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let c = self.cache.read().map_err(|_| SpatialError::LockPoisoned)?;
        let mut results: Vec<SpatialSearchResult> = c.values()
            .filter_map(|data| {
                let dist = Self::haversine_distance(center, &data.coordinates);
                if dist <= radius_km {
                    Some(SpatialSearchResult { entity_id: data.entity_id.clone(), distance: dist, data: data.clone() })
                } else {
                    None
                }
            })
            .collect();
        results.sort_by(|a, b| a.distance.partial_cmp(&b.distance).unwrap_or(std::cmp::Ordering::Equal));
        results.truncate(limit);
        Ok(results)
    }

    async fn search_bounds(&self, bounds: &BoundingBox, limit: usize) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let c = self.cache.read().map_err(|_| SpatialError::LockPoisoned)?;
        let mut results: Vec<SpatialSearchResult> = c.values()
            .filter(|data| bounds.contains(&data.coordinates))
            .map(|data| SpatialSearchResult {
                entity_id: data.entity_id.clone(),
                distance: 0.0,
                data: data.clone(),
            })
            .collect();
        results.truncate(limit);
        Ok(results)
    }

    async fn nearest(&self, point: &Coordinates, k: usize) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let c = self.cache.read().map_err(|_| SpatialError::LockPoisoned)?;
        let mut results: Vec<SpatialSearchResult> = c.values()
            .map(|data| {
                let dist = Self::haversine_distance(point, &data.coordinates);
                SpatialSearchResult { entity_id: data.entity_id.clone(), distance: dist, data: data.clone() }
            })
            .collect();
        results.sort_by(|a, b| a.distance.partial_cmp(&b.distance).unwrap_or(std::cmp::Ordering::Equal));
        results.truncate(k);
        Ok(results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_persistent_spatial_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("spatial.redb");

        {
            let store = RedbSpatialStore::open(&path).await.unwrap();
            let data = SpatialData {
                entity_id: "london".to_string(),
                coordinates: Coordinates { latitude: 51.5074, longitude: -0.1278, altitude: Some(11.0) },
                geometry: None,
                crs: "EPSG:4326".to_string(),
                metadata: HashMap::new(),
            };
            store.put(&data).await.unwrap();
        }

        {
            let store = RedbSpatialStore::open(&path).await.unwrap();
            let data = store.get("london").await.unwrap().unwrap();
            assert!((data.coordinates.latitude - 51.5074).abs() < 0.001);
        }
    }
}
