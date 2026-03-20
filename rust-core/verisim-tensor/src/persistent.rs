// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent tensor store backed by redb via verisim-storage.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use tracing::info;
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{ReduceOp, Tensor, TensorError, TensorStore};

/// Persistent tensor store: redb for durability, in-memory cache for compute.
pub struct RedbTensorStore {
    store: TypedStore<RedbBackend>,
    cache: Arc<RwLock<HashMap<String, Tensor>>>,
}

impl RedbTensorStore {
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, TensorError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| TensorError::SerializationError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "tensor");

        let entries: Vec<(String, Tensor)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| TensorError::SerializationError(format!("scan: {}", e)))?;

        let mut cache = HashMap::new();
        for (id, tensor) in entries {
            cache.insert(id, tensor);
        }

        info!(count = cache.len(), "Loaded tensor store from redb");
        Ok(Self { store, cache: Arc::new(RwLock::new(cache)) })
    }
}

#[async_trait]
impl TensorStore for RedbTensorStore {
    async fn put(&self, tensor: &Tensor) -> Result<(), TensorError> {
        self.store.put(&tensor.id, tensor).await
            .map_err(|e| TensorError::SerializationError(format!("put: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| TensorError::LockPoisoned)?;
        c.insert(tensor.id.clone(), tensor.clone());
        Ok(())
    }

    async fn get(&self, id: &str) -> Result<Option<Tensor>, TensorError> {
        let c = self.cache.read().map_err(|_| TensorError::LockPoisoned)?;
        Ok(c.get(id).cloned())
    }

    async fn delete(&self, id: &str) -> Result<(), TensorError> {
        self.store.delete(id).await
            .map_err(|e| TensorError::SerializationError(format!("delete: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| TensorError::LockPoisoned)?;
        c.remove(id);
        Ok(())
    }

    async fn list(&self) -> Result<Vec<String>, TensorError> {
        let c = self.cache.read().map_err(|_| TensorError::LockPoisoned)?;
        Ok(c.keys().cloned().collect())
    }

    async fn map(&self, id: &str, op: fn(f64) -> f64) -> Result<Tensor, TensorError> {
        let c = self.cache.read().map_err(|_| TensorError::LockPoisoned)?;
        let tensor = c.get(id).ok_or_else(|| TensorError::NotFound(id.to_string()))?;
        let new_data: Vec<f64> = tensor.data.iter().map(|&v| op(v)).collect();
        Tensor::new(format!("{}_mapped", id), tensor.shape.clone(), new_data)
    }

    async fn reduce(&self, id: &str, axis: usize, op: ReduceOp) -> Result<Tensor, TensorError> {
        let c = self.cache.read().map_err(|_| TensorError::LockPoisoned)?;
        let tensor = c.get(id).ok_or_else(|| TensorError::NotFound(id.to_string()))?;
        let arr = tensor.to_ndarray();
        let reduced = match op {
            ReduceOp::Sum => arr.sum_axis(ndarray::Axis(axis)),
            ReduceOp::Mean => arr.mean_axis(ndarray::Axis(axis))
                .ok_or_else(|| TensorError::InvalidOperation("mean on empty axis".into()))?,
            ReduceOp::Max => arr.map_axis(ndarray::Axis(axis), |lane| {
                lane.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            }),
            ReduceOp::Min => arr.map_axis(ndarray::Axis(axis), |lane| {
                lane.iter().copied().fold(f64::INFINITY, f64::min)
            }),
        };
        Ok(Tensor::from_ndarray(format!("{}_reduced", id), &reduced.into_dyn()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_persistent_tensor_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tensor.redb");

        {
            let store = RedbTensorStore::open(&path).await.unwrap();
            let t = Tensor::new("t1", vec![2, 3], vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
            store.put(&t).await.unwrap();
        }

        {
            let store = RedbTensorStore::open(&path).await.unwrap();
            let t = store.get("t1").await.unwrap().unwrap();
            assert_eq!(t.shape, vec![2, 3]);
            assert_eq!(t.data, vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
        }
    }
}
