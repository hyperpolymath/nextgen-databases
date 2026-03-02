# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Main module.
#
# This is the top-level module for the VeriSimDB Julia client SDK. It aggregates
# all submodules (types, error, client, hexad, search, drift, provenance, vql,
# federation) and re-exports the public API.
#
# Usage:
#   using VeriSimDBClient
#   client = Client("http://localhost:8080")
#   hexad = create_hexad(client, HexadInput(modalities=[Graph, Vector]))

module VeriSimDBClient

using HTTP
using JSON3
using URIs
using Dates

# Include submodules in dependency order:
# types.jl and error.jl have no internal dependencies;
# client.jl depends on types and error;
# operation modules depend on client, types, and error.
include("types.jl")
include("error.jl")
include("client.jl")
include("hexad.jl")
include("search.jl")
include("drift.jl")
include("provenance.jl")
include("vql.jl")
include("federation.jl")

# --- Public exports ---

# Client
export Client, health

# Types
export Hexad, HexadInput, Modality, ModalityStatus, HexadStatus
export GraphData, GraphEdge, VectorData, TensorData, DocumentContent, SpatialData
export DriftScore, DriftLevel, DriftStatusReport
export ProvenanceEvent, ProvenanceChain, ProvenanceEventInput
export PaginatedResponse, SearchResult
export VqlResult, VqlExplanation
export FederationPeer

# Hexad CRUD
export create_hexad, get_hexad, update_hexad, delete_hexad, list_hexads

# Search
export search_text, search_vector, search_spatial_radius, search_spatial_bounds
export search_nearest, search_related

# Drift
export get_drift_score, drift_status, normalize_drift

# Provenance
export get_provenance_chain, record_provenance, verify_provenance

# VQL
export execute_vql, explain_vql

# Federation
export register_peer, list_peers, federated_query

# Errors
export VeriSimError, is_retryable

end # module VeriSimDBClient
