// SPDX-License-Identifier: PMPL-1.0-or-later
//! Store statistics collection and tracking.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::Modality;

/// Statistics for a single modality store.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoreStatistics {
    /// Which modality these stats describe.
    pub modality: Modality,
    /// Total number of rows/entities in this store.
    pub total_rows: u64,
    /// Average query latency in milliseconds (exponential moving average).
    pub avg_latency_ms: f64,
    /// Average number of rows returned per query.
    pub avg_rows_returned: u64,
    /// Total number of queries executed.
    pub query_count: u64,
    /// When statistics were last updated.
    pub last_updated: DateTime<Utc>,
}

impl StoreStatistics {
    /// Create empty statistics for a modality.
    fn new(modality: Modality) -> Self {
        Self {
            modality,
            total_rows: 0,
            avg_latency_ms: 0.0,
            avg_rows_returned: 0,
            query_count: 0,
            last_updated: Utc::now(),
        }
    }
}

/// Collects and maintains statistics across all modality stores.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatisticsCollector {
    stats: HashMap<Modality, StoreStatistics>,
}

impl StatisticsCollector {
    /// Create a new collector with empty statistics for all 6 modalities.
    pub fn new() -> Self {
        let mut stats = HashMap::new();
        for m in Modality::ALL {
            stats.insert(m, StoreStatistics::new(m));
        }
        Self { stats }
    }

    /// Get statistics for a specific modality.
    pub fn get(&self, modality: Modality) -> Option<&StoreStatistics> {
        self.stats.get(&modality)
    }

    /// Get a snapshot of all statistics.
    pub fn snapshot(&self) -> &HashMap<Modality, StoreStatistics> {
        &self.stats
    }

    /// Record a query execution for a modality.
    ///
    /// Uses exponential moving average (alpha=0.1) for latency,
    /// matching the drift detector's approach.
    pub fn record_execution(
        &mut self,
        modality: Modality,
        latency_ms: f64,
        rows_returned: u64,
    ) {
        let entry = self.stats.entry(modality).or_insert_with(|| StoreStatistics::new(modality));
        entry.query_count += 1;

        // Exponential moving average (alpha = 0.1)
        if entry.query_count == 1 {
            entry.avg_latency_ms = latency_ms;
            entry.avg_rows_returned = rows_returned;
        } else {
            entry.avg_latency_ms = 0.1 * latency_ms + 0.9 * entry.avg_latency_ms;
            entry.avg_rows_returned =
                (0.1 * rows_returned as f64 + 0.9 * entry.avg_rows_returned as f64) as u64;
        }

        entry.last_updated = Utc::now();
    }

    /// Update the total row count for a modality.
    pub fn update_row_count(&mut self, modality: Modality, total_rows: u64) {
        if let Some(entry) = self.stats.get_mut(&modality) {
            entry.total_rows = total_rows;
            entry.last_updated = Utc::now();
        }
    }
}

impl Default for StatisticsCollector {
    fn default() -> Self {
        Self::new()
    }
}

/// Adaptive tuner that adjusts planner configuration based on actual
/// execution performance vs estimated costs.
///
/// When enabled, the tuner compares actual query latencies against
/// the planner's estimates and adjusts per-modality optimization modes:
/// - If actual >> estimated → switch to Conservative (underestimating)
/// - If actual << estimated → switch to Aggressive (overestimating)
/// - Otherwise → keep Balanced
pub struct AdaptiveTuner {
    /// Ratio of actual/estimated below which we go Aggressive.
    aggressive_threshold: f64,
    /// Ratio of actual/estimated above which we go Conservative.
    conservative_threshold: f64,
    /// Minimum number of samples before making adjustments.
    min_samples: u64,
}

impl AdaptiveTuner {
    /// Create a new adaptive tuner with default thresholds.
    pub fn new() -> Self {
        Self {
            aggressive_threshold: 0.5,    // Actual < 50% of estimate → overestimating
            conservative_threshold: 2.0,  // Actual > 200% of estimate → underestimating
            min_samples: 10,
        }
    }

    /// Create a tuner with custom thresholds.
    pub fn with_thresholds(aggressive: f64, conservative: f64, min_samples: u64) -> Self {
        Self {
            aggressive_threshold: aggressive,
            conservative_threshold: conservative,
            min_samples,
        }
    }

    /// Evaluate the collector's statistics and suggest config adjustments.
    ///
    /// Returns a list of (Modality, suggested OptimizationMode) pairs
    /// for modalities that should be tuned.
    pub fn suggest_adjustments(
        &self,
        collector: &StatisticsCollector,
        config: &crate::config::PlannerConfig,
    ) -> Vec<(crate::Modality, crate::config::OptimizationMode)> {
        let mut adjustments = Vec::new();

        for modality in crate::Modality::ALL {
            if let Some(stats) = collector.get(modality) {
                if stats.query_count < self.min_samples {
                    continue; // Not enough data
                }

                let base_cost = crate::cost::BaseCost::for_modality(modality);
                let current_mode = config.mode_for(modality);
                let estimated_ms = base_cost.time_ms * current_mode.cost_multiplier();

                if estimated_ms <= 0.0 {
                    continue;
                }

                let ratio = stats.avg_latency_ms / estimated_ms;

                let suggested = if ratio < self.aggressive_threshold {
                    crate::config::OptimizationMode::Aggressive
                } else if ratio > self.conservative_threshold {
                    crate::config::OptimizationMode::Conservative
                } else {
                    crate::config::OptimizationMode::Balanced
                };

                if suggested != current_mode {
                    adjustments.push((modality, suggested));
                }
            }
        }

        adjustments
    }

    /// Apply suggested adjustments to a config, returning the updated config.
    pub fn apply(
        &self,
        collector: &StatisticsCollector,
        config: &crate::config::PlannerConfig,
    ) -> crate::config::PlannerConfig {
        if !config.enable_adaptive {
            return config.clone();
        }

        let adjustments = self.suggest_adjustments(collector, config);
        if adjustments.is_empty() {
            return config.clone();
        }

        let mut new_config = config.clone();
        for (modality, mode) in adjustments {
            new_config.modality_overrides.insert(modality, mode);
        }
        new_config
    }
}

impl Default for AdaptiveTuner {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_collector_initializes_all_modalities() {
        let collector = StatisticsCollector::new();
        for m in Modality::ALL {
            let stats = collector.get(m).unwrap();
            assert_eq!(stats.modality, m);
            assert_eq!(stats.query_count, 0);
            assert_eq!(stats.total_rows, 0);
        }
        assert_eq!(collector.snapshot().len(), 6);
    }

    #[test]
    fn test_record_first_execution() {
        let mut collector = StatisticsCollector::new();
        collector.record_execution(Modality::Vector, 42.0, 10);

        let stats = collector.get(Modality::Vector).unwrap();
        assert_eq!(stats.query_count, 1);
        assert!((stats.avg_latency_ms - 42.0).abs() < f64::EPSILON);
        assert_eq!(stats.avg_rows_returned, 10);
    }

    #[test]
    fn test_record_updates_moving_average() {
        let mut collector = StatisticsCollector::new();

        // First execution
        collector.record_execution(Modality::Graph, 100.0, 50);
        assert!((collector.get(Modality::Graph).unwrap().avg_latency_ms - 100.0).abs() < f64::EPSILON);

        // Second execution — EMA: 0.1 * 200 + 0.9 * 100 = 110
        collector.record_execution(Modality::Graph, 200.0, 100);
        let stats = collector.get(Modality::Graph).unwrap();
        assert!((stats.avg_latency_ms - 110.0).abs() < f64::EPSILON);
        assert_eq!(stats.query_count, 2);
    }

    #[test]
    fn test_update_row_count() {
        let mut collector = StatisticsCollector::new();
        collector.update_row_count(Modality::Document, 5000);
        assert_eq!(collector.get(Modality::Document).unwrap().total_rows, 5000);
    }

    #[test]
    fn test_snapshot_returns_all() {
        let collector = StatisticsCollector::new();
        let snap = collector.snapshot();
        assert_eq!(snap.len(), 6);
    }

    // ====================================================================
    // Task #8: Adaptive tuning tests
    // ====================================================================

    #[test]
    fn test_adaptive_tuner_no_data_no_adjustments() {
        let tuner = AdaptiveTuner::new();
        let collector = StatisticsCollector::new();
        let config = crate::config::PlannerConfig::default();
        let adjustments = tuner.suggest_adjustments(&collector, &config);
        assert!(adjustments.is_empty(), "No data → no adjustments");
    }

    #[test]
    fn test_adaptive_tuner_below_min_samples() {
        let tuner = AdaptiveTuner::new(); // min_samples = 10
        let mut collector = StatisticsCollector::new();
        // Record only 5 executions (below threshold)
        for _ in 0..5 {
            collector.record_execution(Modality::Vector, 10.0, 5);
        }
        let config = crate::config::PlannerConfig::default();
        let adjustments = tuner.suggest_adjustments(&collector, &config);
        assert!(adjustments.is_empty(), "Below min_samples → no adjustments");
    }

    #[test]
    fn test_adaptive_tuner_suggests_aggressive_when_overestimating() {
        let tuner = AdaptiveTuner::new();
        let mut collector = StatisticsCollector::new();
        // Vector base = 50ms, aggressive mode = 0.8x = 40ms estimated
        // Record actual latency of 10ms (ratio = 10/40 = 0.25 < 0.5) → Aggressive
        for _ in 0..15 {
            collector.record_execution(Modality::Vector, 10.0, 5);
        }
        let config = crate::config::PlannerConfig::default();
        let adjustments = tuner.suggest_adjustments(&collector, &config);
        // Vector already has Aggressive override, so if actual confirms it, no change.
        // But ratio 0.25 < 0.5, already aggressive, stays aggressive → no adjustment.
        // Let's test Graph instead where it's Conservative
        let mut collector2 = StatisticsCollector::new();
        // Graph base = 150ms, conservative mode = 1.5x = 225ms estimated
        // Record actual latency of 50ms (ratio = 50/225 = 0.22 < 0.5) → Aggressive
        for _ in 0..15 {
            collector2.record_execution(Modality::Graph, 50.0, 10);
        }
        let adjustments2 = tuner.suggest_adjustments(&collector2, &config);
        let graph_adj = adjustments2.iter().find(|(m, _)| *m == Modality::Graph);
        assert!(graph_adj.is_some(), "Graph should have adjustment");
        assert_eq!(
            graph_adj.unwrap().1,
            crate::config::OptimizationMode::Aggressive,
            "Actual << estimated → Aggressive"
        );
    }

    #[test]
    fn test_adaptive_tuner_suggests_conservative_when_underestimating() {
        let tuner = AdaptiveTuner::new();
        let mut collector = StatisticsCollector::new();
        // Document base = 80ms, balanced mode = 1.0x = 80ms estimated
        // Record actual latency of 200ms (ratio = 200/80 = 2.5 > 2.0) → Conservative
        for _ in 0..15 {
            collector.record_execution(Modality::Document, 200.0, 50);
        }
        let config = crate::config::PlannerConfig::default();
        let adjustments = tuner.suggest_adjustments(&collector, &config);
        let doc_adj = adjustments.iter().find(|(m, _)| *m == Modality::Document);
        assert!(doc_adj.is_some(), "Document should have adjustment");
        assert_eq!(
            doc_adj.unwrap().1,
            crate::config::OptimizationMode::Conservative,
            "Actual >> estimated → Conservative"
        );
    }

    #[test]
    fn test_adaptive_tuner_apply_updates_config() {
        let tuner = AdaptiveTuner::new();
        let mut collector = StatisticsCollector::new();
        // Make Document wildly underestimated
        for _ in 0..15 {
            collector.record_execution(Modality::Document, 200.0, 50);
        }
        let config = crate::config::PlannerConfig::default();
        let new_config = tuner.apply(&collector, &config);
        assert_eq!(
            new_config.mode_for(Modality::Document),
            crate::config::OptimizationMode::Conservative,
        );
    }

    #[test]
    fn test_adaptive_tuner_disabled() {
        let tuner = AdaptiveTuner::new();
        let mut collector = StatisticsCollector::new();
        for _ in 0..15 {
            collector.record_execution(Modality::Document, 200.0, 50);
        }
        let mut config = crate::config::PlannerConfig::default();
        config.enable_adaptive = false;
        let new_config = tuner.apply(&collector, &config);
        // Should not change when adaptive is disabled
        assert_eq!(
            new_config.mode_for(Modality::Document),
            config.mode_for(Modality::Document),
        );
    }
}
