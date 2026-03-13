// SPDX-License-Identifier: PMPL-1.0-or-later
//! HTTP API for spatial queries

use crate::config::Config;
use crate::lithoglyph;
use crate::index::{BoundingBox, SpatialEntry, SpatialIndex, SpatialQueryResult};
use anyhow::Result;
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing::info;

/// Application state shared across handlers
pub struct AppState {
    lithoglyph_client: lithoglyph::Client,
    spatial_index: SpatialIndex,
    config: Config,
}

impl AppState {
    /// Create new application state
    pub fn new(lithoglyph_client: lithoglyph::Client, spatial_index: SpatialIndex, config: Config) -> Self {
        Self {
            lithoglyph_client,
            spatial_index,
            config,
        }
    }
}

/// Start the HTTP server
pub async fn serve(state: AppState) -> Result<()> {
    let state = Arc::new(state);

    let app = Router::new()
        .route("/geo/health", get(health_handler))
        .route("/geo/within-bbox", get(bbox_handler))
        .route("/geo/within-radius", get(radius_handler))
        .route("/geo/nearest", get(nearest_handler))
        .route("/geo/reindex", post(reindex_handler))
        .route("/geo/stats", get(stats_handler))
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state.clone());

    let addr = format!("{}:{}", state.config.server.host, state.config.server.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;

    info!("Lith-Geo listening on {}", addr);

    axum::serve(listener, app).await?;

    Ok(())
}

// === Query Parameters ===

#[derive(Debug, Deserialize)]
pub struct BboxParams {
    min_lat: f64,
    min_lon: f64,
    max_lat: f64,
    max_lon: f64,
}

#[derive(Debug, Deserialize)]
pub struct RadiusParams {
    lat: f64,
    lon: f64,
    radius: f64,
    #[serde(default = "default_unit")]
    unit: String,
}

fn default_unit() -> String {
    "km".to_string()
}

#[derive(Debug, Deserialize)]
pub struct NearestParams {
    lat: f64,
    lon: f64,
    #[serde(default = "default_k")]
    k: usize,
}

fn default_k() -> usize {
    10
}

// === Response Types ===

#[derive(Debug, Serialize)]
pub struct SpatialResponse {
    query: serde_json::Value,
    results: Vec<ResultEntry>,
    index_timestamp: Option<String>,
    total_indexed: usize,
}

#[derive(Debug, Serialize)]
pub struct ResultEntry {
    lithoglyph_id: String,
    location: LocationResponse,
    distance_km: Option<f64>,
    provenance_url: String,
}

#[derive(Debug, Serialize)]
pub struct LocationResponse {
    lat: f64,
    lon: f64,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    status: String,
    lithoglyph_reachable: bool,
    index_entries: usize,
}

#[derive(Debug, Serialize)]
pub struct StatsResponse {
    entry_count: usize,
    last_rebuild: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ReindexResponse {
    status: String,
    entries_indexed: usize,
    duration_ms: u128,
}

// === Handlers ===

async fn health_handler(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    let lithoglyph_reachable = state
        .lithoglyph_client
        .health_check()
        .await
        .unwrap_or(false);

    Json(HealthResponse {
        status: "ok".to_string(),
        lithoglyph_reachable,
        index_entries: state.spatial_index.len(),
    })
}

async fn bbox_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<BboxParams>,
) -> Json<SpatialResponse> {
    let bbox = BoundingBox::new(params.min_lat, params.min_lon, params.max_lat, params.max_lon);

    let results = state.spatial_index.query_bbox(bbox);
    let stats = state.spatial_index.stats();

    Json(SpatialResponse {
        query: serde_json::json!({
            "type": "within-bbox",
            "bbox": {
                "min_lat": params.min_lat,
                "min_lon": params.min_lon,
                "max_lat": params.max_lat,
                "max_lon": params.max_lon
            }
        }),
        results: results_to_entries(&results, state.lithoglyph_client.base_url()),
        index_timestamp: stats.last_rebuild.map(|t: chrono::DateTime<chrono::Utc>| t.to_rfc3339()),
        total_indexed: stats.entry_count,
    })
}

async fn radius_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<RadiusParams>,
) -> Json<SpatialResponse> {
    let radius_km = match params.unit.as_str() {
        "m" => params.radius / 1000.0,
        "mi" => params.radius * 1.60934,
        _ => params.radius, // default km
    };

    let results = state.spatial_index.query_radius(params.lat, params.lon, radius_km);
    let stats = state.spatial_index.stats();

    Json(SpatialResponse {
        query: serde_json::json!({
            "type": "within-radius",
            "center": { "lat": params.lat, "lon": params.lon },
            "radius_km": radius_km
        }),
        results: results_to_entries(&results, state.lithoglyph_client.base_url()),
        index_timestamp: stats.last_rebuild.map(|t: chrono::DateTime<chrono::Utc>| t.to_rfc3339()),
        total_indexed: stats.entry_count,
    })
}

async fn nearest_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<NearestParams>,
) -> Json<SpatialResponse> {
    let results = state.spatial_index.query_nearest(params.lat, params.lon, params.k);
    let stats = state.spatial_index.stats();

    Json(SpatialResponse {
        query: serde_json::json!({
            "type": "nearest",
            "center": { "lat": params.lat, "lon": params.lon },
            "k": params.k
        }),
        results: results_to_entries(&results, state.lithoglyph_client.base_url()),
        index_timestamp: stats.last_rebuild.map(|t: chrono::DateTime<chrono::Utc>| t.to_rfc3339()),
        total_indexed: stats.entry_count,
    })
}

async fn reindex_handler(State(state): State<Arc<AppState>>) -> Result<Json<ReindexResponse>, StatusCode> {
    let start = std::time::Instant::now();

    // Fetch documents from Lith
    let documents = state
        .lithoglyph_client
        .fetch_collection(&state.config.lithoglyph.collection)
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch from Lith: {}", e);
            StatusCode::BAD_GATEWAY
        })?;

    // Extract spatial entries
    let entries: Vec<SpatialEntry> = documents
        .iter()
        .filter_map(|doc| {
            lithoglyph::Client::extract_location(doc, &state.config.lithoglyph.location_field)
                .map(|loc| SpatialEntry::new(doc.id.clone(), loc.lat, loc.lon))
        })
        .collect();

    let count = entries.len();

    // Rebuild index
    state.spatial_index.bulk_insert(entries);

    let duration = start.elapsed();

    info!(
        "Reindexed {} entries in {}ms",
        count,
        duration.as_millis()
    );

    Ok(Json(ReindexResponse {
        status: "ok".to_string(),
        entries_indexed: count,
        duration_ms: duration.as_millis(),
    }))
}

async fn stats_handler(State(state): State<Arc<AppState>>) -> Json<StatsResponse> {
    let stats = state.spatial_index.stats();

    Json(StatsResponse {
        entry_count: stats.entry_count,
        last_rebuild: stats.last_rebuild.map(|t: chrono::DateTime<chrono::Utc>| t.to_rfc3339()),
    })
}

// === Helpers ===

fn results_to_entries(results: &[SpatialQueryResult], lithoglyph_base_url: &str) -> Vec<ResultEntry> {
    results
        .iter()
        .map(|r| ResultEntry {
            lithoglyph_id: r.entry.lithoglyph_id.clone(),
            location: LocationResponse {
                lat: r.entry.lat(),
                lon: r.entry.lon(),
            },
            distance_km: r.distance_km,
            provenance_url: format!("{}/documents/{}", lithoglyph_base_url, r.entry.lithoglyph_id),
        })
        .collect()
}
