# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Octad CRUD operations.
#
# This file provides create, read, update, delete, and paginated list
# operations for VeriSimDB octad entities. All functions communicate with
# the VeriSimDB REST API via the Client's HTTP helpers.

"""
    create_octad(client::Client, input::OctadInput) -> Octad

Create a new octad on the VeriSimDB server.

# Arguments
- `client::Client` — The authenticated client.
- `input::OctadInput` — The octad input describing modalities and data.

# Returns
The newly created `Octad` with server-assigned ID and timestamps.

# Throws
`VeriSimError` on HTTP or server failure.
"""
function create_octad(client::Client, input::OctadInput)::Octad
    resp = do_post(client, "/api/v1/octads", input)
    return parse_response(Octad, resp)
end

"""
    get_octad(client::Client, id::String) -> Octad

Retrieve a single octad by its unique identifier.

# Arguments
- `client::Client` — The authenticated client.
- `id::String` — The octad's unique identifier.

# Returns
The requested `Octad`.

# Throws
`NotFoundError` if the octad does not exist.
"""
function get_octad(client::Client, id::String)::Octad
    resp = do_get(client, "/api/v1/octads/$id")
    return parse_response(Octad, resp)
end

"""
    update_octad(client::Client, id::String, input::OctadInput) -> Octad

Update an existing octad with the given input fields.
Only the fields present in the input are modified; others remain unchanged.

# Arguments
- `client::Client` — The authenticated client.
- `id::String` — The octad's unique identifier.
- `input::OctadInput` — The fields to update.

# Returns
The updated `Octad`.

# Throws
`VeriSimError` on failure.
"""
function update_octad(client::Client, id::String, input::OctadInput)::Octad
    resp = do_put(client, "/api/v1/octads/$id", input)
    return parse_response(Octad, resp)
end

"""
    delete_octad(client::Client, id::String) -> Bool

Delete a octad by its unique identifier.

# Arguments
- `client::Client` — The authenticated client.
- `id::String` — The octad's unique identifier.

# Returns
`true` if the octad was successfully deleted.

# Throws
`VeriSimError` on failure.
"""
function delete_octad(client::Client, id::String)::Bool
    resp = do_delete(client, "/api/v1/octads/$id")
    status = resp.status
    if status == 204 || status == 200
        return true
    end
    throw(error_from_status(status, String(resp.body)))
end

"""
    list_octads(client::Client; page::Int=1, per_page::Int=20) -> PaginatedResponse

Retrieve a paginated list of octads.

# Keyword Arguments
- `page::Int` — Page number (1-indexed). Defaults to 1.
- `per_page::Int` — Number of octads per page. Defaults to 20.

# Returns
A `PaginatedResponse` containing octads and pagination metadata.

# Throws
`VeriSimError` on failure.
"""
function list_octads(client::Client; page::Int=1, per_page::Int=20)::PaginatedResponse
    resp = do_get(client, "/api/v1/octads?page=$page&per_page=$per_page")
    return parse_response(PaginatedResponse, resp)
end
