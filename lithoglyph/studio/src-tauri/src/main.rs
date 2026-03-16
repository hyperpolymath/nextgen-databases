// SPDX-License-Identifier: PMPL-1.0-or-later
//! Lith Studio - Zero-friction interface for Lith with GQLdt
//!
//! This is the Tauri backend that bridges the ReScript UI to Lith.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#![forbid(unsafe_code)]
use serde::{Deserialize, Serialize};

// ============================================================================
// Service Status Types
// ============================================================================

/// Status of external service dependencies
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceStatus {
    pub lithoglyph: ServiceInfo,
    pub gqldt: ServiceInfo,
    pub overall_ready: bool,
    pub features: FeatureAvailability,
}

/// Information about a specific service
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceInfo {
    pub name: String,
    pub available: bool,
    pub version: Option<String>,
    pub message: String,
    pub blocking_milestone: Option<String>,
}

/// Which features are currently available
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

/// Schema field definition from the UI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldDef {
    pub name: String,
    pub field_type: String,
    pub min: Option<i64>,
    pub max: Option<i64>,
    pub required: bool,
}

/// Collection definition from the UI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectionDef {
    pub name: String,
    pub fields: Vec<FieldDef>,
}

/// Validation result
#[derive(Debug, Serialize, Deserialize)]
pub struct ValidationResult {
    pub valid: bool,
    pub errors: Vec<String>,
    pub proofs_generated: Vec<String>,
}

// ============================================================================
// Query Types
// ============================================================================

/// Query filter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryFilter {
    pub field: String,
    pub operator: String,
    pub value: String,
}

/// Query definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryDef {
    pub collection: String,
    pub filters: Vec<QueryFilter>,
    pub limit: Option<i64>,
    pub include_provenance: bool,
}

/// Query result row
#[derive(Debug, Serialize, Deserialize)]
pub struct QueryRow {
    pub data: std::collections::HashMap<String, String>,
}

/// Query execution result
#[derive(Debug, Serialize, Deserialize)]
pub struct QueryResult {
    pub rows: Vec<QueryRow>,
    pub total: i64,
    pub execution_time_ms: i64,
}

// ============================================================================
// Data Entry Types
// ============================================================================

/// Document with provenance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentWithProvenance {
    pub collection: String,
    pub data: std::collections::HashMap<String, String>,
    pub provenance: ProvenanceInfo,
}

/// Provenance metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProvenanceInfo {
    pub source: String,
    pub rationale: String,
    pub confidence: i32,
}

/// Insert result
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

/// Functional dependency
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionalDependency {
    pub determinant: Vec<String>,
    pub dependent: Vec<String>,
    pub confidence: f64,
    pub discovered: bool,
}

/// Normal form level
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NormalForm {
    First,
    Second,
    Third,
    BCNF,
    Fourth,
    Fifth,
}

/// Normalization proposal
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

/// Proposed table change
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TableChange {
    pub name: String,
    pub fields: Vec<String>,
    pub reason: String,
}

/// FD discovery result
#[derive(Debug, Serialize, Deserialize)]
pub struct DiscoveryResult {
    pub fds: Vec<FunctionalDependency>,
    pub current_nf: String,
    pub proposals: Vec<NormalizationProposal>,
}

// ============================================================================
// Proof Types
// ============================================================================

/// Proof obligation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofObligation {
    pub id: String,
    pub description: String,
    pub formal_statement: String,
    pub status: String,
    pub suggested_tactic: Option<String>,
    pub explanation: String,
}

/// Constraint violation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstraintViolation {
    pub field: String,
    pub constraint: String,
    pub value: String,
    pub severity: String,
    pub explanation: String,
    pub suggested_fixes: Vec<SuggestedFix>,
}

/// Suggested fix for a violation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestedFix {
    pub description: String,
    pub code: String,
    pub confidence: i32,
}

// ============================================================================
// Tauri Commands - Schema
// ============================================================================

/// Generate GQLdt code from a visual collection definition
#[tauri::command]
fn generate_gqldt(collection: CollectionDef) -> Result<String, String> {
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

    Ok(gql)
}

/// Validate GQLdt code using Lean 4 type checker
#[tauri::command]
fn validate_gqldt(code: String) -> Result<ValidationResult, String> {
    // TODO: Call Lean 4 via subprocess or FFI
    // For now, return a placeholder
    let proofs = if code.contains("BoundedNat") {
        vec!["bounds_valid".to_string()]
    } else {
        vec![]
    };

    Ok(ValidationResult {
        valid: true,
        errors: vec![],
        proofs_generated: proofs,
    })
}

// ============================================================================
// Tauri Commands - Query
// ============================================================================

/// Execute a query
#[tauri::command]
fn execute_query(_query: QueryDef) -> Result<QueryResult, String> {
    // TODO: Connect to Lith and execute query
    // For now, return placeholder
    Ok(QueryResult {
        rows: vec![],
        total: 0,
        execution_time_ms: 5,
    })
}

/// Explain a query plan
#[tauri::command]
fn explain_query(query: QueryDef) -> Result<String, String> {
    // TODO: Generate query explanation
    Ok(format!(
        "EXPLAIN for {} with {} filters",
        query.collection,
        query.filters.len()
    ))
}

// ============================================================================
// Tauri Commands - Data Entry
// ============================================================================

/// Insert a document with provenance
#[tauri::command]
fn insert_document(_doc: DocumentWithProvenance) -> Result<InsertResult, String> {
    // TODO: Connect to Lith and insert
    // For now, return placeholder
    let doc_id = format!("doc_{}", uuid::Uuid::new_v4());

    Ok(InsertResult {
        success: true,
        document_id: Some(doc_id),
        message: "Document inserted with provenance tracking".to_string(),
        proofs: vec!["constraints_satisfied".to_string()],
    })
}

/// Validate a document against schema constraints
#[tauri::command]
fn validate_document(
    _collection: String,
    _data: std::collections::HashMap<String, String>,
) -> Result<Vec<ConstraintViolation>, String> {
    // TODO: Validate against actual schema
    // For now, return empty (no violations)
    Ok(vec![])
}

// ============================================================================
// Tauri Commands - Normalization
// ============================================================================

/// Discover functional dependencies from data
#[tauri::command]
fn discover_fds(
    _collection: String,
    _confidence_threshold: f64,
) -> Result<DiscoveryResult, String> {
    // TODO: Connect to Form.Normalizer and discover FDs
    // For now, return placeholder with example FDs
    let fds = vec![
        FunctionalDependency {
            determinant: vec!["id".to_string()],
            dependent: vec!["name".to_string(), "email".to_string()],
            confidence: 1.0,
            discovered: true,
        },
    ];

    Ok(DiscoveryResult {
        fds,
        current_nf: "2NF".to_string(),
        proposals: vec![],
    })
}

/// Apply a normalization proposal
#[tauri::command]
fn apply_normalization(_proposal_id: String) -> Result<bool, String> {
    // TODO: Apply normalization with rollback support
    Ok(true)
}

// ============================================================================
// Tauri Commands - Proofs
// ============================================================================

/// Get proof obligations for a schema
#[tauri::command]
fn get_proof_obligations(_collection: String) -> Result<Vec<ProofObligation>, String> {
    // TODO: Get actual proof obligations from Lean 4
    Ok(vec![])
}

/// Apply a proof tactic
#[tauri::command]
fn apply_tactic(_obligation_id: String, _tactic: String) -> Result<bool, String> {
    // TODO: Apply tactic via Lean 4
    Ok(true)
}

// ============================================================================
// Tauri Commands - Service Status
// ============================================================================

/// Check availability of backend services
#[tauri::command]
fn check_service_status() -> ServiceStatus {
    // Check Lith availability
    let lithoglyph = check_lithoglyph_status();

    // Check GQLdt availability
    let gqldt = check_gqldt_status();

    // Determine which features are available
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

    ServiceStatus {
        lithoglyph,
        gqldt,
        overall_ready,
        features,
    }
}

/// Check Lith HTTP API availability
fn check_lithoglyph_status() -> ServiceInfo {
    // TODO: Actually ping Lith when M11 is released
    // For now, return unavailable with informative message
    ServiceInfo {
        name: "Lith".to_string(),
        available: false,
        version: None,
        message: "Lith HTTP API not yet available. \
                  Query execution, data entry, and normalization features \
                  will be enabled when Lith M11 is released.".to_string(),
        blocking_milestone: Some("Lith M11".to_string()),
    }
}

/// Check GQLdt/Lean 4 availability
fn check_gqldt_status() -> ServiceInfo {
    // TODO: Check for Lean 4 binary and GQLdt package
    // For now, return unavailable with informative message
    ServiceInfo {
        name: "GQLdt (Lean 4)".to_string(),
        available: false,
        version: None,
        message: "GQLdt type checker not yet integrated. \
                  Type validation and proof generation will be enabled \
                  when GQLdt M5 (Zig FFI) is released.".to_string(),
        blocking_milestone: Some("GQLdt M5".to_string()),
    }
}

/// Get app version and build info
#[tauri::command]
fn get_app_info() -> AppInfo {
    AppInfo {
        name: "Lith Studio".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        description: "Zero-friction interface for Lith with dependently-typed GQL".to_string(),
        license: "PMPL-1.0-or-later".to_string(),
        repository: "https://github.com/hyperpolymath/lithoglyph-studio".to_string(),
    }
}

/// Application information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppInfo {
    pub name: String,
    pub version: String,
    pub description: String,
    pub license: String,
    pub repository: String,
}

// ============================================================================
// Main
// ============================================================================

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            // Service status
            check_service_status,
            get_app_info,
            // Schema
            generate_gqldt,
            validate_gqldt,
            // Query
            execute_query,
            explain_query,
            // Data entry
            insert_document,
            validate_document,
            // Normalization
            discover_fds,
            apply_normalization,
            // Proofs
            get_proof_obligations,
            apply_tactic,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Lith Studio");
}
