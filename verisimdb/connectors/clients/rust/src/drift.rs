// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Drift detection and normalization operations.
//!
//! VeriSimDB continuously monitors how far each hexad's modality data has
//! diverged from its normalised baseline. When drift exceeds a configurable
//! threshold the entity is flagged for re-normalisation. This module exposes
//! drift score retrieval, system-wide status, and manual normalization triggers.

use crate::client::VeriSimClient;
use crate::error::Result;
use crate::types::DriftScore;

impl VeriSimClient {
    /// Retrieve the drift score for a single hexad entity.
    ///
    /// The score aggregates per-modality drift metrics into an overall value
    /// (0.0 = perfectly normalised, higher = more drift).
    ///
    /// # Arguments
    ///
    /// * `id` — The hexad entity identifier.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if the entity does not exist.
    pub async fn get_drift_score(&self, id: &str) -> Result<DriftScore> {
        let path = format!("/api/v1/drift/{id}");
        self.get(&path).await
    }

    /// Retrieve system-wide drift status.
    ///
    /// Returns a JSON object summarising total entities monitored, number
    /// exceeding drift threshold, average drift, and last sweep timestamp.
    pub async fn drift_status(&self) -> Result<serde_json::Value> {
        self.get("/api/v1/drift/status").await
    }

    /// Trigger re-normalisation for a specific hexad entity.
    ///
    /// This enqueues the entity for the normaliser pipeline, which will
    /// recompute cross-modality consistency and update the baseline.
    ///
    /// # Arguments
    ///
    /// * `id` — The hexad entity identifier.
    pub async fn trigger_normalization(&self, id: &str) -> Result<()> {
        let path = format!("/api/v1/drift/{id}/normalize");
        let empty: serde_json::Value = serde_json::json!({});
        let _: serde_json::Value = self.post(&path, &empty).await?;
        Ok(())
    }

    /// Retrieve the normaliser pipeline status.
    ///
    /// Returns a JSON object with queue depth, active workers, throughput
    /// metrics, and last error (if any).
    pub async fn normalizer_status(&self) -> Result<serde_json::Value> {
        self.get("/api/v1/drift/normalizer/status").await
    }
}
