// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//! Proof-attempts API handlers.
//!
//! Three REST endpoints that bridge the proof-attempts pipeline to ClickHouse:
//!
//! | Method | Path                                   | Purpose                           |
//! |--------|----------------------------------------|-----------------------------------|
//! | POST   | /proof_attempts                        | Insert a single attempt row       |
//! | GET    | /proof_attempts/strategy?class=X&limit=N | Recommend best provers for class  |
//! | GET    | /proof_attempts/certificates?class=X  | PROVEN/pending cert status        |
//!
//! The handlers speak directly to the ClickHouse HTTP interface (default
//! `http://localhost:8123`) via `reqwest`.  The URL is read from the
//! `VERISIM_CLICKHOUSE_URL` environment variable at request time so that no
//! restart is needed when the ClickHouse endpoint changes.

use axum::{
    Json,
    extract::Query,
    http::StatusCode,
    response::IntoResponse,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, warn};

// ClickHouse supports sending SELECT queries as POST body with Content-Type: text/plain.
// This avoids any URL-encoding complexity.


// ── Shared HTTP client (one per module, constructed lazily via once_cell) ──

fn ch_client() -> &'static Client {
    use std::sync::OnceLock;
    static CLIENT: OnceLock<Client> = OnceLock::new();
    CLIENT.get_or_init(|| {
        Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .expect("failed to build ClickHouse HTTP client")
    })
}

fn ch_url() -> String {
    std::env::var("VERISIM_CLICKHOUSE_URL")
        .unwrap_or_else(|_| "http://localhost:8123".to_string())
}

// ── Inbound proof-attempt row (matches echidnabot VeriSimWriter schema) ──

/// A single proof attempt submitted by echidnabot.
#[derive(Debug, Deserialize, Serialize)]
pub struct ProofAttemptRow {
    pub attempt_id: String,
    pub obligation_id: String,
    pub repo: String,
    pub file: String,
    pub claim: String,
    pub obligation_class: String,
    pub prover_used: String,
    pub outcome: String,
    pub duration_ms: u64,
    pub confidence: f64,
    pub parent_attempt_id: Option<String>,
    pub strategy_tag: String,
    pub started_at: String,
    pub completed_at: String,
    pub prover_output: String,
    pub error_message: Option<String>,
}

// ── Response types ──

#[derive(Debug, Serialize)]
pub struct StrategyResponse {
    pub recommendations: Vec<Recommendation>,
}

#[derive(Debug, Serialize)]
pub struct Recommendation {
    pub prover: String,
    pub success_rate: f64,
    pub avg_duration_ms: f64,
    pub total_attempts: u64,
}

#[derive(Debug, Serialize)]
pub struct CertificatesResponse {
    pub proven: Vec<CertRow>,
}

#[derive(Debug, Serialize)]
pub struct CertRow {
    pub prover_used: String,
    pub status: String,
    pub success_rate: f64,
    pub total_attempts: u64,
}

// ── Query params ──

#[derive(Debug, Deserialize)]
pub struct ListParams {
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
pub struct StrategyParams {
    pub class: String,
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
pub struct ClassParam {
    pub class: String,
}

// ── Handlers ──

/// GET /proof_attempts?limit=N
///
/// Returns up to `limit` (default 1000, max 20000) recent proof-attempt rows
/// from ClickHouse for retraining the Julia ML models.
pub async fn list_proof_attempts(
    Query(params): Query<ListParams>,
) -> impl IntoResponse {
    let limit = params.limit.unwrap_or(1000).min(20000);

    let sql = format!(
        "SELECT attempt_id, obligation_id, repo, file, claim, obligation_class, \
                prover_used, outcome, duration_ms, confidence, parent_attempt_id, \
                strategy_tag, started_at, completed_at \
         FROM verisim.proof_attempts \
         ORDER BY started_at DESC \
         LIMIT {limit} \
         FORMAT JSONEachRow"
    );

    match ch_client()
        .post(ch_url())
        .header("Content-Type", "text/plain")
        .body(sql)
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            let text = resp.text().await.unwrap_or_default();
            // Return newline-delimited JSON rows as a JSON array for convenience
            let rows: Vec<serde_json::Value> = text
                .lines()
                .filter(|l| !l.trim().is_empty())
                .filter_map(|l| serde_json::from_str(l).ok())
                .collect();
            (StatusCode::OK, Json(serde_json::json!(rows)))
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            let body = resp.text().await.unwrap_or_default();
            warn!("proof_attempts list: ClickHouse {status}: {body}");
            (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({"error": "clickhouse error", "status": status})),
            )
        }
        Err(e) => {
            warn!("proof_attempts list: unreachable: {e}");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(serde_json::json!({"error": "clickhouse unreachable"})),
            )
        }
    }
}

/// POST /proof_attempts
///
/// Inserts a single attempt row into `verisim.proof_attempts` via the
/// ClickHouse HTTP INSERT ... FORMAT JSONEachRow endpoint.
pub async fn insert_proof_attempt(
    Json(row): Json<ProofAttemptRow>,
) -> impl IntoResponse {
    let url = format!("{}/?query=INSERT+INTO+verisim.proof_attempts+FORMAT+JSONEachRow", ch_url());

    let body = match serde_json::to_string(&row) {
        Ok(s) => s,
        Err(e) => {
            warn!("proof_attempts: failed to serialise row: {e}");
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "serialisation failed", "detail": e.to_string()})),
            );
        }
    };

    debug!(attempt_id = %row.attempt_id, prover = %row.prover_used, "inserting proof attempt");

    match ch_client()
        .post(&url)
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => (
            StatusCode::CREATED,
            Json(serde_json::json!({"status": "ok", "attempt_id": row.attempt_id})),
        ),
        Ok(resp) => {
            let status = resp.status().as_u16();
            let body = resp.text().await.unwrap_or_default();
            warn!("proof_attempts: ClickHouse returned {status}: {body}");
            (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({"error": "clickhouse error", "status": status, "detail": body})),
            )
        }
        Err(e) => {
            warn!("proof_attempts: ClickHouse unreachable: {e}");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(serde_json::json!({"error": "clickhouse unreachable", "detail": e.to_string()})),
            )
        }
    }
}

/// GET /proof_attempts/strategy?class=X&limit=N
///
/// Returns up to `limit` (default 5) prover recommendations for the given
/// obligation class, ordered by success rate descending.  Queries the
/// `mv_proven_certificates` view which pre-computes success_rate and
/// avg_duration_ms so no Rust arithmetic is needed.
pub async fn strategy(
    Query(params): Query<StrategyParams>,
) -> impl IntoResponse {
    let limit = params.limit.unwrap_or(5).min(50);
    let class = params.class.replace('\'', "\\'"); // minimal SQL escape

    let sql = format!(
        "SELECT prover_used, success_rate, avg_duration_ms, total_attempts \
         FROM verisim.mv_proven_certificates \
         WHERE obligation_class = '{class}' \
         ORDER BY success_rate DESC, avg_duration_ms ASC \
         LIMIT {limit} \
         FORMAT JSONEachRow"
    );

    match ch_client()
        .post(ch_url())
        .header("Content-Type", "text/plain")
        .body(sql)
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            let text = resp.text().await.unwrap_or_default();
            let recommendations = parse_jsonl_recommendations(&text);
            (
                StatusCode::OK,
                Json(serde_json::json!({"recommendations": recommendations})),
            )
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            let body = resp.text().await.unwrap_or_default();
            warn!("proof_attempts/strategy: ClickHouse {status}: {body}");
            (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({"error": "clickhouse error", "status": status})),
            )
        }
        Err(e) => {
            warn!("proof_attempts/strategy: unreachable: {e}");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(serde_json::json!({"error": "clickhouse unreachable"})),
            )
        }
    }
}

/// GET /proof_attempts/certificates?class=X
///
/// Returns PROVEN / pending status for every (class, prover) pair from
/// `mv_proven_certificates`.
pub async fn certificates(
    Query(params): Query<ClassParam>,
) -> impl IntoResponse {
    let class = params.class.replace('\'', "\\'");

    let sql = format!(
        "SELECT prover_used, status, success_rate, total_attempts \
         FROM verisim.mv_proven_certificates \
         WHERE obligation_class = '{class}' \
         FORMAT JSONEachRow"
    );

    match ch_client()
        .post(ch_url())
        .header("Content-Type", "text/plain")
        .body(sql)
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            let text = resp.text().await.unwrap_or_default();
            let rows = parse_jsonl_certs(&text);
            (
                StatusCode::OK,
                Json(serde_json::json!({"proven": rows})),
            )
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            warn!("proof_attempts/certificates: ClickHouse {status}");
            (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({"error": "clickhouse error", "status": status})),
            )
        }
        Err(e) => {
            warn!("proof_attempts/certificates: unreachable: {e}");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(serde_json::json!({"error": "clickhouse unreachable"})),
            )
        }
    }
}

// ── ClickHouse JSONEachRow parsers ──

/// Parse newline-delimited JSON rows from ClickHouse JSONEachRow output.
/// Each line is a JSON object; malformed lines are silently skipped.
fn parse_jsonl_recommendations(text: &str) -> Vec<serde_json::Value> {
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|line| {
            let v: serde_json::Value = serde_json::from_str(line).ok()?;
            let prover = v["prover_used"].as_str()?.to_string();
            let success_rate = v["success_rate"].as_f64().unwrap_or(0.0);
            let avg_duration_ms = v["avg_duration_ms"].as_f64().unwrap_or(0.0);
            let total_attempts = v["total_attempts"].as_u64().unwrap_or(0);
            Some(serde_json::json!({
                "prover": prover,
                "success_rate": success_rate,
                "avg_duration_ms": avg_duration_ms,
                "total_attempts": total_attempts,
            }))
        })
        .collect()
}

fn parse_jsonl_certs(text: &str) -> Vec<serde_json::Value> {
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|line| {
            let v: serde_json::Value = serde_json::from_str(line).ok()?;
            let prover_used = v["prover_used"].as_str()?.to_string();
            let status = v["status"].as_str().unwrap_or("pending").to_string();
            let success_rate = v["success_rate"].as_f64().unwrap_or(0.0);
            let total_attempts = v["total_attempts"].as_u64().unwrap_or(0);
            Some(serde_json::json!({
                "prover_used": prover_used,
                "status": status,
                "success_rate": success_rate,
                "total_attempts": total_attempts,
            }))
        })
        .collect()
}
