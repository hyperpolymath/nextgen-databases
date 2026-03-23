// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
//! Lith Studio — Gossamer backend
//!
//! Zero-friction interface for Lith with GQLdt. This is the Gossamer backend
//! that bridges the ReScript UI to Lith. All 11 commands (migrated from Tauri)
//! are registered as Gossamer IPC handlers with identical JSON contracts.

#![forbid(unsafe_code)]

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ============================================================================
// Service Status Types
// ============================================================================

/// Status of external service dependencies.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceStatus {
    pub lithoglyph: ServiceInfo,
    pub gqldt: ServiceInfo,
    pub overall_ready: bool,
    pub features: FeatureAvailability,
}

/// Information about a specific service.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceInfo {
    pub name: String,
    pub available: bool,
    pub version: Option<String>,
    pub message: String,
    pub blocking_milestone: Option<String>,
}

/// Which features are currently available.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureAvailability {
    pub schema_builder: bool,
    pub gqldt_generation: bool,
    pub gqldt_validation: bool,
    pub query_execution: bool,
    pub data_entry: bool,
    pub normalization: bool,
    pub proof_assistant: bool,
}

// ============================================================================
// Schema Types
// ============================================================================

/// Schema field definition from the UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldDef {
    pub name: String,
    pub field_type: String,
    pub min: Option<i64>,
    pub max: Option<i64>,
    pub required: bool,
}

/// Collection definition from the UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectionDef {
    pub name: String,
    pub fields: Vec<FieldDef>,
}

/// Validation result.
#[derive(Debug, Serialize, Deserialize)]
pub struct ValidationResult {
    pub valid: bool,
    pub errors: Vec<String>,
    pub proofs_generated: Vec<String>,
}

// ============================================================================
// Query Types
// ============================================================================

/// Query filter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryFilter {
    pub field: String,
    pub operator: String,
    pub value: String,
}

/// Query definition.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryDef {
    pub collection: String,
    pub filters: Vec<QueryFilter>,
    pub limit: Option<i64>,
    pub include_provenance: bool,
}

/// Query result row.
#[derive(Debug, Serialize, Deserialize)]
pub struct QueryRow {
    pub data: HashMap<String, String>,
}

/// Query execution result.
#[derive(Debug, Serialize, Deserialize)]
pub struct QueryResult {
    pub rows: Vec<QueryRow>,
    pub total: i64,
    pub execution_time_ms: i64,
}

// ============================================================================
// Data Entry Types
// ============================================================================

/// Document with provenance.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentWithProvenance {
    pub collection: String,
    pub data: HashMap<String, String>,
    pub provenance: ProvenanceInfo,
}

/// Provenance metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProvenanceInfo {
    pub source: String,
    pub rationale: String,
    pub confidence: i32,
}

/// Insert result.
#[derive(Debug, Serialize, Deserialize)]
pub struct InsertResult {
    pub success: bool,
    pub document_id: Option<String>,
    pub message: String,
    pub proofs: Vec<String>,
}

// ============================================================================
// Normalization Types
// ============================================================================

/// Functional dependency.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionalDependency {
    pub determinant: Vec<String>,
    pub dependent: Vec<String>,
    pub confidence: f64,
    pub discovered: bool,
}

/// Normal form level.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NormalForm {
    First,
    Second,
    Third,
    BCNF,
    Fourth,
    Fifth,
}

/// Normalization proposal.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizationProposal {
    pub id: String,
    pub current_nf: String,
    pub target_nf: String,
    pub violating_fds: Vec<FunctionalDependency>,
    pub proposed_tables: Vec<TableChange>,
    pub narrative: String,
    pub is_lossless: bool,
    pub preserves_fds: bool,
}

/// Proposed table change.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TableChange {
    pub name: String,
    pub fields: Vec<String>,
    pub reason: String,
}

/// FD discovery result.
#[derive(Debug, Serialize, Deserialize)]
pub struct DiscoveryResult {
    pub fds: Vec<FunctionalDependency>,
    pub current_nf: String,
    pub proposals: Vec<NormalizationProposal>,
}

// ============================================================================
// Proof Types
// ============================================================================

/// Proof obligation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofObligation {
    pub id: String,
    pub description: String,
    pub formal_statement: String,
    pub status: String,
    pub suggested_tactic: Option<String>,
    pub explanation: String,
}

/// Constraint violation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstraintViolation {
    pub field: String,
    pub constraint: String,
    pub value: String,
    pub severity: String,
    pub explanation: String,
    pub suggested_fixes: Vec<SuggestedFix>,
}

/// Suggested fix for a violation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestedFix {
    pub description: String,
    pub code: String,
    pub confidence: i32,
}

/// Application information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppInfo {
    pub name: String,
    pub version: String,
    pub description: String,
    pub license: String,
    pub repository: String,
}

// ============================================================================
// Command Handlers — Schema
// ============================================================================

/// Generate GQLdt code from a visual collection definition.
///
/// Expects JSON: `{ "collection": { "name": "...", "fields": [...] } }`
/// Returns: GQLdt source code string.
fn handle_generate_gqldt(payload: serde_json::Value) -> Result<serde_json::Value, String> {
    let collection: CollectionDef = serde_json::from_value(
        payload.get("collection").cloned().unwrap_or(payload.clone()),
    )
    .map_err(|e| format!("invalid collection definition: {e}"))?;

    let mut gql = format!(
        "CREATE COLLECTION {} (\n  id : UUID",
        collection.name
    );

    for field in &collection.fields {
        let type_str = match field.field_type.as_str() {
            "number" => {
                if let (Some(min), Some(max)) = (field.min, field.max) {
                    format!("BoundedNat {} {}", min, max)
                } else {
                    "Int".to_string()
                }
            }
            "text" => {
                if field.required {
                    "NonEmptyString".to_string()
                } else {
                    "Option String".to_string()
                }
            }
            "confidence" => "Confidence".to_string(),
            "prompt_scores" => "PromptScores".to_string(),
            _ => "String".to_string(),
        };

        gql.push_str(&format!(",\n  {} : {}", field.name, type_str));
    }

    gql.push_str("\n) WITH DEPENDENT_TYPES, PROVENANCE_TRACKING;");

    Ok(serde_json::Value::String(gql))
}

/// Validate GQLdt code using Lean 4 type checker.
///
/// Expects JSON: `{ "code": "..." }`
/// Returns: ValidationResult.
fn handle_validate_gqldt(payload: serde_json::Value) -> Result<serde_json::Value, String> {
    let code = payload
        .get("code")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    // TODO: Call Lean 4 via subprocess or FFI
    // For now, return a placeholder
    let proofs = if code.contains("BoundedNat") {
        vec!["bounds_valid".to_string()]
    } else {
        vec![]
    };

    let result = ValidationResult {
        valid: true,
        errors: vec![],
        proofs_generated: proofs,
    };

    serde_json::to_value(&result).map_err(|e| e.to_string())
}

// ============================================================================
// Command Handlers — Query
// ============================================================================

/// Execute a query.
///
/// Expects JSON: `{ "query": { "collection": "...", "filters": [...], ... } }`
/// Returns: QueryResult.
fn handle_execute_query(_payload: serde_json::Value) -> Result<serde_json::Value, String> {
    // TODO: Connect to Lith and execute query
    let result = QueryResult {
        rows: vec![],
        total: 0,
        execution_time_ms: 5,
    };

    serde_json::to_value(&result).map_err(|e| e.to_string())
}

/// Explain a query plan.
///
/// Expects JSON: `{ "query": { "collection": "...", "filters": [...], ... } }`
/// Returns: Explanation string.
fn handle_explain_query(payload: serde_json::Value) -> Result<serde_json::Value, String> {
    let query: QueryDef = serde_json::from_value(
        payload.get("query").cloned().unwrap_or(payload.clone()),
    )
    .map_err(|e| format!("invalid query definition: {e}"))?;

    let explanation = format!(
        "EXPLAIN for {} with {} filters",
        query.collection,
        query.filters.len()
    );

    Ok(serde_json::Value::String(explanation))
}

// ============================================================================
// Command Handlers — Data Entry
// ============================================================================

/// Insert a document with provenance.
///
/// Expects JSON: `{ "doc": { "collection": "...", "data": {...}, "provenance": {...} } }`
/// Returns: InsertResult.
fn handle_insert_document(_payload: serde_json::Value) -> Result<serde_json::Value, String> {
    // TODO: Connect to Lith and insert
    let doc_id = format!("doc_{}", uuid::Uuid::new_v4());

    let result = InsertResult {
        success: true,
        document_id: Some(doc_id),
        message: "Document inserted with provenance tracking".to_string(),
        proofs: vec!["constraints_satisfied".to_string()],
    };

    serde_json::to_value(&result).map_err(|e| e.to_string())
}

/// Validate a document against schema constraints.
///
/// Expects JSON: `{ "collection": "...", "data": {...} }`
/// Returns: Array of ConstraintViolation (empty = valid).
fn handle_validate_document(_payload: serde_json::Value) -> Result<serde_json::Value, String> {
    // TODO: Validate against actual schema
    let violations: Vec<ConstraintViolation> = vec![];
    serde_json::to_value(&violations).map_err(|e| e.to_string())
}

// ============================================================================
// Command Handlers — Normalization
// ============================================================================

/// Discover functional dependencies from data.
///
/// Expects JSON: `{ "collection": "...", "confidence_threshold": 0.8 }`
/// Returns: DiscoveryResult.
fn handle_discover_fds(_payload: serde_json::Value) -> Result<serde_json::Value, String> {
    // TODO: Connect to Form.Normalizer and discover FDs
    let fds = vec![FunctionalDependency {
        determinant: vec!["id".to_string()],
        dependent: vec!["name".to_string(), "email".to_string()],
        confidence: 1.0,
        discovered: true,
    }];

    let result = DiscoveryResult {
        fds,
        current_nf: "2NF".to_string(),
        proposals: vec![],
    };

    serde_json::to_value(&result).map_err(|e| e.to_string())
}

/// Apply a normalization proposal.
///
/// Expects JSON: `{ "proposal_id": "..." }`
/// Returns: boolean success.
fn handle_apply_normalization(_payload: serde_json::Value) -> Result<serde_json::Value, String> {
    // TODO: Apply normalization with rollback support
    Ok(serde_json::Value::Bool(true))
}

// ============================================================================
// Command Handlers — Proofs
// ============================================================================

/// Get proof obligations for a schema.
///
/// Expects JSON: `{ "collection": "..." }`
/// Returns: Array of ProofObligation.
fn handle_get_proof_obligations(
    _payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    // TODO: Get actual proof obligations from Lean 4
    let obligations: Vec<ProofObligation> = vec![];
    serde_json::to_value(&obligations).map_err(|e| e.to_string())
}

/// Apply a proof tactic.
///
/// Expects JSON: `{ "obligation_id": "...", "tactic": "..." }`
/// Returns: boolean success.
fn handle_apply_tactic(_payload: serde_json::Value) -> Result<serde_json::Value, String> {
    // TODO: Apply tactic via Lean 4
    Ok(serde_json::Value::Bool(true))
}

// ============================================================================
// Command Handlers — Service Status
// ============================================================================

/// Check Lith HTTP API availability.
fn check_lithoglyph_status() -> ServiceInfo {
    // TODO: Actually ping Lith when M11 is released
    ServiceInfo {
        name: "Lith".to_string(),
        available: false,
        version: None,
        message: "Lith HTTP API not yet available. \
                  Query execution, data entry, and normalization features \
                  will be enabled when Lith M11 is released."
            .to_string(),
        blocking_milestone: Some("Lith M11".to_string()),
    }
}

/// Check GQLdt/Lean 4 availability.
fn check_gqldt_status() -> ServiceInfo {
    // TODO: Check for Lean 4 binary and GQLdt package
    ServiceInfo {
        name: "GQLdt (Lean 4)".to_string(),
        available: false,
        version: None,
        message: "GQLdt type checker not yet integrated. \
                  Type validation and proof generation will be enabled \
                  when GQLdt M5 (Zig FFI) is released."
            .to_string(),
        blocking_milestone: Some("GQLdt M5".to_string()),
    }
}

/// Check availability of backend services.
///
/// Expects JSON: `{}` (no arguments)
/// Returns: ServiceStatus.
fn handle_check_service_status(
    _payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let lithoglyph = check_lithoglyph_status();
    let gqldt = check_gqldt_status();

    let features = FeatureAvailability {
        // Schema builder works offline (generates GQLdt code locally)
        schema_builder: true,
        // GQLdt code generation works offline
        gqldt_generation: true,
        // Validation requires GQLdt/Lean 4
        gqldt_validation: gqldt.available,
        // Query execution requires Lith
        query_execution: lithoglyph.available,
        // Data entry requires Lith
        data_entry: lithoglyph.available,
        // Normalization requires Lith
        normalization: lithoglyph.available,
        // Proof assistant requires GQLdt
        proof_assistant: gqldt.available,
    };

    let overall_ready = lithoglyph.available && gqldt.available;

    let status = ServiceStatus {
        lithoglyph,
        gqldt,
        overall_ready,
        features,
    };

    serde_json::to_value(&status).map_err(|e| e.to_string())
}

/// Get app version and build info.
///
/// Expects JSON: `{}` (no arguments)
/// Returns: AppInfo.
fn handle_get_app_info(_payload: serde_json::Value) -> Result<serde_json::Value, String> {
    let info = AppInfo {
        name: "Lith Studio".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        description: "Zero-friction interface for Lith with dependently-typed GQL".to_string(),
        license: "PMPL-1.0-or-later".to_string(),
        repository: "https://github.com/hyperpolymath/lithoglyph-studio".to_string(),
    };

    serde_json::to_value(&info).map_err(|e| e.to_string())
}

// ============================================================================
// Main — Gossamer application entry point
// ============================================================================

fn main() -> Result<(), gossamer_rs::Error> {
    let mut app = gossamer_rs::App::new("Lith Studio", 1200, 800)?;

    // Service status commands
    app.command("check_service_status", handle_check_service_status);
    app.command("get_app_info", handle_get_app_info);

    // Schema commands
    app.command("generate_gqldt", handle_generate_gqldt);
    app.command("validate_gqldt", handle_validate_gqldt);

    // Query commands
    app.command("execute_query", handle_execute_query);
    app.command("explain_query", handle_explain_query);

    // Data entry commands
    app.command("insert_document", handle_insert_document);
    app.command("validate_document", handle_validate_document);

    // Normalization commands
    app.command("discover_fds", handle_discover_fds);
    app.command("apply_normalization", handle_apply_normalization);

    // Proof commands
    app.command("get_proof_obligations", handle_get_proof_obligations);
    app.command("apply_tactic", handle_apply_tactic);

    // Load the frontend from dist/
    app.navigate("dist/index.html")?;

    // Run the event loop (blocks until window is closed)
    app.run();
    Ok(())
}
