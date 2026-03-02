// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Error types and handling.
//
// This module defines typed error variants for all failure modes that can
// occur when communicating with a VeriSimDB server. Errors are structured
// to provide actionable information: HTTP status codes, server-side error
// codes, and human-readable messages.

/** Typed error variants for VeriSimDB client operations.
 *
 * Client errors (4xx), server errors (5xx), domain-specific errors, and
 * client-side errors are all represented as a single variant type for
 * exhaustive pattern matching.
 */
type t =
  // --- Client errors (4xx) ---
  | BadRequest(string)
  | Unauthorized(string)
  | Forbidden(string)
  | NotFound(string)
  | Conflict(string)
  | ValidationFailed(string)
  | RateLimited(string)
  // --- Server errors (5xx) ---
  | InternalError(string)
  | ServiceUnavailable(string)
  // --- Domain-specific errors ---
  | HexadNotFound(string)
  | ModalityUnavailable(string)
  | DriftComputationError(string)
  | ProvenanceInvalid(string)
  | VqlParseError(string)
  | VqlExecutionError(string)
  | FederationError(string)
  // --- Client-side errors ---
  | ConnectionError(string)
  | TimeoutError(string)
  | SerializationError(string)
  | UnknownError(string)

/** Extract a human-readable message from any error variant.
 *
 * @param err The error variant.
 * @returns A string describing the error.
 */
let message = (err: t): string => {
  switch err {
  | BadRequest(msg) => `Bad request: ${msg}`
  | Unauthorized(msg) => `Unauthorized: ${msg}`
  | Forbidden(msg) => `Forbidden: ${msg}`
  | NotFound(msg) => `Not found: ${msg}`
  | Conflict(msg) => `Conflict: ${msg}`
  | ValidationFailed(msg) => `Validation failed: ${msg}`
  | RateLimited(msg) => `Rate limited: ${msg}`
  | InternalError(msg) => `Internal server error: ${msg}`
  | ServiceUnavailable(msg) => `Service unavailable: ${msg}`
  | HexadNotFound(msg) => `Hexad not found: ${msg}`
  | ModalityUnavailable(msg) => `Modality unavailable: ${msg}`
  | DriftComputationError(msg) => `Drift computation error: ${msg}`
  | ProvenanceInvalid(msg) => `Provenance invalid: ${msg}`
  | VqlParseError(msg) => `VQL parse error: ${msg}`
  | VqlExecutionError(msg) => `VQL execution error: ${msg}`
  | FederationError(msg) => `Federation error: ${msg}`
  | ConnectionError(msg) => `Connection error: ${msg}`
  | TimeoutError(msg) => `Timeout error: ${msg}`
  | SerializationError(msg) => `Serialization error: ${msg}`
  | UnknownError(msg) => `Unknown error: ${msg}`
  }
}

/** Construct an error variant from an HTTP status code.
 *
 * Maps standard HTTP status codes to the appropriate error variant.
 * Used internally by other SDK modules when the server returns a non-success
 * status code.
 *
 * @param status The HTTP status code.
 * @returns The appropriate error variant with a default message.
 */
let fromStatus = (status: int): t => {
  switch status {
  | 400 => BadRequest("Bad request")
  | 401 => Unauthorized("Authentication required")
  | 403 => Forbidden("Insufficient permissions")
  | 404 => NotFound("Resource not found")
  | 409 => Conflict("Resource conflict")
  | 422 => ValidationFailed("Input validation failed")
  | 429 => RateLimited("Too many requests")
  | 500 => InternalError("Internal server error")
  | 503 => ServiceUnavailable("Server temporarily unavailable")
  | code => UnknownError(`Unexpected HTTP status: ${Int.toString(code)}`)
  }
}

/** Check whether an error is retryable.
 *
 * Server errors (5xx) and rate limiting (429) are generally retryable.
 * Client errors (4xx) are not, as they indicate a problem with the request.
 *
 * @param err The error to check.
 * @returns true if the operation can be safely retried.
 */
let isRetryable = (err: t): bool => {
  switch err {
  | RateLimited(_) => true
  | InternalError(_) => true
  | ServiceUnavailable(_) => true
  | ConnectionError(_) => true
  | TimeoutError(_) => true
  | BadRequest(_) => false
  | Unauthorized(_) => false
  | Forbidden(_) => false
  | NotFound(_) => false
  | Conflict(_) => false
  | ValidationFailed(_) => false
  | HexadNotFound(_) => false
  | ModalityUnavailable(_) => false
  | DriftComputationError(_) => false
  | ProvenanceInvalid(_) => false
  | VqlParseError(_) => false
  | VqlExecutionError(_) => false
  | FederationError(_) => false
  | SerializationError(_) => false
  | UnknownError(_) => false
  }
}
