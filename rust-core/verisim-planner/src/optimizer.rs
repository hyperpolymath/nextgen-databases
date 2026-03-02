// SPDX-License-Identifier: PMPL-1.0-or-later
//! Query optimizer — transforms logical plans into physical plans.

use tracing::debug;

use crate::config::PlannerConfig;
use crate::cost::{CostEstimate, CostModel};
use crate::error::PlannerError;
use crate::explain::ExplainOutput;
use crate::plan::{ExecutionStrategy, LogicalPlan, PhysicalPlan, PlanStep};
use crate::stats::StatisticsCollector;

/// The query planner/optimizer.
///
/// Transforms a `LogicalPlan` into an optimized `PhysicalPlan` by:
/// 1. Estimating cost per modality node
/// 2. Reordering by execution priority + cost
/// 3. Selecting sequential vs parallel strategy
/// 4. Generating optimization hints
pub struct Planner {
    config: PlannerConfig,
    stats: StatisticsCollector,
}

impl Planner {
    /// Create a new planner with the given configuration.
    pub fn new(config: PlannerConfig) -> Self {
        Self {
            config,
            stats: StatisticsCollector::new(),
        }
    }

    /// Get a reference to the current configuration.
    pub fn config(&self) -> &PlannerConfig {
        &self.config
    }

    /// Update the planner configuration.
    pub fn set_config(&mut self, config: PlannerConfig) {
        self.config = config;
    }

    /// Get a reference to the statistics collector.
    pub fn stats(&self) -> &StatisticsCollector {
        &self.stats
    }

    /// Get a mutable reference to the statistics collector.
    pub fn stats_mut(&mut self) -> &mut StatisticsCollector {
        &mut self.stats
    }

    /// Optimize a logical plan into a physical plan.
    pub fn optimize(&self, logical: &LogicalPlan) -> Result<PhysicalPlan, PlannerError> {
        if logical.nodes.is_empty() {
            return Err(PlannerError::EmptyPlan);
        }

        debug!(
            node_count = logical.nodes.len(),
            "Optimizing logical plan"
        );

        // 1. Estimate cost for each node
        let mut node_costs: Vec<(usize, CostEstimate, Option<String>)> = logical
            .nodes
            .iter()
            .enumerate()
            .map(|(i, node)| {
                let stats = self.stats.get(node.modality);
                let cost = CostModel::estimate(node, &self.config, stats);
                let hint = CostModel::optimization_hint(node);
                (i, cost, hint)
            })
            .collect();

        // 2. Sort by execution priority first, then by total cost within same priority
        node_costs.sort_by(|a, b| {
            let pri_a = logical.nodes[a.0].modality.execution_priority();
            let pri_b = logical.nodes[b.0].modality.execution_priority();
            pri_a
                .cmp(&pri_b)
                .then_with(|| a.1.time_ms.partial_cmp(&b.1.time_ms).unwrap_or(std::cmp::Ordering::Equal))
        });

        // 3. Select execution strategy
        let strategy = if logical.nodes.len() >= self.config.parallel_threshold {
            ExecutionStrategy::Parallel
        } else {
            ExecutionStrategy::Sequential
        };

        // 4. Build physical plan steps
        let mut steps = Vec::with_capacity(node_costs.len());
        let mut cost_estimates = Vec::with_capacity(node_costs.len());
        let mut notes = Vec::new();

        for (step_num, &(node_idx, ref cost, ref hint)) in node_costs.iter().enumerate() {
            let node = &logical.nodes[node_idx];

            let operation = format!(
                "{} {}",
                match node.modality {
                    crate::Modality::Graph => "Graph traversal",
                    crate::Modality::Vector => "Vector similarity search",
                    crate::Modality::Tensor => "Tensor computation",
                    crate::Modality::Semantic => "Semantic verification",
                    crate::Modality::Document => "Document fulltext search",
                    crate::Modality::Temporal => "Temporal version lookup",
                },
                if node.conditions.is_empty() {
                    "(scan)".to_string()
                } else {
                    format!("({} conditions)", node.conditions.len())
                }
            );

            let pushed_predicates: Vec<String> = node
                .conditions
                .iter()
                .map(|c| format!("{:?}", c))
                .collect();

            steps.push(PlanStep {
                step: step_num + 1,
                operation,
                modality: node.modality,
                cost: cost.clone(),
                optimization_hint: hint.clone(),
                pushed_predicates,
            });

            cost_estimates.push(cost.clone());
        }

        // 5. Combine total cost (modality queries + post-processing)
        let is_parallel = strategy == ExecutionStrategy::Parallel;
        let modality_cost = CostEstimate::combine(&cost_estimates, is_parallel);
        let total_cost = CostModel::estimate_with_post_processing(
            &modality_cost,
            &logical.post_processing,
        );

        // 6. Generate optimization notes
        if is_parallel {
            notes.push(format!(
                "Parallel execution across {} modalities",
                steps.len()
            ));
        } else {
            notes.push("Sequential execution — single modality".to_string());
        }

        if total_cost.time_ms > 500.0 {
            notes.push("High estimated cost — consider adding LIMIT or more selective predicates".to_string());
        }

        // Check if any step has poor selectivity
        for step in &steps {
            if step.cost.selectivity > 0.5 && step.cost.time_ms > 100.0 {
                notes.push(format!(
                    "Step {}: {} has high selectivity ({:.0}%) — may benefit from additional predicates",
                    step.step,
                    step.modality,
                    step.cost.selectivity * 100.0
                ));
            }
        }

        Ok(PhysicalPlan {
            steps,
            strategy,
            total_cost,
            notes,
        })
    }

    /// Generate an EXPLAIN output for a logical plan.
    pub fn explain(&self, logical: &LogicalPlan) -> Result<ExplainOutput, PlannerError> {
        let physical = self.optimize(logical)?;
        Ok(ExplainOutput::from_physical_plan(&physical, &self.config))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plan::{ConditionKind, LogicalPlan, PlanNode, QuerySource};
    use crate::Modality;

    fn graph_vector_plan() -> LogicalPlan {
        LogicalPlan {
            source: QuerySource::Hexad,
            nodes: vec![
                PlanNode {
                    modality: Modality::Graph,
                    conditions: vec![ConditionKind::Traversal {
                        predicate: "relates_to".to_string(),
                        depth: Some(2),
                    }],
                    projections: vec![],
                    early_limit: None,
                },
                PlanNode {
                    modality: Modality::Vector,
                    conditions: vec![ConditionKind::Similarity { k: 10 }],
                    projections: vec![],
                    early_limit: None,
                },
            ],
            post_processing: vec![],
        }
    }

    #[test]
    fn test_single_modality_sequential() {
        let planner = Planner::new(PlannerConfig::default());
        let plan = LogicalPlan {
            source: QuerySource::Hexad,
            nodes: vec![PlanNode {
                modality: Modality::Document,
                conditions: vec![ConditionKind::Fulltext {
                    query: "test".to_string(),
                }],
                projections: vec![],
                early_limit: None,
            }],
            post_processing: vec![],
        };

        let physical = planner.optimize(&plan).unwrap();
        assert_eq!(physical.strategy, ExecutionStrategy::Sequential);
        assert_eq!(physical.steps.len(), 1);
    }

    #[test]
    fn test_multi_modality_parallel() {
        let planner = Planner::new(PlannerConfig::default());
        let physical = planner.optimize(&graph_vector_plan()).unwrap();
        assert_eq!(physical.strategy, ExecutionStrategy::Parallel);
        assert_eq!(physical.steps.len(), 2);
    }

    #[test]
    fn test_vector_before_graph() {
        let planner = Planner::new(PlannerConfig::default());
        let physical = planner.optimize(&graph_vector_plan()).unwrap();

        // Vector has priority 20, Graph has priority 40 → Vector first
        assert_eq!(physical.steps[0].modality, Modality::Vector);
        assert_eq!(physical.steps[1].modality, Modality::Graph);
    }

    #[test]
    fn test_semantic_always_last() {
        let planner = Planner::new(PlannerConfig::default());
        let plan = LogicalPlan {
            source: QuerySource::Hexad,
            nodes: vec![
                PlanNode {
                    modality: Modality::Semantic,
                    conditions: vec![ConditionKind::ProofVerification {
                        contract: "test".to_string(),
                    }],
                    projections: vec![],
                    early_limit: None,
                },
                PlanNode {
                    modality: Modality::Document,
                    conditions: vec![],
                    projections: vec![],
                    early_limit: None,
                },
                PlanNode {
                    modality: Modality::Vector,
                    conditions: vec![],
                    projections: vec![],
                    early_limit: None,
                },
            ],
            post_processing: vec![],
        };

        let physical = planner.optimize(&plan).unwrap();
        let last = physical.steps.last().unwrap();
        assert_eq!(last.modality, Modality::Semantic);
    }

    #[test]
    fn test_temporal_always_first() {
        let planner = Planner::new(PlannerConfig::default());
        let plan = LogicalPlan {
            source: QuerySource::Hexad,
            nodes: vec![
                PlanNode {
                    modality: Modality::Graph,
                    conditions: vec![],
                    projections: vec![],
                    early_limit: None,
                },
                PlanNode {
                    modality: Modality::Temporal,
                    conditions: vec![ConditionKind::AtTime {
                        timestamp: "2026-01-01T00:00:00Z".to_string(),
                    }],
                    projections: vec![],
                    early_limit: None,
                },
            ],
            post_processing: vec![],
        };

        let physical = planner.optimize(&plan).unwrap();
        assert_eq!(physical.steps[0].modality, Modality::Temporal);
    }

    #[test]
    fn test_empty_plan_error() {
        let planner = Planner::new(PlannerConfig::default());
        let plan = LogicalPlan {
            source: QuerySource::Hexad,
            nodes: vec![],
            post_processing: vec![],
        };

        let result = planner.optimize(&plan);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), PlannerError::EmptyPlan));
    }

    #[test]
    fn test_explain_generates_output() {
        let planner = Planner::new(PlannerConfig::default());
        let explain = planner.explain(&graph_vector_plan()).unwrap();
        assert_eq!(explain.steps.len(), 2);
        assert!(!explain.text_output.is_empty());
    }

    #[test]
    fn test_integration_graph_vector() {
        let planner = Planner::new(PlannerConfig::default());
        let physical = planner.optimize(&graph_vector_plan()).unwrap();

        // Vector ordered before Graph
        assert_eq!(physical.steps[0].modality, Modality::Vector);
        assert_eq!(physical.steps[1].modality, Modality::Graph);

        // Parallel strategy
        assert_eq!(physical.strategy, ExecutionStrategy::Parallel);

        // EXPLAIN output contains expected sections
        let explain = planner.explain(&graph_vector_plan()).unwrap();
        assert!(explain.text_output.contains("Step"));
        assert!(explain.text_output.contains("Strategy"));
        assert!(explain.text_output.contains("vector"));
    }
}
