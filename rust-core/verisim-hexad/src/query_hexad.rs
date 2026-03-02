// SPDX-License-Identifier: PMPL-1.0-or-later
//! QueryHexad Builder — Creates a hexad from a VQL query.
//!
//! Homoiconicity: queries are data. A VQL query stored as a hexad has:
//! - **Document**: query text (searchable via full-text)
//! - **Graph**: parse tree as subject → predicate → object triples
//! - **Vector**: embedding of query text (for similarity search of past queries)
//! - **Tensor**: cost vector from execution plan
//! - **Semantic**: proof obligations as typed annotations
//! - **Temporal**: query execution history (when run, what results)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::{HexadId, HexadInput, HexadDocumentInput, HexadVectorInput,
            HexadGraphInput, HexadTensorInput, HexadSemanticInput};

/// Metadata about a query execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryExecution {
    /// When the query was executed
    pub executed_at: DateTime<Utc>,
    /// Duration in milliseconds
    pub duration_ms: u64,
    /// Number of results returned
    pub result_count: usize,
    /// Execution plan cost estimate
    pub estimated_cost: f64,
}

/// A builder for creating hexads from VQL queries
#[derive(Debug)]
pub struct QueryHexadBuilder {
    query_text: String,
    query_id: Option<String>,
    parse_tree_triples: Vec<(String, String, String)>,
    embedding: Option<Vec<f32>>,
    cost_vector: Option<Vec<f64>>,
    proof_obligations: Vec<String>,
    executions: Vec<QueryExecution>,
    metadata: HashMap<String, String>,
}

impl QueryHexadBuilder {
    /// Create a new builder from a VQL query string
    pub fn new(query_text: impl Into<String>) -> Self {
        Self {
            query_text: query_text.into(),
            query_id: None,
            parse_tree_triples: Vec::new(),
            embedding: None,
            cost_vector: None,
            proof_obligations: Vec::new(),
            executions: Vec::new(),
            metadata: HashMap::new(),
        }
    }

    /// Set the query ID (defaults to auto-generated)
    pub fn with_id(mut self, id: impl Into<String>) -> Self {
        self.query_id = Some(id.into());
        self
    }

    /// Add parse tree triples (AST as RDF: subject → predicate → object)
    pub fn with_parse_tree(mut self, triples: Vec<(String, String, String)>) -> Self {
        self.parse_tree_triples = triples;
        self
    }

    /// Set the query embedding vector (for similarity search)
    pub fn with_embedding(mut self, embedding: Vec<f32>) -> Self {
        self.embedding = Some(embedding);
        self
    }

    /// Set the execution plan cost vector
    pub fn with_cost_vector(mut self, costs: Vec<f64>) -> Self {
        self.cost_vector = Some(costs);
        self
    }

    /// Add proof obligations from the query
    pub fn with_proof_obligations(mut self, obligations: Vec<String>) -> Self {
        self.proof_obligations = obligations;
        self
    }

    /// Record a query execution
    pub fn with_execution(mut self, execution: QueryExecution) -> Self {
        self.executions.push(execution);
        self
    }

    /// Add metadata
    pub fn with_metadata(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.metadata.insert(key.into(), value.into());
        self
    }

    /// Build the HexadInput for storage
    pub fn build(self) -> (HexadId, HexadInput) {
        let id = self.query_id.unwrap_or_else(|| {
            format!("query-{}", uuid::Uuid::new_v4())
        });

        let mut input = HexadInput::default();

        // Document modality: query text (searchable)
        input.document = Some(HexadDocumentInput {
            title: format!("VQL Query: {}", truncate(&self.query_text, 80)),
            body: self.query_text.clone(),
            fields: {
                let mut fields = HashMap::new();
                fields.insert("type".to_string(), "vql_query".to_string());
                fields.insert("query_text".to_string(), self.query_text);
                if !self.executions.is_empty() {
                    fields.insert(
                        "last_executed".to_string(),
                        self.executions.last().unwrap().executed_at.to_rfc3339(),
                    );
                    fields.insert(
                        "execution_count".to_string(),
                        self.executions.len().to_string(),
                    );
                }
                fields
            },
        });

        // Graph modality: parse tree as relationships
        if !self.parse_tree_triples.is_empty() {
            input.graph = Some(HexadGraphInput {
                relationships: self
                    .parse_tree_triples
                    .into_iter()
                    .map(|(_, predicate, object)| (predicate, object))
                    .collect(),
            });
        }

        // Vector modality: embedding of query text
        if let Some(embedding) = self.embedding {
            input.vector = Some(HexadVectorInput {
                embedding,
                model: Some("query-embedding".to_string()),
            });
        }

        // Tensor modality: cost vector from execution plan
        if let Some(costs) = self.cost_vector {
            let len = costs.len();
            input.tensor = Some(HexadTensorInput {
                shape: vec![1, len],
                data: costs,
            });
        }

        // Semantic modality: proof obligations as type annotations
        if !self.proof_obligations.is_empty() {
            input.semantic = Some(HexadSemanticInput {
                types: self.proof_obligations,
                properties: HashMap::new(),
            });
        }

        // Metadata
        input.metadata = self.metadata;

        (HexadId::new(id), input)
    }
}

/// Truncate a string to max_len characters with ellipsis
fn truncate(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}...", &s[..max_len.saturating_sub(3)])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_query_hexad() {
        let (id, input) = QueryHexadBuilder::new("SELECT * FROM hexads WHERE drift > 0.5")
            .with_id("query-001")
            .with_embedding(vec![0.1, 0.2, 0.3])
            .with_cost_vector(vec![1.0, 0.5, 0.3])
            .with_proof_obligations(vec!["verisim:DriftQuery".to_string()])
            .with_execution(QueryExecution {
                executed_at: Utc::now(),
                duration_ms: 42,
                result_count: 5,
                estimated_cost: 1.8,
            })
            .with_metadata("user", "test-user")
            .build();

        assert_eq!(id.0, "query-001");
        assert!(input.document.is_some());
        assert!(input.vector.is_some());
        assert!(input.tensor.is_some());
        assert!(input.semantic.is_some());

        let doc = input.document.unwrap();
        assert!(doc.title.starts_with("VQL Query:"));
        assert!(doc.body.contains("drift"));
    }

    #[test]
    fn test_auto_id_generation() {
        let (id, _input) = QueryHexadBuilder::new("SELECT 1").build();
        assert!(id.0.starts_with("query-"));
    }

    #[test]
    fn test_minimal_query_hexad() {
        let (_, input) = QueryHexadBuilder::new("REFLECT").build();
        assert!(input.document.is_some());
        assert!(input.vector.is_none());
        assert!(input.tensor.is_none());
    }
}
