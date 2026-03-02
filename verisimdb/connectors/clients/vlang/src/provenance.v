// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Provenance operations.
//
// Every hexad in VeriSimDB maintains an immutable provenance chain — a
// cryptographically linked sequence of events recording every mutation
// (creation, update, merge, split, delete) applied to the hexad. This
// module provides functions to query provenance chains, record new
// provenance events, and verify chain integrity.

module verisimdb_client

import json

// ProvenanceEventInput is the input structure for recording a new provenance event.
pub struct ProvenanceEventInput {
pub:
	event_type string            // e.g. "annotation", "review", "transformation"
	actor      string            // identifier of the agent or user
	details    map[string]string // arbitrary key-value metadata
}

// get_provenance_chain retrieves the complete provenance chain for a hexad.
//
// The provenance chain is returned in chronological order (oldest event first)
// and includes the verification status of the chain.
//
// Parameters:
//   c        — The authenticated Client.
//   hexad_id — The unique identifier of the hexad.
//
// Returns:
//   A ProvenanceChain containing all events and verification status, or an error.
pub fn (c Client) get_provenance_chain(hexad_id string) !ProvenanceChain {
	resp := c.do_get('/api/v1/hexads/${hexad_id}/provenance')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(ProvenanceChain, resp.body)
}

// record_provenance appends a new event to a hexad's provenance chain.
//
// The event is cryptographically linked to the previous event in the chain,
// ensuring tamper-evidence. The server assigns the event ID and timestamp.
//
// Parameters:
//   c        — The authenticated Client.
//   hexad_id — The unique identifier of the hexad.
//   input    — The event details to record.
//
// Returns:
//   The newly created ProvenanceEvent with server-assigned fields, or an error.
pub fn (c Client) record_provenance(hexad_id string, input ProvenanceEventInput) !ProvenanceEvent {
	body := json.encode(input)
	resp := c.do_post('/api/v1/hexads/${hexad_id}/provenance', body)!
	if resp.status_code != 201 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(ProvenanceEvent, resp.body)
}

// verify_provenance verifies the cryptographic integrity of a hexad's provenance chain.
//
// The server traverses the entire chain, checking each event's hash link to
// its parent. Returns true if the chain is intact, false if tampering is detected.
//
// Parameters:
//   c        — The authenticated Client.
//   hexad_id — The unique identifier of the hexad.
//
// Returns:
//   true if the provenance chain is verified intact, false otherwise, or an error.
pub fn (c Client) verify_provenance(hexad_id string) !bool {
	resp := c.do_post('/api/v1/hexads/${hexad_id}/provenance/verify', '{}')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	chain := json.decode(ProvenanceChain, resp.body)
	return chain.verified
}
