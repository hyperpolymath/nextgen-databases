// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — VCL (VeriSimDB Query Language) operations.
//
// VCL is VeriSimDB's native query language, designed for multi-modal queries
// that can span graph traversals, vector similarity, spatial filters, and
// temporal constraints in a single statement. This module provides functions
// to execute VCL statements and retrieve query execution plans.

module verisimdb_client

import json

// VclRequest is the payload for executing or explaining a VCL query.
pub struct VclRequest {
pub:
	query  string            // The VCL query string
	params map[string]string // Named parameters for parameterised queries
}

// execute_vcl executes a VCL query and returns the result set.
//
// VCL queries can combine modalities — for example:
//   FIND octads WHERE vector_similar($embedding, 0.8)
//     AND spatial_within(51.5, -0.1, 10km)
//     AND graph_connected("category:science", depth: 2)
//
// Parameters:
//   c      — The authenticated Client.
//   query  — The VCL query string.
//   params — Optional named parameters for parameterised queries.
//
// Returns:
//   A VclResult containing columns, rows, count, and execution time, or an error.
pub fn (c Client) execute_vcl(query string, params map[string]string) !VclResult {
	req := VclRequest{
		query: query
		params: params
	}
	body := json.encode(req)
	resp := c.do_post('/api/v1/vcl/execute', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(VclResult, resp.body)
}

// explain_vcl returns the query execution plan for a VCL statement without
// actually running the query. Useful for debugging and optimising queries.
//
// Parameters:
//   c      — The authenticated Client.
//   query  — The VCL query string.
//   params — Optional named parameters.
//
// Returns:
//   A VclExplanation containing the plan, estimated cost, and any warnings.
pub fn (c Client) explain_vcl(query string, params map[string]string) !VclExplanation {
	req := VclRequest{
		query: query
		params: params
	}
	body := json.encode(req)
	resp := c.do_post('/api/v1/vcl/explain', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(VclExplanation, resp.body)
}
