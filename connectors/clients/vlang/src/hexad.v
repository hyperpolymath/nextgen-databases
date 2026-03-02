// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Hexad CRUD operations.
//
// This module provides create, read, update, delete, and paginated list
// operations for VeriSimDB hexad entities. All functions communicate with
// the VeriSimDB REST API via the Client's HTTP helpers.

module verisimdb_client

import json

// create_hexad creates a new hexad on the VeriSimDB server.
//
// Parameters:
//   c     — The authenticated Client.
//   input — The HexadInput describing the new hexad's modalities and data.
//
// Returns:
//   The newly created Hexad with server-assigned ID and timestamps,
//   or a VeriSimError on failure.
pub fn (c Client) create_hexad(input HexadInput) !Hexad {
	body := json.encode(input)
	resp := c.do_post('/api/v1/hexads', body)!
	if resp.status_code != 201 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(Hexad, resp.body)
}

// get_hexad retrieves a single hexad by its unique identifier.
//
// Parameters:
//   c  — The authenticated Client.
//   id — The hexad's unique identifier.
//
// Returns:
//   The requested Hexad, or a VeriSimError if not found.
pub fn (c Client) get_hexad(id string) !Hexad {
	resp := c.do_get('/api/v1/hexads/${id}')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(Hexad, resp.body)
}

// update_hexad updates an existing hexad with the given input fields.
// Only the fields present in the input are modified; others are left unchanged.
//
// Parameters:
//   c     — The authenticated Client.
//   id    — The hexad's unique identifier.
//   input — The HexadInput with fields to update.
//
// Returns:
//   The updated Hexad, or a VeriSimError on failure.
pub fn (c Client) update_hexad(id string, input HexadInput) !Hexad {
	body := json.encode(input)
	resp := c.do_put('/api/v1/hexads/${id}', body)!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(Hexad, resp.body)
}

// delete_hexad deletes a hexad by its unique identifier.
//
// Parameters:
//   c  — The authenticated Client.
//   id — The hexad's unique identifier.
//
// Returns:
//   true if the hexad was successfully deleted, or a VeriSimError on failure.
pub fn (c Client) delete_hexad(id string) !bool {
	resp := c.do_delete('/api/v1/hexads/${id}')!
	if resp.status_code != 204 && resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return true
}

// list_hexads retrieves a paginated list of hexads.
//
// Parameters:
//   c        — The authenticated Client.
//   page     — The page number (1-indexed).
//   per_page — The number of hexads per page.
//
// Returns:
//   A PaginatedResponse containing the hexad list and pagination metadata,
//   or a VeriSimError on failure.
pub fn (c Client) list_hexads(page int, per_page int) !PaginatedResponse {
	resp := c.do_get('/api/v1/hexads?page=${page}&per_page=${per_page}')!
	if resp.status_code != 200 {
		return error(parse_error_response(resp.body).message)
	}
	return json.decode(PaginatedResponse, resp.body)
}
