// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Drift detection operations.
//
// Drift is a core concept in VeriSimDB: it measures how much a hexad's
// embeddings, relationships, or content have diverged from a baseline state.
// This module provides functions to query drift scores, check drift status
// classifications, and trigger re-normalisation of drifted hexads.

module verisimdb_client

import json

// get_drift_score retrieves the current drift score for a specific hexad.
//
// The drift score is a floating-point value between 0.0 (no drift — fully
// aligned with baseline) and 1.0 (maximum drift — completely diverged).
//
// Parameters:
//   c        — The authenticated Client.
//   hexad_id — The unique identifier of the hexad to measure.
//
// Returns:
//   A DriftScore containing the overall score, per-modality component scores,
//   and measurement timestamps, or an error on failure.
pub fn (c Client) get_drift_score(hexad_id string) !DriftScore {
	resp := c.do_get('/api/v1/hexads/${hexad_id}/drift')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(DriftScore, resp.body)
}

// drift_status retrieves a classified drift status report for a hexad.
//
// The status report includes the drift level classification (stable, low,
// moderate, high, critical) along with the underlying score and a
// human-readable message explaining the drift state.
//
// Parameters:
//   c        — The authenticated Client.
//   hexad_id — The unique identifier of the hexad.
//
// Returns:
//   A DriftStatusReport with classification and score, or an error.
pub fn (c Client) drift_status(hexad_id string) !DriftStatusReport {
	resp := c.do_get('/api/v1/hexads/${hexad_id}/drift/status')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(DriftStatusReport, resp.body)
}

// normalize triggers re-normalisation of a drifted hexad.
//
// Normalisation recomputes the hexad's embeddings and relationship weights
// against the current baseline, effectively resetting the drift score.
// This is a potentially expensive operation for hexads with many modalities.
//
// Parameters:
//   c        — The authenticated Client.
//   hexad_id — The unique identifier of the hexad to normalise.
//
// Returns:
//   The updated DriftScore after normalisation, or an error on failure.
pub fn (c Client) normalize(hexad_id string) !DriftScore {
	resp := c.do_post('/api/v1/hexads/${hexad_id}/drift/normalize', '{}')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(DriftScore, resp.body)
}
