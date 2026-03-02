# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Error types and handling.
#
# This file defines custom exception types for all failure modes that can occur
# when communicating with a VeriSimDB server. Each error category is a concrete
# subtype of VeriSimError, allowing callers to catch specific error classes or
# handle all VeriSimDB errors generically.

"""
    VeriSimError <: Exception

Abstract base type for all VeriSimDB client errors. Subtypes represent
specific failure categories (HTTP errors, domain errors, client-side errors).
"""
abstract type VeriSimError <: Exception end

# ---------------------------------------------------------------------------
# HTTP client errors (4xx)
# ---------------------------------------------------------------------------

"""HTTP 400 — Malformed request."""
struct BadRequestError <: VeriSimError
    message::String
    details::Dict{String,String}
end
BadRequestError(msg::String) = BadRequestError(msg, Dict{String,String}())

"""HTTP 401 — Missing or invalid authentication."""
struct UnauthorizedError <: VeriSimError
    message::String
end

"""HTTP 403 — Insufficient permissions."""
struct ForbiddenError <: VeriSimError
    message::String
end

"""HTTP 404 — Resource does not exist."""
struct NotFoundError <: VeriSimError
    message::String
end

"""HTTP 409 — Resource version conflict."""
struct ConflictError <: VeriSimError
    message::String
end

"""HTTP 422 — Input validation failure."""
struct ValidationError <: VeriSimError
    message::String
    details::Dict{String,String}
end
ValidationError(msg::String) = ValidationError(msg, Dict{String,String}())

"""HTTP 429 — Too many requests."""
struct RateLimitedError <: VeriSimError
    message::String
    retry_after::Union{Int,Nothing}
end
RateLimitedError(msg::String) = RateLimitedError(msg, nothing)

# ---------------------------------------------------------------------------
# HTTP server errors (5xx)
# ---------------------------------------------------------------------------

"""HTTP 500 — Unexpected server error."""
struct InternalServerError <: VeriSimError
    message::String
end

"""HTTP 503 — Server temporarily unavailable."""
struct ServiceUnavailableError <: VeriSimError
    message::String
end

# ---------------------------------------------------------------------------
# Domain-specific errors
# ---------------------------------------------------------------------------

"""Hexad with given ID does not exist."""
struct HexadNotFoundError <: VeriSimError
    hexad_id::String
    message::String
end

"""Requested modality is not enabled on the hexad."""
struct ModalityUnavailableError <: VeriSimError
    modality::String
    message::String
end

"""Drift score computation failed."""
struct DriftComputationError <: VeriSimError
    message::String
end

"""Provenance chain integrity failure."""
struct ProvenanceInvalidError <: VeriSimError
    hexad_id::String
    message::String
end

"""VQL syntax error."""
struct VqlParseError <: VeriSimError
    query::String
    message::String
end

"""VQL runtime error."""
struct VqlExecutionError <: VeriSimError
    query::String
    message::String
end

"""Federation peer communication failure."""
struct FederationError <: VeriSimError
    peer_id::Union{String,Nothing}
    message::String
end
FederationError(msg::String) = FederationError(nothing, msg)

# ---------------------------------------------------------------------------
# Client-side errors
# ---------------------------------------------------------------------------

"""Network connectivity failure."""
struct ConnectionError <: VeriSimError
    message::String
end

"""Request exceeded timeout."""
struct TimeoutError <: VeriSimError
    message::String
    timeout_ms::Int
end

"""JSON serialization/deserialization failure."""
struct SerializationError <: VeriSimError
    message::String
end

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

"""
    is_retryable(err::VeriSimError) -> Bool

Check whether an error is retryable. Server errors (5xx), rate limiting (429),
connection errors, and timeouts are generally retryable. Client errors (4xx)
are not, as they indicate a problem with the request itself.
"""
function is_retryable(err::VeriSimError)::Bool
    return err isa RateLimitedError ||
           err isa InternalServerError ||
           err isa ServiceUnavailableError ||
           err isa ConnectionError ||
           err isa TimeoutError
end

"""
    error_from_status(status::Int, body::String) -> VeriSimError

Construct an appropriate VeriSimError subtype from an HTTP status code and
response body. Used internally by other SDK modules when the server returns
a non-success status code.
"""
function error_from_status(status::Int, body::String)::VeriSimError
    msg = isempty(body) ? "HTTP $status" : body
    if status == 400
        return BadRequestError(msg)
    elseif status == 401
        return UnauthorizedError(msg)
    elseif status == 403
        return ForbiddenError(msg)
    elseif status == 404
        return NotFoundError(msg)
    elseif status == 409
        return ConflictError(msg)
    elseif status == 422
        return ValidationError(msg)
    elseif status == 429
        return RateLimitedError(msg)
    elseif status == 500
        return InternalServerError(msg)
    elseif status == 503
        return ServiceUnavailableError(msg)
    else
        return InternalServerError("Unexpected HTTP status $status: $msg")
    end
end

# Implement Base.showerror for pretty-printing VeriSimDB errors.
Base.showerror(io::IO, e::VeriSimError) = print(io, "VeriSimDB Error: ", e.message)
