// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! Slow query log for VeriSimDB.
//!
//! Records queries that exceed a configurable duration threshold.
//! Integrates with the `tracing` framework to emit structured log events
//! and maintains an in-memory ring buffer for recent slow queries.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::RwLock;
use tracing::warn;

use crate::plan::{ExecutionStrategy, PhysicalPlan};
use crate::Modality;

/// Configuration for the slow query log.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlowQueryConfig {
    /// Queries taking longer than this (milliseconds) are logged.
    /// Default: 100ms.
    pub threshold_ms: f64,

    /// Maximum number of entries to keep in the ring buffer.
    /// Default: 1000.
    pub max_entries: usize,

    /// Whether slow query logging is enabled.
    /// Default: true.
    pub enabled: bool,

    /// Log queries that use more than this many modalities.
    /// Set to 0 to disable this check.
    /// Default: 0 (disabled).
    pub multi_modality_threshold: usize,
}

impl Default for SlowQueryConfig {
    fn default() -> Self {
        Self {
            threshold_ms: 100.0,
            max_entries: 1000,
            enabled: true,
            multi_modality_threshold: 0,
        }
    }
}

/// A single slow query log entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlowQueryEntry {
    /// When the query was recorded.
    pub timestamp: DateTime<Utc>,

    /// The VQL query text (if available).
    pub query_text: Option<String>,

    /// Actual execution time in milliseconds.
    pub actual_ms: f64,

    /// Estimated execution time from planner (milliseconds).
    pub estimated_ms: f64,

    /// Ratio of actual to estimated (>1 means slower than expected).
    pub slowdown_ratio: f64,

    /// Execution strategy used.
    pub strategy: String,

    /// Modalities involved.
    pub modalities: Vec<Modality>,

    /// Number of rows returned.
    pub rows_returned: usize,

    /// Which step was the bottleneck.
    pub bottleneck: Option<BottleneckInfo>,
}

/// Information about the slowest step in a query.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BottleneckInfo {
    /// Modality of the bottleneck step.
    pub modality: Modality,

    /// Step name/operation.
    pub operation: String,

    /// Time spent on this step (ms).
    pub time_ms: f64,

    /// Percentage of total query time.
    pub percentage: f64,
}

/// Slow query log — ring buffer with tracing integration.
pub struct SlowQueryLog {
    config: RwLock<SlowQueryConfig>,
    entries: RwLock<VecDeque<SlowQueryEntry>>,
}

impl SlowQueryLog {
    /// Create a new slow query log with the given configuration.
    pub fn new(config: SlowQueryConfig) -> Self {
        Self {
            config: RwLock::new(config),
            entries: RwLock::new(VecDeque::new()),
        }
    }

    /// Create with default configuration.
    pub fn with_defaults() -> Self {
        Self::new(SlowQueryConfig::default())
    }

    /// Record a query execution. If it exceeds the threshold, it is logged.
    ///
    /// Returns `true` if the query was recorded as slow.
    pub fn record(
        &self,
        query_text: Option<&str>,
        actual_ms: f64,
        plan: &PhysicalPlan,
        step_times: &[(Modality, f64, usize)], // (modality, time_ms, rows)
    ) -> bool {
        let config = self.config.read().unwrap();
        if !config.enabled {
            return false;
        }

        let is_slow = actual_ms >= config.threshold_ms;
        let is_multi = config.multi_modality_threshold > 0
            && plan.steps.len() >= config.multi_modality_threshold;

        if !is_slow && !is_multi {
            return false;
        }

        let estimated_ms = plan.total_cost.time_ms;
        let slowdown_ratio = if estimated_ms > 0.0 {
            actual_ms / estimated_ms
        } else {
            f64::INFINITY
        };

        let modalities: Vec<Modality> = plan.steps.iter().map(|s| s.modality).collect();

        // Find bottleneck
        let bottleneck = step_times
            .iter()
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(modality, time_ms, _rows)| {
                let percentage = if actual_ms > 0.0 {
                    (time_ms / actual_ms) * 100.0
                } else {
                    0.0
                };
                BottleneckInfo {
                    modality: *modality,
                    operation: format!("{} query", modality),
                    time_ms: *time_ms,
                    percentage,
                }
            });

        let total_rows: usize = step_times.iter().map(|(_, _, r)| r).sum();
        let strategy = match plan.strategy {
            ExecutionStrategy::Sequential => "sequential".to_string(),
            ExecutionStrategy::Parallel => "parallel".to_string(),
        };

        let entry = SlowQueryEntry {
            timestamp: Utc::now(),
            query_text: query_text.map(|s| s.to_string()),
            actual_ms,
            estimated_ms,
            slowdown_ratio,
            strategy,
            modalities: modalities.clone(),
            rows_returned: total_rows,
            bottleneck: bottleneck.clone(),
        };

        // Emit tracing warning
        let modality_names: Vec<String> = modalities.iter().map(|m| m.to_string()).collect();
        let bottleneck_desc = bottleneck
            .as_ref()
            .map(|b| format!("{} ({:.0}ms, {:.0}%)", b.modality, b.time_ms, b.percentage))
            .unwrap_or_else(|| "unknown".to_string());

        warn!(
            actual_ms = actual_ms,
            estimated_ms = estimated_ms,
            slowdown_ratio = slowdown_ratio,
            modalities = ?modality_names,
            rows = total_rows,
            bottleneck = %bottleneck_desc,
            query = query_text.unwrap_or("<unknown>"),
            "Slow query detected"
        );

        // Insert into ring buffer
        let max_entries = config.max_entries;
        drop(config);

        let mut entries = self.entries.write().unwrap();
        entries.push_back(entry);
        while entries.len() > max_entries {
            entries.pop_front();
        }

        true
    }

    /// Get recent slow queries.
    pub fn recent(&self, limit: usize) -> Vec<SlowQueryEntry> {
        let entries = self.entries.read().unwrap();
        entries.iter().rev().take(limit).cloned().collect()
    }

    /// Get all slow queries.
    pub fn all(&self) -> Vec<SlowQueryEntry> {
        self.entries.read().unwrap().iter().cloned().collect()
    }

    /// Get the count of recorded slow queries.
    pub fn count(&self) -> usize {
        self.entries.read().unwrap().len()
    }

    /// Clear the slow query log.
    pub fn clear(&self) {
        self.entries.write().unwrap().clear();
    }

    /// Update configuration.
    pub fn set_config(&self, config: SlowQueryConfig) {
        *self.config.write().unwrap() = config;
    }

    /// Get current configuration.
    pub fn config(&self) -> SlowQueryConfig {
        self.config.read().unwrap().clone()
    }

    /// Summary statistics.
    pub fn summary(&self) -> SlowQuerySummary {
        let entries = self.entries.read().unwrap();
        if entries.is_empty() {
            return SlowQuerySummary::default();
        }

        let total = entries.len();
        let sum_ms: f64 = entries.iter().map(|e| e.actual_ms).sum();
        let max_ms = entries
            .iter()
            .map(|e| e.actual_ms)
            .fold(0.0_f64, f64::max);
        let min_ms = entries
            .iter()
            .map(|e| e.actual_ms)
            .fold(f64::INFINITY, f64::min);
        let avg_ms = sum_ms / total as f64;
        let avg_ratio: f64 = entries.iter().map(|e| e.slowdown_ratio).sum::<f64>() / total as f64;

        // Most common bottleneck modality
        let mut modality_counts = std::collections::HashMap::new();
        for entry in entries.iter() {
            if let Some(ref b) = entry.bottleneck {
                *modality_counts.entry(b.modality).or_insert(0u64) += 1;
            }
        }
        let top_bottleneck = modality_counts
            .into_iter()
            .max_by_key(|&(_, count)| count)
            .map(|(m, _)| m);

        SlowQuerySummary {
            total_count: total,
            avg_ms,
            max_ms,
            min_ms,
            avg_slowdown_ratio: avg_ratio,
            top_bottleneck_modality: top_bottleneck,
        }
    }
}

/// Summary statistics for the slow query log.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SlowQuerySummary {
    pub total_count: usize,
    pub avg_ms: f64,
    pub max_ms: f64,
    pub min_ms: f64,
    pub avg_slowdown_ratio: f64,
    pub top_bottleneck_modality: Option<Modality>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cost::CostEstimate;
    use crate::plan::PlanStep;

    fn make_plan(steps: Vec<(Modality, f64)>) -> PhysicalPlan {
        let total_ms: f64 = steps.iter().map(|(_, ms)| ms).sum();
        PhysicalPlan {
            steps: steps
                .iter()
                .enumerate()
                .map(|(i, (m, ms))| PlanStep {
                    step: i + 1,
                    operation: format!("{} query", m),
                    modality: *m,
                    cost: CostEstimate {
                        time_ms: *ms,
                        estimated_rows: 100,
                        selectivity: 0.5,
                        io_cost: ms * 0.6,
                        cpu_cost: ms * 0.4,
                    },
                    optimization_hint: None,
                    pushed_predicates: vec![],
                })
                .collect(),
            strategy: if steps.len() >= 2 {
                ExecutionStrategy::Parallel
            } else {
                ExecutionStrategy::Sequential
            },
            total_cost: CostEstimate {
                time_ms: total_ms,
                estimated_rows: 100,
                selectivity: 0.5,
                io_cost: total_ms * 0.6,
                cpu_cost: total_ms * 0.4,
            },
            notes: vec![],
        }
    }

    #[test]
    fn test_fast_query_not_logged() {
        let log = SlowQueryLog::with_defaults();
        let plan = make_plan(vec![(Modality::Vector, 30.0)]);
        let step_times = vec![(Modality::Vector, 30.0, 10)];

        let was_slow = log.record(Some("SELECT VECTOR FROM HEXAD"), 30.0, &plan, &step_times);
        assert!(!was_slow);
        assert_eq!(log.count(), 0);
    }

    #[test]
    fn test_slow_query_logged() {
        let log = SlowQueryLog::with_defaults();
        let plan = make_plan(vec![(Modality::Semantic, 50.0)]);
        let step_times = vec![(Modality::Semantic, 150.0, 5)];

        let was_slow =
            log.record(Some("SELECT SEMANTIC FROM HEXAD"), 150.0, &plan, &step_times);
        assert!(was_slow);
        assert_eq!(log.count(), 1);

        let entries = log.recent(10);
        assert_eq!(entries.len(), 1);
        assert!(entries[0].actual_ms >= 100.0);
        assert_eq!(entries[0].modalities, vec![Modality::Semantic]);
    }

    #[test]
    fn test_custom_threshold() {
        let config = SlowQueryConfig {
            threshold_ms: 50.0,
            ..Default::default()
        };
        let log = SlowQueryLog::new(config);
        let plan = make_plan(vec![(Modality::Graph, 40.0)]);
        let step_times = vec![(Modality::Graph, 60.0, 20)];

        let was_slow = log.record(Some("SELECT GRAPH FROM HEXAD"), 60.0, &plan, &step_times);
        assert!(was_slow);
        assert_eq!(log.count(), 1);
    }

    #[test]
    fn test_disabled_log() {
        let config = SlowQueryConfig {
            enabled: false,
            ..Default::default()
        };
        let log = SlowQueryLog::new(config);
        let plan = make_plan(vec![(Modality::Semantic, 50.0)]);
        let step_times = vec![(Modality::Semantic, 500.0, 5)];

        let was_slow = log.record(Some("SELECT SEMANTIC"), 500.0, &plan, &step_times);
        assert!(!was_slow);
        assert_eq!(log.count(), 0);
    }

    #[test]
    fn test_ring_buffer_eviction() {
        let config = SlowQueryConfig {
            threshold_ms: 10.0,
            max_entries: 3,
            ..Default::default()
        };
        let log = SlowQueryLog::new(config);
        let plan = make_plan(vec![(Modality::Vector, 5.0)]);

        for i in 0..5 {
            let step_times = vec![(Modality::Vector, 20.0 + i as f64, 1)];
            log.record(Some(&format!("query-{i}")), 20.0 + i as f64, &plan, &step_times);
        }

        assert_eq!(log.count(), 3);
        // Most recent entries should remain
        let entries = log.all();
        assert!(entries[0].actual_ms >= 22.0);
    }

    #[test]
    fn test_bottleneck_detection() {
        let log = SlowQueryLog::with_defaults();
        let plan = make_plan(vec![
            (Modality::Vector, 30.0),
            (Modality::Semantic, 200.0),
        ]);
        let step_times = vec![
            (Modality::Vector, 25.0, 10),
            (Modality::Semantic, 180.0, 5),
        ];

        log.record(Some("multi-modality query"), 205.0, &plan, &step_times);

        let entries = log.recent(1);
        assert_eq!(entries.len(), 1);
        let bottleneck = entries[0].bottleneck.as_ref().unwrap();
        assert_eq!(bottleneck.modality, Modality::Semantic);
        assert!(bottleneck.percentage > 80.0);
    }

    #[test]
    fn test_slowdown_ratio() {
        let log = SlowQueryLog::with_defaults();
        let plan = make_plan(vec![(Modality::Graph, 50.0)]);
        let step_times = vec![(Modality::Graph, 200.0, 100)];

        log.record(Some("slow graph query"), 200.0, &plan, &step_times);

        let entries = log.recent(1);
        // estimated 50ms, actual 200ms → ratio 4.0
        assert!((entries[0].slowdown_ratio - 4.0).abs() < 0.01);
    }

    #[test]
    fn test_clear() {
        let log = SlowQueryLog::with_defaults();
        let plan = make_plan(vec![(Modality::Tensor, 50.0)]);
        let step_times = vec![(Modality::Tensor, 150.0, 5)];

        log.record(Some("q1"), 150.0, &plan, &step_times);
        assert_eq!(log.count(), 1);

        log.clear();
        assert_eq!(log.count(), 0);
    }

    #[test]
    fn test_summary_stats() {
        let config = SlowQueryConfig {
            threshold_ms: 10.0,
            ..Default::default()
        };
        let log = SlowQueryLog::new(config);
        let plan = make_plan(vec![(Modality::Vector, 10.0)]);

        for ms in [50.0, 100.0, 150.0] {
            let step_times = vec![(Modality::Vector, ms, 10)];
            log.record(None, ms, &plan, &step_times);
        }

        let summary = log.summary();
        assert_eq!(summary.total_count, 3);
        assert!((summary.avg_ms - 100.0).abs() < 0.01);
        assert!((summary.max_ms - 150.0).abs() < 0.01);
        assert!((summary.min_ms - 50.0).abs() < 0.01);
        assert_eq!(summary.top_bottleneck_modality, Some(Modality::Vector));
    }

    #[test]
    fn test_empty_summary() {
        let log = SlowQueryLog::with_defaults();
        let summary = log.summary();
        assert_eq!(summary.total_count, 0);
        assert_eq!(summary.top_bottleneck_modality, None);
    }

    #[test]
    fn test_config_update() {
        let log = SlowQueryLog::with_defaults();
        assert!((log.config().threshold_ms - 100.0).abs() < f64::EPSILON);

        log.set_config(SlowQueryConfig {
            threshold_ms: 500.0,
            ..Default::default()
        });
        assert!((log.config().threshold_ms - 500.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_recent_ordering() {
        let config = SlowQueryConfig {
            threshold_ms: 10.0,
            ..Default::default()
        };
        let log = SlowQueryLog::new(config);
        let plan = make_plan(vec![(Modality::Document, 10.0)]);

        for ms in [20.0, 30.0, 40.0, 50.0] {
            let step_times = vec![(Modality::Document, ms, 1)];
            log.record(None, ms, &plan, &step_times);
        }

        // recent() should return newest first
        let recent = log.recent(2);
        assert_eq!(recent.len(), 2);
        assert!(recent[0].actual_ms >= recent[1].actual_ms);
    }

    #[test]
    fn test_json_serialization() {
        let config = SlowQueryConfig {
            threshold_ms: 10.0,
            ..Default::default()
        };
        let log = SlowQueryLog::new(config);
        let plan = make_plan(vec![(Modality::Temporal, 5.0)]);
        let step_times = vec![(Modality::Temporal, 20.0, 3)];

        log.record(Some("SELECT TEMPORAL FROM HEXAD"), 20.0, &plan, &step_times);

        let entries = log.recent(1);
        let json = serde_json::to_string(&entries[0]).unwrap();
        let parsed: SlowQueryEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.query_text, Some("SELECT TEMPORAL FROM HEXAD".to_string()));
    }
}
