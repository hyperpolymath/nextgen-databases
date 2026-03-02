// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! HTTP client for communicating with the verisim-api server.
//!
//! Wraps `reqwest::blocking::Client` and provides typed methods for
//! VQL query execution, EXPLAIN output, and health checks.

use reqwest::blocking::Client;
use serde_json::Value;

/// Error type for VQL client operations.
#[derive(Debug)]
pub enum ClientError {
    /// HTTP transport or connection error.
    Http(reqwest::Error),
    /// Server returned a non-success status code.
    Server { status: u16, body: String },
    /// Failed to parse response body as JSON.
    Parse(String),
}

impl std::fmt::Display for ClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ClientError::Http(err) => write!(f, "Connection error: {err}"),
            ClientError::Server { status, body } => {
                write!(f, "Server error (HTTP {status}): {body}")
            }
            ClientError::Parse(msg) => write!(f, "Parse error: {msg}"),
        }
    }
}

impl std::error::Error for ClientError {}

impl From<reqwest::Error> for ClientError {
    fn from(err: reqwest::Error) -> Self {
        ClientError::Http(err)
    }
}

/// HTTP client for the VeriSimDB API.
///
/// All methods use blocking I/O so they can be called directly from the
/// synchronous REPL loop without an async runtime.
pub struct VqlClient {
    /// Base URL of the verisim-api server (e.g. `http://localhost:8080`).
    base_url: String,
    /// Underlying HTTP client (connection-pooled).
    http: Client,
}

impl VqlClient {
    /// Create a new client pointing at the given base URL.
    ///
    /// The URL should include the scheme and port but no trailing slash.
    /// Example: `http://localhost:8080`
    pub fn new(base_url: &str) -> Self {
        // Install ring as the default crypto provider (pure Rust, no OpenSSL/aws-lc-sys)
        let _ = rustls::crypto::ring::default_provider().install_default();

        let base_url = base_url.trim_end_matches('/').to_string();
        let http = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("failed to build HTTP client");
        Self { base_url, http }
    }

    /// Return the current base URL.
    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    /// Execute a VQL query string.
    ///
    /// Sends `POST /vql/execute` with body `{"query": "<vql>"}`.
    /// Returns the raw JSON response from the server.
    pub fn execute(&self, query: &str) -> Result<Value, ClientError> {
        let url = format!("{}/vql/execute", self.base_url);
        let payload = serde_json::json!({ "query": query });

        let response = self.http.post(&url).json(&payload).send()?;
        self.handle_response(response)
    }

    /// Request EXPLAIN output for a VQL query.
    ///
    /// Sends the query through the VQL execute endpoint with an EXPLAIN
    /// prefix, which returns a query plan without executing the query.
    pub fn explain(&self, query: &str) -> Result<Value, ClientError> {
        let url = format!("{}/vql/execute", self.base_url);
        let explain_query = format!("EXPLAIN {}", query);
        let payload = serde_json::json!({ "query": explain_query });

        let response = self.http.post(&url).json(&payload).send()?;
        self.handle_response(response)
    }

    /// Check server health.
    ///
    /// Sends `GET /health` and returns the health response JSON.
    pub fn health(&self) -> Result<Value, ClientError> {
        let url = format!("{}/health", self.base_url);
        let response = self.http.get(&url).send()?;
        self.handle_response(response)
    }

    /// Parse an HTTP response into a `serde_json::Value`.
    ///
    /// Returns `ClientError::Server` for non-2xx status codes, and
    /// `ClientError::Parse` if the body is not valid JSON.
    fn handle_response(&self, response: reqwest::blocking::Response) -> Result<Value, ClientError> {
        let status = response.status().as_u16();
        let body = response.text()?;

        if !(200..300).contains(&status) {
            return Err(ClientError::Server { status, body });
        }

        serde_json::from_str(&body).map_err(|e| ClientError::Parse(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_creation() {
        let client = VqlClient::new("http://localhost:8080");
        assert_eq!(client.base_url(), "http://localhost:8080");
    }

    #[test]
    fn test_trailing_slash_stripped() {
        let client = VqlClient::new("http://localhost:8080/");
        assert_eq!(client.base_url(), "http://localhost:8080");
    }

    #[test]
    fn test_client_error_display() {
        let err = ClientError::Server {
            status: 404,
            body: "not found".to_string(),
        };
        let msg = format!("{err}");
        assert!(msg.contains("404"));
        assert!(msg.contains("not found"));
    }
}
