# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Provenance operations.
#
# Every octad in VeriSimDB maintains an immutable provenance chain — a
# cryptographically linked sequence of events recording every mutation
# applied to the octad. This file provides functions to query chains,
# record new events, and verify chain integrity.

"""
    get_provenance_chain(client::Client, octad_id::String) -> ProvenanceChain

Retrieve the complete provenance chain for a octad.

The chain is returned in chronological order (oldest event first) and
includes the verification status.

# Arguments
- `client::Client` — The authenticated client.
- `octad_id::String` — The unique identifier of the octad.

# Returns
A `ProvenanceChain` containing all events and verification status.
"""
function get_provenance_chain(client::Client, octad_id::String)::ProvenanceChain
    resp = do_get(client, "/api/v1/octads/$octad_id/provenance")
    return parse_response(ProvenanceChain, resp)
end

"""
    record_provenance(client, octad_id, input) -> ProvenanceEvent

Record a new provenance event on a octad's chain.

The event is cryptographically linked to the previous event in the chain.
The server assigns the event ID and timestamp.

# Arguments
- `client::Client` — The authenticated client.
- `octad_id::String` — The unique identifier of the octad.
- `input::ProvenanceEventInput` — The event details to record.

# Returns
The newly created `ProvenanceEvent` with server-assigned fields.
"""
function record_provenance(
    client::Client,
    octad_id::String,
    input::ProvenanceEventInput
)::ProvenanceEvent
    resp = do_post(client, "/api/v1/octads/$octad_id/provenance", input)
    return parse_response(ProvenanceEvent, resp)
end

"""
    verify_provenance(client::Client, octad_id::String) -> Bool

Verify the cryptographic integrity of a octad's provenance chain.

The server traverses the entire chain, checking each event's hash link to
its parent. Returns `true` if the chain is intact, `false` if tampering
is detected.

# Arguments
- `client::Client` — The authenticated client.
- `octad_id::String` — The unique identifier of the octad.

# Returns
`true` if the provenance chain is verified intact.
"""
function verify_provenance(client::Client, octad_id::String)::Bool
    resp = do_post(client, "/api/v1/octads/$octad_id/provenance/verify", Dict())
    chain = parse_response(ProvenanceChain, resp)
    return chain.verified
end
