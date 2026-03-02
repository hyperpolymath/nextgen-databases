# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Search operations.
#
# This file provides multi-modal search capabilities against VeriSimDB,
# including full-text search, vector similarity search, spatial radius and
# bounding-box queries, nearest-neighbour lookups, and relationship traversal.

"""
    search_text(client, query; modalities=Modality[], limit=20, offset=0) -> Vector{SearchResult}

Perform a full-text search across hexad content.

# Arguments
- `client::Client` — The authenticated client.
- `query::String` — The text query string.

# Keyword Arguments
- `modalities::Vector{Modality}` — Filter by specific modalities.
- `limit::Int` — Maximum results to return.
- `offset::Int` — Number of results to skip.

# Returns
A vector of `SearchResult` items ranked by relevance.
"""
function search_text(
    client::Client,
    query::String;
    modalities::Vector{Modality}=Modality[],
    limit::Int=20,
    offset::Int=0
)::Vector{SearchResult}
    body = Dict(
        "query" => query,
        "modalities" => [string(m) for m in modalities],
        "limit" => limit,
        "offset" => offset
    )
    resp = do_post(client, "/api/v1/search/text", body)
    return parse_response(Vector{SearchResult}, resp)
end

"""
    search_vector(client, vector; model="", top_k=10, threshold=0.0) -> Vector{SearchResult}

Perform a vector similarity search using a query embedding.

# Arguments
- `client::Client` — The authenticated client.
- `vector::Vector{Float64}` — The query embedding vector.

# Keyword Arguments
- `model::String` — Name of the embedding model.
- `top_k::Int` — Number of nearest results.
- `threshold::Float64` — Minimum similarity threshold.
"""
function search_vector(
    client::Client,
    vector::Vector{Float64};
    model::String="",
    top_k::Int=10,
    threshold::Float64=0.0
)::Vector{SearchResult}
    body = Dict(
        "vector" => vector,
        "model" => model,
        "top_k" => top_k,
        "threshold" => threshold
    )
    resp = do_post(client, "/api/v1/search/vector", body)
    return parse_response(Vector{SearchResult}, resp)
end

"""
    search_spatial_radius(client; latitude, longitude, radius_km, limit=20) -> Vector{SearchResult}

Find hexads within a given radius of a geographic point.
"""
function search_spatial_radius(
    client::Client;
    latitude::Float64,
    longitude::Float64,
    radius_km::Float64,
    limit::Int=20
)::Vector{SearchResult}
    body = Dict(
        "latitude" => latitude,
        "longitude" => longitude,
        "radius_km" => radius_km,
        "limit" => limit
    )
    resp = do_post(client, "/api/v1/search/spatial/radius", body)
    return parse_response(Vector{SearchResult}, resp)
end

"""
    search_spatial_bounds(client; min_lat, min_lon, max_lat, max_lon, limit=20) -> Vector{SearchResult}

Find hexads within a rectangular bounding box.
"""
function search_spatial_bounds(
    client::Client;
    min_lat::Float64,
    min_lon::Float64,
    max_lat::Float64,
    max_lon::Float64,
    limit::Int=20
)::Vector{SearchResult}
    body = Dict(
        "min_lat" => min_lat,
        "min_lon" => min_lon,
        "max_lat" => max_lat,
        "max_lon" => max_lon,
        "limit" => limit
    )
    resp = do_post(client, "/api/v1/search/spatial/bounds", body)
    return parse_response(Vector{SearchResult}, resp)
end

"""
    search_nearest(client, hexad_id; top_k=10, modality=Vector) -> Vector{SearchResult}

Find the nearest neighbours of a given hexad.
"""
function search_nearest(
    client::Client,
    hexad_id::String;
    top_k::Int=10,
    modality::Modality=Vector
)::Vector{SearchResult}
    body = Dict(
        "hexad_id" => hexad_id,
        "top_k" => top_k,
        "modality" => string(modality)
    )
    resp = do_post(client, "/api/v1/search/nearest", body)
    return parse_response(Vector{SearchResult}, resp)
end

"""
    search_related(client, hexad_id; rel_type=nothing, depth=1, limit=20) -> Vector{SearchResult}

Traverse relationships from a given hexad.
"""
function search_related(
    client::Client,
    hexad_id::String;
    rel_type::Union{String,Nothing}=nothing,
    depth::Int=1,
    limit::Int=20
)::Vector{SearchResult}
    body = Dict{String,Any}(
        "hexad_id" => hexad_id,
        "depth" => depth,
        "limit" => limit
    )
    if !isnothing(rel_type)
        body["rel_type"] = rel_type
    end
    resp = do_post(client, "/api/v1/search/related", body)
    return parse_response(Vector{SearchResult}, resp)
end
