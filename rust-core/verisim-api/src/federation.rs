// SPDX-License-Identifier: PMPL-1.0-or-later
//! Federation Protocol for VeriSimDB
//!
//! Enables cross-instance querying with drift-aware consistency policies.
//! Each VeriSimDB instance can federate with others to form a distributed
//! knowledge network while maintaining local autonomy.
//!
//! ## Protocol
//!
//! Federation uses a pull-based HTTP protocol where the coordinator
//! (the instance receiving the query) fans out requests to peer stores
//! and aggregates results according to the configured drift policy.
//!
//! ## Drift Policies
//!
//! - **Strict**: Only return results from stores with drift score < threshold.
//! - **Repair**: Return results and trigger normalization on drifted stores.
//! - **Tolerate**: Return all results, annotating drifted ones.
//! - **Latest**: Return only the most recent version from each store.

use axum::{
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use tracing::{error, info, warn, instrument};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Drift policy for federated queries.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DriftPolicy {
    Strict,
    Repair,
    Tolerate,
    Latest,
}

impl Default for DriftPolicy {
    fn default() -> Self {
        DriftPolicy::Tolerate
    }
}

/// A registered peer store in the federation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerStore {
    /// Unique store identifier.
    pub store_id: String,
    /// HTTP endpoint URL (e.g., "https://store-2.verisimdb.example.com/api/v1").
    pub endpoint: String,
    /// Modalities this store supports.
    pub modalities: Vec<String>,
    /// Trust level (0.0 - 1.0).
    pub trust_level: f64,
    /// Last health check timestamp (RFC 3339).
    pub last_seen: Option<String>,
    /// Average response time in milliseconds.
    pub response_time_ms: Option<u64>,
    /// SHA-256 hash of the peer's secret (not serialized to clients).
    #[serde(skip)]
    pub secret_hash: Option<String>,
}

/// A federation query request.
#[derive(Debug, Serialize, Deserialize)]
pub struct FederationQueryRequest {
    /// Pattern to match stores (e.g., "/universities/*", or a specific store ID).
    pub pattern: String,
    /// Modalities to query.
    pub modalities: Vec<String>,
    /// Drift policy.
    #[serde(default)]
    pub drift_policy: DriftPolicy,
    /// Maximum results per store.
    pub limit: Option<usize>,
    /// Optional text query.
    pub text_query: Option<String>,
    /// Optional vector query.
    pub vector_query: Option<Vec<f32>>,
}

/// A single result from a federated query.
#[derive(Debug, Serialize, Deserialize)]
pub struct FederationResult {
    /// Which store provided this result.
    pub source_store: String,
    /// Hexad ID.
    pub hexad_id: String,
    /// Relevance score.
    pub score: f64,
    /// Whether the source store has drift issues.
    pub drifted: bool,
    /// Result data (modality-dependent).
    pub data: serde_json::Value,
}

/// Response for federation queries.
#[derive(Debug, Serialize, Deserialize)]
pub struct FederationQueryResponse {
    /// Query results aggregated from all matching stores.
    pub results: Vec<FederationResult>,
    /// Stores that were queried.
    pub stores_queried: Vec<String>,
    /// Stores that failed or were excluded by drift policy.
    pub stores_excluded: Vec<String>,
    /// The drift policy applied.
    pub drift_policy: DriftPolicy,
}

/// Registration request to join the federation.
#[derive(Debug, Serialize, Deserialize)]
pub struct RegisterRequest {
    pub store_id: String,
    pub endpoint: String,
    pub modalities: Vec<String>,
    /// Pre-shared key for this peer (sent once at registration, stored as SHA-256 hash).
    pub secret: Option<String>,
}

/// Health check from a peer.
#[derive(Debug, Serialize, Deserialize)]
pub struct HeartbeatRequest {
    pub store_id: String,
    pub drift_scores: HashMap<String, f64>,
}

/// Federation registry query parameters.
#[derive(Debug, Deserialize)]
pub struct PeerQueryParams {
    pub modality: Option<String>,
}

// ---------------------------------------------------------------------------
// Federation State
// ---------------------------------------------------------------------------

/// Shared federation state — registry of known peer stores.
#[derive(Clone)]
pub struct FederationState {
    pub peers: Arc<RwLock<HashMap<String, PeerStore>>>,
    pub self_store_id: String,
    pub self_endpoint: String,
    /// Drift threshold for Strict policy.
    pub strict_drift_threshold: f64,
    /// Pre-shared keys for federation peers (store_id → key).
    /// Parsed from `VERISIM_FEDERATION_KEYS` env var (comma-separated `store_id:key`).
    /// When empty, federation registration is disabled (closed by default).
    federation_keys: Arc<HashMap<String, String>>,
}

impl FederationState {
    pub fn new(self_store_id: String, self_endpoint: String) -> Self {
        let keys = Self::load_federation_keys();
        Self {
            peers: Arc::new(RwLock::new(HashMap::new())),
            self_store_id,
            self_endpoint,
            strict_drift_threshold: 0.3,
            federation_keys: Arc::new(keys),
        }
    }

    /// Load federation keys from `VERISIM_FEDERATION_KEYS` env var.
    /// Format: `store_id1:key1,store_id2:key2,...`
    fn load_federation_keys() -> HashMap<String, String> {
        match std::env::var("VERISIM_FEDERATION_KEYS") {
            Ok(val) if !val.is_empty() => {
                val.split(',')
                    .filter_map(|pair| {
                        let parts: Vec<&str> = pair.splitn(2, ':').collect();
                        if parts.len() == 2 {
                            Some((parts[0].trim().to_string(), parts[1].trim().to_string()))
                        } else {
                            warn!(entry = %pair, "Invalid federation key entry (expected store_id:key)");
                            None
                        }
                    })
                    .collect()
            }
            _ => HashMap::new(),
        }
    }

    /// Check if federation registration is enabled (requires keys to be configured).
    pub fn registration_enabled(&self) -> bool {
        !self.federation_keys.is_empty()
    }

    /// Validate a PSK for a given store_id.
    fn validate_psk(&self, store_id: &str, provided_secret: &str) -> bool {
        if let Some(expected_key) = self.federation_keys.get(store_id) {
            expected_key == provided_secret
        } else {
            false
        }
    }

    /// Validate the X-Federation-PSK header for an existing peer.
    fn validate_peer_header(&self, store_id: &str, headers: &HeaderMap) -> Result<(), StatusCode> {
        let psk = headers
            .get("X-Federation-PSK")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");

        if psk.is_empty() {
            return Err(StatusCode::UNAUTHORIZED);
        }

        // Check against stored hash
        let peers = self.peers.read().map_err(|_| {
            error!("Federation peers RwLock poisoned");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

        if let Some(peer) = peers.get(store_id) {
            if let Some(ref stored_hash) = peer.secret_hash {
                let provided_hash = sha256_hex(psk);
                if stored_hash == &provided_hash {
                    return Ok(());
                }
            }
        }

        Err(StatusCode::UNAUTHORIZED)
    }
}

/// Compute SHA-256 hex digest of a string.
fn sha256_hex(input: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    format!("{:x}", hasher.finalize())
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

/// Build federation API routes.
pub fn federation_router(state: FederationState) -> Router {
    Router::new()
        .route("/federation/peers", get(list_peers))
        .route("/federation/register", post(register_peer))
        .route("/federation/heartbeat", post(heartbeat))
        .route("/federation/query", post(federation_query))
        .route("/federation/deregister/{store_id}", post(deregister_peer))
        .with_state(state)
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// List all known peer stores.
#[instrument(skip(state))]
async fn list_peers(
    State(state): State<FederationState>,
    Query(params): Query<PeerQueryParams>,
) -> Result<Json<Vec<PeerStore>>, StatusCode> {
    let peers = state.peers.read().map_err(|_| {
        tracing::error!("Federation peers RwLock poisoned");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let result: Vec<PeerStore> = peers
        .values()
        .filter(|p| {
            if let Some(ref modality) = params.modality {
                p.modalities.iter().any(|m| m == modality)
            } else {
                true
            }
        })
        .cloned()
        .collect();

    Ok(Json(result))
}

/// Register a new peer store in the federation.
///
/// Requires `VERISIM_FEDERATION_KEYS` to be set with the store_id:key pair.
/// Federation registration is disabled (403) when no keys are configured.
#[instrument(skip(state))]
async fn register_peer(
    State(state): State<FederationState>,
    Json(request): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<PeerStore>), StatusCode> {
    // Reject if federation registration is disabled
    if !state.registration_enabled() {
        warn!("Federation registration rejected: VERISIM_FEDERATION_KEYS not configured");
        return Err(StatusCode::FORBIDDEN);
    }

    // Validate store_id format (alphanumeric + dash + underscore, max 128)
    if request.store_id.is_empty()
        || request.store_id.len() > 128
        || !request.store_id.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == '/')
    {
        return Err(StatusCode::BAD_REQUEST);
    }

    // Validate PSK
    let secret = request.secret.as_deref().unwrap_or("");
    if !state.validate_psk(&request.store_id, secret) {
        warn!(store_id = %request.store_id, "Federation registration rejected: invalid PSK");
        return Err(StatusCode::UNAUTHORIZED);
    }

    let secret_hash = Some(sha256_hex(secret));

    let peer = PeerStore {
        store_id: request.store_id.clone(),
        endpoint: request.endpoint,
        modalities: request.modalities,
        trust_level: 1.0,
        last_seen: Some(chrono::Utc::now().to_rfc3339()),
        response_time_ms: None,
        secret_hash,
    };

    info!(store_id = %request.store_id, "Registered peer store");

    state
        .peers
        .write()
        .map_err(|_| {
            error!("Federation peers RwLock poisoned");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .insert(request.store_id, peer.clone());

    Ok((StatusCode::CREATED, Json(peer)))
}

/// Receive a heartbeat from a peer.
///
/// Requires `X-Federation-PSK` header matching the stored peer secret.
#[instrument(skip(state, headers))]
async fn heartbeat(
    State(state): State<FederationState>,
    headers: HeaderMap,
    Json(request): Json<HeartbeatRequest>,
) -> Result<StatusCode, StatusCode> {
    state.validate_peer_header(&request.store_id, &headers)?;

    let mut peers = state.peers.write().map_err(|_| {
        error!("Federation peers RwLock poisoned");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    if let Some(peer) = peers.get_mut(&request.store_id) {
        peer.last_seen = Some(chrono::Utc::now().to_rfc3339());
        Ok(StatusCode::OK)
    } else {
        Ok(StatusCode::NOT_FOUND)
    }
}

/// Remove a peer from the federation.
#[instrument(skip(state))]
async fn deregister_peer(
    State(state): State<FederationState>,
    axum::extract::Path(store_id): axum::extract::Path<String>,
) -> Result<StatusCode, StatusCode> {
    let removed = state
        .peers
        .write()
        .map_err(|_| {
            tracing::error!("Federation peers RwLock poisoned");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .remove(&store_id);

    if removed.is_some() {
        info!(store_id = %store_id, "Deregistered peer store");
        Ok(StatusCode::OK)
    } else {
        Ok(StatusCode::NOT_FOUND)
    }
}

/// Execute a federated query across matching peer stores.
#[instrument(skip(state))]
async fn federation_query(
    State(state): State<FederationState>,
    Json(request): Json<FederationQueryRequest>,
) -> Result<Json<FederationQueryResponse>, StatusCode> {
    let limit = request.limit.unwrap_or(100).min(1000);

    // Collect matching stores and apply drift policy (hold lock briefly)
    let (stores_to_query, stores_excluded) = {
        let peers = state.peers.read().map_err(|_| {
            tracing::error!("Federation peers RwLock poisoned");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

        let matching: Vec<PeerStore> = peers
            .values()
            .filter(|p| pattern_matches(&request.pattern, &p.store_id))
            .filter(|p| {
                request
                    .modalities
                    .iter()
                    .all(|m| p.modalities.iter().any(|pm| pm == m))
            })
            .cloned()
            .collect();

        let mut included = Vec::new();
        let mut excluded = Vec::new();

        for store in matching {
            // Skip self to prevent infinite recursion
            if store.store_id == state.self_store_id {
                continue;
            }

            let include = match request.drift_policy {
                DriftPolicy::Strict => {
                    store.trust_level >= (1.0 - state.strict_drift_threshold)
                }
                DriftPolicy::Repair | DriftPolicy::Tolerate | DriftPolicy::Latest => true,
            };

            if include {
                included.push(store);
            } else {
                info!(
                    store_id = %store.store_id,
                    trust = store.trust_level,
                    "Excluded store due to Strict drift policy"
                );
                excluded.push(store.store_id.clone());
            }
        }

        (included, excluded)
    };
    // RwLock dropped here — safe to make async HTTP calls

    let stores_queried: Vec<String> = stores_to_query
        .iter()
        .map(|s| s.store_id.clone())
        .collect();

    let client = reqwest::Client::new();
    let text_query = request.text_query.clone();
    let vector_query = request.vector_query.clone();
    let drift_policy = request.drift_policy;

    // Fan out parallel queries
    let mut handles = Vec::new();
    for store in stores_to_query {
        let client = client.clone();
        let text_q = text_query.clone();
        let vector_q = vector_query.clone();

        let handle = tokio::spawn(async move {
            let timeout = std::time::Duration::from_secs(10);
            match tokio::time::timeout(
                timeout,
                query_single_peer(&client, &store, text_q.as_deref(), vector_q.as_deref(), limit),
            )
            .await
            {
                Ok(Ok(results)) => results,
                Ok(Err(e)) => {
                    warn!(store_id = %store.store_id, error = %e, "Peer query failed");
                    Vec::new()
                }
                Err(_) => {
                    warn!(store_id = %store.store_id, "Peer query timed out after 10s");
                    Vec::new()
                }
            }
        });
        handles.push(handle);
    }

    // Collect results from all peers
    let mut all_results: Vec<FederationResult> = Vec::new();
    for handle in handles {
        match handle.await {
            Ok(mut results) => all_results.append(&mut results),
            Err(e) => warn!(error = %e, "Peer query task panicked"),
        }
    }

    // Sort by score descending and apply global limit
    all_results.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    all_results.truncate(limit);

    Ok(Json(FederationQueryResponse {
        results: all_results,
        stores_queried,
        stores_excluded,
        drift_policy,
    }))
}

/// Query a single peer store via HTTP.
async fn query_single_peer(
    client: &reqwest::Client,
    store: &PeerStore,
    text_query: Option<&str>,
    vector_query: Option<&[f32]>,
    limit: usize,
) -> Result<Vec<FederationResult>, String> {
    let endpoint = &store.endpoint;
    let store_id = &store.store_id;

    let response_items: Vec<serde_json::Value> = if let Some(q) = text_query {
        // Text search
        let url = format!("{}/search/text", endpoint);
        let resp = client
            .get(&url)
            .query(&[("q", q), ("limit", &limit.to_string())])
            .send()
            .await
            .map_err(|e| format!("HTTP request to {} failed: {}", store_id, e))?;

        if !resp.status().is_success() {
            return Err(format!("Peer {} returned status {}", store_id, resp.status()));
        }

        resp.json()
            .await
            .map_err(|e| format!("Failed to parse response from {}: {}", store_id, e))?
    } else if let Some(vec) = vector_query {
        // Vector search
        let url = format!("{}/search/vector", endpoint);
        let body = serde_json::json!({ "vector": vec, "k": limit });
        let resp = client
            .post(&url)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("HTTP request to {} failed: {}", store_id, e))?;

        if !resp.status().is_success() {
            return Err(format!("Peer {} returned status {}", store_id, resp.status()));
        }

        resp.json()
            .await
            .map_err(|e| format!("Failed to parse response from {}: {}", store_id, e))?
    } else {
        // No specific query — list hexads from the peer's /hexads endpoint
        let url = format!("{}/hexads", endpoint);
        let resp = client
            .get(&url)
            .query(&[("limit", &limit.to_string())])
            .send()
            .await
            .map_err(|e| format!("HTTP request to {} failed: {}", store_id, e))?;

        if !resp.status().is_success() {
            return Err(format!("Peer {} returned status {}", store_id, resp.status()));
        }

        resp.json()
            .await
            .map_err(|e| format!("Failed to parse response from {}: {}", store_id, e))?
    };

    // Map response items to FederationResult
    let results = response_items
        .into_iter()
        .map(|item| FederationResult {
            source_store: store_id.clone(),
            hexad_id: item["id"].as_str().unwrap_or("unknown").to_string(),
            score: item["score"].as_f64().unwrap_or(0.0),
            drifted: false,
            data: item,
        })
        .collect();

    Ok(results)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Match a federation pattern against a store ID.
/// Supports glob-style wildcards: "/universities/*" matches "/universities/oxford".
fn pattern_matches(pattern: &str, store_id: &str) -> bool {
    if pattern == "*" {
        return true;
    }

    if let Some(prefix) = pattern.strip_suffix("/*") {
        store_id.starts_with(prefix)
    } else {
        pattern == store_id
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pattern_matching() {
        assert!(pattern_matches("*", "any-store"));
        assert!(pattern_matches("/universities/*", "/universities/oxford"));
        assert!(pattern_matches("/universities/*", "/universities/cambridge"));
        assert!(!pattern_matches("/universities/*", "/hospitals/nhs"));
        assert!(pattern_matches("store-1", "store-1"));
        assert!(!pattern_matches("store-1", "store-2"));
    }

    #[test]
    fn test_federation_state() {
        let state = FederationState::new("self".to_string(), "http://localhost:8080".to_string());

        let peer = PeerStore {
            store_id: "peer-1".to_string(),
            endpoint: "http://peer-1:8080".to_string(),
            modalities: vec!["graph".to_string(), "vector".to_string()],
            trust_level: 0.95,
            last_seen: None,
            response_time_ms: None,
            secret_hash: None,
        };

        state
            .peers
            .write()
            .unwrap()
            .insert("peer-1".to_string(), peer);

        let peers = state.peers.read().unwrap();
        assert_eq!(peers.len(), 1);
        assert_eq!(peers["peer-1"].trust_level, 0.95);
    }

    #[test]
    fn test_registration_disabled_by_default() {
        let state = FederationState::new("self".to_string(), "http://localhost:8080".to_string());
        // Without VERISIM_FEDERATION_KEYS, registration should be disabled
        assert!(!state.registration_enabled());
    }

    #[test]
    fn test_sha256_hex() {
        let hash = sha256_hex("test-secret");
        assert_eq!(hash.len(), 64); // SHA-256 produces 64 hex chars
    }
}
