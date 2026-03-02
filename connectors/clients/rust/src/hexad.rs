// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Hexad CRUD operations.
//!
//! Hexads are the fundamental multi-modal entities in VeriSimDB. Each hexad can
//! carry data across all eight modalities (graph, vector, tensor, semantic,
//! document, temporal, provenance, spatial). This module provides create, read,
//! update, delete, and list operations as methods on [`VeriSimClient`].

use crate::client::VeriSimClient;
use crate::error::Result;
use crate::types::{Hexad, HexadInput, PaginatedResponse};

impl VeriSimClient {
    /// Create a new hexad entity.
    ///
    /// The server assigns a UUID and timestamps; the returned [`Hexad`] contains
    /// the fully-populated record.
    ///
    /// # Arguments
    ///
    /// * `input` — The hexad payload. At minimum, `name` should be set.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::Validation`] if required fields are missing, or a
    /// network / server error on transport failure.
    pub async fn create_hexad(&self, input: &HexadInput) -> Result<Hexad> {
        self.post("/api/v1/hexads", input).await
    }

    /// Retrieve a single hexad by its unique identifier.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if no hexad exists with the given `id`.
    pub async fn get_hexad(&self, id: &str) -> Result<Hexad> {
        let path = format!("/api/v1/hexads/{id}");
        self.get(&path).await
    }

    /// Update an existing hexad entity.
    ///
    /// Only the fields present in `input` are modified; omitted fields retain
    /// their current values (partial update / merge semantics).
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if the hexad does not exist.
    pub async fn update_hexad(&self, id: &str, input: &HexadInput) -> Result<Hexad> {
        let path = format!("/api/v1/hexads/{id}");
        self.put(&path, input).await
    }

    /// Delete a hexad entity by its unique identifier.
    ///
    /// This is a hard delete — the entity and all associated modality data are
    /// removed. Provenance records are retained for auditability.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if the hexad does not exist.
    pub async fn delete_hexad(&self, id: &str) -> Result<()> {
        let path = format!("/api/v1/hexads/{id}");
        self.delete(&path).await
    }

    /// List hexad entities with pagination.
    ///
    /// # Arguments
    ///
    /// * `limit`  — Maximum number of results to return (server may cap this).
    /// * `offset` — Zero-based offset for pagination.
    ///
    /// # Returns
    ///
    /// A [`PaginatedResponse`] containing the requested page of hexads.
    pub async fn list_hexads(
        &self,
        limit: usize,
        offset: usize,
    ) -> Result<PaginatedResponse<Hexad>> {
        let path = format!("/api/v1/hexads?limit={limit}&offset={offset}");
        self.get(&path).await
    }
}
