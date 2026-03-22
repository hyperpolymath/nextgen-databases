//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Provenance operations.
////
//// Every octad maintains an immutable provenance chain — a cryptographically
//// linked sequence of events recording every mutation applied to it. This
//// module provides functions to query chains, record new events, and verify
//// chain integrity.
////
//// JSON encoding/decoding uses the shared codec module.

import verisimdb_client.{type Client}
import verisimdb_client/codec
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{
  type ProvenanceChain, type ProvenanceEvent, type ProvenanceEventInput,
}

/// Retrieve the complete provenance chain for a octad.
///
/// The chain is returned in chronological order (oldest first) and includes
/// the verification status.
///
/// Parameters:
///   client — The authenticated client.
///   octad_id — The unique identifier of the octad.
///
/// Returns the ProvenanceChain with all events, or an error.
pub fn get_chain(
  client: Client,
  octad_id: String,
) -> Result(ProvenanceChain, VeriSimError) {
  let path = "/api/v1/octads/" <> octad_id <> "/provenance"
  case verisimdb_client.do_get(client, path) {
    Ok(resp) ->
      case resp.status {
        200 -> codec.decode_provenance_chain(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Record a new provenance event on a octad's chain.
///
/// The event is cryptographically linked to the previous event.
/// The server assigns the event ID and timestamp.
///
/// Parameters:
///   client — The authenticated client.
///   octad_id — The unique identifier of the octad.
///   input — The event details to record.
///
/// Returns the newly created ProvenanceEvent, or an error.
pub fn record_event(
  client: Client,
  octad_id: String,
  input: ProvenanceEventInput,
) -> Result(ProvenanceEvent, VeriSimError) {
  let path = "/api/v1/octads/" <> octad_id <> "/provenance"
  let body = codec.encode_provenance_event_input(input)
  case verisimdb_client.do_post(client, path, body) {
    Ok(resp) ->
      case resp.status {
        201 -> codec.decode_provenance_event(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Verify the cryptographic integrity of a octad's provenance chain.
///
/// Returns Ok(True) if the chain is intact, Ok(False) if tampered,
/// or an error on failure.
///
/// Parameters:
///   client — The authenticated client.
///   octad_id — The unique identifier of the octad.
pub fn verify(
  client: Client,
  octad_id: String,
) -> Result(Bool, VeriSimError) {
  let path = "/api/v1/octads/" <> octad_id <> "/provenance/verify"
  case verisimdb_client.do_post(client, path, "{}") {
    Ok(resp) ->
      case resp.status {
        200 -> {
          case codec.decode_provenance_chain(resp.body) {
            Ok(chain) -> Ok(chain.verified)
            Error(err) -> Error(err)
          }
        }
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}
