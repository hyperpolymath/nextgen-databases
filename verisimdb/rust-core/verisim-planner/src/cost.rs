// SPDX-License-Identifier: PMPL-1.0-or-later
//! Cost model and estimation.
//!
//! Base costs match VQLExplain.res values. Mode multipliers match
//! query_planner_config.ex (conservative=1.5x, balanced=1.0x, aggressive=0.8x).

use serde::{Deserialize, Serialize};

use crate::config::PlannerConfig;
use crate::plan::{ConditionKind, PlanNode};
use crate::stats::StoreStatistics;
use crate::Modality;

/// Base cost parameters for a single modality.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BaseCost {
    /// Base time estimate in milliseconds.
    pub time_ms: f64,
    /// Base selectivity (fraction of rows returned, 0.0–1.0).
    pub selectivity: f64,
    /// Optimization hint for this modality.
    pub hint: &'static str,
}

impl BaseCost {
    /// Get the default base cost for a modality.
    ///
    /// Values match VQLExplain.res:
    /// - Graph: 150ms, 0.2 selectivity
    /// - Vector: 50ms, 0.01 selectivity
    /// - Tensor: 200ms, 0.5 selectivity
    /// - Semantic: 300ms, 0.8 selectivity
    /// - Document: 80ms, 0.05 selectivity
    /// - Temporal: 30ms, 0.1 selectivity
    pub fn for_modality(modality: Modality) -> Self {
        match modality {
            Modality::Graph => BaseCost {
                time_ms: 150.0,
                selectivity: 0.2,
                hint: "Graph traversal — O(E) scan",
            },
            Modality::Vector => BaseCost {
                time_ms: 50.0,
                selectivity: 0.01,
                hint: "HNSW approximate nearest neighbor",
            },
            Modality::Tensor => BaseCost {
                time_ms: 200.0,
                selectivity: 0.5,
                hint: "Tensor reduction — shape dependent",
            },
            Modality::Semantic => BaseCost {
                time_ms: 300.0,
                selectivity: 0.8,
                hint: "ZKP verification — expensive",
            },
            Modality::Document => BaseCost {
                time_ms: 80.0,
                selectivity: 0.05,
                hint: "Tantivy inverted index lookup",
            },
            Modality::Temporal => BaseCost {
                time_ms: 30.0,
                selectivity: 0.1,
                hint: "Version tree lookup — cached",
            },
        }
    }
}

/// Cost estimate for a plan step or the total plan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CostEstimate {
    /// Estimated wall-clock time in milliseconds.
    pub time_ms: f64,
    /// Estimated number of rows returned.
    pub estimated_rows: u64,
    /// Selectivity (0.0–1.0).
    pub selectivity: f64,
    /// I/O component of cost.
    pub io_cost: f64,
    /// CPU component of cost.
    pub cpu_cost: f64,
}

impl CostEstimate {
    /// Combine two estimates for sequential execution (sum of times).
    pub fn sequential(a: &CostEstimate, b: &CostEstimate) -> CostEstimate {
        CostEstimate {
            time_ms: a.time_ms + b.time_ms,
            estimated_rows: a.estimated_rows.max(b.estimated_rows),
            selectivity: a.selectivity * b.selectivity,
            io_cost: a.io_cost + b.io_cost,
            cpu_cost: a.cpu_cost + b.cpu_cost,
        }
    }

    /// Combine two estimates for parallel execution (max of times).
    pub fn parallel(a: &CostEstimate, b: &CostEstimate) -> CostEstimate {
        CostEstimate {
            time_ms: a.time_ms.max(b.time_ms),
            estimated_rows: a.estimated_rows.max(b.estimated_rows),
            selectivity: a.selectivity * b.selectivity,
            io_cost: a.io_cost + b.io_cost,
            cpu_cost: a.cpu_cost + b.cpu_cost,
        }
    }

    /// Combine a list of estimates according to strategy.
    pub fn combine(estimates: &[CostEstimate], parallel: bool) -> CostEstimate {
        if estimates.is_empty() {
            return CostEstimate {
                time_ms: 0.0,
                estimated_rows: 0,
                selectivity: 1.0,
                io_cost: 0.0,
                cpu_cost: 0.0,
            };
        }
        let mut result = estimates[0].clone();
        for est in &estimates[1..] {
            result = if parallel {
                CostEstimate::parallel(&result, est)
            } else {
                CostEstimate::sequential(&result, est)
            };
        }
        result
    }
}

/// Proof obligation cost parameters.
///
/// Different proof types have vastly different verification costs.
/// Values derived from the consultation-dependent-types-zkp.adoc
/// and VQLProofObligation.res cost estimates.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofCost {
    /// Base verification time in milliseconds.
    pub verify_ms: f64,
    /// Circuit generation time (if applicable).
    pub circuit_ms: f64,
    /// Whether this proof type is parallelizable.
    pub parallelizable: bool,
}

impl ProofCost {
    /// Get the cost for a proof type by name.
    ///
    /// Proof types from VQLProofObligation.res:
    /// - Existence: trivial check (hexad exists)
    /// - Citation: contract lookup in registry
    /// - Access: semantic store rights check
    /// - Integrity: CBOR proof blob + Merkle verification
    /// - Provenance: lineage chain walk
    /// - ZKP/Custom: full SNARK circuit verification
    pub fn for_type(proof_type: &str) -> Self {
        match proof_type.to_lowercase().as_str() {
            "existence" => ProofCost {
                verify_ms: 1.0,
                circuit_ms: 0.0,
                parallelizable: true,
            },
            "citation" => ProofCost {
                verify_ms: 5.0,
                circuit_ms: 0.0,
                parallelizable: true,
            },
            "access" => ProofCost {
                verify_ms: 15.0,
                circuit_ms: 0.0,
                parallelizable: true,
            },
            "integrity" => ProofCost {
                verify_ms: 50.0,
                circuit_ms: 10.0,
                parallelizable: true,
            },
            "provenance" => ProofCost {
                verify_ms: 30.0,
                circuit_ms: 0.0,
                parallelizable: false, // Chain walk is sequential
            },
            // ZKP/Custom: full SNARK verification
            _ => ProofCost {
                verify_ms: 200.0,
                circuit_ms: 100.0,
                parallelizable: false,
            },
        }
    }

    /// Total cost for this proof.
    pub fn total_ms(&self) -> f64 {
        self.verify_ms + self.circuit_ms
    }
}

/// Post-processing cost estimation.
///
/// Estimates CPU cost for operations applied after modality queries.
pub struct PostProcessingCost;

impl PostProcessingCost {
    /// Estimate cost for a post-processing step given the row count.
    pub fn estimate(pp: &crate::plan::PostProcessing, row_count: u64) -> CostEstimate {
        let n = row_count.max(1) as f64;
        match pp {
            crate::plan::PostProcessing::OrderBy { fields, .. } => {
                // O(n log n) sort, ~0.001ms per comparison
                let sort_time = n * n.log2().max(1.0) * 0.001 * fields.len() as f64;
                CostEstimate {
                    time_ms: sort_time,
                    estimated_rows: row_count,
                    selectivity: 1.0,
                    io_cost: 0.0,
                    cpu_cost: sort_time,
                }
            }
            crate::plan::PostProcessing::Limit { count } => {
                // Nearly free — just truncation
                let out_rows = row_count.min(*count as u64);
                CostEstimate {
                    time_ms: 0.1,
                    estimated_rows: out_rows,
                    selectivity: out_rows as f64 / n,
                    io_cost: 0.0,
                    cpu_cost: 0.1,
                }
            }
            crate::plan::PostProcessing::GroupBy { fields, aggregates } => {
                // O(n) hash grouping + O(groups * aggregates) computation
                let group_time = n * 0.002 * fields.len() as f64;
                let agg_time = n * 0.001 * aggregates.len().max(1) as f64;
                let total = group_time + agg_time;
                // Grouping typically reduces rows significantly
                let est_groups = (n / 10.0).max(1.0) as u64;
                CostEstimate {
                    time_ms: total,
                    estimated_rows: est_groups,
                    selectivity: est_groups as f64 / n,
                    io_cost: 0.0,
                    cpu_cost: total,
                }
            }
            crate::plan::PostProcessing::Project { columns } => {
                // Nearly free — column selection
                let project_time = n * 0.0001 * columns.len() as f64;
                CostEstimate {
                    time_ms: project_time,
                    estimated_rows: row_count,
                    selectivity: 1.0,
                    io_cost: 0.0,
                    cpu_cost: project_time,
                }
            }
        }
    }
}

/// Cross-modal condition cost estimation.
///
/// Cross-modal conditions (DRIFT, CONSISTENCY, EXISTS, field comparisons)
/// are evaluated post-fetch and have CPU costs proportional to row count.
pub struct CrossModalCost;

impl CrossModalCost {
    /// Estimate the cost of evaluating a cross-modal condition.
    pub fn estimate(condition: &ConditionKind, row_count: u64) -> CostEstimate {
        let n = row_count.max(1) as f64;
        let (per_row_ms, selectivity) = match condition {
            // Cross-modal field compare: fetch two fields, compare
            ConditionKind::Predicate { expression } if expression.contains("cross_modal") => {
                (0.01, 0.3) // Most rows won't match cross-modal predicates
            }
            // Drift computation: cosine distance between embeddings
            ConditionKind::Predicate { expression } if expression.contains("drift") => {
                (0.5, 0.5) // Embedding extraction + distance calc per row
            }
            // Consistency check: full similarity metric
            ConditionKind::Predicate { expression } if expression.contains("consistency") => {
                (1.0, 0.7) // Metric computation (cosine/euclidean/jaccard)
            }
            // Exists/NotExists: cheap boolean check
            ConditionKind::Predicate { expression }
                if expression.contains("exists") || expression.contains("not_exists") =>
            {
                (0.001, 0.5)
            }
            // Generic predicate fallback
            _ => (0.01, 0.5),
        };

        let total_time = n * per_row_ms;
        CostEstimate {
            time_ms: total_time,
            estimated_rows: (n * selectivity).max(1.0) as u64,
            selectivity,
            io_cost: 0.0,
            cpu_cost: total_time,
        }
    }
}

/// Cost model that estimates execution cost for plan nodes.
pub struct CostModel;

impl CostModel {
    /// Estimate the cost of executing a single plan node.
    ///
    /// Factors:
    /// 1. Base cost for the modality (from VQLExplain.res)
    /// 2. Optimization mode multiplier (from query_planner_config.ex)
    /// 3. Store statistics (if available)
    /// 4. Early limit reduction
    /// 5. Condition-specific adjustments (including proof obligations)
    /// 6. Cross-modal condition overhead
    pub fn estimate(
        node: &PlanNode,
        config: &PlannerConfig,
        stats: Option<&StoreStatistics>,
    ) -> CostEstimate {
        let base = BaseCost::for_modality(node.modality);
        let mode = config.mode_for(node.modality);

        // Apply mode multipliers (from query_planner_config.ex)
        let cost_mult = mode.cost_multiplier();
        let sel_mult = mode.selectivity_multiplier();

        let mut time_ms = base.time_ms * cost_mult;
        let mut selectivity = (base.selectivity * sel_mult).min(1.0);

        // Adjust for store statistics if available (weighted by statistics_weight)
        if let Some(s) = stats {
            if s.query_count > 0 {
                let w = config.statistics_weight;
                time_ms = time_ms * (1.0 - w) + s.avg_latency_ms * w;
                if s.total_rows > 0 {
                    let empirical_sel = s.avg_rows_returned as f64 / s.total_rows as f64;
                    selectivity = selectivity * (1.0 - w) + empirical_sel * w;
                }
            }
        }

        // Early limit reduces selectivity (fewer rows scanned/returned)
        if let Some(limit) = node.early_limit {
            let limit_factor = (limit as f64 / 1000.0).min(1.0);
            selectivity *= limit_factor;
            time_ms *= 0.5 + 0.5 * limit_factor; // At least 50% of base cost
        }

        // Track proof obligation costs separately for accurate modeling
        let mut proof_time_ms = 0.0;

        // Condition-specific adjustments
        for condition in &node.conditions {
            match condition {
                ConditionKind::Equality { .. } => {
                    selectivity *= 0.1; // Highly selective
                    time_ms *= 0.7;
                }
                ConditionKind::Range { .. } => {
                    selectivity *= 0.3;
                    time_ms *= 0.8;
                }
                ConditionKind::Similarity { k } => {
                    selectivity = (*k as f64 / 10000.0).min(1.0);
                }
                ConditionKind::Fulltext { .. } => {
                    // Tantivy inverted index is fast
                    time_ms *= 0.6;
                }
                ConditionKind::ProofVerification { contract } => {
                    // Detailed proof costing based on proof type
                    let proof_type = extract_proof_type(contract);
                    let pcost = ProofCost::for_type(&proof_type);
                    proof_time_ms += pcost.total_ms();
                }
                _ => {}
            }
        }

        // Add proof overhead to total time
        time_ms += proof_time_ms;

        let estimated_rows = if let Some(s) = stats {
            (s.total_rows as f64 * selectivity).max(1.0) as u64
        } else {
            (1000.0 * selectivity).max(1.0) as u64
        };

        // Split cost: proofs are CPU-bound, modality queries are I/O-heavy
        let io_cost = (time_ms - proof_time_ms) * 0.6;
        let cpu_cost = (time_ms - proof_time_ms) * 0.4 + proof_time_ms;

        CostEstimate {
            time_ms,
            estimated_rows,
            selectivity,
            io_cost,
            cpu_cost,
        }
    }

    /// Estimate total plan cost including post-processing steps.
    pub fn estimate_with_post_processing(
        modality_cost: &CostEstimate,
        post_processing: &[crate::plan::PostProcessing],
    ) -> CostEstimate {
        let mut total = modality_cost.clone();
        let mut current_rows = total.estimated_rows;

        for pp in post_processing {
            let pp_cost = PostProcessingCost::estimate(pp, current_rows);
            total.time_ms += pp_cost.time_ms;
            total.cpu_cost += pp_cost.cpu_cost;
            current_rows = pp_cost.estimated_rows;
        }

        total.estimated_rows = current_rows;
        total
    }

    /// Generate an optimization hint string for a plan node.
    pub fn optimization_hint(node: &PlanNode) -> Option<String> {
        let base = BaseCost::for_modality(node.modality);
        let mut hint = base.hint.to_string();

        for condition in &node.conditions {
            match condition {
                ConditionKind::Similarity { k } => {
                    hint = format!("HNSW ANN search (k={})", k);
                }
                ConditionKind::Fulltext { query } => {
                    let preview = if query.len() > 20 {
                        format!("{}...", &query[..20])
                    } else {
                        query.clone()
                    };
                    hint = format!("Tantivy fulltext: \"{}\"", preview);
                }
                ConditionKind::Traversal { predicate, depth } => {
                    hint = format!(
                        "Graph traversal: {} (depth={})",
                        predicate,
                        depth.unwrap_or(1)
                    );
                }
                ConditionKind::ProofVerification { contract } => {
                    hint = format!("ZKP verify: {}", contract);
                }
                ConditionKind::Equality { field, .. } => {
                    hint = format!("Index lookup on {}", field);
                }
                ConditionKind::AtTime { timestamp } => {
                    hint = format!("Temporal snapshot at {}", timestamp);
                }
                _ => {}
            }
        }

        Some(hint)
    }
}

/// Extract proof type from a contract string.
///
/// Contract strings follow the pattern "ProofType(ContractName)"
/// or just "ContractName" (defaults to custom/ZKP).
fn extract_proof_type(contract: &str) -> String {
    let known_types = [
        "existence", "citation", "access", "integrity", "provenance", "zkp",
    ];
    let lower = contract.to_lowercase();
    for t in &known_types {
        if lower.contains(t) {
            return t.to_string();
        }
    }
    "custom".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::PlannerConfig;

    #[test]
    fn test_base_costs_match_vql_explain() {
        assert_eq!(BaseCost::for_modality(Modality::Graph).time_ms, 150.0);
        assert_eq!(BaseCost::for_modality(Modality::Vector).time_ms, 50.0);
        assert_eq!(BaseCost::for_modality(Modality::Tensor).time_ms, 200.0);
        assert_eq!(BaseCost::for_modality(Modality::Semantic).time_ms, 300.0);
        assert_eq!(BaseCost::for_modality(Modality::Document).time_ms, 80.0);
        assert_eq!(BaseCost::for_modality(Modality::Temporal).time_ms, 30.0);
    }

    #[test]
    fn test_base_selectivity_values() {
        assert!((BaseCost::for_modality(Modality::Graph).selectivity - 0.2).abs() < f64::EPSILON);
        assert!((BaseCost::for_modality(Modality::Vector).selectivity - 0.01).abs() < f64::EPSILON);
        assert!((BaseCost::for_modality(Modality::Semantic).selectivity - 0.8).abs() < f64::EPSILON);
    }

    #[test]
    fn test_mode_multipliers_balanced() {
        let config = PlannerConfig::default();
        let node = PlanNode {
            modality: Modality::Graph,
            conditions: vec![],
            projections: vec![],
            early_limit: None,
        };
        // Graph has conservative override by default → cost_mult = 1.5
        let est = CostModel::estimate(&node, &config, None);
        assert!((est.time_ms - 150.0 * 1.5).abs() < f64::EPSILON);
    }

    #[test]
    fn test_mode_multipliers_aggressive() {
        let config = PlannerConfig::default();
        let node = PlanNode {
            modality: Modality::Vector,
            conditions: vec![],
            projections: vec![],
            early_limit: None,
        };
        // Vector has aggressive override by default → cost_mult = 0.8
        let est = CostModel::estimate(&node, &config, None);
        assert!((est.time_ms - 50.0 * 0.8).abs() < f64::EPSILON);
    }

    #[test]
    fn test_early_limit_reduces_selectivity() {
        let config = PlannerConfig::default();
        let node_no_limit = PlanNode {
            modality: Modality::Document,
            conditions: vec![],
            projections: vec![],
            early_limit: None,
        };
        let node_with_limit = PlanNode {
            modality: Modality::Document,
            conditions: vec![],
            projections: vec![],
            early_limit: Some(10),
        };
        let est_no = CostModel::estimate(&node_no_limit, &config, None);
        let est_with = CostModel::estimate(&node_with_limit, &config, None);
        assert!(est_with.selectivity < est_no.selectivity);
        assert!(est_with.time_ms < est_no.time_ms);
    }

    #[test]
    fn test_sequential_combinator() {
        let a = CostEstimate {
            time_ms: 100.0,
            estimated_rows: 50,
            selectivity: 0.5,
            io_cost: 60.0,
            cpu_cost: 40.0,
        };
        let b = CostEstimate {
            time_ms: 200.0,
            estimated_rows: 100,
            selectivity: 0.3,
            io_cost: 120.0,
            cpu_cost: 80.0,
        };
        let combined = CostEstimate::sequential(&a, &b);
        assert!((combined.time_ms - 300.0).abs() < f64::EPSILON);
        assert!((combined.io_cost - 180.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_parallel_combinator() {
        let a = CostEstimate {
            time_ms: 100.0,
            estimated_rows: 50,
            selectivity: 0.5,
            io_cost: 60.0,
            cpu_cost: 40.0,
        };
        let b = CostEstimate {
            time_ms: 200.0,
            estimated_rows: 100,
            selectivity: 0.3,
            io_cost: 120.0,
            cpu_cost: 80.0,
        };
        let combined = CostEstimate::parallel(&a, &b);
        assert!((combined.time_ms - 200.0).abs() < f64::EPSILON); // max
        assert!((combined.io_cost - 180.0).abs() < f64::EPSILON); // sum
    }

    // ====================================================================
    // Task #7: Proof obligation costing
    // ====================================================================

    #[test]
    fn test_proof_cost_existence_is_cheap() {
        let pc = ProofCost::for_type("existence");
        assert!(pc.total_ms() < 5.0, "Existence proof should be < 5ms");
    }

    #[test]
    fn test_proof_cost_zkp_is_expensive() {
        let pc = ProofCost::for_type("zkp");
        assert!(pc.total_ms() > 100.0, "ZKP proof should be > 100ms");
        assert!(pc.circuit_ms > 0.0, "ZKP should have circuit generation cost");
    }

    #[test]
    fn test_proof_cost_integrity_includes_circuit() {
        let pc = ProofCost::for_type("integrity");
        assert!(pc.circuit_ms > 0.0, "Integrity proof includes Merkle circuit");
        assert!(pc.verify_ms > pc.circuit_ms, "Verify > circuit for integrity");
    }

    #[test]
    fn test_proof_cost_unknown_defaults_to_custom() {
        let pc = ProofCost::for_type("MyCustomContract");
        assert!(pc.total_ms() > 100.0, "Unknown proof defaults to expensive custom");
    }

    #[test]
    fn test_proof_adds_to_node_cost() {
        let config = PlannerConfig::default();
        let node_no_proof = PlanNode {
            modality: Modality::Semantic,
            conditions: vec![],
            projections: vec![],
            early_limit: None,
        };
        let node_with_proof = PlanNode {
            modality: Modality::Semantic,
            conditions: vec![ConditionKind::ProofVerification {
                contract: "integrity_check".to_string(),
            }],
            projections: vec![],
            early_limit: None,
        };
        let est_no = CostModel::estimate(&node_no_proof, &config, None);
        let est_with = CostModel::estimate(&node_with_proof, &config, None);
        assert!(est_with.time_ms > est_no.time_ms, "Proof should add cost");
        // Proof cost should show up in CPU, not I/O
        assert!(est_with.cpu_cost > est_no.cpu_cost);
    }

    #[test]
    fn test_multiple_proofs_accumulate() {
        let config = PlannerConfig::default();
        let node_one = PlanNode {
            modality: Modality::Semantic,
            conditions: vec![ConditionKind::ProofVerification {
                contract: "existence_check".to_string(),
            }],
            projections: vec![],
            early_limit: None,
        };
        let node_two = PlanNode {
            modality: Modality::Semantic,
            conditions: vec![
                ConditionKind::ProofVerification {
                    contract: "existence_check".to_string(),
                },
                ConditionKind::ProofVerification {
                    contract: "integrity_check".to_string(),
                },
            ],
            projections: vec![],
            early_limit: None,
        };
        let est_one = CostModel::estimate(&node_one, &config, None);
        let est_two = CostModel::estimate(&node_two, &config, None);
        assert!(est_two.time_ms > est_one.time_ms, "Two proofs > one proof");
    }

    #[test]
    fn test_extract_proof_type_known() {
        assert_eq!(extract_proof_type("CitationContract"), "citation");
        assert_eq!(extract_proof_type("integrity_check"), "integrity");
        assert_eq!(extract_proof_type("AccessRights"), "access");
        assert_eq!(extract_proof_type("ProvenanceAudit"), "provenance");
    }

    #[test]
    fn test_extract_proof_type_unknown() {
        assert_eq!(extract_proof_type("MyContract"), "custom");
        assert_eq!(extract_proof_type("FooBar"), "custom");
    }

    // ====================================================================
    // Task #9: Post-processing and cross-modal costing
    // ====================================================================

    #[test]
    fn test_post_processing_limit_cheap() {
        use crate::plan::PostProcessing;
        let cost = PostProcessingCost::estimate(&PostProcessing::Limit { count: 10 }, 1000);
        assert!(cost.time_ms < 1.0, "LIMIT should be nearly free");
        assert_eq!(cost.estimated_rows, 10);
    }

    #[test]
    fn test_post_processing_order_by_scales_with_rows() {
        use crate::plan::PostProcessing;
        let small = PostProcessingCost::estimate(
            &PostProcessing::OrderBy { fields: vec![("name".into(), true)] },
            100,
        );
        let large = PostProcessingCost::estimate(
            &PostProcessing::OrderBy { fields: vec![("name".into(), true)] },
            10000,
        );
        assert!(large.time_ms > small.time_ms * 10.0, "O(n log n) scaling");
    }

    #[test]
    fn test_post_processing_group_by_reduces_rows() {
        use crate::plan::PostProcessing;
        let cost = PostProcessingCost::estimate(
            &PostProcessing::GroupBy {
                fields: vec!["category".into()],
                aggregates: vec!["COUNT(*)".into()],
            },
            1000,
        );
        assert!(cost.estimated_rows < 1000, "GROUP BY should reduce rows");
    }

    #[test]
    fn test_estimate_with_post_processing() {
        use crate::plan::PostProcessing;
        let base = CostEstimate {
            time_ms: 100.0,
            estimated_rows: 500,
            selectivity: 0.5,
            io_cost: 60.0,
            cpu_cost: 40.0,
        };
        let pps = vec![
            PostProcessing::OrderBy { fields: vec![("score".into(), false)] },
            PostProcessing::Limit { count: 10 },
        ];
        let total = CostModel::estimate_with_post_processing(&base, &pps);
        assert!(total.time_ms > base.time_ms, "PP adds time");
        assert_eq!(total.estimated_rows, 10, "LIMIT reduces final rows");
    }

    #[test]
    fn test_cross_modal_drift_cost() {
        let cond = ConditionKind::Predicate {
            expression: "drift(vector, document) > 0.3".to_string(),
        };
        let cost = CrossModalCost::estimate(&cond, 100);
        assert!(cost.time_ms > 0.0);
        assert!(cost.selectivity < 1.0);
    }

    #[test]
    fn test_cross_modal_exists_cheap() {
        let cond = ConditionKind::Predicate {
            expression: "vector exists".to_string(),
        };
        let cost = CrossModalCost::estimate(&cond, 1000);
        // Exists is cheap — just a boolean check
        assert!(cost.time_ms < 5.0);
    }
}
