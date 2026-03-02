// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Drift Detection
//!
//! Monitors cross-modal consistency degradation and triggers normalization.
//! This is the "early warning system" for data quality issues.

use chrono::{DateTime, Utc};
use prometheus::{Counter, Gauge, Registry};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;
use tokio::sync::mpsc;

// Drift calculation algorithms
mod calculator;
pub use calculator::{DriftCalculator, TensorStats};

/// Drift detection errors
#[derive(Error, Debug)]
pub enum DriftError {
    #[error("Metric not found: {0}")]
    MetricNotFound(String),

    #[error("Invalid threshold: {0}")]
    InvalidThreshold(String),

    #[error("Channel error: {0}")]
    ChannelError(String),

    #[error("Lock poisoned: internal concurrency error")]
    LockPoisoned,
}

/// Types of drift that can be detected
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum DriftType {
    /// Vector embeddings diverge from semantic meaning
    SemanticVectorDrift,
    /// Graph structure doesn't match document content
    GraphDocumentDrift,
    /// Temporal versions become inconsistent
    TemporalConsistencyDrift,
    /// Tensor representations diverge
    TensorDrift,
    /// Cross-modal schema violations
    SchemaDrift,
    /// Provenance chain integrity broken or lineage inconsistent
    ProvenanceDrift,
    /// Spatial coordinates inconsistent with graph/document location mentions
    SpatialDrift,
    /// Overall data quality degradation
    QualityDrift,
}

impl std::fmt::Display for DriftType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DriftType::SemanticVectorDrift => write!(f, "semantic_vector_drift"),
            DriftType::GraphDocumentDrift => write!(f, "graph_document_drift"),
            DriftType::TemporalConsistencyDrift => write!(f, "temporal_consistency_drift"),
            DriftType::TensorDrift => write!(f, "tensor_drift"),
            DriftType::SchemaDrift => write!(f, "schema_drift"),
            DriftType::ProvenanceDrift => write!(f, "provenance_drift"),
            DriftType::SpatialDrift => write!(f, "spatial_drift"),
            DriftType::QualityDrift => write!(f, "quality_drift"),
        }
    }
}

/// Severity levels for drift alerts
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum DriftSeverity {
    Info,
    Warning,
    Critical,
    Emergency,
}

/// A detected drift event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriftEvent {
    /// Type of drift
    pub drift_type: DriftType,
    /// Severity level
    pub severity: DriftSeverity,
    /// Affected entity IDs
    pub affected_entities: Vec<String>,
    /// Drift score (0.0 - 1.0, higher = worse)
    pub score: f64,
    /// When detected
    pub detected_at: DateTime<Utc>,
    /// Description
    pub description: String,
    /// Suggested remediation
    pub remediation: Option<String>,
}

impl DriftEvent {
    /// Create a new drift event
    pub fn new(drift_type: DriftType, score: f64, description: impl Into<String>) -> Self {
        let severity = if score > 0.9 {
            DriftSeverity::Emergency
        } else if score > 0.7 {
            DriftSeverity::Critical
        } else if score > 0.5 {
            DriftSeverity::Warning
        } else {
            DriftSeverity::Info
        };

        Self {
            drift_type,
            severity,
            affected_entities: Vec::new(),
            score,
            detected_at: Utc::now(),
            description: description.into(),
            remediation: None,
        }
    }

    /// Add affected entities
    pub fn with_entities(mut self, entities: Vec<String>) -> Self {
        self.affected_entities = entities;
        self
    }

    /// Add remediation suggestion
    pub fn with_remediation(mut self, remediation: impl Into<String>) -> Self {
        self.remediation = Some(remediation.into());
        self
    }
}

/// Threshold policy for drift detection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ThresholdPolicy {
    /// Fixed threshold value
    Fixed(f64),
    /// Adaptive threshold: base + (moving_avg * sensitivity)
    Adaptive { base: f64, sensitivity: f64 },
}

impl ThresholdPolicy {
    /// Compute the effective threshold given the current moving average
    pub fn effective_threshold(&self, moving_average: f64) -> f64 {
        match self {
            ThresholdPolicy::Fixed(v) => *v,
            ThresholdPolicy::Adaptive { base, sensitivity } => {
                base + (moving_average * sensitivity)
            }
        }
    }
}

/// Threshold configuration for drift detection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriftThresholds {
    /// Threshold for semantic-vector drift
    pub semantic_vector: f64,
    /// Threshold for graph-document drift
    pub graph_document: f64,
    /// Threshold for temporal consistency drift
    pub temporal_consistency: f64,
    /// Threshold for tensor drift
    pub tensor: f64,
    /// Threshold for schema drift
    pub schema: f64,
    /// Threshold for provenance chain integrity drift
    pub provenance: f64,
    /// Threshold for spatial consistency drift
    pub spatial: f64,
    /// Threshold for overall quality drift
    pub quality: f64,
    /// Optional adaptive policies per drift type (overrides fixed thresholds)
    #[serde(default)]
    pub adaptive_policies: HashMap<DriftType, ThresholdPolicy>,
}

impl Default for DriftThresholds {
    fn default() -> Self {
        Self {
            semantic_vector: 0.3,
            graph_document: 0.4,
            temporal_consistency: 0.2,
            tensor: 0.35,
            schema: 0.1,
            provenance: 0.1,
            spatial: 0.3,
            quality: 0.25,
            adaptive_policies: HashMap::new(),
        }
    }
}

impl DriftThresholds {
    /// Get the effective threshold for a drift type, considering adaptive policies
    pub fn effective_threshold(&self, drift_type: DriftType, moving_average: f64) -> f64 {
        if let Some(policy) = self.adaptive_policies.get(&drift_type) {
            return policy.effective_threshold(moving_average);
        }
        // Fall back to fixed thresholds
        match drift_type {
            DriftType::SemanticVectorDrift => self.semantic_vector,
            DriftType::GraphDocumentDrift => self.graph_document,
            DriftType::TemporalConsistencyDrift => self.temporal_consistency,
            DriftType::TensorDrift => self.tensor,
            DriftType::SchemaDrift => self.schema,
            DriftType::ProvenanceDrift => self.provenance,
            DriftType::SpatialDrift => self.spatial,
            DriftType::QualityDrift => self.quality,
        }
    }
}

/// Metrics for a specific drift type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriftMetrics {
    /// Current drift score
    pub current_score: f64,
    /// Moving average
    pub moving_average: f64,
    /// Maximum observed score
    pub max_score: f64,
    /// Number of measurements
    pub measurement_count: u64,
    /// Last measurement time
    pub last_measured: DateTime<Utc>,
    /// Historical scores (last N measurements)
    pub history: Vec<(DateTime<Utc>, f64)>,
}

impl Default for DriftMetrics {
    fn default() -> Self {
        Self {
            current_score: 0.0,
            moving_average: 0.0,
            max_score: 0.0,
            measurement_count: 0,
            last_measured: Utc::now(),
            history: Vec::new(),
        }
    }
}

impl DriftMetrics {
    /// Record a new measurement
    pub fn record(&mut self, score: f64) {
        self.current_score = score;
        self.measurement_count += 1;
        self.last_measured = Utc::now();

        if score > self.max_score {
            self.max_score = score;
        }

        // Update moving average (exponential)
        let alpha = 0.1;
        self.moving_average = alpha * score + (1.0 - alpha) * self.moving_average;

        // Keep last 100 measurements
        self.history.push((Utc::now(), score));
        if self.history.len() > 100 {
            self.history.remove(0);
        }
    }

    /// Check if score exceeds threshold
    pub fn exceeds_threshold(&self, threshold: f64) -> bool {
        self.current_score > threshold
    }

    /// Get trend (positive = increasing drift)
    pub fn trend(&self) -> f64 {
        if self.history.len() < 2 {
            return 0.0;
        }

        let recent: Vec<_> = self.history.iter().rev().take(10).collect();
        let older: Vec<_> = self.history.iter().rev().skip(10).take(10).collect();

        if older.is_empty() {
            return 0.0;
        }

        let recent_avg: f64 = recent.iter().map(|(_, s)| s).sum::<f64>() / recent.len() as f64;
        let older_avg: f64 = older.iter().map(|(_, s)| s).sum::<f64>() / older.len() as f64;

        recent_avg - older_avg
    }
}

/// Drift detector - monitors and reports drift events
pub struct DriftDetector {
    thresholds: DriftThresholds,
    metrics: Arc<RwLock<HashMap<DriftType, DriftMetrics>>>,
    event_sender: Option<mpsc::Sender<DriftEvent>>,
    prometheus_registry: Option<Registry>,
    // Prometheus metrics
    drift_score_gauge: Option<HashMap<DriftType, Gauge>>,
    drift_event_counter: Option<HashMap<DriftType, Counter>>,
}

impl DriftDetector {
    /// Create a new drift detector
    pub fn new(thresholds: DriftThresholds) -> Self {
        let mut metrics = HashMap::new();
        for drift_type in [
            DriftType::SemanticVectorDrift,
            DriftType::GraphDocumentDrift,
            DriftType::TemporalConsistencyDrift,
            DriftType::TensorDrift,
            DriftType::SchemaDrift,
            DriftType::ProvenanceDrift,
            DriftType::SpatialDrift,
            DriftType::QualityDrift,
        ] {
            metrics.insert(drift_type, DriftMetrics::default());
        }

        Self {
            thresholds,
            metrics: Arc::new(RwLock::new(metrics)),
            event_sender: None,
            prometheus_registry: None,
            drift_score_gauge: None,
            drift_event_counter: None,
        }
    }

    /// Create with default thresholds
    pub fn with_defaults() -> Self {
        Self::new(DriftThresholds::default())
    }

    /// Set event channel for drift notifications
    pub fn with_event_channel(mut self, sender: mpsc::Sender<DriftEvent>) -> Self {
        self.event_sender = Some(sender);
        self
    }

    /// Register Prometheus metrics
    pub fn with_prometheus(mut self, registry: Registry) -> Result<Self, DriftError> {
        let mut gauges = HashMap::new();
        let mut counters = HashMap::new();

        for drift_type in [
            DriftType::SemanticVectorDrift,
            DriftType::GraphDocumentDrift,
            DriftType::TemporalConsistencyDrift,
            DriftType::TensorDrift,
            DriftType::SchemaDrift,
            DriftType::ProvenanceDrift,
            DriftType::SpatialDrift,
            DriftType::QualityDrift,
        ] {
            let gauge = Gauge::new(
                format!("verisim_drift_score_{}", drift_type),
                format!("Current drift score for {}", drift_type),
            )
            .map_err(|e| DriftError::InvalidThreshold(e.to_string()))?;
            registry
                .register(Box::new(gauge.clone()))
                .map_err(|e| DriftError::InvalidThreshold(e.to_string()))?;
            gauges.insert(drift_type, gauge);

            let counter = Counter::new(
                format!("verisim_drift_events_{}", drift_type),
                format!("Number of drift events for {}", drift_type),
            )
            .map_err(|e| DriftError::InvalidThreshold(e.to_string()))?;
            registry
                .register(Box::new(counter.clone()))
                .map_err(|e| DriftError::InvalidThreshold(e.to_string()))?;
            counters.insert(drift_type, counter);
        }

        self.prometheus_registry = Some(registry);
        self.drift_score_gauge = Some(gauges);
        self.drift_event_counter = Some(counters);
        Ok(self)
    }

    /// Record a drift measurement
    pub async fn record(&self, drift_type: DriftType, score: f64, entities: Vec<String>) -> Result<Option<DriftEvent>, DriftError> {
        // Update metrics
        {
            let mut metrics = self.metrics.write().map_err(|_| DriftError::LockPoisoned)?;
            if let Some(m) = metrics.get_mut(&drift_type) {
                m.record(score);
            }
        }

        // Update Prometheus gauge
        if let Some(ref gauges) = self.drift_score_gauge {
            if let Some(gauge) = gauges.get(&drift_type) {
                gauge.set(score);
            }
        }

        // Check threshold (adaptive or fixed)
        let moving_avg = {
            let metrics = self.metrics.read().map_err(|_| DriftError::LockPoisoned)?;
            metrics
                .get(&drift_type)
                .map(|m| m.moving_average)
                .unwrap_or(0.0)
        };
        let threshold = self.thresholds.effective_threshold(drift_type, moving_avg);

        if score > threshold {
            let event = DriftEvent::new(
                drift_type,
                score,
                format!(
                    "{} detected with score {:.3} (threshold: {:.3})",
                    drift_type, score, threshold
                ),
            )
            .with_entities(entities);

            // Update Prometheus counter
            if let Some(ref counters) = self.drift_event_counter {
                if let Some(counter) = counters.get(&drift_type) {
                    counter.inc();
                }
            }

            // Send event notification
            if let Some(ref sender) = self.event_sender {
                sender
                    .send(event.clone())
                    .await
                    .map_err(|e| DriftError::ChannelError(e.to_string()))?;
            }

            return Ok(Some(event));
        }

        Ok(None)
    }

    /// Get current metrics for a drift type
    pub fn get_metrics(&self, drift_type: DriftType) -> Result<Option<DriftMetrics>, DriftError> {
        let metrics = self.metrics.read().map_err(|_| DriftError::LockPoisoned)?;
        Ok(metrics.get(&drift_type).cloned())
    }

    /// Get all metrics
    pub fn all_metrics(&self) -> Result<HashMap<DriftType, DriftMetrics>, DriftError> {
        let metrics = self.metrics.read().map_err(|_| DriftError::LockPoisoned)?;
        Ok(metrics.clone())
    }

    /// Check overall health
    pub fn health_check(&self) -> Result<DriftHealthStatus, DriftError> {
        let metrics = self.metrics.read().map_err(|_| DriftError::LockPoisoned)?;
        let mut worst_score = 0.0;
        let mut worst_type = DriftType::QualityDrift;

        for (drift_type, m) in metrics.iter() {
            if m.current_score > worst_score {
                worst_score = m.current_score;
                worst_type = *drift_type;
            }
        }

        let status = if worst_score > 0.9 {
            HealthStatus::Critical
        } else if worst_score > 0.7 {
            HealthStatus::Degraded
        } else if worst_score > 0.5 {
            HealthStatus::Warning
        } else {
            HealthStatus::Healthy
        };

        Ok(DriftHealthStatus {
            status,
            worst_drift_type: worst_type,
            worst_score,
            checked_at: Utc::now(),
        })
    }
}

/// Overall health status
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum HealthStatus {
    Healthy,
    Warning,
    Degraded,
    Critical,
}

/// Drift health status report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriftHealthStatus {
    pub status: HealthStatus,
    pub worst_drift_type: DriftType,
    pub worst_score: f64,
    pub checked_at: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_drift_detection() {
        let detector = DriftDetector::with_defaults();

        // Record normal score
        let event = detector
            .record(DriftType::SemanticVectorDrift, 0.1, vec![])
            .await
            .unwrap();
        assert!(event.is_none());

        // Record high score (above threshold of 0.3 for semantic_vector)
        // Score 0.6 triggers Warning severity (> 0.5)
        let event = detector
            .record(DriftType::SemanticVectorDrift, 0.6, vec!["entity1".to_string()])
            .await
            .unwrap();
        assert!(event.is_some());
        assert_eq!(event.unwrap().severity, DriftSeverity::Warning);
    }

    #[test]
    fn test_drift_metrics() {
        let mut metrics = DriftMetrics::default();

        metrics.record(0.1);
        metrics.record(0.2);
        metrics.record(0.3);

        assert_eq!(metrics.current_score, 0.3);
        assert_eq!(metrics.max_score, 0.3);
        assert_eq!(metrics.measurement_count, 3);
    }

    #[test]
    fn test_health_check() {
        let detector = DriftDetector::with_defaults();
        let status = detector.health_check().unwrap();
        assert_eq!(status.status, HealthStatus::Healthy);
    }
}
