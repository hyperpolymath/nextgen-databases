//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Drift detection operations.
////
//// Drift measures how much a hexad's embeddings, relationships, or content
//// have diverged from a baseline state (0.0 = no drift, 1.0 = maximum drift).
//// This module provides functions to query drift scores, check classified
//// status, and trigger re-normalisation.

import verisimdb_client.{type Client}
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{type DriftScore, type DriftStatusReport}

/// Retrieve the current drift score for a specific hexad.
///
/// The drift score is a floating-point value between 0.0 (no drift — fully
/// aligned with baseline) and 1.0 (maximum drift — completely diverged).
///
/// Parameters:
///   client — The authenticated client.
///   hexad_id — The unique identifier of the hexad.
///
/// Returns a DriftScore with component breakdown, or an error.
pub fn get_score(
  client: Client,
  hexad_id: String,
) -> Result(DriftScore, VeriSimError) {
  let path = "/api/v1/hexads/" <> hexad_id <> "/drift"
  case verisimdb_client.do_get(client, path) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_drift_score(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Retrieve a classified drift status report for a hexad.
///
/// The report includes the drift level (Stable, Low, Moderate, High, Critical),
/// the underlying score, and a human-readable explanation.
///
/// Parameters:
///   client — The authenticated client.
///   hexad_id — The unique identifier of the hexad.
///
/// Returns a DriftStatusReport, or an error.
pub fn status(
  client: Client,
  hexad_id: String,
) -> Result(DriftStatusReport, VeriSimError) {
  let path = "/api/v1/hexads/" <> hexad_id <> "/drift/status"
  case verisimdb_client.do_get(client, path) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_drift_status_report(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Trigger re-normalisation of a drifted hexad.
///
/// Normalisation recomputes the hexad's embeddings and relationship weights
/// against the current baseline, effectively resetting the drift score.
///
/// Parameters:
///   client — The authenticated client.
///   hexad_id — The unique identifier of the hexad.
///
/// Returns the updated DriftScore after normalisation, or an error.
pub fn normalize(
  client: Client,
  hexad_id: String,
) -> Result(DriftScore, VeriSimError) {
  let path = "/api/v1/hexads/" <> hexad_id <> "/drift/normalize"
  case verisimdb_client.do_post(client, path, "{}") {
    Ok(resp) ->
      case resp.status {
        200 -> decode_drift_score(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

// ---------------------------------------------------------------------------
// Internal JSON decoding helpers (stubs)
// ---------------------------------------------------------------------------

/// Decode a DriftScore from a JSON response body.
/// TODO: Implement full JSON decoding with gleam_json decoders.
fn decode_drift_score(body: String) -> Result(DriftScore, VeriSimError) {
  Error(error.SerializationError(
    "DriftScore JSON decoding not yet implemented (scaffold)",
  ))
}

/// Decode a DriftStatusReport from a JSON response body.
/// TODO: Implement full JSON decoding with gleam_json decoders.
fn decode_drift_status_report(
  body: String,
) -> Result(DriftStatusReport, VeriSimError) {
  Error(error.SerializationError(
    "DriftStatusReport JSON decoding not yet implemented (scaffold)",
  ))
}
