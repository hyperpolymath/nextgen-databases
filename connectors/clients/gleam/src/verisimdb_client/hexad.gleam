//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Hexad CRUD operations.
////
//// This module provides create, read, update, delete, and paginated list
//// operations for VeriSimDB hexad entities. All functions communicate with
//// the VeriSimDB REST API via the main client module's HTTP helpers.

import gleam/int
import gleam/json
import gleam/result
import verisimdb_client.{type Client}
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{type Hexad, type HexadInput, type PaginatedResponse}

/// Create a new hexad on the VeriSimDB server.
///
/// Parameters:
///   client — The authenticated client.
///   input — The hexad input describing modalities and data.
///
/// Returns the newly created Hexad with server-assigned ID, or an error.
pub fn create(
  client: Client,
  input: HexadInput,
) -> Result(Hexad, VeriSimError) {
  let body = encode_hexad_input(input)
  case verisimdb_client.do_post(client, "/api/v1/hexads", body) {
    Ok(resp) ->
      case resp.status {
        201 -> decode_hexad(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Retrieve a single hexad by its unique identifier.
///
/// Parameters:
///   client — The authenticated client.
///   id — The hexad's unique identifier.
///
/// Returns the requested Hexad, or an error if not found.
pub fn get(client: Client, id: String) -> Result(Hexad, VeriSimError) {
  case verisimdb_client.do_get(client, "/api/v1/hexads/" <> id) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_hexad(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Update an existing hexad with the given input fields.
/// Only the fields present in the input are modified.
///
/// Parameters:
///   client — The authenticated client.
///   id — The hexad's unique identifier.
///   input — The fields to update.
///
/// Returns the updated Hexad, or an error.
pub fn update(
  client: Client,
  id: String,
  input: HexadInput,
) -> Result(Hexad, VeriSimError) {
  let body = encode_hexad_input(input)
  case verisimdb_client.do_put(client, "/api/v1/hexads/" <> id, body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_hexad(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Delete a hexad by its unique identifier.
///
/// Parameters:
///   client — The authenticated client.
///   id — The hexad's unique identifier.
///
/// Returns Ok(True) if deletion succeeded, or an error.
pub fn delete(client: Client, id: String) -> Result(Bool, VeriSimError) {
  case verisimdb_client.do_delete(client, "/api/v1/hexads/" <> id) {
    Ok(resp) ->
      case resp.status {
        200 -> Ok(True)
        204 -> Ok(True)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Retrieve a paginated list of hexads.
///
/// Parameters:
///   client — The authenticated client.
///   page — Page number (1-indexed).
///   per_page — Number of hexads per page.
///
/// Returns a PaginatedResponse, or an error.
pub fn list(
  client: Client,
  page: Int,
  per_page: Int,
) -> Result(PaginatedResponse, VeriSimError) {
  let path =
    "/api/v1/hexads?page="
    <> int.to_string(page)
    <> "&per_page="
    <> int.to_string(per_page)
  case verisimdb_client.do_get(client, path) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_paginated_response(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

// ---------------------------------------------------------------------------
// Internal JSON encoding/decoding helpers (stubs for scaffold)
// ---------------------------------------------------------------------------

/// Encode a HexadInput to a JSON string.
/// TODO: Implement full JSON encoding with gleam_json.
fn encode_hexad_input(input: HexadInput) -> String {
  // Scaffold: produces a minimal JSON representation.
  // Full implementation would encode all modality data fields.
  let modality_strings =
    input.modalities
    |> list_map_to_json_strings(types.modality_to_string)
  json.to_string(json.object([
    #("modalities", json.array(modality_strings, json.string)),
  ]))
}

/// Decode a Hexad from a JSON response body.
/// TODO: Implement full JSON decoding with gleam_json.
fn decode_hexad(body: String) -> Result(Hexad, VeriSimError) {
  // Scaffold: returns a placeholder error indicating decoding is not yet implemented.
  Error(error.SerializationError(
    "Hexad JSON decoding not yet implemented (scaffold)",
  ))
}

/// Decode a PaginatedResponse from a JSON response body.
/// TODO: Implement full JSON decoding with gleam_json.
fn decode_paginated_response(
  body: String,
) -> Result(PaginatedResponse, VeriSimError) {
  Error(error.SerializationError(
    "PaginatedResponse JSON decoding not yet implemented (scaffold)",
  ))
}

/// Map a list of items through a function, collecting results as strings.
fn list_map_to_json_strings(
  items: List(a),
  f: fn(a) -> String,
) -> List(String) {
  case items {
    [] -> []
    [first, ..rest] -> [f(first), ..list_map_to_json_strings(rest, f)]
  }
}
