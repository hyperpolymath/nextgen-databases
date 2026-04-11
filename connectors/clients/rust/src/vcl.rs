// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! VeriSim Consonance Language (VCL) execution.
//!
//! VCL is VeriSimDB's native query language, supporting SQL-like syntax extended
//! with multi-modal operations (vector similarity, graph traversal, spatial
//! predicates, drift thresholds, etc.). This module provides methods to execute
//! VCL statements and retrieve explain / query plans.

use serde::{Deserialize, Serialize};

use crate::client::VeriSimClient;
use crate::error::Result;

/// Response from a VCL query execution or explain request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VclResponse {
    /// Whether the query executed successfully.
    pub success: bool,
    /// The type of VCL statement ("SELECT", "INSERT", "UPDATE", "DELETE", "EXPLAIN", etc.).
    pub statement_type: String,
    /// Number of rows affected or returned.
    pub row_count: usize,
    /// The result data (rows for SELECT, affected IDs for mutations, plan for EXPLAIN).
    pub data: serde_json::Value,
    /// Optional human-readable message (warnings, notices, etc.).
    pub message: Option<String>,
}

/// Internal request body for VCL execution.
#[derive(Debug, Serialize)]
struct VclRequest {
    query: String,
}

impl VeriSimClient {
    /// Execute a VCL statement against the VeriSimDB instance.
    ///
    /// Supports SELECT, INSERT, UPDATE, DELETE, and VeriSimDB-specific
    /// statements like `DRIFT CHECK`, `NORMALIZE`, and `FEDERATE`.
    ///
    /// # Arguments
    ///
    /// * `query` — The VCL statement string.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::Server`] if the query has syntax errors or
    /// the server rejects it for semantic reasons.
    pub async fn execute_vcl(&self, query: &str) -> Result<VclResponse> {
        let body = VclRequest {
            query: query.to_owned(),
        };
        self.post("/api/v1/vcl/execute", &body).await
    }

    /// Request an explain / query plan for a VCL statement without executing it.
    ///
    /// Useful for understanding which modalities, indices, and federation peers
    /// would be involved in a query.
    ///
    /// # Arguments
    ///
    /// * `query` — The VCL statement string to explain.
    pub async fn explain_vcl(&self, query: &str) -> Result<VclResponse> {
        let body = VclRequest {
            query: query.to_owned(),
        };
        self.post("/api/v1/vcl/explain", &body).await
    }
}
