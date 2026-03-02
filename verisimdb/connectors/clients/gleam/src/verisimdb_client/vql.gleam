//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — VQL (VeriSimDB Query Language) operations.
////
//// VQL is VeriSimDB's native query language for multi-modal queries that span
//// graph traversals, vector similarity, spatial filters, and temporal constraints
//// in a single statement. This module provides execution and explain functions.

import gleam/dict.{type Dict}
import gleam/json
import verisimdb_client.{type Client}
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{type VqlExplanation, type VqlResult}

/// Execute a VQL query and return the result set.
///
/// VQL queries can combine modalities — for example:
///   FIND hexads WHERE vector_similar($embedding, 0.8)
///     AND spatial_within(51.5, -0.1, 10km)
///     AND graph_connected("category:science", depth: 2)
///
/// Parameters:
///   client — The authenticated client.
///   query — The VQL query string.
///   params — Named parameters for parameterised queries.
///
/// Returns a VqlResult with columns, rows, and timing, or an error.
pub fn execute(
  client: Client,
  query: String,
  params: Dict(String, String),
) -> Result(VqlResult, VeriSimError) {
  let param_pairs =
    params
    |> dict.to_list
    |> encode_string_pairs
  let body =
    json.to_string(json.object([
      #("query", json.string(query)),
      #("params", json.object(param_pairs)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/vql/execute", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_vql_result(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Explain a VQL query's execution plan without running it.
///
/// Parameters:
///   client — The authenticated client.
///   query — The VQL query string.
///   params — Named parameters.
///
/// Returns a VqlExplanation with the plan, cost, and warnings, or an error.
pub fn explain(
  client: Client,
  query: String,
  params: Dict(String, String),
) -> Result(VqlExplanation, VeriSimError) {
  let param_pairs =
    params
    |> dict.to_list
    |> encode_string_pairs
  let body =
    json.to_string(json.object([
      #("query", json.string(query)),
      #("params", json.object(param_pairs)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/vql/explain", body) {
    Ok(resp) ->
      case resp.status {
        200 -> decode_vql_explanation(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Encode string key-value pairs as JSON object fields.
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

/// Decode a VqlResult from a JSON response body.
/// TODO: Implement full JSON decoding with gleam_json decoders.
fn decode_vql_result(body: String) -> Result(VqlResult, VeriSimError) {
  Error(error.SerializationError(
    "VqlResult JSON decoding not yet implemented (scaffold)",
  ))
}

/// Decode a VqlExplanation from a JSON response body.
/// TODO: Implement full JSON decoding with gleam_json decoders.
fn decode_vql_explanation(
  body: String,
) -> Result(VqlExplanation, VeriSimError) {
  Error(error.SerializationError(
    "VqlExplanation JSON decoding not yet implemented (scaffold)",
  ))
}
