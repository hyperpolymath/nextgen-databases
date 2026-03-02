// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Federation operations.
//
// VeriSimDB supports federated operation where multiple VeriSimDB instances
// form a cluster, sharing and synchronising hexad data across peers. This
// module provides functions to register and manage federation peers, and
// to execute queries that span multiple federated nodes.

module verisimdb_client

import json

// PeerRegistration is the input for registering a new federation peer.
pub struct PeerRegistration {
pub:
	name     string
	url      string
	metadata map[string]string
}

// FederatedQueryRequest wraps a VQL query intended for federated execution
// across all peers in the cluster.
pub struct FederatedQueryRequest {
pub:
	query    string            // VQL query string
	params   map[string]string // Named parameters
	peer_ids []string          // Specific peers to query (empty = all peers)
	timeout  int = 30000       // Per-peer timeout in milliseconds
}

// FederatedQueryResult aggregates results from multiple peers.
pub struct FederatedQueryResult {
pub:
	results    []PeerQueryResult
	total      int
	elapsed_ms f64
}

// PeerQueryResult holds the result from a single peer in a federated query.
pub struct PeerQueryResult {
pub:
	peer_id    string
	peer_name  string
	result     VqlResult
	elapsed_ms f64
	error      ?string
}

// register_peer registers a new VeriSimDB instance as a federation peer.
//
// Parameters:
//   c     — The authenticated Client.
//   input — The peer registration details including name and URL.
//
// Returns:
//   The registered FederationPeer with server-assigned ID, or an error.
pub fn (c Client) register_peer(input PeerRegistration) !FederationPeer {
	body := json.encode(input)
	resp := c.do_post('/api/v1/federation/peers', body)!
	if resp.status_code != 201 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(FederationPeer, resp.body)
}

// list_peers retrieves all registered federation peers.
//
// Parameters:
//   c — The authenticated Client.
//
// Returns:
//   A list of FederationPeer records, or an error.
pub fn (c Client) list_peers() ![]FederationPeer {
	resp := c.do_get('/api/v1/federation/peers')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode([]FederationPeer, resp.body)
}

// federated_query executes a VQL query across one or more federation peers.
//
// If peer_ids is empty, the query is broadcast to all active peers. Results
// are aggregated and returned with per-peer timing and error information.
//
// Parameters:
//   c     — The authenticated Client.
//   input — The federated query request including VQL, parameters, and target peers.
//
// Returns:
//   A FederatedQueryResult aggregating all peer responses, or an error.
pub fn (c Client) federated_query(input FederatedQueryRequest) !FederatedQueryResult {
	body := json.encode(input)
	resp := c.do_post('/api/v1/federation/query', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(FederatedQueryResult, resp.body)
}
