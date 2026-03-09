# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Drift detection operations.
#
# Drift measures how much a octad's embeddings, relationships, or content
# have diverged from a baseline state (0.0 = no drift, 1.0 = maximum drift).
# This file provides functions to query drift scores, check classified status,
# and trigger re-normalisation.

"""
    get_drift_score(client::Client, octad_id::String) -> DriftScore

Retrieve the current drift score for a specific octad.

The drift score is a floating-point value between 0.0 (no drift — fully
aligned with baseline) and 1.0 (maximum drift — completely diverged).

# Arguments
- `client::Client` — The authenticated client.
- `octad_id::String` — The unique identifier of the octad.

# Returns
A `DriftScore` with overall score, per-modality components, and timestamps.
"""
function get_drift_score(client::Client, octad_id::String)::DriftScore
    resp = do_get(client, "/api/v1/octads/$octad_id/drift")
    return parse_response(DriftScore, resp)
end

"""
    drift_status(client::Client, octad_id::String) -> DriftStatusReport

Retrieve a classified drift status report for a octad.

The report includes the drift level (Stable, Low, Moderate, High, Critical),
the underlying score, and a human-readable message.

# Arguments
- `client::Client` — The authenticated client.
- `octad_id::String` — The unique identifier of the octad.

# Returns
A `DriftStatusReport` with classification and score.
"""
function drift_status(client::Client, octad_id::String)::DriftStatusReport
    resp = do_get(client, "/api/v1/octads/$octad_id/drift/status")
    return parse_response(DriftStatusReport, resp)
end

"""
    normalize_drift(client::Client, octad_id::String) -> DriftScore

Trigger re-normalisation of a drifted octad.

Normalisation recomputes the octad's embeddings and relationship weights
against the current baseline, effectively resetting the drift score.
This is a potentially expensive operation for octads with many modalities.

# Arguments
- `client::Client` — The authenticated client.
- `octad_id::String` — The unique identifier of the octad to normalise.

# Returns
The updated `DriftScore` after normalisation.
"""
function normalize_drift(client::Client, octad_id::String)::DriftScore
    resp = do_post(client, "/api/v1/octads/$octad_id/drift/normalize", Dict())
    return parse_response(DriftScore, resp)
end
