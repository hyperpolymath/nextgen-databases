// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Graph Modality
//!
//! RDF and property graph storage. Provides two backends:
//!
//! - **`SimpleGraphStore`** (default) — Pure Rust, in-memory HashMap/BTreeMap
//!   store. Zero C/C++ dependencies, builds on any platform without a C++ linker.
//!
//! - **`OxiGraphStore`** (feature: `oxigraph-backend`) — Full Oxigraph RDF store
//!   with SPARQL support. Requires C++ linker for the RocksDB transitive dependency.
//!
//! Implements Marr's Computational Level: "What relationships exist?"

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::RwLock;
use thiserror::Error;

// Re-export Oxigraph backend when feature is enabled
#[cfg(feature = "oxigraph-backend")]
mod oxigraph_backend;
#[cfg(feature = "oxigraph-backend")]
pub use oxigraph_backend::OxiGraphStore;

// Re-export redb backend when feature is enabled
#[cfg(feature = "redb-backend")]
mod redb_backend;
#[cfg(feature = "redb-backend")]
pub use redb_backend::RedbGraphStore;

/// Graph modality errors
#[derive(Error, Debug)]
pub enum GraphError {
    #[error("Store error: {0}")]
    StoreError(String),

    #[error("Parse error: {0}")]
    ParseError(String),

    #[error("Entity not found: {0}")]
    NotFound(String),

    #[error("Invalid IRI: {0}")]
    InvalidIri(String),

    #[error("Lock poisoned")]
    LockPoisoned,
}

/// A node in the graph (entity reference)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct GraphNode {
    /// IRI of the node
    pub iri: String,
    /// Local name (last segment of IRI)
    pub local_name: String,
}

impl GraphNode {
    /// Create a new graph node from an IRI
    pub fn new(iri: impl Into<String>) -> Self {
        let iri = iri.into();
        let local_name = iri
            .rsplit_once('/')
            .or_else(|| iri.rsplit_once('#'))
            .map(|(_, name)| name.to_string())
            .unwrap_or_else(|| iri.clone());
        Self { iri, local_name }
    }
}

/// An edge in the graph (relationship)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphEdge {
    /// Subject node
    pub subject: GraphNode,
    /// Predicate (relationship type)
    pub predicate: GraphNode,
    /// Object (target node or literal)
    pub object: GraphObject,
}

/// Object of a triple (can be node or literal)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GraphObject {
    Node(GraphNode),
    Literal { value: String, datatype: Option<String> },
}

/// Graph store trait for cross-modal consistency.
///
/// All graph backends implement this trait, allowing the hexad store to be
/// generic over the concrete backend.
#[async_trait]
pub trait GraphStore: Send + Sync {
    /// Insert a triple
    async fn insert(&self, edge: &GraphEdge) -> Result<(), GraphError>;

    /// Query outgoing edges from a node
    async fn outgoing(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError>;

    /// Query incoming edges to a node
    async fn incoming(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError>;

    /// Check if a triple exists
    async fn exists(&self, edge: &GraphEdge) -> Result<bool, GraphError>;

    /// Delete a triple
    async fn delete(&self, edge: &GraphEdge) -> Result<(), GraphError>;

    /// Get all nodes connected to a given node within N hops
    async fn neighborhood(&self, node: &GraphNode, hops: usize) -> Result<Vec<GraphNode>, GraphError>;
}

// ═══════════════════════════════════════════════════════════════════════════
// SimpleGraphStore — Pure Rust in-memory graph store
// ═══════════════════════════════════════════════════════════════════════════

/// A canonicalised triple key for deduplication and lookup.
///
/// Stores `(subject_iri, predicate_iri, object_key)` where `object_key` is
/// either the IRI for nodes or `"literal::<value>"` for literals.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct TripleKey(String, String, String);

impl TripleKey {
    fn from_edge(edge: &GraphEdge) -> Self {
        let obj_key = match &edge.object {
            GraphObject::Node(n) => n.iri.clone(),
            GraphObject::Literal { value, .. } => format!("literal::{}", value),
        };
        Self(edge.subject.iri.clone(), edge.predicate.iri.clone(), obj_key)
    }
}

/// Pure Rust in-memory graph store.
///
/// Uses HashMap indices for O(1) subject/object lookups and a HashSet for
/// deduplication. No external dependencies — builds on any platform.
///
/// Thread-safe via `RwLock` — concurrent reads, exclusive writes.
pub struct SimpleGraphStore {
    /// All edges stored as a set of triple keys → edge data
    edges: RwLock<HashMap<TripleKey, GraphEdge>>,
    /// Subject index: subject IRI → set of triple keys
    subject_idx: RwLock<HashMap<String, HashSet<TripleKey>>>,
    /// Object index: object IRI → set of triple keys (nodes only)
    object_idx: RwLock<HashMap<String, HashSet<TripleKey>>>,
}

impl SimpleGraphStore {
    /// Create a new empty in-memory graph store.
    pub fn new() -> Self {
        Self {
            edges: RwLock::new(HashMap::new()),
            subject_idx: RwLock::new(HashMap::new()),
            object_idx: RwLock::new(HashMap::new()),
        }
    }

    /// Create a new store — mirrors OxiGraphStore::in_memory() API for drop-in
    /// replacement.
    pub fn in_memory() -> Result<Self, GraphError> {
        Ok(Self::new())
    }
}

impl Default for SimpleGraphStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl GraphStore for SimpleGraphStore {
    async fn insert(&self, edge: &GraphEdge) -> Result<(), GraphError> {
        let key = TripleKey::from_edge(edge);

        // Update subject index
        self.subject_idx
            .write()
            .map_err(|_| GraphError::LockPoisoned)?
            .entry(edge.subject.iri.clone())
            .or_default()
            .insert(key.clone());

        // Update object index (nodes only)
        if let GraphObject::Node(n) = &edge.object {
            self.object_idx
                .write()
                .map_err(|_| GraphError::LockPoisoned)?
                .entry(n.iri.clone())
                .or_default()
                .insert(key.clone());
        }

        // Insert the edge
        self.edges
            .write()
            .map_err(|_| GraphError::LockPoisoned)?
            .insert(key, edge.clone());

        Ok(())
    }

    async fn outgoing(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError> {
        let subject_idx = self.subject_idx.read().map_err(|_| GraphError::LockPoisoned)?;
        let edges = self.edges.read().map_err(|_| GraphError::LockPoisoned)?;

        let result = match subject_idx.get(&node.iri) {
            Some(keys) => keys
                .iter()
                .filter_map(|k| edges.get(k).cloned())
                .collect(),
            None => Vec::new(),
        };

        Ok(result)
    }

    async fn incoming(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError> {
        let object_idx = self.object_idx.read().map_err(|_| GraphError::LockPoisoned)?;
        let edges = self.edges.read().map_err(|_| GraphError::LockPoisoned)?;

        let result = match object_idx.get(&node.iri) {
            Some(keys) => keys
                .iter()
                .filter_map(|k| edges.get(k).cloned())
                .collect(),
            None => Vec::new(),
        };

        Ok(result)
    }

    async fn exists(&self, edge: &GraphEdge) -> Result<bool, GraphError> {
        let key = TripleKey::from_edge(edge);
        let edges = self.edges.read().map_err(|_| GraphError::LockPoisoned)?;
        Ok(edges.contains_key(&key))
    }

    async fn delete(&self, edge: &GraphEdge) -> Result<(), GraphError> {
        let key = TripleKey::from_edge(edge);

        // Remove from subject index
        if let Ok(mut idx) = self.subject_idx.write() {
            if let Some(keys) = idx.get_mut(&edge.subject.iri) {
                keys.remove(&key);
                if keys.is_empty() {
                    idx.remove(&edge.subject.iri);
                }
            }
        }

        // Remove from object index
        if let GraphObject::Node(n) = &edge.object {
            if let Ok(mut idx) = self.object_idx.write() {
                if let Some(keys) = idx.get_mut(&n.iri) {
                    keys.remove(&key);
                    if keys.is_empty() {
                        idx.remove(&n.iri);
                    }
                }
            }
        }

        // Remove the edge
        self.edges
            .write()
            .map_err(|_| GraphError::LockPoisoned)?
            .remove(&key);

        Ok(())
    }

    async fn neighborhood(&self, node: &GraphNode, hops: usize) -> Result<Vec<GraphNode>, GraphError> {
        let mut visited = HashSet::new();
        let mut frontier = vec![node.clone()];
        visited.insert(node.iri.clone());

        for _ in 0..hops {
            let mut next_frontier = Vec::new();
            for current in frontier {
                for edge in self.outgoing(&current).await? {
                    if let GraphObject::Node(n) = edge.object {
                        if visited.insert(n.iri.clone()) {
                            next_frontier.push(n);
                        }
                    }
                }
                for edge in self.incoming(&current).await? {
                    if visited.insert(edge.subject.iri.clone()) {
                        next_frontier.push(edge.subject);
                    }
                }
            }
            frontier = next_frontier;
        }

        Ok(visited.into_iter().map(GraphNode::new).collect())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_insert_and_query() {
        let store = SimpleGraphStore::in_memory().unwrap();
        let edge = GraphEdge {
            subject: GraphNode::new("https://example.org/Alice"),
            predicate: GraphNode::new("https://example.org/knows"),
            object: GraphObject::Node(GraphNode::new("https://example.org/Bob")),
        };

        store.insert(&edge).await.unwrap();
        assert!(store.exists(&edge).await.unwrap());

        let outgoing = store.outgoing(&edge.subject).await.unwrap();
        assert_eq!(outgoing.len(), 1);
    }

    #[tokio::test]
    async fn test_incoming_edges() {
        let store = SimpleGraphStore::new();
        let edge = GraphEdge {
            subject: GraphNode::new("https://example.org/Alice"),
            predicate: GraphNode::new("https://example.org/knows"),
            object: GraphObject::Node(GraphNode::new("https://example.org/Bob")),
        };

        store.insert(&edge).await.unwrap();

        let bob = GraphNode::new("https://example.org/Bob");
        let incoming = store.incoming(&bob).await.unwrap();
        assert_eq!(incoming.len(), 1);
    }

    #[tokio::test]
    async fn test_delete_edge() {
        let store = SimpleGraphStore::new();
        let edge = GraphEdge {
            subject: GraphNode::new("https://example.org/Alice"),
            predicate: GraphNode::new("https://example.org/knows"),
            object: GraphObject::Node(GraphNode::new("https://example.org/Bob")),
        };

        store.insert(&edge).await.unwrap();
        assert!(store.exists(&edge).await.unwrap());

        store.delete(&edge).await.unwrap();
        assert!(!store.exists(&edge).await.unwrap());
    }

    #[tokio::test]
    async fn test_literal_object() {
        let store = SimpleGraphStore::new();
        let edge = GraphEdge {
            subject: GraphNode::new("https://example.org/Alice"),
            predicate: GraphNode::new("https://example.org/name"),
            object: GraphObject::Literal {
                value: "Alice".to_string(),
                datatype: Some("http://www.w3.org/2001/XMLSchema#string".to_string()),
            },
        };

        store.insert(&edge).await.unwrap();
        assert!(store.exists(&edge).await.unwrap());

        let outgoing = store.outgoing(&edge.subject).await.unwrap();
        assert_eq!(outgoing.len(), 1);
    }

    #[tokio::test]
    async fn test_neighborhood() {
        let store = SimpleGraphStore::new();

        // Alice -> Bob -> Carol
        let e1 = GraphEdge {
            subject: GraphNode::new("https://example.org/Alice"),
            predicate: GraphNode::new("https://example.org/knows"),
            object: GraphObject::Node(GraphNode::new("https://example.org/Bob")),
        };
        let e2 = GraphEdge {
            subject: GraphNode::new("https://example.org/Bob"),
            predicate: GraphNode::new("https://example.org/knows"),
            object: GraphObject::Node(GraphNode::new("https://example.org/Carol")),
        };

        store.insert(&e1).await.unwrap();
        store.insert(&e2).await.unwrap();

        let alice = GraphNode::new("https://example.org/Alice");

        // 1 hop: Alice, Bob
        let neighbors_1 = store.neighborhood(&alice, 1).await.unwrap();
        assert_eq!(neighbors_1.len(), 2);

        // 2 hops: Alice, Bob, Carol
        let neighbors_2 = store.neighborhood(&alice, 2).await.unwrap();
        assert_eq!(neighbors_2.len(), 3);
    }

    #[tokio::test]
    async fn test_deduplication() {
        let store = SimpleGraphStore::new();
        let edge = GraphEdge {
            subject: GraphNode::new("https://example.org/Alice"),
            predicate: GraphNode::new("https://example.org/knows"),
            object: GraphObject::Node(GraphNode::new("https://example.org/Bob")),
        };

        // Insert the same edge twice
        store.insert(&edge).await.unwrap();
        store.insert(&edge).await.unwrap();

        let outgoing = store.outgoing(&edge.subject).await.unwrap();
        assert_eq!(outgoing.len(), 1, "Duplicate edges should be deduplicated");
    }
}
