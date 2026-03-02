// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

//! Conflict Resolution Policies for the VeriSim Normalizer
//!
//! When two or more modalities report conflicting information about the same
//! entity, a **conflict** arises. This module provides:
//!
//! - Detection and recording of conflicts ([`ConflictResolver::detect_conflict`]).
//! - Policy-based resolution ([`ConflictPolicy`]) with five built-in strategies:
//!   last-writer-wins, modality-priority, manual-resolve, auto-merge, and custom.
//! - Threshold-gated auto-resolution: conflicts below
//!   [`ConflictConfig::auto_resolve_threshold`] are resolved automatically, while
//!   those above [`ConflictConfig::require_manual_above`] are always escalated.
//! - Per-modality-pair policy overrides for fine-grained control.
//! - Full history tracking of resolved and dismissed conflicts.
//!
//! ## Integration
//!
//! The [`ConflictResolver`] sits alongside the [`RegenerationEngine`] in the
//! normalizer pipeline. After drift detection identifies *that* modalities have
//! diverged, the conflict resolver decides *who wins* when both sides carry
//! valid but contradictory data.
//!
//! [`RegenerationEngine`]: crate::regeneration::RegenerationEngine

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::regeneration::Modality;

// ---------------------------------------------------------------------------
// ConflictPolicy
// ---------------------------------------------------------------------------

/// Policy that governs how a conflict between modalities is resolved.
///
/// Each variant represents a distinct resolution strategy. The policy can be
/// set globally via [`ConflictConfig::default_policy`], overridden for specific
/// modality pairs via [`ConflictConfig::per_modality_policies`], or supplied
/// ad-hoc when calling [`ConflictResolver::resolve`].
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ConflictPolicy {
    /// Last writer wins -- the most recently updated modality takes precedence.
    ///
    /// This is the simplest policy and is appropriate when all modalities are
    /// considered equally trustworthy. The modality whose data was written last
    /// (by wall-clock time) is chosen as the winner.
    LastWriterWins,

    /// Modality priority -- a modality higher in the supplied authority order
    /// wins over one lower in the order.
    ///
    /// The contained `Vec<Modality>` defines the priority ranking from highest
    /// (index 0) to lowest. If a conflicting modality is not in the list, it
    /// is treated as lowest priority.
    ModalityPriority(Vec<Modality>),

    /// Manual resolution -- the conflict is flagged for human review.
    ///
    /// No automatic winner is selected. The conflict status moves to
    /// [`ConflictStatus::InProgress`] and remains there until a human calls
    /// [`ConflictResolver::resolve_manual`].
    ManualResolve,

    /// Auto-merge -- attempt to automatically merge conflicting data.
    ///
    /// The resolver picks the modality with the richest data (most fields
    /// populated, longest content, etc.) as the primary source, and annotates
    /// the resolution accordingly. This is a heuristic, not a guarantee.
    AutoMerge,

    /// Custom -- delegate resolution to a user-provided external resolver.
    ///
    /// The contained `String` identifies the external resolver (e.g. a webhook
    /// URL or plugin name). The conflict is marked [`ConflictStatus::InProgress`]
    /// until the external system calls back with a decision.
    Custom(String),
}

impl fmt::Display for ConflictPolicy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConflictPolicy::LastWriterWins => write!(f, "last_writer_wins"),
            ConflictPolicy::ModalityPriority(_) => write!(f, "modality_priority"),
            ConflictPolicy::ManualResolve => write!(f, "manual_resolve"),
            ConflictPolicy::AutoMerge => write!(f, "auto_merge"),
            ConflictPolicy::Custom(name) => write!(f, "custom({})", name),
        }
    }
}

// ---------------------------------------------------------------------------
// ConflictStatus
// ---------------------------------------------------------------------------

/// Lifecycle state of a conflict.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConflictStatus {
    /// Conflict has been detected but not yet addressed.
    Open,

    /// Resolution is in progress (manual review or custom resolver).
    InProgress,

    /// Conflict has been resolved (see [`ConflictResolution`] for details).
    Resolved,

    /// Conflict was dismissed without resolution (e.g. deemed a false positive).
    Dismissed,
}

impl fmt::Display for ConflictStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConflictStatus::Open => write!(f, "open"),
            ConflictStatus::InProgress => write!(f, "in_progress"),
            ConflictStatus::Resolved => write!(f, "resolved"),
            ConflictStatus::Dismissed => write!(f, "dismissed"),
        }
    }
}

// ---------------------------------------------------------------------------
// Conflict
// ---------------------------------------------------------------------------

/// A detected conflict between two or more modalities on a single entity.
///
/// Conflicts are created by [`ConflictResolver::detect_conflict`] and tracked
/// through the [`ConflictStatus`] lifecycle until resolution or dismissal.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conflict {
    /// Unique identifier for this conflict instance.
    pub id: String,

    /// The hexad entity on which the conflict was detected.
    pub entity_id: String,

    /// When the conflict was first detected.
    pub detected_at: DateTime<Utc>,

    /// The modalities whose data disagrees.
    pub conflicting_modalities: Vec<Modality>,

    /// Measured drift score between the conflicting modalities (0.0 -- 1.0).
    pub drift_score: f64,

    /// Human-readable description of what the conflict is about.
    pub description: String,

    /// Current lifecycle status.
    pub status: ConflictStatus,

    /// How the conflict was resolved, if applicable.
    pub resolution: Option<ConflictResolution>,
}

// ---------------------------------------------------------------------------
// ConflictResolution
// ---------------------------------------------------------------------------

/// Record of how a conflict was resolved.
///
/// Attached to a [`Conflict`] once it reaches [`ConflictStatus::Resolved`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConflictResolution {
    /// When the resolution was applied.
    pub resolved_at: DateTime<Utc>,

    /// Which policy was used to determine the winner.
    pub policy_used: ConflictPolicy,

    /// The modality that was chosen as the authoritative source, if applicable.
    ///
    /// Some policies (e.g. [`ConflictPolicy::AutoMerge`]) may not select a
    /// single winner, in which case this is `None`.
    pub winning_modality: Option<Modality>,

    /// Who or what performed the resolution.
    ///
    /// `"system"` for automatic resolution, or a user/service identifier for
    /// manual/custom resolution.
    pub resolver: String,

    /// Optional notes from the resolver explaining the decision.
    pub notes: Option<String>,
}

// ---------------------------------------------------------------------------
// ConflictConfig
// ---------------------------------------------------------------------------

/// Configuration for the conflict resolution subsystem.
///
/// Controls which policy is used by default, per-modality-pair overrides,
/// and threshold gates for automatic vs. manual escalation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConflictConfig {
    /// The default policy applied when no per-pair override matches.
    pub default_policy: ConflictPolicy,

    /// Policy overrides keyed by ordered modality pair.
    ///
    /// If a conflict involves modalities `(A, B)` and there is an entry for
    /// `(A, B)` **or** `(B, A)`, that policy takes precedence over
    /// `default_policy`.
    pub per_modality_policies: HashMap<(Modality, Modality), ConflictPolicy>,

    /// Drift score at or below which conflicts are auto-resolved using the
    /// applicable policy, without human intervention.
    ///
    /// Range: 0.0 -- 1.0. Conflicts with `drift_score <= auto_resolve_threshold`
    /// are resolved immediately.
    pub auto_resolve_threshold: f64,

    /// Drift score at or above which conflicts **always** require manual review,
    /// regardless of the configured policy.
    ///
    /// Range: 0.0 -- 1.0. Must be >= `auto_resolve_threshold`.
    pub require_manual_above: f64,

    /// Maximum number of resolved/dismissed conflicts to retain in history.
    ///
    /// Older entries are evicted when this limit is exceeded (FIFO).
    pub max_history_entries: usize,
}

impl Default for ConflictConfig {
    fn default() -> Self {
        Self {
            default_policy: ConflictPolicy::LastWriterWins,
            per_modality_policies: HashMap::new(),
            auto_resolve_threshold: 0.3,
            require_manual_above: 0.8,
            max_history_entries: 1000,
        }
    }
}

impl ConflictConfig {
    /// Look up the policy for a specific pair of conflicting modalities.
    ///
    /// Checks both `(a, b)` and `(b, a)` orderings before falling back to
    /// `default_policy`.
    pub fn policy_for_pair(&self, a: Modality, b: Modality) -> &ConflictPolicy {
        self.per_modality_policies
            .get(&(a, b))
            .or_else(|| self.per_modality_policies.get(&(b, a)))
            .unwrap_or(&self.default_policy)
    }
}

// ---------------------------------------------------------------------------
// ConflictError
// ---------------------------------------------------------------------------

/// Errors returned by the conflict resolution engine.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ConflictError {
    /// No conflict with the given ID was found.
    #[error("Conflict not found: {0}")]
    NotFound(String),

    /// The conflict has already been resolved or dismissed.
    #[error("Conflict already resolved: {0}")]
    AlreadyResolved(String),

    /// The supplied policy is invalid for the given conflict.
    #[error("Invalid policy: {0}")]
    InvalidPolicy(String),

    /// The specified modality is not one of the conflicting modalities.
    #[error("Modality not in conflict: {0}")]
    ModalityNotInConflict(String),
}

// ---------------------------------------------------------------------------
// ConflictResolver
// ---------------------------------------------------------------------------

/// The conflict resolution engine.
///
/// Manages the lifecycle of conflicts from detection through resolution or
/// dismissal, applying configured policies to determine winners.
///
/// Thread-safe: all mutable state is behind [`RwLock`] guards.
pub struct ConflictResolver {
    /// Configuration controlling policies, thresholds, and history limits.
    config: ConflictConfig,

    /// Active (Open or InProgress) conflicts.
    active_conflicts: RwLock<Vec<Conflict>>,

    /// History of resolved and dismissed conflicts (bounded by
    /// `config.max_history_entries`).
    history: RwLock<Vec<Conflict>>,
}

impl ConflictResolver {
    /// Create a new conflict resolver with the given configuration.
    pub fn new(config: ConflictConfig) -> Self {
        Self {
            config,
            active_conflicts: RwLock::new(Vec::new()),
            history: RwLock::new(Vec::new()),
        }
    }

    /// Create a resolver with default configuration.
    pub fn with_defaults() -> Self {
        Self::new(ConflictConfig::default())
    }

    /// Access the underlying configuration.
    pub fn config(&self) -> &ConflictConfig {
        &self.config
    }

    // -- detection -----------------------------------------------------------

    /// Detect and record a new conflict.
    ///
    /// Creates a [`Conflict`] with status [`ConflictStatus::Open`], assigns it
    /// a unique ID, and stores it in the active conflicts list.
    ///
    /// # Arguments
    ///
    /// * `entity_id` -- the hexad entity on which the conflict was detected.
    /// * `modalities` -- the modalities whose data disagrees.
    /// * `drift_score` -- measured drift score (0.0 -- 1.0).
    /// * `description` -- human-readable description of the conflict.
    ///
    /// # Returns
    ///
    /// The newly created [`Conflict`].
    pub async fn detect_conflict(
        &self,
        entity_id: &str,
        modalities: Vec<Modality>,
        drift_score: f64,
        description: &str,
    ) -> Conflict {
        let conflict = Conflict {
            id: Uuid::new_v4().to_string(),
            entity_id: entity_id.to_string(),
            detected_at: Utc::now(),
            conflicting_modalities: modalities.clone(),
            drift_score,
            description: description.to_string(),
            status: ConflictStatus::Open,
            resolution: None,
        };

        info!(
            conflict_id = %conflict.id,
            entity_id = %entity_id,
            drift_score = drift_score,
            modalities = ?modalities,
            "Conflict detected"
        );

        self.active_conflicts.write().await.push(conflict.clone());
        conflict
    }

    // -- resolution ----------------------------------------------------------

    /// Resolve a conflict using the specified policy, or the applicable default.
    ///
    /// If `policy` is `None`, the resolver determines the appropriate policy
    /// based on the conflict's drift score and the configured thresholds and
    /// per-pair overrides.
    ///
    /// # Policy selection logic
    ///
    /// 1. If `drift_score >= require_manual_above`, force [`ConflictPolicy::ManualResolve`].
    /// 2. If an explicit `policy` argument is provided, use it.
    /// 3. If a per-modality-pair override exists, use it.
    /// 4. Otherwise, use `default_policy`.
    ///
    /// # Errors
    ///
    /// - [`ConflictError::NotFound`] if no active conflict with the given ID exists.
    /// - [`ConflictError::AlreadyResolved`] if the conflict is already Resolved or Dismissed.
    /// - [`ConflictError::InvalidPolicy`] if the selected policy cannot be applied
    ///   (e.g. [`ConflictPolicy::ManualResolve`] or [`ConflictPolicy::Custom`] cannot
    ///   produce an automatic resolution).
    pub async fn resolve(
        &self,
        conflict_id: &str,
        policy: Option<ConflictPolicy>,
    ) -> Result<ConflictResolution, ConflictError> {
        let mut active = self.active_conflicts.write().await;
        let conflict = active
            .iter_mut()
            .find(|c| c.id == conflict_id)
            .ok_or_else(|| ConflictError::NotFound(conflict_id.to_string()))?;

        // Guard: already resolved or dismissed
        if conflict.status == ConflictStatus::Resolved
            || conflict.status == ConflictStatus::Dismissed
        {
            return Err(ConflictError::AlreadyResolved(conflict_id.to_string()));
        }

        // Step 1: Force manual if drift is very high
        if conflict.drift_score >= self.config.require_manual_above {
            conflict.status = ConflictStatus::InProgress;
            debug!(
                conflict_id = %conflict_id,
                drift_score = conflict.drift_score,
                threshold = self.config.require_manual_above,
                "Drift score above manual threshold -- forcing manual resolution"
            );
            return Err(ConflictError::InvalidPolicy(format!(
                "Drift score {:.3} >= manual threshold {:.3} -- use resolve_manual()",
                conflict.drift_score, self.config.require_manual_above
            )));
        }

        // Step 2-4: Select policy
        let effective_policy = if let Some(ref p) = policy {
            p.clone()
        } else {
            self.select_policy(conflict)
        };

        // ManualResolve and Custom cannot produce automatic resolutions
        match &effective_policy {
            ConflictPolicy::ManualResolve => {
                conflict.status = ConflictStatus::InProgress;
                return Err(ConflictError::InvalidPolicy(
                    "ManualResolve policy requires resolve_manual()".to_string(),
                ));
            }
            ConflictPolicy::Custom(name) => {
                conflict.status = ConflictStatus::InProgress;
                return Err(ConflictError::InvalidPolicy(format!(
                    "Custom policy '{}' requires external resolver callback",
                    name
                )));
            }
            _ => {}
        }

        // Apply the policy
        let resolution = self.apply_policy(conflict, &effective_policy);

        info!(
            conflict_id = %conflict_id,
            policy = %effective_policy,
            winning_modality = ?resolution.winning_modality,
            "Conflict resolved automatically"
        );

        // Update state
        conflict.status = ConflictStatus::Resolved;
        conflict.resolution = Some(resolution.clone());

        // Move to history
        let resolved = conflict.clone();
        drop(active);
        self.move_to_history(resolved).await;

        Ok(resolution)
    }

    /// Manually resolve a conflict by specifying the winning modality.
    ///
    /// This is the only way to resolve conflicts that have been escalated to
    /// [`ConflictPolicy::ManualResolve`] or that exceeded the
    /// `require_manual_above` threshold.
    ///
    /// # Arguments
    ///
    /// * `conflict_id` -- ID of the conflict to resolve.
    /// * `winning_modality` -- the modality chosen as the authoritative source.
    /// * `resolver` -- identifier of the human or service performing the resolution.
    /// * `notes` -- optional free-text explanation.
    ///
    /// # Errors
    ///
    /// - [`ConflictError::NotFound`] if no active conflict with the given ID exists.
    /// - [`ConflictError::AlreadyResolved`] if the conflict is already Resolved or Dismissed.
    /// - [`ConflictError::ModalityNotInConflict`] if `winning_modality` is not
    ///   one of the conflicting modalities.
    pub async fn resolve_manual(
        &self,
        conflict_id: &str,
        winning_modality: Modality,
        resolver: &str,
        notes: Option<String>,
    ) -> Result<ConflictResolution, ConflictError> {
        let mut active = self.active_conflicts.write().await;
        let conflict = active
            .iter_mut()
            .find(|c| c.id == conflict_id)
            .ok_or_else(|| ConflictError::NotFound(conflict_id.to_string()))?;

        // Guard: already resolved or dismissed
        if conflict.status == ConflictStatus::Resolved
            || conflict.status == ConflictStatus::Dismissed
        {
            return Err(ConflictError::AlreadyResolved(conflict_id.to_string()));
        }

        // Guard: winning modality must be part of the conflict
        if !conflict.conflicting_modalities.contains(&winning_modality) {
            return Err(ConflictError::ModalityNotInConflict(format!(
                "{} is not in conflicting modalities {:?}",
                winning_modality, conflict.conflicting_modalities
            )));
        }

        let resolution = ConflictResolution {
            resolved_at: Utc::now(),
            policy_used: ConflictPolicy::ManualResolve,
            winning_modality: Some(winning_modality),
            resolver: resolver.to_string(),
            notes,
        };

        info!(
            conflict_id = %conflict_id,
            winning_modality = %winning_modality,
            resolver = %resolver,
            "Conflict resolved manually"
        );

        conflict.status = ConflictStatus::Resolved;
        conflict.resolution = Some(resolution.clone());

        // Move to history
        let resolved = conflict.clone();
        drop(active);
        self.move_to_history(resolved).await;

        Ok(resolution)
    }

    /// Dismiss a conflict without resolving it.
    ///
    /// Dismissed conflicts are moved to history with a note explaining why they
    /// were dismissed. This is appropriate for false positives or conflicts that
    /// have been superseded by other changes.
    ///
    /// # Errors
    ///
    /// - [`ConflictError::NotFound`] if no active conflict with the given ID exists.
    /// - [`ConflictError::AlreadyResolved`] if the conflict is already Resolved or Dismissed.
    pub async fn dismiss(
        &self,
        conflict_id: &str,
        reason: &str,
    ) -> Result<(), ConflictError> {
        let mut active = self.active_conflicts.write().await;
        let conflict = active
            .iter_mut()
            .find(|c| c.id == conflict_id)
            .ok_or_else(|| ConflictError::NotFound(conflict_id.to_string()))?;

        // Guard: already resolved or dismissed
        if conflict.status == ConflictStatus::Resolved
            || conflict.status == ConflictStatus::Dismissed
        {
            return Err(ConflictError::AlreadyResolved(conflict_id.to_string()));
        }

        info!(
            conflict_id = %conflict_id,
            reason = %reason,
            "Conflict dismissed"
        );

        conflict.status = ConflictStatus::Dismissed;
        conflict.resolution = Some(ConflictResolution {
            resolved_at: Utc::now(),
            policy_used: ConflictPolicy::LastWriterWins, // placeholder -- no actual policy used
            winning_modality: None,
            resolver: "system".to_string(),
            notes: Some(format!("Dismissed: {}", reason)),
        });

        // Move to history
        let dismissed = conflict.clone();
        drop(active);
        self.move_to_history(dismissed).await;

        Ok(())
    }

    // -- queries -------------------------------------------------------------

    /// Return all active (Open or InProgress) conflicts.
    pub async fn active_conflicts(&self) -> Vec<Conflict> {
        self.active_conflicts.read().await.clone()
    }

    /// Return resolved/dismissed conflict history, most recent first.
    ///
    /// # Arguments
    ///
    /// * `limit` -- maximum number of entries to return. If `0`, returns all.
    pub async fn history(&self, limit: usize) -> Vec<Conflict> {
        let history = self.history.read().await;
        if limit == 0 || limit >= history.len() {
            // Return in reverse chronological order (most recent first)
            let mut result = history.clone();
            result.reverse();
            result
        } else {
            // Take the last `limit` entries (most recent) and reverse
            let start = history.len() - limit;
            let mut result = history[start..].to_vec();
            result.reverse();
            result
        }
    }

    /// Return all conflicts (active and historical) for a given entity.
    ///
    /// Results are ordered with active conflicts first, then historical in
    /// reverse chronological order.
    pub async fn by_entity(&self, entity_id: &str) -> Vec<Conflict> {
        let active = self.active_conflicts.read().await;
        let history = self.history.read().await;

        let mut result: Vec<Conflict> = active
            .iter()
            .filter(|c| c.entity_id == entity_id)
            .cloned()
            .collect();

        let mut hist: Vec<Conflict> = history
            .iter()
            .filter(|c| c.entity_id == entity_id)
            .cloned()
            .collect();
        hist.reverse();

        result.extend(hist);
        result
    }

    // -- internal helpers ----------------------------------------------------

    /// Select the most appropriate policy for a conflict based on config.
    ///
    /// Checks per-modality-pair overrides first, then falls back to the default
    /// policy.
    fn select_policy(&self, conflict: &Conflict) -> ConflictPolicy {
        // Check per-pair overrides for the first matching pair
        let modalities = &conflict.conflicting_modalities;
        for i in 0..modalities.len() {
            for j in (i + 1)..modalities.len() {
                let pair_policy = self
                    .config
                    .per_modality_policies
                    .get(&(modalities[i], modalities[j]))
                    .or_else(|| {
                        self.config
                            .per_modality_policies
                            .get(&(modalities[j], modalities[i]))
                    });
                if let Some(policy) = pair_policy {
                    debug!(
                        pair = ?(&modalities[i], &modalities[j]),
                        policy = %policy,
                        "Using per-modality-pair policy override"
                    );
                    return policy.clone();
                }
            }
        }

        self.config.default_policy.clone()
    }

    /// Apply a policy to a conflict and produce a resolution.
    ///
    /// This method determines the winning modality based on the policy logic.
    /// It is called internally by [`resolve`](Self::resolve) after policy
    /// selection and threshold checks.
    fn apply_policy(&self, conflict: &Conflict, policy: &ConflictPolicy) -> ConflictResolution {
        let winning_modality = match policy {
            ConflictPolicy::LastWriterWins => {
                // The last modality in the list is considered the most recently
                // updated (caller orders them by write timestamp).
                conflict.conflicting_modalities.last().copied()
            }
            ConflictPolicy::ModalityPriority(priority_order) => {
                // Find the conflicting modality with the highest priority
                // (lowest index in the priority order).
                let mut best: Option<(usize, Modality)> = None;
                for m in &conflict.conflicting_modalities {
                    if let Some(idx) = priority_order.iter().position(|p| p == m) {
                        match best {
                            None => best = Some((idx, *m)),
                            Some((best_idx, _)) if idx < best_idx => {
                                best = Some((idx, *m));
                            }
                            _ => {}
                        }
                    }
                }
                // If none of the conflicting modalities appear in the priority
                // list, fall back to the first conflicting modality.
                best.map(|(_, m)| m)
                    .or_else(|| conflict.conflicting_modalities.first().copied())
            }
            ConflictPolicy::AutoMerge => {
                // For auto-merge, we don't pick a single winner -- the merge
                // process combines data from all conflicting modalities.
                // We return None to indicate no single winner.
                None
            }
            ConflictPolicy::ManualResolve | ConflictPolicy::Custom(_) => {
                // These policies should not reach apply_policy -- they are
                // intercepted earlier. Defensive coding: return None.
                warn!(
                    policy = %policy,
                    "apply_policy called with non-automatic policy -- returning no winner"
                );
                None
            }
        };

        ConflictResolution {
            resolved_at: Utc::now(),
            policy_used: policy.clone(),
            winning_modality,
            resolver: "system".to_string(),
            notes: None,
        }
    }

    /// Move a resolved or dismissed conflict from active list to history.
    ///
    /// Removes the conflict from `active_conflicts` by ID and appends it to
    /// `history`, evicting the oldest entry if `max_history_entries` is exceeded.
    async fn move_to_history(&self, conflict: Conflict) {
        // Remove from active
        {
            let mut active = self.active_conflicts.write().await;
            active.retain(|c| c.id != conflict.id);
        }

        // Add to history
        {
            let mut history = self.history.write().await;
            history.push(conflict);

            // Evict oldest entries if history is too large
            let max = self.config.max_history_entries;
            if history.len() > max {
                let excess = history.len() - max;
                history.drain(0..excess);
            }
        }
    }
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // -- helpers -------------------------------------------------------------

    /// Create a default config for testing.
    fn test_config() -> ConflictConfig {
        ConflictConfig {
            default_policy: ConflictPolicy::LastWriterWins,
            per_modality_policies: HashMap::new(),
            auto_resolve_threshold: 0.3,
            require_manual_above: 0.8,
            max_history_entries: 100,
        }
    }

    // -- ConflictConfig default tests ----------------------------------------

    #[test]
    fn test_conflict_config_defaults() {
        let config = ConflictConfig::default();
        assert_eq!(config.default_policy, ConflictPolicy::LastWriterWins);
        assert!(config.per_modality_policies.is_empty());
        assert!((config.auto_resolve_threshold - 0.3).abs() < f64::EPSILON);
        assert!((config.require_manual_above - 0.8).abs() < f64::EPSILON);
        assert_eq!(config.max_history_entries, 1000);
    }

    // -- LastWriterWins tests ------------------------------------------------

    #[tokio::test]
    async fn test_last_writer_wins_resolution() {
        let resolver = ConflictResolver::new(test_config());

        let conflict = resolver
            .detect_conflict(
                "entity-1",
                vec![Modality::Document, Modality::Vector],
                0.5,
                "Document and vector disagree on content",
            )
            .await;

        let resolution = resolver.resolve(&conflict.id, None).await.unwrap();

        // LastWriterWins picks the last modality in the list
        assert_eq!(resolution.winning_modality, Some(Modality::Vector));
        assert_eq!(resolution.policy_used, ConflictPolicy::LastWriterWins);
        assert_eq!(resolution.resolver, "system");
    }

    // -- ModalityPriority tests ----------------------------------------------

    #[tokio::test]
    async fn test_modality_priority_resolution() {
        let config = ConflictConfig {
            default_policy: ConflictPolicy::ModalityPriority(vec![
                Modality::Semantic,
                Modality::Document,
                Modality::Graph,
                Modality::Vector,
                Modality::Tensor,
                Modality::Temporal,
            ]),
            ..test_config()
        };

        let resolver = ConflictResolver::new(config);

        let conflict = resolver
            .detect_conflict(
                "entity-2",
                vec![Modality::Vector, Modality::Document],
                0.5,
                "Vector and document disagree",
            )
            .await;

        let resolution = resolver.resolve(&conflict.id, None).await.unwrap();

        // Document has higher priority than Vector in the custom order
        assert_eq!(resolution.winning_modality, Some(Modality::Document));
        assert!(matches!(
            resolution.policy_used,
            ConflictPolicy::ModalityPriority(_)
        ));
    }

    #[tokio::test]
    async fn test_modality_priority_with_custom_order() {
        // Reversed priority: Tensor > Vector > Graph > Semantic > Document
        let priority_order = vec![
            Modality::Tensor,
            Modality::Vector,
            Modality::Graph,
            Modality::Semantic,
            Modality::Document,
        ];

        let resolver = ConflictResolver::new(test_config());

        let conflict = resolver
            .detect_conflict(
                "entity-3",
                vec![Modality::Document, Modality::Vector],
                0.4,
                "Document and vector disagree",
            )
            .await;

        let resolution = resolver
            .resolve(
                &conflict.id,
                Some(ConflictPolicy::ModalityPriority(priority_order)),
            )
            .await
            .unwrap();

        // Vector is higher priority than Document in the reversed order
        assert_eq!(resolution.winning_modality, Some(Modality::Vector));
    }

    // -- ManualResolve tests -------------------------------------------------

    #[tokio::test]
    async fn test_manual_resolve_creates_in_progress() {
        let config = ConflictConfig {
            default_policy: ConflictPolicy::ManualResolve,
            ..test_config()
        };

        let resolver = ConflictResolver::new(config);

        let conflict = resolver
            .detect_conflict(
                "entity-4",
                vec![Modality::Graph, Modality::Semantic],
                0.5,
                "Graph and semantic disagree",
            )
            .await;

        // Automatic resolve should fail with InvalidPolicy
        let err = resolver.resolve(&conflict.id, None).await.unwrap_err();
        assert!(matches!(err, ConflictError::InvalidPolicy(_)));

        // Conflict should now be InProgress
        let active = resolver.active_conflicts().await;
        let found = active.iter().find(|c| c.id == conflict.id).unwrap();
        assert_eq!(found.status, ConflictStatus::InProgress);
    }

    #[tokio::test]
    async fn test_manual_resolve_succeeds() {
        let config = ConflictConfig {
            default_policy: ConflictPolicy::ManualResolve,
            ..test_config()
        };

        let resolver = ConflictResolver::new(config);

        let conflict = resolver
            .detect_conflict(
                "entity-5",
                vec![Modality::Graph, Modality::Semantic],
                0.5,
                "Graph and semantic disagree",
            )
            .await;

        // First try automatic (fails)
        let _ = resolver.resolve(&conflict.id, None).await;

        // Then resolve manually
        let resolution = resolver
            .resolve_manual(
                &conflict.id,
                Modality::Semantic,
                "admin-user-42",
                Some("Semantic annotations are more recent".to_string()),
            )
            .await
            .unwrap();

        assert_eq!(resolution.winning_modality, Some(Modality::Semantic));
        assert_eq!(resolution.resolver, "admin-user-42");
        assert!(resolution.notes.as_ref().unwrap().contains("more recent"));
        assert_eq!(resolution.policy_used, ConflictPolicy::ManualResolve);
    }

    // -- Auto-resolve below threshold ----------------------------------------

    #[tokio::test]
    async fn test_auto_resolve_below_threshold() {
        let config = ConflictConfig {
            auto_resolve_threshold: 0.5,
            ..test_config()
        };

        let resolver = ConflictResolver::new(config);

        // Drift score 0.3, which is below auto_resolve_threshold 0.5
        let conflict = resolver
            .detect_conflict(
                "entity-6",
                vec![Modality::Document, Modality::Tensor],
                0.3,
                "Minor drift between document and tensor",
            )
            .await;

        // Should resolve automatically
        let resolution = resolver.resolve(&conflict.id, None).await.unwrap();
        assert_eq!(resolution.resolver, "system");

        // Should be in history now, not active
        let active = resolver.active_conflicts().await;
        assert!(active.iter().all(|c| c.id != conflict.id));

        let history = resolver.history(10).await;
        assert!(history.iter().any(|c| c.id == conflict.id));
    }

    // -- Force manual above threshold ----------------------------------------

    #[tokio::test]
    async fn test_force_manual_above_threshold() {
        let config = ConflictConfig {
            require_manual_above: 0.8,
            ..test_config()
        };

        let resolver = ConflictResolver::new(config);

        let conflict = resolver
            .detect_conflict(
                "entity-7",
                vec![Modality::Document, Modality::Graph],
                0.9,
                "Severe drift requiring manual intervention",
            )
            .await;

        // Auto-resolve should fail because drift_score >= require_manual_above
        let err = resolver.resolve(&conflict.id, None).await.unwrap_err();
        assert!(matches!(err, ConflictError::InvalidPolicy(_)));
        assert!(err.to_string().contains("manual threshold"));

        // Conflict should be InProgress now
        let active = resolver.active_conflicts().await;
        let found = active.iter().find(|c| c.id == conflict.id).unwrap();
        assert_eq!(found.status, ConflictStatus::InProgress);
    }

    // -- Dismiss conflict ----------------------------------------------------

    #[tokio::test]
    async fn test_dismiss_conflict() {
        let resolver = ConflictResolver::new(test_config());

        let conflict = resolver
            .detect_conflict(
                "entity-8",
                vec![Modality::Vector, Modality::Tensor],
                0.4,
                "False positive drift",
            )
            .await;

        resolver
            .dismiss(&conflict.id, "False positive -- data was updated concurrently")
            .await
            .unwrap();

        // Should not be active
        let active = resolver.active_conflicts().await;
        assert!(active.iter().all(|c| c.id != conflict.id));

        // Should be in history with Dismissed status
        let history = resolver.history(10).await;
        let found = history.iter().find(|c| c.id == conflict.id).unwrap();
        assert_eq!(found.status, ConflictStatus::Dismissed);
        assert!(found
            .resolution
            .as_ref()
            .unwrap()
            .notes
            .as_ref()
            .unwrap()
            .contains("False positive"));
    }

    // -- History tracking ----------------------------------------------------

    #[tokio::test]
    async fn test_history_tracking() {
        let resolver = ConflictResolver::new(test_config());

        // Create and resolve three conflicts
        for i in 0..3 {
            let conflict = resolver
                .detect_conflict(
                    &format!("entity-hist-{}", i),
                    vec![Modality::Document, Modality::Vector],
                    0.5,
                    &format!("Conflict {}", i),
                )
                .await;
            resolver.resolve(&conflict.id, None).await.unwrap();
        }

        // Full history should have 3 entries
        let all_history = resolver.history(0).await;
        assert_eq!(all_history.len(), 3);

        // Limited history should return most recent first
        let limited = resolver.history(2).await;
        assert_eq!(limited.len(), 2);
        assert_eq!(limited[0].entity_id, "entity-hist-2"); // most recent
        assert_eq!(limited[1].entity_id, "entity-hist-1");
    }

    #[tokio::test]
    async fn test_history_max_entries_eviction() {
        let config = ConflictConfig {
            max_history_entries: 3,
            ..test_config()
        };

        let resolver = ConflictResolver::new(config);

        // Create and resolve 5 conflicts
        for i in 0..5 {
            let conflict = resolver
                .detect_conflict(
                    &format!("entity-evict-{}", i),
                    vec![Modality::Document, Modality::Vector],
                    0.5,
                    &format!("Conflict {}", i),
                )
                .await;
            resolver.resolve(&conflict.id, None).await.unwrap();
        }

        // History should be capped at 3
        let history = resolver.history(0).await;
        assert_eq!(history.len(), 3);

        // Oldest entries (0 and 1) should have been evicted
        let entity_ids: Vec<&str> = history.iter().map(|c| c.entity_id.as_str()).collect();
        assert!(!entity_ids.contains(&"entity-evict-0"));
        assert!(!entity_ids.contains(&"entity-evict-1"));
        assert!(entity_ids.contains(&"entity-evict-2"));
        assert!(entity_ids.contains(&"entity-evict-3"));
        assert!(entity_ids.contains(&"entity-evict-4"));
    }

    // -- By-entity filtering -------------------------------------------------

    #[tokio::test]
    async fn test_by_entity_filtering() {
        let resolver = ConflictResolver::new(test_config());

        // Create conflicts for two entities
        let c1 = resolver
            .detect_conflict(
                "entity-A",
                vec![Modality::Document, Modality::Vector],
                0.5,
                "Conflict on A",
            )
            .await;

        resolver
            .detect_conflict(
                "entity-B",
                vec![Modality::Graph, Modality::Semantic],
                0.4,
                "Conflict on B",
            )
            .await;

        let c3 = resolver
            .detect_conflict(
                "entity-A",
                vec![Modality::Tensor, Modality::Temporal],
                0.6,
                "Second conflict on A",
            )
            .await;

        // Resolve one of entity-A's conflicts
        resolver.resolve(&c1.id, None).await.unwrap();

        // by_entity should return both A conflicts (1 resolved in history, 1 active)
        let a_conflicts = resolver.by_entity("entity-A").await;
        assert_eq!(a_conflicts.len(), 2);

        // Active should come first
        assert_eq!(a_conflicts[0].id, c3.id);
        assert_eq!(a_conflicts[0].status, ConflictStatus::Open);

        // Then historical
        assert_eq!(a_conflicts[1].id, c1.id);
        assert_eq!(a_conflicts[1].status, ConflictStatus::Resolved);

        // entity-B should have exactly 1
        let b_conflicts = resolver.by_entity("entity-B").await;
        assert_eq!(b_conflicts.len(), 1);
    }

    // -- Per-modality-pair policy override -----------------------------------

    #[tokio::test]
    async fn test_per_modality_pair_policy_override() {
        let mut config = test_config();
        // Override: Document vs Vector conflicts use ModalityPriority
        config.per_modality_policies.insert(
            (Modality::Document, Modality::Vector),
            ConflictPolicy::ModalityPriority(vec![
                Modality::Document,
                Modality::Vector,
            ]),
        );

        let resolver = ConflictResolver::new(config);

        let conflict = resolver
            .detect_conflict(
                "entity-pair",
                vec![Modality::Vector, Modality::Document],
                0.5,
                "Doc vs vector with pair override",
            )
            .await;

        let resolution = resolver.resolve(&conflict.id, None).await.unwrap();

        // Per-pair override should use ModalityPriority with Document winning
        assert_eq!(resolution.winning_modality, Some(Modality::Document));
        assert!(matches!(
            resolution.policy_used,
            ConflictPolicy::ModalityPriority(_)
        ));
    }

    #[tokio::test]
    async fn test_per_modality_pair_reverse_order_lookup() {
        let mut config = test_config();
        // Register (Document, Vector) -- query with (Vector, Document)
        config.per_modality_policies.insert(
            (Modality::Document, Modality::Vector),
            ConflictPolicy::AutoMerge,
        );

        // policy_for_pair should find it in either order
        let policy = config.policy_for_pair(Modality::Vector, Modality::Document);
        assert_eq!(*policy, ConflictPolicy::AutoMerge);
    }

    // -- Already-resolved error ----------------------------------------------

    #[tokio::test]
    async fn test_already_resolved_error() {
        let resolver = ConflictResolver::new(test_config());

        let conflict = resolver
            .detect_conflict(
                "entity-dup",
                vec![Modality::Document, Modality::Vector],
                0.5,
                "Will be resolved twice",
            )
            .await;

        // First resolve succeeds
        resolver.resolve(&conflict.id, None).await.unwrap();

        // Second resolve should fail -- conflict has moved to history
        let err = resolver.resolve(&conflict.id, None).await.unwrap_err();
        assert!(matches!(err, ConflictError::NotFound(_)));
    }

    // -- Not-found error -----------------------------------------------------

    #[tokio::test]
    async fn test_not_found_error() {
        let resolver = ConflictResolver::new(test_config());

        let err = resolver
            .resolve("nonexistent-id", None)
            .await
            .unwrap_err();
        assert!(matches!(err, ConflictError::NotFound(_)));
        assert!(err.to_string().contains("nonexistent-id"));
    }

    #[tokio::test]
    async fn test_manual_resolve_not_found() {
        let resolver = ConflictResolver::new(test_config());

        let err = resolver
            .resolve_manual("nonexistent", Modality::Document, "admin", None)
            .await
            .unwrap_err();
        assert!(matches!(err, ConflictError::NotFound(_)));
    }

    // -- Modality-not-in-conflict error --------------------------------------

    #[tokio::test]
    async fn test_modality_not_in_conflict_error() {
        let resolver = ConflictResolver::new(test_config());

        let conflict = resolver
            .detect_conflict(
                "entity-modal",
                vec![Modality::Document, Modality::Vector],
                0.5,
                "Document vs vector conflict",
            )
            .await;

        // Try to resolve with a modality that is not part of the conflict
        let err = resolver
            .resolve_manual(&conflict.id, Modality::Tensor, "admin", None)
            .await
            .unwrap_err();
        assert!(matches!(err, ConflictError::ModalityNotInConflict(_)));
        assert!(err.to_string().contains("tensor"));
    }

    // -- Multiple conflicts on same entity -----------------------------------

    #[tokio::test]
    async fn test_multiple_conflicts_same_entity() {
        let resolver = ConflictResolver::new(test_config());

        let c1 = resolver
            .detect_conflict(
                "shared-entity",
                vec![Modality::Document, Modality::Vector],
                0.4,
                "First conflict",
            )
            .await;

        let c2 = resolver
            .detect_conflict(
                "shared-entity",
                vec![Modality::Graph, Modality::Semantic],
                0.6,
                "Second conflict",
            )
            .await;

        let c3 = resolver
            .detect_conflict(
                "shared-entity",
                vec![Modality::Tensor, Modality::Temporal],
                0.5,
                "Third conflict",
            )
            .await;

        // All three should be active
        let active = resolver.active_conflicts().await;
        assert_eq!(active.len(), 3);

        // Resolve the first
        resolver.resolve(&c1.id, None).await.unwrap();

        // Now 2 active, 1 in history
        let active = resolver.active_conflicts().await;
        assert_eq!(active.len(), 2);

        let history = resolver.history(10).await;
        assert_eq!(history.len(), 1);

        // by_entity should return all 3
        let by_entity = resolver.by_entity("shared-entity").await;
        assert_eq!(by_entity.len(), 3);
    }

    // -- Active conflicts listing --------------------------------------------

    #[tokio::test]
    async fn test_active_conflicts_listing() {
        let resolver = ConflictResolver::new(test_config());

        // Initially empty
        assert!(resolver.active_conflicts().await.is_empty());

        // Add two conflicts
        let c1 = resolver
            .detect_conflict(
                "entity-list-1",
                vec![Modality::Document, Modality::Vector],
                0.5,
                "First",
            )
            .await;

        let c2 = resolver
            .detect_conflict(
                "entity-list-2",
                vec![Modality::Graph, Modality::Tensor],
                0.6,
                "Second",
            )
            .await;

        let active = resolver.active_conflicts().await;
        assert_eq!(active.len(), 2);
        assert_eq!(active[0].id, c1.id);
        assert_eq!(active[1].id, c2.id);

        // Resolve one
        resolver.resolve(&c1.id, None).await.unwrap();

        let active = resolver.active_conflicts().await;
        assert_eq!(active.len(), 1);
        assert_eq!(active[0].id, c2.id);
    }

    // -- JSON serialization round-trip ---------------------------------------

    #[tokio::test]
    async fn test_json_serialization_roundtrip() {
        let resolver = ConflictResolver::new(test_config());

        let conflict = resolver
            .detect_conflict(
                "entity-json",
                vec![Modality::Document, Modality::Semantic, Modality::Vector],
                0.55,
                "Three-way conflict for serialization test",
            )
            .await;

        // Serialize the conflict to JSON
        let json = serde_json::to_string_pretty(&conflict).unwrap();

        // Deserialize back
        let deserialized: Conflict = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.id, conflict.id);
        assert_eq!(deserialized.entity_id, "entity-json");
        assert_eq!(deserialized.conflicting_modalities.len(), 3);
        assert!((deserialized.drift_score - 0.55).abs() < f64::EPSILON);
        assert_eq!(deserialized.status, ConflictStatus::Open);
        assert!(deserialized.resolution.is_none());

        // Resolve and round-trip the resolution
        let resolution = resolver.resolve(&conflict.id, None).await.unwrap();
        let resolution_json = serde_json::to_string_pretty(&resolution).unwrap();
        let deserialized_resolution: ConflictResolution =
            serde_json::from_str(&resolution_json).unwrap();

        assert_eq!(
            deserialized_resolution.policy_used,
            ConflictPolicy::LastWriterWins
        );
        assert_eq!(deserialized_resolution.resolver, "system");
    }

    // -- ConflictConfig JSON round-trip --------------------------------------

    #[test]
    fn test_conflict_config_json_roundtrip() {
        // Note: per_modality_policies uses a (Modality, Modality) tuple key which
        // does not serialise to JSON directly. We test the round-trip with an
        // empty map (the common case for JSON configs). Binary formats (bincode,
        // postcard, CBOR) can handle tuple keys natively.
        let config = test_config();

        let json = serde_json::to_string_pretty(&config).unwrap();
        let deserialized: ConflictConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.default_policy, config.default_policy);
        assert!((deserialized.auto_resolve_threshold - config.auto_resolve_threshold).abs()
            < f64::EPSILON);
        assert!((deserialized.require_manual_above - config.require_manual_above).abs()
            < f64::EPSILON);
        assert_eq!(deserialized.max_history_entries, config.max_history_entries);
        assert!(deserialized.per_modality_policies.is_empty());
    }

    // -- AutoMerge resolution ------------------------------------------------

    #[tokio::test]
    async fn test_auto_merge_no_single_winner() {
        let config = ConflictConfig {
            default_policy: ConflictPolicy::AutoMerge,
            ..test_config()
        };

        let resolver = ConflictResolver::new(config);

        let conflict = resolver
            .detect_conflict(
                "entity-merge",
                vec![Modality::Document, Modality::Semantic],
                0.5,
                "Merge candidate",
            )
            .await;

        let resolution = resolver.resolve(&conflict.id, None).await.unwrap();

        // AutoMerge does not pick a single winner
        assert!(resolution.winning_modality.is_none());
        assert_eq!(resolution.policy_used, ConflictPolicy::AutoMerge);
    }

    // -- Dismiss already-resolved error --------------------------------------

    #[tokio::test]
    async fn test_dismiss_already_dismissed() {
        let resolver = ConflictResolver::new(test_config());

        let conflict = resolver
            .detect_conflict(
                "entity-dismiss-twice",
                vec![Modality::Document, Modality::Vector],
                0.4,
                "Will be dismissed",
            )
            .await;

        resolver.dismiss(&conflict.id, "First dismissal").await.unwrap();

        // Second dismissal should fail (not found -- moved to history)
        let err = resolver
            .dismiss(&conflict.id, "Second dismissal")
            .await
            .unwrap_err();
        assert!(matches!(err, ConflictError::NotFound(_)));
    }

    // -- Display impls -------------------------------------------------------

    #[test]
    fn test_conflict_policy_display() {
        assert_eq!(
            format!("{}", ConflictPolicy::LastWriterWins),
            "last_writer_wins"
        );
        assert_eq!(
            format!("{}", ConflictPolicy::ModalityPriority(vec![])),
            "modality_priority"
        );
        assert_eq!(
            format!("{}", ConflictPolicy::ManualResolve),
            "manual_resolve"
        );
        assert_eq!(format!("{}", ConflictPolicy::AutoMerge), "auto_merge");
        assert_eq!(
            format!("{}", ConflictPolicy::Custom("webhook".to_string())),
            "custom(webhook)"
        );
    }

    #[test]
    fn test_conflict_status_display() {
        assert_eq!(format!("{}", ConflictStatus::Open), "open");
        assert_eq!(format!("{}", ConflictStatus::InProgress), "in_progress");
        assert_eq!(format!("{}", ConflictStatus::Resolved), "resolved");
        assert_eq!(format!("{}", ConflictStatus::Dismissed), "dismissed");
    }

    // -- ConflictError display -----------------------------------------------

    #[test]
    fn test_conflict_error_display() {
        let err = ConflictError::NotFound("abc-123".to_string());
        assert_eq!(err.to_string(), "Conflict not found: abc-123");

        let err = ConflictError::AlreadyResolved("def-456".to_string());
        assert_eq!(err.to_string(), "Conflict already resolved: def-456");

        let err = ConflictError::InvalidPolicy("bad policy".to_string());
        assert_eq!(err.to_string(), "Invalid policy: bad policy");

        let err = ConflictError::ModalityNotInConflict("tensor".to_string());
        assert_eq!(err.to_string(), "Modality not in conflict: tensor");
    }
}
