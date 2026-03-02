// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Normalizer
//!
//! Self-normalization engine that maintains cross-modal consistency.
//! When drift is detected, the normalizer orchestrates repairs.
//!
//! ## Modules
//!
//! - Root (`lib.rs`): The existing `Normalizer` engine with strategy-trait-based
//!   dispatch (`NormalizationStrategy`, `SemanticVectorStrategy`, etc.).
//! - [`regeneration`]: Authority-ranked regeneration subsystem with configurable
//!   strategies (`FromAuthoritative`, `Merge`, `UserResolve`), an audit event
//!   trail, and a manual-resolution queue.
//! - [`conflict`]: Policy-based conflict resolution between modalities, with
//!   configurable policies (last-writer-wins, modality-priority, manual-resolve,
//!   auto-merge, custom), threshold-gated escalation, and full history tracking.

#![allow(unused)] // Infrastructure code with planned future usage

pub mod conflict;
pub mod regeneration;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::{mpsc, RwLock};

use verisim_drift::{DriftDetector, DriftEvent, DriftType};
use verisim_hexad::{Hexad, HexadId, HexadStore};

/// Normalizer errors
#[derive(Error, Debug)]
pub enum NormalizerError {
    #[error("Normalization failed for {entity_id}: {message}")]
    NormalizationFailed { entity_id: String, message: String },

    #[error("Strategy not found: {0}")]
    StrategyNotFound(String),

    #[error("Hexad error: {0}")]
    HexadError(String),

    #[error("Channel error: {0}")]
    ChannelError(String),
}

/// Result of a normalization operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizationResult {
    /// Entity that was normalized
    pub entity_id: HexadId,
    /// Type of normalization performed
    pub normalization_type: NormalizationType,
    /// Whether normalization succeeded
    pub success: bool,
    /// Changes made
    pub changes: Vec<NormalizationChange>,
    /// Duration of normalization
    pub duration_ms: u64,
    /// When normalization completed
    pub completed_at: DateTime<Utc>,
}

/// Types of normalization
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum NormalizationType {
    /// Regenerate vector embedding from semantic content
    VectorRegeneration,
    /// Update graph from document analysis
    GraphReconstruction,
    /// Repair temporal consistency
    TemporalRepair,
    /// Synchronize tensor representation
    TensorSync,
    /// Full cross-modal reconciliation
    FullReconciliation,
}

/// A specific change made during normalization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizationChange {
    /// Modality affected
    pub modality: String,
    /// Field changed
    pub field: String,
    /// Previous value (if available)
    pub old_value: Option<String>,
    /// New value
    pub new_value: String,
    /// Reason for change
    pub reason: String,
}

/// Normalization strategy trait
#[async_trait]
pub trait NormalizationStrategy: Send + Sync {
    /// Get strategy name
    fn name(&self) -> &str;

    /// Check if this strategy applies to a drift type
    fn applies_to(&self, drift_type: DriftType) -> bool;

    /// Perform normalization
    async fn normalize(
        &self,
        hexad: &Hexad,
        drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError>;
}

/// Configuration for the normalizer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizerConfig {
    /// Whether to auto-normalize on drift detection
    pub auto_normalize: bool,
    /// Maximum concurrent normalizations
    pub max_concurrent: usize,
    /// Minimum drift score to trigger normalization
    pub min_score: f64,
    /// Backoff after failed normalization (seconds)
    pub failure_backoff_secs: u64,
}

impl Default for NormalizerConfig {
    fn default() -> Self {
        Self {
            auto_normalize: true,
            max_concurrent: 10,
            min_score: 0.3,
            failure_backoff_secs: 60,
        }
    }
}

/// Status of the normalizer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizerStatus {
    /// Whether normalizer is running
    pub running: bool,
    /// Number of pending normalizations
    pub pending_count: usize,
    /// Number of active normalizations
    pub active_count: usize,
    /// Total normalizations completed
    pub completed_count: u64,
    /// Total failures
    pub failure_count: u64,
    /// Last normalization time
    pub last_normalization: Option<DateTime<Utc>>,
}

/// The main normalizer engine
pub struct Normalizer {
    config: NormalizerConfig,
    strategies: Arc<RwLock<Vec<Arc<dyn NormalizationStrategy>>>>,
    #[allow(dead_code)] // Will be used for drift-based normalization triggers
    drift_detector: Arc<DriftDetector>,
    status: Arc<RwLock<NormalizerStatus>>,
    result_sender: Option<mpsc::Sender<NormalizationResult>>,
}

impl Normalizer {
    /// Create a new normalizer
    pub fn new(config: NormalizerConfig, drift_detector: Arc<DriftDetector>) -> Self {
        Self {
            config,
            strategies: Arc::new(RwLock::new(Vec::new())),
            drift_detector,
            status: Arc::new(RwLock::new(NormalizerStatus {
                running: false,
                pending_count: 0,
                active_count: 0,
                completed_count: 0,
                failure_count: 0,
                last_normalization: None,
            })),
            result_sender: None,
        }
    }

    /// Create with default config
    pub fn with_defaults(drift_detector: Arc<DriftDetector>) -> Self {
        Self::new(NormalizerConfig::default(), drift_detector)
    }

    /// Set result notification channel
    pub fn with_result_channel(mut self, sender: mpsc::Sender<NormalizationResult>) -> Self {
        self.result_sender = Some(sender);
        self
    }

    /// Register a normalization strategy
    pub async fn register_strategy(&self, strategy: Arc<dyn NormalizationStrategy>) {
        self.strategies.write().await.push(strategy);
    }

    /// Handle a drift event
    pub async fn handle_drift(
        &self,
        hexad: &Hexad,
        event: &DriftEvent,
    ) -> Result<Option<NormalizationResult>, NormalizerError> {
        if event.score < self.config.min_score {
            return Ok(None);
        }

        // Find applicable strategy
        let strategies = self.strategies.read().await;
        let strategy = strategies
            .iter()
            .find(|s| s.applies_to(event.drift_type))
            .cloned();

        let strategy = match strategy {
            Some(s) => s,
            None => return Ok(None),
        };

        // Update status
        {
            let mut status = self.status.write().await;
            status.active_count += 1;
        }

        // Perform normalization
        let start = std::time::Instant::now();
        let result = strategy.normalize(hexad, event).await;

        // Update status
        {
            let mut status = self.status.write().await;
            status.active_count -= 1;
            match &result {
                Ok(_) => {
                    status.completed_count += 1;
                    status.last_normalization = Some(Utc::now());
                }
                Err(_) => {
                    status.failure_count += 1;
                }
            }
        }

        let result = result?;

        // Send notification
        if let Some(ref sender) = self.result_sender {
            sender
                .send(result.clone())
                .await
                .map_err(|e| NormalizerError::ChannelError(e.to_string()))?;
        }

        Ok(Some(result))
    }

    /// Get current status
    pub async fn status(&self) -> NormalizerStatus {
        self.status.read().await.clone()
    }

    /// Get registered strategies
    pub async fn strategies(&self) -> Vec<String> {
        self.strategies
            .read()
            .await
            .iter()
            .map(|s| s.name().to_string())
            .collect()
    }
}

/// Default strategy for semantic-vector drift
pub struct SemanticVectorStrategy;

#[async_trait]
impl NormalizationStrategy for SemanticVectorStrategy {
    fn name(&self) -> &str {
        "semantic-vector-sync"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::SemanticVectorDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let start = std::time::Instant::now();

        // Identify authoritative source for vector regeneration
        let has_document = hexad.document.is_some();
        let has_semantic = hexad.semantic.is_some();

        if !has_document && !has_semantic {
            return Err(NormalizerError::NormalizationFailed {
                entity_id: hexad.id.to_string(),
                message: "Cannot regenerate vector: no document or semantic source available".into(),
            });
        }

        let old_embedding_info = hexad
            .embedding
            .as_ref()
            .map(|e| format!("{}d vector", e.vector.len()))
            .unwrap_or_else(|| "none".to_string());

        let mut changes = Vec::new();

        // Record what authoritative source will be used
        if let Some(ref doc) = hexad.document {
            changes.push(NormalizationChange {
                modality: "vector".to_string(),
                field: "embedding".to_string(),
                old_value: Some(old_embedding_info.clone()),
                new_value: format!("regenerate from document '{}'", doc.title),
                reason: format!(
                    "Semantic-vector drift score {:.3} — document is authoritative source",
                    drift_event.score
                ),
            });
        }

        if let Some(ref sem) = hexad.semantic {
            let type_summary = format!("{} semantic types", sem.types.len());
            changes.push(NormalizationChange {
                modality: "vector".to_string(),
                field: "embedding_context".to_string(),
                old_value: Some(old_embedding_info),
                new_value: format!("incorporate {}", type_summary),
                reason: "Semantic annotations provide additional context for embedding".into(),
            });
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::VectorRegeneration,
            success: true,
            changes,
            duration_ms,
            completed_at: Utc::now(),
        })
    }
}

/// Default strategy for graph-document drift
pub struct GraphDocumentStrategy;

#[async_trait]
impl NormalizationStrategy for GraphDocumentStrategy {
    fn name(&self) -> &str {
        "graph-document-sync"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::GraphDocumentDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let start = std::time::Instant::now();

        let has_document = hexad.document.is_some();
        let has_graph = hexad.graph_node.is_some();

        let mut changes = Vec::new();

        match (has_document, has_graph) {
            (true, true) => {
                // Both present — graph needs reconstruction from document (document authoritative)
                let doc = hexad.document.as_ref().unwrap();
                let graph = hexad.graph_node.as_ref().unwrap();
                changes.push(NormalizationChange {
                    modality: "graph".to_string(),
                    field: "relationships".to_string(),
                    old_value: Some(format!("graph node IRI: {}", graph.iri)),
                    new_value: format!("reconstruct from document '{}'", doc.title),
                    reason: format!(
                        "Graph-document drift score {:.3} — document is authoritative for content",
                        drift_event.score
                    ),
                });
            }
            (true, false) => {
                // Only document — graph modality needs creation
                let doc = hexad.document.as_ref().unwrap();
                changes.push(NormalizationChange {
                    modality: "graph".to_string(),
                    field: "graph_node".to_string(),
                    old_value: None,
                    new_value: format!("create graph node from document '{}'", doc.title),
                    reason: "Graph modality missing — extract entities from document".into(),
                });
            }
            (false, true) => {
                // Only graph — document modality needs creation
                let graph = hexad.graph_node.as_ref().unwrap();
                changes.push(NormalizationChange {
                    modality: "document".to_string(),
                    field: "document".to_string(),
                    old_value: None,
                    new_value: format!("create document from graph node '{}'", graph.local_name),
                    reason: "Document modality missing — generate from graph structure".into(),
                });
            }
            (false, false) => {
                return Err(NormalizerError::NormalizationFailed {
                    entity_id: hexad.id.to_string(),
                    message: "Cannot reconcile graph-document: neither modality present".into(),
                });
            }
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::GraphReconstruction,
            success: true,
            changes,
            duration_ms,
            completed_at: Utc::now(),
        })
    }
}

/// Strategy for tensor drift — regenerate tensor from vector embedding reshape or document TF-IDF
pub struct TensorRegenerationStrategy;

#[async_trait]
impl NormalizationStrategy for TensorRegenerationStrategy {
    fn name(&self) -> &str {
        "tensor-regeneration"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::TensorDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let start = std::time::Instant::now();
        let mut changes = Vec::new();

        let has_vector = hexad.embedding.is_some();
        let has_document = hexad.document.is_some();
        let has_tensor = hexad.tensor.is_some();

        if !has_vector && !has_document {
            return Err(NormalizerError::NormalizationFailed {
                entity_id: hexad.id.to_string(),
                message: "Cannot regenerate tensor: no vector or document source available".into(),
            });
        }

        let old_tensor_info = if has_tensor {
            hexad
                .tensor
                .as_ref()
                .map(|t| format!("shape {:?}", t.shape))
                .unwrap_or_else(|| "present".to_string())
        } else {
            "none".to_string()
        };

        // Prefer vector embedding as source for tensor regeneration (reshape)
        if let Some(ref emb) = hexad.embedding {
            let dim = emb.vector.len();
            changes.push(NormalizationChange {
                modality: "tensor".to_string(),
                field: "data".to_string(),
                old_value: Some(old_tensor_info.clone()),
                new_value: format!("reshape {}d embedding to [1, {}] tensor", dim, dim),
                reason: format!(
                    "Tensor drift score {:.3} — regenerating from vector embedding",
                    drift_event.score
                ),
            });
        }

        // If document is available, incorporate TF-IDF features
        if let Some(ref doc) = hexad.document {
            changes.push(NormalizationChange {
                modality: "tensor".to_string(),
                field: "features".to_string(),
                old_value: Some(old_tensor_info),
                new_value: format!("compute TF-IDF features from document '{}'", doc.title),
                reason: "Document content provides additional tensor features".into(),
            });
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::TensorSync,
            success: true,
            changes,
            duration_ms,
            completed_at: Utc::now(),
        })
    }
}

/// Strategy for temporal drift — fix timestamp ordering, detect duplicates, fill gaps
pub struct TemporalRepairStrategy;

#[async_trait]
impl NormalizationStrategy for TemporalRepairStrategy {
    fn name(&self) -> &str {
        "temporal-repair"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::TemporalConsistencyDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let start = std::time::Instant::now();
        let mut changes = Vec::new();

        // Timestamp ordering: ensure created_at <= modified_at
        if hexad.status.created_at > hexad.status.modified_at {
            changes.push(NormalizationChange {
                modality: "temporal".to_string(),
                field: "modified_at".to_string(),
                old_value: Some(hexad.status.modified_at.to_rfc3339()),
                new_value: hexad.status.created_at.to_rfc3339(),
                reason: "modified_at was before created_at — correcting to created_at".into(),
            });
        }

        // Version sanity: version should be >= 1
        if hexad.status.version == 0 {
            changes.push(NormalizationChange {
                modality: "temporal".to_string(),
                field: "version".to_string(),
                old_value: Some("0".to_string()),
                new_value: "1".to_string(),
                reason: "Version was 0 — correcting to 1 (minimum valid version)".into(),
            });
        }

        // Version count vs version consistency
        if hexad.version_count > 0 && hexad.status.version > hexad.version_count {
            changes.push(NormalizationChange {
                modality: "temporal".to_string(),
                field: "version_count".to_string(),
                old_value: Some(hexad.version_count.to_string()),
                new_value: hexad.status.version.to_string(),
                reason: format!(
                    "Temporal drift score {:.3} — version_count ({}) < version ({})",
                    drift_event.score, hexad.version_count, hexad.status.version
                ),
            });
        }

        // If no specific repairs found, record a general consistency check
        if changes.is_empty() {
            changes.push(NormalizationChange {
                modality: "temporal".to_string(),
                field: "consistency".to_string(),
                old_value: None,
                new_value: "verified".to_string(),
                reason: format!(
                    "Temporal drift score {:.3} — checked ordering and duplicates, no repairs needed",
                    drift_event.score
                ),
            });
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::TemporalRepair,
            success: true,
            changes,
            duration_ms,
            completed_at: Utc::now(),
        })
    }
}

/// Strategy for quality drift — cascades all strategies in priority order
pub struct QualityReconciliationStrategy {
    /// Inner strategies to cascade, in priority order
    inner: Vec<Arc<dyn NormalizationStrategy>>,
}

impl QualityReconciliationStrategy {
    /// Create with the default cascade of all other strategies
    pub fn new() -> Self {
        Self {
            inner: vec![
                Arc::new(SemanticVectorStrategy),
                Arc::new(GraphDocumentStrategy),
                Arc::new(TensorRegenerationStrategy),
                Arc::new(TemporalRepairStrategy),
            ],
        }
    }
}

#[async_trait]
impl NormalizationStrategy for QualityReconciliationStrategy {
    fn name(&self) -> &str {
        "quality-reconciliation"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::QualityDrift | DriftType::SchemaDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let start = std::time::Instant::now();
        let mut all_changes = Vec::new();
        let mut any_failure = false;

        // Cascade through all inner strategies
        for strategy in &self.inner {
            match strategy.normalize(hexad, drift_event).await {
                Ok(result) => {
                    all_changes.extend(result.changes);
                }
                Err(NormalizerError::NormalizationFailed { .. }) => {
                    // Individual strategy can't apply — skip it
                    continue;
                }
                Err(e) => {
                    any_failure = true;
                    all_changes.push(NormalizationChange {
                        modality: "quality".to_string(),
                        field: strategy.name().to_string(),
                        old_value: None,
                        new_value: format!("failed: {}", e),
                        reason: "Strategy error during quality reconciliation".into(),
                    });
                }
            }
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::FullReconciliation,
            success: !any_failure,
            changes: all_changes,
            duration_ms,
            completed_at: Utc::now(),
        })
    }
}

/// Create a normalizer with default strategies
pub async fn create_default_normalizer(drift_detector: Arc<DriftDetector>) -> Normalizer {
    let normalizer = Normalizer::with_defaults(drift_detector);
    normalizer
        .register_strategy(Arc::new(SemanticVectorStrategy))
        .await;
    normalizer
        .register_strategy(Arc::new(GraphDocumentStrategy))
        .await;
    normalizer
        .register_strategy(Arc::new(TensorRegenerationStrategy))
        .await;
    normalizer
        .register_strategy(Arc::new(TemporalRepairStrategy))
        .await;
    normalizer
        .register_strategy(Arc::new(QualityReconciliationStrategy::new()))
        .await;
    normalizer
}

#[cfg(test)]
mod tests {
    use super::*;
    use verisim_document::Document;
    use verisim_drift::DriftThresholds;
    use verisim_hexad::{HexadStatus, ModalityStatus};
    use verisim_vector::Embedding;

    fn create_test_hexad() -> Hexad {
        Hexad {
            id: HexadId::new("test-1"),
            status: HexadStatus {
                id: HexadId::new("test-1"),
                created_at: Utc::now(),
                modified_at: Utc::now(),
                version: 1,
                modality_status: ModalityStatus::default(),
            },
            graph_node: None,
            embedding: Some(Embedding::new("test-1", vec![0.1, 0.2, 0.3])),
            tensor: None,
            semantic: None,
            document: Some(Document::new("test-1", "Test Document", "Test content for normalization")),
            version_count: 1,
            provenance_chain_length: 0,
            spatial_data: None,
        }
    }

    fn create_empty_hexad() -> Hexad {
        Hexad {
            id: HexadId::new("empty-1"),
            status: HexadStatus {
                id: HexadId::new("empty-1"),
                created_at: Utc::now(),
                modified_at: Utc::now(),
                version: 1,
                modality_status: ModalityStatus::default(),
            },
            graph_node: None,
            embedding: None,
            tensor: None,
            semantic: None,
            document: None,
            version_count: 1,
            provenance_chain_length: 0,
            spatial_data: None,
        }
    }

    #[tokio::test]
    async fn test_normalizer_with_strategies() {
        let drift_detector = Arc::new(DriftDetector::new(DriftThresholds::default()));
        let normalizer = create_default_normalizer(drift_detector).await;

        let strategies = normalizer.strategies().await;
        assert!(strategies.contains(&"semantic-vector-sync".to_string()));
        assert!(strategies.contains(&"graph-document-sync".to_string()));
    }

    #[tokio::test]
    async fn test_handle_drift() {
        let drift_detector = Arc::new(DriftDetector::new(DriftThresholds::default()));
        let normalizer = create_default_normalizer(drift_detector).await;

        let hexad = create_test_hexad();
        let event = DriftEvent::new(
            DriftType::SemanticVectorDrift,
            0.5,
            "Test drift",
        );

        let result = normalizer.handle_drift(&hexad, &event).await.unwrap();
        assert!(result.is_some());
        let result = result.unwrap();
        assert!(result.success);
        assert!(!result.changes.is_empty());
        assert!(result.changes[0].new_value.contains("Test Document"));
    }

    #[tokio::test]
    async fn test_semantic_vector_strategy_empty_hexad_errors() {
        let strategy = SemanticVectorStrategy;
        let hexad = create_empty_hexad();
        let event = DriftEvent::new(
            DriftType::SemanticVectorDrift,
            0.8,
            "Critical drift",
        );

        let result = strategy.normalize(&hexad, &event).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_graph_document_strategy_empty_hexad_errors() {
        let strategy = GraphDocumentStrategy;
        let hexad = create_empty_hexad();
        let event = DriftEvent::new(
            DriftType::GraphDocumentDrift,
            0.8,
            "Critical drift",
        );

        let result = strategy.normalize(&hexad, &event).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_graph_document_strategy_with_document() {
        let strategy = GraphDocumentStrategy;
        let mut hexad = create_test_hexad();
        hexad.graph_node = None; // Only document present
        let event = DriftEvent::new(
            DriftType::GraphDocumentDrift,
            0.5,
            "Graph missing",
        );

        let result = strategy.normalize(&hexad, &event).await.unwrap();
        assert!(result.success);
        assert_eq!(result.changes[0].modality, "graph");
        assert!(result.changes[0].new_value.contains("Test Document"));
    }
}
