# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Federation operations.
#
# VeriSimDB supports federated operation where multiple instances form a cluster,
# sharing and synchronising hexad data across peers. This file provides functions
# to register and manage federation peers and to execute cross-node queries.

"""
    PeerRegistration

Input for registering a new federation peer.
"""
struct PeerRegistration
    name::String
    url::String
    metadata::Dict{String,String}
end

PeerRegistration(name::String, url::String) = PeerRegistration(name, url, Dict{String,String}())

JSON3.StructTypes.StructType(::Type{PeerRegistration}) = JSON3.StructTypes.Struct()

"""
    FederatedQueryRequest

Wraps a VQL query intended for federated execution across cluster peers.
"""
struct FederatedQueryRequest
    query::String
    params::Dict{String,String}
    peer_ids::Vector{String}
    timeout::Int
end

function FederatedQueryRequest(
    query::String;
    params::Dict{String,String}=Dict{String,String}(),
    peer_ids::Vector{String}=String[],
    timeout::Int=30000
)
    FederatedQueryRequest(query, params, peer_ids, timeout)
end

JSON3.StructTypes.StructType(::Type{FederatedQueryRequest}) = JSON3.StructTypes.Struct()

"""
    PeerQueryResult

Result from a single peer in a federated query.
"""
struct PeerQueryResult
    peer_id::String
    peer_name::String
    result::VqlResult
    elapsed_ms::Float64
    error::Union{String,Nothing}
end

JSON3.StructTypes.StructType(::Type{PeerQueryResult}) = JSON3.StructTypes.Struct()

"""
    FederatedQueryResult

Aggregated result from a federated query across multiple peers.
"""
struct FederatedQueryResult
    results::Vector{PeerQueryResult}
    total::Int
    elapsed_ms::Float64
end

JSON3.StructTypes.StructType(::Type{FederatedQueryResult}) = JSON3.StructTypes.Struct()

"""
    register_peer(client, input) -> FederationPeer

Register a new VeriSimDB instance as a federation peer.

# Arguments
- `client::Client` — The authenticated client.
- `input::PeerRegistration` — The peer registration details.

# Returns
The registered `FederationPeer` with server-assigned ID.
"""
function register_peer(client::Client, input::PeerRegistration)::FederationPeer
    resp = do_post(client, "/api/v1/federation/peers", input)
    return parse_response(FederationPeer, resp)
end

"""
    list_peers(client) -> Vector{FederationPeer}

Retrieve all registered federation peers.

# Arguments
- `client::Client` — The authenticated client.

# Returns
A vector of `FederationPeer` records.
"""
function list_peers(client::Client)::Vector{FederationPeer}
    resp = do_get(client, "/api/v1/federation/peers")
    return parse_response(Vector{FederationPeer}, resp)
end

"""
    federated_query(client, input) -> FederatedQueryResult

Execute a VQL query across one or more federation peers.

If `peer_ids` is empty, the query is broadcast to all active peers. Results
are aggregated with per-peer timing and error information.

# Arguments
- `client::Client` — The authenticated client.
- `input::FederatedQueryRequest` — The query request.

# Returns
A `FederatedQueryResult` aggregating all peer responses.
"""
function federated_query(client::Client, input::FederatedQueryRequest)::FederatedQueryResult
    resp = do_post(client, "/api/v1/federation/query", input)
    return parse_response(FederatedQueryResult, resp)
end
