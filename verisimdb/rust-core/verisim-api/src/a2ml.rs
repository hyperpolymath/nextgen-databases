// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//! A2ML (Annotated Attribute Markup Language) response helpers for verisim-api.
//!
//! The hyperpolymath no-JSON-emit rule requires that all tool and service
//! outputs use A2ML format rather than JSON.  This module provides:
//!
//! - [`a2ml_response`] — wrap an A2ML body in an Axum `Response`
//! - [`a2ml_error`] — format an error response
//! - A2ML serialisation for the proof-attempts response types
//!
//! ## A2ML format used here
//!
//! ```text
//! # SPDX-License-Identifier: PMPL-1.0-or-later
//! @<tag>(key="value", ...):
//!   @<child>(key="value"):@end
//! @end
//! ```
//!
//! Attribute values are always quoted strings.  Numeric values are
//! formatted as decimal strings.  There is no `null` — absent optionals
//! are omitted from the attribute list entirely.

use axum::{
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};

// ── Content-type constant ─────────────────────────────────────────────────────

/// Content-Type for A2ML responses.
pub const A2ML_CONTENT_TYPE: &str = "text/a2ml; charset=utf-8";

// ── Core response helpers ─────────────────────────────────────────────────────

/// Wrap an A2ML body string in an Axum [`Response`] with the correct
/// `Content-Type`.
pub fn a2ml_response(status: StatusCode, body: String) -> Response {
    (
        status,
        [(header::CONTENT_TYPE, A2ML_CONTENT_TYPE)],
        body,
    )
        .into_response()
}

/// Convenience alias so callers can `use crate::a2ml::String` implicitly.
pub type String = std::string::String;

/// Format a standardised A2ML error block.
///
/// ```text
/// @error(code="clickhouse_error", http-status="502"):@end
/// ```
pub fn a2ml_error(code: &str, http_status: u16) -> String {
    format!("@error(code=\"{code}\", http-status=\"{http_status}\"):@end\n")
}

/// Format an A2ML error block with an additional detail message.
///
/// ```text
/// @error(code="serialisation_failed", http-status="400", detail="..."):@end
/// ```
pub fn a2ml_error_detail(code: &str, http_status: u16, detail: &str) -> String {
    // Escape double-quotes inside `detail` so the A2ML stays well-formed.
    let escaped = detail.replace('"', "\\\"");
    format!("@error(code=\"{code}\", http-status=\"{http_status}\", detail=\"{escaped}\"):@end\n")
}

// ── proof-attempts serialisation ──────────────────────────────────────────────

/// A single proof-attempt row as returned by the list endpoint.
pub struct ProofAttemptRowA2ml<'a> {
    pub attempt_id: &'a str,
    pub obligation_id: &'a str,
    pub repo: &'a str,
    pub file: &'a str,
    pub claim: &'a str,
    pub obligation_class: &'a str,
    pub prover_used: &'a str,
    pub outcome: &'a str,
    pub duration_ms: u64,
    pub confidence: f64,
    pub parent_attempt_id: Option<&'a str>,
    pub strategy_tag: &'a str,
    pub started_at: &'a str,
    pub completed_at: &'a str,
}

impl<'a> ProofAttemptRowA2ml<'a> {
    /// Render the row as an inline A2ML `@row(...):@end` element.
    pub fn to_a2ml(&self, indent: &str) -> String {
        let mut s = format!(
            "{indent}@row(attempt-id=\"{}\", obligation-id=\"{}\", repo=\"{}\", file=\"{}\", \
             claim=\"{}\", class=\"{}\", prover=\"{}\", outcome=\"{}\", \
             duration-ms=\"{}\", confidence=\"{:.4}\", strategy-tag=\"{}\", \
             started-at=\"{}\", completed-at=\"{}\"",
            self.attempt_id,
            self.obligation_id,
            self.repo,
            self.file,
            self.claim,
            self.obligation_class,
            self.prover_used,
            self.outcome,
            self.duration_ms,
            self.confidence,
            self.strategy_tag,
            self.started_at,
            self.completed_at,
        );
        if let Some(parent) = self.parent_attempt_id {
            s.push_str(&format!(", parent-attempt-id=\"{parent}\""));
        }
        s.push_str("):@end\n");
        s
    }
}

/// Serialise a list of raw ClickHouse JSONEachRow rows (as `serde_json::Value`)
/// into a complete A2ML `@proof-attempts` block.
///
/// Rows that are missing required fields are silently skipped.
pub fn proof_attempts_to_a2ml(rows: &[serde_json::Value]) -> String {
    let mut out = String::new();
    out.push_str("@proof-attempts():\n");
    for v in rows {
        let Some(attempt_id)       = v["attempt_id"].as_str()       else { continue };
        let Some(obligation_id)    = v["obligation_id"].as_str()     else { continue };
        let Some(repo)             = v["repo"].as_str()              else { continue };
        let Some(file)             = v["file"].as_str()              else { continue };
        let Some(claim)            = v["claim"].as_str()             else { continue };
        let Some(obligation_class) = v["obligation_class"].as_str()  else { continue };
        let Some(prover_used)      = v["prover_used"].as_str()       else { continue };
        let Some(outcome)          = v["outcome"].as_str()           else { continue };
        let duration_ms            = v["duration_ms"].as_u64().unwrap_or(0);
        let confidence             = v["confidence"].as_f64().unwrap_or(0.0);
        let parent_attempt_id      = v["parent_attempt_id"].as_str();
        let strategy_tag           = v["strategy_tag"].as_str().unwrap_or("");
        let started_at             = v["started_at"].as_str().unwrap_or("");
        let completed_at           = v["completed_at"].as_str().unwrap_or("");

        let row = ProofAttemptRowA2ml {
            attempt_id,
            obligation_id,
            repo,
            file,
            claim,
            obligation_class,
            prover_used,
            outcome,
            duration_ms,
            confidence,
            parent_attempt_id,
            strategy_tag,
            started_at,
            completed_at,
        };
        out.push_str(&row.to_a2ml("  "));
    }
    out.push_str("@end\n");
    out
}

/// Serialise the `inserted` acknowledgement for a single proof attempt.
///
/// ```text
/// @inserted(status="ok", attempt-id="abc123"):@end
/// ```
pub fn inserted_to_a2ml(attempt_id: &str) -> String {
    format!("@inserted(status=\"ok\", attempt-id=\"{attempt_id}\"):@end\n")
}

// ── strategy serialisation ────────────────────────────────────────────────────

/// A single prover recommendation.
pub struct RecommendationA2ml {
    pub prover: String,
    pub success_rate: f64,
    pub avg_duration_ms: f64,
    pub total_attempts: u64,
}

/// Serialise strategy recommendations into an A2ML block.
///
/// ```text
/// @strategy-recommendations():
///   @recommendation(prover="echidna", success-rate="0.9500", ...):@end
/// @end
/// ```
pub fn strategy_to_a2ml(recommendations: &[RecommendationA2ml]) -> String {
    let mut out = String::from("@strategy-recommendations():\n");
    for r in recommendations {
        out.push_str(&format!(
            "  @recommendation(prover=\"{}\", success-rate=\"{:.4}\", \
             avg-duration-ms=\"{:.2}\", total-attempts=\"{}\"):@end\n",
            r.prover, r.success_rate, r.avg_duration_ms, r.total_attempts,
        ));
    }
    out.push_str("@end\n");
    out
}

/// Parse ClickHouse JSONEachRow recommendations into typed structs.
/// Malformed lines are silently skipped.
pub fn parse_recommendations(text: &str) -> Vec<RecommendationA2ml> {
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|line| {
            let v: serde_json::Value = serde_json::from_str(line).ok()?;
            Some(RecommendationA2ml {
                prover:          v["prover_used"].as_str()?.to_string(),
                success_rate:    v["success_rate"].as_f64().unwrap_or(0.0),
                avg_duration_ms: v["avg_duration_ms"].as_f64().unwrap_or(0.0),
                total_attempts:  v["total_attempts"].as_u64().unwrap_or(0),
            })
        })
        .collect()
}

// ── certificates serialisation ────────────────────────────────────────────────

/// A single certificate row.
pub struct CertRowA2ml {
    pub prover_used: String,
    pub status: String,
    pub success_rate: f64,
    pub total_attempts: u64,
}

/// Serialise certificate rows into an A2ML block.
///
/// ```text
/// @certificates():
///   @cert(prover-used="echidna", status="PROVEN", ...):@end
/// @end
/// ```
pub fn certificates_to_a2ml(rows: &[CertRowA2ml]) -> String {
    let mut out = String::from("@certificates():\n");
    for r in rows {
        out.push_str(&format!(
            "  @cert(prover-used=\"{}\", status=\"{}\", \
             success-rate=\"{:.4}\", total-attempts=\"{}\"):@end\n",
            r.prover_used, r.status, r.success_rate, r.total_attempts,
        ));
    }
    out.push_str("@end\n");
    out
}

/// Parse ClickHouse JSONEachRow certificate rows into typed structs.
/// Malformed lines are silently skipped.
pub fn parse_certs(text: &str) -> Vec<CertRowA2ml> {
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|line| {
            let v: serde_json::Value = serde_json::from_str(line).ok()?;
            Some(CertRowA2ml {
                prover_used:    v["prover_used"].as_str()?.to_string(),
                status:         v["status"].as_str().unwrap_or("pending").to_string(),
                success_rate:   v["success_rate"].as_f64().unwrap_or(0.0),
                total_attempts: v["total_attempts"].as_u64().unwrap_or(0),
            })
        })
        .collect()
}

// ── tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_format() {
        let s = a2ml_error("clickhouse_error", 502);
        assert!(s.contains("@error("));
        assert!(s.contains("code=\"clickhouse_error\""));
        assert!(s.contains("http-status=\"502\""));
        assert!(s.ends_with(":@end\n"));
    }

    #[test]
    fn error_detail_escapes_quotes() {
        let s = a2ml_error_detail("bad_input", 400, r#"has "quotes""#);
        assert!(s.contains(r#"detail="has \"quotes\"""#));
    }

    #[test]
    fn inserted_format() {
        let s = inserted_to_a2ml("abc-123");
        assert_eq!(s, "@inserted(status=\"ok\", attempt-id=\"abc-123\"):@end\n");
    }

    #[test]
    fn proof_attempts_to_a2ml_empty() {
        let s = proof_attempts_to_a2ml(&[]);
        assert_eq!(s, "@proof-attempts():\n@end\n");
    }

    #[test]
    fn proof_attempts_to_a2ml_skips_malformed() {
        // Row missing 'attempt_id' field should be skipped
        let rows = vec![serde_json::json!({"obligation_id": "x"})];
        let s = proof_attempts_to_a2ml(&rows);
        // Only the wrapper tags, no @row
        assert!(!s.contains("@row("));
    }

    #[test]
    fn strategy_to_a2ml_format() {
        let recs = vec![
            RecommendationA2ml {
                prover: "echidna".to_string(),
                success_rate: 0.95,
                avg_duration_ms: 120.5,
                total_attempts: 100,
            },
        ];
        let s = strategy_to_a2ml(&recs);
        assert!(s.starts_with("@strategy-recommendations():\n"));
        assert!(s.contains("prover=\"echidna\""));
        assert!(s.contains("success-rate=\"0.9500\""));
        assert!(s.contains("avg-duration-ms=\"120.50\""));
        assert!(s.contains("total-attempts=\"100\""));
        assert!(s.ends_with("@end\n"));
    }

    #[test]
    fn certificates_to_a2ml_format() {
        let rows = vec![CertRowA2ml {
            prover_used: "idris2".to_string(),
            status: "PROVEN".to_string(),
            success_rate: 0.80,
            total_attempts: 50,
        }];
        let s = certificates_to_a2ml(&rows);
        assert!(s.contains("prover-used=\"idris2\""));
        assert!(s.contains("status=\"PROVEN\""));
        assert!(s.contains("success-rate=\"0.8000\""));
    }

    #[test]
    fn parse_recommendations_skips_malformed() {
        let text = "{\"prover_used\":\"echidna\",\"success_rate\":0.9,\"avg_duration_ms\":100.0,\"total_attempts\":10}\n{bad json}\n";
        let recs = parse_recommendations(text);
        assert_eq!(recs.len(), 1);
        assert_eq!(recs[0].prover, "echidna");
    }

    #[test]
    fn parse_certs_skips_malformed() {
        let text = "{\"prover_used\":\"lean4\",\"status\":\"PROVEN\",\"success_rate\":0.75,\"total_attempts\":8}\n";
        let certs = parse_certs(text);
        assert_eq!(certs.len(), 1);
        assert_eq!(certs[0].prover_used, "lean4");
        assert_eq!(certs[0].status, "PROVEN");
    }
}
