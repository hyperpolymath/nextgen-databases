// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//! Proof-attempts API handlers.
//!
//! Three REST endpoints that bridge the proof-attempts pipeline to ClickHouse:
//!
//! | Method | Path                                      | Purpose                           |
//! |--------|-------------------------------------------|-----------------------------------|
//! | GET    | /proof_attempts?limit=N&offset=M          | List attempt rows (paged)         |
//! | POST   | /proof_attempts                           | Insert a single attempt row       |
//! | GET    | /proof_attempts/strategy?class=X&limit=N  | Recommend best provers for class  |
//! | GET    | /proof_attempts/certificates?class=X      | PROVEN/pending cert status        |
//!
//! Responses are emitted as A2ML (text/a2ml) — never JSON.  ClickHouse is
//! still spoken to over its JSONEachRow wire format internally, but that is
//! parsing only (inbound from ClickHouse, never emitted to callers).
//!
//! The ClickHouse URL is read from `VERISIM_CLICKHOUSE_URL` at request time.
//! Optional write auth: if `VERISIM_PROOF_ATTEMPTS_TOKEN` is set, callers must
//! provide either `X-Proof-Attempts-Token: <token>` or
//! `Authorization: Bearer <token>` on `POST /proof_attempts`.

use axum::{
    extract::Query,
    http::{HeaderMap, StatusCode},
    response::Response,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, warn};

use crate::a2ml::{
    a2ml_error, a2ml_error_detail, a2ml_response,
    certificates_to_a2ml, inserted_to_a2ml,
    parse_certs, parse_recommendations, proof_attempts_to_a2ml,
    strategy_to_a2ml,
};

// ── Shared HTTP client (one per module, constructed lazily) ──────────────────

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

fn required_insert_token() -> Option<String> {
    std::env::var("VERISIM_PROOF_ATTEMPTS_TOKEN")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn provided_insert_token(headers: &HeaderMap) -> Option<String> {
    if let Some(v) = headers
        .get("x-proof-attempts-token")
        .and_then(|v| v.to_str().ok())
    {
        return Some(v.trim().to_string());
    }

    headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .map(|v| v.trim().to_string())
}

// ── Inbound proof-attempt row (matches echidnabot VeriSimWriter schema) ───────

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

// ── Query params ─────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ListParams {
    pub limit: Option<usize>,
    pub offset: Option<usize>,
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

// ── Handlers ─────────────────────────────────────────────────────────────────

/// GET /proof_attempts?limit=N&offset=M
///
/// Returns up to `limit` (default 1000, max 20000) recent proof-attempt rows
/// from ClickHouse as an A2ML document for retraining the Julia ML models.
pub async fn list_proof_attempts(
    Query(params): Query<ListParams>,
) -> Response {
    let limit = params.limit.unwrap_or(1000).clamp(1, 20000);
    let offset = params.offset.unwrap_or(0);

    let sql = format!(
        "SELECT attempt_id, obligation_id, repo, file, claim, obligation_class, \
                prover_used, outcome, duration_ms, confidence, parent_attempt_id, \
                strategy_tag, started_at, completed_at \
         FROM verisim.proof_attempts \
         ORDER BY started_at DESC \
         LIMIT {limit} \
         OFFSET {offset} \
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
            // Parse ClickHouse JSONEachRow internally (never emitted as JSON)
            let rows: Vec<serde_json::Value> = text
                .lines()
                .filter(|l| !l.trim().is_empty())
                .filter_map(|l| serde_json::from_str(l).ok())
                .collect();
            a2ml_response(StatusCode::OK, proof_attempts_to_a2ml(&rows))
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            let body = resp.text().await.unwrap_or_default();
            warn!("proof_attempts list: ClickHouse {status}: {body}");
            a2ml_response(StatusCode::BAD_GATEWAY, a2ml_error("clickhouse_error", status))
        }
        Err(e) => {
            warn!("proof_attempts list: unreachable: {e}");
            a2ml_response(StatusCode::SERVICE_UNAVAILABLE, a2ml_error("clickhouse_unreachable", 503))
        }
    }
}

/// POST /proof_attempts
///
/// Inserts a single attempt row into `verisim.proof_attempts` via the
/// ClickHouse HTTP INSERT … FORMAT JSONEachRow endpoint.
pub async fn insert_proof_attempt(
    headers: HeaderMap,
    axum::Json(row): axum::Json<ProofAttemptRow>,
) -> Response {
    if let Some(expected) = required_insert_token() {
        match provided_insert_token(&headers) {
            Some(provided) if provided == expected => {}
            Some(_) => {
                return a2ml_response(
                    StatusCode::UNAUTHORIZED,
                    a2ml_error_detail("invalid_proof_attempts_token", 401, "Token mismatch"),
                );
            }
            None => {
                return a2ml_response(
                    StatusCode::UNAUTHORIZED,
                    a2ml_error_detail(
                        "proof_attempts_auth_required",
                        401,
                        "Set X-Proof-Attempts-Token or Authorization: Bearer",
                    ),
                );
            }
        }
    }

    let url = format!(
        "{}/?query=INSERT+INTO+verisim.proof_attempts+FORMAT+JSONEachRow",
        ch_url()
    );

    // Serialise the inbound row to JSONEachRow for the ClickHouse wire format.
    // This is internal I/O to ClickHouse, not an outbound response.
    let body = match serde_json::to_string(&row) {
        Ok(s) => s,
        Err(e) => {
            warn!("proof_attempts: failed to serialise row: {e}");
            return a2ml_response(
                StatusCode::BAD_REQUEST,
                a2ml_error_detail("serialisation_failed", 400, &e.to_string()),
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
        Ok(resp) if resp.status().is_success() => {
            a2ml_response(StatusCode::CREATED, inserted_to_a2ml(&row.attempt_id))
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            let detail = resp.text().await.unwrap_or_default();
            warn!("proof_attempts: ClickHouse returned {status}: {detail}");
            a2ml_response(
                StatusCode::BAD_GATEWAY,
                a2ml_error_detail("clickhouse_error", status, &detail),
            )
        }
        Err(e) => {
            warn!("proof_attempts: ClickHouse unreachable: {e}");
            a2ml_response(
                StatusCode::SERVICE_UNAVAILABLE,
                a2ml_error_detail("clickhouse_unreachable", 503, &e.to_string()),
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
) -> Response {
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
            let recommendations = parse_recommendations(&text);
            a2ml_response(StatusCode::OK, strategy_to_a2ml(&recommendations))
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            let body = resp.text().await.unwrap_or_default();
            warn!("proof_attempts/strategy: ClickHouse {status}: {body}");
            a2ml_response(StatusCode::BAD_GATEWAY, a2ml_error("clickhouse_error", status))
        }
        Err(e) => {
            warn!("proof_attempts/strategy: unreachable: {e}");
            a2ml_response(StatusCode::SERVICE_UNAVAILABLE, a2ml_error("clickhouse_unreachable", 503))
        }
    }
}

/// GET /proof_attempts/certificates?class=X
///
/// Returns PROVEN / pending status for every (class, prover) pair from
/// `mv_proven_certificates`.
pub async fn certificates(
    Query(params): Query<ClassParam>,
) -> Response {
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
            let rows = parse_certs(&text);
            a2ml_response(StatusCode::OK, certificates_to_a2ml(&rows))
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            warn!("proof_attempts/certificates: ClickHouse {status}");
            a2ml_response(StatusCode::BAD_GATEWAY, a2ml_error("clickhouse_error", status))
        }
        Err(e) => {
            warn!("proof_attempts/certificates: unreachable: {e}");
            a2ml_response(StatusCode::SERVICE_UNAVAILABLE, a2ml_error("clickhouse_unreachable", 503))
        }
    }
}
