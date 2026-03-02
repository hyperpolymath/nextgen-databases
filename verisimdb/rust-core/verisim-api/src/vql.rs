// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! VQL execution endpoint — accepts VQL text queries, parses them, and
//! routes to the appropriate store operations.
//!
//! This is a lightweight server-side VQL parser that handles the core
//! query operations directly against the hexad store. It bridges the gap
//! between the REPL client (which sends raw VQL text) and the REST API
//! (which expects structured JSON requests).
//!
//! ## Supported VQL Statements
//!
//! - `SELECT [modalities] FROM hexads [WHERE id = '...'] [LIMIT n]`
//! - `SEARCH TEXT '<query>' [LIMIT n]`
//! - `SEARCH VECTOR [v1, v2, ...] [LIMIT n]`
//! - `SEARCH RELATED '<id>' [BY '<predicate>']`
//! - `INSERT INTO hexads (fields...) VALUES (values...)`
//! - `DELETE FROM hexads WHERE id = '<id>'`
//! - `SHOW STATUS` / `SHOW DRIFT` / `SHOW NORMALIZER`
//! - `SHOW HEXADS [LIMIT n]`
//! - `COUNT hexads`
//! - `EXPLAIN <query>`

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tracing::{info, instrument};

use verisim_hexad::{HexadId, HexadInput, HexadDocumentInput, HexadStore};

use crate::{ApiError, AppState, HexadResponse};

/// VQL execute request — wraps a raw VQL query string.
#[derive(Debug, Deserialize)]
pub struct VqlExecuteRequest {
    /// The VQL query text to parse and execute.
    pub query: String,
}

/// VQL execute response — returns structured results from a query.
#[derive(Debug, Serialize)]
pub struct VqlExecuteResponse {
    /// Whether the query executed successfully.
    pub success: bool,
    /// The type of statement that was executed.
    pub statement_type: String,
    /// Number of rows/items in the result.
    pub row_count: usize,
    /// The result data (schema depends on statement type).
    pub data: Value,
    /// Optional message (e.g., for INSERT/DELETE confirmations).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

/// Execute a VQL query string against the database.
///
/// Parses the query, determines the operation, executes it against the
/// hexad store, and returns structured results.
#[instrument(skip(state, request), fields(query = %request.query))]
pub async fn vql_execute_handler(
    State(state): State<AppState>,
    Json(request): Json<VqlExecuteRequest>,
) -> Result<Json<VqlExecuteResponse>, ApiError> {
    let query = request.query.trim();

    if query.is_empty() {
        return Err(ApiError::BadRequest("Empty query".to_string()));
    }

    // Normalize: strip trailing semicolons, collapse whitespace.
    let query = query.trim_end_matches(';').trim();

    // Parse and route the query.
    let tokens = tokenize(query);
    if tokens.is_empty() {
        return Err(ApiError::BadRequest("Empty query after parsing".to_string()));
    }

    let result = match tokens[0].to_uppercase().as_str() {
        "SELECT" => execute_select(&state, &tokens, query).await,
        "SEARCH" => execute_search(&state, &tokens).await,
        "INSERT" => execute_insert(&state, query).await,
        "DELETE" => execute_delete(&state, &tokens).await,
        "SHOW" => execute_show(&state, &tokens).await,
        "COUNT" => execute_count(&state, &tokens).await,
        "EXPLAIN" => execute_explain(&state, &tokens, query).await,
        other => Err(ApiError::BadRequest(format!(
            "Unknown VQL statement: '{}'. Supported: SELECT, SEARCH, INSERT, DELETE, SHOW, COUNT, EXPLAIN",
            other
        ))),
    }?;

    info!(
        statement_type = %result.statement_type,
        row_count = result.row_count,
        "VQL query executed"
    );

    Ok(Json(result))
}

/// Tokenize a VQL query into whitespace-separated tokens, respecting
/// quoted strings (single and double quotes).
fn tokenize(input: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut in_single_quote = false;
    let mut in_double_quote = false;

    for ch in input.chars() {
        match ch {
            '\'' if !in_double_quote => {
                in_single_quote = !in_single_quote;
                current.push(ch);
            }
            '"' if !in_single_quote => {
                in_double_quote = !in_double_quote;
                current.push(ch);
            }
            ' ' | '\t' | '\n' if !in_single_quote && !in_double_quote => {
                if !current.is_empty() {
                    tokens.push(std::mem::take(&mut current));
                }
            }
            _ => {
                current.push(ch);
            }
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }

    tokens
}

/// Strip surrounding quotes (single or double) from a string.
fn unquote(s: &str) -> &str {
    if (s.starts_with('\'') && s.ends_with('\'')) || (s.starts_with('"') && s.ends_with('"')) {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

/// Parse a LIMIT clause from the end of the token list.
/// Returns (limit_value, index_of_limit_keyword_or_end).
fn parse_limit(tokens: &[String]) -> (usize, usize) {
    for (i, token) in tokens.iter().enumerate() {
        if token.to_uppercase() == "LIMIT" {
            if let Some(next) = tokens.get(i + 1) {
                if let Ok(n) = next.parse::<usize>() {
                    return (n.min(1000), i);
                }
            }
        }
    }
    (100, tokens.len()) // default limit
}

// ---------------------------------------------------------------------------
// SELECT
// ---------------------------------------------------------------------------

/// Execute a SELECT query.
///
/// Supported forms:
/// - `SELECT * FROM hexads` — list all hexads
/// - `SELECT * FROM hexads WHERE id = '<id>'` — get one hexad
/// - `SELECT * FROM hexads LIMIT n` — list with limit
async fn execute_select(
    state: &AppState,
    tokens: &[String],
    _raw: &str,
) -> Result<VqlExecuteResponse, ApiError> {
    let (limit, _) = parse_limit(tokens);

    // Check for WHERE id = '...'
    let where_id = find_where_id(tokens);

    if let Some(id) = where_id {
        // Single hexad lookup
        let hexad_id = HexadId::new(id);
        let hexad = state
            .hexad_store
            .get(&hexad_id)
            .await
            .map_err(|e| ApiError::Internal(e.to_string()))?
            .ok_or_else(|| ApiError::NotFound(format!("Hexad '{}' not found", id)))?;

        let response = HexadResponse::from(&hexad);
        Ok(VqlExecuteResponse {
            success: true,
            statement_type: "SELECT".to_string(),
            row_count: 1,
            data: serde_json::to_value(vec![response])
                .map_err(|e| ApiError::Serialization(e.to_string()))?,
            message: None,
        })
    } else {
        // List hexads
        let hexads = state
            .hexad_store
            .list(limit, 0)
            .await
            .map_err(|e| ApiError::Internal(e.to_string()))?;

        let responses: Vec<HexadResponse> = hexads.iter().map(HexadResponse::from).collect();
        let count = responses.len();

        Ok(VqlExecuteResponse {
            success: true,
            statement_type: "SELECT".to_string(),
            row_count: count,
            data: serde_json::to_value(responses)
                .map_err(|e| ApiError::Serialization(e.to_string()))?,
            message: None,
        })
    }
}

/// Find `WHERE id = '<value>'` in token list.
fn find_where_id<'a>(tokens: &'a [String]) -> Option<&'a str> {
    for (i, token) in tokens.iter().enumerate() {
        if token.to_uppercase() == "WHERE" {
            // Expect: WHERE id = '<value>'
            if tokens.get(i + 1).map(|t| t.to_lowercase()) == Some("id".to_string()) {
                if tokens.get(i + 2).map(|t| t.as_str()) == Some("=") {
                    if let Some(val) = tokens.get(i + 3) {
                        return Some(unquote(val));
                    }
                }
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// SEARCH
// ---------------------------------------------------------------------------

/// Execute a SEARCH query.
///
/// Supported forms:
/// - `SEARCH TEXT '<query>' [LIMIT n]`
/// - `SEARCH VECTOR [v1, v2, ...] [LIMIT n]`
/// - `SEARCH RELATED '<id>' [BY '<predicate>']`
async fn execute_search(
    state: &AppState,
    tokens: &[String],
) -> Result<VqlExecuteResponse, ApiError> {
    if tokens.len() < 3 {
        return Err(ApiError::BadRequest(
            "SEARCH requires at least: SEARCH TEXT '<query>' or SEARCH VECTOR [...]".to_string(),
        ));
    }

    match tokens[1].to_uppercase().as_str() {
        "TEXT" => {
            let query_text = unquote(&tokens[2]);
            let (limit, _) = parse_limit(tokens);

            let hexads = state
                .hexad_store
                .search_text(query_text, limit)
                .await
                .map_err(|e| ApiError::Internal(e.to_string()))?;

            let results: Vec<Value> = hexads
                .iter()
                .enumerate()
                .map(|(i, h)| {
                    json!({
                        "id": h.id.to_string(),
                        "score": 1.0 - (i as f64 * 0.1),
                        "title": h.document.as_ref().map(|d| d.title.clone()),
                        "has_graph": h.graph_node.is_some(),
                        "has_vector": h.embedding.is_some(),
                        "has_document": h.document.is_some(),
                    })
                })
                .collect();

            let count = results.len();
            Ok(VqlExecuteResponse {
                success: true,
                statement_type: "SEARCH TEXT".to_string(),
                row_count: count,
                data: json!(results),
                message: None,
            })
        }
        "VECTOR" => {
            // Parse vector: [v1, v2, v3, ...]
            // Tokens after VECTOR up to LIMIT are the vector components.
            let (limit, limit_idx) = parse_limit(tokens);
            let vector_str: String = tokens[2..limit_idx].join(" ");
            let vector = parse_vector(&vector_str)?;

            if vector.len() != state.config.vector_dimension {
                return Err(ApiError::BadRequest(format!(
                    "Vector dimension mismatch: expected {}, got {}",
                    state.config.vector_dimension,
                    vector.len()
                )));
            }

            let hexads = state
                .hexad_store
                .search_similar(&vector, limit)
                .await
                .map_err(|e| ApiError::Internal(e.to_string()))?;

            let results: Vec<Value> = hexads
                .iter()
                .enumerate()
                .map(|(i, h)| {
                    json!({
                        "id": h.id.to_string(),
                        "score": 1.0 - (i as f64 * 0.1),
                        "title": h.document.as_ref().map(|d| d.title.clone()),
                    })
                })
                .collect();

            let count = results.len();
            Ok(VqlExecuteResponse {
                success: true,
                statement_type: "SEARCH VECTOR".to_string(),
                row_count: count,
                data: json!(results),
                message: None,
            })
        }
        "RELATED" => {
            if tokens.len() < 3 {
                return Err(ApiError::BadRequest(
                    "SEARCH RELATED requires: SEARCH RELATED '<id>' [BY '<predicate>']".to_string(),
                ));
            }
            let id = unquote(&tokens[2]);
            let hexad_id = HexadId::new(id);

            let predicate = tokens
                .iter()
                .position(|t| t.to_uppercase() == "BY")
                .and_then(|i| tokens.get(i + 1))
                .map(|t| unquote(t))
                .unwrap_or("related");

            let hexads = state
                .hexad_store
                .query_related(&hexad_id, predicate)
                .await
                .map_err(|e| ApiError::Internal(e.to_string()))?;

            let responses: Vec<HexadResponse> = hexads.iter().map(HexadResponse::from).collect();
            let count = responses.len();

            Ok(VqlExecuteResponse {
                success: true,
                statement_type: "SEARCH RELATED".to_string(),
                row_count: count,
                data: serde_json::to_value(responses)
                    .map_err(|e| ApiError::Serialization(e.to_string()))?,
                message: None,
            })
        }
        other => Err(ApiError::BadRequest(format!(
            "Unknown SEARCH type: '{}'. Use TEXT, VECTOR, or RELATED.",
            other
        ))),
    }
}

/// Parse a vector from a string like `[0.1, 0.2, 0.3]` or `0.1 0.2 0.3`.
fn parse_vector(s: &str) -> Result<Vec<f32>, ApiError> {
    let cleaned = s
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .replace(',', " ");

    let values: Result<Vec<f32>, _> = cleaned
        .split_whitespace()
        .filter(|s| !s.is_empty())
        .map(|v| v.parse::<f32>())
        .collect();

    values.map_err(|e| ApiError::BadRequest(format!("Invalid vector: {}", e)))
}

// ---------------------------------------------------------------------------
// INSERT
// ---------------------------------------------------------------------------

/// Execute an INSERT statement.
///
/// Supported form:
/// `INSERT INTO hexads (title, body) VALUES ('<title>', '<body>')`
///
/// Also accepts simplified form:
/// `INSERT '<title>' '<body>'`
async fn execute_insert(
    state: &AppState,
    raw: &str,
) -> Result<VqlExecuteResponse, ApiError> {
    let upper = raw.to_uppercase();

    let (title, body) = if upper.starts_with("INSERT INTO") {
        // Parse: INSERT INTO hexads (title, body) VALUES ('...', '...')
        parse_insert_values(raw)?
    } else {
        // Simplified: INSERT '<title>' '<body>'
        let tokens = tokenize(raw);
        if tokens.len() < 3 {
            return Err(ApiError::BadRequest(
                "INSERT requires: INSERT INTO hexads (title, body) VALUES ('<title>', '<body>')".to_string(),
            ));
        }
        (
            unquote(&tokens[1]).to_string(),
            unquote(&tokens[2]).to_string(),
        )
    };

    let mut input = HexadInput::default();
    input.document = Some(HexadDocumentInput {
        title: title.clone(),
        body,
        fields: std::collections::HashMap::new(),
    });

    let hexad = state
        .hexad_store
        .create(input)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let response = HexadResponse::from(&hexad);

    Ok(VqlExecuteResponse {
        success: true,
        statement_type: "INSERT".to_string(),
        row_count: 1,
        data: serde_json::to_value(vec![&response])
            .map_err(|e| ApiError::Serialization(e.to_string()))?,
        message: Some(format!("Inserted hexad '{}'", response.id)),
    })
}

/// Parse VALUES clause from INSERT INTO ... VALUES ('...', '...').
fn parse_insert_values(raw: &str) -> Result<(String, String), ApiError> {
    let upper = raw.to_uppercase();
    let values_idx = upper
        .find("VALUES")
        .ok_or_else(|| ApiError::BadRequest("INSERT INTO requires a VALUES clause".to_string()))?;

    let values_part = &raw[values_idx + 6..].trim();
    let values_part = values_part
        .trim_start_matches('(')
        .trim_end_matches(')');

    // Split on comma, respecting quotes.
    let value_tokens = tokenize(&values_part.replace(',', " "));

    let title = value_tokens
        .first()
        .map(|s| unquote(s).to_string())
        .unwrap_or_default();
    let body = value_tokens
        .get(1)
        .map(|s| unquote(s).to_string())
        .unwrap_or_default();

    Ok((title, body))
}

// ---------------------------------------------------------------------------
// DELETE
// ---------------------------------------------------------------------------

/// Execute a DELETE statement.
///
/// Supported form:
/// `DELETE FROM hexads WHERE id = '<id>'`
async fn execute_delete(
    state: &AppState,
    tokens: &[String],
) -> Result<VqlExecuteResponse, ApiError> {
    let id = find_where_id(tokens).ok_or_else(|| {
        ApiError::BadRequest(
            "DELETE requires: DELETE FROM hexads WHERE id = '<id>'".to_string(),
        )
    })?;

    let hexad_id = HexadId::new(id);

    state
        .hexad_store
        .delete(&hexad_id)
        .await
        .map_err(|e| match e {
            verisim_hexad::HexadError::NotFound(_) => {
                ApiError::NotFound(format!("Hexad '{}' not found", id))
            }
            _ => ApiError::Internal(e.to_string()),
        })?;

    Ok(VqlExecuteResponse {
        success: true,
        statement_type: "DELETE".to_string(),
        row_count: 1,
        data: json!(null),
        message: Some(format!("Deleted hexad '{}'", id)),
    })
}

// ---------------------------------------------------------------------------
// SHOW
// ---------------------------------------------------------------------------

/// Execute a SHOW query.
///
/// Supported forms:
/// - `SHOW STATUS` — server health
/// - `SHOW DRIFT` — drift metrics
/// - `SHOW NORMALIZER` — normalizer status
/// - `SHOW HEXADS [LIMIT n]` — list hexads (alias for SELECT)
async fn execute_show(
    state: &AppState,
    tokens: &[String],
) -> Result<VqlExecuteResponse, ApiError> {
    if tokens.len() < 2 {
        return Err(ApiError::BadRequest(
            "SHOW requires: SHOW STATUS | SHOW DRIFT | SHOW NORMALIZER | SHOW HEXADS".to_string(),
        ));
    }

    match tokens[1].to_uppercase().as_str() {
        "STATUS" | "HEALTH" => {
            let uptime = state.start_time.elapsed().as_secs();
            let version = env!("CARGO_PKG_VERSION");

            let health = state.drift_detector.health_check();
            let (status, reason) = match health {
                Ok(h) => {
                    use verisim_drift::HealthStatus;
                    match h.status {
                        HealthStatus::Critical | HealthStatus::Degraded => (
                            "degraded",
                            Some(format!("{:?}: {:.3}", h.worst_drift_type, h.worst_score)),
                        ),
                        _ => ("healthy", None),
                    }
                }
                Err(_) => ("degraded", Some("Drift detector unavailable".to_string())),
            };

            Ok(VqlExecuteResponse {
                success: true,
                statement_type: "SHOW STATUS".to_string(),
                row_count: 1,
                data: json!({
                    "status": status,
                    "version": version,
                    "uptime_seconds": uptime,
                    "degraded_reason": reason,
                }),
                message: None,
            })
        }
        "DRIFT" => {
            let all_metrics = state
                .drift_detector
                .all_metrics()
                .map_err(|e| ApiError::Internal(e.to_string()))?;

            let results: Vec<Value> = all_metrics
                .iter()
                .map(|(drift_type, metrics)| {
                    json!({
                        "drift_type": drift_type.to_string(),
                        "current_score": metrics.current_score,
                        "moving_average": metrics.moving_average,
                        "max_score": metrics.max_score,
                        "measurement_count": metrics.measurement_count,
                    })
                })
                .collect();

            let count = results.len();
            Ok(VqlExecuteResponse {
                success: true,
                statement_type: "SHOW DRIFT".to_string(),
                row_count: count,
                data: json!(results),
                message: None,
            })
        }
        "NORMALIZER" => {
            let status = state.normalizer.status().await;
            Ok(VqlExecuteResponse {
                success: true,
                statement_type: "SHOW NORMALIZER".to_string(),
                row_count: 1,
                data: serde_json::to_value(status)
                    .map_err(|e| ApiError::Serialization(e.to_string()))?,
                message: None,
            })
        }
        "HEXADS" => {
            let (limit, _) = parse_limit(tokens);
            let hexads = state
                .hexad_store
                .list(limit, 0)
                .await
                .map_err(|e| ApiError::Internal(e.to_string()))?;

            let responses: Vec<HexadResponse> = hexads.iter().map(HexadResponse::from).collect();
            let count = responses.len();

            Ok(VqlExecuteResponse {
                success: true,
                statement_type: "SHOW HEXADS".to_string(),
                row_count: count,
                data: serde_json::to_value(responses)
                    .map_err(|e| ApiError::Serialization(e.to_string()))?,
                message: None,
            })
        }
        other => Err(ApiError::BadRequest(format!(
            "Unknown SHOW target: '{}'. Use STATUS, DRIFT, NORMALIZER, or HEXADS.",
            other
        ))),
    }
}

// ---------------------------------------------------------------------------
// COUNT
// ---------------------------------------------------------------------------

/// Execute a COUNT query.
///
/// Supported form:
/// - `COUNT hexads` — return total hexad count
async fn execute_count(
    state: &AppState,
    _tokens: &[String],
) -> Result<VqlExecuteResponse, ApiError> {
    // List with a large limit to count (in a real DB this would be a COUNT query).
    let hexads = state
        .hexad_store
        .list(1000, 0)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let count = hexads.len();

    Ok(VqlExecuteResponse {
        success: true,
        statement_type: "COUNT".to_string(),
        row_count: 1,
        data: json!({ "count": count }),
        message: None,
    })
}

// ---------------------------------------------------------------------------
// EXPLAIN
// ---------------------------------------------------------------------------

/// Execute an EXPLAIN query — describes what a query would do without executing.
///
/// Supported form:
/// - `EXPLAIN <any VQL query>`
async fn execute_explain(
    _state: &AppState,
    tokens: &[String],
    raw: &str,
) -> Result<VqlExecuteResponse, ApiError> {
    if tokens.len() < 2 {
        return Err(ApiError::BadRequest("EXPLAIN requires a query to explain".to_string()));
    }

    let inner_query = &raw[raw.to_uppercase().find("EXPLAIN").unwrap() + 7..].trim();
    let inner_tokens = tokenize(inner_query);

    if inner_tokens.is_empty() {
        return Err(ApiError::BadRequest("EXPLAIN requires a query".to_string()));
    }

    let statement_type = inner_tokens[0].to_uppercase();
    let (limit, _) = parse_limit(&inner_tokens);
    let where_id = find_where_id(&inner_tokens);

    let plan = match statement_type.as_str() {
        "SELECT" => {
            if where_id.is_some() {
                json!({
                    "operation": "Point Lookup",
                    "target": "hexad_store",
                    "method": "get_by_id",
                    "cost": "O(1)",
                    "estimated_rows": 1,
                })
            } else {
                json!({
                    "operation": "Sequential Scan",
                    "target": "hexad_store",
                    "method": "list",
                    "limit": limit,
                    "cost": "O(n)",
                    "estimated_rows": limit,
                })
            }
        }
        "SEARCH" => {
            let search_type = inner_tokens.get(1).map(|t| t.to_uppercase()).unwrap_or_default();
            match search_type.as_str() {
                "TEXT" => json!({
                    "operation": "Full-Text Search",
                    "target": "tantivy_document_store",
                    "method": "search_text",
                    "limit": limit,
                    "cost": "O(log n)",
                    "index": "tantivy_inverted_index",
                }),
                "VECTOR" => json!({
                    "operation": "Approximate Nearest Neighbor",
                    "target": "hnsw_vector_store",
                    "method": "search_similar",
                    "limit": limit,
                    "cost": "O(log n)",
                    "index": "hnsw_graph",
                }),
                "RELATED" => json!({
                    "operation": "Graph Traversal",
                    "target": "oxigraph_store",
                    "method": "query_related",
                    "cost": "O(degree)",
                    "index": "rdf_triple_index",
                }),
                _ => json!({"operation": "Unknown search type"}),
            }
        }
        "INSERT" => json!({
            "operation": "Multi-Modal Insert",
            "targets": ["document_store", "graph_store", "vector_store", "semantic_store", "temporal_store"],
            "method": "create",
            "cost": "O(1) per modality",
        }),
        "DELETE" => json!({
            "operation": "Multi-Modal Delete",
            "targets": ["all_modality_stores"],
            "method": "delete",
            "cost": "O(1)",
        }),
        _ => json!({"operation": format!("Unrecognized: {}", statement_type)}),
    };

    Ok(VqlExecuteResponse {
        success: true,
        statement_type: "EXPLAIN".to_string(),
        row_count: 1,
        data: json!({
            "query": inner_query,
            "plan": plan,
        }),
        message: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tokenize_simple() {
        let tokens = tokenize("SELECT * FROM hexads");
        assert_eq!(tokens, vec!["SELECT", "*", "FROM", "hexads"]);
    }

    #[test]
    fn test_tokenize_quoted() {
        let tokens = tokenize("SEARCH TEXT 'hello world' LIMIT 10");
        assert_eq!(tokens, vec!["SEARCH", "TEXT", "'hello world'", "LIMIT", "10"]);
    }

    #[test]
    fn test_unquote() {
        assert_eq!(unquote("'hello'"), "hello");
        assert_eq!(unquote("\"hello\""), "hello");
        assert_eq!(unquote("hello"), "hello");
    }

    #[test]
    fn test_parse_limit() {
        let tokens: Vec<String> = vec!["SELECT", "*", "FROM", "hexads", "LIMIT", "50"]
            .into_iter()
            .map(String::from)
            .collect();
        let (limit, idx) = parse_limit(&tokens);
        assert_eq!(limit, 50);
        assert_eq!(idx, 4);
    }

    #[test]
    fn test_parse_limit_default() {
        let tokens: Vec<String> = vec!["SELECT", "*", "FROM", "hexads"]
            .into_iter()
            .map(String::from)
            .collect();
        let (limit, idx) = parse_limit(&tokens);
        assert_eq!(limit, 100);
        assert_eq!(idx, 4);
    }

    #[test]
    fn test_find_where_id() {
        let tokens: Vec<String> = vec!["SELECT", "*", "FROM", "hexads", "WHERE", "id", "=", "'abc-123'"]
            .into_iter()
            .map(String::from)
            .collect();
        assert_eq!(find_where_id(&tokens), Some("abc-123"));
    }

    #[test]
    fn test_parse_vector() {
        let v = parse_vector("[0.1, 0.2, 0.3]").unwrap();
        assert_eq!(v.len(), 3);
        assert!((v[0] - 0.1).abs() < 0.001);
    }
}
