// SPDX-License-Identifier: PMPL-1.0-or-later
//! HNSW (Hierarchical Navigable Small World) vector index
//!
//! Pure Rust implementation with proper lifetime management.
//! Avoids the `'b` lifetime parameter issue in hnsw_rs 0.3 by owning
//! all graph data directly — no self-referential structs needed.
//!
//! Algorithm: Malkov & Yashunin, "Efficient and robust approximate
//! nearest neighbor search using Hierarchical Navigable Small World graphs"

use crate::{DistanceMetric, Embedding, SearchResult, VectorError, VectorStore};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::cmp::{Ordering, Reverse};
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};
use std::sync::{Arc, RwLock};

/// Maximum supported layers in the HNSW graph.
const MAX_LEVELS: usize = 16;

/// Monotonic counter for level assignment entropy.
static INSERT_COUNTER: AtomicU64 = AtomicU64::new(0);

// ---------------------------------------------------------------------------
// Ordered f32 for BinaryHeap (f32 doesn't implement Ord)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
struct Dist(f32);

impl Eq for Dist {}

impl PartialOrd for Dist {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Dist {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.partial_cmp(&other.0).unwrap_or(Ordering::Equal)
    }
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// HNSW index configuration parameters.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HnswConfig {
    /// Max bidirectional connections per node per layer (M parameter).
    pub max_connections: usize,
    /// Max connections for layer 0 (typically 2*M).
    pub max_connections_layer0: usize,
    /// Size of dynamic candidate list during construction.
    pub ef_construction: usize,
    /// Size of dynamic candidate list during search.
    pub ef_search: usize,
}

impl Default for HnswConfig {
    fn default() -> Self {
        Self {
            max_connections: 16,
            max_connections_layer0: 32,
            ef_construction: 200,
            ef_search: 64,
        }
    }
}

// ---------------------------------------------------------------------------
// Internal graph structures (no public lifetime parameters)
// ---------------------------------------------------------------------------

/// Internal node — owns its vector data.
struct Node {
    id: String,
    vector: Vec<f32>,
    metadata: HashMap<String, String>,
    /// Neighbors per layer (layer index -> vec of node indices).
    neighbors: Vec<Vec<usize>>,
    /// Assigned level for this node.
    level: usize,
    /// Soft-delete flag.
    deleted: bool,
}

/// Internal graph state — fully owned, no lifetimes.
struct Graph {
    nodes: Vec<Node>,
    id_map: HashMap<String, usize>,
    entry_point: Option<usize>,
    current_max_level: usize,
}

impl Graph {
    fn new() -> Self {
        Self {
            nodes: Vec::new(),
            id_map: HashMap::new(),
            entry_point: None,
            current_max_level: 0,
        }
    }

    /// Compute distance between two vectors (lower = closer).
    fn distance(metric: DistanceMetric, a: &[f32], b: &[f32]) -> f32 {
        match metric {
            DistanceMetric::Cosine => {
                let mut dot = 0.0f32;
                let mut norm_a = 0.0f32;
                let mut norm_b = 0.0f32;
                for (x, y) in a.iter().zip(b.iter()) {
                    dot += x * y;
                    norm_a += x * x;
                    norm_b += y * y;
                }
                let denom = norm_a.sqrt() * norm_b.sqrt();
                if denom > 0.0 {
                    1.0 - dot / denom
                } else {
                    1.0
                }
            }
            DistanceMetric::Euclidean => a
                .iter()
                .zip(b.iter())
                .map(|(x, y)| (x - y).powi(2))
                .sum::<f32>()
                .sqrt(),
            DistanceMetric::DotProduct => {
                // Negate so lower value = higher dot product = more similar
                -a.iter().zip(b.iter()).map(|(x, y)| x * y).sum::<f32>()
            }
        }
    }

    /// Convert HNSW distance back to similarity score for results.
    fn distance_to_score(metric: DistanceMetric, distance: f32) -> f32 {
        match metric {
            DistanceMetric::Cosine => 1.0 - distance,
            DistanceMetric::Euclidean => 1.0 / (1.0 + distance),
            DistanceMetric::DotProduct => -distance,
        }
    }

    /// Assign a random level using hash-based PRNG (no `rand` dependency).
    fn assign_level(id: &str, max_connections: usize) -> usize {
        let count = INSERT_COUNTER.fetch_add(1, AtomicOrdering::Relaxed);
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        id.hash(&mut hasher);
        count.hash(&mut hasher);
        let hash = hasher.finish();

        // Convert to uniform float in (0, 1), avoiding ln(0)
        let uniform = ((hash >> 11) as f64 + 1.0) / ((1u64 << 53) as f64 + 1.0);
        let ml = 1.0 / (max_connections as f64).ln();
        let level = (-uniform.ln() * ml).floor() as usize;
        level.min(MAX_LEVELS - 1)
    }

    /// Search a single layer, returning up to `ef` nearest neighbors.
    /// Returns Vec<(distance, node_index)> sorted by distance ascending.
    fn search_layer(
        &self,
        query: &[f32],
        entry_points: &[usize],
        ef: usize,
        layer: usize,
        metric: DistanceMetric,
    ) -> Vec<(f32, usize)> {
        let mut visited = HashSet::new();
        // Min-heap for candidates (closest first)
        let mut candidates: BinaryHeap<Reverse<(Dist, usize)>> = BinaryHeap::new();
        // Max-heap for results (furthest first, for pruning)
        let mut results: BinaryHeap<(Dist, usize)> = BinaryHeap::new();

        for &ep in entry_points {
            if ep >= self.nodes.len() {
                continue;
            }
            let dist = Self::distance(metric, query, &self.nodes[ep].vector);
            visited.insert(ep);
            // Always add to candidates (for navigation), only add live nodes to results
            candidates.push(Reverse((Dist(dist), ep)));
            if !self.nodes[ep].deleted {
                results.push((Dist(dist), ep));
            }
        }

        while let Some(Reverse((Dist(c_dist), c_idx))) = candidates.pop() {
            let furthest_dist = results.peek().map(|(Dist(d), _)| *d).unwrap_or(f32::MAX);
            // For deleted-heavy graphs, only break when we have enough results
            if c_dist > furthest_dist && results.len() >= ef {
                break;
            }

            if layer < self.nodes[c_idx].neighbors.len() {
                for &neighbor_idx in &self.nodes[c_idx].neighbors[layer] {
                    if neighbor_idx >= self.nodes.len() || visited.contains(&neighbor_idx) {
                        continue;
                    }
                    visited.insert(neighbor_idx);

                    let dist = Self::distance(metric, query, &self.nodes[neighbor_idx].vector);

                    // Always add to candidates for graph traversal
                    candidates.push(Reverse((Dist(dist), neighbor_idx)));

                    // Only add live nodes to results
                    if !self.nodes[neighbor_idx].deleted {
                        let furthest_dist =
                            results.peek().map(|(Dist(d), _)| *d).unwrap_or(f32::MAX);
                        if dist < furthest_dist || results.len() < ef {
                            results.push((Dist(dist), neighbor_idx));
                            if results.len() > ef {
                                results.pop();
                            }
                        }
                    }
                }
            }
        }

        let mut result_vec: Vec<(f32, usize)> =
            results.into_iter().map(|(Dist(d), idx)| (d, idx)).collect();
        result_vec.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(Ordering::Equal));
        result_vec
    }

    /// Select M nearest neighbors from sorted candidates.
    fn select_neighbors(candidates: &[(f32, usize)], m: usize) -> Vec<usize> {
        candidates.iter().take(m).map(|(_, idx)| *idx).collect()
    }

    /// Insert a node into the HNSW graph.
    fn insert(
        &mut self,
        id: String,
        vector: Vec<f32>,
        metadata: HashMap<String, String>,
        config: &HnswConfig,
        metric: DistanceMetric,
    ) {
        // Upsert: if ID exists, update vector in place (connections stay valid
        // for approximate search — small perturbations don't break HNSW).
        if let Some(&existing_idx) = self.id_map.get(&id) {
            self.nodes[existing_idx].vector = vector;
            self.nodes[existing_idx].metadata = metadata;
            self.nodes[existing_idx].deleted = false;
            return;
        }

        let level = Self::assign_level(&id, config.max_connections);
        let node_idx = self.nodes.len();

        let node = Node {
            id: id.clone(),
            vector,
            metadata,
            neighbors: (0..=level).map(|_| Vec::new()).collect(),
            level,
            deleted: false,
        };
        self.nodes.push(node);
        self.id_map.insert(id, node_idx);

        // First node — just set as entry point.
        if self.entry_point.is_none() {
            self.entry_point = Some(node_idx);
            self.current_max_level = level;
            return;
        }

        let ep = self.entry_point.unwrap();
        let mut current_ep = vec![ep];

        // Phase 1: Greedy descent from top layer to (node level + 1)
        let top = self.current_max_level;
        if top > level {
            for l in (level + 1..=top).rev() {
                let nearest = self.search_layer(
                    &self.nodes[node_idx].vector,
                    &current_ep,
                    1,
                    l,
                    metric,
                );
                if let Some(&(_, idx)) = nearest.first() {
                    current_ep = vec![idx];
                }
            }
        }

        // Phase 2: Insert at each layer from min(level, top) down to 0
        let insert_top = level.min(top);
        for l in (0..=insert_top).rev() {
            let max_conn = if l == 0 {
                config.max_connections_layer0
            } else {
                config.max_connections
            };

            let nearest = self.search_layer(
                &self.nodes[node_idx].vector,
                &current_ep,
                config.ef_construction,
                l,
                metric,
            );

            let selected = Self::select_neighbors(&nearest, max_conn);

            // Bidirectional connections
            for &neighbor_idx in &selected {
                // node -> neighbor
                if l < self.nodes[node_idx].neighbors.len() {
                    self.nodes[node_idx].neighbors[l].push(neighbor_idx);
                }

                // neighbor -> node (ensure neighbor has layer allocated)
                while self.nodes[neighbor_idx].neighbors.len() <= l {
                    self.nodes[neighbor_idx].neighbors.push(Vec::new());
                }
                self.nodes[neighbor_idx].neighbors[l].push(node_idx);

                // Prune neighbor if over capacity
                if self.nodes[neighbor_idx].neighbors[l].len() > max_conn {
                    let neighbor_vec = self.nodes[neighbor_idx].vector.clone();
                    let mut scored: Vec<(f32, usize)> = self.nodes[neighbor_idx].neighbors[l]
                        .iter()
                        .map(|&n| {
                            let d = Self::distance(metric, &neighbor_vec, &self.nodes[n].vector);
                            (d, n)
                        })
                        .collect();
                    scored.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(Ordering::Equal));
                    self.nodes[neighbor_idx].neighbors[l] =
                        scored.iter().take(max_conn).map(|(_, idx)| *idx).collect();
                }
            }

            current_ep = nearest.iter().map(|(_, idx)| *idx).collect();
            if current_ep.is_empty() {
                current_ep = vec![ep];
            }
        }

        // Update entry point if new node has higher level
        if level > self.current_max_level {
            self.entry_point = Some(node_idx);
            self.current_max_level = level;
        }
    }

    /// Search the graph for k nearest neighbors.
    fn search(
        &self,
        query: &[f32],
        k: usize,
        ef_search: usize,
        metric: DistanceMetric,
    ) -> Vec<(f32, usize)> {
        let ep = match self.entry_point {
            Some(ep) => ep,
            None => return Vec::new(),
        };

        let mut current_ep = vec![ep];

        // Greedy descent from top layer to layer 1
        for l in (1..=self.current_max_level).rev() {
            let nearest = self.search_layer(query, &current_ep, 1, l, metric);
            if let Some(&(_, idx)) = nearest.first() {
                current_ep = vec![idx];
            }
        }

        // Beam search on layer 0
        let mut results = self.search_layer(query, &current_ep, ef_search.max(k), 0, metric);
        results.truncate(k);
        results
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// HNSW-indexed vector store.
///
/// Provides O(log n) approximate nearest neighbor search with configurable
/// recall/speed tradeoff via `ef_search`. Thread-safe: concurrent reads,
/// exclusive writes via `RwLock`.
pub struct HnswVectorStore {
    config: HnswConfig,
    dimension: usize,
    metric: DistanceMetric,
    graph: Arc<RwLock<Graph>>,
}

impl HnswVectorStore {
    /// Create a new HNSW vector store with custom configuration.
    pub fn new(dimension: usize, metric: DistanceMetric, config: HnswConfig) -> Self {
        Self {
            config,
            dimension,
            metric,
            graph: Arc::new(RwLock::new(Graph::new())),
        }
    }

    /// Create with default HNSW parameters (M=16, ef_construction=200, ef_search=64).
    pub fn with_defaults(dimension: usize, metric: DistanceMetric) -> Self {
        Self::new(dimension, metric, HnswConfig::default())
    }

    /// Get the number of non-deleted vectors in the index.
    pub fn len(&self) -> usize {
        let graph = self.graph.read().unwrap_or_else(|e| e.into_inner());
        graph.nodes.iter().filter(|n| !n.deleted).count()
    }

    /// Check if the index is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Get the current HNSW configuration.
    pub fn config(&self) -> &HnswConfig {
        &self.config
    }
}

#[async_trait]
impl VectorStore for HnswVectorStore {
    async fn upsert(&self, embedding: &Embedding) -> Result<(), VectorError> {
        if embedding.dim() != self.dimension {
            return Err(VectorError::DimensionMismatch {
                expected: self.dimension,
                actual: embedding.dim(),
            });
        }

        let mut graph = self.graph.write().map_err(|_| VectorError::LockPoisoned)?;
        graph.insert(
            embedding.id.clone(),
            embedding.vector.clone(),
            embedding.metadata.clone(),
            &self.config,
            self.metric,
        );
        Ok(())
    }

    async fn search(&self, query: &[f32], k: usize) -> Result<Vec<SearchResult>, VectorError> {
        if query.len() != self.dimension {
            return Err(VectorError::DimensionMismatch {
                expected: self.dimension,
                actual: query.len(),
            });
        }

        let graph = self.graph.read().map_err(|_| VectorError::LockPoisoned)?;
        let results = graph.search(query, k, self.config.ef_search, self.metric);

        Ok(results
            .into_iter()
            .map(|(dist, idx)| SearchResult {
                id: graph.nodes[idx].id.clone(),
                score: Graph::distance_to_score(self.metric, dist),
            })
            .collect())
    }

    async fn get(&self, id: &str) -> Result<Option<Embedding>, VectorError> {
        let graph = self.graph.read().map_err(|_| VectorError::LockPoisoned)?;
        Ok(graph.id_map.get(id).and_then(|&idx| {
            let node = &graph.nodes[idx];
            if node.deleted {
                None
            } else {
                Some(Embedding {
                    id: node.id.clone(),
                    vector: node.vector.clone(),
                    metadata: node.metadata.clone(),
                })
            }
        }))
    }

    async fn delete(&self, id: &str) -> Result<(), VectorError> {
        let mut graph = self.graph.write().map_err(|_| VectorError::LockPoisoned)?;
        if let Some(&idx) = graph.id_map.get(id) {
            graph.nodes[idx].deleted = true;
        }
        Ok(())
    }

    fn dimension(&self) -> usize {
        self.dimension
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_hnsw_basic_insert_and_search() {
        let store = HnswVectorStore::with_defaults(3, DistanceMetric::Cosine);

        let e1 = Embedding::new("e1", vec![1.0, 0.0, 0.0]);
        let e2 = Embedding::new("e2", vec![0.9, 0.1, 0.0]);
        let e3 = Embedding::new("e3", vec![0.0, 1.0, 0.0]);

        store.upsert(&e1).await.unwrap();
        store.upsert(&e2).await.unwrap();
        store.upsert(&e3).await.unwrap();

        let results = store.search(&[1.0, 0.0, 0.0], 2).await.unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].id, "e1");
        assert_eq!(results[1].id, "e2");
    }

    #[tokio::test]
    async fn test_hnsw_upsert_updates_vector() {
        let store = HnswVectorStore::with_defaults(3, DistanceMetric::Cosine);

        store
            .upsert(&Embedding::new("e1", vec![1.0, 0.0, 0.0]))
            .await
            .unwrap();
        store
            .upsert(&Embedding::new("e1", vec![0.0, 1.0, 0.0]))
            .await
            .unwrap();

        let emb = store.get("e1").await.unwrap().unwrap();
        assert_eq!(emb.vector, vec![0.0, 1.0, 0.0]);
    }

    #[tokio::test]
    async fn test_hnsw_delete() {
        let store = HnswVectorStore::with_defaults(3, DistanceMetric::Cosine);

        store
            .upsert(&Embedding::new("e1", vec![1.0, 0.0, 0.0]))
            .await
            .unwrap();
        store.delete("e1").await.unwrap();

        assert!(store.get("e1").await.unwrap().is_none());
        assert_eq!(store.len(), 0);
    }

    #[tokio::test]
    async fn test_hnsw_dimension_mismatch() {
        let store = HnswVectorStore::with_defaults(3, DistanceMetric::Cosine);
        let result = store
            .upsert(&Embedding::new("e1", vec![1.0, 0.0]))
            .await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_hnsw_euclidean() {
        let store = HnswVectorStore::with_defaults(2, DistanceMetric::Euclidean);

        store
            .upsert(&Embedding::new("origin", vec![0.0, 0.0]))
            .await
            .unwrap();
        store
            .upsert(&Embedding::new("near", vec![1.0, 0.0]))
            .await
            .unwrap();
        store
            .upsert(&Embedding::new("far", vec![10.0, 10.0]))
            .await
            .unwrap();

        let results = store.search(&[0.0, 0.0], 2).await.unwrap();
        assert_eq!(results[0].id, "origin");
        assert_eq!(results[1].id, "near");
    }

    #[tokio::test]
    async fn test_hnsw_dot_product() {
        let store = HnswVectorStore::with_defaults(3, DistanceMetric::DotProduct);

        store
            .upsert(&Embedding::new("high", vec![1.0, 1.0, 1.0]))
            .await
            .unwrap();
        store
            .upsert(&Embedding::new("low", vec![0.1, 0.1, 0.1]))
            .await
            .unwrap();

        let results = store.search(&[1.0, 1.0, 1.0], 2).await.unwrap();
        assert_eq!(results[0].id, "high");
        assert!(results[0].score > results[1].score);
    }

    #[tokio::test]
    async fn test_hnsw_many_vectors() {
        let dim = 32;
        let store = HnswVectorStore::with_defaults(dim, DistanceMetric::Cosine);

        for i in 0..200 {
            let mut vec = vec![0.0f32; dim];
            vec[i % dim] = 1.0;
            vec[(i * 7) % dim] += 0.5;
            store
                .upsert(&Embedding::new(format!("v{i}"), vec))
                .await
                .unwrap();
        }

        let results = store.search(&vec![1.0; dim], 10).await.unwrap();
        assert_eq!(results.len(), 10);

        // Scores should be monotonically non-increasing
        for w in results.windows(2) {
            assert!(w[0].score >= w[1].score);
        }
    }

    #[tokio::test]
    async fn test_hnsw_empty_search() {
        let store = HnswVectorStore::with_defaults(3, DistanceMetric::Cosine);
        let results = store.search(&[1.0, 0.0, 0.0], 5).await.unwrap();
        assert!(results.is_empty());
    }

    #[tokio::test]
    async fn test_hnsw_deleted_not_in_results() {
        let store = HnswVectorStore::with_defaults(3, DistanceMetric::Cosine);

        store
            .upsert(&Embedding::new("a", vec![1.0, 0.0, 0.0]))
            .await
            .unwrap();
        store
            .upsert(&Embedding::new("b", vec![0.9, 0.1, 0.0]))
            .await
            .unwrap();
        store
            .upsert(&Embedding::new("c", vec![0.0, 1.0, 0.0]))
            .await
            .unwrap();

        store.delete("a").await.unwrap();

        let results = store.search(&[1.0, 0.0, 0.0], 3).await.unwrap();
        assert!(!results.iter().any(|r| r.id == "a"));
        assert_eq!(results[0].id, "b");
    }
}
