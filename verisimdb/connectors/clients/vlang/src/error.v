// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Error types and handling.
//
// This module defines typed error variants for all failure modes that can
// occur when communicating with a VeriSimDB server. Errors are structured
// to provide actionable information: HTTP status codes, server-side error
// codes, and human-readable messages.
//
// The VeriSimDB server returns errors in a standard JSON envelope:
//   { "error": { "code": "HEXAD_NOT_FOUND", "message": "...", "details": {...} } }

module verisimdb_client

import json

// VeriSimErrorCode enumerates the server-side error codes returned by VeriSimDB.
pub enum VeriSimErrorCode {
	// Client errors (4xx)
	bad_request          // 400 — malformed request
	unauthorized         // 401 — missing or invalid authentication
	forbidden            // 403 — insufficient permissions
	not_found            // 404 — resource does not exist
	conflict             // 409 — resource version conflict
	validation_failed    // 422 — input validation failure
	rate_limited         // 429 — too many requests
	// Server errors (5xx)
	internal_error       // 500 — unexpected server error
	service_unavailable  // 503 — server temporarily unavailable
	// Domain-specific errors
	hexad_not_found      // Hexad with given ID does not exist
	modality_unavailable // Requested modality is not enabled
	drift_computation    // Drift score computation failed
	provenance_invalid   // Provenance chain integrity failure
	vql_parse_error      // VQL syntax error
	vql_execution_error  // VQL runtime error
	federation_error     // Federation peer communication failure
	// Client-side errors
	connection_error     // Network connectivity failure
	timeout_error        // Request exceeded timeout
	serialization_error  // JSON encode/decode failure
	unknown              // Unrecognised error code
}

// VeriSimError represents a structured error from VeriSimDB.
pub struct VeriSimError {
pub:
	code       VeriSimErrorCode
	message    string
	status     int              // HTTP status code (0 for client-side errors)
	details    map[string]string
	raw_body   string           // Original response body for debugging
}

// ServerErrorEnvelope matches the JSON structure returned by the VeriSimDB server.
struct ServerErrorEnvelope {
	error ServerErrorPayload
}

// ServerErrorPayload is the inner error object within the server's JSON response.
struct ServerErrorPayload {
	code    string
	message string
	details map[string]string
}

// parse_error_response attempts to parse a VeriSimDB error response body
// into a structured VeriSimError. If parsing fails, it wraps the raw body
// in a generic error.
//
// Parameters:
//   body — The raw HTTP response body.
//
// Returns:
//   A VeriSimError with parsed fields, or a generic error wrapping the raw body.
fn parse_error_response(body string) VeriSimError {
	envelope := json.decode(ServerErrorEnvelope, body) or {
		return VeriSimError{
			code: .unknown
			message: 'Failed to parse error response'
			raw_body: body
		}
	}
	return VeriSimError{
		code: string_to_error_code(envelope.error.code)
		message: envelope.error.message
		details: envelope.error.details
		raw_body: body
	}
}

// string_to_error_code converts a server error code string to a VeriSimErrorCode enum.
//
// Parameters:
//   s — The error code string from the server (e.g. "HEXAD_NOT_FOUND").
//
// Returns:
//   The corresponding VeriSimErrorCode variant, or .unknown for unrecognised codes.
fn string_to_error_code(s string) VeriSimErrorCode {
	return match s {
		'BAD_REQUEST' { .bad_request }
		'UNAUTHORIZED' { .unauthorized }
		'FORBIDDEN' { .forbidden }
		'NOT_FOUND' { .not_found }
		'CONFLICT' { .conflict }
		'VALIDATION_FAILED' { .validation_failed }
		'RATE_LIMITED' { .rate_limited }
		'INTERNAL_ERROR' { .internal_error }
		'SERVICE_UNAVAILABLE' { .service_unavailable }
		'HEXAD_NOT_FOUND' { .hexad_not_found }
		'MODALITY_UNAVAILABLE' { .modality_unavailable }
		'DRIFT_COMPUTATION' { .drift_computation }
		'PROVENANCE_INVALID' { .provenance_invalid }
		'VQL_PARSE_ERROR' { .vql_parse_error }
		'VQL_EXECUTION_ERROR' { .vql_execution_error }
		'FEDERATION_ERROR' { .federation_error }
		else { .unknown }
	}
}
