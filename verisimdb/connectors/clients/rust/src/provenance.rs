// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Provenance chain operations.
//!
//! Every hexad entity in VeriSimDB maintains an append-only provenance chain
//! recording creation, transformation, derivation, and access events. This
//! module provides methods to read, append to, and cryptographically verify
//! provenance chains.

use crate::client::VeriSimClient;
use crate::error::Result;
use crate::types::ProvenanceEvent;

impl VeriSimClient {
    /// Retrieve the full provenance chain for a hexad entity.
    ///
    /// Events are returned in chronological order (oldest first).
    ///
    /// # Arguments
    ///
    /// * `id` — The hexad entity identifier.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if the entity does not exist.
    pub async fn get_provenance_chain(&self, id: &str) -> Result<Vec<ProvenanceEvent>> {
        let path = format!("/api/v1/provenance/{id}");
        self.get(&path).await
    }

    /// Append a new event to a hexad's provenance chain.
    ///
    /// The event is immutably recorded; its timestamp and identifier are
    /// assigned by the server. The returned [`ProvenanceEvent`] contains the
    /// server-assigned fields.
    ///
    /// # Arguments
    ///
    /// * `id`    — The hexad entity identifier.
    /// * `event` — The provenance event to record.
    pub async fn record_provenance(
        &self,
        id: &str,
        event: &ProvenanceEvent,
    ) -> Result<ProvenanceEvent> {
        let path = format!("/api/v1/provenance/{id}");
        self.post(&path, event).await
    }

    /// Verify the integrity of a hexad's provenance chain.
    ///
    /// The server checks that the chain is contiguous, that no events have been
    /// tampered with, and that cryptographic hashes (if enabled) are consistent.
    ///
    /// # Returns
    ///
    /// A JSON object with `valid: bool`, `chain_length: usize`, and optional
    /// `errors` array describing any integrity violations.
    ///
    /// # Arguments
    ///
    /// * `id` — The hexad entity identifier.
    pub async fn verify_provenance(&self, id: &str) -> Result<serde_json::Value> {
        let path = format!("/api/v1/provenance/{id}/verify");
        self.get(&path).await
    }
}
