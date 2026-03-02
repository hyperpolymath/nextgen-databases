// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Error types for the VeriSimDB client SDK.
//!
//! All fallible operations in this crate return [`Result<T>`], which is an alias
//! for `std::result::Result<T, VeriSimError>`. The [`VeriSimError`] enum covers
//! network failures, serialization issues, server-side errors, validation
//! problems, and timeouts.

use thiserror::Error;

/// Comprehensive error type for VeriSimDB client operations.
///
/// Each variant carries enough context for callers to decide whether to retry,
/// surface a user-facing message, or escalate.
#[derive(Error, Debug)]
pub enum VeriSimError {
    /// The requested entity (hexad, peer, provenance record) was not found.
    #[error("Entity not found: {0}")]
    NotFound(String),

    /// Authentication or authorization failed. Check API key / bearer token.
    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    /// An underlying HTTP / network transport error from `reqwest`.
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    /// JSON serialization or deserialization failed.
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    /// The server returned an HTTP error status with a message body.
    #[error("Server error ({status}): {message}")]
    Server {
        /// HTTP status code (e.g. 500, 502, 503).
        status: u16,
        /// Human-readable error message from the server response body.
        message: String,
    },

    /// Client-side validation failed before the request was sent.
    #[error("Validation error: {0}")]
    Validation(String),

    /// The request exceeded the configured timeout duration.
    #[error("Timeout after {0}ms")]
    Timeout(u64),
}

/// Crate-level result alias using [`VeriSimError`].
pub type Result<T> = std::result::Result<T, VeriSimError>;
