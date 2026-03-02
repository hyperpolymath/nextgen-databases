// SPDX-License-Identifier: PMPL-1.0-or-later
//! Oxigraph-backed graph store.
//!
//! This module is only compiled when the `oxigraph-backend` feature is enabled.
//! It provides full RDF/SPARQL support via Oxigraph, but requires a C++ linker
//! for the transitive oxrocksdb-sys dependency.

use async_trait::async_trait;
use oxigraph::model::{GraphName, NamedNode, Quad, Subject, Term};
use oxigraph::store::Store;
use std::path::Path;

use crate::{GraphEdge, GraphError, GraphNode, GraphObject, GraphStore};

/// Oxigraph-backed graph store with full RDF/SPARQL support.
///
/// Requires the `oxigraph-backend` feature flag. Supports both in-memory and
/// persistent (RocksDB-backed) storage.
pub struct OxiGraphStore {
    store: Store,
}

impl OxiGraphStore {
    /// Create a new in-memory store
    pub fn in_memory() -> Result<Self, GraphError> {
        Ok(Self {
            store: Store::new().map_err(|e| GraphError::StoreError(e.to_string()))?,
        })
    }

    /// Open or create a persistent store (requires filesystem + C++ linker at build time)
    pub fn persistent(path: impl AsRef<Path>) -> Result<Self, GraphError> {
        Ok(Self {
            store: Store::open(path).map_err(|e| GraphError::StoreError(e.to_string()))?,
        })
    }

    /// Convert GraphEdge to Oxigraph Quad
    fn edge_to_quad(&self, edge: &GraphEdge) -> Result<Quad, GraphError> {
        let subject = Subject::NamedNode(
            NamedNode::new(&edge.subject.iri)
                .map_err(|e| GraphError::InvalidIri(e.to_string()))?,
        );
        let predicate = NamedNode::new(&edge.predicate.iri)
            .map_err(|e| GraphError::InvalidIri(e.to_string()))?;
        let object = match &edge.object {
            GraphObject::Node(n) => Term::NamedNode(
                NamedNode::new(&n.iri).map_err(|e| GraphError::InvalidIri(e.to_string()))?,
            ),
            GraphObject::Literal { value, datatype: _ } => {
                Term::Literal(oxigraph::model::Literal::new_simple_literal(value))
            }
        };
        Ok(Quad::new(subject, predicate, object, GraphName::DefaultGraph))
    }
}

#[async_trait]
impl GraphStore for OxiGraphStore {
    async fn insert(&self, edge: &GraphEdge) -> Result<(), GraphError> {
        let quad = self.edge_to_quad(edge)?;
        self.store.insert(&quad).map_err(|e| GraphError::StoreError(e.to_string()))?;
        Ok(())
    }

    async fn outgoing(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError> {
        let subject = NamedNode::new(&node.iri).map_err(|e| GraphError::InvalidIri(e.to_string()))?;
        let mut edges = Vec::new();

        for quad in self.store.quads_for_pattern(Some(subject.as_ref().into()), None, None, None) {
            let quad = quad.map_err(|e| GraphError::StoreError(e.to_string()))?;
            let predicate = GraphNode::new(quad.predicate.as_str());
            let object = match quad.object {
                Term::NamedNode(n) => GraphObject::Node(GraphNode::new(n.as_str())),
                Term::Literal(l) => GraphObject::Literal {
                    value: l.value().to_string(),
                    datatype: Some(l.datatype().as_str().to_string()),
                },
                _ => continue,
            };
            edges.push(GraphEdge {
                subject: node.clone(),
                predicate,
                object,
            });
        }
        Ok(edges)
    }

    async fn incoming(&self, node: &GraphNode) -> Result<Vec<GraphEdge>, GraphError> {
        let object = NamedNode::new(&node.iri).map_err(|e| GraphError::InvalidIri(e.to_string()))?;
        let mut edges = Vec::new();

        for quad in self.store.quads_for_pattern(None, None, Some(object.as_ref().into()), None) {
            let quad = quad.map_err(|e| GraphError::StoreError(e.to_string()))?;
            let subject = match quad.subject {
                Subject::NamedNode(n) => GraphNode::new(n.as_str()),
                _ => continue,
            };
            let predicate = GraphNode::new(quad.predicate.as_str());
            edges.push(GraphEdge {
                subject,
                predicate,
                object: GraphObject::Node(node.clone()),
            });
        }
        Ok(edges)
    }

    async fn exists(&self, edge: &GraphEdge) -> Result<bool, GraphError> {
        let quad = self.edge_to_quad(edge)?;
        self.store.contains(&quad).map_err(|e| GraphError::StoreError(e.to_string()))
    }

    async fn delete(&self, edge: &GraphEdge) -> Result<(), GraphError> {
        let quad = self.edge_to_quad(edge)?;
        self.store.remove(&quad).map_err(|e| GraphError::StoreError(e.to_string()))?;
        Ok(())
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

    #[tokio::test]
    async fn test_oxigraph_insert_and_query() {
        let store = OxiGraphStore::in_memory().unwrap();
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
}
