// SPDX-License-Identifier: PMPL-1.0-or-later
//! Logical and physical plan types.

use serde::{Deserialize, Serialize};

use crate::cost::CostEstimate;
use crate::Modality;

/// Source of data for the query.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QuerySource {
    /// Query a single hexad store.
    Hexad,
    /// Federated query across multiple nodes.
    Federation { nodes: Vec<String> },
    /// Direct store access for a specific modality.
    Store { modality: Modality },
}

/// Kind of condition applied to a modality node.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConditionKind {
    /// Equality filter (field = value).
    Equality { field: String, value: String },
    /// Range filter (field BETWEEN low AND high).
    Range { field: String, low: String, high: String },
    /// Full-text search.
    Fulltext { query: String },
    /// Vector similarity (k-NN).
    Similarity { k: usize },
    /// Graph traversal.
    Traversal { predicate: String, depth: Option<u32> },
    /// Temporal version lookup.
    AtTime { timestamp: String },
    /// ZKP proof verification.
    ProofVerification { contract: String },
    /// Tensor operation.
    TensorOp { operation: String },
    /// Generic predicate.
    Predicate { expression: String },
}

/// A single modality node in a logical plan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanNode {
    /// Which modality this node queries.
    pub modality: Modality,
    /// Conditions/filters to apply.
    pub conditions: Vec<ConditionKind>,
    /// Fields to project (empty = all).
    pub projections: Vec<String>,
    /// Early limit pushed down to store.
    pub early_limit: Option<usize>,
}

/// Post-processing operation applied after modality queries.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PostProcessing {
    /// ORDER BY fields.
    OrderBy { fields: Vec<(String, bool)> },
    /// LIMIT result count.
    Limit { count: usize },
    /// GROUP BY + aggregation.
    GroupBy { fields: Vec<String>, aggregates: Vec<String> },
    /// Final projection.
    Project { columns: Vec<String> },
}

/// A logical plan — the unoptimized query representation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogicalPlan {
    /// Data source.
    pub source: QuerySource,
    /// Per-modality query nodes.
    pub nodes: Vec<PlanNode>,
    /// Post-processing steps.
    pub post_processing: Vec<PostProcessing>,
}

/// Execution strategy for the physical plan.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExecutionStrategy {
    Sequential,
    Parallel,
}

/// A single step in a physical plan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    /// Step number (1-indexed).
    pub step: usize,
    /// Operation description.
    pub operation: String,
    /// Target modality.
    pub modality: Modality,
    /// Cost estimate for this step.
    pub cost: CostEstimate,
    /// Optimization hint for this step.
    pub optimization_hint: Option<String>,
    /// Pushed-down predicates.
    pub pushed_predicates: Vec<String>,
}

/// An optimized physical plan ready for execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysicalPlan {
    /// Ordered execution steps.
    pub steps: Vec<PlanStep>,
    /// Overall execution strategy.
    pub strategy: ExecutionStrategy,
    /// Total estimated cost.
    pub total_cost: CostEstimate,
    /// Optimization notes.
    pub notes: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_logical_plan() -> LogicalPlan {
        LogicalPlan {
            source: QuerySource::Hexad,
            nodes: vec![
                PlanNode {
                    modality: Modality::Graph,
                    conditions: vec![ConditionKind::Traversal {
                        predicate: "relates_to".to_string(),
                        depth: Some(2),
                    }],
                    projections: vec!["id".to_string(), "label".to_string()],
                    early_limit: None,
                },
                PlanNode {
                    modality: Modality::Vector,
                    conditions: vec![ConditionKind::Similarity { k: 10 }],
                    projections: vec![],
                    early_limit: Some(50),
                },
            ],
            post_processing: vec![PostProcessing::Limit { count: 10 }],
        }
    }

    #[test]
    fn test_logical_plan_json_roundtrip() {
        let plan = sample_logical_plan();
        let json = serde_json::to_string(&plan).unwrap();
        let parsed: LogicalPlan = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.nodes.len(), 2);
        assert_eq!(parsed.nodes[0].modality, Modality::Graph);
        assert_eq!(parsed.nodes[1].modality, Modality::Vector);
    }

    #[test]
    fn test_physical_plan_json_roundtrip() {
        let plan = PhysicalPlan {
            steps: vec![PlanStep {
                step: 1,
                operation: "Vector similarity search".to_string(),
                modality: Modality::Vector,
                cost: CostEstimate {
                    time_ms: 50.0,
                    estimated_rows: 10,
                    selectivity: 0.01,
                    io_cost: 30.0,
                    cpu_cost: 20.0,
                },
                optimization_hint: Some("HNSW ANN".to_string()),
                pushed_predicates: vec!["k=10".to_string()],
            }],
            strategy: ExecutionStrategy::Sequential,
            total_cost: CostEstimate {
                time_ms: 50.0,
                estimated_rows: 10,
                selectivity: 0.01,
                io_cost: 30.0,
                cpu_cost: 20.0,
            },
            notes: vec!["Single modality — sequential execution".to_string()],
        };
        let json = serde_json::to_string(&plan).unwrap();
        let parsed: PhysicalPlan = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.steps.len(), 1);
        assert_eq!(parsed.strategy, ExecutionStrategy::Sequential);
    }

    #[test]
    fn test_query_source_variants() {
        let hexad = QuerySource::Hexad;
        let json = serde_json::to_string(&hexad).unwrap();
        assert!(json.contains("hexad"));

        let fed = QuerySource::Federation {
            nodes: vec!["node1".to_string()],
        };
        let json = serde_json::to_string(&fed).unwrap();
        assert!(json.contains("federation"));

        let store = QuerySource::Store {
            modality: Modality::Graph,
        };
        let json = serde_json::to_string(&store).unwrap();
        assert!(json.contains("store"));
    }
}
