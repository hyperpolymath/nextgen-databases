// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//! Sanctify Bridge — Integration with sanctify-php (Haskell security analyser).
//!
//! sanctify-php is a Haskell tool that analyses PHP/WordPress code for
//! security vulnerabilities (OWASP Top 10, WordPress-specific checks).
//! It produces structured reports in JSON/SARIF format.
//!
//! This bridge consumes sanctify reports, converts security issues into
//! VeriSimDB semantic annotations, and binds security contracts to hexads.
//!
//! # Architecture
//!
//! ```text
//! sanctify-php (Haskell) → JSON report → SanctifyBridge → SemanticStore
//!                                             │
//!                                   ┌─────────┴──────────┐
//!                                   │ SanctifyContract    │
//!                                   │  - parse_report     │
//!                                   │  - validate         │
//!                                   │  - bind_to_hexad    │
//!                                   └────────────────────┘
//! ```

use serde::{Deserialize, Serialize};

use super::{ProofBlob, ProofType, SemanticError};

/// Security issue severity levels (from sanctify-php).
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Info,
    Low,
    Medium,
    High,
    Critical,
}

impl std::fmt::Display for Severity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Info => write!(f, "info"),
            Self::Low => write!(f, "low"),
            Self::Medium => write!(f, "medium"),
            Self::High => write!(f, "high"),
            Self::Critical => write!(f, "critical"),
        }
    }
}

/// Types of security issues detected by sanctify.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueType {
    SqlInjection,
    CrossSiteScripting,
    CrossSiteRequestForgery,
    CommandInjection,
    PathTraversal,
    UnsafeDeserialization,
    WeakCryptography,
    HardcodedSecret,
    DangerousFunction,
    InsecureFileUpload,
    OpenRedirect,
    XPathInjection,
    LdapInjection,
    XXeVulnerability,
    InsecureRandom,
    MissingStrictTypes,
    TypeCoercionRisk,
}

impl std::fmt::Display for IssueType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

/// A security issue from a sanctify report.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityIssue {
    /// Type of vulnerability
    pub issue_type: IssueType,
    /// Severity level
    pub severity: Severity,
    /// File path
    pub file: String,
    /// Line number
    pub line: u32,
    /// Column number
    pub column: Option<u32>,
    /// Human-readable description
    pub description: String,
    /// Recommended remediation
    pub remedy: String,
    /// Optional code snippet
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
}

/// A sanctify security report.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SanctifyReport {
    /// Report timestamp
    pub timestamp: String,
    /// Sanctify version
    pub version: String,
    /// Files analysed
    pub files_analysed: usize,
    /// Security issues found
    pub issues: Vec<SecurityIssue>,
    /// Summary counts by severity
    pub summary: IssueSummary,
}

/// Summary counts of issues by severity.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct IssueSummary {
    pub critical: usize,
    pub high: usize,
    pub medium: usize,
    pub low: usize,
    pub info: usize,
}

impl IssueSummary {
    /// Total number of issues.
    pub fn total(&self) -> usize {
        self.critical + self.high + self.medium + self.low + self.info
    }

    /// Compute summary from a list of issues.
    pub fn from_issues(issues: &[SecurityIssue]) -> Self {
        let mut summary = Self::default();
        for issue in issues {
            match issue.severity {
                Severity::Critical => summary.critical += 1,
                Severity::High => summary.high += 1,
                Severity::Medium => summary.medium += 1,
                Severity::Low => summary.low += 1,
                Severity::Info => summary.info += 1,
            }
        }
        summary
    }
}

/// A verifiable security contract binding sanctify findings to a hexad.
///
/// Represents a commitment that a particular codebase or entity has been
/// analysed and the results are stored in the semantic modality.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SanctifyContract {
    /// Unique contract identifier
    pub contract_id: String,
    /// Hexad ID this contract is bound to
    pub hexad_id: String,
    /// The sanctify report backing this contract
    pub report: SanctifyReport,
    /// Whether all critical issues have been resolved
    pub all_critical_resolved: bool,
    /// Whether all high issues have been resolved
    pub all_high_resolved: bool,
    /// Contract creation timestamp
    pub created_at: String,
}

/// Parse a sanctify report from JSON bytes.
pub fn parse_sanctify_report(bytes: &[u8]) -> Result<SanctifyReport, SemanticError> {
    serde_json::from_slice(bytes)
        .map_err(|e| SemanticError::SerializationError(format!("Failed to parse sanctify report: {}", e)))
}

/// Validate a sanctify contract's structural integrity.
///
/// Checks:
/// - Contract has a non-empty ID and hexad_id
/// - Summary counts match the actual issue counts
/// - Resolution flags are consistent with issue counts
pub fn validate_contract(contract: &SanctifyContract) -> Result<bool, SemanticError> {
    if contract.contract_id.is_empty() {
        return Err(SemanticError::ConstraintViolation("Contract ID must not be empty".to_string()));
    }
    if contract.hexad_id.is_empty() {
        return Err(SemanticError::ConstraintViolation("Hexad ID must not be empty".to_string()));
    }

    // Verify summary is consistent
    let computed = IssueSummary::from_issues(&contract.report.issues);
    if computed.total() != contract.report.summary.total() {
        return Err(SemanticError::ConstraintViolation(format!(
            "Summary mismatch: computed {} issues but summary says {}",
            computed.total(),
            contract.report.summary.total()
        )));
    }

    // Verify resolution flags are consistent
    if contract.all_critical_resolved && contract.report.summary.critical > 0 {
        return Ok(false); // Claims resolved but has critical issues
    }
    if contract.all_high_resolved && contract.report.summary.high > 0 {
        return Ok(false); // Claims resolved but has high issues
    }

    Ok(true)
}

/// Convert a sanctify contract into a VeriSimDB ProofBlob for storage.
pub fn contract_to_proof_blob(contract: &SanctifyContract) -> Result<ProofBlob, SemanticError> {
    let data = serde_json::to_vec(contract)
        .map_err(|e| SemanticError::SerializationError(e.to_string()))?;

    let claim = format!(
        "security-audit:{} hexad:{} issues:{}",
        contract.contract_id,
        contract.hexad_id,
        contract.report.summary.total()
    );

    Ok(ProofBlob {
        claim,
        proof_type: ProofType::Attestation,
        data,
        timestamp: contract.created_at.clone(),
    })
}

/// Create a SanctifyContract from a report and hexad binding.
pub fn bind_contract_to_hexad(
    contract_id: String,
    hexad_id: String,
    report: SanctifyReport,
) -> SanctifyContract {
    let all_critical_resolved = report.summary.critical == 0;
    let all_high_resolved = report.summary.high == 0;

    SanctifyContract {
        contract_id,
        hexad_id,
        report,
        all_critical_resolved,
        all_high_resolved,
        created_at: chrono::Utc::now().to_rfc3339(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_report() -> SanctifyReport {
        let issues = vec![
            SecurityIssue {
                issue_type: IssueType::SqlInjection,
                severity: Severity::Critical,
                file: "login.php".to_string(),
                line: 42,
                column: Some(15),
                description: "Unsanitized user input in SQL query".to_string(),
                remedy: "Use prepared statements with PDO".to_string(),
                code: Some("$query = \"SELECT * FROM users WHERE id = \" . $_GET['id']".to_string()),
            },
            SecurityIssue {
                issue_type: IssueType::CrossSiteScripting,
                severity: Severity::High,
                file: "profile.php".to_string(),
                line: 88,
                column: None,
                description: "Reflected XSS via unescaped output".to_string(),
                remedy: "Use htmlspecialchars() or esc_html()".to_string(),
                code: None,
            },
            SecurityIssue {
                issue_type: IssueType::MissingStrictTypes,
                severity: Severity::Info,
                file: "utils.php".to_string(),
                line: 1,
                column: None,
                description: "Missing declare(strict_types=1)".to_string(),
                remedy: "Add strict types declaration".to_string(),
                code: None,
            },
        ];
        let summary = IssueSummary::from_issues(&issues);
        SanctifyReport {
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: "0.1.0".to_string(),
            files_analysed: 3,
            issues,
            summary,
        }
    }

    #[test]
    fn test_parse_report_json() {
        let report = sample_report();
        let json = serde_json::to_vec(&report).unwrap();
        let parsed = parse_sanctify_report(&json).unwrap();
        assert_eq!(parsed.issues.len(), 3);
        assert_eq!(parsed.summary.critical, 1);
        assert_eq!(parsed.summary.high, 1);
        assert_eq!(parsed.summary.info, 1);
    }

    #[test]
    fn test_issue_summary() {
        let report = sample_report();
        assert_eq!(report.summary.total(), 3);
        assert_eq!(report.summary.critical, 1);
        assert_eq!(report.summary.high, 1);
        assert_eq!(report.summary.info, 1);
        assert_eq!(report.summary.medium, 0);
        assert_eq!(report.summary.low, 0);
    }

    #[test]
    fn test_bind_contract() {
        let report = sample_report();
        let contract = bind_contract_to_hexad(
            "audit-001".to_string(),
            "hexad-abc".to_string(),
            report,
        );
        assert!(!contract.all_critical_resolved); // Has 1 critical
        assert!(!contract.all_high_resolved); // Has 1 high
        assert_eq!(contract.report.issues.len(), 3);
    }

    #[test]
    fn test_validate_contract() {
        let report = sample_report();
        let contract = bind_contract_to_hexad(
            "audit-001".to_string(),
            "hexad-abc".to_string(),
            report,
        );
        // Valid contract (resolution flags match issue counts)
        assert!(validate_contract(&contract).unwrap());
    }

    #[test]
    fn test_validate_contract_empty_id() {
        let report = sample_report();
        let contract = SanctifyContract {
            contract_id: "".to_string(),
            hexad_id: "hexad-abc".to_string(),
            report,
            all_critical_resolved: false,
            all_high_resolved: false,
            created_at: chrono::Utc::now().to_rfc3339(),
        };
        assert!(validate_contract(&contract).is_err());
    }

    #[test]
    fn test_validate_inconsistent_resolution() {
        let report = sample_report();
        let contract = SanctifyContract {
            contract_id: "audit-002".to_string(),
            hexad_id: "hexad-abc".to_string(),
            report,
            all_critical_resolved: true, // Claims resolved but has 1 critical
            all_high_resolved: false,
            created_at: chrono::Utc::now().to_rfc3339(),
        };
        // Should return false (inconsistent)
        assert!(!validate_contract(&contract).unwrap());
    }

    #[test]
    fn test_contract_to_proof_blob() {
        let report = sample_report();
        let contract = bind_contract_to_hexad(
            "audit-003".to_string(),
            "hexad-xyz".to_string(),
            report,
        );
        let blob = contract_to_proof_blob(&contract).unwrap();
        assert!(blob.claim.contains("security-audit:audit-003"));
        assert!(blob.claim.contains("hexad:hexad-xyz"));
        assert!(!blob.data.is_empty());
    }

    #[test]
    fn test_severity_ordering() {
        assert!(Severity::Critical > Severity::High);
        assert!(Severity::High > Severity::Medium);
        assert!(Severity::Medium > Severity::Low);
        assert!(Severity::Low > Severity::Info);
    }

    #[test]
    fn test_clean_report_contract() {
        // A clean report (no issues)
        let report = SanctifyReport {
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: "0.1.0".to_string(),
            files_analysed: 5,
            issues: vec![],
            summary: IssueSummary::default(),
        };
        let contract = bind_contract_to_hexad(
            "clean-001".to_string(),
            "hexad-clean".to_string(),
            report,
        );
        assert!(contract.all_critical_resolved);
        assert!(contract.all_high_resolved);
        assert!(validate_contract(&contract).unwrap());
    }
}
