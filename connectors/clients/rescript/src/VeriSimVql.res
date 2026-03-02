// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — VQL (VeriSimDB Query Language) operations.
//
// VQL is VeriSimDB's native query language for multi-modal queries that span
// graph traversals, vector similarity, spatial filters, and temporal constraints
// in a single statement. This module provides execution and explain functions.

/** VQL request payload for executing or explaining a query. */
type vqlRequest = {
  query: string,
  params: Dict.t<string>,
}

/** Execute a VQL query and return the result set.
 *
 * @param client The authenticated client.
 * @param query The VQL query string.
 * @param params Optional named parameters for parameterised queries.
 * @returns The query result with columns, rows, and timing, or an error.
 */
let execute = async (
  client: VeriSimClient.t,
  query: string,
  ~params: Dict.t<string>=Dict.make(),
): result<VeriSimTypes.vqlResult, VeriSimError.t> => {
  try {
    let req: vqlRequest = {query, params}
    let body = req->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/vql/execute", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("VQL execution failed"))
  }
}

/** Explain a VQL query's execution plan without running it.
 *
 * @param client The authenticated client.
 * @param query The VQL query string.
 * @param params Optional named parameters.
 * @returns The query plan, estimated cost, and any warnings, or an error.
 */
let explain = async (
  client: VeriSimClient.t,
  query: string,
  ~params: Dict.t<string>=Dict.make(),
): result<VeriSimTypes.vqlExplanation, VeriSimError.t> => {
  try {
    let req: vqlRequest = {query, params}
    let body = req->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/vql/explain", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("VQL explain failed"))
  }
}
