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
            },
            "feedback": {
                "type": "feedback",
                "description": "Groove-routed feedback receiver — stores feedback targeted at VeriSimDB",
                "protocol": "http",
                "endpoint": "/.well-known/groove/feedback",
                "requires_auth": false,
                "panel_compatible": false
            },
            "health-mesh": {
                "type": "health-mesh",
                "description": "Inter-service health mesh — monitors peer status via groove probing",
                "protocol": "http",
                "endpoint": "/.well-known/groove/mesh",
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

// --- Health Mesh ---

/// Cached health state of groove peers, updated by the mesh monitor.
#[derive(Debug, Clone, Serialize)]
pub struct PeerHealth {
    /// Peer's self-reported service ID.
    pub service_id: String,
    /// Port the peer was discovered on.
    pub port: u16,
    /// "up", "degraded", or "down".
    pub status: String,
    /// Unix timestamp (milliseconds) of last successful probe.
    pub last_seen_ms: u64,
}

/// Shared mesh state: list of peer health entries.
#[derive(Debug, Clone)]
pub struct MeshState {
    peers: Arc<Mutex<Vec<PeerHealth>>>,
    last_probe_ms: Arc<Mutex<u64>>,
}

impl MeshState {
    /// Create an empty mesh state.
    pub fn new() -> Self {
        Self {
            peers: Arc::new(Mutex::new(Vec::new())),
            last_probe_ms: Arc::new(Mutex::new(0)),
        }
    }
}

impl Default for MeshState {
    fn default() -> Self {
        Self::new()
    }
}

/// Known ports to probe for groove peers (excluding our own port).
const MESH_PROBE_PORTS: &[u16] = &[6473, 8000, 8081, 8091, 8092];

/// Probe all known groove peers and update the mesh state.
///
/// Called periodically by the mesh monitor background task.
fn probe_mesh_peers(mesh: &MeshState) {
    let now_ms = unix_now_ms();
    let mut results = Vec::new();

    for &port in MESH_PROBE_PORTS {
        let addr_str = format!("127.0.0.1:{}", port);
        let addr: std::net::SocketAddr = match addr_str.parse() {
            Ok(a) => a,
            Err(_) => continue,
        };

        match std::net::TcpStream::connect_timeout(&addr, std::time::Duration::from_millis(500)) {
            Ok(mut stream) => {
                use std::io::{Read, Write};
                stream.set_read_timeout(Some(std::time::Duration::from_millis(500))).ok();
                stream.set_write_timeout(Some(std::time::Duration::from_millis(500))).ok();

                let request = format!(
                    "GET /.well-known/groove/status HTTP/1.0\r\nHost: {}\r\nConnection: close\r\n\r\n",
                    addr_str
                );

                if stream.write_all(request.as_bytes()).is_ok() {
                    let mut buf = vec![0u8; 4096];
                    let service_id = match stream.read(&mut buf) {
                        Ok(n) if n > 0 => {
                            let resp = String::from_utf8_lossy(&buf[..n]);
                            extract_service_id(&resp)
                        }
                        _ => "unknown".to_string(),
                    };
                    results.push(PeerHealth {
                        service_id,
                        port,
                        status: "up".to_string(),
                        last_seen_ms: now_ms,
                    });
                }
            }
            Err(_) => {
                // Peer unreachable — don't include in results.
            }
        }
    }

    if let Ok(mut peers) = mesh.peers.lock() {
        *peers = results;
    }
    if let Ok(mut ts) = mesh.last_probe_ms.lock() {
        *ts = now_ms;
    }
}

/// Extract service_id from a groove status HTTP response body.
fn extract_service_id(response: &str) -> String {
    // Find body after headers.
    let body = if let Some(idx) = response.find("\r\n\r\n") {
        &response[idx + 4..]
    } else {
        response
    };

    if let Ok(v) = serde_json::from_str::<serde_json::Value>(body) {
        if let Some(id) = v.get("service").and_then(|s| s.as_str()) {
            return id.to_string();
        }
        if let Some(id) = v.get("service_id").and_then(|s| s.as_str()) {
            return id.to_string();
        }
    }

    "unknown".to_string()
}

/// Spawn the mesh health monitor as a background tokio task.
///
/// Probes peers every 30 seconds. The MeshState is shared with the
/// HTTP handler via Arc.
pub fn spawn_mesh_monitor(mesh: MeshState) {
    tokio::spawn(async move {
        loop {
            // Run probe on a blocking thread to avoid blocking the async runtime.
            let mesh_clone = mesh.clone();
            let _ = tokio::task::spawn_blocking(move || {
                probe_mesh_peers(&mesh_clone);
            })
            .await;

            tokio::time::sleep(std::time::Duration::from_secs(30)).await;
        }
    });
}

/// GET /.well-known/groove/mesh — Return the cached mesh health view.
async fn groove_mesh_handler(State(mesh): State<MeshState>) -> impl IntoResponse {
    let peers = mesh.peers.lock().unwrap_or_else(|e| e.into_inner()).clone();
    let last_probe = *mesh.last_probe_ms.lock().unwrap_or_else(|e| e.into_inner());

    Json(serde_json::json!({
        "service_id": "verisimdb",
        "timestamp_ms": unix_now_ms(),
        "last_probe_ms": last_probe,
        "peer_count": peers.len(),
        "peers": peers,
    }))
}

// --- Feedback ---

/// Shared feedback store: timestamped feedback entries.
#[derive(Debug, Clone)]
pub struct FeedbackStore {
    entries: Arc<Mutex<Vec<FeedbackEntry>>>,
}

/// A single feedback entry received via the Groove mesh.
#[derive(Debug, Clone, Serialize)]
pub struct FeedbackEntry {
    pub id: String,
    pub timestamp_ms: u64,
    pub source_service: String,
    pub target_service: String,
    pub category: String,
    pub message: String,
    pub metadata: serde_json::Value,
}

/// Maximum stored feedback entries.
const MAX_FEEDBACK_ENTRIES: usize = 10_000;

impl FeedbackStore {
    /// Create an empty feedback store.
    pub fn new() -> Self {
        Self {
            entries: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

impl Default for FeedbackStore {
    fn default() -> Self {
        Self::new()
    }
}

/// Body for POST /.well-known/groove/feedback.
#[derive(Debug, Deserialize)]
pub struct FeedbackRequest {
    #[serde(default = "default_feedback_type")]
    pub r#type: String,
    #[serde(default = "default_verisimdb")]
    pub target_service: String,
    #[serde(default = "default_other")]
    pub category: String,
    #[serde(default)]
    pub message: String,
    #[serde(default)]
    pub metadata: serde_json::Value,
    #[serde(default = "default_unknown")]
    pub source_service: String,
}

fn default_feedback_type() -> String { "feedback".to_string() }
fn default_verisimdb() -> String { "verisimdb".to_string() }
fn default_other() -> String { "other".to_string() }
fn default_unknown() -> String { "unknown".to_string() }

/// POST /.well-known/groove/feedback — Receive feedback from the Groove mesh.
async fn groove_feedback_handler(
    State(store): State<FeedbackStore>,
    Json(req): Json<FeedbackRequest>,
) -> impl IntoResponse {
    let valid_categories = ["bug", "feature", "ux", "performance", "other"];
    if !valid_categories.contains(&req.category.as_str()) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "ok": false,
                "error": format!("invalid category: {}", req.category),
            })),
        );
    }

    let now_ms = unix_now_ms();
    let id = format!("groove-feedback-{now_ms}");

    let entry = FeedbackEntry {
        id: id.clone(),
        timestamp_ms: now_ms,
        source_service: req.source_service,
        target_service: req.target_service.clone(),
        category: req.category,
        message: req.message,
        metadata: req.metadata,
    };

    {
        let mut entries = store.entries.lock().expect("feedback lock poisoned");
        entries.push(entry);
        if entries.len() > MAX_FEEDBACK_ENTRIES {
            entries.remove(0);
        }
    }

    info!(id = %id, "Groove feedback accepted");

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "routed_to": req.target_service,
            "id": id,
        })),
    )
}

/// GET /.well-known/groove/feedback — List stored feedback entries.
async fn groove_feedback_list_handler(
    State(store): State<FeedbackStore>,
) -> impl IntoResponse {
    let entries = store.entries.lock().unwrap_or_else(|e| e.into_inner()).clone();
    Json(serde_json::json!({
        "count": entries.len(),
        "entries": entries,
    }))
}

/// Build the groove sub-router.
///
/// Mounted at `/.well-known/groove` in the main application router.
/// Uses its own `GrooveState` (not `AppState`) to keep the connection
/// tracker lightweight and independent of the database layer.
///
/// Includes health mesh monitoring and feedback-o-tron endpoints.
pub fn groove_router() -> Router {
    let groove_state = GrooveState::new();
    let mesh_state = MeshState::new();
    let feedback_store = FeedbackStore::new();

    // Spawn the background mesh monitor task.
    spawn_mesh_monitor(mesh_state.clone());

    // Connection lifecycle sub-router (uses GrooveState).
    let connection_router = Router::new()
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
        .with_state(groove_state);

    // Health mesh sub-router (uses MeshState).
    let mesh_router = Router::new()
        .route(
            "/.well-known/groove/mesh",
            get(groove_mesh_handler),
        )
        .with_state(mesh_state);

    // Feedback sub-router (uses FeedbackStore).
    let feedback_router = Router::new()
        .route(
            "/.well-known/groove/feedback",
            get(groove_feedback_list_handler).post(groove_feedback_handler),
        )
        .with_state(feedback_store);

    connection_router
        .merge(mesh_router)
        .merge(feedback_router)
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
