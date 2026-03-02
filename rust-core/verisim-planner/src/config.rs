// SPDX-License-Identifier: PMPL-1.0-or-later
//! Planner configuration.
//!
//! Defaults match the Elixir query_planner_config.ex:
//! - global_mode: balanced
//! - Vector: aggressive, Graph: conservative, Semantic: conservative
//! - statistics_weight: 0.7

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::Modality;

/// Optimization mode controlling cost/selectivity trade-offs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OptimizationMode {
    /// Safety buffers: cost ×1.5, selectivity ×2.0.
    Conservative,
    /// Use estimates as-is: cost ×1.0, selectivity ×1.0.
    Balanced,
    /// Optimistic: cost ×0.8, selectivity ×0.5.
    Aggressive,
}

impl OptimizationMode {
    /// Cost multiplier for this mode (from query_planner_config.ex).
    pub fn cost_multiplier(self) -> f64 {
        match self {
            OptimizationMode::Conservative => 1.5,
            OptimizationMode::Balanced => 1.0,
            OptimizationMode::Aggressive => 0.8,
        }
    }

    /// Selectivity multiplier for this mode (from query_planner_config.ex).
    pub fn selectivity_multiplier(self) -> f64 {
        match self {
            OptimizationMode::Conservative => 2.0,
            OptimizationMode::Balanced => 1.0,
            OptimizationMode::Aggressive => 0.5,
        }
    }
}

/// Configuration for the query planner.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlannerConfig {
    /// Global optimization mode.
    pub global_mode: OptimizationMode,
    /// Per-modality mode overrides.
    pub modality_overrides: HashMap<Modality, OptimizationMode>,
    /// Weight given to historical statistics vs base estimates (0.0–1.0).
    pub statistics_weight: f64,
    /// Whether to enable adaptive tuning based on execution feedback.
    pub enable_adaptive: bool,
    /// Minimum number of modality nodes to trigger parallel execution.
    pub parallel_threshold: usize,
}

impl PlannerConfig {
    /// Get the effective optimization mode for a modality.
    ///
    /// Checks per-modality overrides first, falls back to global_mode.
    pub fn mode_for(&self, modality: Modality) -> OptimizationMode {
        self.modality_overrides
            .get(&modality)
            .copied()
            .unwrap_or(self.global_mode)
    }
}

impl Default for PlannerConfig {
    /// Defaults matching Elixir query_planner_config.ex:
    /// - global_mode: balanced
    /// - Vector: aggressive (predictable HNSW)
    /// - Graph: conservative (unpredictable traversals)
    /// - Semantic: conservative (ZKP expensive)
    /// - statistics_weight: 0.7
    /// - enable_adaptive: true
    /// - parallel_threshold: 2
    fn default() -> Self {
        let mut overrides = HashMap::new();
        overrides.insert(Modality::Vector, OptimizationMode::Aggressive);
        overrides.insert(Modality::Graph, OptimizationMode::Conservative);
        overrides.insert(Modality::Semantic, OptimizationMode::Conservative);

        Self {
            global_mode: OptimizationMode::Balanced,
            modality_overrides: overrides,
            statistics_weight: 0.7,
            enable_adaptive: true,
            parallel_threshold: 2,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_defaults_match_elixir() {
        let config = PlannerConfig::default();
        assert_eq!(config.global_mode, OptimizationMode::Balanced);
        assert_eq!(
            config.mode_for(Modality::Vector),
            OptimizationMode::Aggressive
        );
        assert_eq!(
            config.mode_for(Modality::Graph),
            OptimizationMode::Conservative
        );
        assert_eq!(
            config.mode_for(Modality::Semantic),
            OptimizationMode::Conservative
        );
        assert!((config.statistics_weight - 0.7).abs() < f64::EPSILON);
        assert!(config.enable_adaptive);
    }

    #[test]
    fn test_mode_for_fallback() {
        let config = PlannerConfig::default();
        // Tensor, Document, Temporal have no overrides → fall back to global (Balanced)
        assert_eq!(
            config.mode_for(Modality::Tensor),
            OptimizationMode::Balanced
        );
        assert_eq!(
            config.mode_for(Modality::Document),
            OptimizationMode::Balanced
        );
        assert_eq!(
            config.mode_for(Modality::Temporal),
            OptimizationMode::Balanced
        );
    }

    #[test]
    fn test_cost_multipliers() {
        assert!((OptimizationMode::Conservative.cost_multiplier() - 1.5).abs() < f64::EPSILON);
        assert!((OptimizationMode::Balanced.cost_multiplier() - 1.0).abs() < f64::EPSILON);
        assert!((OptimizationMode::Aggressive.cost_multiplier() - 0.8).abs() < f64::EPSILON);
    }

    #[test]
    fn test_selectivity_multipliers() {
        assert!(
            (OptimizationMode::Conservative.selectivity_multiplier() - 2.0).abs() < f64::EPSILON
        );
        assert!(
            (OptimizationMode::Balanced.selectivity_multiplier() - 1.0).abs() < f64::EPSILON
        );
        assert!(
            (OptimizationMode::Aggressive.selectivity_multiplier() - 0.5).abs() < f64::EPSILON
        );
    }

    #[test]
    fn test_config_serde_roundtrip() {
        let config = PlannerConfig::default();
        let json = serde_json::to_string(&config).unwrap();
        let parsed: PlannerConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.global_mode, config.global_mode);
        assert_eq!(parsed.parallel_threshold, config.parallel_threshold);
    }
}
