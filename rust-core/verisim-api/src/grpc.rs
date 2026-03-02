// SPDX-License-Identifier: PMPL-1.0-or-later
//! gRPC API for VeriSimDB.
//!
//! Exposes planner and hexad operations via gRPC on a separate port (50051).

use tonic::{Request, Response, Status};
use tracing::error;

use verisim_planner::LogicalPlan;

use crate::AppState;

// Pre-generated protobuf types (from proto/verisim.proto via prost-build).
// Using a committed file eliminates the protoc build dependency.
#[path = "proto/verisim.rs"]
pub mod proto;

use proto::veri_sim_planner_server::{VeriSimPlanner, VeriSimPlannerServer};
use proto::veri_sim_hexad_server::{VeriSimHexad, VeriSimHexadServer};

// ============================================================================
// Planner gRPC Service
// ============================================================================

pub struct PlannerService {
    state: AppState,
}

impl PlannerService {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl VeriSimPlanner for PlannerService {
    async fn optimize_plan(
        &self,
        request: Request<proto::LogicalPlanRequest>,
    ) -> Result<Response<proto::PhysicalPlanResponse>, Status> {
        let req = request.into_inner();
        let logical: LogicalPlan = serde_json::from_str(&req.plan_json)
            .map_err(|e| Status::invalid_argument(format!("Invalid plan JSON: {}", e)))?;

        let planner = self.state.planner.lock()
            .map_err(|_| { error!("Planner lock poisoned in gRPC"); Status::internal("Internal server error") })?;
        let physical = planner
            .optimize(&logical)
            .map_err(|e| Status::invalid_argument(e.to_string()))?;

        let steps: Vec<proto::PlanStepMsg> = physical
            .steps
            .iter()
            .map(|s| proto::PlanStepMsg {
                step: s.step as i32,
                operation: s.operation.clone(),
                modality: s.modality.to_string(),
                time_ms: s.cost.time_ms,
                estimated_rows: s.cost.estimated_rows,
                selectivity: s.cost.selectivity,
                optimization_hint: s.optimization_hint.clone().unwrap_or_default(),
            })
            .collect();

        Ok(Response::new(proto::PhysicalPlanResponse {
            steps,
            strategy: format!("{:?}", physical.strategy),
            total_time_ms: physical.total_cost.time_ms,
            total_estimated_rows: physical.total_cost.estimated_rows,
            notes: physical.notes.clone(),
        }))
    }

    async fn explain_plan(
        &self,
        request: Request<proto::LogicalPlanRequest>,
    ) -> Result<Response<proto::ExplainResponse>, Status> {
        let req = request.into_inner();
        let logical: LogicalPlan = serde_json::from_str(&req.plan_json)
            .map_err(|e| Status::invalid_argument(format!("Invalid plan JSON: {}", e)))?;

        let planner = self.state.planner.lock()
            .map_err(|_| { error!("Planner lock poisoned in gRPC"); Status::internal("Internal server error") })?;
        let explain = planner
            .explain(&logical)
            .map_err(|e| Status::invalid_argument(e.to_string()))?;

        let steps: Vec<proto::PlanStepMsg> = explain
            .steps
            .iter()
            .map(|s| proto::PlanStepMsg {
                step: s.step as i32,
                operation: s.operation.clone(),
                modality: s.modality.to_string(),
                time_ms: s.estimated_cost_ms,
                estimated_rows: s.estimated_rows,
                selectivity: s.estimated_selectivity,
                optimization_hint: s.optimization_hint.clone().unwrap_or_default(),
            })
            .collect();

        let cost_breakdown: Vec<proto::ModalityCostMsg> = explain
            .cost_breakdown
            .iter()
            .map(|cb| proto::ModalityCostMsg {
                modality: cb.modality.to_string(),
                time_ms: cb.time_ms,
                percentage: cb.percentage,
            })
            .collect();

        let hints: Vec<proto::PerformanceHintMsg> = explain
            .performance_hints
            .iter()
            .map(|h| proto::PerformanceHintMsg {
                severity: h.severity.clone(),
                message: h.message.clone(),
            })
            .collect();

        Ok(Response::new(proto::ExplainResponse {
            steps,
            cost_breakdown,
            performance_hints: hints,
            total_cost_ms: explain.total_cost_ms,
            strategy: explain.strategy.clone(),
            text_output: explain.text_output.clone(),
        }))
    }

    async fn get_config(
        &self,
        _request: Request<proto::Empty>,
    ) -> Result<Response<proto::PlannerConfigResponse>, Status> {
        let planner = self.state.planner.lock()
            .map_err(|_| { error!("Planner lock poisoned in gRPC"); Status::internal("Internal server error") })?;
        let cfg = planner.config();

        Ok(Response::new(proto::PlannerConfigResponse {
            global_mode: format!("{:?}", cfg.global_mode),
            statistics_weight: cfg.statistics_weight,
            enable_adaptive: cfg.enable_adaptive,
            parallel_threshold: cfg.parallel_threshold as i32,
        }))
    }

    async fn set_config(
        &self,
        request: Request<proto::PlannerConfigRequest>,
    ) -> Result<Response<proto::PlannerConfigResponse>, Status> {
        let req = request.into_inner();
        let mut planner = self.state.planner.lock()
            .map_err(|_| { error!("Planner lock poisoned in gRPC"); Status::internal("Internal server error") })?;

        let mut cfg = planner.config().clone();
        if !req.global_mode.is_empty() {
            cfg.global_mode = match req.global_mode.to_lowercase().as_str() {
                "conservative" => verisim_planner::OptimizationMode::Conservative,
                "aggressive" => verisim_planner::OptimizationMode::Aggressive,
                _ => verisim_planner::OptimizationMode::Balanced,
            };
        }
        if req.statistics_weight > 0.0 {
            cfg.statistics_weight = req.statistics_weight;
        }
        cfg.enable_adaptive = req.enable_adaptive;
        if req.parallel_threshold > 0 {
            cfg.parallel_threshold = req.parallel_threshold as usize;
        }
        planner.set_config(cfg);

        let cfg = planner.config();
        Ok(Response::new(proto::PlannerConfigResponse {
            global_mode: format!("{:?}", cfg.global_mode),
            statistics_weight: cfg.statistics_weight,
            enable_adaptive: cfg.enable_adaptive,
            parallel_threshold: cfg.parallel_threshold as i32,
        }))
    }

    async fn get_stats(
        &self,
        _request: Request<proto::Empty>,
    ) -> Result<Response<proto::StatsResponse>, Status> {
        let planner = self.state.planner.lock()
            .map_err(|_| { error!("Planner lock poisoned in gRPC"); Status::internal("Internal server error") })?;

        let stores: Vec<proto::StoreStatsMsg> = verisim_planner::Modality::ALL
            .iter()
            .filter_map(|m| {
                planner.stats().get(*m).map(|s| proto::StoreStatsMsg {
                    modality: m.to_string(),
                    total_rows: s.total_rows,
                    avg_latency_ms: s.avg_latency_ms,
                    avg_rows_returned: s.avg_rows_returned,
                    query_count: s.query_count,
                })
            })
            .collect();

        Ok(Response::new(proto::StatsResponse { stores }))
    }
}

// ============================================================================
// Hexad gRPC Service
// ============================================================================

pub struct HexadService {
    state: AppState,
}

impl HexadService {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl VeriSimHexad for HexadService {
    async fn create(
        &self,
        request: Request<proto::HexadCreateRequest>,
    ) -> Result<Response<proto::HexadResponse>, Status> {
        let req = request.into_inner();
        let mut input = verisim_hexad::HexadInput::default();

        if !req.title.is_empty() {
            input.document = Some(verisim_hexad::HexadDocumentInput {
                title: req.title,
                body: req.body,
                fields: std::collections::HashMap::new(),
            });
        }
        if !req.embedding.is_empty() {
            input.vector = Some(verisim_hexad::HexadVectorInput {
                embedding: req.embedding,
                model: None,
            });
        }
        if !req.types.is_empty() {
            input.semantic = Some(verisim_hexad::HexadSemanticInput {
                types: req.types,
                properties: std::collections::HashMap::new(),
            });
        }

        use verisim_hexad::HexadStore;
        let h = self
            .state
            .hexad_store
            .create(input)
            .await
            .map_err(|e| {
                error!(error = %e, "gRPC hexad creation failed");
                Status::internal("Internal server error")
            })?;

        Ok(Response::new(hexad_to_proto(&h)))
    }

    async fn get(
        &self,
        request: Request<proto::HexadIdRequest>,
    ) -> Result<Response<proto::HexadResponse>, Status> {
        let id = request.into_inner().id;
        let hexad_id = verisim_hexad::HexadId::new(&id);

        use verisim_hexad::HexadStore;
        let h = self
            .state
            .hexad_store
            .get(&hexad_id)
            .await
            .map_err(|e| {
                error!(error = %e, "gRPC hexad get failed");
                Status::internal("Internal server error")
            })?
            .ok_or_else(|| Status::not_found(format!("Hexad {} not found", id)))?;

        Ok(Response::new(hexad_to_proto(&h)))
    }

    async fn update(
        &self,
        request: Request<proto::HexadUpdateRequest>,
    ) -> Result<Response<proto::HexadResponse>, Status> {
        let req = request.into_inner();
        let hexad_id = verisim_hexad::HexadId::new(&req.id);

        let mut input = verisim_hexad::HexadInput::default();
        if !req.title.is_empty() {
            input.document = Some(verisim_hexad::HexadDocumentInput {
                title: req.title,
                body: req.body,
                fields: std::collections::HashMap::new(),
            });
        }
        if !req.embedding.is_empty() {
            input.vector = Some(verisim_hexad::HexadVectorInput {
                embedding: req.embedding,
                model: None,
            });
        }
        if !req.types.is_empty() {
            input.semantic = Some(verisim_hexad::HexadSemanticInput {
                types: req.types,
                properties: std::collections::HashMap::new(),
            });
        }

        use verisim_hexad::HexadStore;
        let h = self
            .state
            .hexad_store
            .update(&hexad_id, input)
            .await
            .map_err(|e| {
                error!(error = %e, "gRPC hexad update failed");
                Status::internal("Internal server error")
            })?;

        Ok(Response::new(hexad_to_proto(&h)))
    }

    async fn delete(
        &self,
        request: Request<proto::HexadIdRequest>,
    ) -> Result<Response<proto::Empty>, Status> {
        let id = request.into_inner().id;
        let hexad_id = verisim_hexad::HexadId::new(&id);

        use verisim_hexad::HexadStore;
        self.state
            .hexad_store
            .delete(&hexad_id)
            .await
            .map_err(|e| {
                error!(error = %e, "gRPC hexad deletion failed");
                Status::internal("Internal server error")
            })?;

        Ok(Response::new(proto::Empty {}))
    }

    async fn search_text(
        &self,
        request: Request<proto::TextSearchRequest>,
    ) -> Result<Response<proto::SearchResponse>, Status> {
        let req = request.into_inner();
        let limit = if req.limit > 0 { req.limit as usize } else { 10 };

        use verisim_hexad::HexadStore;
        let hexads = self
            .state
            .hexad_store
            .search_text(&req.query, limit)
            .await
            .map_err(|e| {
                error!(error = %e, "gRPC text search failed");
                Status::internal("Internal server error")
            })?;

        let results: Vec<proto::SearchResultMsg> = hexads
            .iter()
            .enumerate()
            .map(|(i, h)| proto::SearchResultMsg {
                id: h.id.to_string(),
                score: 1.0 - (i as f32 * 0.1),
                title: h
                    .document
                    .as_ref()
                    .map(|d| d.title.clone())
                    .unwrap_or_default(),
            })
            .collect();

        Ok(Response::new(proto::SearchResponse { results }))
    }

    async fn search_vector(
        &self,
        request: Request<proto::VectorSearchRequest>,
    ) -> Result<Response<proto::SearchResponse>, Status> {
        let req = request.into_inner();
        let k = if req.k > 0 { req.k as usize } else { 10 };

        use verisim_hexad::HexadStore;
        let hexads = self
            .state
            .hexad_store
            .search_similar(&req.vector, k)
            .await
            .map_err(|e| {
                error!(error = %e, "gRPC vector search failed");
                Status::internal("Internal server error")
            })?;

        let results: Vec<proto::SearchResultMsg> = hexads
            .iter()
            .enumerate()
            .map(|(i, h)| proto::SearchResultMsg {
                id: h.id.to_string(),
                score: 1.0 - (i as f32 * 0.1),
                title: h
                    .document
                    .as_ref()
                    .map(|d| d.title.clone())
                    .unwrap_or_default(),
            })
            .collect();

        Ok(Response::new(proto::SearchResponse { results }))
    }
}

// ============================================================================
// Helpers
// ============================================================================

fn hexad_to_proto(h: &verisim_hexad::Hexad) -> proto::HexadResponse {
    proto::HexadResponse {
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
    }
}

/// Build gRPC server routes. Returns a tonic Router that can be served.
pub fn build_grpc_router(state: AppState) -> tonic::transport::server::Router {
    let planner_svc = VeriSimPlannerServer::new(PlannerService::new(state.clone()));
    let hexad_svc = VeriSimHexadServer::new(HexadService::new(state));

    tonic::transport::Server::builder()
        .add_service(planner_svc)
        .add_service(hexad_svc)
}
