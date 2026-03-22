//// SPDX-License-Identifier: MPL-2.0
//// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
//// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
////
//// VeriSimDB Gleam Client — Federation operations.
////
//// VeriSimDB supports federated operation where multiple instances form a
//// cluster, sharing and synchronising octad data across peers. This module
//// provides functions to register and manage peers and to execute cross-node
//// queries.
////
//// JSON decoding uses the shared codec module for type-safe deserialization.

import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import verisimdb_client.{type Client}
import verisimdb_client/codec
import verisimdb_client/error.{type VeriSimError}
import verisimdb_client/types.{
  type FederatedQueryResult, type FederationPeer,
}

/// Peer registration input.
pub type PeerRegistration {
  PeerRegistration(
    name: String,
    url: String,
    metadata: Dict(String, String),
  )
}

/// Federated query request.
pub type FederatedQueryRequest {
  FederatedQueryRequest(
    query: String,
    params: Dict(String, String),
    peer_ids: List(String),
    timeout: Int,
  )
}

/// Register a new VeriSimDB instance as a federation peer.
///
/// Parameters:
///   client — The authenticated client.
///   input — The peer registration details.
///
/// Returns the registered FederationPeer with server-assigned ID, or an error.
pub fn register_peer(
  client: Client,
  input: PeerRegistration,
) -> Result(FederationPeer, VeriSimError) {
  let body =
    json.to_string(json.object([
      #("name", json.string(input.name)),
      #("url", json.string(input.url)),
      #("metadata", codec.encode_string_dict(input.metadata)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/federation/peers", body) {
    Ok(resp) ->
      case resp.status {
        201 -> codec.decode_federation_peer(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Retrieve all registered federation peers.
///
/// Parameters:
///   client — The authenticated client.
///
/// Returns a list of FederationPeer records, or an error.
pub fn list_peers(
  client: Client,
) -> Result(List(FederationPeer), VeriSimError) {
  case verisimdb_client.do_get(client, "/api/v1/federation/peers") {
    Ok(resp) ->
      case resp.status {
        200 -> codec.decode_federation_peers(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}

/// Execute a VQL query across one or more federation peers.
///
/// If peer_ids is empty, the query is broadcast to all active peers.
///
/// Parameters:
///   client — The authenticated client.
///   input — The federated query request.
///
/// Returns aggregated results from all queried peers, or an error.
pub fn federated_query(
  client: Client,
  input: FederatedQueryRequest,
) -> Result(FederatedQueryResult, VeriSimError) {
  let param_pairs =
    input.params
    |> dict.to_list
    |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) })
  let body =
    json.to_string(json.object([
      #("query", json.string(input.query)),
      #("params", json.object(param_pairs)),
      #("peer_ids", json.array(input.peer_ids, json.string)),
      #("timeout", json.int(input.timeout)),
    ]))
  case verisimdb_client.do_post(client, "/api/v1/federation/query", body) {
    Ok(resp) ->
      case resp.status {
        200 -> codec.decode_federated_query_result(resp.body)
        status -> Error(error.from_status(status))
      }
    Error(err) -> Error(err)
  }
}
