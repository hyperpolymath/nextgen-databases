// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Octad CRUD operations.
//
// This module provides create, read, update, delete, and paginated list
// operations for VeriSimDB octad entities. All functions communicate with
// the VeriSimDB REST API via the Client's HTTP helpers.

module verisimdb_client

import json

// create_octad creates a new octad on the VeriSimDB server.
//
// Parameters:
//   c     — The authenticated Client.
//   input — The OctadInput describing the new octad's modalities and data.
//
// Returns:
//   The newly created Octad with server-assigned ID and timestamps,
//   or a VeriSimError on failure.
pub fn (c Client) create_octad(input OctadInput) !Octad {
	body := json.encode(input)
	resp := c.do_post('/api/v1/octads', body)!
	if resp.status_code != 201 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(Octad, resp.body)
}

// get_octad retrieves a single octad by its unique identifier.
//
// Parameters:
//   c  — The authenticated Client.
//   id — The octad's unique identifier.
//
// Returns:
//   The requested Octad, or a VeriSimError if not found.
pub fn (c Client) get_octad(id string) !Octad {
	resp := c.do_get('/api/v1/octads/${id}')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(Octad, resp.body)
}

// update_octad updates an existing octad with the given input fields.
// Only the fields present in the input are modified; others are left unchanged.
//
// Parameters:
//   c     — The authenticated Client.
//   id    — The octad's unique identifier.
//   input — The OctadInput with fields to update.
//
// Returns:
//   The updated Octad, or a VeriSimError on failure.
pub fn (c Client) update_octad(id string, input OctadInput) !Octad {
	body := json.encode(input)
	resp := c.do_put('/api/v1/octads/${id}', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(Octad, resp.body)
}

// delete_octad deletes a octad by its unique identifier.
//
// Parameters:
//   c  — The authenticated Client.
//   id — The octad's unique identifier.
//
// Returns:
//   true if the octad was successfully deleted, or a VeriSimError on failure.
pub fn (c Client) delete_octad(id string) !bool {
	resp := c.do_delete('/api/v1/octads/${id}')!
	if resp.status_code != 204 && resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return true
}

// list_octads retrieves a paginated list of octads.
//
// Parameters:
//   c        — The authenticated Client.
//   page     — The page number (1-indexed).
//   per_page — The number of octads per page.
//
// Returns:
//   A PaginatedResponse containing the octad list and pagination metadata,
//   or a VeriSimError on failure.
pub fn (c Client) list_octads(page int, per_page int) !PaginatedResponse {
	resp := c.do_get('/api/v1/octads?page=${page}&per_page=${per_page}')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(PaginatedResponse, resp.body)
}
