// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Federation operations for cross-instance VeriSimDB queries.
//!
//! VeriSimDB supports a federated architecture where multiple instances can be
//! registered as peers. Federated queries fan out to all (or selected) peers
//! and merge results transparently. This module provides peer management and
//! federated query execution.

use serde::Serialize;

use crate::client::VeriSimClient;
use crate::error::Result;
use crate::types::{FederationResult, Modality};

/// Internal request body for registering a federation peer.
#[derive(Debug, Serialize)]
struct RegisterPeerRequest {
    store_id: String,
    endpoint: String,
    adapter_type: String,
    config: serde_json::Value,
}

/// Internal request body for executing a federated query.
#[derive(Debug, Serialize)]
struct FederatedQueryRequest {
    modalities: Vec<Modality>,
    params: serde_json::Value,
}

impl VeriSimClient {
    /// Register a remote VeriSimDB instance (or compatible adapter) as a
    /// federation peer.
    ///
    /// # Arguments
    ///
    /// * `store_id`     — Unique logical name for the peer (e.g. "us-west-replica").
    /// * `endpoint`     — Base URL of the peer's API (e.g. "https://peer.example.com:8080").
    /// * `adapter_type` — Adapter kind: "verisimdb", "quandledb", "lithoglyph", or custom.
    /// * `config`       — Adapter-specific configuration (auth tokens, timeouts, etc.).
    ///
    /// # Returns
    ///
    /// A JSON object representing the registered peer record.
    pub async fn register_peer(
        &self,
        store_id: &str,
        endpoint: &str,
        adapter_type: &str,
        config: serde_json::Value,
    ) -> Result<serde_json::Value> {
        let body = RegisterPeerRequest {
            store_id: store_id.to_owned(),
            endpoint: endpoint.to_owned(),
            adapter_type: adapter_type.to_owned(),
            config,
        };
        self.post("/api/v1/federation/peers", &body).await
    }

    /// List all registered federation peers.
    ///
    /// Returns a vector of peer records, each containing the store ID, endpoint,
    /// adapter type, health status, and last-seen timestamp.
    pub async fn list_peers(&self) -> Result<Vec<serde_json::Value>> {
        self.get("/api/v1/federation/peers").await
    }

    /// Execute a federated query that fans out to all registered peers.
    ///
    /// The query targets the specified modalities and passes `params` to each
    /// peer's local query engine. Results are merged and returned with per-peer
    /// attribution.
    ///
    /// # Arguments
    ///
    /// * `modalities` — Which modalities to query across peers.
    /// * `params`     — Query parameters (modality-specific filters, limits, etc.).
    ///
    /// # Returns
    ///
    /// A vector of [`FederationResult`] items, one per matched entity across
    /// all responding peers.
    pub async fn federated_query(
        &self,
        modalities: &[Modality],
        params: serde_json::Value,
    ) -> Result<Vec<FederationResult>> {
        let body = FederatedQueryRequest {
            modalities: modalities.to_vec(),
            params,
        };
        self.post("/api/v1/federation/query", &body).await
    }
}
