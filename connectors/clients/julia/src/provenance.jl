# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Provenance operations.
#
# Every hexad in VeriSimDB maintains an immutable provenance chain — a
# cryptographically linked sequence of events recording every mutation
# applied to the hexad. This file provides functions to query chains,
# record new events, and verify chain integrity.

"""
    get_provenance_chain(client::Client, hexad_id::String) -> ProvenanceChain

Retrieve the complete provenance chain for a hexad.

The chain is returned in chronological order (oldest event first) and
includes the verification status.

# Arguments
- `client::Client` — The authenticated client.
- `hexad_id::String` — The unique identifier of the hexad.

# Returns
A `ProvenanceChain` containing all events and verification status.
"""
function get_provenance_chain(client::Client, hexad_id::String)::ProvenanceChain
    resp = do_get(client, "/api/v1/hexads/$hexad_id/provenance")
    return parse_response(ProvenanceChain, resp)
end

"""
    record_provenance(client, hexad_id, input) -> ProvenanceEvent

Record a new provenance event on a hexad's chain.

The event is cryptographically linked to the previous event in the chain.
The server assigns the event ID and timestamp.

# Arguments
- `client::Client` — The authenticated client.
- `hexad_id::String` — The unique identifier of the hexad.
- `input::ProvenanceEventInput` — The event details to record.

# Returns
The newly created `ProvenanceEvent` with server-assigned fields.
"""
function record_provenance(
    client::Client,
    hexad_id::String,
    input::ProvenanceEventInput
)::ProvenanceEvent
    resp = do_post(client, "/api/v1/hexads/$hexad_id/provenance", input)
    return parse_response(ProvenanceEvent, resp)
end

"""
    verify_provenance(client::Client, hexad_id::String) -> Bool

Verify the cryptographic integrity of a hexad's provenance chain.

The server traverses the entire chain, checking each event's hash link to
its parent. Returns `true` if the chain is intact, `false` if tampering
is detected.

# Arguments
- `client::Client` — The authenticated client.
- `hexad_id::String` — The unique identifier of the hexad.

# Returns
`true` if the provenance chain is verified intact.
"""
function verify_provenance(client::Client, hexad_id::String)::Bool
    resp = do_post(client, "/api/v1/hexads/$hexad_id/provenance/verify", Dict())
    chain = parse_response(ProvenanceChain, resp)
    return chain.verified
end
