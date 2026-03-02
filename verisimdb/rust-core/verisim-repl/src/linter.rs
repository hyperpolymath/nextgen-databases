// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! VQL linter — static analysis for VQL queries.
//!
//! Detects common issues, antipatterns, and performance pitfalls in VQL
//! queries before execution:
//!
//! - Missing LIMIT clause on unbounded queries
//! - SELECT * (all modalities) without explicit need
//! - Missing PROOF clause on sensitive modalities (Semantic)
//! - Expensive cross-modality operations without EXPLAIN
//! - Unreachable or redundant clauses
//! - TRAVERSE without DEPTH bound
//! - High estimated row count without pagination

use std::fmt;

/// Severity level for lint diagnostics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    /// Informational suggestion — not an error.
    Hint,
    /// Potential issue that may cause unexpected behaviour.
    Warning,
    /// Likely error or dangerous antipattern.
    Error,
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Severity::Hint => write!(f, "hint"),
            Severity::Warning => write!(f, "warning"),
            Severity::Error => write!(f, "error"),
        }
    }
}

/// A lint rule identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LintRule {
    /// Query lacks a LIMIT clause — may return unbounded results.
    MissingLimit,
    /// SELECT queries all modalities when fewer would suffice.
    SelectAllModalities,
    /// Semantic modality accessed without PROOF clause.
    MissingProof,
    /// TRAVERSE clause without DEPTH bound.
    UnboundedTraverse,
    /// Query uses DRIFT or CONSISTENCY without a threshold.
    MissingThreshold,
    /// ORDER BY without LIMIT (full sort on potentially large result set).
    OrderByWithoutLimit,
    /// DELETE or UPDATE without WHERE clause.
    DangerousWrite,
    /// VQL-DT PROOF type not recognized.
    UnknownProofType,
    /// Redundant WHERE clause (always true).
    RedundantWhere,
    /// Multiple modalities without EXPLAIN — consider reviewing the plan.
    MultiModalityNoExplain,
    /// FEDERATION query without specifying STORE.
    FederationWithoutStore,
}

impl fmt::Display for LintRule {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LintRule::MissingLimit => write!(f, "VQL001"),
            LintRule::SelectAllModalities => write!(f, "VQL002"),
            LintRule::MissingProof => write!(f, "VQL003"),
            LintRule::UnboundedTraverse => write!(f, "VQL004"),
            LintRule::MissingThreshold => write!(f, "VQL005"),
            LintRule::OrderByWithoutLimit => write!(f, "VQL006"),
            LintRule::DangerousWrite => write!(f, "VQL007"),
            LintRule::UnknownProofType => write!(f, "VQL008"),
            LintRule::RedundantWhere => write!(f, "VQL009"),
            LintRule::MultiModalityNoExplain => write!(f, "VQL010"),
            LintRule::FederationWithoutStore => write!(f, "VQL011"),
        }
    }
}

impl LintRule {
    /// Human-readable description of the rule.
    pub fn description(&self) -> &'static str {
        match self {
            LintRule::MissingLimit => "Query lacks LIMIT clause — may return unbounded results",
            LintRule::SelectAllModalities => "Query selects all 8 modalities — consider selecting only what you need",
            LintRule::MissingProof => "Semantic modality accessed without PROOF clause — data integrity not verified",
            LintRule::UnboundedTraverse => "TRAVERSE without DEPTH limit — may explore entire graph",
            LintRule::MissingThreshold => "DRIFT/CONSISTENCY check without THRESHOLD — using implicit default",
            LintRule::OrderByWithoutLimit => "ORDER BY without LIMIT — sorting potentially unbounded result set",
            LintRule::DangerousWrite => "DELETE/UPDATE without WHERE clause — affects all entities",
            LintRule::UnknownProofType => "Unrecognized proof type in PROOF clause",
            LintRule::RedundantWhere => "WHERE clause appears redundant (always true condition)",
            LintRule::MultiModalityNoExplain => "Multi-modality query — consider running EXPLAIN first to review the plan",
            LintRule::FederationWithoutStore => "FEDERATION query without STORE — will query all federated instances",
        }
    }
}

/// A single lint diagnostic.
#[derive(Debug, Clone)]
pub struct LintDiagnostic {
    pub rule: LintRule,
    pub severity: Severity,
    pub message: String,
    /// Approximate character offset in the query (0 if unknown).
    pub offset: usize,
}

impl fmt::Display for LintDiagnostic {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{}] {}: {}", self.rule, self.severity, self.message)
    }
}

/// VQL modality names — all 8 octad modalities.
const MODALITIES: &[&str] = &[
    "GRAPH", "VECTOR", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL",
    "PROVENANCE", "SPATIAL",
];

/// Known VQL-DT proof types.
const KNOWN_PROOF_TYPES: &[&str] = &[
    "EXISTENCE", "CONSISTENCY", "INTEGRITY", "AUTHENTICITY",
    "PROVENANCE", "ACCESS", "CITATION", "ZKP", "PLONK",
];

/// Lint a VQL query string and return diagnostics.
///
/// This performs token-level analysis (not full parsing) to detect common
/// issues. For full AST-based linting, the LSP will use the ReScript parser.
pub fn lint_query(query: &str) -> Vec<LintDiagnostic> {
    let mut diagnostics = Vec::new();
    let upper = query.to_uppercase();
    let tokens = tokenize_upper(&upper);

    // Determine query type
    let is_select = tokens.contains(&"SELECT");
    let is_delete = tokens.contains(&"DELETE");
    let is_update = tokens.contains(&"UPDATE");
    let is_explain = tokens.contains(&"EXPLAIN");
    let has_limit = tokens.contains(&"LIMIT");
    let has_where = tokens.contains(&"WHERE");
    let has_order = tokens.contains(&"ORDER");
    let has_traverse = tokens.contains(&"TRAVERSE");
    let has_depth = tokens.contains(&"DEPTH");
    let has_proof = tokens.contains(&"PROOF");
    let has_drift = tokens.contains(&"DRIFT") || tokens.contains(&"CONSISTENCY");
    let has_threshold = tokens.contains(&"THRESHOLD");
    let has_federation = tokens.contains(&"FEDERATION");
    let has_store = tokens.contains(&"STORE");
    let has_semantic = tokens.contains(&"SEMANTIC");

    // VQL001: Missing LIMIT on SELECT
    if is_select && !has_limit && !is_explain {
        diagnostics.push(LintDiagnostic {
            rule: LintRule::MissingLimit,
            severity: Severity::Warning,
            message: LintRule::MissingLimit.description().to_string(),
            offset: 0,
        });
    }

    // VQL002: SELECT all modalities
    if is_select {
        let modality_count = MODALITIES
            .iter()
            .filter(|m| tokens.contains(m))
            .count();
        if modality_count >= 8 {
            diagnostics.push(LintDiagnostic {
                rule: LintRule::SelectAllModalities,
                severity: Severity::Hint,
                message: LintRule::SelectAllModalities.description().to_string(),
                offset: 0,
            });
        }
    }

    // VQL003: Semantic without PROOF
    if has_semantic && !has_proof && is_select {
        diagnostics.push(LintDiagnostic {
            rule: LintRule::MissingProof,
            severity: Severity::Warning,
            message: LintRule::MissingProof.description().to_string(),
            offset: upper.find("SEMANTIC").unwrap_or(0),
        });
    }

    // VQL004: TRAVERSE without DEPTH
    if has_traverse && !has_depth {
        diagnostics.push(LintDiagnostic {
            rule: LintRule::UnboundedTraverse,
            severity: Severity::Error,
            message: LintRule::UnboundedTraverse.description().to_string(),
            offset: upper.find("TRAVERSE").unwrap_or(0),
        });
    }

    // VQL005: DRIFT/CONSISTENCY without THRESHOLD
    if has_drift && !has_threshold {
        diagnostics.push(LintDiagnostic {
            rule: LintRule::MissingThreshold,
            severity: Severity::Hint,
            message: LintRule::MissingThreshold.description().to_string(),
            offset: upper.find("DRIFT").or_else(|| upper.find("CONSISTENCY")).unwrap_or(0),
        });
    }

    // VQL006: ORDER BY without LIMIT
    if has_order && !has_limit && is_select {
        diagnostics.push(LintDiagnostic {
            rule: LintRule::OrderByWithoutLimit,
            severity: Severity::Warning,
            message: LintRule::OrderByWithoutLimit.description().to_string(),
            offset: upper.find("ORDER").unwrap_or(0),
        });
    }

    // VQL007: Dangerous write without WHERE
    if (is_delete || is_update) && !has_where {
        diagnostics.push(LintDiagnostic {
            rule: LintRule::DangerousWrite,
            severity: Severity::Error,
            message: LintRule::DangerousWrite.description().to_string(),
            offset: 0,
        });
    }

    // VQL008: Unknown proof type
    if has_proof {
        if let Some(proof_pos) = tokens.iter().position(|t| *t == "PROOF") {
            if let Some(proof_type) = tokens.get(proof_pos + 1) {
                if !KNOWN_PROOF_TYPES.contains(proof_type) && !proof_type.is_empty() {
                    diagnostics.push(LintDiagnostic {
                        rule: LintRule::UnknownProofType,
                        severity: Severity::Warning,
                        message: format!(
                            "Unknown proof type '{}' — known types: {}",
                            proof_type,
                            KNOWN_PROOF_TYPES.join(", ")
                        ),
                        offset: upper.find(proof_type).unwrap_or(0),
                    });
                }
            }
        }
    }

    // VQL009: Redundant WHERE (WHERE 1=1, WHERE TRUE)
    if has_where {
        let where_pos = upper.find("WHERE").unwrap_or(0);
        let after_where = &upper[where_pos + 5..].trim_start();
        if after_where.starts_with("1=1")
            || after_where.starts_with("1 = 1")
            || after_where.starts_with("TRUE")
        {
            diagnostics.push(LintDiagnostic {
                rule: LintRule::RedundantWhere,
                severity: Severity::Hint,
                message: LintRule::RedundantWhere.description().to_string(),
                offset: where_pos,
            });
        }
    }

    // VQL010: Multi-modality without EXPLAIN
    if is_select && !is_explain {
        let modality_count = MODALITIES
            .iter()
            .filter(|m| tokens.contains(m))
            .count();
        if modality_count >= 3 {
            diagnostics.push(LintDiagnostic {
                rule: LintRule::MultiModalityNoExplain,
                severity: Severity::Hint,
                message: LintRule::MultiModalityNoExplain.description().to_string(),
                offset: 0,
            });
        }
    }

    // VQL011: FEDERATION without STORE
    if has_federation && !has_store {
        diagnostics.push(LintDiagnostic {
            rule: LintRule::FederationWithoutStore,
            severity: Severity::Warning,
            message: LintRule::FederationWithoutStore.description().to_string(),
            offset: upper.find("FEDERATION").unwrap_or(0),
        });
    }

    // Sort by severity (errors first)
    diagnostics.sort_by(|a, b| b.severity.cmp(&a.severity));
    diagnostics
}

/// Quick check: does a query have any errors (not just warnings/hints)?
pub fn has_errors(query: &str) -> bool {
    lint_query(query)
        .iter()
        .any(|d| d.severity == Severity::Error)
}

/// Format lint diagnostics for terminal output.
pub fn format_diagnostics(query: &str, diagnostics: &[LintDiagnostic]) -> String {
    if diagnostics.is_empty() {
        return String::new();
    }

    let mut output = String::new();
    let error_count = diagnostics.iter().filter(|d| d.severity == Severity::Error).count();
    let warning_count = diagnostics.iter().filter(|d| d.severity == Severity::Warning).count();
    let hint_count = diagnostics.iter().filter(|d| d.severity == Severity::Hint).count();

    for diag in diagnostics {
        output.push_str(&format!("  {} {}\n", diag.rule, diag.message));
    }

    output.push_str(&format!(
        "\n  {} error(s), {} warning(s), {} hint(s) in: {}\n",
        error_count,
        warning_count,
        hint_count,
        if query.len() > 60 {
            format!("{}...", &query[..57])
        } else {
            query.to_string()
        }
    ));

    output
}

/// Tokenize uppercase query into whitespace-separated tokens.
fn tokenize_upper(upper: &str) -> Vec<&str> {
    upper.split_whitespace().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clean_query_no_errors() {
        let diagnostics = lint_query("SELECT GRAPH FROM HEXAD WHERE id = 'abc' LIMIT 10");
        let errors: Vec<_> = diagnostics.iter().filter(|d| d.severity == Severity::Error).collect();
        assert!(errors.is_empty());
    }

    #[test]
    fn test_missing_limit() {
        let diagnostics = lint_query("SELECT GRAPH FROM HEXAD");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::MissingLimit));
    }

    #[test]
    fn test_explain_exempt_from_limit() {
        let diagnostics = lint_query("EXPLAIN SELECT GRAPH FROM HEXAD");
        assert!(!diagnostics.iter().any(|d| d.rule == LintRule::MissingLimit));
    }

    #[test]
    fn test_select_all_modalities() {
        let diagnostics = lint_query(
            "SELECT GRAPH VECTOR TENSOR SEMANTIC DOCUMENT TEMPORAL PROVENANCE SPATIAL FROM HEXAD LIMIT 10"
        );
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::SelectAllModalities));
    }

    #[test]
    fn test_semantic_without_proof() {
        let diagnostics = lint_query("SELECT SEMANTIC FROM HEXAD LIMIT 10");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::MissingProof));
    }

    #[test]
    fn test_semantic_with_proof_ok() {
        let diagnostics = lint_query("SELECT SEMANTIC FROM HEXAD PROOF EXISTENCE LIMIT 10");
        assert!(!diagnostics.iter().any(|d| d.rule == LintRule::MissingProof));
    }

    #[test]
    fn test_unbounded_traverse() {
        let diagnostics = lint_query("SELECT GRAPH FROM HEXAD TRAVERSE relates_to LIMIT 10");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::UnboundedTraverse));
        assert!(diagnostics.iter().any(|d| d.severity == Severity::Error));
    }

    #[test]
    fn test_traverse_with_depth_ok() {
        let diagnostics = lint_query("SELECT GRAPH FROM HEXAD TRAVERSE relates_to DEPTH 3 LIMIT 10");
        assert!(!diagnostics.iter().any(|d| d.rule == LintRule::UnboundedTraverse));
    }

    #[test]
    fn test_drift_without_threshold() {
        let diagnostics = lint_query("SELECT GRAPH FROM HEXAD WHERE DRIFT LIMIT 10");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::MissingThreshold));
    }

    #[test]
    fn test_order_without_limit() {
        let diagnostics = lint_query("SELECT GRAPH FROM HEXAD ORDER BY name");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::OrderByWithoutLimit));
    }

    #[test]
    fn test_dangerous_delete() {
        let diagnostics = lint_query("DELETE FROM HEXAD");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::DangerousWrite));
        assert!(diagnostics.iter().any(|d| d.severity == Severity::Error));
    }

    #[test]
    fn test_delete_with_where_ok() {
        let diagnostics = lint_query("DELETE FROM HEXAD WHERE id = 'abc'");
        assert!(!diagnostics.iter().any(|d| d.rule == LintRule::DangerousWrite));
    }

    #[test]
    fn test_unknown_proof_type() {
        let diagnostics = lint_query("SELECT SEMANTIC FROM HEXAD PROOF FOOBAR LIMIT 10");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::UnknownProofType));
    }

    #[test]
    fn test_known_proof_types_ok() {
        for proof_type in &["EXISTENCE", "CONSISTENCY", "INTEGRITY", "ZKP", "PLONK"] {
            let q = format!("SELECT SEMANTIC FROM HEXAD PROOF {} LIMIT 10", proof_type);
            let diagnostics = lint_query(&q);
            assert!(
                !diagnostics.iter().any(|d| d.rule == LintRule::UnknownProofType),
                "Proof type {} should be recognized",
                proof_type
            );
        }
    }

    #[test]
    fn test_redundant_where() {
        let diagnostics = lint_query("SELECT GRAPH FROM HEXAD WHERE 1=1 LIMIT 10");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::RedundantWhere));
    }

    #[test]
    fn test_multi_modality_hint() {
        let diagnostics = lint_query(
            "SELECT GRAPH VECTOR TENSOR FROM HEXAD LIMIT 10"
        );
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::MultiModalityNoExplain));
    }

    #[test]
    fn test_federation_without_store() {
        let diagnostics = lint_query("SELECT GRAPH FROM FEDERATION HEXAD LIMIT 10");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::FederationWithoutStore));
    }

    #[test]
    fn test_federation_with_store_ok() {
        let diagnostics = lint_query("SELECT GRAPH FROM FEDERATION STORE 'remote-1' HEXAD LIMIT 10");
        assert!(!diagnostics.iter().any(|d| d.rule == LintRule::FederationWithoutStore));
    }

    #[test]
    fn test_has_errors_true() {
        assert!(has_errors("DELETE FROM HEXAD"));
    }

    #[test]
    fn test_has_errors_false() {
        assert!(!has_errors("SELECT GRAPH FROM HEXAD LIMIT 10"));
    }

    #[test]
    fn test_diagnostics_sorted_by_severity() {
        let diagnostics = lint_query(
            "DELETE FROM FEDERATION HEXAD"
        );
        // Errors should come before warnings
        let severities: Vec<_> = diagnostics.iter().map(|d| d.severity).collect();
        for window in severities.windows(2) {
            assert!(window[0] >= window[1], "Diagnostics should be sorted by severity");
        }
    }

    #[test]
    fn test_format_diagnostics_output() {
        let diagnostics = lint_query("DELETE FROM HEXAD");
        let output = format_diagnostics("DELETE FROM HEXAD", &diagnostics);
        assert!(output.contains("VQL007"));
        assert!(output.contains("error"));
    }

    #[test]
    fn test_empty_query() {
        let diagnostics = lint_query("");
        assert!(diagnostics.is_empty());
    }

    #[test]
    fn test_case_insensitive() {
        let diagnostics = lint_query("select semantic from hexad limit 10");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::MissingProof));
    }

    #[test]
    fn test_update_without_where() {
        let diagnostics = lint_query("UPDATE HEXAD SET name = 'test'");
        assert!(diagnostics.iter().any(|d| d.rule == LintRule::DangerousWrite));
    }
}
