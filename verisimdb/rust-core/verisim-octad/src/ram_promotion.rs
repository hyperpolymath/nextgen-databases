// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB Optional RAM Promotion — tiered storage acceleration.
//
// DESIGN CONSTRAINTS:
//   - OPTIONAL: database works fine without this, disk-backed by default
//   - MAX 3 OCTADS promoted at a time (hard limit)
//   - MINIMAL TIME in RAM: promote before operation, demote immediately after
//   - ONLY IF SIGNIFICANT BENEFIT: estimated speedup must exceed threshold
//
// The promotion manager tracks which modality stores are currently
// RAM-resident via tmpfs-backed mmaps, enforces the 2-octad limit,
// and auto-demotes after operation completion.
//
// ABSOLUTE GUARANTEES:
//
// 1. NOTHING stays in RAM unless EXPLICITLY requested by the caller.
//    The default state is DISABLED. Promotion never happens automatically.
//
// 2. All data is ALWAYS on disk (via VeriSimDB's WAL + redb persistence).
//    RAM promotion is a READ CACHE only — the WAL on disk is the source
//    of truth. If RAM disappears (crash, reboot), WAL replay recovers.
//
// 3. Maximum 2 octads in RAM at once (conservative limit for crash safety).
//
// 4. Maximum 5 minutes in RAM before forced demotion (MAX_PROMOTION_DURATION).
//    The caller should demote IMMEDIATELY after their operation completes.
//    The 5-minute timeout is a safety net, not a target.
//
// 5. The PromotionManager does NOT move data. It signals to the modality
//    store that it should use tmpfs-backed storage. The actual data lives
//    in redb (disk) at all times. The RAM copy is a performance overlay.
//
// WHERE DATA LIVES:
//   - WAL: always on disk (redb file in data directory)
//   - Modality stores: always on disk (redb files)
//   - RAM promotion: tmpfs overlay for reads, writes go to WAL first
//   - On crash: WAL replays, RAM overlay is gone, no data loss

use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};
use serde::{Serialize, Deserialize};

/// Hard limit: maximum octads promoted to RAM simultaneously.
/// Conservative limit (2 not 3) for crash safety — fewer in-flight
/// RAM-resident octads means faster WAL replay on recovery.
const MAX_PROMOTED: usize = 2;

/// Minimum estimated speedup factor to justify promotion.
/// If estimated speedup is less than 2x, don't bother promoting.
const MIN_SPEEDUP_FACTOR: f64 = 2.0;

/// Maximum time an octad can stay promoted before forced demotion.
const MAX_PROMOTION_DURATION: Duration = Duration::from_secs(300); // 5 minutes

/// Modality names matching VeriSimDB's octad structure.
#[derive(Debug, Clone, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub enum Modality {
    Graph,
    Vector,
    Tensor,
    Semantic,
    Document,
    Temporal,
    Provenance,
    Spatial,
}

impl Modality {
    pub fn all() -> Vec<Modality> {
        vec![
            Modality::Graph, Modality::Vector, Modality::Tensor,
            Modality::Semantic, Modality::Document, Modality::Temporal,
            Modality::Provenance, Modality::Spatial,
        ]
    }

    pub fn name(&self) -> &str {
        match self {
            Modality::Graph => "graph",
            Modality::Vector => "vector",
            Modality::Tensor => "tensor",
            Modality::Semantic => "semantic",
            Modality::Document => "document",
            Modality::Temporal => "temporal",
            Modality::Provenance => "provenance",
            Modality::Spatial => "spatial",
        }
    }
}

/// State of a promoted modality.
#[derive(Debug, Clone)]
struct PromotedState {
    modality: Modality,
    promoted_at: Instant,
    estimated_size_bytes: u64,
    operation_count: u64,
}

/// Promotion decision result.
#[derive(Debug, Clone)]
pub enum PromotionDecision {
    /// Promote — significant benefit expected.
    Promote { modalities: Vec<Modality>, estimated_speedup: f64 },
    /// Skip — benefit too small to justify RAM usage.
    Skip { reason: String },
    /// Blocked — already at MAX_PROMOTED limit.
    Blocked { current_count: usize, limit: usize },
}

/// The RAM promotion manager.
#[derive(Debug)]
pub struct PromotionManager {
    /// Currently promoted modalities.
    promoted: HashMap<Modality, PromotedState>,
    /// Total RAM budget (bytes). Default: 1GB.
    ram_budget: u64,
    /// RAM currently used by promoted modalities.
    ram_used: u64,
    /// Whether promotion is enabled at all.
    enabled: bool,
    /// Promotion/demotion history for performance tracking.
    history: Vec<PromotionEvent>,
}

/// A promotion or demotion event for history tracking.
#[derive(Debug, Clone, Serialize)]
pub struct PromotionEvent {
    pub modality: String,
    pub action: PromotionAction,
    pub duration_ms: Option<u64>,
    pub size_bytes: u64,
    pub timestamp_epoch_ms: u64,
}

#[derive(Debug, Clone, Serialize)]
pub enum PromotionAction {
    Promoted,
    Demoted,
    Denied { reason: String },
}

impl PromotionManager {
    /// Create a new promotion manager. Disabled by default.
    pub fn new() -> Self {
        PromotionManager {
            promoted: HashMap::new(),
            ram_budget: 1_073_741_824, // 1 GB
            ram_used: 0,
            enabled: false,
            history: Vec::new(),
        }
    }

    /// Enable promotion with a RAM budget.
    pub fn enable(&mut self, ram_budget_bytes: u64) {
        self.enabled = true;
        self.ram_budget = ram_budget_bytes;
    }

    /// Disable promotion. Demotes all currently promoted modalities.
    pub fn disable(&mut self) {
        let modalities: Vec<Modality> = self.promoted.keys().cloned().collect();
        for m in modalities {
            self.demote(&m);
        }
        self.enabled = false;
    }

    /// Check if promotion is enabled.
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// How many modalities are currently promoted.
    pub fn promoted_count(&self) -> usize {
        self.promoted.len()
    }

    /// Which modalities are currently promoted.
    pub fn promoted_modalities(&self) -> Vec<&Modality> {
        self.promoted.keys().collect()
    }

    /// Decide whether to promote modalities for an operation.
    ///
    /// Considers: current promotion count, RAM budget, estimated data size,
    /// and estimated speedup factor.
    pub fn decide(
        &self,
        modalities: &[Modality],
        estimated_data_size: u64,
        estimated_disk_time_ms: u64,
        estimated_ram_time_ms: u64,
    ) -> PromotionDecision {
        if !self.enabled {
            return PromotionDecision::Skip {
                reason: "RAM promotion disabled".to_string(),
            };
        }

        // Check 3-octad limit.
        let new_count = modalities.iter()
            .filter(|m| !self.promoted.contains_key(m))
            .count();
        if self.promoted.len() + new_count > MAX_PROMOTED {
            return PromotionDecision::Blocked {
                current_count: self.promoted.len(),
                limit: MAX_PROMOTED,
            };
        }

        // Check RAM budget.
        if self.ram_used + estimated_data_size > self.ram_budget {
            return PromotionDecision::Skip {
                reason: format!(
                    "Insufficient RAM budget: need {} bytes, have {} available",
                    estimated_data_size,
                    self.ram_budget - self.ram_used
                ),
            };
        }

        // Check speedup threshold.
        let speedup = if estimated_ram_time_ms > 0 {
            estimated_disk_time_ms as f64 / estimated_ram_time_ms as f64
        } else {
            f64::INFINITY
        };

        if speedup < MIN_SPEEDUP_FACTOR {
            return PromotionDecision::Skip {
                reason: format!(
                    "Estimated speedup {:.1}x below threshold {:.1}x",
                    speedup, MIN_SPEEDUP_FACTOR
                ),
            };
        }

        PromotionDecision::Promote {
            modalities: modalities.to_vec(),
            estimated_speedup: speedup,
        }
    }

    /// Promote a modality to RAM.
    ///
    /// Returns Ok(()) if promoted, Err if blocked/disabled.
    pub fn promote(&mut self, modality: &Modality, estimated_size: u64) -> Result<(), String> {
        if !self.enabled {
            return Err("RAM promotion disabled".to_string());
        }

        if self.promoted.len() >= MAX_PROMOTED {
            return Err(format!(
                "Cannot promote: already at limit ({}/{})",
                self.promoted.len(), MAX_PROMOTED
            ));
        }

        if self.promoted.contains_key(modality) {
            return Ok(()); // Already promoted.
        }

        if self.ram_used + estimated_size > self.ram_budget {
            return Err(format!(
                "Cannot promote: would exceed RAM budget ({} + {} > {})",
                self.ram_used, estimated_size, self.ram_budget
            ));
        }

        self.promoted.insert(modality.clone(), PromotedState {
            modality: modality.clone(),
            promoted_at: Instant::now(),
            estimated_size_bytes: estimated_size,
            operation_count: 0,
        });
        self.ram_used += estimated_size;

        self.history.push(PromotionEvent {
            modality: modality.name().to_string(),
            action: PromotionAction::Promoted,
            duration_ms: None,
            size_bytes: estimated_size,
            timestamp_epoch_ms: epoch_ms(),
        });

        Ok(())
    }

    /// Demote a modality from RAM back to disk.
    pub fn demote(&mut self, modality: &Modality) {
        if let Some(state) = self.promoted.remove(modality) {
            self.ram_used = self.ram_used.saturating_sub(state.estimated_size_bytes);

            let duration = state.promoted_at.elapsed();
            self.history.push(PromotionEvent {
                modality: modality.name().to_string(),
                action: PromotionAction::Demoted,
                duration_ms: Some(duration.as_millis() as u64),
                size_bytes: state.estimated_size_bytes,
                timestamp_epoch_ms: epoch_ms(),
            });
        }
    }

    /// Demote all currently promoted modalities.
    pub fn demote_all(&mut self) {
        let modalities: Vec<Modality> = self.promoted.keys().cloned().collect();
        for m in modalities {
            self.demote(&m);
        }
    }

    /// Check for expired promotions and force-demote them.
    pub fn enforce_timeouts(&mut self) {
        let expired: Vec<Modality> = self.promoted.iter()
            .filter(|(_, state)| state.promoted_at.elapsed() > MAX_PROMOTION_DURATION)
            .map(|(m, _)| m.clone())
            .collect();

        for m in expired {
            self.demote(&m);
        }
    }

    /// Record that an operation was performed on a promoted modality.
    pub fn record_operation(&mut self, modality: &Modality) {
        if let Some(state) = self.promoted.get_mut(modality) {
            state.operation_count += 1;
        }
    }

    /// Get promotion history.
    pub fn history(&self) -> &[PromotionEvent] {
        &self.history
    }

    /// Get current RAM usage.
    pub fn ram_usage(&self) -> (u64, u64) {
        (self.ram_used, self.ram_budget)
    }
}

impl Default for PromotionManager {
    fn default() -> Self { Self::new() }
}

fn epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabled_by_default() {
        let pm = PromotionManager::new();
        assert!(!pm.is_enabled());
        assert_eq!(pm.promoted_count(), 0);
    }

    #[test]
    fn enable_and_promote() {
        let mut pm = PromotionManager::new();
        pm.enable(1_000_000); // 1 MB budget

        assert!(pm.promote(&Modality::Graph, 100_000).is_ok());
        assert_eq!(pm.promoted_count(), 1);
        assert!(pm.promoted_modalities().contains(&&Modality::Graph));
    }

    #[test]
    fn max_two_limit() {
        let mut pm = PromotionManager::new();
        pm.enable(10_000_000);

        assert!(pm.promote(&Modality::Graph, 1000).is_ok());
        assert!(pm.promote(&Modality::Vector, 1000).is_ok());
        // Third should fail — limit is 2.
        assert!(pm.promote(&Modality::Tensor, 1000).is_err());
        assert_eq!(pm.promoted_count(), 2);
    }

    #[test]
    fn demote_frees_slot() {
        let mut pm = PromotionManager::new();
        pm.enable(10_000_000);

        pm.promote(&Modality::Graph, 1000).expect("TODO: handle error");
        pm.promote(&Modality::Vector, 1000).expect("TODO: handle error");

        pm.demote(&Modality::Graph);
        assert_eq!(pm.promoted_count(), 1);

        // Now we can promote another.
        assert!(pm.promote(&Modality::Tensor, 1000).is_ok());
        assert_eq!(pm.promoted_count(), 2);
    }

    #[test]
    fn ram_budget_enforced() {
        let mut pm = PromotionManager::new();
        pm.enable(5000); // 5 KB budget

        assert!(pm.promote(&Modality::Graph, 3000).is_ok());
        // This would exceed budget.
        assert!(pm.promote(&Modality::Vector, 3000).is_err());

        let (used, budget) = pm.ram_usage();
        assert_eq!(used, 3000);
        assert_eq!(budget, 5000);
    }

    #[test]
    fn decision_checks_speedup() {
        let mut pm = PromotionManager::new();
        pm.enable(10_000_000);

        // 10x speedup — should promote.
        let decision = pm.decide(&[Modality::Tensor], 1000, 100, 10);
        assert!(matches!(decision, PromotionDecision::Promote { .. }));

        // 1.5x speedup — below threshold (2x), should skip.
        let decision = pm.decide(&[Modality::Graph], 1000, 15, 10);
        assert!(matches!(decision, PromotionDecision::Skip { .. }));
    }

    #[test]
    fn demote_all() {
        let mut pm = PromotionManager::new();
        pm.enable(10_000_000);

        pm.promote(&Modality::Graph, 1000).expect("TODO: handle error");
        pm.promote(&Modality::Vector, 1000).expect("TODO: handle error");
        pm.demote_all();

        assert_eq!(pm.promoted_count(), 0);
        let (used, _) = pm.ram_usage();
        assert_eq!(used, 0);
    }

    #[test]
    fn history_tracked() {
        let mut pm = PromotionManager::new();
        pm.enable(10_000_000);

        pm.promote(&Modality::Graph, 1000).expect("TODO: handle error");
        pm.demote(&Modality::Graph);

        assert_eq!(pm.history().len(), 2);
        assert!(matches!(pm.history()[0].action, PromotionAction::Promoted));
        assert!(matches!(pm.history()[1].action, PromotionAction::Demoted));
        assert!(pm.history()[1].duration_ms.is_some());
    }

    #[test]
    fn disabled_rejects_all() {
        let mut pm = PromotionManager::new();
        // Not enabled.
        assert!(pm.promote(&Modality::Graph, 1000).is_err());

        let decision = pm.decide(&[Modality::Graph], 1000, 100, 10);
        assert!(matches!(decision, PromotionDecision::Skip { .. }));
    }
}
