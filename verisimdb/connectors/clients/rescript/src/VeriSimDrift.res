// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Drift detection operations.
//
// Drift measures how much a hexad's embeddings, relationships, or content
// have diverged from a baseline state. This module provides functions to
// query drift scores, check drift status classifications, and trigger
// re-normalisation of drifted hexads.

/** Retrieve the current drift score for a specific hexad.
 *
 * The drift score is a floating-point value between 0.0 (no drift) and
 * 1.0 (maximum drift).
 *
 * @param client The authenticated client.
 * @param hexadId The unique identifier of the hexad.
 * @returns The drift score with component breakdown, or an error.
 */
let getScore = async (
  client: VeriSimClient.t,
  hexadId: string,
): result<VeriSimTypes.driftScore, VeriSimError.t> => {
  try {
    let resp = await VeriSimClient.doGet(client, `/api/v1/hexads/${hexadId}/drift`)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to get drift score"))
  }
}

/** Retrieve a classified drift status report for a hexad.
 *
 * The report includes the drift level (Stable, Low, Moderate, High, Critical),
 * the underlying score, and a human-readable explanation.
 *
 * @param client The authenticated client.
 * @param hexadId The unique identifier of the hexad.
 * @returns The drift status report, or an error.
 */
let status = async (
  client: VeriSimClient.t,
  hexadId: string,
): result<VeriSimTypes.driftStatusReport, VeriSimError.t> => {
  try {
    let resp = await VeriSimClient.doGet(client, `/api/v1/hexads/${hexadId}/drift/status`)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to get drift status"))
  }
}

/** Trigger re-normalisation of a drifted hexad.
 *
 * Normalisation recomputes the hexad's embeddings and relationship weights
 * against the current baseline, effectively resetting the drift score.
 *
 * @param client The authenticated client.
 * @param hexadId The unique identifier of the hexad.
 * @returns The updated drift score after normalisation, or an error.
 */
let normalize = async (
  client: VeriSimClient.t,
  hexadId: string,
): result<VeriSimTypes.driftScore, VeriSimError.t> => {
  try {
    let emptyBody = JSON.parseExn("{}")
    let resp = await VeriSimClient.doPost(
      client,
      `/api/v1/hexads/${hexadId}/drift/normalize`,
      emptyBody,
    )
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to normalize drift"))
  }
}
