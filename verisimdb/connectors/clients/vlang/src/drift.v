// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Drift detection operations.
//
// Drift is a core concept in VeriSimDB: it measures how much a octad's
// embeddings, relationships, or content have diverged from a baseline state.
// This module provides functions to query drift scores, check drift status
// classifications, and trigger re-normalisation of drifted octads.

module verisimdb_client

import json

// get_drift_score retrieves the current drift score for a specific octad.
//
// The drift score is a floating-point value between 0.0 (no drift — fully
// aligned with baseline) and 1.0 (maximum drift — completely diverged).
//
// Parameters:
//   c        — The authenticated Client.
//   octad_id — The unique identifier of the octad to measure.
//
// Returns:
//   A DriftScore containing the overall score, per-modality component scores,
//   and measurement timestamps, or an error on failure.
pub fn (c Client) get_drift_score(octad_id string) !DriftScore {
	resp := c.do_get('/api/v1/octads/${octad_id}/drift')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(DriftScore, resp.body)
}

// drift_status retrieves a classified drift status report for a octad.
//
// The status report includes the drift level classification (stable, low,
// moderate, high, critical) along with the underlying score and a
// human-readable message explaining the drift state.
//
// Parameters:
//   c        — The authenticated Client.
//   octad_id — The unique identifier of the octad.
//
// Returns:
//   A DriftStatusReport with classification and score, or an error.
pub fn (c Client) drift_status(octad_id string) !DriftStatusReport {
	resp := c.do_get('/api/v1/octads/${octad_id}/drift/status')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(DriftStatusReport, resp.body)
}

// normalize triggers re-normalisation of a drifted octad.
//
// Normalisation recomputes the octad's embeddings and relationship weights
// against the current baseline, effectively resetting the drift score.
// This is a potentially expensive operation for octads with many modalities.
//
// Parameters:
//   c        — The authenticated Client.
//   octad_id — The unique identifier of the octad to normalise.
//
// Returns:
//   The updated DriftScore after normalisation, or an error on failure.
pub fn (c Client) normalize(octad_id string) !DriftScore {
	resp := c.do_post('/api/v1/octads/${octad_id}/drift/normalize', '{}')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(DriftScore, resp.body)
}
