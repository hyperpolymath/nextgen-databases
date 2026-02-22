// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// client.gleam — HTTP client for NextGen database APIs.
//
// Sends VQL/GQL/KQL queries to the appropriate database server and returns
// parsed JSON responses. All three databases use the same protocol pattern:
// POST a JSON body with {"query": "<text>"} and receive JSON results.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/result
import nqc/database.{type Connection}

/// Error type for client operations.
pub type ClientError {
  /// Failed to build HTTP request.
  RequestError(String)
  /// HTTP transport error (connection refused, timeout, etc.).
  TransportError(String)
  /// Server returned non-2xx status.
  ServerError(status: Int, body: String)
  /// Failed to parse response body as JSON.
  ParseError(String)
}

/// Format a client error as a human-readable string.
pub fn error_to_string(err: ClientError) -> String {
  case err {
    RequestError(msg) -> "Request error: " <> msg
    TransportError(msg) -> "Connection error: " <> msg
    ServerError(status:, body:) ->
      "Server error (HTTP " <> int.to_string(status) <> "): " <> body
    ParseError(msg) -> "Parse error: " <> msg
  }
}

/// Execute a query against the connected database.
///
/// Sends POST {execute_path} with body {"query": "<query_text>"}
/// and returns the raw JSON response as a dynamic value.
pub fn execute(
  conn: Connection,
  query: String,
) -> Result(Dynamic, ClientError) {
  let url = database.execute_url(conn)
  let body = json.object([#("query", json.string(query))])
  post_json(url, json.to_string(body))
}

/// Check server health.
///
/// Sends GET {health_path} and returns the health JSON response.
pub fn health(conn: Connection) -> Result(Dynamic, ClientError) {
  let url = database.health_url(conn)
  get_json(url)
}

/// Send a POST request with a JSON body and return parsed JSON.
fn post_json(
  url: String,
  body: String,
) -> Result(Dynamic, ClientError) {
  case request.to(url) {
    Ok(req) -> {
      let req =
        req
        |> request.set_method(http.Post)
        |> request.set_header("content-type", "application/json")
        |> request.set_header("accept", "application/json")
        |> request.set_body(body)
      send_and_parse(req, url)
    }
    Error(_) -> Error(RequestError("Invalid URL: " <> url))
  }
}

/// Send a GET request and return parsed JSON.
fn get_json(url: String) -> Result(Dynamic, ClientError) {
  case request.to(url) {
    Ok(req) -> {
      let req =
        req
        |> request.set_method(http.Get)
        |> request.set_header("accept", "application/json")
      send_and_parse(req, url)
    }
    Error(_) -> Error(RequestError("Invalid URL: " <> url))
  }
}

/// Send an HTTP request and parse the JSON response body.
fn send_and_parse(
  req: request.Request(String),
  url: String,
) -> Result(Dynamic, ClientError) {
  case httpc.send(req) {
    Ok(response) -> {
      case response.status {
        status if status >= 200 && status < 300 ->
          json.parse(response.body, decode.dynamic)
          |> result.map_error(fn(e) {
            ParseError(
              "Failed to parse JSON: " <> string_from_decode_error(e),
            )
          })
        status ->
          Error(ServerError(status: status, body: response.body))
      }
    }
    Error(_) -> Error(TransportError("Failed to connect to " <> url))
  }
}

/// Convert a JSON decode error to a string.
fn string_from_decode_error(err: json.DecodeError) -> String {
  case err {
    json.UnexpectedEndOfInput -> "Unexpected end of input"
    json.UnexpectedByte(byte) -> "Unexpected byte: " <> byte
    json.UnexpectedSequence(seq) -> "Unexpected sequence: " <> seq
    json.UnableToDecode(_) -> "Unable to decode response"
  }
}
