//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Octad CRUD operations.
////
//// This module provides create, read, update, delete, and paginated list
//// operations for VeriSimDB octad entities. All functions communicate with
//// the VeriSimDB REST API via the main client module's HTTP helpers.
////
//// JSON encoding serializes all 8 modality data fields when present.
//// JSON decoding uses gleam/dynamic/decode for type-safe deserialization.

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import verisimdb_client.{type Client}
import verisimdb_client/codec
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{type Octad, type OctadInput, type PaginatedResponse}

/// Create a new octad on the VeriSimDB server.
///
/// Parameters:
///   client — The authenticated client.
///   input — The octad input describing modalities and data.
///
/// Returns the newly created Octad with server-assigned ID, or an error.
pub fn create(
  client: Client,
  input: OctadInput,
) -> Result(Octad, VeriSimError) {
  let body = codec.encode_octad_input(input)
  case verisimdb_client.do_post(client, "/api/v1/octads", body) {
    Ok(resp) ->
      case resp.status {
        201 -> codec.decode_octad(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Retrieve a single octad by its unique identifier.
///
/// Parameters:
///   client — The authenticated client.
///   id — The octad's unique identifier.
///
/// Returns the requested Octad, or an error if not found.
pub fn get(client: Client, id: String) -> Result(Octad, VeriSimError) {
  case verisimdb_client.do_get(client, "/api/v1/octads/" <> id) {
    Ok(resp) ->
      case resp.status {
        200 -> codec.decode_octad(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Update an existing octad with the given input fields.
/// Only the fields present in the input are modified.
///
/// Parameters:
///   client — The authenticated client.
///   id — The octad's unique identifier.
///   input — The fields to update.
///
/// Returns the updated Octad, or an error.
pub fn update(
  client: Client,
  id: String,
  input: OctadInput,
) -> Result(Octad, VeriSimError) {
  let body = codec.encode_octad_input(input)
  case verisimdb_client.do_put(client, "/api/v1/octads/" <> id, body) {
    Ok(resp) ->
      case resp.status {
        200 -> codec.decode_octad(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Delete a octad by its unique identifier.
///
/// Parameters:
///   client — The authenticated client.
///   id — The octad's unique identifier.
///
/// Returns Ok(True) if deletion succeeded, or an error.
pub fn delete(client: Client, id: String) -> Result(Bool, VeriSimError) {
  case verisimdb_client.do_delete(client, "/api/v1/octads/" <> id) {
    Ok(resp) ->
      case resp.status {
        200 -> Ok(True)
        204 -> Ok(True)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Retrieve a paginated list of octads.
///
/// Parameters:
///   client — The authenticated client.
///   page — Page number (1-indexed).
///   per_page — Number of octads per page.
///
/// Returns a PaginatedResponse, or an error.
pub fn list(
  client: Client,
  page: Int,
  per_page: Int,
) -> Result(PaginatedResponse, VeriSimError) {
  let path =
    "/api/v1/octads?page="
    <> int.to_string(page)
    <> "&per_page="
    <> int.to_string(per_page)
  case verisimdb_client.do_get(client, path) {
    Ok(resp) ->
      case resp.status {
        200 -> codec.decode_paginated_response(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}
