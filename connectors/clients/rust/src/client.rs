// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! VeriSimDB client configuration, authentication, and HTTP transport layer.
//!
//! [`VeriSimClient`] is the primary entry point for all SDK operations. It owns
//! the base URL, HTTP client, authentication credentials, and timeout settings.
//! Domain-specific methods (hexad CRUD, search, drift, etc.) are defined as
//! `impl VeriSimClient` blocks in their respective modules.

use std::time::Duration;

use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE};
use serde::de::DeserializeOwned;
use serde::Serialize;
use url::Url;

use crate::error::{Result, VeriSimError};
use crate::types::ErrorResponse;

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Authentication method for connecting to a VeriSimDB instance.
#[derive(Debug, Clone)]
pub enum Auth {
    /// No authentication (local development, trusted networks).
    None,
    /// API key passed via the `X-API-Key` header.
    ApiKey(String),
    /// Bearer token passed via the `Authorization: Bearer <token>` header.
    Bearer(String),
    /// HTTP Basic authentication.
    Basic {
        /// Username.
        username: String,
        /// Password.
        password: String,
    },
}

// ---------------------------------------------------------------------------
// VeriSimClient
// ---------------------------------------------------------------------------

/// The main VeriSimDB client.
///
/// Holds connection parameters and provides low-level HTTP helpers that the
/// higher-level module methods (`hexad`, `search`, `drift`, etc.) delegate to.
///
/// # Examples
///
/// ```rust,no_run
/// use verisimdb_client::client::VeriSimClient;
///
/// # #[tokio::main]
/// # async fn main() -> verisimdb_client::error::Result<()> {
/// let client = VeriSimClient::new("http://localhost:8080")?;
/// assert!(client.health().await?);
/// # Ok(())
/// # }
/// ```
pub struct VeriSimClient {
    /// Parsed base URL of the VeriSimDB instance (e.g. `http://localhost:8080`).
    base_url: Url,
    /// Underlying `reqwest` HTTP client (connection-pooled, TLS-capable).
    http: reqwest::Client,
    /// Authentication credentials.
    auth: Auth,
    /// Per-request timeout.
    timeout: Duration,
}

impl VeriSimClient {
    // -- Constructors -------------------------------------------------------

    /// Create a new unauthenticated client pointing at `base_url`.
    ///
    /// # Errors
    ///
    /// Returns [`VeriSimError::Validation`] if `base_url` cannot be parsed.
    pub fn new(base_url: &str) -> Result<Self> {
        Self::build(base_url, Auth::None)
    }

    /// Create a client that authenticates via an API key header.
    pub fn with_api_key(base_url: &str, key: &str) -> Result<Self> {
        Self::build(base_url, Auth::ApiKey(key.to_owned()))
    }

    /// Create a client that authenticates via a bearer token.
    pub fn with_bearer(base_url: &str, token: &str) -> Result<Self> {
        Self::build(base_url, Auth::Bearer(token.to_owned()))
    }

    /// Create a client that authenticates via HTTP Basic credentials.
    pub fn with_basic(base_url: &str, username: &str, password: &str) -> Result<Self> {
        Self::build(
            base_url,
            Auth::Basic {
                username: username.to_owned(),
                password: password.to_owned(),
            },
        )
    }

    /// Internal builder shared by all constructors.
    fn build(base_url: &str, auth: Auth) -> Result<Self> {
        let base_url = Url::parse(base_url)
            .map_err(|e| VeriSimError::Validation(format!("Invalid base URL: {e}")))?;

        let timeout = Duration::from_secs(30);

        let http = reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .map_err(VeriSimError::Network)?;

        Ok(Self {
            base_url,
            http,
            auth,
            timeout,
        })
    }

    // -- Health check -------------------------------------------------------

    /// Ping the VeriSimDB health endpoint.
    ///
    /// Returns `true` if the server is reachable and reports healthy.
    pub async fn health(&self) -> Result<bool> {
        let url = self.url("/health");
        let response = self.apply_auth(self.http.get(url)).send().await?;
        Ok(response.status().is_success())
    }

    // -- Public timeout accessor --------------------------------------------

    /// Return the configured per-request timeout.
    pub fn timeout(&self) -> Duration {
        self.timeout
    }

    /// Set a custom per-request timeout.
    pub fn set_timeout(&mut self, timeout: Duration) {
        self.timeout = timeout;
    }

    // -- Internal HTTP helpers ----------------------------------------------

    /// Build a full URL by joining `path` onto the base URL.
    pub(crate) fn url(&self, path: &str) -> Url {
        // Unwrap is safe: path is always a well-formed relative segment.
        self.base_url.join(path).expect("valid path join")
    }

    /// Attach authentication headers to an outgoing request builder.
    pub(crate) fn apply_auth(
        &self,
        builder: reqwest::RequestBuilder,
    ) -> reqwest::RequestBuilder {
        match &self.auth {
            Auth::None => builder,
            Auth::ApiKey(key) => builder.header("X-API-Key", key.as_str()),
            Auth::Bearer(token) => {
                let value = format!("Bearer {token}");
                builder.header(AUTHORIZATION, value)
            }
            Auth::Basic { username, password } => {
                builder.basic_auth(username, Some(password))
            }
        }
    }

    /// Perform a GET request and deserialize the JSON response body.
    pub(crate) async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let url = self.url(path);
        let response = self
            .apply_auth(self.http.get(url))
            .send()
            .await
            .map_err(VeriSimError::Network)?;

        self.handle_response(response).await
    }

    /// Perform a POST request with a JSON body and deserialize the response.
    pub(crate) async fn post<B: Serialize, T: DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T> {
        let url = self.url(path);
        let response = self
            .apply_auth(self.http.post(url))
            .json(body)
            .send()
            .await
            .map_err(VeriSimError::Network)?;

        self.handle_response(response).await
    }

    /// Perform a PUT request with a JSON body and deserialize the response.
    pub(crate) async fn put<B: Serialize, T: DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T> {
        let url = self.url(path);
        let response = self
            .apply_auth(self.http.put(url))
            .json(body)
            .send()
            .await
            .map_err(VeriSimError::Network)?;

        self.handle_response(response).await
    }

    /// Perform a DELETE request. Returns `()` on success.
    pub(crate) async fn delete(&self, path: &str) -> Result<()> {
        let url = self.url(path);
        let response = self
            .apply_auth(self.http.delete(url))
            .send()
            .await
            .map_err(VeriSimError::Network)?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err(self.extract_error(response).await)
        }
    }

    // -- Response handling --------------------------------------------------

    /// Deserialize a successful response or extract an error from the body.
    async fn handle_response<T: DeserializeOwned>(
        &self,
        response: reqwest::Response,
    ) -> Result<T> {
        let status = response.status();

        if status.is_success() {
            let body = response.text().await.map_err(VeriSimError::Network)?;
            serde_json::from_str(&body).map_err(VeriSimError::Serialization)
        } else {
            Err(self.extract_error(response).await)
        }
    }

    /// Turn a non-2xx response into the appropriate [`VeriSimError`] variant.
    async fn extract_error(&self, response: reqwest::Response) -> VeriSimError {
        let status = response.status().as_u16();

        // Attempt to parse a structured error body.
        let message = match response.json::<ErrorResponse>().await {
            Ok(err_body) => err_body.message,
            Err(_) => format!("HTTP {status}"),
        };

        match status {
            404 => VeriSimError::NotFound(message),
            401 | 403 => VeriSimError::Unauthorized(message),
            _ => VeriSimError::Server { status, message },
        }
    }
}
