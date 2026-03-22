// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// client_test.gleam — Tests for the HTTP client module.
//
// Tests error formatting and error type construction. HTTP request/response
// tests require a running database server and are covered by the conformance
// suite in verification/conformance/.

import gleam/string
import gleeunit/should
import nqc/client
import nqc/database

// ---------------------------------------------------------------------------
// error_to_string — human-readable error formatting
// ---------------------------------------------------------------------------

pub fn error_to_string_request_error_test() {
  let err = client.RequestError("Invalid URL: foo")
  let msg = client.error_to_string(err)
  should.be_true(string.contains(msg, "Request error"))
  should.be_true(string.contains(msg, "Invalid URL: foo"))
}

pub fn error_to_string_transport_error_test() {
  let err = client.TransportError("Failed to connect to http://localhost:9999")
  let msg = client.error_to_string(err)
  should.be_true(string.contains(msg, "Connection error"))
  should.be_true(string.contains(msg, "localhost:9999"))
}

pub fn error_to_string_server_error_test() {
  let err = client.ServerError(status: 500, body: "Internal Server Error")
  let msg = client.error_to_string(err)
  should.be_true(string.contains(msg, "Server error"))
  should.be_true(string.contains(msg, "500"))
  should.be_true(string.contains(msg, "Internal Server Error"))
}

pub fn error_to_string_server_error_404_test() {
  let err = client.ServerError(status: 404, body: "Not Found")
  let msg = client.error_to_string(err)
  should.be_true(string.contains(msg, "404"))
}

pub fn error_to_string_parse_error_test() {
  let err = client.ParseError("Failed to parse JSON: Unexpected end of input")
  let msg = client.error_to_string(err)
  should.be_true(string.contains(msg, "Parse error"))
  should.be_true(string.contains(msg, "Unexpected end of input"))
}

// ---------------------------------------------------------------------------
// execute against unreachable server — verifies error path
// ---------------------------------------------------------------------------

pub fn execute_unreachable_server_returns_error_test() {
  // Connect to a port where nothing is listening.
  let profile = database.vql_profile()
  let conn =
    database.Connection(
      profile: profile,
      host: "localhost",
      port: 19999,
      dt_enabled: False,
    )
  let result = client.execute(conn, "SELECT 1")
  should.be_error(result)
}

pub fn health_unreachable_server_returns_error_test() {
  let profile = database.vql_profile()
  let conn =
    database.Connection(
      profile: profile,
      host: "localhost",
      port: 19999,
      dt_enabled: False,
    )
  let result = client.health(conn)
  should.be_error(result)
}
