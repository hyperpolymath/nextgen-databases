// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
//! Groove Protocol connection lifecycle for VeriSimDB.
//!
//! Implements the connect/disconnect lifecycle from the Groove Protocol spec
//! (section 4). Allows groove-aware systems (Gossamer, Burble, PanLL, etc.)
//! to establish typed connections with VeriSimDB for octad storage, drift
//! detection, and provenance services.
//!
//! Endpoints:
//!   GET  /.well-known/groove            — Capability manifest
//!   POST /.well-known/groove/connect    — Establish connection (spec 4.2)
//!   POST /.well-known/groove/disconnect — Tear down connection (spec 4.5)
//!   GET  /.well-known/groove/heartbeat  — Heartbeat keepalive (spec 4.3)
//!   GET  /.well-known/groove/status     — Current connection states
//!
//! Connection state machine:
//!   DISCOVERED -> NEGOTIATING -> CONNECTED -> ACTIVE -> DISCONNECTING -> DISCONNECTED
//!                    |                          |
//!                 REJECTED                   DEGRADED -> RECONNECTING -> ACTIVE

use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tracing::{info, warn};

/// Groove connection state, mirroring the spec state machine.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionState {
    /// Peer discovered but not yet negotiated.
    Discovered,
    /// Capability negotiation in progress.
    Negotiating,
    /// Connection established, capabilities available.
    Connected,
    /// Active data exchange (heartbeats received).
    Active,
    /// Heartbeats missed, capabilities may be unreliable.
    Degraded,
    /// Attempting to re-establish after degradation.
    Reconnecting,
    /// Graceful shutdown in progress.
    Disconnecting,
    /// Connection closed.
    Disconnected,
    /// Peer rejected (incompatible capabilities or security).
    Rejected,
}

/// Information about a single groove connection.
#[derive(Debug, Clone, Serialize)]
pub struct ConnectionInfo {
    /// Peer's self-reported service ID.
    pub peer_id: String,
    /// Current lifecycle state.
    pub state: ConnectionState,
    /// Unix timestamp (milliseconds) when the connection was established.
    pub connected_at_ms: u64,
    /// Unix timestamp (milliseconds) of the last heartbeat.
    pub last_heartbeat_ms: u64,
    /// Monotonic instant of last heartbeat (not serialised, used for timeout).
    #[serde(skip)]
    pub last_heartbeat_instant: Instant,
    /// Capabilities that matched between provider and consumer.
    pub matched_capabilities: Vec<String>,
}

/// Shared state for all groove connections.
#[derive(Debug, Clone)]
pub struct GrooveState {
    /// Active connections keyed by session ID.
    connections: Arc<Mutex<HashMap<String, ConnectionInfo>>>,
}

impl GrooveState {
    /// Create a new empty groove state.
    pub fn new() -> Self {
        Self {
            connections: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

impl Default for GrooveState {
    fn default() -> Self {
        Self::new()
    }
}

/// Static capability manifest for VeriSimDB.
///
/// Declares what VeriSimDB offers to groove consumers (octad storage, drift
/// detection, provenance, spatial search, etc.) and what it consumes from
/// groove partners (integrity verification, scanning).
fn manifest() -> serde_json::Value {
    serde_json::json!({
        "groove_version": "1",
        "service_id": "verisimdb",
        "service_version": env!("CARGO_PKG_VERSION"),
        "capabilities": {
            "octad-storage": {
                "type": "octad-storage",
                "description": "8-modality entity storage with drift detection and self-normalisation",
                "protocol": "http",
                "endpoint": "/api/v1/octads",
                "requires_auth": false,
                "panel_compatible": true
            },
            "drift-detection": {
                "type": "drift-detection",
                "description": "Cross-modal drift measurement and alerting",
                "protocol": "http",
                "endpoint": "/api/v1/drift/status",
                "requires_auth": false,
                "panel_compatible": true
            },
            "provenance": {
                "type": "provenance",
                "description": "Hash-chain provenance tracking for entity lineage",
                "protocol": "http",
                "endpoint": "/api/v1/provenance",
                "requires_auth": false,
                "panel_compatible": true
            },
            "vector-search": {
                "type": "vector-search",
                "description": "HNSW similarity search over entity embeddings",
                "protocol": "http",
                "endpoint": "/api/v1/search/vector",
                "requires_auth": false,
                "panel_compatible": false
            },
            "spatial-search": {
                "type": "spatial-search",
                "description": "R-tree geospatial queries (radius, bounds, nearest)",
                "protocol": "http",
                "endpoint": "/api/v1/spatial/search",
                "requires_auth": false,
                "panel_compatible": false
            },
            "vql": {
                "type": "vql",
                "description": "VeriSim Query Language — type-safe multi-modal queries",
                "protocol": "http",
                "endpoint": "/api/v1/vql/execute",
                "requires_auth": false,
                "panel_compatible": true
            }
        },
        "consumes": ["integrity", "scanning"],
        "endpoints": {
            "api": "http://localhost:8080/api/v1",
            "health": "http://localhost:8080/health",
            "graphql": "http://localhost:8080/graphql"
        },
        "health": "/health",
        "heartbeat": {
            "interval_ms": 5000,
            "timeout_ms": 15000
        }
    })
}

/// Our offered capability IDs (for matching against consumer "consumes" list).
const OFFERED_CAPABILITIES: &[&str] = &[
    "octad-storage",
    "drift-detection",
    "provenance",
    "vector-search",
    "spatial-search",
    "vql",
];

/// Heartbeat timeout: 15 seconds (3 missed heartbeats at 5s interval, per spec 4.3).
const HEARTBEAT_TIMEOUT_MS: u64 = 15_000;

// --- Request/Response types ---

/// Body for POST /.well-known/groove/connect
#[derive(Debug, Deserialize)]
pub struct ConnectRequest {
    /// The peer's service ID.
    pub service_id: Option<String>,
    /// The peer's service version.
    pub service_version: Option<String>,
    /// Capabilities the peer consumes (we check if we offer them).
    pub consumes: Option<Vec<String>>,
    /// Full peer manifest (opaque, stored for reference).
    #[serde(flatten)]
    pub extra: HashMap<String, serde_json::Value>,
}

/// Response for POST /.well-known/groove/connect
#[derive(Debug, Serialize)]
pub struct ConnectResponse {
    pub ok: bool,
    pub session_id: Option<String>,
    pub provider: &'static str,
    pub state: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub matched_capabilities: Option<Vec<String>>,
}

/// Body for POST /.well-known/groove/disconnect
#[derive(Debug, Deserialize)]
pub struct DisconnectRequest {
    pub session_id: String,
}

/// Query params for GET /.well-known/groove/heartbeat
#[derive(Debug, Deserialize)]
pub struct HeartbeatQuery {
    pub session_id: String,
}

// --- Handlers ---

/// GET /.well-known/groove — Return the capability manifest.
async fn groove_manifest_handler() -> impl IntoResponse {
    Json(manifest())
}

/// POST /.well-known/groove/connect — Establish a groove connection.
///
/// The consumer sends its manifest. VeriSimDB checks structural compatibility
/// (does the consumer consume something we offer?) and returns a session ID
/// if compatible. Per spec section 4.2.
async fn groove_connect_handler(
    State(groove): State<GrooveState>,
    Json(req): Json<ConnectRequest>,
) -> impl IntoResponse {
    let peer_id = req.service_id.unwrap_or_else(|| "unknown".to_string());
    let peer_consumes = req.consumes.unwrap_or_default();

    // Structural compatibility check: does the peer consume anything we offer?
    let matched: Vec<String> = peer_consumes
        .iter()
        .filter(|cap| OFFERED_CAPABILITIES.contains(&cap.as_str()))
        .cloned()
        .collect();

    if matched.is_empty() && !peer_consumes.is_empty() {
        info!(
            peer_id = %peer_id,
            "Groove connection rejected: no capability match"
        );
        return (
            StatusCode::CONFLICT,
            Json(ConnectResponse {
                ok: false,
                session_id: None,
                provider: "verisimdb",
                state: "rejected",
                error: Some("no matching capabilities".to_string()),
                matched_capabilities: None,
            }),
        );
    }

    let session_id = generate_session_id();
    let now_ms = unix_now_ms();

    let conn_info = ConnectionInfo {
        peer_id: peer_id.clone(),
        state: ConnectionState::Connected,
        connected_at_ms: now_ms,
        last_heartbeat_ms: now_ms,
        last_heartbeat_instant: Instant::now(),
        matched_capabilities: matched.clone(),
    };

    {
        let mut connections = groove.connections.lock().expect("groove lock poisoned");
        connections.insert(session_id.clone(), conn_info);
    }

    info!(
        peer_id = %peer_id,
        session_id = %session_id,
        capabilities = ?matched,
        "Groove connection established"
    );

    (
        StatusCode::OK,
        Json(ConnectResponse {
            ok: true,
            session_id: Some(session_id),
            provider: "verisimdb",
            state: "connected",
            error: None,
            matched_capabilities: Some(matched),
        }),
    )
}

/// POST /.well-known/groove/disconnect — Tear down a groove connection.
///
/// Consumes the linear connection handle. Per spec section 4.5.
async fn groove_disconnect_handler(
    State(groove): State<GrooveState>,
    Json(req): Json<DisconnectRequest>,
) -> impl IntoResponse {
    let mut connections = groove.connections.lock().expect("groove lock poisoned");

    match connections.remove(&req.session_id) {
        Some(info) => {
            info!(
                peer_id = %info.peer_id,
                session_id = %req.session_id,
                "Groove connection disconnected"
            );
            (
                StatusCode::OK,
                Json(serde_json::json!({"ok": true, "state": "disconnected"})),
            )
        }
        None => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"ok": false, "error": "session not found"})),
        ),
    }
}

/// GET /.well-known/groove/heartbeat — Heartbeat from connected peer.
///
/// Per spec section 4.3. Returns 204 No Content on success.
async fn groove_heartbeat_handler(
    State(groove): State<GrooveState>,
    Query(params): Query<HeartbeatQuery>,
) -> impl IntoResponse {
    let mut connections = groove.connections.lock().expect("groove lock poisoned");

    match connections.get_mut(&params.session_id) {
        Some(info) => {
            info.last_heartbeat_ms = unix_now_ms();
            info.last_heartbeat_instant = Instant::now();
            // Promote from connected/degraded to active on heartbeat.
            if info.state == ConnectionState::Connected || info.state == ConnectionState::Degraded {
                info.state = ConnectionState::Active;
            }
            StatusCode::NO_CONTENT.into_response()
        }
        None => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"ok": false, "error": "session not found"})),
        )
            .into_response(),
    }
}

/// GET /.well-known/groove/status — Current connection state for all peers.
///
/// Also performs heartbeat timeout checks: connections that have not sent a
/// heartbeat within 15 seconds are transitioned to DEGRADED; connections
/// already DEGRADED that miss another timeout are removed.
async fn groove_status_handler(State(groove): State<GrooveState>) -> impl IntoResponse {
    let mut connections = groove.connections.lock().expect("groove lock poisoned");
    let now = Instant::now();

    // Check heartbeat timeouts and update states.
    let mut to_remove = Vec::new();
    for (session_id, info) in connections.iter_mut() {
        let elapsed_ms = now.duration_since(info.last_heartbeat_instant).as_millis() as u64;

        if elapsed_ms > HEARTBEAT_TIMEOUT_MS {
            if info.state == ConnectionState::Degraded {
                // Already degraded and still no heartbeat — remove.
                warn!(
                    peer_id = %info.peer_id,
                    session_id = %session_id,
                    "Groove peer timed out, removing"
                );
                to_remove.push(session_id.clone());
            } else if info.state == ConnectionState::Active
                || info.state == ConnectionState::Connected
            {
                // Transition to degraded.
                warn!(
                    peer_id = %info.peer_id,
                    session_id = %session_id,
                    elapsed_ms = elapsed_ms,
                    "Groove peer degraded (no heartbeat)"
                );
                info.state = ConnectionState::Degraded;
            }
        }
    }

    for session_id in &to_remove {
        connections.remove(session_id);
    }

    // Build response.
    let status: HashMap<&String, _> = connections
        .iter()
        .map(|(id, info)| {
            (
                id,
                serde_json::json!({
                    "peer_id": info.peer_id,
                    "state": info.state,
                    "connected_at_ms": info.connected_at_ms,
                    "last_heartbeat_ms": info.last_heartbeat_ms,
                    "matched_capabilities": info.matched_capabilities,
                }),
            )
        })
        .collect();

    Json(serde_json::json!({
        "service_id": "verisimdb",
        "active_connections": connections.len(),
        "connections": status,
    }))
}

/// Build the groove sub-router.
///
/// Mounted at `/.well-known/groove` in the main application router.
/// Uses its own `GrooveState` (not `AppState`) to keep the connection
/// tracker lightweight and independent of the database layer.
pub fn groove_router() -> Router {
    let groove_state = GrooveState::new();

    Router::new()
        .route(
            "/.well-known/groove",
            get(groove_manifest_handler),
        )
        .route(
            "/.well-known/groove/connect",
            post(groove_connect_handler),
        )
        .route(
            "/.well-known/groove/disconnect",
            post(groove_disconnect_handler),
        )
        .route(
            "/.well-known/groove/heartbeat",
            get(groove_heartbeat_handler),
        )
        .route(
            "/.well-known/groove/status",
            get(groove_status_handler),
        )
        .with_state(groove_state)
}

// --- Helpers ---

/// Generate a random hex session ID (32 hex characters = 16 bytes).
fn generate_session_id() -> String {
    use std::fmt::Write;
    let mut bytes = [0u8; 16];
    // Use getrandom via std (available since Rust 1.36+, backed by OS entropy).
    // Fallback: timestamp + counter if getrandom is somehow unavailable.
    #[cfg(unix)]
    {
        use std::io::Read;
        if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
            let _ = f.read_exact(&mut bytes);
        }
    }
    #[cfg(not(unix))]
    {
        // Fallback: use system time as entropy source (not cryptographically strong,
        // but groove session IDs are not security-critical).
        let t = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        bytes[..8].copy_from_slice(&t.to_le_bytes()[..8]);
        bytes[8..].copy_from_slice(&(t.wrapping_mul(6364136223846793005)).to_le_bytes()[..8]);
    }

    let mut s = String::with_capacity(32);
    for b in &bytes {
        let _ = write!(s, "{:02x}", b);
    }
    s
}

/// Current Unix time in milliseconds.
fn unix_now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manifest_has_required_fields() {
        let m = manifest();
        assert_eq!(m["service_id"], "verisimdb");
        assert_eq!(m["groove_version"], "1");
        assert!(m["capabilities"]["octad-storage"].is_object());
        assert!(m["capabilities"]["drift-detection"].is_object());
        assert!(m["capabilities"]["provenance"].is_object());
    }

    #[test]
    fn test_session_id_generation() {
        let id1 = generate_session_id();
        let id2 = generate_session_id();
        assert_eq!(id1.len(), 32);
        assert_eq!(id2.len(), 32);
        // Should be different (probabilistically).
        assert_ne!(id1, id2);
    }

    #[test]
    fn test_groove_state_connect_disconnect() {
        let state = GrooveState::new();
        let session_id = "test-session-123".to_string();
        let now_ms = unix_now_ms();

        // Insert a connection.
        {
            let mut conns = state.connections.lock().unwrap();
            conns.insert(
                session_id.clone(),
                ConnectionInfo {
                    peer_id: "burble".to_string(),
                    state: ConnectionState::Connected,
                    connected_at_ms: now_ms,
                    last_heartbeat_ms: now_ms,
                    last_heartbeat_instant: Instant::now(),
                    matched_capabilities: vec!["octad-storage".to_string()],
                },
            );
            assert_eq!(conns.len(), 1);
        }

        // Remove it.
        {
            let mut conns = state.connections.lock().unwrap();
            let removed = conns.remove(&session_id);
            assert!(removed.is_some());
            assert_eq!(conns.len(), 0);
        }
    }

    #[test]
    fn test_capability_matching() {
        let peer_consumes = vec![
            "octad-storage".to_string(),
            "unknown-cap".to_string(),
        ];

        let matched: Vec<String> = peer_consumes
            .iter()
            .filter(|cap| OFFERED_CAPABILITIES.contains(&cap.as_str()))
            .cloned()
            .collect();

        assert_eq!(matched, vec!["octad-storage".to_string()]);
    }
}
