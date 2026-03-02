// SPDX-License-Identifier: PMPL-1.0-or-later
//! Regeneration Strategies for the VeriSim Normalizer
//!
//! Implements authority-ranked cross-modal regeneration. When drift is detected
//! between modalities, this module decides *how* to repair the drifted modality
//! by consulting a configurable authority ranking and per-modality strategy
//! overrides.
//!
//! ## Authority Ranking (default, highest to lowest)
//!
//! 1. **Document** -- human-written content, most authoritative
//! 2. **Semantic** -- type annotations and proof contracts
//! 3. **Graph** -- structural relationships
//! 4. **Vector** -- computed embeddings
//! 5. **Tensor** -- derived computations
//! 6. **Temporal** -- version history (always consistent by construction)
//!
//! ## Strategies
//!
//! - `FromAuthoritative`: regenerate drifted modality from the highest-authority
//!   consistent modality.
//! - `Merge`: combine data from all non-drifted modalities (weighted by authority)
//!   to produce the best result.
//! - `UserResolve`: flag the entity for manual resolution and add it to the
//!   normalization queue.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

use verisim_hexad::Hexad;

use crate::NormalizerError;

// ---------------------------------------------------------------------------
// Modality enum (normalizer-local; avoids coupling to verisim-planner)
// ---------------------------------------------------------------------------

/// The eight modalities of VeriSimDB (octad), ordered by default authority
/// ranking.
///
/// The normalizer defines its own copy so it does not depend on the planner
/// crate. Conversion helpers exist for interop where necessary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Modality {
    Document,
    Semantic,
    Graph,
    Vector,
    Tensor,
    Temporal,
    Provenance,
    Spatial,
}

impl Modality {
    /// Default authority order (highest to lowest):
    ///
    /// Document > Semantic > Provenance > Graph > Vector > Tensor > Spatial > Temporal
    ///
    /// Provenance is ranked high because lineage data is critical for audit
    /// and compliance.  Spatial is ranked low because coordinates are often
    /// derived from other modalities.
    pub const DEFAULT_AUTHORITY_ORDER: [Modality; 8] = [
        Modality::Document,
        Modality::Semantic,
        Modality::Provenance,
        Modality::Graph,
        Modality::Vector,
        Modality::Tensor,
        Modality::Spatial,
        Modality::Temporal,
    ];

    /// All eight modalities (unordered — use `DEFAULT_AUTHORITY_ORDER` when
    /// ordering matters).
    pub const ALL: [Modality; 8] = Self::DEFAULT_AUTHORITY_ORDER;

    /// Check whether this modality is populated on a given hexad.
    pub fn is_present_on(self, hexad: &Hexad) -> bool {
        match self {
            Modality::Document => hexad.document.is_some(),
            Modality::Semantic => hexad.semantic.is_some(),
            Modality::Graph => hexad.graph_node.is_some(),
            Modality::Vector => hexad.embedding.is_some(),
            Modality::Tensor => hexad.tensor.is_some(),
            Modality::Temporal => hexad.version_count > 0,
            Modality::Provenance => hexad.provenance_chain_length > 0,
            Modality::Spatial => hexad.spatial_data.is_some(),
        }
    }

    /// Extract a textual summary of this modality's data from a hexad.
    ///
    /// Returns `None` if the modality is not populated.
    pub fn summarize(self, hexad: &Hexad) -> Option<String> {
        match self {
            Modality::Document => hexad.document.as_ref().map(|d| {
                format!(
                    "document(title='{}', body_len={})",
                    d.title,
                    d.body.len()
                )
            }),
            Modality::Semantic => hexad.semantic.as_ref().map(|s| {
                format!(
                    "semantic(types={}, properties={})",
                    s.types.len(),
                    s.properties.len()
                )
            }),
            Modality::Graph => hexad.graph_node.as_ref().map(|g| {
                format!("graph(iri='{}', local_name='{}')", g.iri, g.local_name)
            }),
            Modality::Vector => hexad.embedding.as_ref().map(|e| {
                format!("vector(dim={})", e.vector.len())
            }),
            Modality::Tensor => hexad.tensor.as_ref().map(|t| {
                format!("tensor(shape={:?}, len={})", t.shape, t.data.len())
            }),
            Modality::Temporal => {
                if hexad.version_count > 0 {
                    Some(format!("temporal(versions={})", hexad.version_count))
                } else {
                    None
                }
            }
            Modality::Provenance => {
                if hexad.provenance_chain_length > 0 {
                    Some(format!("provenance(chain_length={})", hexad.provenance_chain_length))
                } else {
                    None
                }
            }
            Modality::Spatial => hexad.spatial_data.as_ref().map(|s| {
                format!(
                    "spatial(lat={}, lon={}, type={})",
                    s.coordinates.latitude,
                    s.coordinates.longitude,
                    s.geometry_type
                )
            }),
        }
    }
}

impl fmt::Display for Modality {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Modality::Document => write!(f, "document"),
            Modality::Semantic => write!(f, "semantic"),
            Modality::Graph => write!(f, "graph"),
            Modality::Vector => write!(f, "vector"),
            Modality::Tensor => write!(f, "tensor"),
            Modality::Temporal => write!(f, "temporal"),
            Modality::Provenance => write!(f, "provenance"),
            Modality::Spatial => write!(f, "spatial"),
        }
    }
}

// ---------------------------------------------------------------------------
// RegenerationStrategy
// ---------------------------------------------------------------------------

/// Strategy to apply when drift is detected on a modality.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RegenerationStrategy {
    /// Regenerate the drifted modality from the highest-authority modality
    /// that is currently consistent (not drifted).
    FromAuthoritative,

    /// Combine data from *all* non-drifted modalities, weighted by their
    /// authority rank, to produce the best possible repair.
    Merge,

    /// Do not auto-fix.  Flag the entity for manual resolution and place
    /// it on the `NormalizationQueue`.
    UserResolve,
}

impl fmt::Display for RegenerationStrategy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RegenerationStrategy::FromAuthoritative => write!(f, "from_authoritative"),
            RegenerationStrategy::Merge => write!(f, "merge"),
            RegenerationStrategy::UserResolve => write!(f, "user_resolve"),
        }
    }
}

// ---------------------------------------------------------------------------
// RegenerationConfig
// ---------------------------------------------------------------------------

/// Configuration for the regeneration subsystem.
///
/// This is separate from `NormalizerConfig` (which governs the top-level
/// normalizer engine) so that the two can evolve independently.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegenerationConfig {
    /// Global authority ranking (ordered highest to lowest).
    ///
    /// When `FromAuthoritative` is used, the first modality in this list that
    /// is present and not drifted becomes the regeneration source.
    pub authority_order: Vec<Modality>,

    /// Default strategy applied when drift is detected and no per-modality
    /// override is configured.
    pub default_strategy: RegenerationStrategy,

    /// Per-modality strategy overrides.
    ///
    /// If a modality appears in this map, its strategy takes precedence over
    /// `default_strategy`.
    pub modality_strategies: HashMap<Modality, RegenerationStrategy>,

    /// Drift score threshold (0.0 -- 1.0) above which regeneration is
    /// triggered.  Scores at or below this value are considered acceptable.
    pub drift_threshold: f64,

    /// Maximum number of regenerations that may execute concurrently.
    pub max_concurrent: usize,
}

impl Default for RegenerationConfig {
    fn default() -> Self {
        Self {
            authority_order: Modality::DEFAULT_AUTHORITY_ORDER.to_vec(),
            default_strategy: RegenerationStrategy::FromAuthoritative,
            modality_strategies: HashMap::new(),
            drift_threshold: 0.3,
            max_concurrent: 10,
        }
    }
}

impl RegenerationConfig {
    /// Look up the strategy for a specific modality.
    ///
    /// Returns the per-modality override if one exists, otherwise falls back
    /// to `default_strategy`.
    pub fn strategy_for(&self, modality: Modality) -> RegenerationStrategy {
        self.modality_strategies
            .get(&modality)
            .copied()
            .unwrap_or(self.default_strategy)
    }

    /// Return the authority weight for a given modality.
    ///
    /// Weight is `N - index` where N is the length of `authority_order`, so
    /// the first (most authoritative) modality has the highest weight.
    /// Returns 0 if the modality is not in the ranking.
    pub fn authority_weight(&self, modality: Modality) -> f64 {
        let n = self.authority_order.len() as f64;
        self.authority_order
            .iter()
            .position(|m| *m == modality)
            .map(|idx| n - idx as f64)
            .unwrap_or(0.0)
    }
}

// ---------------------------------------------------------------------------
// NormalizationEvent (audit trail)
// ---------------------------------------------------------------------------

/// Record of a single regeneration action, for audit and observability.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizationEvent {
    /// ID of the hexad entity that was (or would be) repaired.
    pub entity_id: String,

    /// The modality that drifted and required regeneration.
    pub drifted_modality: Modality,

    /// Which strategy was applied.
    pub strategy_used: RegenerationStrategy,

    /// If `FromAuthoritative` was used, which modality served as the source.
    pub source_modality: Option<Modality>,

    /// Drift score *before* regeneration was attempted.
    pub pre_drift_score: f64,

    /// Drift score *after* regeneration completed, if validation was run.
    pub post_drift_score: Option<f64>,

    /// When the event was recorded.
    pub timestamp: DateTime<Utc>,

    /// Whether the regeneration succeeded.
    pub success: bool,
}

// ---------------------------------------------------------------------------
// RegenerationResult
// ---------------------------------------------------------------------------

/// Outcome of a single regeneration attempt.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RegenerationResult {
    /// Drift was repaired successfully.
    Repaired {
        /// Full audit event.
        event: NormalizationEvent,
    },

    /// The entity was placed on the manual-resolution queue.
    PendingResolution {
        /// Entity that needs attention.
        entity_id: String,
        /// Human-readable explanation of why auto-repair was not attempted.
        reason: String,
    },

    /// Drift score was at or below the configured threshold -- no action taken.
    NoActionNeeded,

    /// Regeneration was attempted but failed.
    Failed {
        /// Description of what went wrong.
        error: String,
    },
}

// ---------------------------------------------------------------------------
// NormalizationQueue (for UserResolve strategy)
// ---------------------------------------------------------------------------

/// An item waiting for manual resolution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingNormalization {
    /// The entity that needs manual attention.
    pub entity_id: String,

    /// Which modality drifted.
    pub drifted_modality: Modality,

    /// The drift score that triggered the queue entry.
    pub drift_score: f64,

    /// When this item was added to the queue.
    pub queued_at: DateTime<Utc>,
}

/// Thread-safe queue of entities awaiting manual resolution.
///
/// Entries are added when the `UserResolve` strategy is selected for a
/// drifted modality. External tooling (dashboards, CLI, etc.) drains the
/// queue after a human reviews each case.
#[derive(Debug, Clone)]
pub struct NormalizationQueue {
    pending: Arc<RwLock<Vec<PendingNormalization>>>,
}

impl NormalizationQueue {
    /// Create an empty queue.
    pub fn new() -> Self {
        Self {
            pending: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Add an entity to the resolution queue.
    pub async fn enqueue(&self, item: PendingNormalization) {
        self.pending.write().await.push(item);
    }

    /// Return all pending items (snapshot).
    pub async fn pending(&self) -> Vec<PendingNormalization> {
        self.pending.read().await.clone()
    }

    /// Number of items waiting.
    pub async fn len(&self) -> usize {
        self.pending.read().await.len()
    }

    /// Whether the queue is empty.
    pub async fn is_empty(&self) -> bool {
        self.pending.read().await.is_empty()
    }

    /// Remove and return the item for a given entity + modality, if present.
    ///
    /// Used when a human resolves an item externally.
    pub async fn resolve(
        &self,
        entity_id: &str,
        modality: Modality,
    ) -> Option<PendingNormalization> {
        let mut pending = self.pending.write().await;
        let idx = pending.iter().position(|p| {
            p.entity_id == entity_id && p.drifted_modality == modality
        });
        idx.map(|i| pending.remove(i))
    }

    /// Drain all items from the queue and return them.
    pub async fn drain(&self) -> Vec<PendingNormalization> {
        let mut pending = self.pending.write().await;
        std::mem::take(&mut *pending)
    }
}

impl Default for NormalizationQueue {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// RegenerationEngine -- the core pipeline
// ---------------------------------------------------------------------------

/// The regeneration engine executes the full regeneration pipeline:
///
/// 1. Check whether drift score exceeds threshold.
/// 2. Identify which modality drifted.
/// 3. Select strategy (per-modality override or default).
/// 4. Execute strategy.
/// 5. Validate (re-check drift score after regeneration).
/// 6. Record the event.
///
/// Actual modality data extraction and re-computation are pluggable via the
/// `ModalityRegenerator` trait.  The engine owns the *decision logic* and
/// pipeline orchestration.
pub struct RegenerationEngine {
    /// Configuration controlling authority ranking, thresholds, and strategy
    /// selection.
    config: RegenerationConfig,

    /// Queue for items requiring manual resolution.
    queue: NormalizationQueue,

    /// Audit trail of all regeneration events (most recent last).
    events: Arc<RwLock<Vec<NormalizationEvent>>>,

    /// Pluggable regenerator for actually mutating modality data.
    regenerator: Arc<dyn ModalityRegenerator>,
}

/// Trait for pluggable modality-data regeneration.
///
/// Implementations translate the *decision* (which source modality to use,
/// which target to regenerate) into actual data mutations.  The engine calls
/// these methods; callers provide the implementation appropriate to their
/// storage backend.
#[async_trait::async_trait]
pub trait ModalityRegenerator: Send + Sync {
    /// Regenerate `target` modality data from `source` modality data.
    ///
    /// Returns a textual summary of what changed (for the audit log).
    async fn regenerate_from(
        &self,
        hexad: &Hexad,
        source: Modality,
        target: Modality,
    ) -> Result<String, NormalizerError>;

    /// Merge data from `sources` (with associated weights) into `target`.
    ///
    /// Returns a textual summary of what changed.
    async fn merge_into(
        &self,
        hexad: &Hexad,
        sources: &[(Modality, f64)],
        target: Modality,
    ) -> Result<String, NormalizerError>;

    /// Re-measure drift score for `modality` after a regeneration.
    ///
    /// Returns the new score (0.0 = perfect, 1.0 = maximum drift).
    async fn measure_drift(
        &self,
        hexad: &Hexad,
        modality: Modality,
    ) -> Result<f64, NormalizerError>;
}

// ---------------------------------------------------------------------------
// Default (summary-only) regenerator
// ---------------------------------------------------------------------------

/// A regenerator that does not mutate actual storage but produces descriptive
/// summaries of what *would* happen.
///
/// Useful for dry-run mode, testing, and as the default before real storage
/// backends are wired in.
pub struct SummaryRegenerator;

#[async_trait::async_trait]
impl ModalityRegenerator for SummaryRegenerator {
    async fn regenerate_from(
        &self,
        hexad: &Hexad,
        source: Modality,
        target: Modality,
    ) -> Result<String, NormalizerError> {
        let source_summary = source
            .summarize(hexad)
            .unwrap_or_else(|| format!("{} (empty)", source));
        Ok(format!(
            "Regenerated {} from {} [{}]",
            target, source, source_summary
        ))
    }

    async fn merge_into(
        &self,
        hexad: &Hexad,
        sources: &[(Modality, f64)],
        target: Modality,
    ) -> Result<String, NormalizerError> {
        let parts: Vec<String> = sources
            .iter()
            .map(|(m, w)| {
                let s = m
                    .summarize(hexad)
                    .unwrap_or_else(|| format!("{} (empty)", m));
                format!("{}(w={:.2}) [{}]", m, w, s)
            })
            .collect();
        Ok(format!(
            "Merged into {} from: {}",
            target,
            parts.join(", ")
        ))
    }

    async fn measure_drift(
        &self,
        _hexad: &Hexad,
        _modality: Modality,
    ) -> Result<f64, NormalizerError> {
        // After a summary-only "regeneration" the drift hasn't actually changed,
        // but we return 0.0 to signal a successful conceptual repair.
        Ok(0.0)
    }
}

// ---------------------------------------------------------------------------
// RegenerationEngine implementation
// ---------------------------------------------------------------------------

impl RegenerationEngine {
    /// Create an engine with the given config and a summary-only regenerator.
    pub fn new(config: RegenerationConfig) -> Self {
        Self {
            config,
            queue: NormalizationQueue::new(),
            events: Arc::new(RwLock::new(Vec::new())),
            regenerator: Arc::new(SummaryRegenerator),
        }
    }

    /// Create an engine with a custom `ModalityRegenerator`.
    pub fn with_regenerator(
        config: RegenerationConfig,
        regenerator: Arc<dyn ModalityRegenerator>,
    ) -> Self {
        Self {
            config,
            queue: NormalizationQueue::new(),
            events: Arc::new(RwLock::new(Vec::new())),
            regenerator,
        }
    }

    /// Create an engine with all defaults.
    pub fn with_defaults() -> Self {
        Self::new(RegenerationConfig::default())
    }

    /// Access the underlying configuration.
    pub fn config(&self) -> &RegenerationConfig {
        &self.config
    }

    /// Access the manual-resolution queue.
    pub fn queue(&self) -> &NormalizationQueue {
        &self.queue
    }

    /// Return a snapshot of all recorded events.
    pub async fn events(&self) -> Vec<NormalizationEvent> {
        self.events.read().await.clone()
    }

    // -- core pipeline -------------------------------------------------------

    /// Execute the full regeneration pipeline for a single drifted modality.
    ///
    /// # Arguments
    ///
    /// * `hexad` -- the entity whose modality drifted.
    /// * `drifted_modality` -- which modality has drifted.
    /// * `drift_score` -- the measured drift score (0.0 -- 1.0).
    ///
    /// # Returns
    ///
    /// A `RegenerationResult` describing what happened (repaired, queued for
    /// human review, no action, or failure).
    pub async fn regenerate(
        &self,
        hexad: &Hexad,
        drifted_modality: Modality,
        drift_score: f64,
    ) -> RegenerationResult {
        let entity_id = hexad.id.to_string();

        // Step 1: check threshold
        if drift_score <= self.config.drift_threshold {
            debug!(
                entity_id = %entity_id,
                modality = %drifted_modality,
                score = drift_score,
                threshold = self.config.drift_threshold,
                "Drift score below threshold -- no action"
            );
            return RegenerationResult::NoActionNeeded;
        }

        // Step 2-3: select strategy
        let strategy = self.config.strategy_for(drifted_modality);
        info!(
            entity_id = %entity_id,
            modality = %drifted_modality,
            score = drift_score,
            strategy = %strategy,
            "Starting regeneration"
        );

        // Step 4: execute strategy
        match strategy {
            RegenerationStrategy::FromAuthoritative => {
                self.execute_from_authoritative(hexad, drifted_modality, drift_score)
                    .await
            }
            RegenerationStrategy::Merge => {
                self.execute_merge(hexad, drifted_modality, drift_score)
                    .await
            }
            RegenerationStrategy::UserResolve => {
                self.execute_user_resolve(hexad, drifted_modality, drift_score)
                    .await
            }
        }
    }

    // -- FromAuthoritative ---------------------------------------------------

    /// Find the highest-authority modality that is present on the hexad and is
    /// *not* the drifted modality, then regenerate from it.
    async fn execute_from_authoritative(
        &self,
        hexad: &Hexad,
        drifted_modality: Modality,
        drift_score: f64,
    ) -> RegenerationResult {
        let entity_id = hexad.id.to_string();

        // Walk authority order to find the best source.
        let source = self
            .config
            .authority_order
            .iter()
            .copied()
            .find(|m| *m != drifted_modality && m.is_present_on(hexad));

        let source = match source {
            Some(s) => s,
            None => {
                let msg = format!(
                    "No authoritative source available for {} on entity {}",
                    drifted_modality, entity_id
                );
                warn!("{}", msg);

                // Record the failed attempt in the audit trail.
                let event = NormalizationEvent {
                    entity_id: entity_id.clone(),
                    drifted_modality,
                    strategy_used: RegenerationStrategy::FromAuthoritative,
                    source_modality: None,
                    pre_drift_score: drift_score,
                    post_drift_score: None,
                    timestamp: Utc::now(),
                    success: false,
                };
                self.record_event(event).await;

                return RegenerationResult::Failed { error: msg };
            }
        };

        info!(
            entity_id = %entity_id,
            source = %source,
            target = %drifted_modality,
            "FromAuthoritative: regenerating from source"
        );

        // Call the pluggable regenerator.
        let regen_result = self
            .regenerator
            .regenerate_from(hexad, source, drifted_modality)
            .await;

        match regen_result {
            Ok(summary) => {
                debug!(summary = %summary, "Regeneration produced summary");

                // Step 5: validate
                let post_score = self
                    .regenerator
                    .measure_drift(hexad, drifted_modality)
                    .await
                    .ok();

                // Step 6: record
                let event = NormalizationEvent {
                    entity_id: entity_id.clone(),
                    drifted_modality,
                    strategy_used: RegenerationStrategy::FromAuthoritative,
                    source_modality: Some(source),
                    pre_drift_score: drift_score,
                    post_drift_score: post_score,
                    timestamp: Utc::now(),
                    success: true,
                };
                self.record_event(event.clone()).await;

                RegenerationResult::Repaired { event }
            }
            Err(e) => {
                let event = NormalizationEvent {
                    entity_id: entity_id.clone(),
                    drifted_modality,
                    strategy_used: RegenerationStrategy::FromAuthoritative,
                    source_modality: Some(source),
                    pre_drift_score: drift_score,
                    post_drift_score: None,
                    timestamp: Utc::now(),
                    success: false,
                };
                self.record_event(event).await;

                RegenerationResult::Failed {
                    error: e.to_string(),
                }
            }
        }
    }

    // -- Merge ---------------------------------------------------------------

    /// Collect data from all non-drifted modalities, weight by authority, and
    /// merge into the drifted modality.
    async fn execute_merge(
        &self,
        hexad: &Hexad,
        drifted_modality: Modality,
        drift_score: f64,
    ) -> RegenerationResult {
        let entity_id = hexad.id.to_string();

        // Collect non-drifted, present modalities with their weights.
        let sources: Vec<(Modality, f64)> = self
            .config
            .authority_order
            .iter()
            .copied()
            .filter(|m| *m != drifted_modality && m.is_present_on(hexad))
            .map(|m| {
                let weight = self.config.authority_weight(m);
                (m, weight)
            })
            .collect();

        if sources.is_empty() {
            let msg = format!(
                "No source modalities available for merge into {} on entity {}",
                drifted_modality, entity_id
            );
            warn!("{}", msg);

            // Record the failed attempt in the audit trail.
            let event = NormalizationEvent {
                entity_id: entity_id.clone(),
                drifted_modality,
                strategy_used: RegenerationStrategy::Merge,
                source_modality: None,
                pre_drift_score: drift_score,
                post_drift_score: None,
                timestamp: Utc::now(),
                success: false,
            };
            self.record_event(event).await;

            return RegenerationResult::Failed { error: msg };
        }

        info!(
            entity_id = %entity_id,
            target = %drifted_modality,
            source_count = sources.len(),
            "Merge: combining sources"
        );

        let merge_result = self
            .regenerator
            .merge_into(hexad, &sources, drifted_modality)
            .await;

        match merge_result {
            Ok(summary) => {
                debug!(summary = %summary, "Merge produced summary");

                let post_score = self
                    .regenerator
                    .measure_drift(hexad, drifted_modality)
                    .await
                    .ok();

                let event = NormalizationEvent {
                    entity_id: entity_id.clone(),
                    drifted_modality,
                    strategy_used: RegenerationStrategy::Merge,
                    source_modality: None, // merge uses multiple sources
                    pre_drift_score: drift_score,
                    post_drift_score: post_score,
                    timestamp: Utc::now(),
                    success: true,
                };
                self.record_event(event.clone()).await;

                RegenerationResult::Repaired { event }
            }
            Err(e) => {
                let event = NormalizationEvent {
                    entity_id: entity_id.clone(),
                    drifted_modality,
                    strategy_used: RegenerationStrategy::Merge,
                    source_modality: None,
                    pre_drift_score: drift_score,
                    post_drift_score: None,
                    timestamp: Utc::now(),
                    success: false,
                };
                self.record_event(event).await;

                RegenerationResult::Failed {
                    error: e.to_string(),
                }
            }
        }
    }

    // -- UserResolve ---------------------------------------------------------

    /// Place the entity on the manual-resolution queue instead of auto-fixing.
    async fn execute_user_resolve(
        &self,
        hexad: &Hexad,
        drifted_modality: Modality,
        drift_score: f64,
    ) -> RegenerationResult {
        let entity_id = hexad.id.to_string();

        let pending = PendingNormalization {
            entity_id: entity_id.clone(),
            drifted_modality,
            drift_score,
            queued_at: Utc::now(),
        };

        self.queue.enqueue(pending).await;

        let event = NormalizationEvent {
            entity_id: entity_id.clone(),
            drifted_modality,
            strategy_used: RegenerationStrategy::UserResolve,
            source_modality: None,
            pre_drift_score: drift_score,
            post_drift_score: None,
            timestamp: Utc::now(),
            success: true, // queueing itself succeeded
        };
        self.record_event(event).await;

        info!(
            entity_id = %entity_id,
            modality = %drifted_modality,
            score = drift_score,
            "Entity queued for manual resolution"
        );

        RegenerationResult::PendingResolution {
            entity_id,
            reason: format!(
                "{} drift (score {:.3}) requires manual resolution per strategy config",
                drifted_modality, drift_score
            ),
        }
    }

    // -- helpers -------------------------------------------------------------

    /// Append an event to the audit trail.
    async fn record_event(&self, event: NormalizationEvent) {
        self.events.write().await.push(event);
    }
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use verisim_document::Document;
    use verisim_graph::GraphNode;
    use verisim_hexad::{HexadId, HexadStatus, ModalityStatus};
    use verisim_semantic::{Provenance, SemanticAnnotation};
    use verisim_vector::Embedding;

    // -- test helpers --------------------------------------------------------

    /// Build a hexad with document, semantic, graph, and vector populated.
    fn rich_hexad() -> Hexad {
        Hexad {
            id: HexadId::new("rich-1"),
            status: HexadStatus {
                id: HexadId::new("rich-1"),
                created_at: Utc::now(),
                modified_at: Utc::now(),
                version: 1,
                modality_status: ModalityStatus::default(),
            },
            graph_node: Some(GraphNode::new("https://verisim.db/entity/rich-1")),
            embedding: Some(Embedding::new("rich-1", vec![0.1, 0.2, 0.3])),
            tensor: None,
            semantic: Some(SemanticAnnotation {
                entity_id: "rich-1".into(),
                types: vec!["http://example.org/Document".into()],
                properties: HashMap::new(),
                provenance: Provenance::default(),
            }),
            document: Some(Document::new(
                "rich-1",
                "Rich Entity",
                "Full content for normalizer testing",
            )),
            version_count: 3,
            provenance_chain_length: 0,
            spatial_data: None,
        }
    }

    /// Build a hexad with only a document.
    fn doc_only_hexad() -> Hexad {
        Hexad {
            id: HexadId::new("doc-1"),
            status: HexadStatus {
                id: HexadId::new("doc-1"),
                created_at: Utc::now(),
                modified_at: Utc::now(),
                version: 1,
                modality_status: ModalityStatus::default(),
            },
            graph_node: None,
            embedding: None,
            tensor: None,
            semantic: None,
            document: Some(Document::new("doc-1", "Doc Only", "Minimal entity")),
            version_count: 0,
            provenance_chain_length: 0,
            spatial_data: None,
        }
    }

    /// Build a completely empty hexad.
    fn empty_hexad() -> Hexad {
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
            version_count: 0,
            provenance_chain_length: 0,
            spatial_data: None,
        }
    }

    // -- authority order tests -----------------------------------------------

    #[test]
    fn test_default_authority_order_matches_spec() {
        let order = Modality::DEFAULT_AUTHORITY_ORDER;
        assert_eq!(order[0], Modality::Document, "Document should be rank 1");
        assert_eq!(order[1], Modality::Semantic, "Semantic should be rank 2");
        assert_eq!(order[2], Modality::Provenance, "Provenance should be rank 3");
        assert_eq!(order[3], Modality::Graph, "Graph should be rank 4");
        assert_eq!(order[4], Modality::Vector, "Vector should be rank 5");
        assert_eq!(order[5], Modality::Tensor, "Tensor should be rank 6");
        assert_eq!(order[6], Modality::Spatial, "Spatial should be rank 7");
        assert_eq!(order[7], Modality::Temporal, "Temporal should be rank 8");
    }

    #[test]
    fn test_authority_weight_highest_first() {
        let config = RegenerationConfig::default();
        let doc_w = config.authority_weight(Modality::Document);
        let sem_w = config.authority_weight(Modality::Semantic);
        let graph_w = config.authority_weight(Modality::Graph);
        let vec_w = config.authority_weight(Modality::Vector);
        let tensor_w = config.authority_weight(Modality::Tensor);
        let temporal_w = config.authority_weight(Modality::Temporal);

        assert!(doc_w > sem_w, "Document weight > Semantic weight");
        assert!(sem_w > graph_w, "Semantic weight > Graph weight");
        assert!(graph_w > vec_w, "Graph weight > Vector weight");
        assert!(vec_w > tensor_w, "Vector weight > Tensor weight");
        assert!(tensor_w > temporal_w, "Tensor weight > Temporal weight");
        assert!(temporal_w > 0.0, "Temporal weight > 0");
    }

    // -- strategy selection tests --------------------------------------------

    #[test]
    fn test_strategy_for_default() {
        let config = RegenerationConfig::default();
        assert_eq!(
            config.strategy_for(Modality::Vector),
            RegenerationStrategy::FromAuthoritative,
            "Default strategy should be FromAuthoritative"
        );
    }

    #[test]
    fn test_strategy_for_per_modality_override() {
        let mut config = RegenerationConfig::default();
        config
            .modality_strategies
            .insert(Modality::Tensor, RegenerationStrategy::UserResolve);

        assert_eq!(
            config.strategy_for(Modality::Tensor),
            RegenerationStrategy::UserResolve,
            "Per-modality override should take precedence"
        );
        assert_eq!(
            config.strategy_for(Modality::Vector),
            RegenerationStrategy::FromAuthoritative,
            "Non-overridden modalities should still use default"
        );
    }

    // -- modality presence tests ---------------------------------------------

    #[test]
    fn test_modality_is_present_on_rich_hexad() {
        let h = rich_hexad();
        assert!(Modality::Document.is_present_on(&h));
        assert!(Modality::Semantic.is_present_on(&h));
        assert!(Modality::Graph.is_present_on(&h));
        assert!(Modality::Vector.is_present_on(&h));
        assert!(!Modality::Tensor.is_present_on(&h));
        assert!(Modality::Temporal.is_present_on(&h)); // version_count > 0
    }

    #[test]
    fn test_modality_is_present_on_empty_hexad() {
        let h = empty_hexad();
        for m in Modality::ALL {
            assert!(
                !m.is_present_on(&h),
                "{} should not be present on empty hexad",
                m
            );
        }
    }

    // -- FromAuthoritative tests ---------------------------------------------

    #[tokio::test]
    async fn test_from_authoritative_selects_correct_source() {
        let engine = RegenerationEngine::with_defaults();
        let h = rich_hexad();

        // Vector drifted -- Document is highest authority and is present.
        let result = engine
            .regenerate(&h, Modality::Vector, 0.8)
            .await;

        match result {
            RegenerationResult::Repaired { event } => {
                assert_eq!(event.drifted_modality, Modality::Vector);
                assert_eq!(
                    event.source_modality,
                    Some(Modality::Document),
                    "Should select Document as highest authority"
                );
                assert_eq!(event.strategy_used, RegenerationStrategy::FromAuthoritative);
                assert!(event.success);
                assert!(event.pre_drift_score > 0.0);
                assert!(event.post_drift_score.is_some());
            }
            other => panic!("Expected Repaired, got {:?}", other),
        }
    }

    #[tokio::test]
    async fn test_from_authoritative_skips_drifted_modality() {
        let engine = RegenerationEngine::with_defaults();
        let h = rich_hexad();

        // Document itself drifted -- next authority is Semantic.
        let result = engine
            .regenerate(&h, Modality::Document, 0.7)
            .await;

        match result {
            RegenerationResult::Repaired { event } => {
                assert_eq!(event.drifted_modality, Modality::Document);
                assert_eq!(
                    event.source_modality,
                    Some(Modality::Semantic),
                    "Should skip Document (drifted) and use Semantic"
                );
            }
            other => panic!("Expected Repaired, got {:?}", other),
        }
    }

    #[tokio::test]
    async fn test_from_authoritative_fails_no_source() {
        let engine = RegenerationEngine::with_defaults();
        let h = empty_hexad();

        let result = engine
            .regenerate(&h, Modality::Vector, 0.9)
            .await;

        match result {
            RegenerationResult::Failed { error } => {
                assert!(
                    error.contains("No authoritative source"),
                    "Error should mention missing sources: {}",
                    error
                );
            }
            other => panic!("Expected Failed, got {:?}", other),
        }
    }

    #[tokio::test]
    async fn test_from_authoritative_doc_only_regenerates_graph() {
        let engine = RegenerationEngine::with_defaults();
        let h = doc_only_hexad();

        // Graph drifted, only Document is available.
        let result = engine
            .regenerate(&h, Modality::Graph, 0.6)
            .await;

        match result {
            RegenerationResult::Repaired { event } => {
                assert_eq!(event.source_modality, Some(Modality::Document));
                assert_eq!(event.drifted_modality, Modality::Graph);
            }
            other => panic!("Expected Repaired, got {:?}", other),
        }
    }

    // -- Merge tests ---------------------------------------------------------

    #[tokio::test]
    async fn test_merge_combines_multiple_sources() {
        let mut config = RegenerationConfig::default();
        config.default_strategy = RegenerationStrategy::Merge;

        let engine = RegenerationEngine::new(config);
        let h = rich_hexad();

        let result = engine
            .regenerate(&h, Modality::Tensor, 0.5)
            .await;

        match result {
            RegenerationResult::Repaired { event } => {
                assert_eq!(event.strategy_used, RegenerationStrategy::Merge);
                assert_eq!(event.drifted_modality, Modality::Tensor);
                // source_modality is None for merge (uses multiple)
                assert!(event.source_modality.is_none());
                assert!(event.success);
            }
            other => panic!("Expected Repaired, got {:?}", other),
        }
    }

    #[tokio::test]
    async fn test_merge_fails_no_sources() {
        let mut config = RegenerationConfig::default();
        config.default_strategy = RegenerationStrategy::Merge;

        let engine = RegenerationEngine::new(config);
        let h = empty_hexad();

        let result = engine
            .regenerate(&h, Modality::Vector, 0.9)
            .await;

        match result {
            RegenerationResult::Failed { error } => {
                assert!(error.contains("No source modalities"));
            }
            other => panic!("Expected Failed, got {:?}", other),
        }
    }

    // -- UserResolve tests ---------------------------------------------------

    #[tokio::test]
    async fn test_user_resolve_adds_to_queue() {
        let mut config = RegenerationConfig::default();
        config
            .modality_strategies
            .insert(Modality::Tensor, RegenerationStrategy::UserResolve);

        let engine = RegenerationEngine::new(config);
        let h = rich_hexad();

        assert!(engine.queue().is_empty().await);

        let result = engine
            .regenerate(&h, Modality::Tensor, 0.7)
            .await;

        match result {
            RegenerationResult::PendingResolution { entity_id, reason } => {
                assert_eq!(entity_id, "rich-1");
                assert!(reason.contains("manual resolution"));
            }
            other => panic!("Expected PendingResolution, got {:?}", other),
        }

        assert_eq!(engine.queue().len().await, 1);
        let pending = engine.queue().pending().await;
        assert_eq!(pending[0].entity_id, "rich-1");
        assert_eq!(pending[0].drifted_modality, Modality::Tensor);
        assert!((pending[0].drift_score - 0.7).abs() < f64::EPSILON);
    }

    #[tokio::test]
    async fn test_user_resolve_queue_drain() {
        let mut config = RegenerationConfig::default();
        config.default_strategy = RegenerationStrategy::UserResolve;

        let engine = RegenerationEngine::new(config);
        let h = rich_hexad();

        engine.regenerate(&h, Modality::Vector, 0.5).await;
        engine.regenerate(&h, Modality::Graph, 0.6).await;

        assert_eq!(engine.queue().len().await, 2);

        let drained = engine.queue().drain().await;
        assert_eq!(drained.len(), 2);
        assert!(engine.queue().is_empty().await);
    }

    #[tokio::test]
    async fn test_user_resolve_queue_selective_resolve() {
        let mut config = RegenerationConfig::default();
        config.default_strategy = RegenerationStrategy::UserResolve;

        let engine = RegenerationEngine::new(config);
        let h = rich_hexad();

        engine.regenerate(&h, Modality::Vector, 0.5).await;
        engine.regenerate(&h, Modality::Graph, 0.6).await;

        // Resolve only the graph item.
        let resolved = engine
            .queue()
            .resolve("rich-1", Modality::Graph)
            .await;
        assert!(resolved.is_some());
        assert_eq!(resolved.unwrap().drifted_modality, Modality::Graph);

        // Only vector should remain.
        assert_eq!(engine.queue().len().await, 1);
        let remaining = engine.queue().pending().await;
        assert_eq!(remaining[0].drifted_modality, Modality::Vector);
    }

    // -- threshold tests -----------------------------------------------------

    #[tokio::test]
    async fn test_drift_below_threshold_no_action() {
        let config = RegenerationConfig {
            drift_threshold: 0.5,
            ..Default::default()
        };
        let engine = RegenerationEngine::new(config);
        let h = rich_hexad();

        let result = engine
            .regenerate(&h, Modality::Vector, 0.3)
            .await;
        assert!(
            matches!(result, RegenerationResult::NoActionNeeded),
            "Score 0.3 should be below threshold 0.5"
        );
    }

    #[tokio::test]
    async fn test_drift_at_threshold_no_action() {
        let config = RegenerationConfig {
            drift_threshold: 0.5,
            ..Default::default()
        };
        let engine = RegenerationEngine::new(config);
        let h = rich_hexad();

        let result = engine
            .regenerate(&h, Modality::Vector, 0.5)
            .await;
        assert!(
            matches!(result, RegenerationResult::NoActionNeeded),
            "Score exactly at threshold should be no-action (requires > threshold)"
        );
    }

    #[tokio::test]
    async fn test_drift_above_threshold_triggers_action() {
        let config = RegenerationConfig {
            drift_threshold: 0.5,
            ..Default::default()
        };
        let engine = RegenerationEngine::new(config);
        let h = rich_hexad();

        let result = engine
            .regenerate(&h, Modality::Vector, 0.51)
            .await;
        assert!(
            matches!(result, RegenerationResult::Repaired { .. }),
            "Score 0.51 should trigger action with threshold 0.5"
        );
    }

    // -- event recording tests -----------------------------------------------

    #[tokio::test]
    async fn test_normalization_event_records_correctly() {
        let engine = RegenerationEngine::with_defaults();
        let h = rich_hexad();

        assert!(engine.events().await.is_empty());

        engine
            .regenerate(&h, Modality::Vector, 0.8)
            .await;

        let events = engine.events().await;
        assert_eq!(events.len(), 1);

        let event = &events[0];
        assert_eq!(event.entity_id, "rich-1");
        assert_eq!(event.drifted_modality, Modality::Vector);
        assert_eq!(event.strategy_used, RegenerationStrategy::FromAuthoritative);
        assert_eq!(event.source_modality, Some(Modality::Document));
        assert!((event.pre_drift_score - 0.8).abs() < f64::EPSILON);
        assert!(event.post_drift_score.is_some());
        assert!(event.success);
    }

    #[tokio::test]
    async fn test_failed_regeneration_records_event() {
        let engine = RegenerationEngine::with_defaults();
        let h = empty_hexad();

        engine
            .regenerate(&h, Modality::Vector, 0.9)
            .await;

        let events = engine.events().await;
        assert_eq!(events.len(), 1);
        assert!(!events[0].success);
    }

    #[tokio::test]
    async fn test_multiple_regenerations_accumulate_events() {
        let engine = RegenerationEngine::with_defaults();
        let h = rich_hexad();

        engine.regenerate(&h, Modality::Vector, 0.5).await;
        engine.regenerate(&h, Modality::Graph, 0.6).await;
        engine.regenerate(&h, Modality::Semantic, 0.7).await;

        let events = engine.events().await;
        assert_eq!(events.len(), 3);
        assert_eq!(events[0].drifted_modality, Modality::Vector);
        assert_eq!(events[1].drifted_modality, Modality::Graph);
        assert_eq!(events[2].drifted_modality, Modality::Semantic);
    }

    // -- custom authority order tests ----------------------------------------

    #[tokio::test]
    async fn test_custom_authority_order() {
        // Reverse authority: Temporal is highest.
        let config = RegenerationConfig {
            authority_order: vec![
                Modality::Temporal,
                Modality::Tensor,
                Modality::Vector,
                Modality::Graph,
                Modality::Semantic,
                Modality::Document,
            ],
            ..Default::default()
        };

        let engine = RegenerationEngine::new(config);
        let h = rich_hexad(); // has temporal (version_count=3)

        let result = engine
            .regenerate(&h, Modality::Document, 0.8)
            .await;

        match result {
            RegenerationResult::Repaired { event } => {
                assert_eq!(
                    event.source_modality,
                    Some(Modality::Temporal),
                    "Custom order should make Temporal the highest authority"
                );
            }
            other => panic!("Expected Repaired, got {:?}", other),
        }
    }

    // -- modality summarize tests --------------------------------------------

    #[test]
    fn test_modality_summarize() {
        let h = rich_hexad();
        let doc_summary = Modality::Document.summarize(&h);
        assert!(doc_summary.is_some());
        assert!(doc_summary.unwrap().contains("Rich Entity"));

        let tensor_summary = Modality::Tensor.summarize(&h);
        assert!(tensor_summary.is_none(), "Tensor not populated");
    }

    // -- Display impls -------------------------------------------------------

    #[test]
    fn test_modality_display() {
        assert_eq!(format!("{}", Modality::Document), "document");
        assert_eq!(format!("{}", Modality::Semantic), "semantic");
        assert_eq!(format!("{}", Modality::Graph), "graph");
        assert_eq!(format!("{}", Modality::Vector), "vector");
        assert_eq!(format!("{}", Modality::Tensor), "tensor");
        assert_eq!(format!("{}", Modality::Temporal), "temporal");
    }

    #[test]
    fn test_strategy_display() {
        assert_eq!(
            format!("{}", RegenerationStrategy::FromAuthoritative),
            "from_authoritative"
        );
        assert_eq!(format!("{}", RegenerationStrategy::Merge), "merge");
        assert_eq!(
            format!("{}", RegenerationStrategy::UserResolve),
            "user_resolve"
        );
    }

    // -- RegenerationConfig edge cases ---------------------------------------

    #[test]
    fn test_authority_weight_for_unlisted_modality() {
        // Config with only 3 modalities in authority order.
        let config = RegenerationConfig {
            authority_order: vec![Modality::Document, Modality::Semantic, Modality::Graph],
            ..Default::default()
        };

        assert_eq!(
            config.authority_weight(Modality::Vector),
            0.0,
            "Unlisted modality should have weight 0"
        );
        assert!(config.authority_weight(Modality::Document) > 0.0);
    }

    #[test]
    fn test_default_config_values() {
        let config = RegenerationConfig::default();
        assert_eq!(config.drift_threshold, 0.3);
        assert_eq!(config.max_concurrent, 10);
        assert_eq!(config.default_strategy, RegenerationStrategy::FromAuthoritative);
        assert!(config.modality_strategies.is_empty());
        assert_eq!(config.authority_order.len(), 8);
    }
}
