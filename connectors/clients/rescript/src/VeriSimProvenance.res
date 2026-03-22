// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Provenance operations.
//
// Every hexad maintains an immutable provenance chain — a cryptographically
// linked sequence of events recording every mutation applied to it. This module
// provides functions to query chains, record new events, and verify integrity.

/// JSON boundary cast — used at the HTTP response boundary where we trust
/// the VeriSimDB server's JSON schema matches our ReScript types.
/// This replaces Obj.magic with an explicit, auditable cast point.
external fromJson: JSON.t => 'a = "%identity"
external toJson: 'a => JSON.t = "%identity"

/** Retrieve the complete provenance chain for a hexad.
 *
 * The chain is returned in chronological order (oldest first) and includes
 * the verification status.
 *
 * @param client The authenticated client.
 * @param hexadId The unique identifier of the hexad.
 * @returns The provenance chain with all events, or an error.
 */
let getChain = async (
  client: VeriSimClient.t,
  hexadId: string,
): result<VeriSimTypes.provenanceChain, VeriSimError.t> => {
  try {
    let resp = await VeriSimClient.doGet(client, `/api/v1/hexads/${hexadId}/provenance`)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->fromJson)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to get provenance chain"))
  }
}

/** Record a new provenance event on a hexad's chain.
 *
 * The event is cryptographically linked to the previous event in the chain.
 * The server assigns the event ID and timestamp.
 *
 * @param client The authenticated client.
 * @param hexadId The unique identifier of the hexad.
 * @param input The event details to record.
 * @returns The newly created provenance event, or an error.
 */
let recordEvent = async (
  client: VeriSimClient.t,
  hexadId: string,
  input: VeriSimTypes.provenanceEventInput,
): result<VeriSimTypes.provenanceEvent, VeriSimError.t> => {
  try {
    let body = switch JSON.stringifyAny(input) {
    | Some(s) => JSON.parseExn(s)
    | None => JSON.parseExn("{}")
    }
    let resp = await VeriSimClient.doPost(client, `/api/v1/hexads/${hexadId}/provenance`, body)
    if resp.status == 201 {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->fromJson)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to record provenance event"))
  }
}

/** Verify the cryptographic integrity of a hexad's provenance chain.
 *
 * The server traverses the entire chain, checking each event's hash link.
 * Returns true if the chain is intact, false if tampering is detected.
 *
 * @param client The authenticated client.
 * @param hexadId The unique identifier of the hexad.
 * @returns true if the chain is verified intact, or an error.
 */
let verify = async (
  client: VeriSimClient.t,
  hexadId: string,
): result<bool, VeriSimError.t> => {
  try {
    let emptyBody = JSON.parseExn("{}")
    let resp = await VeriSimClient.doPost(
      client,
      `/api/v1/hexads/${hexadId}/provenance/verify`,
      emptyBody,
    )
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      let chain: VeriSimTypes.provenanceChain = json->fromJson
      Ok(chain.verified)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to verify provenance"))
  }
}
