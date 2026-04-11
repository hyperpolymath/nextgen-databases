// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Federation operations.
//
// VeriSimDB supports federated operation where multiple instances form a cluster,
// sharing and synchronising hexad data across peers. This module provides functions
// to register and manage peers and to execute cross-node queries.

/// JSON boundary cast — used at the HTTP response boundary where we trust
/// the VeriSimDB server's JSON schema matches our ReScript types.
/// This replaces Obj.magic with an explicit, auditable cast point.
external fromJson: JSON.t => 'a = "%identity"
external toJson: 'a => JSON.t = "%identity"

/** Peer registration input. */
type peerRegistration = {
  name: string,
  url: string,
  metadata: Dict.t<string>,
}

/** Federated query request. */
type federatedQueryRequest = {
  query: string,
  params: Dict.t<string>,
  peerIds: array<string>,
  timeout: int,
}

/** Register a new VeriSimDB instance as a federation peer.
 *
 * @param client The authenticated client.
 * @param input The peer registration details.
 * @returns The registered peer with server-assigned ID, or an error.
 */
let registerPeer = async (
  client: VeriSimClient.t,
  input: peerRegistration,
): result<VeriSimTypes.federationPeer, VeriSimError.t> => {
  try {
    let body = switch JSON.stringifyAny(input) {
    | Some(s) => JSON.parseExn(s)
    | None => JSON.parseExn("{}")
    }
    let resp = await VeriSimClient.doPost(client, "/api/v1/federation/peers", body)
    if resp.status == 201 {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->fromJson)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to register peer"))
  }
}

/** Retrieve all registered federation peers.
 *
 * @param client The authenticated client.
 * @returns A list of federation peers, or an error.
 */
let listPeers = async (
  client: VeriSimClient.t,
): result<array<VeriSimTypes.federationPeer>, VeriSimError.t> => {
  try {
    let resp = await VeriSimClient.doGet(client, "/api/v1/federation/peers")
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->fromJson)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to list peers"))
  }
}

/** Execute a VCL query across one or more federation peers.
 *
 * If peerIds is empty, the query is broadcast to all active peers.
 *
 * @param client The authenticated client.
 * @param input The federated query request.
 * @returns Aggregated results from all queried peers, or an error.
 */
let federatedQuery = async (
  client: VeriSimClient.t,
  input: federatedQueryRequest,
): result<VeriSimTypes.federatedQueryResult, VeriSimError.t> => {
  try {
    let body = switch JSON.stringifyAny(input) {
    | Some(s) => JSON.parseExn(s)
    | None => JSON.parseExn("{}")
    }
    let resp = await VeriSimClient.doPost(client, "/api/v1/federation/query", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->fromJson)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Federated query failed"))
  }
}
