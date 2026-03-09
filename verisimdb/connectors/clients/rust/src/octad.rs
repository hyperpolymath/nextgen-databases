// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Octad CRUD operations.
//!
//! Octads are the fundamental multi-modal entities in VeriSimDB. Each octad can
//! carry data across all eight modalities (graph, vector, tensor, semantic,
//! document, temporal, provenance, spatial). This module provides create, read,
//! update, delete, and list operations as methods on [`VeriSimClient`].

use crate::client::VeriSimClient;
use crate::error::Result;
use crate::types::{Octad, OctadInput, PaginatedResponse};

impl VeriSimClient {
    /// Create a new octad entity.
    ///
    /// The server assigns a UUID and timestamps; the returned [`Octad`] contains
    /// the fully-populated record.
    ///
    /// # Arguments
    ///
    /// * `input` — The octad payload. At minimum, `name` should be set.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::Validation`] if required fields are missing, or a
    /// network / server error on transport failure.
    pub async fn create_octad(&self, input: &OctadInput) -> Result<Octad> {
        self.post("/api/v1/octads", input).await
    }

    /// Retrieve a single octad by its unique identifier.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if no octad exists with the given `id`.
    pub async fn get_octad(&self, id: &str) -> Result<Octad> {
        let path = format!("/api/v1/octads/{id}");
        self.get(&path).await
    }

    /// Update an existing octad entity.
    ///
    /// Only the fields present in `input` are modified; omitted fields retain
    /// their current values (partial update / merge semantics).
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if the octad does not exist.
    pub async fn update_octad(&self, id: &str, input: &OctadInput) -> Result<Octad> {
        let path = format!("/api/v1/octads/{id}");
        self.put(&path, input).await
    }

    /// Delete a octad entity by its unique identifier.
    ///
    /// This is a hard delete — the entity and all associated modality data are
    /// removed. Provenance records are retained for auditability.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::NotFound`] if the octad does not exist.
    pub async fn delete_octad(&self, id: &str) -> Result<()> {
        let path = format!("/api/v1/octads/{id}");
        self.delete(&path).await
    }

    /// List octad entities with pagination.
    ///
    /// # Arguments
    ///
    /// * `limit`  — Maximum number of results to return (server may cap this).
    /// * `offset` — Zero-based offset for pagination.
    ///
    /// # Returns
    ///
    /// A [`PaginatedResponse`] containing the requested page of octads.
    pub async fn list_octads(
        &self,
        limit: usize,
        offset: usize,
    ) -> Result<PaginatedResponse<Octad>> {
        let path = format!("/api/v1/octads?limit={limit}&offset={offset}");
        self.get(&path).await
    }
}
