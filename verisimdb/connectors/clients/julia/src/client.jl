# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Connection configuration, authentication, and HTTP transport.
#
# This file defines the Client struct and the internal HTTP helper functions
# used by all other SDK modules to communicate with a VeriSimDB server instance.
# It supports multiple authentication methods (API key, Basic, Bearer token, or
# none) and manages base URL routing, request timeouts, and standard HTTP verbs.

using HTTP
using JSON3
using Base64

# ---------------------------------------------------------------------------
# Authentication types
# ---------------------------------------------------------------------------

"""
    Auth

Abstract type for authentication methods. Concrete subtypes:
- `ApiKeyAuth` — X-API-Key header
- `BasicAuth` — HTTP Basic Authentication
- `BearerAuth` — Bearer token
- `NoAuth` — No authentication
"""
abstract type Auth end

"""API key authentication via X-API-Key header."""
struct ApiKeyAuth <: Auth
    key::String
end

"""HTTP Basic Authentication (username:password)."""
struct BasicAuth <: Auth
    username::String
    password::String
end

"""Bearer token authentication."""
struct BearerAuth <: Auth
    token::String
end

"""No authentication."""
struct NoAuth <: Auth end

# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

"""
    Client

Holds connection configuration for a VeriSimDB server.

# Fields
- `base_url::String` — Root URL of the VeriSimDB API (e.g. "http://localhost:8080").
- `timeout::Int` — Request timeout in seconds. Defaults to 30.
- `auth::Auth` — Authentication method. Defaults to `NoAuth()`.

# Constructors
- `Client(base_url)` — Unauthenticated client.
- `Client(base_url, auth)` — Client with specific authentication.
- `Client(base_url; timeout=30, auth=NoAuth())` — Full keyword constructor.
"""
struct Client
    base_url::String
    timeout::Int
    auth::Auth
end

# Convenience constructors.
Client(base_url::String) = Client(rstrip(base_url, '/'), 30, NoAuth())
Client(base_url::String, auth::Auth) = Client(rstrip(base_url, '/'), 30, auth)
function Client(base_url::String; timeout::Int=30, auth::Auth=NoAuth())
    Client(rstrip(base_url, '/'), timeout, auth)
end

# ---------------------------------------------------------------------------
# Internal HTTP helpers
# ---------------------------------------------------------------------------

"""
    auth_headers(client::Client) -> Vector{Pair{String,String}}

Build authentication headers from the client's auth configuration.
Returns a vector of header pairs suitable for passing to HTTP.jl.
"""
function auth_headers(client::Client)::Vector{Pair{String,String}}
    headers = Pair{String,String}[]
    if client.auth isa ApiKeyAuth
        push!(headers, "X-API-Key" => client.auth.key)
    elseif client.auth isa BasicAuth
        encoded = base64encode("$(client.auth.username):$(client.auth.password)")
        push!(headers, "Authorization" => "Basic $encoded")
    elseif client.auth isa BearerAuth
        push!(headers, "Authorization" => "Bearer $(client.auth.token)")
    end
    return headers
end

"""
    do_get(client::Client, path::String) -> HTTP.Response

Send an authenticated GET request to the given API path.
"""
function do_get(client::Client, path::String)::HTTP.Response
    url = client.base_url * path
    headers = auth_headers(client)
    return HTTP.get(url; headers=headers, readtimeout=client.timeout, status_exception=false)
end

"""
    do_post(client::Client, path::String, body) -> HTTP.Response

Send an authenticated POST request with a JSON body.
"""
function do_post(client::Client, path::String, body)::HTTP.Response
    url = client.base_url * path
    headers = auth_headers(client)
    push!(headers, "Content-Type" => "application/json")
    json_body = JSON3.write(body)
    return HTTP.post(url; headers=headers, body=json_body, readtimeout=client.timeout, status_exception=false)
end

"""
    do_put(client::Client, path::String, body) -> HTTP.Response

Send an authenticated PUT request with a JSON body.
"""
function do_put(client::Client, path::String, body)::HTTP.Response
    url = client.base_url * path
    headers = auth_headers(client)
    push!(headers, "Content-Type" => "application/json")
    json_body = JSON3.write(body)
    return HTTP.put(url; headers=headers, body=json_body, readtimeout=client.timeout, status_exception=false)
end

"""
    do_delete(client::Client, path::String) -> HTTP.Response

Send an authenticated DELETE request to the given API path.
"""
function do_delete(client::Client, path::String)::HTTP.Response
    url = client.base_url * path
    headers = auth_headers(client)
    return HTTP.delete(url; headers=headers, readtimeout=client.timeout, status_exception=false)
end

"""
    parse_response(::Type{T}, resp::HTTP.Response) -> T

Parse an HTTP response body as JSON into the specified type T.
Throws a VeriSimError if the response indicates failure.
"""
function parse_response(::Type{T}, resp::HTTP.Response) where T
    status = resp.status
    body = String(resp.body)
    if status >= 400
        throw(error_from_status(status, body))
    end
    return JSON3.read(body, T)
end

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

"""
    health(client::Client) -> Bool

Check whether the VeriSimDB server is reachable and healthy.
Sends a GET request to /health and expects a 200 OK response.
"""
function health(client::Client)::Bool
    try
        resp = do_get(client, "/health")
        return resp.status == 200
    catch e
        if e isa VeriSimError
            rethrow()
        end
        throw(ConnectionError("Failed to connect to VeriSimDB server: $(sprint(showerror, e))"))
    end
end
