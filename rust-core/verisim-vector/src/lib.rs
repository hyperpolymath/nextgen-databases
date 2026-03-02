// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Vector Modality
//!
//! HNSW-based similarity search for embeddings.
//! Implements Marr's Computational Level: "What is similar to what?"

mod hnsw;

pub use hnsw::{HnswConfig, HnswVectorStore};

use async_trait::async_trait;
use ndarray::{Array1, ArrayView1};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;

/// Vector modality errors
#[derive(Error, Debug)]
pub enum VectorError {
    #[error("Dimension mismatch: expected {expected}, got {actual}")]
    DimensionMismatch { expected: usize, actual: usize },

    #[error("Vector not found: {0}")]
    NotFound(String),

    #[error("Index error: {0}")]
    IndexError(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Lock poisoned: internal concurrency error")]
    LockPoisoned,
}

/// A vector embedding with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Embedding {
    /// Unique identifier (matches Hexad entity ID)
    pub id: String,
    /// The embedding vector
    pub vector: Vec<f32>,
    /// Optional metadata
    pub metadata: HashMap<String, String>,
}

impl Embedding {
    /// Create a new embedding
    pub fn new(id: impl Into<String>, vector: Vec<f32>) -> Self {
        Self {
            id: id.into(),
            vector,
            metadata: HashMap::new(),
        }
    }

    /// Add metadata
    pub fn with_metadata(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.metadata.insert(key.into(), value.into());
        self
    }

    /// Get dimensionality
    pub fn dim(&self) -> usize {
        self.vector.len()
    }

    /// Convert to ndarray
    pub fn as_array(&self) -> Array1<f32> {
        Array1::from_vec(self.vector.clone())
    }
}

/// Search result with score
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// Entity ID
    pub id: String,
    /// Similarity score (higher is more similar for cosine)
    pub score: f32,
}

/// Distance metric for similarity
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default)]
pub enum DistanceMetric {
    #[default]
    Cosine,
    Euclidean,
    DotProduct,
}

/// Vector store trait for cross-modal consistency
#[async_trait]
pub trait VectorStore: Send + Sync {
    /// Insert or update an embedding
    async fn upsert(&self, embedding: &Embedding) -> Result<(), VectorError>;

    /// Search for similar vectors
    async fn search(&self, query: &[f32], k: usize) -> Result<Vec<SearchResult>, VectorError>;

    /// Get embedding by ID
    async fn get(&self, id: &str) -> Result<Option<Embedding>, VectorError>;

    /// Delete embedding by ID
    async fn delete(&self, id: &str) -> Result<(), VectorError>;

    /// Get the dimensionality of the index
    fn dimension(&self) -> usize;
}

/// In-memory vector store with brute-force search
///
/// Note: This is a simple implementation for correctness. For production
/// workloads with >10k vectors, integrate HNSW with proper lifetime management.
pub struct BruteForceVectorStore {
    dimension: usize,
    metric: DistanceMetric,
    embeddings: Arc<RwLock<HashMap<String, Embedding>>>,
}

impl BruteForceVectorStore {
    /// Create a new vector store
    pub fn new(dimension: usize, metric: DistanceMetric) -> Self {
        Self {
            dimension,
            metric,
            embeddings: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Normalize vector for cosine similarity
    fn normalize(v: &[f32]) -> Vec<f32> {
        let norm: f32 = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            v.iter().map(|x| x / norm).collect()
        } else {
            v.to_vec()
        }
    }

    /// Compute similarity between two vectors based on metric
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
                let dist_sq: f32 = a.iter().zip(b.iter()).map(|(x, y)| (x - y).powi(2)).sum();
                1.0 / (1.0 + dist_sq.sqrt()) // Convert distance to similarity
            }
        }
    }
}

#[async_trait]
impl VectorStore for BruteForceVectorStore {
    async fn upsert(&self, embedding: &Embedding) -> Result<(), VectorError> {
        if embedding.dim() != self.dimension {
            return Err(VectorError::DimensionMismatch {
                expected: self.dimension,
                actual: embedding.dim(),
            });
        }

        self.embeddings
            .write()
            .map_err(|_| VectorError::LockPoisoned)?
            .insert(embedding.id.clone(), embedding.clone());

        Ok(())
    }

    async fn search(&self, query: &[f32], k: usize) -> Result<Vec<SearchResult>, VectorError> {
        if query.len() != self.dimension {
            return Err(VectorError::DimensionMismatch {
                expected: self.dimension,
                actual: query.len(),
            });
        }

        let embeddings = self.embeddings.read().map_err(|_| VectorError::LockPoisoned)?;

        // Compute similarities for all embeddings (brute-force)
        let mut scored: Vec<_> = embeddings
            .iter()
            .map(|(id, emb)| {
                let score = self.similarity(query, &emb.vector);
                SearchResult {
                    id: id.clone(),
                    score,
                }
            })
            .collect();

        // Sort by similarity descending
        scored.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));

        // Return top k
        scored.truncate(k);
        Ok(scored)
    }

    async fn get(&self, id: &str) -> Result<Option<Embedding>, VectorError> {
        Ok(self.embeddings.read().map_err(|_| VectorError::LockPoisoned)?.get(id).cloned())
    }

    async fn delete(&self, id: &str) -> Result<(), VectorError> {
        self.embeddings.write().map_err(|_| VectorError::LockPoisoned)?.remove(id);
        Ok(())
    }

    fn dimension(&self) -> usize {
        self.dimension
    }
}

/// Compute cosine similarity between two vectors
pub fn cosine_similarity(a: ArrayView1<f32>, b: ArrayView1<f32>) -> f32 {
    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm_a > 0.0 && norm_b > 0.0 {
        dot / (norm_a * norm_b)
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_upsert_and_search() {
        let store = BruteForceVectorStore::new(3, DistanceMetric::Cosine);

        let e1 = Embedding::new("e1", vec![1.0, 0.0, 0.0]);
        let e2 = Embedding::new("e2", vec![0.9, 0.1, 0.0]);
        let e3 = Embedding::new("e3", vec![0.0, 1.0, 0.0]);

        store.upsert(&e1).await.unwrap();
        store.upsert(&e2).await.unwrap();
        store.upsert(&e3).await.unwrap();

        let results = store.search(&[1.0, 0.0, 0.0], 2).await.unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].id, "e1");
    }
}
