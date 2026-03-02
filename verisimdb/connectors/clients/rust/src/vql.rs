// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! VeriSim Query Language (VQL) execution.
//!
//! VQL is VeriSimDB's native query language, supporting SQL-like syntax extended
//! with multi-modal operations (vector similarity, graph traversal, spatial
//! predicates, drift thresholds, etc.). This module provides methods to execute
//! VQL statements and retrieve explain / query plans.

use serde::{Deserialize, Serialize};

use crate::client::VeriSimClient;
use crate::error::Result;

/// Response from a VQL query execution or explain request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VqlResponse {
    /// Whether the query executed successfully.
    pub success: bool,
    /// The type of VQL statement ("SELECT", "INSERT", "UPDATE", "DELETE", "EXPLAIN", etc.).
    pub statement_type: String,
    /// Number of rows affected or returned.
    pub row_count: usize,
    /// The result data (rows for SELECT, affected IDs for mutations, plan for EXPLAIN).
    pub data: serde_json::Value,
    /// Optional human-readable message (warnings, notices, etc.).
    pub message: Option<String>,
}

/// Internal request body for VQL execution.
#[derive(Debug, Serialize)]
struct VqlRequest {
    query: String,
}

impl VeriSimClient {
    /// Execute a VQL statement against the VeriSimDB instance.
    ///
    /// Supports SELECT, INSERT, UPDATE, DELETE, and VeriSimDB-specific
    /// statements like `DRIFT CHECK`, `NORMALIZE`, and `FEDERATE`.
    ///
    /// # Arguments
    ///
    /// * `query` — The VQL statement string.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::Server`] if the query has syntax errors or
    /// the server rejects it for semantic reasons.
    pub async fn execute_vql(&self, query: &str) -> Result<VqlResponse> {
        let body = VqlRequest {
            query: query.to_owned(),
        };
        self.post("/api/v1/vql/execute", &body).await
    }

    /// Request an explain / query plan for a VQL statement without executing it.
    ///
    /// Useful for understanding which modalities, indices, and federation peers
    /// would be involved in a query.
    ///
    /// # Arguments
    ///
    /// * `query` — The VQL statement string to explain.
    pub async fn explain_vql(&self, query: &str) -> Result<VqlResponse> {
        let body = VqlRequest {
            query: query.to_owned(),
        };
        self.post("/api/v1/vql/explain", &body).await
    }
}
