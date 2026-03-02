//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Provenance operations.
////
//// Every hexad maintains an immutable provenance chain — a cryptographically
//// linked sequence of events recording every mutation applied to it. This
//// module provides functions to query chains, record new events, and verify
//// chain integrity.

import gleam/dict
import gleam/json
import verisimdb_client.{type Client}
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{
  type ProvenanceChain, type ProvenanceEvent, type ProvenanceEventInput,
}

/// Retrieve the complete provenance chain for a hexad.
///
/// The chain is returned in chronological order (oldest first) and includes
/// the verification status.
///
/// Parameters:
///   client — The authenticated client.
///   hexad_id — The unique identifier of the hexad.
///
/// Returns the ProvenanceChain with all events, or an error.
pub fn get_chain(
  client: Client,
  hexad_id: String,
) -> Result(ProvenanceChain, VeriSimError) {
  let path = "/api/v1/hexads/" <> hexad_id <> "/provenance"
  case verisimdb_client.do_get(client, path) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_provenance_chain(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Record a new provenance event on a hexad's chain.
///
/// The event is cryptographically linked to the previous event.
/// The server assigns the event ID and timestamp.
///
/// Parameters:
///   client — The authenticated client.
///   hexad_id — The unique identifier of the hexad.
///   input — The event details to record.
///
/// Returns the newly created ProvenanceEvent, or an error.
pub fn record_event(
  client: Client,
  hexad_id: String,
  input: ProvenanceEventInput,
) -> Result(ProvenanceEvent, VeriSimError) {
  let path = "/api/v1/hexads/" <> hexad_id <> "/provenance"
  let detail_pairs =
    input.details
    |> dict.to_list
    |> encode_string_pairs
  let body =
    json.to_string(json.object([
      #("event_type", json.string(input.event_type)),
      #("actor", json.string(input.actor)),
      #("details", json.object(detail_pairs)),
    ]))
  case verisimdb_client.do_post(client, path, body) {
    Ok(resp) ->
      case resp.status {
        201 -> decode_provenance_event(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Verify the cryptographic integrity of a hexad's provenance chain.
///
/// Returns Ok(True) if the chain is intact, Ok(False) if tampered,
/// or an error on failure.
///
/// Parameters:
///   client — The authenticated client.
///   hexad_id — The unique identifier of the hexad.
pub fn verify(
  client: Client,
  hexad_id: String,
) -> Result(Bool, VeriSimError) {
  let path = "/api/v1/hexads/" <> hexad_id <> "/provenance/verify"
  case verisimdb_client.do_post(client, path, "{}") {
    Ok(resp) ->
      case resp.status {
        200 -> {
          // TODO: Parse the chain and return chain.verified
          // Scaffold returns placeholder
          Error(error.SerializationError(
            "Provenance verify decoding not yet implemented (scaffold)",
          ))
        }
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Encode a list of string key-value pairs as JSON object fields.
fn encode_string_pairs(
  pairs: List(#(String, String)),
) -> List(#(String, json.Json)) {
  case pairs {
    [] -> []
    [#(k, v), ..rest] -> [
      #(k, json.string(v)),
      ..encode_string_pairs(rest)
    ]
  }
}

/// Decode a ProvenanceChain from a JSON response body.
/// TODO: Implement full JSON decoding.
fn decode_provenance_chain(
  body: String,
) -> Result(ProvenanceChain, VeriSimError) {
  Error(error.SerializationError(
    "ProvenanceChain JSON decoding not yet implemented (scaffold)",
  ))
}

/// Decode a ProvenanceEvent from a JSON response body.
/// TODO: Implement full JSON decoding.
fn decode_provenance_event(
  body: String,
) -> Result(ProvenanceEvent, VeriSimError) {
  Error(error.SerializationError(
    "ProvenanceEvent JSON decoding not yet implemented (scaffold)",
  ))
}
