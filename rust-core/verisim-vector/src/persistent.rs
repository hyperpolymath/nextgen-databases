// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent vector store backed by redb via verisim-storage.
//
// Durable storage of embeddings with an ephemeral in-memory index for fast
// similarity search. On startup, all embeddings are loaded from redb and the
// index is rebuilt. Writes go to both redb (durable) and the in-memory index
// (fast search).
//
// Design:
// - TypedStore<RedbBackend> with namespace "vec" handles serialisation + persistence
// - In-memory HashMap + brute-force search for queries (same as BruteForceVectorStore)
// - Startup: load all embeddings from redb, populate in-memory index
// - Upsert: write to redb first (durable), then update in-memory index
// - Delete: remove from redb first, then remove from in-memory index
// - Search: in-memory only (fast, no disk I/O)

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use tracing::{debug, info};
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{DistanceMetric, Embedding, SearchResult, VectorError, VectorStore};

/// Persistent vector store: redb for durability, in-memory index for search.
pub struct RedbVectorStore {
    /// Dimensionality of stored vectors.
    dimension: usize,
    /// Distance metric for similarity computation.
    metric: DistanceMetric,
    /// Durable storage: TypedStore<RedbBackend> with namespace "vec".
    store: TypedStore<RedbBackend>,
    /// Ephemeral in-memory index for fast similarity search.
    /// Rebuilt from redb on startup.
    index: Arc<RwLock<HashMap<String, Embedding>>>,
}

impl RedbVectorStore {
    /// Open or create a persistent vector store at the given path.
    ///
    /// On first open, creates an empty redb database.
    /// On subsequent opens, loads all embeddings from redb and rebuilds the
    /// in-memory index. Returns the number of embeddings loaded.
    pub async fn open(
        path: impl AsRef<Path>,
        dimension: usize,
        metric: DistanceMetric,
    ) -> Result<Self, VectorError> {
        let backend = RedbBackend::open(path.as_ref()).map_err(|e| {
            VectorError::IndexError(format!("Failed to open redb: {}", e))
        })?;
        let store = TypedStore::new(backend, "vec");

        let mut index = HashMap::new();

        // Load all existing embeddings from redb into memory
        let entries: Vec<(String, Embedding)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| VectorError::IndexError(format!("Failed to scan redb: {}", e)))?;

        for (id, embedding) in &entries {
            // Validate dimensionality
            if embedding.dim() != dimension {
                debug!(
                    id = %id,
                    expected = dimension,
                    actual = embedding.dim(),
                    "Skipping embedding with wrong dimensionality"
                );
                continue;
            }
            index.insert(id.clone(), embedding.clone());
        }

        info!(
            count = index.len(),
            dimension = dimension,
            path = %path.as_ref().display(),
            "Loaded vector store from redb"
        );

        Ok(Self {
            dimension,
            metric,
            store,
            index: Arc::new(RwLock::new(index)),
        })
    }

    /// Normalise a vector for cosine similarity.
    fn normalize(v: &[f32]) -> Vec<f32> {
        let norm: f32 = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            v.iter().map(|x| x / norm).collect()
        } else {
            v.to_vec()
        }
    }

    /// Compute similarity between two vectors.
    fn similarity(&self, a: &[f32], b: &[f32]) -> f32 {
        match self.metric {
            DistanceMetric::Cosine => {
                let a_norm = Self::normalize(a);
                let b_norm = Self::normalize(b);
                a_norm.iter().zip(b_norm.iter()).map(|(x, y)| x * y).sum()
            }
            DistanceMetric::DotProduct => {
                a.iter().zip(b.iter()).map(|(x, y)| x * y).sum()
            }
            DistanceMetric::Euclidean => {
                let dist_sq: f32 = a
                    .iter()
                    .zip(b.iter())
                    .map(|(x, y)| (x - y).powi(2))
                    .sum();
                1.0 / (1.0 + dist_sq.sqrt())
            }
        }
    }
}

#[async_trait]
impl VectorStore for RedbVectorStore {
    async fn upsert(&self, embedding: &Embedding) -> Result<(), VectorError> {
        if embedding.dim() != self.dimension {
            return Err(VectorError::DimensionMismatch {
                expected: self.dimension,
                actual: embedding.dim(),
            });
        }

        // Write to redb first (durable)
        self.store
            .put(&embedding.id, embedding)
            .await
            .map_err(|e| VectorError::IndexError(format!("redb put: {}", e)))?;

        // Then update in-memory index
        let mut idx = self.index.write().map_err(|_| VectorError::LockPoisoned)?;
        idx.insert(embedding.id.clone(), embedding.clone());

        Ok(())
    }

    async fn search(&self, query: &[f32], k: usize) -> Result<Vec<SearchResult>, VectorError> {
        if query.len() != self.dimension {
            return Err(VectorError::DimensionMismatch {
                expected: self.dimension,
                actual: query.len(),
            });
        }

        let idx = self.index.read().map_err(|_| VectorError::LockPoisoned)?;

        let mut results: Vec<SearchResult> = idx
            .values()
            .map(|emb| SearchResult {
                id: emb.id.clone(),
                score: self.similarity(query, &emb.vector),
            })
            .collect();

        results.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        results.truncate(k);

        Ok(results)
    }

    async fn get(&self, id: &str) -> Result<Option<Embedding>, VectorError> {
        // Read from in-memory index (fast path)
        let idx = self.index.read().map_err(|_| VectorError::LockPoisoned)?;
        Ok(idx.get(id).cloned())
    }

    async fn delete(&self, id: &str) -> Result<(), VectorError> {
        // Delete from redb first (durable)
        self.store
            .delete(id)
            .await
            .map_err(|e| VectorError::IndexError(format!("redb delete: {}", e)))?;

        // Then remove from in-memory index
        let mut idx = self.index.write().map_err(|_| VectorError::LockPoisoned)?;
        idx.remove(id);

        Ok(())
    }

    fn dimension(&self) -> usize {
        self.dimension
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_persistent_vector_roundtrip() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("vector.redb");

        // Create store and insert embeddings
        {
            let store = RedbVectorStore::open(&path, 3, DistanceMetric::Cosine)
                .await
                .expect("TODO: handle error");

            store
                .upsert(&Embedding::new("a", vec![1.0, 0.0, 0.0]))
                .await
                .expect("TODO: handle error");
            store
                .upsert(&Embedding::new("b", vec![0.0, 1.0, 0.0]))
                .await
                .expect("TODO: handle error");
            store
                .upsert(&Embedding::new("c", vec![0.9, 0.1, 0.0]))
                .await
                .expect("TODO: handle error");

            // Verify search works
            let results = store.search(&[1.0, 0.0, 0.0], 2).await.expect("TODO: handle error");
            assert_eq!(results.len(), 2);
            assert_eq!(results[0].id, "a"); // Most similar to [1,0,0]
        }

        // Reopen store — data should survive
        {
            let store = RedbVectorStore::open(&path, 3, DistanceMetric::Cosine)
                .await
                .expect("TODO: handle error");

            // Verify data persisted
            let a = store.get("a").await.expect("TODO: handle error");
            assert!(a.is_some());
            assert_eq!(a.expect("TODO: handle error").vector, vec![1.0, 0.0, 0.0]);

            let b = store.get("b").await.expect("TODO: handle error");
            assert!(b.is_some());

            // Verify search still works after reload
            let results = store.search(&[1.0, 0.0, 0.0], 2).await.expect("TODO: handle error");
            assert_eq!(results.len(), 2);
            assert_eq!(results[0].id, "a");
        }
    }

    #[tokio::test]
    async fn test_persistent_vector_delete() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("vector-del.redb");

        {
            let store = RedbVectorStore::open(&path, 3, DistanceMetric::Cosine)
                .await
                .expect("TODO: handle error");

            store
                .upsert(&Embedding::new("x", vec![1.0, 0.0, 0.0]))
                .await
                .expect("TODO: handle error");
            store.delete("x").await.expect("TODO: handle error");

            let result: Option<Embedding> = store.get("x").await.expect("TODO: handle error");
            assert!(result.is_none());
        }

        // Reopen — deletion should persist
        {
            let store = RedbVectorStore::open(&path, 3, DistanceMetric::Cosine)
                .await
                .expect("TODO: handle error");
            let result: Option<Embedding> = store.get("x").await.expect("TODO: handle error");
            assert!(result.is_none());
        }
    }
}
