# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Hexad CRUD operations.
#
# This file provides create, read, update, delete, and paginated list
# operations for VeriSimDB hexad entities. All functions communicate with
# the VeriSimDB REST API via the Client's HTTP helpers.

"""
    create_hexad(client::Client, input::HexadInput) -> Hexad

Create a new hexad on the VeriSimDB server.

# Arguments
- `client::Client` — The authenticated client.
- `input::HexadInput` — The hexad input describing modalities and data.

# Returns
The newly created `Hexad` with server-assigned ID and timestamps.

# Throws
`VeriSimError` on HTTP or server failure.
"""
function create_hexad(client::Client, input::HexadInput)::Hexad
    resp = do_post(client, "/api/v1/hexads", input)
    return parse_response(Hexad, resp)
end

"""
    get_hexad(client::Client, id::String) -> Hexad

Retrieve a single hexad by its unique identifier.

# Arguments
- `client::Client` — The authenticated client.
- `id::String` — The hexad's unique identifier.

# Returns
The requested `Hexad`.

# Throws
`NotFoundError` if the hexad does not exist.
"""
function get_hexad(client::Client, id::String)::Hexad
    resp = do_get(client, "/api/v1/hexads/$id")
    return parse_response(Hexad, resp)
end

"""
    update_hexad(client::Client, id::String, input::HexadInput) -> Hexad

Update an existing hexad with the given input fields.
Only the fields present in the input are modified; others remain unchanged.

# Arguments
- `client::Client` — The authenticated client.
- `id::String` — The hexad's unique identifier.
- `input::HexadInput` — The fields to update.

# Returns
The updated `Hexad`.

# Throws
`VeriSimError` on failure.
"""
function update_hexad(client::Client, id::String, input::HexadInput)::Hexad
    resp = do_put(client, "/api/v1/hexads/$id", input)
    return parse_response(Hexad, resp)
end

"""
    delete_hexad(client::Client, id::String) -> Bool

Delete a hexad by its unique identifier.

# Arguments
- `client::Client` — The authenticated client.
- `id::String` — The hexad's unique identifier.

# Returns
`true` if the hexad was successfully deleted.

# Throws
`VeriSimError` on failure.
"""
function delete_hexad(client::Client, id::String)::Bool
    resp = do_delete(client, "/api/v1/hexads/$id")
    status = resp.status
    if status == 204 || status == 200
        return true
    end
    throw(error_from_status(status, String(resp.body)))
end

"""
    list_hexads(client::Client; page::Int=1, per_page::Int=20) -> PaginatedResponse

Retrieve a paginated list of hexads.

# Keyword Arguments
- `page::Int` — Page number (1-indexed). Defaults to 1.
- `per_page::Int` — Number of hexads per page. Defaults to 20.

# Returns
A `PaginatedResponse` containing hexads and pagination metadata.

# Throws
`VeriSimError` on failure.
"""
function list_hexads(client::Client; page::Int=1, per_page::Int=20)::PaginatedResponse
    resp = do_get(client, "/api/v1/hexads?page=$page&per_page=$per_page")
    return parse_response(PaginatedResponse, resp)
end
