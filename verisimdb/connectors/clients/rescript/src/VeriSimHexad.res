// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Hexad CRUD operations.
//
// This module provides create, read, update, delete, and paginated list
// operations for VeriSimDB hexad entities. All functions are async and
// communicate with the VeriSimDB REST API via VeriSimClient's HTTP helpers.

/** Create a new hexad on the VeriSimDB server.
 *
 * @param client The authenticated client configuration.
 * @param input The hexad input describing modalities and data.
 * @returns The newly created hexad with server-assigned ID, or an error.
 */
let create = async (
  client: VeriSimClient.t,
  input: VeriSimTypes.hexadInput,
): result<VeriSimTypes.hexad, VeriSimError.t> => {
  try {
    let body = input->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/hexads", body)
    if resp.status == 201 {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to create hexad"))
  }
}

/** Retrieve a single hexad by its unique identifier.
 *
 * @param client The authenticated client configuration.
 * @param id The hexad's unique identifier.
 * @returns The requested hexad, or an error if not found.
 */
let get = async (
  client: VeriSimClient.t,
  id: string,
): result<VeriSimTypes.hexad, VeriSimError.t> => {
  try {
    let resp = await VeriSimClient.doGet(client, `/api/v1/hexads/${id}`)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to get hexad"))
  }
}

/** Update an existing hexad with the given input fields.
 *
 * Only the fields present in the input are modified; others remain unchanged.
 *
 * @param client The authenticated client configuration.
 * @param id The hexad's unique identifier.
 * @param input The fields to update.
 * @returns The updated hexad, or an error on failure.
 */
let update = async (
  client: VeriSimClient.t,
  id: string,
  input: VeriSimTypes.hexadInput,
): result<VeriSimTypes.hexad, VeriSimError.t> => {
  try {
    let body = input->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPut(client, `/api/v1/hexads/${id}`, body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to update hexad"))
  }
}

/** Delete a hexad by its unique identifier.
 *
 * @param client The authenticated client configuration.
 * @param id The hexad's unique identifier.
 * @returns true if deletion succeeded, or an error on failure.
 */
let delete = async (
  client: VeriSimClient.t,
  id: string,
): result<bool, VeriSimError.t> => {
  try {
    let resp = await VeriSimClient.doDelete(client, `/api/v1/hexads/${id}`)
    if resp.status == 204 || resp.status == 200 {
      Ok(true)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to delete hexad"))
  }
}

/** Retrieve a paginated list of hexads.
 *
 * @param client The authenticated client configuration.
 * @param page The page number (1-indexed).
 * @param perPage The number of hexads per page.
 * @returns A paginated response containing hexads and metadata, or an error.
 */
let list = async (
  client: VeriSimClient.t,
  ~page: int=1,
  ~perPage: int=20,
): result<VeriSimTypes.paginatedResponse, VeriSimError.t> => {
  try {
    let pageStr = Int.toString(page)
    let perPageStr = Int.toString(perPage)
    let resp = await VeriSimClient.doGet(
      client,
      `/api/v1/hexads?page=${pageStr}&per_page=${perPageStr}`,
    )
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to list hexads"))
  }
}
