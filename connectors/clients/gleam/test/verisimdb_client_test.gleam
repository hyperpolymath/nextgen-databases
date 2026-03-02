//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Test suite.
////
//// Basic unit tests for the verisimdb_client package. These tests validate
//// type construction, error handling, and client configuration without
//// requiring a running VeriSimDB server.

import gleam/dict
import gleam/option
import gleeunit
import gleeunit/should
import verisimdb_client.{ApiKey, Basic, Bearer, Client, NoAuth}
import verisimdb_client/error
import verisimdb_client/types

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Client construction tests
// ---------------------------------------------------------------------------

pub fn new_client_test() {
  let client = verisimdb_client.new("http://localhost:8080")
  should.equal(client.base_url, "http://localhost:8080")
  should.equal(client.timeout, 30_000)
  should.equal(client.auth, NoAuth)
}

pub fn new_client_strips_trailing_slash_test() {
  let client = verisimdb_client.new("http://localhost:8080/")
  should.equal(client.base_url, "http://localhost:8080")
}

pub fn new_client_with_api_key_test() {
  let client =
    verisimdb_client.new_with_api_key("http://localhost:8080", "test-key")
  should.equal(client.auth, ApiKey("test-key"))
}

pub fn new_client_with_bearer_test() {
  let client =
    verisimdb_client.new_with_bearer("http://localhost:8080", "my-token")
  should.equal(client.auth, Bearer("my-token"))
}

pub fn new_client_with_basic_auth_test() {
  let client =
    verisimdb_client.new_with_auth(
      "http://localhost:8080",
      Basic("user", "pass"),
    )
  should.equal(client.auth, Basic("user", "pass"))
}

// ---------------------------------------------------------------------------
// Modality tests
// ---------------------------------------------------------------------------

pub fn modality_to_string_test() {
  should.equal(types.modality_to_string(types.Graph), "graph")
  should.equal(types.modality_to_string(types.Vector), "vector")
  should.equal(types.modality_to_string(types.Tensor), "tensor")
  should.equal(types.modality_to_string(types.Semantic), "semantic")
  should.equal(types.modality_to_string(types.Document), "document")
  should.equal(types.modality_to_string(types.Temporal), "temporal")
  should.equal(types.modality_to_string(types.Provenance), "provenance")
  should.equal(types.modality_to_string(types.Spatial), "spatial")
}

pub fn modality_from_string_test() {
  should.equal(types.modality_from_string("graph"), option.Some(types.Graph))
  should.equal(types.modality_from_string("vector"), option.Some(types.Vector))
  should.equal(types.modality_from_string("unknown"), option.None)
}

// ---------------------------------------------------------------------------
// Error tests
// ---------------------------------------------------------------------------

pub fn error_from_status_test() {
  should.equal(error.from_status(400), error.BadRequest("Bad request"))
  should.equal(
    error.from_status(401),
    error.Unauthorized("Authentication required"),
  )
  should.equal(
    error.from_status(403),
    error.Forbidden("Insufficient permissions"),
  )
  should.equal(error.from_status(404), error.NotFound("Resource not found"))
  should.equal(error.from_status(409), error.Conflict("Resource conflict"))
  should.equal(
    error.from_status(422),
    error.ValidationFailed("Input validation failed"),
  )
  should.equal(error.from_status(429), error.RateLimited("Too many requests"))
  should.equal(
    error.from_status(500),
    error.InternalError("Internal server error"),
  )
  should.equal(
    error.from_status(503),
    error.ServiceUnavailable("Server temporarily unavailable"),
  )
}

pub fn error_is_retryable_test() {
  // Retryable
  should.be_true(error.is_retryable(error.RateLimited("slow down")))
  should.be_true(error.is_retryable(error.InternalError("oops")))
  should.be_true(error.is_retryable(error.ServiceUnavailable("busy")))
  should.be_true(error.is_retryable(error.ConnectionError("disconnected")))
  should.be_true(error.is_retryable(error.TimeoutError("too slow")))

  // Not retryable
  should.be_false(error.is_retryable(error.BadRequest("bad")))
  should.be_false(error.is_retryable(error.Unauthorized("no auth")))
  should.be_false(error.is_retryable(error.NotFound("missing")))
  should.be_false(error.is_retryable(error.Conflict("conflict")))
}

pub fn error_message_test() {
  should.equal(
    error.message(error.BadRequest("invalid")),
    "Bad request: invalid",
  )
  should.equal(
    error.message(error.ConnectionError("refused")),
    "Connection error: refused",
  )
}

// ---------------------------------------------------------------------------
// Type construction tests
// ---------------------------------------------------------------------------

pub fn default_modality_status_test() {
  let ms = types.default_modality_status()
  should.be_false(ms.graph)
  should.be_false(ms.vector)
  should.be_false(ms.tensor)
  should.be_false(ms.semantic)
  should.be_false(ms.document)
  should.be_false(ms.temporal)
  should.be_false(ms.provenance)
  should.be_false(ms.spatial)
}

pub fn hexad_input_construction_test() {
  let input =
    types.HexadInput(
      graph_data: option.None,
      vector_data: option.None,
      tensor_data: option.None,
      content: option.None,
      spatial_data: option.None,
      metadata: dict.new(),
      modalities: [types.Graph, types.Vector],
    )
  should.equal(input.modalities, [types.Graph, types.Vector])
}

pub fn provenance_event_input_construction_test() {
  let details = dict.from_list([#("key", "value")])
  let input = types.ProvenanceEventInput("annotation", "test-user", details)
  should.equal(input.event_type, "annotation")
  should.equal(input.actor, "test-user")
}
