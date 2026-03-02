// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//! EXPLAIN ANALYZE query profiling.
//!
//! Extends the static EXPLAIN output with actual execution metrics collected
//! at runtime. A [`Profiler`] wraps a [`PhysicalPlan`] and records wall-clock
//! timings, actual row counts, and estimation accuracy for every step. Results
//! are fed back into the [`StatisticsCollector`] via
//! [`record_execution`](StatisticsCollector::record_execution) so the
//! [`AdaptiveTuner`] can refine future cost estimates.

use std::fmt;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::explain::{ExplainOutput, PerformanceHint};
use crate::plan::PhysicalPlan;
use crate::stats::StatisticsCollector;
use crate::Modality;

// ---------------------------------------------------------------------------
// ProfileStep — per-step actual metrics
// ---------------------------------------------------------------------------

/// Actual execution metrics for a single plan step.
///
/// Pairs the planner's estimates with observed wall-clock timings and row
/// counts so callers can evaluate estimation accuracy.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileStep {
    /// Human-readable name for this step (mirrors `PlanStep::operation`).
    pub step_name: String,
    /// Modality targeted by this step.
    pub modality: Modality,
    /// Cost the planner *estimated* for this step (milliseconds).
    pub estimated_ms: f64,
    /// Actual wall-clock duration observed (milliseconds).
    pub actual_ms: f64,
    /// Rows the planner *estimated* this step would return.
    pub estimated_rows: u64,
    /// Actual rows returned by the step.
    pub actual_rows: u64,
    /// Timestamp when execution of this step began.
    pub started_at: DateTime<Utc>,
    /// Timestamp when execution of this step completed.
    pub ended_at: DateTime<Utc>,
}

impl ProfileStep {
    /// Ratio of actual to estimated duration.
    ///
    /// - `1.0` means the estimate was perfect.
    /// - `> 1.0` means the step was *slower* than estimated.
    /// - `< 1.0` means the step was *faster* than estimated.
    ///
    /// Returns `f64::INFINITY` when `estimated_ms` is zero.
    pub fn time_accuracy_ratio(&self) -> f64 {
        if self.estimated_ms <= 0.0 {
            return f64::INFINITY;
        }
        self.actual_ms / self.estimated_ms
    }

    /// Ratio of actual to estimated row count.
    ///
    /// Same semantics as [`time_accuracy_ratio`](Self::time_accuracy_ratio).
    pub fn row_accuracy_ratio(&self) -> f64 {
        if self.estimated_rows == 0 {
            return f64::INFINITY;
        }
        self.actual_rows as f64 / self.estimated_rows as f64
    }
}

// ---------------------------------------------------------------------------
// QueryProfile — aggregated profile for an entire query
// ---------------------------------------------------------------------------

/// Aggregated profiling results for a fully-executed query plan.
///
/// Contains per-step breakdowns, totals, and automatically-generated
/// optimization hints when estimation error exceeds useful thresholds.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryProfile {
    /// Identifier for the physical plan that was profiled.
    pub plan_id: String,
    /// Per-step profiling data, in execution order.
    pub steps: Vec<ProfileStep>,
    /// Sum of all estimated step durations (milliseconds).
    pub total_estimated_ms: f64,
    /// Sum of all actual step durations (milliseconds).
    pub total_actual_ms: f64,
    /// Optimization hints derived from accuracy analysis.
    pub optimization_hints: Vec<String>,
}

impl QueryProfile {
    /// Overall time accuracy ratio (actual / estimated).
    pub fn total_time_accuracy_ratio(&self) -> f64 {
        if self.total_estimated_ms <= 0.0 {
            return f64::INFINITY;
        }
        self.total_actual_ms / self.total_estimated_ms
    }

    /// Render the profile as a human-readable EXPLAIN ANALYZE text block.
    pub fn render_text(&self, explain: &ExplainOutput) -> String {
        let mut out = String::new();

        out.push_str("=== VeriSimDB EXPLAIN ANALYZE ===\n\n");
        out.push_str(&format!("Plan ID: {}\n", self.plan_id));
        out.push_str(&format!("Strategy: {}\n", explain.strategy));
        out.push_str(&format!(
            "Total Estimated: {:.1}ms | Total Actual: {:.1}ms | Accuracy: {:.2}x\n\n",
            self.total_estimated_ms,
            self.total_actual_ms,
            self.total_time_accuracy_ratio(),
        ));

        out.push_str("--- Steps ---\n");
        for (i, step) in self.steps.iter().enumerate() {
            out.push_str(&format!(
                "  Step {}: {} [{}]\n",
                i + 1,
                step.step_name,
                step.modality
            ));
            out.push_str(&format!(
                "    Estimated: {:.1}ms / ~{} rows\n",
                step.estimated_ms, step.estimated_rows
            ));
            out.push_str(&format!(
                "    Actual:    {:.1}ms / {} rows\n",
                step.actual_ms, step.actual_rows
            ));
            out.push_str(&format!(
                "    Time accuracy: {:.2}x | Row accuracy: {:.2}x\n",
                step.time_accuracy_ratio(),
                step.row_accuracy_ratio()
            ));
        }

        if !self.optimization_hints.is_empty() {
            out.push_str("\n--- Optimization Hints ---\n");
            for hint in &self.optimization_hints {
                out.push_str(&format!("  * {}\n", hint));
            }
        }

        out
    }
}

impl fmt::Display for QueryProfile {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "QueryProfile(plan={}, steps={}, estimated={:.1}ms, actual={:.1}ms)",
            self.plan_id, self.steps.len(), self.total_estimated_ms, self.total_actual_ms)
    }
}

// ---------------------------------------------------------------------------
// Profiler — wraps a PhysicalPlan and collects execution metrics
// ---------------------------------------------------------------------------

/// Threshold above which a time-accuracy ratio triggers a "slower than
/// estimated" hint.
const SLOW_THRESHOLD: f64 = 2.0;

/// Threshold below which a time-accuracy ratio triggers a "faster than
/// estimated" hint.
const FAST_THRESHOLD: f64 = 0.5;

/// Threshold above which a row-accuracy ratio triggers a "more rows than
/// estimated" hint.
const ROW_OVER_THRESHOLD: f64 = 3.0;

/// Threshold below which a row-accuracy ratio triggers a "fewer rows than
/// estimated" hint.
const ROW_UNDER_THRESHOLD: f64 = 0.33;

/// Records actual execution metrics against a [`PhysicalPlan`] and produces
/// a [`QueryProfile`].
///
/// # Usage
///
/// ```ignore
/// let profiler = Profiler::new("query-42", &physical_plan);
///
/// // For each step, record actual timings:
/// profiler.record_step(0, 55.3, 12, started, ended);
/// profiler.record_step(1, 210.0, 185, started, ended);
///
/// let profile = profiler.finish(&mut stats_collector);
/// println!("{}", profile.render_text(&explain_output));
/// ```
pub struct Profiler {
    /// Identifier for the plan being profiled.
    plan_id: String,
    /// The physical plan whose execution is being measured.
    plan: PhysicalPlan,
    /// Collected step profiles (filled incrementally via `record_step`).
    recorded_steps: Vec<Option<ProfileStep>>,
}

impl Profiler {
    /// Create a new profiler for the given physical plan.
    ///
    /// `plan_id` is an opaque caller-chosen identifier (e.g. a query hash
    /// or UUID) embedded in the resulting [`QueryProfile`].
    pub fn new(plan_id: impl Into<String>, plan: &PhysicalPlan) -> Self {
        let step_count = plan.steps.len();
        Self {
            plan_id: plan_id.into(),
            plan: plan.clone(),
            recorded_steps: vec![None; step_count],
        }
    }

    /// Record actual execution metrics for step `step_index` (0-based).
    ///
    /// # Panics
    ///
    /// Panics if `step_index` is out of range for the underlying plan.
    pub fn record_step(
        &mut self,
        step_index: usize,
        actual_ms: f64,
        actual_rows: u64,
        started_at: DateTime<Utc>,
        ended_at: DateTime<Utc>,
    ) {
        assert!(
            step_index < self.plan.steps.len(),
            "step_index {} out of range (plan has {} steps)",
            step_index,
            self.plan.steps.len()
        );

        let plan_step = &self.plan.steps[step_index];
        self.recorded_steps[step_index] = Some(ProfileStep {
            step_name: plan_step.operation.clone(),
            modality: plan_step.modality,
            estimated_ms: plan_step.cost.time_ms,
            actual_ms,
            estimated_rows: plan_step.cost.estimated_rows,
            actual_rows,
            started_at,
            ended_at,
        });
    }

    /// Consume the profiler and produce a [`QueryProfile`].
    ///
    /// Any steps that were *not* recorded via [`record_step`](Self::record_step)
    /// are filled with zero actual values (and will generate accuracy hints).
    ///
    /// This method also feeds each step's actual latency and row count into
    /// the provided [`StatisticsCollector`] so the [`AdaptiveTuner`] can
    /// refine future estimates.
    pub fn finish(self, stats: &mut StatisticsCollector) -> QueryProfile {
        let mut steps: Vec<ProfileStep> = Vec::with_capacity(self.plan.steps.len());

        for (i, recorded) in self.recorded_steps.into_iter().enumerate() {
            let profile_step = match recorded {
                Some(s) => s,
                None => {
                    // Step was never recorded — fill with zero actuals.
                    let plan_step = &self.plan.steps[i];
                    let now = Utc::now();
                    ProfileStep {
                        step_name: plan_step.operation.clone(),
                        modality: plan_step.modality,
                        estimated_ms: plan_step.cost.time_ms,
                        actual_ms: 0.0,
                        estimated_rows: plan_step.cost.estimated_rows,
                        actual_rows: 0,
                        started_at: now,
                        ended_at: now,
                    }
                }
            };

            // Feed actuals into the statistics collector for adaptive tuning.
            stats.record_execution(
                profile_step.modality,
                profile_step.actual_ms,
                profile_step.actual_rows,
            );

            steps.push(profile_step);
        }

        let total_estimated_ms: f64 = steps.iter().map(|s| s.estimated_ms).sum();
        let total_actual_ms: f64 = steps.iter().map(|s| s.actual_ms).sum();
        let optimization_hints = generate_hints(&steps, total_estimated_ms, total_actual_ms);

        QueryProfile {
            plan_id: self.plan_id,
            steps,
            total_estimated_ms,
            total_actual_ms,
            optimization_hints,
        }
    }
}

// ---------------------------------------------------------------------------
// ExplainOutput extension — ANALYZE integration
// ---------------------------------------------------------------------------

impl ExplainOutput {
    /// Merge profiling results into this EXPLAIN output to produce an
    /// EXPLAIN ANALYZE rendering.
    ///
    /// Returns a combined output that contains both the original plan details
    /// and the actual execution metrics.
    pub fn with_profile(&self, profile: &QueryProfile) -> ExplainAnalyzeOutput {
        let mut hints: Vec<PerformanceHint> = self.performance_hints.clone();

        // Append profiler-generated hints as PerformanceHint structs.
        for hint_text in &profile.optimization_hints {
            hints.push(PerformanceHint {
                severity: "analyze".to_string(),
                message: hint_text.clone(),
            });
        }

        ExplainAnalyzeOutput {
            explain: self.clone(),
            profile: profile.clone(),
            combined_hints: hints,
            text_output: profile.render_text(self),
        }
    }
}

/// Combined EXPLAIN ANALYZE output containing both plan estimates and actual
/// execution metrics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExplainAnalyzeOutput {
    /// Original EXPLAIN output (estimates only).
    pub explain: ExplainOutput,
    /// Actual execution profile.
    pub profile: QueryProfile,
    /// Merged performance + profiling hints.
    pub combined_hints: Vec<PerformanceHint>,
    /// Human-readable EXPLAIN ANALYZE text.
    pub text_output: String,
}

impl fmt::Display for ExplainAnalyzeOutput {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.text_output)
    }
}

// ---------------------------------------------------------------------------
// Hint generation
// ---------------------------------------------------------------------------

/// Analyze per-step accuracy and produce actionable optimization hints.
fn generate_hints(
    steps: &[ProfileStep],
    total_estimated_ms: f64,
    total_actual_ms: f64,
) -> Vec<String> {
    let mut hints = Vec::new();

    // Overall accuracy hint.
    if total_estimated_ms > 0.0 {
        let overall_ratio = total_actual_ms / total_estimated_ms;
        if overall_ratio > SLOW_THRESHOLD {
            hints.push(format!(
                "Query was {:.1}x slower than estimated ({:.0}ms actual vs {:.0}ms estimated) \
                 — planner may be underestimating costs",
                overall_ratio, total_actual_ms, total_estimated_ms
            ));
        } else if overall_ratio < FAST_THRESHOLD {
            hints.push(format!(
                "Query was {:.1}x faster than estimated ({:.0}ms actual vs {:.0}ms estimated) \
                 — planner may be overestimating costs",
                overall_ratio, total_actual_ms, total_estimated_ms
            ));
        }
    }

    // Per-step time accuracy hints.
    for step in steps {
        let time_ratio = step.time_accuracy_ratio();
        if time_ratio > SLOW_THRESHOLD && time_ratio.is_finite() {
            hints.push(format!(
                "Step '{}' [{}]: {:.1}x slower than estimated ({:.0}ms vs {:.0}ms) \
                 — consider updating cost model for this modality",
                step.step_name, step.modality, time_ratio, step.actual_ms, step.estimated_ms
            ));
        } else if time_ratio < FAST_THRESHOLD {
            hints.push(format!(
                "Step '{}' [{}]: {:.1}x faster than estimated ({:.0}ms vs {:.0}ms) \
                 — aggressive mode may be appropriate",
                step.step_name, step.modality, time_ratio, step.actual_ms, step.estimated_ms
            ));
        }
    }

    // Per-step row accuracy hints.
    for step in steps {
        let row_ratio = step.row_accuracy_ratio();
        if row_ratio > ROW_OVER_THRESHOLD && row_ratio.is_finite() {
            hints.push(format!(
                "Step '{}' [{}]: returned {:.1}x more rows than estimated ({} vs {}) \
                 — selectivity estimate may be too low",
                step.step_name, step.modality, row_ratio, step.actual_rows, step.estimated_rows
            ));
        } else if row_ratio < ROW_UNDER_THRESHOLD && step.estimated_rows > 0 {
            hints.push(format!(
                "Step '{}' [{}]: returned {:.1}x fewer rows than estimated ({} vs {}) \
                 — selectivity estimate may be too high",
                step.step_name, step.modality, row_ratio, step.actual_rows, step.estimated_rows
            ));
        }
    }

    hints
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::PlannerConfig;
    use crate::cost::CostEstimate;
    use crate::plan::{ExecutionStrategy, PhysicalPlan, PlanStep};
    use chrono::Duration;

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// Build a simple two-step physical plan for testing.
    fn two_step_plan() -> PhysicalPlan {
        PhysicalPlan {
            steps: vec![
                PlanStep {
                    step: 1,
                    operation: "Vector similarity search (1 conditions)".to_string(),
                    modality: Modality::Vector,
                    cost: CostEstimate {
                        time_ms: 40.0,
                        estimated_rows: 10,
                        selectivity: 0.005,
                        io_cost: 24.0,
                        cpu_cost: 16.0,
                    },
                    optimization_hint: Some("HNSW ANN search (k=10)".to_string()),
                    pushed_predicates: vec!["Similarity { k: 10 }".to_string()],
                },
                PlanStep {
                    step: 2,
                    operation: "Graph traversal (1 conditions)".to_string(),
                    modality: Modality::Graph,
                    cost: CostEstimate {
                        time_ms: 225.0,
                        estimated_rows: 200,
                        selectivity: 0.4,
                        io_cost: 135.0,
                        cpu_cost: 90.0,
                    },
                    optimization_hint: Some("Graph traversal: relates_to (depth=2)".to_string()),
                    pushed_predicates: vec!["Traversal { predicate: relates_to }".to_string()],
                },
            ],
            strategy: ExecutionStrategy::Parallel,
            total_cost: CostEstimate {
                time_ms: 225.0,
                estimated_rows: 200,
                selectivity: 0.002,
                io_cost: 159.0,
                cpu_cost: 106.0,
            },
            notes: vec!["Parallel execution across 2 modalities".to_string()],
        }
    }

    fn make_timestamps(base: DateTime<Utc>, duration_ms: f64) -> (DateTime<Utc>, DateTime<Utc>) {
        let end = base + Duration::milliseconds(duration_ms as i64);
        (base, end)
    }

    // -----------------------------------------------------------------------
    // Test 1: Profile with known durations
    // -----------------------------------------------------------------------

    #[test]
    fn test_profile_with_known_durations() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("test-query-1", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();
        let (s0, e0) = make_timestamps(base, 35.0);
        let (s1, e1) = make_timestamps(base, 250.0);

        profiler.record_step(0, 35.0, 8, s0, e0);
        profiler.record_step(1, 250.0, 180, s1, e1);

        let profile = profiler.finish(&mut stats);

        assert_eq!(profile.plan_id, "test-query-1");
        assert_eq!(profile.steps.len(), 2);
        assert!((profile.steps[0].actual_ms - 35.0).abs() < f64::EPSILON);
        assert!((profile.steps[1].actual_ms - 250.0).abs() < f64::EPSILON);
        assert_eq!(profile.steps[0].actual_rows, 8);
        assert_eq!(profile.steps[1].actual_rows, 180);
    }

    // -----------------------------------------------------------------------
    // Test 2: Accuracy ratio calculation
    // -----------------------------------------------------------------------

    #[test]
    fn test_accuracy_ratio_calculation() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("ratio-test", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();

        // Step 0: estimated 40ms, actual 35ms → ratio 0.875
        let (s0, e0) = make_timestamps(base, 35.0);
        profiler.record_step(0, 35.0, 10, s0, e0);

        // Step 1: estimated 225ms, actual 450ms → ratio 2.0
        let (s1, e1) = make_timestamps(base, 450.0);
        profiler.record_step(1, 450.0, 200, s1, e1);

        let profile = profiler.finish(&mut stats);

        // Step 0 time accuracy: 35 / 40 = 0.875
        let ratio_0 = profile.steps[0].time_accuracy_ratio();
        assert!((ratio_0 - 0.875).abs() < 0.001, "Expected 0.875, got {}", ratio_0);

        // Step 1 time accuracy: 450 / 225 = 2.0
        let ratio_1 = profile.steps[1].time_accuracy_ratio();
        assert!((ratio_1 - 2.0).abs() < 0.001, "Expected 2.0, got {}", ratio_1);

        // Row accuracy for step 0: 10 / 10 = 1.0 (perfect)
        let row_ratio_0 = profile.steps[0].row_accuracy_ratio();
        assert!((row_ratio_0 - 1.0).abs() < 0.001);

        // Row accuracy for step 1: 200 / 200 = 1.0 (perfect)
        let row_ratio_1 = profile.steps[1].row_accuracy_ratio();
        assert!((row_ratio_1 - 1.0).abs() < 0.001);
    }

    // -----------------------------------------------------------------------
    // Test 3: Hints generated for large estimation errors (time)
    // -----------------------------------------------------------------------

    #[test]
    fn test_hints_for_large_time_errors() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("slow-query", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();

        // Step 0: estimated 40ms, actual 200ms → 5x slower → should generate hint
        let (s0, e0) = make_timestamps(base, 200.0);
        profiler.record_step(0, 200.0, 10, s0, e0);

        // Step 1: estimated 225ms, actual 900ms → 4x slower → should generate hint
        let (s1, e1) = make_timestamps(base, 900.0);
        profiler.record_step(1, 900.0, 200, s1, e1);

        let profile = profiler.finish(&mut stats);

        // Should have at least the overall "slower than estimated" hint
        assert!(
            !profile.optimization_hints.is_empty(),
            "Expected hints for large estimation errors"
        );

        let has_slow_hint = profile.optimization_hints.iter().any(|h| h.contains("slower"));
        assert!(
            has_slow_hint,
            "Expected a 'slower than estimated' hint, got: {:?}",
            profile.optimization_hints
        );
    }

    // -----------------------------------------------------------------------
    // Test 4: Hints generated for large estimation errors (rows)
    // -----------------------------------------------------------------------

    #[test]
    fn test_hints_for_large_row_errors() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("row-mismatch", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();

        // Step 0: estimated 10 rows, actual 50 rows → 5x more → hint
        let (s0, e0) = make_timestamps(base, 40.0);
        profiler.record_step(0, 40.0, 50, s0, e0);

        // Step 1: estimated 200 rows, actual 10 rows → 0.05x fewer → hint
        let (s1, e1) = make_timestamps(base, 225.0);
        profiler.record_step(1, 225.0, 10, s1, e1);

        let profile = profiler.finish(&mut stats);

        let has_row_over = profile.optimization_hints.iter().any(|h| h.contains("more rows"));
        assert!(
            has_row_over,
            "Expected 'more rows than estimated' hint, got: {:?}",
            profile.optimization_hints
        );

        let has_row_under = profile.optimization_hints.iter().any(|h| h.contains("fewer rows"));
        assert!(
            has_row_under,
            "Expected 'fewer rows than estimated' hint, got: {:?}",
            profile.optimization_hints
        );
    }

    // -----------------------------------------------------------------------
    // Test 5: Total time calculation
    // -----------------------------------------------------------------------

    #[test]
    fn test_total_time_calculation() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("total-time", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();
        let (s0, e0) = make_timestamps(base, 50.0);
        let (s1, e1) = make_timestamps(base, 300.0);

        profiler.record_step(0, 50.0, 10, s0, e0);
        profiler.record_step(1, 300.0, 200, s1, e1);

        let profile = profiler.finish(&mut stats);

        // Total estimated = 40 + 225 = 265
        assert!(
            (profile.total_estimated_ms - 265.0).abs() < f64::EPSILON,
            "Expected total_estimated_ms=265.0, got {}",
            profile.total_estimated_ms
        );

        // Total actual = 50 + 300 = 350
        assert!(
            (profile.total_actual_ms - 350.0).abs() < f64::EPSILON,
            "Expected total_actual_ms=350.0, got {}",
            profile.total_actual_ms
        );

        // Overall ratio = 350 / 265 ≈ 1.3208
        let overall = profile.total_time_accuracy_ratio();
        assert!(
            (overall - 350.0 / 265.0).abs() < 0.001,
            "Expected ratio ~1.321, got {}",
            overall
        );
    }

    // -----------------------------------------------------------------------
    // Test 6: Auto-feed results into StatisticsCollector
    // -----------------------------------------------------------------------

    #[test]
    fn test_auto_feed_statistics() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("feed-test", &plan);
        let mut stats = StatisticsCollector::new();

        // Verify initial state: zero queries for Vector and Graph
        assert_eq!(stats.get(Modality::Vector).unwrap().query_count, 0);
        assert_eq!(stats.get(Modality::Graph).unwrap().query_count, 0);

        let base = Utc::now();
        let (s0, e0) = make_timestamps(base, 42.0);
        let (s1, e1) = make_timestamps(base, 180.0);

        profiler.record_step(0, 42.0, 12, s0, e0);
        profiler.record_step(1, 180.0, 190, s1, e1);

        let _profile = profiler.finish(&mut stats);

        // After finish(), stats should have recorded one execution per modality
        let vector_stats = stats.get(Modality::Vector).unwrap();
        assert_eq!(vector_stats.query_count, 1);
        assert!((vector_stats.avg_latency_ms - 42.0).abs() < f64::EPSILON);
        assert_eq!(vector_stats.avg_rows_returned, 12);

        let graph_stats = stats.get(Modality::Graph).unwrap();
        assert_eq!(graph_stats.query_count, 1);
        assert!((graph_stats.avg_latency_ms - 180.0).abs() < f64::EPSILON);
        assert_eq!(graph_stats.avg_rows_returned, 190);
    }

    // -----------------------------------------------------------------------
    // Test 7: Integration with ExplainOutput (ANALYZE rendering)
    // -----------------------------------------------------------------------

    #[test]
    fn test_explain_analyze_integration() {
        let plan = two_step_plan();
        let config = PlannerConfig::default();
        let explain = ExplainOutput::from_physical_plan(&plan, &config);

        let mut profiler = Profiler::new("analyze-test", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();
        let (s0, e0) = make_timestamps(base, 38.0);
        let (s1, e1) = make_timestamps(base, 220.0);

        profiler.record_step(0, 38.0, 9, s0, e0);
        profiler.record_step(1, 220.0, 195, s1, e1);

        let profile = profiler.finish(&mut stats);
        let analyze = explain.with_profile(&profile);

        // Text output should contain EXPLAIN ANALYZE header
        assert!(analyze.text_output.contains("EXPLAIN ANALYZE"));
        // Should contain actual metrics
        assert!(analyze.text_output.contains("Actual:"));
        // Should contain estimated metrics
        assert!(analyze.text_output.contains("Estimated:"));
        // Should reference both modalities
        assert!(analyze.text_output.contains("vector"));
        assert!(analyze.text_output.contains("graph"));
        // Display trait should work
        let display = format!("{}", analyze);
        assert!(!display.is_empty());
    }

    // -----------------------------------------------------------------------
    // Test 8: Unrecorded steps produce zero actuals
    // -----------------------------------------------------------------------

    #[test]
    fn test_unrecorded_steps_produce_zero_actuals() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("partial-record", &plan);
        let mut stats = StatisticsCollector::new();

        // Only record step 0, leave step 1 unrecorded
        let base = Utc::now();
        let (s0, e0) = make_timestamps(base, 50.0);
        profiler.record_step(0, 50.0, 8, s0, e0);

        let profile = profiler.finish(&mut stats);

        assert_eq!(profile.steps.len(), 2);
        // Step 1 should have zero actual values
        assert!((profile.steps[1].actual_ms - 0.0).abs() < f64::EPSILON);
        assert_eq!(profile.steps[1].actual_rows, 0);
    }

    // -----------------------------------------------------------------------
    // Test 9: Fast query generates "overestimating" hints
    // -----------------------------------------------------------------------

    #[test]
    fn test_fast_query_overestimating_hints() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("fast-query", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();
        // Both steps are much faster than estimated
        let (s0, e0) = make_timestamps(base, 5.0);  // estimated 40ms
        let (s1, e1) = make_timestamps(base, 20.0); // estimated 225ms

        profiler.record_step(0, 5.0, 10, s0, e0);
        profiler.record_step(1, 20.0, 200, s1, e1);

        let profile = profiler.finish(&mut stats);

        let has_fast_hint = profile.optimization_hints.iter().any(|h| h.contains("faster"));
        assert!(
            has_fast_hint,
            "Expected 'faster than estimated' hint, got: {:?}",
            profile.optimization_hints
        );
    }

    // -----------------------------------------------------------------------
    // Test 10: QueryProfile display trait
    // -----------------------------------------------------------------------

    #[test]
    fn test_query_profile_display() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("display-test", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();
        let (s0, e0) = make_timestamps(base, 40.0);
        let (s1, e1) = make_timestamps(base, 225.0);

        profiler.record_step(0, 40.0, 10, s0, e0);
        profiler.record_step(1, 225.0, 200, s1, e1);

        let profile = profiler.finish(&mut stats);
        let display = format!("{}", profile);

        assert!(display.contains("display-test"));
        assert!(display.contains("steps=2"));
    }

    // -----------------------------------------------------------------------
    // Test 11: JSON serialization round-trip
    // -----------------------------------------------------------------------

    #[test]
    fn test_query_profile_json_roundtrip() {
        let plan = two_step_plan();
        let mut profiler = Profiler::new("serde-test", &plan);
        let mut stats = StatisticsCollector::new();

        let base = Utc::now();
        let (s0, e0) = make_timestamps(base, 40.0);
        let (s1, e1) = make_timestamps(base, 225.0);

        profiler.record_step(0, 40.0, 10, s0, e0);
        profiler.record_step(1, 225.0, 200, s1, e1);

        let profile = profiler.finish(&mut stats);

        let json = serde_json::to_string(&profile).unwrap();
        let parsed: QueryProfile = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.plan_id, "serde-test");
        assert_eq!(parsed.steps.len(), 2);
        assert!((parsed.total_estimated_ms - profile.total_estimated_ms).abs() < f64::EPSILON);
        assert!((parsed.total_actual_ms - profile.total_actual_ms).abs() < f64::EPSILON);
    }

    // -----------------------------------------------------------------------
    // Test 12: Zero estimated_ms produces INFINITY ratio
    // -----------------------------------------------------------------------

    #[test]
    fn test_zero_estimated_produces_infinity_ratio() {
        let now = Utc::now();
        let step = ProfileStep {
            step_name: "zero-est".to_string(),
            modality: Modality::Temporal,
            estimated_ms: 0.0,
            actual_ms: 10.0,
            estimated_rows: 0,
            actual_rows: 5,
            started_at: now,
            ended_at: now,
        };

        assert!(step.time_accuracy_ratio().is_infinite());
        assert!(step.row_accuracy_ratio().is_infinite());
    }
}
