# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Core type definitions.
#
# This file defines all data structures exchanged between the Julia client SDK
# and the VeriSimDB server. Types are Julia structs with JSON3.StructTypes
# registration for automatic serialization/deserialization.
#
# The central entity in VeriSimDB is the Hexad — a six-faceted data object that
# unifies graph, vector, tensor, semantic, document, temporal, provenance, and
# spatial modalities into a single addressable record.

using JSON3
using Dates

# ---------------------------------------------------------------------------
# Modality
# ---------------------------------------------------------------------------

"""
    Modality

Enumeration of the eight data modalities supported by VeriSimDB hexads.
A single hexad can participate in multiple modalities simultaneously.
"""
@enum Modality begin
    Graph
    Vector
    Tensor
    Semantic
    Document
    Temporal
    Provenance
    Spatial
end

"""
    ModalityStatus

Indicates which modalities are active on a given hexad.
Each field is a Bool; true means the modality is enabled.
"""
struct ModalityStatus
    graph::Bool
    vector::Bool
    tensor::Bool
    semantic::Bool
    document::Bool
    temporal::Bool
    provenance::Bool
    spatial::Bool
end

# Default constructor with all modalities disabled.
ModalityStatus() = ModalityStatus(false, false, false, false, false, false, false, false)

JSON3.StructTypes.StructType(::Type{ModalityStatus}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Hexad status
# ---------------------------------------------------------------------------

"""
    HexadStatus

Lifecycle state of a hexad: active, archived, draft, or deleted.
"""
@enum HexadStatus begin
    Active
    Archived
    Draft
    Deleted
end

# ---------------------------------------------------------------------------
# Graph modality data
# ---------------------------------------------------------------------------

"""
    GraphEdge

A directed relationship between two hexads in the graph modality.
"""
struct GraphEdge
    source::String
    target::String
    rel_type::String
    weight::Float64
    metadata::Dict{String,String}
end

JSON3.StructTypes.StructType(::Type{GraphEdge}) = JSON3.StructTypes.Struct()

"""
    GraphData

Graph-modality data for a hexad: edges and node properties.
"""
struct GraphData
    edges::Vector{GraphEdge}
    properties::Dict{String,String}
end

JSON3.StructTypes.StructType(::Type{GraphData}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Vector modality data
# ---------------------------------------------------------------------------

"""
    VectorData

Embedding vector data for vector-modality operations such as similarity
search and nearest-neighbour queries.
"""
struct VectorData
    embedding::Vector{Float64}
    model::String
    dimensions::Int
end

JSON3.StructTypes.StructType(::Type{VectorData}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Tensor modality data
# ---------------------------------------------------------------------------

"""
    TensorData

Multi-dimensional tensor data reference. The actual tensor data is stored
externally; `data_ref` is a URI pointing to the storage location.
"""
struct TensorData
    shape::Vector{Int}
    dtype::String
    data_ref::String
end

JSON3.StructTypes.StructType(::Type{TensorData}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Document modality data
# ---------------------------------------------------------------------------

"""
    DocumentContent

Document-modality content: raw text, structured format, and language metadata.
"""
struct DocumentContent
    text::String
    format::String        # e.g. "plain", "markdown", "html"
    language::String      # ISO 639-1 language code
    metadata::Dict{String,String}
end

JSON3.StructTypes.StructType(::Type{DocumentContent}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Spatial modality data
# ---------------------------------------------------------------------------

"""
    SpatialData

Spatial-modality coordinates and geometry. Supports WGS-84 and other CRS.
"""
struct SpatialData
    latitude::Float64
    longitude::Float64
    altitude::Union{Float64,Nothing}
    geometry::Union{String,Nothing}   # GeoJSON geometry string
    crs::String                       # e.g. "EPSG:4326"
end

JSON3.StructTypes.StructType(::Type{SpatialData}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Hexad (core entity)
# ---------------------------------------------------------------------------

"""
    Hexad

The core entity in VeriSimDB — a multi-modal data object unifying graph,
vector, tensor, semantic, document, temporal, provenance, and spatial modalities
into a single addressable record.
"""
struct Hexad
    id::String
    status::HexadStatus
    modalities::ModalityStatus
    created_at::String              # ISO 8601 timestamp
    updated_at::String              # ISO 8601 timestamp
    metadata::Dict{String,String}
    graph_data::Union{GraphData,Nothing}
    vector_data::Union{VectorData,Nothing}
    tensor_data::Union{TensorData,Nothing}
    content::Union{DocumentContent,Nothing}
    spatial_data::Union{SpatialData,Nothing}
end

JSON3.StructTypes.StructType(::Type{Hexad}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Hexad input (for create/update)
# ---------------------------------------------------------------------------

"""
    HexadInput

Input structure for creating or updating a hexad. Optional fields use
`Union{T, Nothing}` (Julia's equivalent of Option/Maybe).
"""
struct HexadInput
    graph_data::Union{GraphData,Nothing}
    vector_data::Union{VectorData,Nothing}
    tensor_data::Union{TensorData,Nothing}
    content::Union{DocumentContent,Nothing}
    spatial_data::Union{SpatialData,Nothing}
    metadata::Dict{String,String}
    modalities::Vector{Modality}
end

# Convenience constructor with keyword arguments.
function HexadInput(;
    graph_data::Union{GraphData,Nothing}=nothing,
    vector_data::Union{VectorData,Nothing}=nothing,
    tensor_data::Union{TensorData,Nothing}=nothing,
    content::Union{DocumentContent,Nothing}=nothing,
    spatial_data::Union{SpatialData,Nothing}=nothing,
    metadata::Dict{String,String}=Dict{String,String}(),
    modalities::Vector{Modality}=Modality[]
)
    HexadInput(graph_data, vector_data, tensor_data, content, spatial_data, metadata, modalities)
end

JSON3.StructTypes.StructType(::Type{HexadInput}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Drift types
# ---------------------------------------------------------------------------

"""
    DriftScore

Drift measurement for a hexad. The `score` field ranges from 0.0 (no drift,
fully aligned with baseline) to 1.0 (maximum drift, completely diverged).
The `components` dictionary breaks down the score by modality.
"""
struct DriftScore
    hexad_id::String
    score::Float64
    components::Dict{String,Float64}
    measured_at::String   # ISO 8601
    baseline_at::String   # ISO 8601
end

JSON3.StructTypes.StructType(::Type{DriftScore}) = JSON3.StructTypes.Struct()

"""
    DriftLevel

Classification of drift severity.
"""
@enum DriftLevel begin
    DriftStable
    DriftLow
    DriftModerate
    DriftHigh
    DriftCritical
end

"""
    DriftStatusReport

Classified drift status for a hexad, combining the numeric score with
a human-readable level and message.
"""
struct DriftStatusReport
    hexad_id::String
    level::DriftLevel
    score::DriftScore
    message::String
end

JSON3.StructTypes.StructType(::Type{DriftStatusReport}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Provenance types
# ---------------------------------------------------------------------------

"""
    ProvenanceEvent

A single event in a hexad's provenance chain. Each event is cryptographically
linked to its parent, forming an immutable audit trail.
"""
struct ProvenanceEvent
    event_id::String
    hexad_id::String
    event_type::String     # e.g. "created", "updated", "merged", "split"
    actor::String
    timestamp::String      # ISO 8601
    details::Dict{String,String}
    parent_id::Union{String,Nothing}
end

JSON3.StructTypes.StructType(::Type{ProvenanceEvent}) = JSON3.StructTypes.Struct()

"""
    ProvenanceChain

Complete provenance history for a hexad, including verification status.
"""
struct ProvenanceChain
    hexad_id::String
    events::Vector{ProvenanceEvent}
    verified::Bool
end

JSON3.StructTypes.StructType(::Type{ProvenanceChain}) = JSON3.StructTypes.Struct()

"""
    ProvenanceEventInput

Input for recording a new provenance event.
"""
struct ProvenanceEventInput
    event_type::String
    actor::String
    details::Dict{String,String}
end

JSON3.StructTypes.StructType(::Type{ProvenanceEventInput}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Pagination
# ---------------------------------------------------------------------------

"""
    PaginatedResponse

Paginated response wrapping a list of hexads with page metadata.
"""
struct PaginatedResponse
    items::Vector{Hexad}
    total::Int
    page::Int
    per_page::Int
    total_pages::Int
end

JSON3.StructTypes.StructType(::Type{PaginatedResponse}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Search types
# ---------------------------------------------------------------------------

"""
    SearchResult

A search result pairing a hexad with a relevance score (0.0 to 1.0).
"""
struct SearchResult
    hexad::Hexad
    score::Float64
end

JSON3.StructTypes.StructType(::Type{SearchResult}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# VQL types
# ---------------------------------------------------------------------------

"""
    VqlResult

Result of a VQL query execution, containing columnar data and timing.
"""
struct VqlResult
    columns::Vector{String}
    rows::Vector{Vector{String}}
    count::Int
    elapsed_ms::Float64
end

JSON3.StructTypes.StructType(::Type{VqlResult}) = JSON3.StructTypes.Struct()

"""
    VqlExplanation

Query execution plan for a VQL statement, showing cost estimates and warnings.
"""
struct VqlExplanation
    query::String
    plan::String
    cost::Float64
    warnings::Vector{String}
end

JSON3.StructTypes.StructType(::Type{VqlExplanation}) = JSON3.StructTypes.Struct()

# ---------------------------------------------------------------------------
# Federation types
# ---------------------------------------------------------------------------

"""
    FederationPeer

A remote VeriSimDB node in a federated cluster.
"""
struct FederationPeer
    peer_id::String
    name::String
    url::String
    status::String       # "active", "inactive", "syncing"
    last_seen::String    # ISO 8601
    metadata::Dict{String,String}
end

JSON3.StructTypes.StructType(::Type{FederationPeer}) = JSON3.StructTypes.Struct()
