// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Planner
//!
//! Cost-based query planning for VeriSimDB.
//! Transforms logical plans into optimized physical execution plans
//! with per-modality cost estimation and EXPLAIN output.

pub mod config;
pub mod cost;
pub mod error;
pub mod explain;
pub mod optimizer;
pub mod plan;
pub mod prepared;
pub mod profiler;
pub mod slow_query;
pub mod stats;
pub mod vql_bridge;

use serde::{Deserialize, Serialize};
use std::fmt;
use std::str::FromStr;

pub use config::{OptimizationMode, PlannerConfig};
pub use cost::{CostEstimate, CostModel, CrossModalCost, PostProcessingCost, ProofCost};
pub use error::PlannerError;
pub use explain::ExplainOutput;
pub use optimizer::Planner;
pub use plan::{LogicalPlan, PhysicalPlan};
pub use profiler::{ExplainAnalyzeOutput, Profiler, ProfileStep, QueryProfile};
pub use prepared::{CacheConfig, CacheError, CacheStats, ParamValue, PlanCache, PreparedId, PreparedStatement};
pub use slow_query::{SlowQueryConfig, SlowQueryEntry, SlowQueryLog, SlowQuerySummary};
pub use stats::{AdaptiveTuner, StatisticsCollector, StoreStatistics};

/// The six modalities of VeriSimDB.
///
/// Each modality represents a different representation/store for hexad entities.
/// The planner defines its own canonical enum to avoid coupling with verisim-hexad
/// or verisim-drift.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Modality {
    Graph,
    Vector,
    Tensor,
    Semantic,
    Document,
    Temporal,
}

impl Modality {
    /// All six modalities in canonical order.
    pub const ALL: [Modality; 6] = [
        Modality::Graph,
        Modality::Vector,
        Modality::Tensor,
        Modality::Semantic,
        Modality::Document,
        Modality::Temporal,
    ];

    /// Execution priority — lower value means execute earlier.
    ///
    /// Matches the Elixir bidirectional planner ordering:
    /// - Temporal first (often cached)
    /// - Vector/Document next (selective indexes)
    /// - Graph middle
    /// - Tensor moderate
    /// - Semantic last (ZKP expensive)
    pub fn execution_priority(self) -> u32 {
        match self {
            Modality::Temporal => 10,
            Modality::Vector => 20,
            Modality::Document => 30,
            Modality::Graph => 40,
            Modality::Tensor => 50,
            Modality::Semantic => 90,
        }
    }
}

impl fmt::Display for Modality {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Modality::Graph => write!(f, "graph"),
            Modality::Vector => write!(f, "vector"),
            Modality::Tensor => write!(f, "tensor"),
            Modality::Semantic => write!(f, "semantic"),
            Modality::Document => write!(f, "document"),
            Modality::Temporal => write!(f, "temporal"),
        }
    }
}

impl FromStr for Modality {
    type Err = PlannerError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "graph" => Ok(Modality::Graph),
            "vector" => Ok(Modality::Vector),
            "tensor" => Ok(Modality::Tensor),
            "semantic" => Ok(Modality::Semantic),
            "document" => Ok(Modality::Document),
            "temporal" => Ok(Modality::Temporal),
            _ => Err(PlannerError::UnknownModality(s.to_string())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_modality_display_roundtrip() {
        for m in Modality::ALL {
            let s = m.to_string();
            let parsed: Modality = s.parse().unwrap();
            assert_eq!(m, parsed);
        }
    }

    #[test]
    fn test_modality_case_insensitive_parse() {
        assert_eq!("GRAPH".parse::<Modality>().unwrap(), Modality::Graph);
        assert_eq!("Vector".parse::<Modality>().unwrap(), Modality::Vector);
        assert_eq!("SEMANTIC".parse::<Modality>().unwrap(), Modality::Semantic);
    }

    #[test]
    fn test_unknown_modality_error() {
        assert!("unknown".parse::<Modality>().is_err());
    }

    #[test]
    fn test_modality_serde_roundtrip() {
        for m in Modality::ALL {
            let json = serde_json::to_string(&m).unwrap();
            let parsed: Modality = serde_json::from_str(&json).unwrap();
            assert_eq!(m, parsed);
        }
    }

    #[test]
    fn test_execution_priority_ordering() {
        assert!(Modality::Temporal.execution_priority() < Modality::Vector.execution_priority());
        assert!(Modality::Vector.execution_priority() < Modality::Document.execution_priority());
        assert!(Modality::Document.execution_priority() < Modality::Graph.execution_priority());
        assert!(Modality::Graph.execution_priority() < Modality::Tensor.execution_priority());
        assert!(Modality::Tensor.execution_priority() < Modality::Semantic.execution_priority());
    }
}
