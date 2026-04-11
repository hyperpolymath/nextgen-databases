// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — VCL (VeriSimDB Query Language) operations.
//
// VCL is VeriSimDB's native query language for multi-modal queries that span
// graph traversals, vector similarity, spatial filters, and temporal constraints
// in a single statement. This module provides execution and explain functions.

/// JSON boundary cast — used at the HTTP response boundary where we trust
/// the VeriSimDB server's JSON schema matches our ReScript types.
/// This replaces Obj.magic with an explicit, auditable cast point.
external fromJson: JSON.t => 'a = "%identity"
external toJson: 'a => JSON.t = "%identity"

/** VCL request payload for executing or explaining a query. */
type vclRequest = {
  query: string,
  params: Dict.t<string>,
}

/** Execute a VCL query and return the result set.
 *
 * @param client The authenticated client.
 * @param query The VCL query string.
 * @param params Optional named parameters for parameterised queries.
 * @returns The query result with columns, rows, and timing, or an error.
 */
let execute = async (
  client: VeriSimClient.t,
  query: string,
  ~params: Dict.t<string>=Dict.make(),
): result<VeriSimTypes.vclResult, VeriSimError.t> => {
  try {
    let req: vclRequest = {query, params}
    let body = switch JSON.stringifyAny(req) {
    | Some(s) => JSON.parseExn(s)
    | None => JSON.parseExn("{}")
    }
    let resp = await VeriSimClient.doPost(client, "/api/v1/vcl/execute", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->fromJson)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("VCL execution failed"))
  }
}

/** Explain a VCL query's execution plan without running it.
 *
 * @param client The authenticated client.
 * @param query The VCL query string.
 * @param params Optional named parameters.
 * @returns The query plan, estimated cost, and any warnings, or an error.
 */
let explain = async (
  client: VeriSimClient.t,
  query: string,
  ~params: Dict.t<string>=Dict.make(),
): result<VeriSimTypes.vclExplanation, VeriSimError.t> => {
  try {
    let req: vclRequest = {query, params}
    let body = switch JSON.stringifyAny(req) {
    | Some(s) => JSON.parseExn(s)
    | None => JSON.parseExn("{}")
    }
    let resp = await VeriSimClient.doPost(client, "/api/v1/vcl/explain", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->fromJson)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("VCL explain failed"))
  }
}
