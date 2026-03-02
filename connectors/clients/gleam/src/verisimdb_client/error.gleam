//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Error types and handling.
////
//// This module defines typed error variants for all failure modes that can
//// occur when communicating with a VeriSimDB server. Gleam's custom types
//// enable exhaustive pattern matching on all error variants.
////
//// The VeriSimDB server returns errors in a standard JSON envelope:
////   { "error": { "code": "HEXAD_NOT_FOUND", "message": "...", "details": {...} } }

import gleam/int

/// Typed error variants for VeriSimDB client operations.
///
/// Client errors (4xx), server errors (5xx), domain-specific errors, and
/// client-side errors are all represented as a single custom type for
/// exhaustive pattern matching.
pub type VeriSimError {
  // --- Client errors (4xx) ---
  /// HTTP 400 — Malformed request.
  BadRequest(message: String)
  /// HTTP 401 — Missing or invalid authentication.
  Unauthorized(message: String)
  /// HTTP 403 — Insufficient permissions.
  Forbidden(message: String)
  /// HTTP 404 — Resource does not exist.
  NotFound(message: String)
  /// HTTP 409 — Resource version conflict.
  Conflict(message: String)
  /// HTTP 422 — Input validation failure.
  ValidationFailed(message: String)
  /// HTTP 429 — Too many requests.
  RateLimited(message: String)

  // --- Server errors (5xx) ---
  /// HTTP 500 — Unexpected server error.
  InternalError(message: String)
  /// HTTP 503 — Server temporarily unavailable.
  ServiceUnavailable(message: String)

  // --- Domain-specific errors ---
  /// Hexad with given ID does not exist.
  HexadNotFound(message: String)
  /// Requested modality is not enabled.
  ModalityUnavailable(message: String)
  /// Drift score computation failed.
  DriftComputationError(message: String)
  /// Provenance chain integrity failure.
  ProvenanceInvalid(message: String)
  /// VQL syntax error.
  VqlParseError(message: String)
  /// VQL runtime error.
  VqlExecutionError(message: String)
  /// Federation peer communication failure.
  FederationError(message: String)

  // --- Client-side errors ---
  /// Network connectivity failure.
  ConnectionError(message: String)
  /// Request exceeded timeout.
  TimeoutError(message: String)
  /// JSON serialization/deserialization failure.
  SerializationError(message: String)
  /// Unrecognised error.
  UnknownError(message: String)
}

/// Extract a human-readable message from any error variant.
pub fn message(err: VeriSimError) -> String {
  case err {
    BadRequest(msg) -> "Bad request: " <> msg
    Unauthorized(msg) -> "Unauthorized: " <> msg
    Forbidden(msg) -> "Forbidden: " <> msg
    NotFound(msg) -> "Not found: " <> msg
    Conflict(msg) -> "Conflict: " <> msg
    ValidationFailed(msg) -> "Validation failed: " <> msg
    RateLimited(msg) -> "Rate limited: " <> msg
    InternalError(msg) -> "Internal server error: " <> msg
    ServiceUnavailable(msg) -> "Service unavailable: " <> msg
    HexadNotFound(msg) -> "Hexad not found: " <> msg
    ModalityUnavailable(msg) -> "Modality unavailable: " <> msg
    DriftComputationError(msg) -> "Drift computation error: " <> msg
    ProvenanceInvalid(msg) -> "Provenance invalid: " <> msg
    VqlParseError(msg) -> "VQL parse error: " <> msg
    VqlExecutionError(msg) -> "VQL execution error: " <> msg
    FederationError(msg) -> "Federation error: " <> msg
    ConnectionError(msg) -> "Connection error: " <> msg
    TimeoutError(msg) -> "Timeout error: " <> msg
    SerializationError(msg) -> "Serialization error: " <> msg
    UnknownError(msg) -> "Unknown error: " <> msg
  }
}

/// Construct an error variant from an HTTP status code.
///
/// Maps standard HTTP status codes to the appropriate error variant.
/// Used internally by other SDK modules when the server returns a non-success
/// status code.
pub fn from_status(status: Int) -> VeriSimError {
  case status {
    400 -> BadRequest("Bad request")
    401 -> Unauthorized("Authentication required")
    403 -> Forbidden("Insufficient permissions")
    404 -> NotFound("Resource not found")
    409 -> Conflict("Resource conflict")
    422 -> ValidationFailed("Input validation failed")
    429 -> RateLimited("Too many requests")
    500 -> InternalError("Internal server error")
    503 -> ServiceUnavailable("Server temporarily unavailable")
    _ -> UnknownError("Unexpected HTTP status: " <> int.to_string(status))
  }
}

/// Check whether an error is retryable.
///
/// Server errors (5xx), rate limiting (429), connection errors, and timeouts
/// are generally retryable. Client errors (4xx) are not.
pub fn is_retryable(err: VeriSimError) -> Bool {
  case err {
    RateLimited(_) -> True
    InternalError(_) -> True
    ServiceUnavailable(_) -> True
    ConnectionError(_) -> True
    TimeoutError(_) -> True
    BadRequest(_) -> False
    Unauthorized(_) -> False
    Forbidden(_) -> False
    NotFound(_) -> False
    Conflict(_) -> False
    ValidationFailed(_) -> False
    HexadNotFound(_) -> False
    ModalityUnavailable(_) -> False
    DriftComputationError(_) -> False
    ProvenanceInvalid(_) -> False
    VqlParseError(_) -> False
    VqlExecutionError(_) -> False
    FederationError(_) -> False
    SerializationError(_) -> False
    UnknownError(_) -> False
  }
}
