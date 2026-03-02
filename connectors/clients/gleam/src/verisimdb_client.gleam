//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Main module.
////
//// This module provides the core Client type and constructor functions for
//// connecting to a VeriSimDB server. It supports multiple authentication
//// methods (API key, Basic, Bearer token, or none) and manages base URL
//// routing, request timeouts, and standard HTTP verb helpers.
////
//// Usage:
////   let client = verisimdb_client.new("http://localhost:8080")
////   let assert Ok(True) = verisimdb_client.health(client)

import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/hackney
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/bit_array
import verisimdb_client/error.{type VeriSimError}

// ---------------------------------------------------------------------------
// Authentication types
// ---------------------------------------------------------------------------

/// Authentication method for connecting to VeriSimDB.
pub type Auth {
  /// API key authentication via X-API-Key header.
  ApiKey(key: String)
  /// HTTP Basic Authentication (username:password).
  Basic(username: String, password: String)
  /// Bearer token authentication via Authorization header.
  Bearer(token: String)
  /// No authentication required.
  NoAuth
}

// ---------------------------------------------------------------------------
// Client type
// ---------------------------------------------------------------------------

/// Client holds the connection configuration for a VeriSimDB server.
///
/// Fields:
///   base_url — Root URL of the VeriSimDB API (e.g. "http://localhost:8080").
///   timeout — Request timeout in milliseconds. Defaults to 30000 (30 seconds).
///   auth — Authentication method. Defaults to NoAuth.
pub type Client {
  Client(base_url: String, timeout: Int, auth: Auth)
}

/// Create a new unauthenticated client with the given base URL.
pub fn new(base_url: String) -> Client {
  Client(
    base_url: string.trim_end(base_url, "/"),
    timeout: 30_000,
    auth: NoAuth,
  )
}

/// Create a client with a specific authentication method.
pub fn new_with_auth(base_url: String, auth: Auth) -> Client {
  Client(
    base_url: string.trim_end(base_url, "/"),
    timeout: 30_000,
    auth: auth,
  )
}

/// Create a client authenticated with an API key.
pub fn new_with_api_key(base_url: String, key: String) -> Client {
  new_with_auth(base_url, ApiKey(key))
}

/// Create a client authenticated with a Bearer token.
pub fn new_with_bearer(base_url: String, token: String) -> Client {
  new_with_auth(base_url, Bearer(token))
}

// ---------------------------------------------------------------------------
// Internal HTTP helpers
// ---------------------------------------------------------------------------

/// Build an HTTP request with authentication headers applied.
fn build_request(
  client: Client,
  method: http.Method,
  path: String,
) -> Result(request.Request(String), VeriSimError) {
  let url = client.base_url <> path
  case request.to(url) {
    Ok(req) -> {
      let req = request.set_method(req, method)
      let req = apply_auth(req, client.auth)
      Ok(req)
    }
    Error(_) -> Error(error.ConnectionError("Invalid URL: " <> url))
  }
}

/// Apply authentication headers to a request.
fn apply_auth(
  req: request.Request(String),
  auth: Auth,
) -> request.Request(String) {
  case auth {
    ApiKey(key) -> request.set_header(req, "x-api-key", key)
    Basic(username, password) -> {
      let credentials = username <> ":" <> password
      let encoded =
        credentials
        |> bit_array.from_string
        |> bit_array.base64_encode(True)
      request.set_header(req, "authorization", "Basic " <> encoded)
    }
    Bearer(token) ->
      request.set_header(req, "authorization", "Bearer " <> token)
    NoAuth -> req
  }
}

/// Send a GET request to the given API path.
pub fn do_get(
  client: Client,
  path: String,
) -> Result(response.Response(String), VeriSimError) {
  case build_request(client, http.Get, path) {
    Ok(req) ->
      case hackney.send(req) {
        Ok(resp) -> Ok(resp)
        Error(_) ->
          Error(error.ConnectionError(
            "Failed to connect to VeriSimDB server",
          ))
      }
    Error(err) -> Error(err)
  }
}

/// Send a POST request with a JSON body.
pub fn do_post(
  client: Client,
  path: String,
  body: String,
) -> Result(response.Response(String), VeriSimError) {
  case build_request(client, http.Post, path) {
    Ok(req) -> {
      let req =
        req
        |> request.set_header("content-type", "application/json")
        |> request.set_body(body)
      case hackney.send(req) {
        Ok(resp) -> Ok(resp)
        Error(_) ->
          Error(error.ConnectionError(
            "Failed to connect to VeriSimDB server",
          ))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Send a PUT request with a JSON body.
pub fn do_put(
  client: Client,
  path: String,
  body: String,
) -> Result(response.Response(String), VeriSimError) {
  case build_request(client, http.Put, path) {
    Ok(req) -> {
      let req =
        req
        |> request.set_header("content-type", "application/json")
        |> request.set_body(body)
      case hackney.send(req) {
        Ok(resp) -> Ok(resp)
        Error(_) ->
          Error(error.ConnectionError(
            "Failed to connect to VeriSimDB server",
          ))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Send a DELETE request to the given API path.
pub fn do_delete(
  client: Client,
  path: String,
) -> Result(response.Response(String), VeriSimError) {
  case build_request(client, http.Delete, path) {
    Ok(req) ->
      case hackney.send(req) {
        Ok(resp) -> Ok(resp)
        Error(_) ->
          Error(error.ConnectionError(
            "Failed to connect to VeriSimDB server",
          ))
      }
    Error(err) -> Error(err)
  }
}

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

/// Check whether the VeriSimDB server is reachable and healthy.
///
/// Sends a GET request to /health and expects a 200 OK response.
/// Returns Ok(True) if healthy, or an error on failure.
pub fn health(client: Client) -> Result(Bool, VeriSimError) {
  case do_get(client, "/health") {
    Ok(resp) ->
      case resp.status {
        200 -> Ok(True)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}
