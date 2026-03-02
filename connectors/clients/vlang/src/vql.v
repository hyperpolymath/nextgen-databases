// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — VQL (VeriSimDB Query Language) operations.
//
// VQL is VeriSimDB's native query language, designed for multi-modal queries
// that can span graph traversals, vector similarity, spatial filters, and
// temporal constraints in a single statement. This module provides functions
// to execute VQL statements and retrieve query execution plans.

module verisimdb_client

import json

// VqlRequest is the payload for executing or explaining a VQL query.
pub struct VqlRequest {
pub:
	query  string            // The VQL query string
	params map[string]string // Named parameters for parameterised queries
}

// execute_vql executes a VQL query and returns the result set.
//
// VQL queries can combine modalities — for example:
//   FIND hexads WHERE vector_similar($embedding, 0.8)
//     AND spatial_within(51.5, -0.1, 10km)
//     AND graph_connected("category:science", depth: 2)
//
// Parameters:
//   c      — The authenticated Client.
//   query  — The VQL query string.
//   params — Optional named parameters for parameterised queries.
//
// Returns:
//   A VqlResult containing columns, rows, count, and execution time, or an error.
pub fn (c Client) execute_vql(query string, params map[string]string) !VqlResult {
	req := VqlRequest{
		query: query
		params: params
	}
	body := json.encode(req)
	resp := c.do_post('/api/v1/vql/execute', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(VqlResult, resp.body)
}

// explain_vql returns the query execution plan for a VQL statement without
// actually running the query. Useful for debugging and optimising queries.
//
// Parameters:
//   c      — The authenticated Client.
//   query  — The VQL query string.
//   params — Optional named parameters.
//
// Returns:
//   A VqlExplanation containing the plan, estimated cost, and any warnings.
pub fn (c Client) explain_vql(query string, params map[string]string) !VqlExplanation {
	req := VqlRequest{
		query: query
		params: params
	}
	body := json.encode(req)
	resp := c.do_post('/api/v1/vql/explain', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(VqlExplanation, resp.body)
}
