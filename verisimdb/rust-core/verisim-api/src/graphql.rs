// SPDX-License-Identifier: PMPL-1.0-or-later
//! GraphQL API for VeriSimDB.
//!
//! Exposes planner, hexad, search, drift, and normalizer operations
//! via a GraphQL schema at `/graphql`.

use async_graphql::{
    Context, EmptySubscription, InputObject, Object, Schema, SimpleObject,
    http::GraphiQLSource,
};
use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use tracing::error;
use axum::{
    extract::State as AxumState,
    response::{Html, IntoResponse},
    routing::{get, post},
    Router,
};

use verisim_planner::{
    ExplainOutput as PlannerExplainOutput,
    LogicalPlan,
};

use crate::AppState;

// ============================================================================
// GraphQL Output Types
// ============================================================================

/// Health check result.
#[derive(SimpleObject)]
struct Health {
    status: String,
    version: String,
    uptime_seconds: u64,
}

/// Hexad summary.
#[derive(SimpleObject)]
struct Hexad {
    id: String,
    created_at: String,
    modified_at: String,
    version: u64,
    has_graph: bool,
    has_vector: bool,
    has_tensor: bool,
    has_semantic: bool,
    has_document: bool,
    version_count: u64,
}

/// Search result entry.
#[derive(SimpleObject)]
struct SearchResult {
    id: String,
    score: f32,
    title: Option<String>,
}

/// Drift status for a single drift type.
#[derive(SimpleObject)]
struct DriftStatus {
    drift_type: String,
    current_score: f64,
    moving_average: f64,
    max_score: f64,
    measurement_count: u64,
}

/// A single step in a physical plan.
#[derive(SimpleObject)]
struct PlanStep {
    step: i32,
    operation: String,
    modality: String,
    time_ms: f64,
    estimated_rows: u64,
    selectivity: f64,
    optimization_hint: Option<String>,
}

/// Optimized physical plan.
#[derive(SimpleObject)]
struct PhysicalPlan {
    steps: Vec<PlanStep>,
    strategy: String,
    total_time_ms: f64,
    total_estimated_rows: u64,
    notes: Vec<String>,
}

/// Cost breakdown for a modality.
#[derive(SimpleObject)]
struct ModalityCost {
    modality: String,
    time_ms: f64,
    percentage: f64,
}

/// Performance hint.
#[derive(SimpleObject)]
struct PerformanceHint {
    severity: String,
    message: String,
}

/// EXPLAIN output.
#[derive(SimpleObject)]
struct ExplainOutput {
    steps: Vec<PlanStep>,
    cost_breakdown: Vec<ModalityCost>,
    performance_hints: Vec<PerformanceHint>,
    total_cost_ms: f64,
    strategy: String,
    text_output: String,
}

/// Planner configuration.
#[derive(SimpleObject, Clone)]
struct PlannerConfigOutput {
    global_mode: String,
    statistics_weight: f64,
    enable_adaptive: bool,
    parallel_threshold: i32,
}

/// Store statistics for a modality.
#[derive(SimpleObject)]
struct StoreStats {
    modality: String,
    total_rows: u64,
    avg_latency_ms: f64,
    avg_rows_returned: u64,
    query_count: u64,
}

/// Full statistics snapshot.
#[derive(SimpleObject)]
struct PlannerStats {
    stores: Vec<StoreStats>,
}

// ============================================================================
// GraphQL Input Types
// ============================================================================

/// Hexad creation/update input.
#[derive(InputObject)]
struct HexadInput {
    title: Option<String>,
    body: Option<String>,
    embedding: Option<Vec<f32>>,
    types: Option<Vec<String>>,
    tensor_shape: Option<Vec<i32>>,
    tensor_data: Option<Vec<f64>>,
}

/// Planner configuration input.
#[derive(InputObject)]
struct PlannerConfigInput {
    global_mode: Option<String>,
    statistics_weight: Option<f64>,
    enable_adaptive: Option<bool>,
    parallel_threshold: Option<i32>,
}

// ============================================================================
// Query Root
// ============================================================================

pub struct QueryRoot;

#[Object]
impl QueryRoot {
    /// Health check.
    async fn health(&self, ctx: &Context<'_>) -> async_graphql::Result<Health> {
        let state = ctx.data::<AppState>()?;
        Ok(Health {
            status: "healthy".to_string(),
            version: env!("CARGO_PKG_VERSION").to_string(),
            uptime_seconds: state.start_time.elapsed().as_secs(),
        })
    }

    /// Get a hexad by ID.
    async fn hexad(&self, ctx: &Context<'_>, id: String) -> async_graphql::Result<Option<Hexad>> {
        let state = ctx.data::<AppState>()?;
        let hexad_id = verisim_hexad::HexadId::new(&id);

        use verisim_hexad::HexadStore;
        match state.hexad_store.get(&hexad_id).await {
            Ok(Some(h)) => Ok(Some(Hexad {
                id: h.id.to_string(),
                created_at: h.status.created_at.to_rfc3339(),
                modified_at: h.status.modified_at.to_rfc3339(),
                version: h.status.version,
                has_graph: h.graph_node.is_some(),
                has_vector: h.embedding.is_some(),
                has_tensor: h.tensor.is_some(),
                has_semantic: h.semantic.is_some(),
                has_document: h.document.is_some(),
                version_count: h.version_count,
            })),
            Ok(None) => Ok(None),
            Err(e) => {
                error!(error = %e, "GraphQL hexad query failed");
                Err(async_graphql::Error::new("Internal server error"))
            }
        }
    }

    /// Search by text.
    async fn search_text(
        &self,
        ctx: &Context<'_>,
        query: String,
        limit: Option<i32>,
    ) -> async_graphql::Result<Vec<SearchResult>> {
        let state = ctx.data::<AppState>()?;
        let limit = limit.unwrap_or(10) as usize;

        use verisim_hexad::HexadStore;
        let hexads = state
            .hexad_store
            .search_text(&query, limit)
            .await
            .map_err(|e| {
                error!(error = %e, "GraphQL text search failed");
                async_graphql::Error::new("Internal server error")
            })?;

        Ok(hexads
            .iter()
            .enumerate()
            .map(|(i, h)| SearchResult {
                id: h.id.to_string(),
                score: 1.0 - (i as f32 * 0.1),
                title: h.document.as_ref().map(|d| d.title.clone()),
            })
            .collect())
    }

    /// Get drift status for all drift types.
    async fn drift_status(&self, ctx: &Context<'_>) -> async_graphql::Result<Vec<DriftStatus>> {
        let state = ctx.data::<AppState>()?;
        let all_metrics = state.drift_detector.all_metrics()
            .map_err(|e| {
                error!(error = %e, "GraphQL drift status query failed");
                async_graphql::Error::new("Internal server error")
            })?;

        Ok(all_metrics
            .iter()
            .map(|(dt, m)| DriftStatus {
                drift_type: dt.to_string(),
                current_score: m.current_score,
                moving_average: m.moving_average,
                max_score: m.max_score,
                measurement_count: m.measurement_count,
            })
            .collect())
    }

    /// Get current planner configuration.
    async fn planner_config(&self, ctx: &Context<'_>) -> async_graphql::Result<PlannerConfigOutput> {
        let state = ctx.data::<AppState>()?;
        let planner = state.planner.lock().map_err(|_| { error!("Planner lock poisoned in GraphQL"); async_graphql::Error::new("Internal server error") })?;
        let cfg = planner.config();
        Ok(PlannerConfigOutput {
            global_mode: format!("{:?}", cfg.global_mode),
            statistics_weight: cfg.statistics_weight,
            enable_adaptive: cfg.enable_adaptive,
            parallel_threshold: cfg.parallel_threshold as i32,
        })
    }

    /// Get planner statistics.
    async fn planner_stats(&self, ctx: &Context<'_>) -> async_graphql::Result<PlannerStats> {
        let state = ctx.data::<AppState>()?;
        let planner = state.planner.lock().map_err(|_| { error!("Planner lock poisoned in GraphQL"); async_graphql::Error::new("Internal server error") })?;

        let stores: Vec<StoreStats> = verisim_planner::Modality::ALL
            .iter()
            .filter_map(|m| {
                planner.stats().get(*m).map(|s| StoreStats {
                    modality: m.to_string(),
                    total_rows: s.total_rows,
                    avg_latency_ms: s.avg_latency_ms,
                    avg_rows_returned: s.avg_rows_returned,
                    query_count: s.query_count,
                })
            })
            .collect();

        Ok(PlannerStats { stores })
    }

    /// EXPLAIN a logical plan.
    async fn explain_plan(
        &self,
        ctx: &Context<'_>,
        plan_json: String,
    ) -> async_graphql::Result<ExplainOutput> {
        let state = ctx.data::<AppState>()?;
        let logical: LogicalPlan = serde_json::from_str(&plan_json)
            .map_err(|e| async_graphql::Error::new(format!("Invalid plan JSON: {}", e)))?;

        let planner = state.planner.lock().map_err(|_| {
            error!("Planner lock poisoned in GraphQL explain");
            async_graphql::Error::new("Internal server error")
        })?;
        let explain = planner
            .explain(&logical)
            .map_err(|e| async_graphql::Error::new(format!("Plan error: {}", e)))?;

        Ok(convert_explain(&explain))
    }
}

// ============================================================================
// Mutation Root
// ============================================================================

pub struct MutationRoot;

#[Object]
impl MutationRoot {
    /// Create a new hexad.
    async fn create_hexad(
        &self,
        ctx: &Context<'_>,
        input: HexadInput,
    ) -> async_graphql::Result<Hexad> {
        let state = ctx.data::<AppState>()?;

        let mut hexad_input = verisim_hexad::HexadInput::default();
        if let Some(title) = &input.title {
            hexad_input.document = Some(verisim_hexad::HexadDocumentInput {
                title: title.clone(),
                body: input.body.clone().unwrap_or_default(),
                fields: std::collections::HashMap::new(),
            });
        }
        if let Some(embedding) = &input.embedding {
            hexad_input.vector = Some(verisim_hexad::HexadVectorInput {
                embedding: embedding.clone(),
                model: None,
            });
        }
        if let Some(types) = &input.types {
            hexad_input.semantic = Some(verisim_hexad::HexadSemanticInput {
                types: types.clone(),
                properties: std::collections::HashMap::new(),
            });
        }

        use verisim_hexad::HexadStore;
        let h = state
            .hexad_store
            .create(hexad_input)
            .await
            .map_err(|e| {
                error!(error = %e, "GraphQL hexad creation failed");
                async_graphql::Error::new("Internal server error")
            })?;

        Ok(Hexad {
            id: h.id.to_string(),
            created_at: h.status.created_at.to_rfc3339(),
            modified_at: h.status.modified_at.to_rfc3339(),
            version: h.status.version,
            has_graph: h.graph_node.is_some(),
            has_vector: h.embedding.is_some(),
            has_tensor: h.tensor.is_some(),
            has_semantic: h.semantic.is_some(),
            has_document: h.document.is_some(),
            version_count: h.version_count,
        })
    }

    /// Delete a hexad.
    async fn delete_hexad(&self, ctx: &Context<'_>, id: String) -> async_graphql::Result<bool> {
        let state = ctx.data::<AppState>()?;
        let hexad_id = verisim_hexad::HexadId::new(&id);

        use verisim_hexad::HexadStore;
        state
            .hexad_store
            .delete(&hexad_id)
            .await
            .map_err(|e| {
                error!(error = %e, "GraphQL hexad deletion failed");
                async_graphql::Error::new("Internal server error")
            })?;

        Ok(true)
    }

    /// Optimize a logical plan into a physical plan.
    async fn optimize_plan(
        &self,
        ctx: &Context<'_>,
        plan_json: String,
    ) -> async_graphql::Result<PhysicalPlan> {
        let state = ctx.data::<AppState>()?;
        let logical: LogicalPlan = serde_json::from_str(&plan_json)
            .map_err(|e| async_graphql::Error::new(format!("Invalid plan JSON: {}", e)))?;

        let planner = state.planner.lock().map_err(|_| { error!("Planner lock poisoned in GraphQL"); async_graphql::Error::new("Internal server error") })?;
        let physical = planner
            .optimize(&logical)
            .map_err(|e| async_graphql::Error::new(e.to_string()))?;

        Ok(convert_physical_plan(&physical))
    }

    /// Update planner configuration.
    async fn update_planner_config(
        &self,
        ctx: &Context<'_>,
        input: PlannerConfigInput,
    ) -> async_graphql::Result<PlannerConfigOutput> {
        let state = ctx.data::<AppState>()?;
        let mut planner = state.planner.lock().map_err(|_| { error!("Planner lock poisoned in GraphQL"); async_graphql::Error::new("Internal server error") })?;

        let mut cfg = planner.config().clone();
        if let Some(mode) = &input.global_mode {
            cfg.global_mode = match mode.to_lowercase().as_str() {
                "conservative" => verisim_planner::OptimizationMode::Conservative,
                "aggressive" => verisim_planner::OptimizationMode::Aggressive,
                _ => verisim_planner::OptimizationMode::Balanced,
            };
        }
        if let Some(w) = input.statistics_weight {
            cfg.statistics_weight = w;
        }
        if let Some(a) = input.enable_adaptive {
            cfg.enable_adaptive = a;
        }
        if let Some(t) = input.parallel_threshold {
            cfg.parallel_threshold = t as usize;
        }
        planner.set_config(cfg);

        let cfg = planner.config();
        Ok(PlannerConfigOutput {
            global_mode: format!("{:?}", cfg.global_mode),
            statistics_weight: cfg.statistics_weight,
            enable_adaptive: cfg.enable_adaptive,
            parallel_threshold: cfg.parallel_threshold as i32,
        })
    }
}

// ============================================================================
// Schema Construction
// ============================================================================

pub type VeriSimSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

/// Build the GraphQL schema with AppState as context data.
pub fn build_schema(state: AppState) -> VeriSimSchema {
    Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .data(state)
        .finish()
}

/// GraphQL request handler.
async fn graphql_handler(
    AxumState(schema): AxumState<VeriSimSchema>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    schema.execute(req.into_inner()).await.into()
}

/// GraphiQL playground handler.
async fn graphiql_handler() -> impl IntoResponse {
    Html(GraphiQLSource::build().endpoint("/graphql").finish())
}

/// Build the GraphQL axum router.
pub fn graphql_router(state: AppState) -> Router {
    let schema = build_schema(state);

    Router::new()
        .route("/graphql", post(graphql_handler))
        .route("/graphiql", get(graphiql_handler))
        .with_state(schema)
}

// ============================================================================
// Conversion Helpers
// ============================================================================

fn convert_physical_plan(p: &verisim_planner::PhysicalPlan) -> PhysicalPlan {
    PhysicalPlan {
        steps: p
            .steps
            .iter()
            .map(|s| PlanStep {
                step: s.step as i32,
                operation: s.operation.clone(),
                modality: s.modality.to_string(),
                time_ms: s.cost.time_ms,
                estimated_rows: s.cost.estimated_rows,
                selectivity: s.cost.selectivity,
                optimization_hint: s.optimization_hint.clone(),
            })
            .collect(),
        strategy: format!("{:?}", p.strategy),
        total_time_ms: p.total_cost.time_ms,
        total_estimated_rows: p.total_cost.estimated_rows,
        notes: p.notes.clone(),
    }
}

fn convert_explain(e: &PlannerExplainOutput) -> ExplainOutput {
    ExplainOutput {
        steps: e
            .steps
            .iter()
            .map(|s| PlanStep {
                step: s.step as i32,
                operation: s.operation.clone(),
                modality: s.modality.to_string(),
                time_ms: s.estimated_cost_ms,
                estimated_rows: s.estimated_rows,
                selectivity: s.estimated_selectivity,
                optimization_hint: s.optimization_hint.clone(),
            })
            .collect(),
        cost_breakdown: e
            .cost_breakdown
            .iter()
            .map(|cb| ModalityCost {
                modality: cb.modality.to_string(),
                time_ms: cb.time_ms,
                percentage: cb.percentage,
            })
            .collect(),
        performance_hints: e
            .performance_hints
            .iter()
            .map(|h| PerformanceHint {
                severity: h.severity.clone(),
                message: h.message.clone(),
            })
            .collect(),
        total_cost_ms: e.total_cost_ms,
        strategy: e.strategy.clone(),
        text_output: e.text_output.clone(),
    }
}
