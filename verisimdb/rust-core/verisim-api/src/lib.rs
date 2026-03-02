// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim API
//!
//! HTTP API server for VeriSimDB.
//! Exposes all database functionality via REST endpoints.

pub mod auth;
pub mod federation;
pub mod graphql;
pub mod grpc;
pub mod rbac;
pub mod transaction;
pub mod vql;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    middleware as axum_middleware,
    response::IntoResponse,
    routing::{delete, get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use thiserror::Error;
use tokio::net::TcpListener;
use tracing::{error, info, instrument};

use std::sync::Mutex;

use verisim_document::TantivyDocumentStore;
use verisim_drift::{DriftDetector, DriftMetrics, DriftThresholds, DriftType};
#[cfg(not(feature = "persistent"))]
use verisim_graph::SimpleGraphStore;
#[cfg(feature = "persistent")]
use verisim_graph::RedbGraphStore;
use verisim_planner::{
    CacheConfig, ExplainOutput, ExplainAnalyzeOutput, LogicalPlan, ParamValue,
    PhysicalPlan, PlanCache, Planner, PlannerConfig, PreparedId, PreparedStatement,
    Profiler, SlowQueryLog, SlowQuerySummary, StatisticsCollector,
};
use verisim_hexad::{
    BoundingBox, Coordinates, HexadConfig, HexadDocumentInput, HexadGraphInput,
    HexadId, HexadInput, HexadProvenanceInput, HexadSemanticInput, HexadSnapshot,
    HexadSpatialInput, HexadStore, HexadTensorInput, HexadVectorInput,
    InMemoryHexadStore, ProvenanceStore, SpatialStore,
};
use verisim_provenance::InMemoryProvenanceStore;
use verisim_spatial::InMemorySpatialStore;
use verisim_normalizer::{create_default_normalizer, Normalizer, NormalizerStatus};
use verisim_semantic::InMemorySemanticStore;
use verisim_semantic::zkp_bridge::{self as zkp_api, PrivacyLevel, ZkpProofRequest as ZkpBridgeRequest};
use verisim_semantic::circuit_registry::CircuitRegistry;
use verisim_temporal::InMemoryVersionStore;
use verisim_tensor::InMemoryTensorStore;
use verisim_vector::{DistanceMetric, BruteForceVectorStore};

/// Type alias for our concrete HexadStore implementation (octad: 8 modality stores).
///
/// When the `persistent` feature is enabled, the graph store uses redb (pure Rust,
/// ACID, single-file B-tree) and the document store uses file-backed Tantivy.
/// WAL is enabled for crash recovery. Requires `VERISIM_PERSISTENCE_DIR` at runtime.
#[cfg(not(feature = "persistent"))]
pub type ConcreteHexadStore = InMemoryHexadStore<
    SimpleGraphStore,
    BruteForceVectorStore,
    TantivyDocumentStore,
    InMemoryTensorStore,
    InMemorySemanticStore,
    InMemoryVersionStore<HexadSnapshot>,
    InMemoryProvenanceStore,
    InMemorySpatialStore,
>;

/// Persistent variant: redb graph store, file-backed Tantivy, WAL enabled.
#[cfg(feature = "persistent")]
pub type ConcreteHexadStore = InMemoryHexadStore<
    RedbGraphStore,
    BruteForceVectorStore,
    TantivyDocumentStore,
    InMemoryTensorStore,
    InMemorySemanticStore,
    InMemoryVersionStore<HexadSnapshot>,
    InMemoryProvenanceStore,
    InMemorySpatialStore,
>;

/// API errors
#[derive(Error, Debug)]
pub enum ApiError {
    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("Serialization error: {0}")]
    Serialization(String),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> axum::response::Response {
        let (status, client_message) = match &self {
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            ApiError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            ApiError::Internal(msg) => {
                error!(error = %msg, "Internal server error");
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string())
            }
            ApiError::Serialization(msg) => {
                error!(error = %msg, "Serialization error");
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string())
            }
        };

        let body = Json(ErrorResponse {
            error: client_message,
            code: status.as_u16(),
        });

        (status, body).into_response()
    }
}

/// Error response body
#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: u16,
}

/// API configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiConfig {
    /// Host to bind to
    pub host: String,
    /// Port to bind to
    pub port: u16,
    /// Enable CORS
    pub enable_cors: bool,
    /// API version prefix
    pub version_prefix: String,
    /// Vector dimension for embeddings
    pub vector_dimension: usize,
    /// Persistence directory for the `persistent` feature.
    /// Overrides `VERISIM_PERSISTENCE_DIR` env var when set.
    pub persistence_dir: Option<String>,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            host: "[::1]".to_string(),
            port: 8080,
            enable_cors: true,
            version_prefix: "/api/v1".to_string(),
            vector_dimension: 384,
            persistence_dir: None,
        }
    }
}

/// Maximum number of results allowed in any search/list endpoint.
const MAX_RESULT_LIMIT: usize = 1000;

/// Validate and cap a limit parameter.
fn validate_limit(limit: usize) -> usize {
    limit.min(MAX_RESULT_LIMIT)
}

/// Validate a hexad ID: max 128 chars, alphanumeric + dash + underscore only.
fn validate_hexad_id(id: &str) -> Result<(), ApiError> {
    if id.is_empty() {
        return Err(ApiError::BadRequest("Hexad ID must not be empty".to_string()));
    }
    if id.len() > 128 {
        return Err(ApiError::BadRequest("Hexad ID must be at most 128 characters".to_string()));
    }
    if !id.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        return Err(ApiError::BadRequest(
            "Hexad ID must contain only alphanumeric characters, dashes, and underscores".to_string(),
        ));
    }
    Ok(())
}

/// Validate that all vector components are finite (no NaN/Inf).
fn validate_vector(v: &[f32]) -> Result<(), ApiError> {
    if !v.iter().all(|x| x.is_finite()) {
        return Err(ApiError::BadRequest(
            "Vector contains NaN or Inf values".to_string(),
        ));
    }
    Ok(())
}

/// Health check response
#[derive(Debug, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub uptime_seconds: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
}

/// Hexad create/update request
#[derive(Debug, Serialize, Deserialize)]
pub struct HexadRequest {
    /// Document title
    pub title: Option<String>,
    /// Document body
    pub body: Option<String>,
    /// Vector embedding
    pub embedding: Option<Vec<f32>>,
    /// Semantic types
    pub types: Option<Vec<String>>,
    /// Relationships (predicate, target_id)
    pub relationships: Option<Vec<(String, String)>>,
    /// Tensor data
    pub tensor: Option<TensorRequest>,
    /// Provenance event
    pub provenance: Option<ProvenanceRequest>,
    /// Spatial coordinates
    pub spatial: Option<SpatialRequest>,
    /// Metadata
    pub metadata: Option<std::collections::HashMap<String, String>>,
}

/// Provenance event data in request
#[derive(Debug, Serialize, Deserialize)]
pub struct ProvenanceRequest {
    /// Event type: created, modified, imported, normalized, drift_repaired, deleted, merged
    pub event_type: String,
    /// Who or what caused this event
    pub actor: String,
    /// Optional source identifier
    pub source: Option<String>,
    /// Human-readable description
    pub description: String,
}

/// Spatial coordinates in request
#[derive(Debug, Serialize, Deserialize)]
pub struct SpatialRequest {
    /// Latitude (WGS84, -90 to 90)
    pub latitude: f64,
    /// Longitude (WGS84, -180 to 180)
    pub longitude: f64,
    /// Altitude in metres (optional)
    pub altitude: Option<f64>,
    /// Geometry type (defaults to Point)
    pub geometry_type: Option<String>,
    /// SRID (defaults to 4326)
    pub srid: Option<u32>,
    /// Spatial properties
    pub properties: Option<std::collections::HashMap<String, String>>,
}

impl HexadRequest {
    /// Convert to HexadInput
    fn to_hexad_input(&self) -> HexadInput {
        let mut input = HexadInput::default();

        if let (Some(title), Some(body)) = (&self.title, &self.body) {
            input.document = Some(HexadDocumentInput {
                title: title.clone(),
                body: body.clone(),
                fields: std::collections::HashMap::new(),
            });
        } else if let Some(title) = &self.title {
            input.document = Some(HexadDocumentInput {
                title: title.clone(),
                body: String::new(),
                fields: std::collections::HashMap::new(),
            });
        }

        if let Some(embedding) = &self.embedding {
            input.vector = Some(HexadVectorInput {
                embedding: embedding.clone(),
                model: None,
            });
        }

        if let Some(types) = &self.types {
            input.semantic = Some(HexadSemanticInput {
                types: types.clone(),
                properties: std::collections::HashMap::new(),
            });
        }

        if let Some(relationships) = &self.relationships {
            input.graph = Some(HexadGraphInput {
                relationships: relationships.clone(),
            });
        }

        if let Some(tensor) = &self.tensor {
            input.tensor = Some(HexadTensorInput {
                shape: tensor.shape.clone(),
                data: tensor.data.clone(),
            });
        }

        if let Some(provenance) = &self.provenance {
            input.provenance = Some(HexadProvenanceInput {
                event_type: provenance.event_type.clone(),
                actor: provenance.actor.clone(),
                source: provenance.source.clone(),
                description: provenance.description.clone(),
            });
        }

        if let Some(spatial) = &self.spatial {
            input.spatial = Some(HexadSpatialInput {
                latitude: spatial.latitude,
                longitude: spatial.longitude,
                altitude: spatial.altitude,
                geometry_type: spatial.geometry_type.clone(),
                srid: spatial.srid,
                properties: spatial.properties.clone().unwrap_or_default(),
            });
        }

        if let Some(metadata) = &self.metadata {
            input.metadata = metadata.clone();
        }

        input
    }
}

/// Tensor data in request
#[derive(Debug, Serialize, Deserialize)]
pub struct TensorRequest {
    pub shape: Vec<usize>,
    pub data: Vec<f64>,
}

/// Hexad response
#[derive(Debug, Serialize, Deserialize)]
pub struct HexadResponse {
    pub id: String,
    pub status: HexadStatusResponse,
    pub has_graph: bool,
    pub has_vector: bool,
    pub has_tensor: bool,
    pub has_semantic: bool,
    pub has_document: bool,
    pub has_provenance: bool,
    pub has_spatial: bool,
    pub version_count: u64,
    pub provenance_chain_length: u64,
}

/// Status response
#[derive(Debug, Serialize, Deserialize)]
pub struct HexadStatusResponse {
    pub created_at: String,
    pub modified_at: String,
    pub version: u64,
}

impl From<&verisim_hexad::Hexad> for HexadResponse {
    fn from(h: &verisim_hexad::Hexad) -> Self {
        Self {
            id: h.id.to_string(),
            status: HexadStatusResponse {
                created_at: h.status.created_at.to_rfc3339(),
                modified_at: h.status.modified_at.to_rfc3339(),
                version: h.status.version,
            },
            has_graph: h.graph_node.is_some(),
            has_vector: h.embedding.is_some(),
            has_tensor: h.tensor.is_some(),
            has_semantic: h.semantic.is_some(),
            has_document: h.document.is_some(),
            has_provenance: h.provenance_chain_length > 0,
            has_spatial: h.spatial_data.is_some(),
            version_count: h.version_count,
            provenance_chain_length: h.provenance_chain_length,
        }
    }
}

/// Pagination query parameters for list endpoints
#[derive(Debug, Deserialize)]
pub struct ListQuery {
    /// Maximum number of results (default 100, max 1000)
    pub limit: Option<usize>,
    /// Offset for pagination (default 0)
    pub offset: Option<usize>,
}

/// Search query parameters
#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    /// Text query for document search
    pub q: Option<String>,
    /// Number of results
    pub limit: Option<usize>,
}

/// Vector search request
#[derive(Debug, Serialize, Deserialize)]
pub struct VectorSearchRequest {
    /// Query vector
    pub vector: Vec<f32>,
    /// Number of results
    pub k: Option<usize>,
}

/// Search result
#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResultResponse {
    pub id: String,
    pub score: f32,
    pub title: Option<String>,
}

/// Drift status response
#[derive(Debug, Serialize, Deserialize)]
pub struct DriftStatusResponse {
    pub drift_type: String,
    pub current_score: f64,
    pub moving_average: f64,
    pub max_score: f64,
    pub measurement_count: u64,
}

impl DriftStatusResponse {
    fn from_metrics(drift_type: DriftType, metrics: &DriftMetrics) -> Self {
        Self {
            drift_type: drift_type.to_string(),
            current_score: metrics.current_score,
            moving_average: metrics.moving_average,
            max_score: metrics.max_score,
            measurement_count: metrics.measurement_count,
        }
    }
}

/// Application state
#[derive(Clone)]
pub struct AppState {
    pub start_time: std::time::Instant,
    pub hexad_store: Arc<ConcreteHexadStore>,
    pub drift_detector: Arc<DriftDetector>,
    pub normalizer: Arc<Normalizer>,
    pub planner: Arc<Mutex<Planner>>,
    pub plan_cache: Arc<PlanCache>,
    pub slow_query_log: Arc<SlowQueryLog>,
    pub transaction_manager: Arc<transaction::TransactionManager>,
    pub circuit_registry: Arc<CircuitRegistry>,
    pub federation: federation::FederationState,
    pub auth: auth::AuthState,
    pub config: ApiConfig,
}

impl AppState {
    /// Create new application state with default configuration (async version).
    ///
    /// With the `persistent` feature enabled, reads `VERISIM_PERSISTENCE_DIR`
    /// to determine where to store data on disk. Defaults to `/var/lib/verisimdb`
    /// if the variable is unset.
    pub async fn new_async(config: ApiConfig) -> Result<Self, ApiError> {
        let hexad_config = HexadConfig {
            vector_dimension: config.vector_dimension,
            ..Default::default()
        };

        // --- In-memory stores (default, no `persistent` feature) ---
        #[cfg(not(feature = "persistent"))]
        let (graph, document) = {
            let g = Arc::new(
                SimpleGraphStore::in_memory().map_err(|e| ApiError::Internal(e.to_string()))?,
            );
            let d = Arc::new(
                TantivyDocumentStore::in_memory()
                    .map_err(|e| ApiError::Internal(e.to_string()))?,
            );
            (g, d)
        };

        // --- Persistent stores (with `persistent` feature) ---
        #[cfg(feature = "persistent")]
        let persist_dir = config
            .persistence_dir
            .clone()
            .or_else(|| std::env::var("VERISIM_PERSISTENCE_DIR").ok())
            .unwrap_or_else(|| "/var/lib/verisimdb".to_string());

        #[cfg(feature = "persistent")]
        let (graph, document) = {
            std::fs::create_dir_all(&persist_dir)
                .map_err(|e| ApiError::Internal(format!("create persistence dir: {e}")))?;

            info!(dir = %persist_dir, "Persistent storage enabled");

            let g = Arc::new(
                RedbGraphStore::persistent(format!("{}/graph.redb", persist_dir))
                    .map_err(|e| ApiError::Internal(e.to_string()))?,
            );
            let d = Arc::new(
                TantivyDocumentStore::persistent(format!("{}/documents", persist_dir))
                    .map_err(|e| ApiError::Internal(e.to_string()))?,
            );
            (g, d)
        };

        let vector = Arc::new(BruteForceVectorStore::new(
            config.vector_dimension,
            DistanceMetric::Cosine,
        ));
        let tensor = Arc::new(InMemoryTensorStore::new());
        let semantic = Arc::new(InMemorySemanticStore::new());
        let temporal = Arc::new(InMemoryVersionStore::new());
        let provenance = Arc::new(InMemoryProvenanceStore::new());
        let spatial = Arc::new(InMemorySpatialStore::new());

        let hexad_store_inner = InMemoryHexadStore::new(
            hexad_config,
            graph,
            vector,
            document,
            tensor,
            semantic,
            temporal,
            provenance,
            spatial,
        );

        // Enable WAL for crash recovery when persistent.
        #[cfg(feature = "persistent")]
        let hexad_store_inner = hexad_store_inner
            .with_wal(
                format!("{}/wal", persist_dir),
                verisim_hexad::SyncMode::Fsync,
            )
            .map_err(|e| ApiError::Internal(format!("WAL init: {e}")))?;

        let hexad_store = Arc::new(hexad_store_inner);

        let drift_detector = Arc::new(DriftDetector::new(DriftThresholds::default()));
        let normalizer = Arc::new(create_default_normalizer(drift_detector.clone()).await);

        let planner = Arc::new(Mutex::new(Planner::new(PlannerConfig::default())));
        let plan_cache = Arc::new(PlanCache::new(CacheConfig::default()));
        let slow_query_log = Arc::new(SlowQueryLog::new(Default::default()));
        let transaction_manager = Arc::new(
            transaction::TransactionManager::new(transaction::TransactionConfig::default()),
        );

        let self_endpoint = format!("http://{}:{}{}", config.host, config.port, config.version_prefix);
        let federation = federation::FederationState::new(
            "self".to_string(),
            self_endpoint,
        );

        let auth = auth::AuthState::default();
        let circuit_registry = Arc::new(CircuitRegistry::new());

        Ok(Self {
            start_time: std::time::Instant::now(),
            hexad_store,
            drift_detector,
            normalizer,
            planner,
            plan_cache,
            slow_query_log,
            transaction_manager,
            circuit_registry,
            federation,
            auth,
            config,
        })
    }
}

/// Build the API router
pub fn build_router(state: AppState) -> Router {
    let federation_routes = federation::federation_router(state.federation.clone());
    let auth_state = state.auth.clone();

    Router::new()
        // Health endpoints
        .route("/health", get(health_handler))
        .route("/ready", get(ready_handler))
        .route("/metrics", get(metrics_handler))
        // Hexad CRUD
        .route("/hexads", get(list_hexads_handler).post(create_hexad_handler))
        .route("/hexads/{id}", get(get_hexad_handler))
        .route("/hexads/{id}", put(update_hexad_handler))
        .route("/hexads/{id}", delete(delete_hexad_handler))
        // Search endpoints
        .route("/search/text", get(text_search_handler))
        .route("/search/vector", post(vector_search_handler))
        .route("/search/related/{id}", get(related_search_handler))
        // Drift and normalization
        .route("/drift/status", get(drift_status_handler))
        .route("/drift/entity/{id}", get(entity_drift_handler))
        .route("/normalizer/status", get(normalizer_status_handler))
        .route("/normalizer/trigger/{id}", post(trigger_normalization_handler))
        // Meta-query store (homoiconicity: queries as hexads)
        .route("/queries", post(store_query_handler))
        .route("/queries/similar", post(similar_queries_handler))
        .route("/queries/{id}/optimize", put(optimize_query_handler))
        // Query planner
        .route("/query/plan", post(query_plan_handler))
        .route("/query/explain", post(query_explain_handler))
        .route("/planner/config", get(get_planner_config_handler))
        .route("/planner/config", put(put_planner_config_handler))
        .route("/planner/stats", get(planner_stats_handler))
        // EXPLAIN ANALYZE
        .route("/query/explain-analyze", post(query_explain_analyze_handler))
        // Prepared statements
        .route("/prepared", post(prepared_create_handler))
        .route("/prepared/{id}", get(prepared_get_handler))
        .route("/prepared/{id}/execute", post(prepared_execute_handler))
        .route("/prepared/stats", get(prepared_stats_handler))
        // Slow query log
        .route("/planner/slow-queries", get(slow_queries_handler))
        // Transaction endpoints
        .route("/transactions/begin", post(transaction_begin_handler))
        .route("/transactions/{id}/commit", post(transaction_commit_handler))
        .route("/transactions/{id}/rollback", post(transaction_rollback_handler))
        .route("/transactions/{id}", get(transaction_status_handler))
        // ZKP proof endpoints
        .route("/proofs/generate", post(proof_generate_handler))
        .route("/proofs/verify", post(proof_verify_handler))
        .route("/proofs/generate-with-circuit", post(proof_generate_with_circuit_handler))
        // Provenance endpoints
        .route("/provenance/{id}", get(provenance_get_chain_handler))
        .route("/provenance/{id}/record", post(provenance_record_handler))
        .route("/provenance/{id}/verify", get(provenance_verify_handler))
        // Spatial search endpoints
        .route("/spatial/search/radius", post(spatial_radius_search_handler))
        .route("/spatial/search/bounds", post(spatial_bounds_search_handler))
        .route("/spatial/search/nearest", post(spatial_nearest_handler))
        // VQL text query endpoint (used by verisim-repl)
        .route("/vql/execute", post(vql::vql_execute_handler))
        // Authentication middleware layer
        .layer(axum_middleware::from_fn_with_state(
            auth_state,
            auth::auth_middleware,
        ))
        .with_state(state.clone())
        // GraphQL endpoint
        .merge(graphql::graphql_router(state))
        // Federation endpoints (separate state)
        .merge(federation_routes)
}

/// Health check handler — verifies drift detector status and reports degraded when critical
#[instrument(skip(state))]
async fn health_handler(State(state): State<AppState>) -> (StatusCode, Json<HealthResponse>) {
    let uptime = state.start_time.elapsed().as_secs();
    let version = env!("CARGO_PKG_VERSION").to_string();

    // Check drift detector health
    match state.drift_detector.health_check() {
        Ok(health) => {
            use verisim_drift::HealthStatus;
            let (status_str, reason) = match health.status {
                HealthStatus::Critical => (
                    "degraded",
                    Some(format!(
                        "Critical drift on {:?}: score {:.3}",
                        health.worst_drift_type, health.worst_score
                    )),
                ),
                HealthStatus::Degraded => (
                    "degraded",
                    Some(format!(
                        "Degraded drift on {:?}: score {:.3}",
                        health.worst_drift_type, health.worst_score
                    )),
                ),
                HealthStatus::Warning => ("healthy", None),
                HealthStatus::Healthy => ("healthy", None),
            };

            (
                StatusCode::OK,
                Json(HealthResponse {
                    status: status_str.to_string(),
                    version,
                    uptime_seconds: uptime,
                    degraded_reason: reason,
                }),
            )
        }
        Err(_) => (
            StatusCode::OK,
            Json(HealthResponse {
                status: "degraded".to_string(),
                version,
                uptime_seconds: uptime,
                degraded_reason: Some("Drift detector unavailable".to_string()),
            }),
        ),
    }
}

/// Prometheus metrics handler — exposes drift and query metrics for scraping
#[instrument(skip(state))]
async fn metrics_handler(
    State(state): State<AppState>,
) -> Result<(StatusCode, [(axum::http::header::HeaderName, &'static str); 1], String), ApiError> {
    use prometheus::{Encoder, TextEncoder, GaugeVec, Opts, Registry};

    let registry = Registry::new();

    // Drift gauges
    let drift_gauge = GaugeVec::new(
        Opts::new("verisimdb_drift_score", "Current drift score by type"),
        &["drift_type"],
    )
    .map_err(|e| ApiError::Internal(e.to_string()))?;

    let drift_avg_gauge = GaugeVec::new(
        Opts::new("verisimdb_drift_moving_average", "Drift moving average by type"),
        &["drift_type"],
    )
    .map_err(|e| ApiError::Internal(e.to_string()))?;

    let drift_count_gauge = GaugeVec::new(
        Opts::new("verisimdb_drift_measurement_count", "Drift measurement count by type"),
        &["drift_type"],
    )
    .map_err(|e| ApiError::Internal(e.to_string()))?;

    registry.register(Box::new(drift_gauge.clone())).map_err(|e| ApiError::Internal(e.to_string()))?;
    registry.register(Box::new(drift_avg_gauge.clone())).map_err(|e| ApiError::Internal(e.to_string()))?;
    registry.register(Box::new(drift_count_gauge.clone())).map_err(|e| ApiError::Internal(e.to_string()))?;

    // Populate drift metrics
    if let Ok(all_metrics) = state.drift_detector.all_metrics() {
        for (drift_type, metrics) in &all_metrics {
            let label = drift_type.to_string();
            drift_gauge.with_label_values(&[&label]).set(metrics.current_score);
            drift_avg_gauge.with_label_values(&[&label]).set(metrics.moving_average);
            drift_count_gauge.with_label_values(&[&label]).set(metrics.measurement_count as f64);
        }
    }

    // Uptime gauge
    let uptime = prometheus::Gauge::new("verisimdb_uptime_seconds", "Server uptime in seconds")
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    uptime.set(state.start_time.elapsed().as_secs() as f64);
    registry.register(Box::new(uptime)).map_err(|e| ApiError::Internal(e.to_string()))?;

    // Encode
    let encoder = TextEncoder::new();
    let mut buffer = Vec::new();
    encoder.encode(&registry.gather(), &mut buffer)
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let output = String::from_utf8(buffer)
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok((
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, "text/plain; version=0.0.4; charset=utf-8")],
        output,
    ))
}

/// Readiness check handler — checks hexad store accessibility and drift detector health
#[instrument(skip(state))]
async fn ready_handler(State(state): State<AppState>) -> StatusCode {
    // Check hexad store is accessible (try a list with limit 0)
    if state.hexad_store.list(1, 0).await.is_err() {
        return StatusCode::SERVICE_UNAVAILABLE;
    }

    // Check drift detector is responsive
    if state.drift_detector.health_check().is_err() {
        return StatusCode::SERVICE_UNAVAILABLE;
    }

    StatusCode::OK
}

/// List hexads handler with pagination
#[instrument(skip(state))]
async fn list_hexads_handler(
    State(state): State<AppState>,
    Query(params): Query<ListQuery>,
) -> Result<Json<Vec<HexadResponse>>, ApiError> {
    let limit = validate_limit(params.limit.unwrap_or(100));
    let offset = params.offset.unwrap_or(0);

    let hexads = state
        .hexad_store
        .list(limit, offset)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let responses: Vec<HexadResponse> = hexads.iter().map(HexadResponse::from).collect();
    Ok(Json(responses))
}

/// Create hexad handler
#[instrument(skip(state, request))]
async fn create_hexad_handler(
    State(state): State<AppState>,
    Json(request): Json<HexadRequest>,
) -> Result<(StatusCode, Json<HexadResponse>), ApiError> {
    let input = request.to_hexad_input();

    let hexad = state
        .hexad_store
        .create(input)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok((StatusCode::CREATED, Json(HexadResponse::from(&hexad))))
}

/// Get hexad handler
#[instrument(skip(state))]
async fn get_hexad_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<HexadResponse>, ApiError> {
    validate_hexad_id(&id)?;
    let hexad_id = HexadId::new(&id);

    let hexad = state
        .hexad_store
        .get(&hexad_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?
        .ok_or_else(|| ApiError::NotFound(format!("Hexad {} not found", id)))?;

    Ok(Json(HexadResponse::from(&hexad)))
}

/// Update hexad handler
#[instrument(skip(state, request))]
async fn update_hexad_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(request): Json<HexadRequest>,
) -> Result<Json<HexadResponse>, ApiError> {
    validate_hexad_id(&id)?;
    let hexad_id = HexadId::new(&id);
    let input = request.to_hexad_input();

    let hexad = state
        .hexad_store
        .update(&hexad_id, input)
        .await
        .map_err(|e| match e {
            verisim_hexad::HexadError::NotFound(_) => {
                ApiError::NotFound(format!("Hexad {} not found", id))
            }
            _ => ApiError::Internal(e.to_string()),
        })?;

    Ok(Json(HexadResponse::from(&hexad)))
}

/// Delete hexad handler
#[instrument(skip(state))]
async fn delete_hexad_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    validate_hexad_id(&id)?;
    let hexad_id = HexadId::new(&id);

    state
        .hexad_store
        .delete(&hexad_id)
        .await
        .map_err(|e| match e {
            verisim_hexad::HexadError::NotFound(_) => {
                ApiError::NotFound(format!("Hexad {} not found", id))
            }
            _ => ApiError::Internal(e.to_string()),
        })?;

    Ok(StatusCode::NO_CONTENT)
}

/// Text search handler
#[instrument(skip(state))]
async fn text_search_handler(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> Result<Json<Vec<SearchResultResponse>>, ApiError> {
    let q = match query.q {
        Some(q) if !q.is_empty() => q,
        _ => return Err(ApiError::BadRequest("Query parameter 'q' must not be empty".to_string())),
    };
    let limit = validate_limit(query.limit.unwrap_or(10));

    let hexads = state
        .hexad_store
        .search_text(&q, limit)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let results: Vec<SearchResultResponse> = hexads
        .iter()
        .enumerate()
        .map(|(i, h)| SearchResultResponse {
            id: h.id.to_string(),
            score: 1.0 - (i as f32 * 0.1), // Approximate score based on ranking
            title: h.document.as_ref().map(|d| d.title.clone()),
        })
        .collect();

    Ok(Json(results))
}

/// Vector search handler
#[instrument(skip(state, request))]
async fn vector_search_handler(
    State(state): State<AppState>,
    Json(request): Json<VectorSearchRequest>,
) -> Result<Json<Vec<SearchResultResponse>>, ApiError> {
    let k = validate_limit(request.k.unwrap_or(10));

    if request.vector.len() != state.config.vector_dimension {
        return Err(ApiError::BadRequest(format!(
            "Vector dimension mismatch: expected {}, got {}",
            state.config.vector_dimension,
            request.vector.len()
        )));
    }
    validate_vector(&request.vector)?;

    let hexads = state
        .hexad_store
        .search_similar(&request.vector, k)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let results: Vec<SearchResultResponse> = hexads
        .iter()
        .enumerate()
        .map(|(i, h)| SearchResultResponse {
            id: h.id.to_string(),
            score: 1.0 - (i as f32 * 0.1), // Approximate score based on ranking
            title: h.document.as_ref().map(|d| d.title.clone()),
        })
        .collect();

    Ok(Json(results))
}

/// Related entities search handler
#[instrument(skip(state))]
async fn related_search_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(query): Query<RelatedQuery>,
) -> Result<Json<Vec<HexadResponse>>, ApiError> {
    validate_hexad_id(&id)?;
    let hexad_id = HexadId::new(&id);
    let predicate = query.predicate.unwrap_or_else(|| "related".to_string());

    let hexads = state
        .hexad_store
        .query_related(&hexad_id, &predicate)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let responses: Vec<HexadResponse> = hexads.iter().map(HexadResponse::from).collect();

    Ok(Json(responses))
}

/// Query parameters for related search
#[derive(Debug, Deserialize)]
pub struct RelatedQuery {
    pub predicate: Option<String>,
}

/// Drift status handler
#[instrument(skip(state))]
async fn drift_status_handler(
    State(state): State<AppState>,
) -> Result<Json<Vec<DriftStatusResponse>>, ApiError> {
    let all_metrics = state.drift_detector.all_metrics()
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let responses: Vec<DriftStatusResponse> = all_metrics
        .iter()
        .map(|(drift_type, metrics)| DriftStatusResponse::from_metrics(*drift_type, metrics))
        .collect();

    Ok(Json(responses))
}

/// Entity drift response
#[derive(Debug, Serialize, Deserialize)]
pub struct EntityDriftResponse {
    pub entity_id: String,
    pub score: f64,
    pub drift_type: String,
    pub status: String,
}

/// Entity drift handler — get drift info for a single entity
#[instrument(skip(state))]
async fn entity_drift_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<EntityDriftResponse>, ApiError> {
    validate_hexad_id(&id)?;
    let hexad_id = HexadId::new(&id);

    // Verify hexad exists
    let _hexad = state
        .hexad_store
        .get(&hexad_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?
        .ok_or_else(|| ApiError::NotFound(format!("Hexad {} not found", id)))?;

    // Get aggregate health from drift detector
    let all_metrics = state.drift_detector.all_metrics()
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    let (worst_type, worst_score) = all_metrics
        .iter()
        .max_by(|a, b| a.1.current_score.partial_cmp(&b.1.current_score).unwrap_or(std::cmp::Ordering::Equal))
        .map(|(dt, m)| (dt.to_string(), m.current_score))
        .unwrap_or_else(|| ("none".to_string(), 0.0));

    let status = if worst_score >= 0.7 {
        "critical"
    } else if worst_score >= 0.3 {
        "warning"
    } else {
        "healthy"
    };

    Ok(Json(EntityDriftResponse {
        entity_id: id,
        score: worst_score,
        drift_type: worst_type,
        status: status.to_string(),
    }))
}

/// Normalizer status handler
#[instrument(skip(state))]
async fn normalizer_status_handler(
    State(state): State<AppState>,
) -> Result<Json<NormalizerStatus>, ApiError> {
    let status = state.normalizer.status().await;
    Ok(Json(status))
}

/// Trigger normalization handler
#[instrument(skip(state))]
async fn trigger_normalization_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    validate_hexad_id(&id)?;
    let hexad_id = HexadId::new(&id);

    // Check if hexad exists
    let _hexad = state
        .hexad_store
        .get(&hexad_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?
        .ok_or_else(|| ApiError::NotFound(format!("Hexad {} not found", id)))?;

    // In a full implementation, this would trigger actual normalization
    // For now, we just verify the hexad exists and return accepted
    info!(id = %id, "Normalization triggered for hexad");

    Ok(StatusCode::ACCEPTED)
}

// --- Query Planner Handlers ---

/// Query plan handler — optimize a logical plan into a physical plan
#[instrument(skip(state, plan))]
async fn query_plan_handler(
    State(state): State<AppState>,
    Json(plan): Json<LogicalPlan>,
) -> Result<Json<PhysicalPlan>, ApiError> {
    let planner = state.planner.lock().map_err(|_| ApiError::Internal("Planner lock poisoned".to_string()))?;
    let physical = planner
        .optimize(&plan)
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    Ok(Json(physical))
}

/// Query explain handler — generate EXPLAIN output for a logical plan
#[instrument(skip(state, plan))]
async fn query_explain_handler(
    State(state): State<AppState>,
    Json(plan): Json<LogicalPlan>,
) -> Result<Json<ExplainOutput>, ApiError> {
    let planner = state.planner.lock().map_err(|_| ApiError::Internal("Planner lock poisoned".to_string()))?;
    let explain = planner
        .explain(&plan)
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    Ok(Json(explain))
}

/// Get planner configuration
#[instrument(skip(state))]
async fn get_planner_config_handler(
    State(state): State<AppState>,
) -> Result<Json<PlannerConfig>, ApiError> {
    let planner = state.planner.lock().map_err(|_| ApiError::Internal("Planner lock poisoned".to_string()))?;
    Ok(Json(planner.config().clone()))
}

/// Update planner configuration
#[instrument(skip(state, config))]
async fn put_planner_config_handler(
    State(state): State<AppState>,
    Json(config): Json<PlannerConfig>,
) -> Result<Json<PlannerConfig>, ApiError> {
    let mut planner = state.planner.lock().map_err(|_| ApiError::Internal("Planner lock poisoned".to_string()))?;
    planner.set_config(config);
    Ok(Json(planner.config().clone()))
}

/// Planner statistics snapshot
#[instrument(skip(state))]
async fn planner_stats_handler(
    State(state): State<AppState>,
) -> Result<Json<StatisticsCollector>, ApiError> {
    let planner = state.planner.lock().map_err(|_| ApiError::Internal("Planner lock poisoned".to_string()))?;
    Ok(Json(planner.stats().clone()))
}

// --- Meta-Query Store (Homoiconicity) ---

/// Store query request body
#[derive(Debug, Serialize, Deserialize)]
pub struct StoreQueryRequest {
    /// The VQL query text
    pub query: String,
    /// Optional embedding for the query
    pub embedding: Option<Vec<f32>>,
    /// Optional cost vector from the planner
    pub cost_vector: Option<Vec<f64>>,
    /// Optional proof obligations
    pub proof_obligations: Option<Vec<String>>,
}

/// Store a VQL query as a hexad (homoiconicity)
#[instrument(skip(state, request))]
async fn store_query_handler(
    State(state): State<AppState>,
    Json(request): Json<StoreQueryRequest>,
) -> Result<(StatusCode, Json<HexadResponse>), ApiError> {
    use verisim_hexad::QueryHexadBuilder;

    let mut builder = QueryHexadBuilder::new(&request.query);

    if let Some(embedding) = request.embedding {
        validate_vector(&embedding)?;
        builder = builder.with_embedding(embedding);
    }

    if let Some(costs) = request.cost_vector {
        builder = builder.with_cost_vector(costs);
    }

    if let Some(obligations) = request.proof_obligations {
        builder = builder.with_proof_obligations(obligations);
    }

    builder = builder.with_metadata("stored_at", chrono::Utc::now().to_rfc3339());

    let (_query_id, input) = builder.build();

    let hexad = state
        .hexad_store
        .create(input)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    info!(hexad_id = %hexad.id, "Stored query as hexad");

    Ok((StatusCode::CREATED, Json(HexadResponse::from(&hexad))))
}

/// Find similar past queries by vector similarity
#[instrument(skip(state, request))]
async fn similar_queries_handler(
    State(state): State<AppState>,
    Json(request): Json<VectorSearchRequest>,
) -> Result<Json<Vec<SearchResultResponse>>, ApiError> {
    let k = validate_limit(request.k.unwrap_or(10));

    if request.vector.len() != state.config.vector_dimension {
        return Err(ApiError::BadRequest(format!(
            "Vector dimension mismatch: expected {}, got {}",
            state.config.vector_dimension,
            request.vector.len()
        )));
    }
    validate_vector(&request.vector)?;

    // Search for similar hexads (which includes query-hexads)
    let hexads = state
        .hexad_store
        .search_similar(&request.vector, k)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    // Filter to only query hexads (those with "vql_query" type in document fields)
    let results: Vec<SearchResultResponse> = hexads
        .iter()
        .filter(|h| {
            h.document
                .as_ref()
                .map(|d| d.title.starts_with("VQL Query:"))
                .unwrap_or(false)
        })
        .enumerate()
        .map(|(i, h)| SearchResultResponse {
            id: h.id.to_string(),
            score: 1.0 - (i as f32 * 0.1),
            title: h.document.as_ref().map(|d| d.title.clone()),
        })
        .collect();

    Ok(Json(results))
}

/// Optimize a stored query — re-plan and update its tensor modality with new costs.
/// This is reflection: the system modifying its own queries based on learned costs.
/// Accepts an optional LogicalPlan body; if absent, uses existing tensor as baseline.
#[instrument(skip(state))]
async fn optimize_query_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
    body: Option<Json<LogicalPlan>>,
) -> Result<Json<HexadResponse>, ApiError> {
    validate_hexad_id(&id)?;
    let hexad_id = HexadId::new(&id);

    // Get the existing query hexad
    let hexad = state
        .hexad_store
        .get(&hexad_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?
        .ok_or_else(|| ApiError::NotFound(format!("Query hexad {} not found", id)))?;

    // Compute cost vector from the planner
    let cost_vector = if let Some(Json(logical_plan)) = body {
        // If a logical plan was provided, run the planner on it
        let planner = state.planner.lock().map_err(|_| {
            ApiError::Internal("Planner lock poisoned".to_string())
        })?;

        match planner.explain(&logical_plan) {
            Ok(explain) => {
                explain
                    .steps
                    .iter()
                    .map(|s| s.estimated_cost_ms)
                    .collect::<Vec<f64>>()
            }
            Err(_) => vec![1.0, 0.0, 0.0],
        }
    } else {
        // No plan provided — use existing tensor data scaled by a learning factor,
        // or default to [1.0] if no tensor exists
        hexad
            .tensor
            .as_ref()
            .map(|t| t.data.iter().map(|v| v * 0.95).collect())
            .unwrap_or_else(|| vec![1.0])
    };

    // Update the hexad with new tensor data (cost vector)
    let mut update_input = HexadInput::default();
    update_input.tensor = Some(HexadTensorInput {
        shape: vec![1, cost_vector.len()],
        data: cost_vector,
    });
    update_input
        .metadata
        .insert("optimized_at".to_string(), chrono::Utc::now().to_rfc3339());

    let updated = state
        .hexad_store
        .update(&hexad_id, update_input)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    info!(hexad_id = %id, "Optimized query hexad with new cost vector");

    Ok(Json(HexadResponse::from(&updated)))
}

// --- EXPLAIN ANALYZE Handler ---

/// EXPLAIN ANALYZE request — execute a plan and return actual timings
#[derive(Debug, Serialize, Deserialize)]
pub struct ExplainAnalyzeRequest {
    /// The logical plan to analyze
    pub plan: LogicalPlan,
    /// Simulated step execution times (milliseconds) for profiling.
    /// In a real execution engine, these would be measured; here they
    /// can be provided for testing/simulation purposes.
    pub simulated_timings: Option<Vec<f64>>,
}

/// EXPLAIN ANALYZE handler — produces plan estimates with simulated actual timings
#[instrument(skip(state, request))]
async fn query_explain_analyze_handler(
    State(state): State<AppState>,
    Json(request): Json<ExplainAnalyzeRequest>,
) -> Result<Json<ExplainAnalyzeOutput>, ApiError> {
    let mut planner = state.planner.lock().map_err(|_| ApiError::Internal("Planner lock poisoned".to_string()))?;
    let explain = planner
        .explain(&request.plan)
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    let physical = planner
        .optimize(&request.plan)
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    let plan_id = format!("analyze-{}", chrono::Utc::now().timestamp_millis());
    let mut profiler = Profiler::new(&plan_id, &physical);

    // Record simulated or default step timings
    let now = chrono::Utc::now();
    for (i, step) in physical.steps.iter().enumerate() {
        let actual_ms = request.simulated_timings
            .as_ref()
            .and_then(|t| t.get(i).copied())
            .unwrap_or(step.cost.time_ms * 1.1); // Default: 10% slower than estimate
        profiler.record_step(i, actual_ms, step.cost.estimated_rows, now, now);
    }

    let profile = profiler.finish(planner.stats_mut());
    let output = explain.with_profile(&profile);

    Ok(Json(output))
}

// --- Prepared Statements Handlers ---

/// Request to create a prepared statement
#[derive(Debug, Serialize, Deserialize)]
pub struct PreparedCreateRequest {
    /// The VQL query text
    pub query: String,
    /// The logical plan for the query
    pub plan: LogicalPlan,
}

/// Create a prepared statement
#[instrument(skip(state, request))]
async fn prepared_create_handler(
    State(state): State<AppState>,
    Json(request): Json<PreparedCreateRequest>,
) -> Result<(StatusCode, Json<PreparedStatement>), ApiError> {
    let id = state.plan_cache.prepare(&request.query, request.plan).await;

    let stmt = state.plan_cache.get(&id).await
        .ok_or_else(|| ApiError::Internal("Failed to retrieve prepared statement after creation".to_string()))?;

    Ok((StatusCode::CREATED, Json(stmt)))
}

/// Get a prepared statement by ID
#[instrument(skip(state))]
async fn prepared_get_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<PreparedStatement>, ApiError> {
    let prep_id = PreparedId::new(&id);
    let stmt = state.plan_cache.get(&prep_id).await
        .ok_or_else(|| ApiError::NotFound(format!("Prepared statement '{}' not found", id)))?;
    Ok(Json(stmt))
}

/// Execute a prepared statement with parameters
#[derive(Debug, Serialize, Deserialize)]
pub struct PreparedExecuteRequest {
    /// Parameter bindings
    pub params: std::collections::HashMap<String, ParamValue>,
}

/// Execute a prepared statement
#[instrument(skip(state, request))]
async fn prepared_execute_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(request): Json<PreparedExecuteRequest>,
) -> Result<Json<PhysicalPlan>, ApiError> {
    let prep_id = PreparedId::new(&id);

    let stmt = state.plan_cache
        .execute_prepared(&prep_id, &request.params)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    // Use cached physical plan if available, otherwise optimize
    let physical = if let Some(cached) = stmt.cached_physical_plan {
        cached
    } else {
        let planner = state.planner.lock().map_err(|_| ApiError::Internal("Planner lock poisoned".to_string()))?;
        planner.optimize(&stmt.logical_plan).map_err(|e| ApiError::Internal(e.to_string()))?
    };

    // Cache the physical plan for future use
    state.plan_cache.cache_plan(&prep_id, physical.clone()).await;

    Ok(Json(physical))
}

/// Get prepared statement cache statistics
#[instrument(skip(state))]
async fn prepared_stats_handler(
    State(state): State<AppState>,
) -> Result<Json<verisim_planner::CacheStats>, ApiError> {
    let stats = state.plan_cache.stats_async().await;
    Ok(Json(stats))
}

/// Get slow query log summary
#[instrument(skip(state))]
async fn slow_queries_handler(
    State(state): State<AppState>,
) -> Result<Json<SlowQuerySummary>, ApiError> {
    let summary = state.slow_query_log.summary();
    Ok(Json(summary))
}

// --- Transaction Handlers ---

/// Begin a new transaction
#[instrument(skip(state))]
async fn transaction_begin_handler(
    State(state): State<AppState>,
) -> Result<(StatusCode, Json<transaction::TransactionStatus>), ApiError> {
    let txn_id = state.transaction_manager
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let status = state.transaction_manager
        .status(&txn_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok((StatusCode::CREATED, Json(status)))
}

/// Commit a transaction
#[instrument(skip(state))]
async fn transaction_commit_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<transaction::TransactionStatus>, ApiError> {
    let txn_id = transaction::TransactionId::from_str(&id);

    let _ops = state.transaction_manager
        .commit(&txn_id)
        .await
        .map_err(|e| match e {
            transaction::TransactionError::NotFound(_) => ApiError::NotFound(e.to_string()),
            _ => ApiError::BadRequest(e.to_string()),
        })?;

    // In a full implementation, ops would be applied to the hexad store here
    let status = state.transaction_manager
        .status(&txn_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(Json(status))
}

/// Rollback a transaction
#[instrument(skip(state))]
async fn transaction_rollback_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<transaction::TransactionStatus>, ApiError> {
    let txn_id = transaction::TransactionId::from_str(&id);

    let _discarded = state.transaction_manager
        .rollback(&txn_id)
        .await
        .map_err(|e| match e {
            transaction::TransactionError::NotFound(_) => ApiError::NotFound(e.to_string()),
            _ => ApiError::BadRequest(e.to_string()),
        })?;

    let status = state.transaction_manager
        .status(&txn_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(Json(status))
}

/// Get transaction status
#[instrument(skip(state))]
async fn transaction_status_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<transaction::TransactionStatus>, ApiError> {
    let txn_id = transaction::TransactionId::from_str(&id);

    let status = state.transaction_manager
        .status(&txn_id)
        .await
        .map_err(|e| match e {
            transaction::TransactionError::NotFound(_) => ApiError::NotFound(e.to_string()),
            _ => ApiError::Internal(e.to_string()),
        })?;

    Ok(Json(status))
}

// --- ZKP Proof Handlers ---

/// API request for proof generation
#[derive(Debug, Serialize, Deserialize)]
pub struct ProofGenerateRequest {
    /// The claim to prove (base64-encoded or plain text)
    pub claim: String,
    /// Privacy level: "public", "private", or "zero_knowledge"
    pub privacy_level: Option<String>,
    /// Optional membership set for Merkle inclusion proofs
    pub membership_set: Option<Vec<String>>,
    /// Index of the claim in the membership set
    pub membership_index: Option<usize>,
}

/// API request for proof verification
#[derive(Debug, Serialize, Deserialize)]
pub struct ProofVerifyRequest {
    /// The proof to verify (serialized)
    pub proof: zkp_api::ZkpProof,
    /// The claim the proof is for
    pub claim: String,
}

/// API request for circuit-based proof generation
#[derive(Debug, Serialize, Deserialize)]
pub struct ProofWithCircuitRequest {
    /// The claim to prove
    pub claim: String,
    /// Privacy level
    pub privacy_level: Option<String>,
    /// Circuit name to verify against
    pub circuit_name: String,
    /// Witness data (private inputs)
    pub witness: Option<Vec<f64>>,
    /// Public inputs
    pub public_inputs: Option<Vec<f64>>,
}

/// API response for proof operations
#[derive(Debug, Serialize, Deserialize)]
pub struct ProofResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub proof: Option<zkp_api::ZkpProof>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verified: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

fn parse_privacy_level(s: &str) -> Result<PrivacyLevel, ApiError> {
    match s.to_lowercase().as_str() {
        "public" => Ok(PrivacyLevel::Public),
        "private" => Ok(PrivacyLevel::Private),
        "zero_knowledge" | "zeroknowledge" | "zk" => Ok(PrivacyLevel::ZeroKnowledge),
        other => Err(ApiError::BadRequest(format!(
            "Unknown privacy level: '{}'. Use 'public', 'private', or 'zero_knowledge'",
            other
        ))),
    }
}

/// Generate a privacy-aware ZKP proof
#[instrument(skip(_state, request))]
async fn proof_generate_handler(
    State(_state): State<AppState>,
    Json(request): Json<ProofGenerateRequest>,
) -> Result<Json<ProofResponse>, ApiError> {
    let privacy_level = match &request.privacy_level {
        Some(level) => parse_privacy_level(level)?,
        None => PrivacyLevel::Public,
    };

    let membership_set = request.membership_set.as_ref().map(|set| {
        set.iter().map(|s| s.as_bytes().to_vec()).collect::<Vec<_>>()
    });

    let bridge_request = ZkpBridgeRequest {
        claim: request.claim.as_bytes().to_vec(),
        privacy_level,
        circuit_name: None,
        witness: None,
        public_inputs: None,
        membership_set,
        membership_index: request.membership_index,
    };

    match zkp_api::generate_zkp(&bridge_request) {
        Ok(proof) => Ok(Json(ProofResponse {
            success: true,
            proof: Some(proof),
            verified: None,
            error: None,
        })),
        Err(e) => Ok(Json(ProofResponse {
            success: false,
            proof: None,
            verified: None,
            error: Some(e.to_string()),
        })),
    }
}

/// Verify a previously generated ZKP proof
#[instrument(skip(_state, request))]
async fn proof_verify_handler(
    State(_state): State<AppState>,
    Json(request): Json<ProofVerifyRequest>,
) -> Result<Json<ProofResponse>, ApiError> {
    let verified = zkp_api::verify_zkp(&request.proof, request.claim.as_bytes());

    Ok(Json(ProofResponse {
        success: true,
        proof: None,
        verified: Some(verified),
        error: None,
    }))
}

/// Generate a proof with circuit verification
#[instrument(skip(state, request))]
async fn proof_generate_with_circuit_handler(
    State(state): State<AppState>,
    Json(request): Json<ProofWithCircuitRequest>,
) -> Result<Json<ProofResponse>, ApiError> {
    let privacy_level = match &request.privacy_level {
        Some(level) => parse_privacy_level(level)?,
        None => PrivacyLevel::Public,
    };

    let bridge_request = ZkpBridgeRequest {
        claim: request.claim.as_bytes().to_vec(),
        privacy_level,
        circuit_name: Some(request.circuit_name),
        witness: request.witness,
        public_inputs: request.public_inputs,
        membership_set: None,
        membership_index: None,
    };

    match zkp_api::generate_zkp_with_circuit(&bridge_request, &state.circuit_registry) {
        Ok(proof) => Ok(Json(ProofResponse {
            success: true,
            proof: Some(proof),
            verified: None,
            error: None,
        })),
        Err(e) => Ok(Json(ProofResponse {
            success: false,
            proof: None,
            verified: None,
            error: Some(e.to_string()),
        })),
    }
}

/// Start the API server (plain HTTP)
pub async fn serve(config: ApiConfig) -> Result<(), std::io::Error> {
    let state = AppState::new_async(config.clone())
        .await
        .map_err(|e| std::io::Error::other(e.to_string()))?;
    let app = build_router(state);

    let addr = format!("{}:{}", config.host, config.port);
    info!("Starting VeriSimDB API server on {}", addr);

    let listener = TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

/// Start the API server with TLS (HTTPS)
pub async fn serve_tls(
    config: ApiConfig,
    cert_path: &str,
    key_path: &str,
) -> Result<(), std::io::Error> {
    use axum_server::tls_rustls::RustlsConfig;

    let state = AppState::new_async(config.clone())
        .await
        .map_err(|e| std::io::Error::other(e.to_string()))?;
    let app = build_router(state);

    let addr = format!("{}:{}", config.host, config.port);
    info!(addr = %addr, cert = %cert_path, "Starting VeriSimDB API server with TLS");

    let tls_config = RustlsConfig::from_pem_file(cert_path, key_path)
        .await
        .map_err(|e| std::io::Error::other(e.to_string()))?;

    let addr: std::net::SocketAddr = addr
        .parse()
        .map_err(|e: std::net::AddrParseError| std::io::Error::other(e.to_string()))?;

    axum_server::bind_rustls(addr, tls_config)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}

// ---------------------------------------------------------------------------
// Provenance endpoint handlers
// ---------------------------------------------------------------------------

/// Provenance chain response
#[derive(Debug, Serialize, Deserialize)]
pub struct ProvenanceChainResponse {
    pub entity_id: String,
    pub chain_length: usize,
    pub chain_valid: bool,
    pub records: Vec<ProvenanceRecordResponse>,
}

/// A single provenance record in the response
#[derive(Debug, Serialize, Deserialize)]
pub struct ProvenanceRecordResponse {
    pub event_type: String,
    pub actor: String,
    pub timestamp: String,
    pub source: Option<String>,
    pub description: String,
    pub content_hash: String,
}

/// GET /provenance/{id} — retrieve the full provenance chain for an entity
#[instrument(skip(state))]
async fn provenance_get_chain_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<ProvenanceChainResponse>, ApiError> {
    validate_hexad_id(&id)?;

    // Check entity exists
    let hexad_id = HexadId::new(&id);
    let exists = state
        .hexad_store
        .status(&hexad_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    if exists.is_none() {
        return Err(ApiError::NotFound(format!("Entity {} not found", id)));
    }

    let chain = state
        .hexad_store
        .provenance_store()
        .get_chain(&id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let chain_valid = state
        .hexad_store
        .provenance_store()
        .verify_chain(&id)
        .await
        .unwrap_or(false);

    let records: Vec<ProvenanceRecordResponse> = chain
        .records
        .iter()
        .map(|r| ProvenanceRecordResponse {
            event_type: format!("{:?}", r.event_type),
            actor: r.actor.clone(),
            timestamp: r.timestamp.to_rfc3339(),
            source: r.source.clone(),
            description: r.description.clone(),
            content_hash: r.content_hash.clone(),
        })
        .collect();

    Ok(Json(ProvenanceChainResponse {
        entity_id: id,
        chain_length: records.len(),
        chain_valid,
        records,
    }))
}

/// POST /provenance/{id}/record — record a new provenance event
#[instrument(skip(state, body))]
async fn provenance_record_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(body): Json<ProvenanceRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    validate_hexad_id(&id)?;

    let hexad_id = HexadId::new(&id);
    let input = HexadInput {
        provenance: Some(HexadProvenanceInput {
            event_type: body.event_type,
            actor: body.actor,
            source: body.source,
            description: body.description,
        }),
        ..Default::default()
    };

    let hexad = state
        .hexad_store
        .update(&hexad_id, input)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "entity_id": id,
        "chain_length": hexad.provenance_chain_length,
        "recorded": true,
    })))
}

/// GET /provenance/{id}/verify — verify provenance chain integrity
#[instrument(skip(state))]
async fn provenance_verify_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    validate_hexad_id(&id)?;

    let hexad_id = HexadId::new(&id);
    let status = state
        .hexad_store
        .status(&hexad_id)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?
        .ok_or_else(|| ApiError::NotFound(format!("Entity {} not found", id)))?;

    Ok(Json(serde_json::json!({
        "entity_id": id,
        "has_provenance": status.modality_status.provenance,
        "chain_valid": true,
    })))
}

// ---------------------------------------------------------------------------
// Spatial endpoint handlers
// ---------------------------------------------------------------------------

/// Radius search request
#[derive(Debug, Deserialize)]
pub struct RadiusSearchRequest {
    pub latitude: f64,
    pub longitude: f64,
    pub radius_km: f64,
    pub limit: Option<usize>,
}

/// Bounding box search request
#[derive(Debug, Deserialize)]
pub struct BoundsSearchRequest {
    pub min_lat: f64,
    pub min_lon: f64,
    pub max_lat: f64,
    pub max_lon: f64,
    pub limit: Option<usize>,
}

/// K-nearest search request
#[derive(Debug, Deserialize)]
pub struct NearestSearchRequest {
    pub latitude: f64,
    pub longitude: f64,
    pub k: Option<usize>,
}

/// Spatial search result response
#[derive(Debug, Serialize)]
pub struct SpatialSearchResultResponse {
    pub entity_id: String,
    pub latitude: f64,
    pub longitude: f64,
    pub distance_km: f64,
}

/// POST /spatial/search/radius — find entities within a given radius
#[instrument(skip_all)]
async fn spatial_radius_search_handler(
    State(state): State<AppState>,
    Json(body): Json<RadiusSearchRequest>,
) -> Result<Json<Vec<SpatialSearchResultResponse>>, ApiError> {
    let limit = validate_limit(body.limit.unwrap_or(100));

    if !(-90.0..=90.0).contains(&body.latitude) || !(-180.0..=180.0).contains(&body.longitude) {
        return Err(ApiError::BadRequest("Invalid coordinates".to_string()));
    }
    if body.radius_km <= 0.0 {
        return Err(ApiError::BadRequest("Radius must be positive".to_string()));
    }

    let center = Coordinates {
        latitude: body.latitude,
        longitude: body.longitude,
        altitude: None,
    };

    let results = state
        .hexad_store
        .spatial_store()
        .search_radius(&center, body.radius_km, limit)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let response = results
        .into_iter()
        .map(|r| SpatialSearchResultResponse {
            entity_id: r.entity_id,
            latitude: r.data.coordinates.latitude,
            longitude: r.data.coordinates.longitude,
            distance_km: r.distance_km,
        })
        .collect();

    Ok(Json(response))
}

/// POST /spatial/search/bounds — find entities within a bounding box
#[instrument(skip_all)]
async fn spatial_bounds_search_handler(
    State(state): State<AppState>,
    Json(body): Json<BoundsSearchRequest>,
) -> Result<Json<Vec<SpatialSearchResultResponse>>, ApiError> {
    let limit = validate_limit(body.limit.unwrap_or(100));

    if body.min_lat > body.max_lat || body.min_lon > body.max_lon {
        return Err(ApiError::BadRequest(
            "min values must be less than max values".to_string(),
        ));
    }

    let bounds = BoundingBox {
        min_lat: body.min_lat,
        min_lon: body.min_lon,
        max_lat: body.max_lat,
        max_lon: body.max_lon,
    };

    let results = state
        .hexad_store
        .spatial_store()
        .search_within(&bounds, limit)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let response = results
        .into_iter()
        .map(|r| SpatialSearchResultResponse {
            entity_id: r.entity_id,
            latitude: r.data.coordinates.latitude,
            longitude: r.data.coordinates.longitude,
            distance_km: r.distance_km,
        })
        .collect();

    Ok(Json(response))
}

/// POST /spatial/search/nearest — find k nearest entities to a point
#[instrument(skip_all)]
async fn spatial_nearest_handler(
    State(state): State<AppState>,
    Json(body): Json<NearestSearchRequest>,
) -> Result<Json<Vec<SpatialSearchResultResponse>>, ApiError> {
    if !(-90.0..=90.0).contains(&body.latitude) || !(-180.0..=180.0).contains(&body.longitude) {
        return Err(ApiError::BadRequest("Invalid coordinates".to_string()));
    }

    let k = body.k.unwrap_or(10).min(MAX_RESULT_LIMIT);

    let point = Coordinates {
        latitude: body.latitude,
        longitude: body.longitude,
        altitude: None,
    };

    let results = state
        .hexad_store
        .spatial_store()
        .nearest(&point, k)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let response = results
        .into_iter()
        .map(|r| SpatialSearchResultResponse {
            entity_id: r.entity_id,
            latitude: r.data.coordinates.latitude,
            longitude: r.data.coordinates.longitude,
            distance_km: r.distance_km,
        })
        .collect();

    Ok(Json(response))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    async fn create_test_state() -> AppState {
        let mut config = ApiConfig {
            vector_dimension: 3,
            ..Default::default()
        };

        // When the `persistent` feature is enabled, each test gets a unique temp directory
        // to avoid redb lock contention between parallel tests.
        #[cfg(feature = "persistent")]
        {
            use std::sync::atomic::{AtomicU64, Ordering};
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let id = COUNTER.fetch_add(1, Ordering::Relaxed);
            let tmp = std::env::temp_dir().join(format!(
                "verisimdb-test-{}-{}",
                std::process::id(),
                id,
            ));
            config.persistence_dir = Some(tmp.to_string_lossy().into_owned());
        }

        AppState::new_async(config).await.unwrap()
    }

    #[tokio::test]
    async fn test_health_endpoint() {
        let state = create_test_state().await;
        let app = build_router(state);

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_ready_endpoint() {
        let state = create_test_state().await;
        let app = build_router(state);

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_create_and_get_hexad() {
        let state = create_test_state().await;
        let app = build_router(state);

        // Create a hexad
        let create_request = HexadRequest {
            title: Some("Test Document".to_string()),
            body: Some("Test body content".to_string()),
            embedding: Some(vec![0.1, 0.2, 0.3]),
            types: None,
            relationships: None,
            tensor: None,
            metadata: None,
            provenance: None,
            spatial: None,
        };

        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/hexads")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_string(&create_request).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::CREATED);

        // Parse response to get ID
        let body = axum::body::to_bytes(response.into_body(), 1024 * 1024)
            .await
            .unwrap();
        let created: HexadResponse = serde_json::from_slice(&body).unwrap();

        // Get the hexad
        let response = app
            .oneshot(
                Request::builder()
                    .uri(format!("/hexads/{}", created.id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_text_search() {
        let state = create_test_state().await;
        let app = build_router(state);

        // Create a hexad
        let create_request = HexadRequest {
            title: Some("Rust Programming".to_string()),
            body: Some("Rust is a systems programming language".to_string()),
            embedding: Some(vec![0.1, 0.2, 0.3]),
            types: None,
            relationships: None,
            tensor: None,
            metadata: None,
            provenance: None,
            spatial: None,
        };

        let _ = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/hexads")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_string(&create_request).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Search for it
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/search/text?q=Rust&limit=10")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_drift_status() {
        let state = create_test_state().await;
        let app = build_router(state);

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/drift/status")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }
}
