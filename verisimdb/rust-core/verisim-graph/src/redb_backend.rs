// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// redb-backed persistent graph store.
//
// This module is only compiled when the `redb-backend` feature is enabled.
// It provides durable graph triple storage using redb (pure Rust, B-tree, ACID,
// single-file database). No C/C++ dependencies — builds on any platform with a
// Rust toolchain.
//
// # Storage Design
//
// Three redb tables store the graph:
//
// 1. **`triples`** — Primary triple store.
//    Key: `"{subject}\0{predicate}\0{object_key}"` (null-separated composite key)
//    Value: JSON-serialised `GraphEdge`
//
// 2. **`subject_idx`** — Subject index for outgoing edge lookups.
//    Key: `"{subject_iri}\0{triple_key}"` (composite for prefix scanning)
//    Value: empty (`&[u8]` — presence in index is sufficient)
//
// 3. **`object_idx`** — Object index for incoming edge lookups (node objects only).
//    Key: `"{object_iri}\0{triple_key}"` (composite for prefix scanning)
//    Value: empty
//
// This design uses redb's efficient `range()` with prefix scanning for
// O(log n) subject/object lookups rather than MultimapTable, which avoids
// the complexity of value deduplication.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use async_trait::async_trait;
use redb::{Database, ReadableDatabase, TableDefinition};
use serde_json;

use crate::{GraphEdge, GraphError, GraphNode, GraphObject, GraphStore};

/// Primary triple store: composite triple key → serialised GraphEdge.
const TRIPLES: TableDefinition<&[u8], &[u8]> = TableDefinition::new("triples");

/// Subject index: `"{subject_iri}\0{triple_key}"` → empty value.
const SUBJECT_IDX: TableDefinition<&[u8], &[u8]> = TableDefinition::new("subject_idx");

/// Object index: `"{object_iri}\0{triple_key}"` → empty value.
const OBJECT_IDX: TableDefinition<&[u8], &[u8]> = TableDefinition::new("object_idx");

/// Separator byte for composite keys (null byte — not valid in IRIs).
const SEP: u8 = 0x00;

/// A persistent graph store backed by redb.
///
/// Provides the same `GraphStore` interface as `SimpleGraphStore` (in-memory)
/// and `OxiGraphStore` (Oxigraph), but with durable on-disk storage via a
/// pure-Rust B-tree database. No C/C++ dependencies.
///
/// Thread-safe: `Database` is `Send + Sync` with internal locking.
///
/// # Example
///
/// ```rust,ignore
/// use verisim_graph::{RedbGraphStore, GraphStore, GraphEdge, GraphNode, GraphObject};
///
/// let store = RedbGraphStore::persistent("/tmp/graph-test.redb").unwrap();
///
/// let edge = GraphEdge {
///     subject: GraphNode::new("https://example.org/Alice"),
///     predicate: GraphNode::new("https://example.org/knows"),
///     object: GraphObject::Node(GraphNode::new("https://example.org/Bob")),
/// };
///
/// store.insert(&edge).await.unwrap();
/// let outgoing = store.outgoing(&edge.subject).await.unwrap();
/// assert_eq!(outgoing.len(), 1);
/// ```
pub struct RedbGraphStore {
    db: Arc<Database>,
    #[allow(dead_code)]
    path: PathBuf,
}

impl RedbGraphStore {
    /// Open or create a persistent graph store at the given path.
    pub fn persistent(path: impl AsRef<Path>) -> Result<Self, GraphError> {
        let path = path.as_ref().to_path_buf();

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| GraphError::StoreError(format!("create dirs: {e}")))?;
        }

        let db = Database::create(&path)
            .map_err(|e| GraphError::StoreError(format!("open redb: {e}")))?;

        Ok(Self {
            db: Arc::new(db),
            path,
        })
    }

    /// Build a composite triple key from an edge: `"{subject}\0{predicate}\0{object_key}"`.
    fn triple_key(edge: &GraphEdge) -> Vec<u8> {
        let obj_key = match &edge.object {
            GraphObject::Node(n) => n.iri.as_bytes().to_vec(),
            GraphObject::Literal { value, .. } => {
                let mut k = b"literal::".to_vec();
                k.extend_from_slice(value.as_bytes());
                k
            }
        };
        let mut key = Vec::with_capacity(
            edge.subject.iri.len() + edge.predicate.iri.len() + obj_key.len() + 2,
        );
        key.extend_from_slice(edge.subject.iri.as_bytes());
        key.push(SEP);
        key.extend_from_slice(edge.predicate.iri.as_bytes());
        key.push(SEP);
        key.extend_from_slice(&obj_key);
        key
    }

    /// Build a subject-index key: `"{subject_iri}\0{triple_key}"`.
    fn subject_index_key(subject_iri: &str, triple_key: &[u8]) -> Vec<u8> {
        let mut key = Vec::with_capacity(subject_iri.len() + 1 + triple_key.len());
        key.extend_from_slice(subject_iri.as_bytes());
        key.push(SEP);
        key.extend_from_slice(triple_key);
        key
    }

    /// Build an object-index key: `"{object_iri}\0{triple_key}"`.
    fn object_index_key(object_iri: &str, triple_key: &[u8]) -> Vec<u8> {
        let mut key = Vec::with_capacity(object_iri.len() + 1 + triple_key.len());
        key.extend_from_slice(object_iri.as_bytes());
        key.push(SEP);
        key.extend_from_slice(triple_key);
        key
    }

    /// Build a prefix for scanning all entries for a given IRI: `"{iri}\0"`.
    fn iri_prefix(iri: &str) -> Vec<u8> {
        let mut prefix = Vec::with_capacity(iri.len() + 1);
        prefix.extend_from_slice(iri.as_bytes());
        prefix.push(SEP);
        prefix
    }

    /// Deserialise a GraphEdge from JSON bytes.
    fn deserialise_edge(bytes: &[u8]) -> Result<GraphEdge, GraphError> {
        serde_json::from_slice(bytes)
            .map_err(|e| GraphError::StoreError(format!("deserialise edge: {e}")))
    }

    /// Serialise a GraphEdge to JSON bytes.
    fn serialise_edge(edge: &GraphEdge) -> Result<Vec<u8>, GraphError> {
        serde_json::to_vec(edge)
            .map_err(|e| GraphError::StoreError(format!("serialise edge: {e}")))
    }

    /// Scan an index table for all triple keys matching a given IRI prefix,
    /// then look up the corresponding edges in the triples table.
    fn scan_index_for_edges(
        db: &Database,
        index_table: TableDefinition<&[u8], &[u8]>,
        iri: &str,
    ) -> Result<Vec<GraphEdge>, GraphError> {
        let txn = db.begin_read().map_err(|e| GraphError::StoreError(format!("read txn: {e}")))?;

        let idx = match txn.open_table(index_table) {
            Ok(t) => t,
            Err(_) => return Ok(Vec::new()),
        };

        let triples = match txn.open_table(TRIPLES) {
            Ok(t) => t,
            Err(_) => return Ok(Vec::new()),
        };

        let prefix = Self::iri_prefix(iri);
        let iter = idx.range(prefix.as_slice()..).map_err(|e| {
            GraphError::StoreError(format!("index scan: {e}"))
        })?;

        let mut edges = Vec::new();
        for entry in iter {
            let entry = entry.map_err(|e| GraphError::StoreError(format!("index entry: {e}")))?;
            let idx_key = entry.0.value();

            // Stop when keys no longer match the IRI prefix
            if !idx_key.starts_with(&prefix) {
                break;
            }

            // Extract the triple key from the index key (after the first separator)
            let triple_key = &idx_key[prefix.len()..];

            // Look up the edge in the triples table
            if let Some(edge_bytes) = triples.get(triple_key).map_err(|e| {
                GraphError::StoreError(format!("triple lookup: {e}"))
            })? {
                edges.push(Self::deserialise_edge(edge_bytes.value())?);
            }
        }

        Ok(edges)
    }
}

#[async_trait]
impl GraphStore for RedbGraphStore {
    async fn insert(&self, edge: &GraphEdge) -> Result<(), GraphError> {
        let db = Arc::clone(&self.db);
        let edge = edge.clone();

        tokio::task::spawn_blocking(move || -> Result<(), GraphError> {
            let tkey = Self::triple_key(&edge);
            let edge_bytes = Self::serialise_edge(&edge)?;

            let txn = db.begin_write().map_err(|e| {
                GraphError::StoreError(format!("write txn: {e}"))
            })?;

            {
                // Insert the triple
                let mut triples = txn.open_table(TRIPLES).map_err(|e| {
                    GraphError::StoreError(format!("open triples: {e}"))
                })?;
                triples.insert(tkey.as_slice(), edge_bytes.as_slice()).map_err(|e| {
                    GraphError::StoreError(format!("insert triple: {e}"))
                })?;
            }

            {
                // Update subject index
                let mut subject_idx = txn.open_table(SUBJECT_IDX).map_err(|e| {
                    GraphError::StoreError(format!("open subject_idx: {e}"))
                })?;
                let skey = Self::subject_index_key(&edge.subject.iri, &tkey);
                subject_idx.insert(skey.as_slice(), &[] as &[u8]).map_err(|e| {
                    GraphError::StoreError(format!("insert subject_idx: {e}"))
                })?;
            }

            {
                // Update object index (node objects only)
                if let GraphObject::Node(n) = &edge.object {
                    let mut object_idx = txn.open_table(OBJECT_IDX).map_err(|e| {
                        GraphError::StoreError(format!("open object_idx: {e}"))
                    })?;
                    let okey = Self::object_index_key(&n.iri, &tkey);
                    object_idx.insert(okey.as_slice(), &[] as &[u8]).map_err(|e| {
                        GraphError::StoreError(format!("insert object_idx: {e}"))
                    })?;
                }
            }

            txn.commit().map_err(|e| {
                GraphError::StoreError(format!("commit: {e}"))
            })?;

            Ok(())
        })
        .await
        .map_err(|e| GraphError::StoreError(format!("task join: {e}")))?
    }

    async fn outgoing(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError> {
        let db = Arc::clone(&self.db);
        let iri = node.iri.clone();

        tokio::task::spawn_blocking(move || {
            Self::scan_index_for_edges(&db, SUBJECT_IDX, &iri)
        })
        .await
        .map_err(|e| GraphError::StoreError(format!("task join: {e}")))?
    }

    async fn incoming(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError> {
        let db = Arc::clone(&self.db);
        let iri = node.iri.clone();

        tokio::task::spawn_blocking(move || {
            Self::scan_index_for_edges(&db, OBJECT_IDX, &iri)
        })
        .await
        .map_err(|e| GraphError::StoreError(format!("task join: {e}")))?
    }

    async fn exists(&self, edge: &GraphEdge) -> Result<bool, GraphError> {
        let db = Arc::clone(&self.db);
        let tkey = Self::triple_key(edge);

        tokio::task::spawn_blocking(move || -> Result<bool, GraphError> {
            let txn = db.begin_read().map_err(|e| {
                GraphError::StoreError(format!("read txn: {e}"))
            })?;

            let table = match txn.open_table(TRIPLES) {
                Ok(t) => t,
                Err(_) => return Ok(false),
            };

            match table.get(tkey.as_slice()) {
                Ok(Some(_)) => Ok(true),
                Ok(None) => Ok(false),
                Err(e) => Err(GraphError::StoreError(format!("exists check: {e}"))),
            }
        })
        .await
        .map_err(|e| GraphError::StoreError(format!("task join: {e}")))?
    }

    async fn delete(&self, edge: &GraphEdge) -> Result<(), GraphError> {
        let db = Arc::clone(&self.db);
        let edge = edge.clone();

        tokio::task::spawn_blocking(move || -> Result<(), GraphError> {
            let tkey = Self::triple_key(&edge);

            let txn = db.begin_write().map_err(|e| {
                GraphError::StoreError(format!("write txn: {e}"))
            })?;

            {
                // Remove from triples table
                let mut triples = txn.open_table(TRIPLES).map_err(|e| {
                    GraphError::StoreError(format!("open triples: {e}"))
                })?;
                triples.remove(tkey.as_slice()).map_err(|e| {
                    GraphError::StoreError(format!("remove triple: {e}"))
                })?;
            }

            {
                // Remove from subject index
                let mut subject_idx = txn.open_table(SUBJECT_IDX).map_err(|e| {
                    GraphError::StoreError(format!("open subject_idx: {e}"))
                })?;
                let skey = Self::subject_index_key(&edge.subject.iri, &tkey);
                subject_idx.remove(skey.as_slice()).map_err(|e| {
                    GraphError::StoreError(format!("remove subject_idx: {e}"))
                })?;
            }

            {
                // Remove from object index (node objects only)
                if let GraphObject::Node(n) = &edge.object {
                    let mut object_idx = txn.open_table(OBJECT_IDX).map_err(|e| {
                        GraphError::StoreError(format!("open object_idx: {e}"))
                    })?;
                    let okey = Self::object_index_key(&n.iri, &tkey);
                    object_idx.remove(okey.as_slice()).map_err(|e| {
                        GraphError::StoreError(format!("remove object_idx: {e}"))
                    })?;
                }
            }

            txn.commit().map_err(|e| {
                GraphError::StoreError(format!("commit: {e}"))
            })?;

            Ok(())
        })
        .await
        .map_err(|e| GraphError::StoreError(format!("task join: {e}")))?
    }

    async fn neighborhood(&self, node: &GraphNode, hops: usize) -> Result<Vec<GraphNode>, GraphError> {
        use std::collections::HashSet;

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

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn temp_store() -> (RedbGraphStore, tempfile::TempDir) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("graph-test.redb");
        let store = RedbGraphStore::persistent(&path).unwrap();
        (store, dir)
    }

    fn test_edge(subject: &str, predicate: &str, object: &str) -> GraphEdge {
        GraphEdge {
            subject: GraphNode::new(subject),
            predicate: GraphNode::new(predicate),
            object: GraphObject::Node(GraphNode::new(object)),
        }
    }

    #[tokio::test]
    async fn test_insert_and_exists() {
        let (store, _dir) = temp_store();
        let edge = test_edge(
            "https://example.org/Alice",
            "https://example.org/knows",
            "https://example.org/Bob",
        );

        assert!(!store.exists(&edge).await.unwrap());
        store.insert(&edge).await.unwrap();
        assert!(store.exists(&edge).await.unwrap());
    }

    #[tokio::test]
    async fn test_outgoing_edges() {
        let (store, _dir) = temp_store();

        let e1 = test_edge(
            "https://example.org/Alice",
            "https://example.org/knows",
            "https://example.org/Bob",
        );
        let e2 = test_edge(
            "https://example.org/Alice",
            "https://example.org/likes",
            "https://example.org/Carol",
        );
        let e3 = test_edge(
            "https://example.org/Bob",
            "https://example.org/knows",
            "https://example.org/Carol",
        );

        store.insert(&e1).await.unwrap();
        store.insert(&e2).await.unwrap();
        store.insert(&e3).await.unwrap();

        let alice = GraphNode::new("https://example.org/Alice");
        let outgoing = store.outgoing(&alice).await.unwrap();
        assert_eq!(outgoing.len(), 2);
    }

    #[tokio::test]
    async fn test_incoming_edges() {
        let (store, _dir) = temp_store();

        let e1 = test_edge(
            "https://example.org/Alice",
            "https://example.org/knows",
            "https://example.org/Bob",
        );
        let e2 = test_edge(
            "https://example.org/Carol",
            "https://example.org/knows",
            "https://example.org/Bob",
        );

        store.insert(&e1).await.unwrap();
        store.insert(&e2).await.unwrap();

        let bob = GraphNode::new("https://example.org/Bob");
        let incoming = store.incoming(&bob).await.unwrap();
        assert_eq!(incoming.len(), 2);
    }

    #[tokio::test]
    async fn test_delete_edge() {
        let (store, _dir) = temp_store();
        let edge = test_edge(
            "https://example.org/Alice",
            "https://example.org/knows",
            "https://example.org/Bob",
        );

        store.insert(&edge).await.unwrap();
        assert!(store.exists(&edge).await.unwrap());

        store.delete(&edge).await.unwrap();
        assert!(!store.exists(&edge).await.unwrap());

        // Verify indices are cleaned up
        let alice = GraphNode::new("https://example.org/Alice");
        let outgoing = store.outgoing(&alice).await.unwrap();
        assert_eq!(outgoing.len(), 0);
    }

    #[tokio::test]
    async fn test_literal_object() {
        let (store, _dir) = temp_store();
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

        // Literals should NOT appear in the object index
        let alice_node = GraphNode::new("Alice");
        let incoming = store.incoming(&alice_node).await.unwrap();
        assert_eq!(incoming.len(), 0);
    }

    #[tokio::test]
    async fn test_neighborhood() {
        let (store, _dir) = temp_store();

        // Alice -> Bob -> Carol
        let e1 = test_edge(
            "https://example.org/Alice",
            "https://example.org/knows",
            "https://example.org/Bob",
        );
        let e2 = test_edge(
            "https://example.org/Bob",
            "https://example.org/knows",
            "https://example.org/Carol",
        );

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
        let (store, _dir) = temp_store();
        let edge = test_edge(
            "https://example.org/Alice",
            "https://example.org/knows",
            "https://example.org/Bob",
        );

        // Insert the same edge twice
        store.insert(&edge).await.unwrap();
        store.insert(&edge).await.unwrap();

        let outgoing = store.outgoing(&edge.subject).await.unwrap();
        assert_eq!(outgoing.len(), 1, "Duplicate edges should be deduplicated");
    }

    #[tokio::test]
    async fn test_persistence_across_reopen() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("persist-test.redb");

        let edge = test_edge(
            "https://example.org/Alice",
            "https://example.org/knows",
            "https://example.org/Bob",
        );

        // Write and drop
        {
            let store = RedbGraphStore::persistent(&path).unwrap();
            store.insert(&edge).await.unwrap();
        }

        // Reopen and verify
        {
            let store = RedbGraphStore::persistent(&path).unwrap();
            assert!(store.exists(&edge).await.unwrap());
            let outgoing = store.outgoing(&edge.subject).await.unwrap();
            assert_eq!(outgoing.len(), 1);
        }
    }
}
