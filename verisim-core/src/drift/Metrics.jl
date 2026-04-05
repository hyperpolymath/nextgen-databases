# SPDX-License-Identifier: PMPL-1.0-or-later
#
# drift/Metrics.jl — pairwise drift functions per TeX §4.3.
#
# Absent-pair convention (def:pairwise-drift): d(⊥, ·) = d(·, ⊥) = 0.
# This is the soundness property that lets Federable shapes be absent
# at store level without making drift claims unsound.
#
# Phase 3 implements d_SV (Semantic-Vector) as the first pairwise drift
# for the parity test. The other pairs are stubbed with proper signatures
# and will be filled in as more peers come online.

module Metrics

using SHA

export cosine_distance, hash_embedding, d_SV, d_VD, d_SD, drift

# -----------------------------------------------------------------------
# Primitive drift functions
# -----------------------------------------------------------------------

"""
    cosine_distance(v1, v2) -> Float64

Cosine distance: 1 - (v1 · v2) / (‖v1‖ ‖v2‖).
Returns 0 for parallel vectors, 1 for orthogonal, 2 for anti-parallel.
"""
function cosine_distance(v1::AbstractVector{<:Real},
                         v2::AbstractVector{<:Real})::Float64
    length(v1) == length(v2) || throw(DimensionMismatch(
        "cosine_distance: length($(length(v1))) ≠ length($(length(v2)))"))
    n1 = sqrt(sum(x*x for x in v1))
    n2 = sqrt(sum(x*x for x in v2))
    (n1 == 0 || n2 == 0) && return 0.0
    dot = sum(v1[i] * v2[i] for i in eachindex(v1))
    1.0 - Float64(dot) / (Float64(n1) * Float64(n2))
end

"""
    hash_embedding(bytes, dim) -> Vector{Float32}

Deterministic hash-derived embedding. Used as a stand-in for a real
embedding function f : Σ_D -> R^d during testing. Property: same input
always yields same embedding.

This is a TEST SURROGATE for the real embedding function the TeX
assumes (§4.3, d_{V,D}: "the embedding that would be computed from the
current document content"). Real impl would call a language model.
"""
function hash_embedding(bytes::AbstractVector{UInt8}, dim::Int = 384)::Vector{Float32}
    dim > 0 || throw(ArgumentError("dim must be > 0"))
    # Expand SHA-256 output (32 bytes) to dim floats by repeated hashing.
    out = Vector{Float32}(undef, dim)
    counter = UInt8(0)
    i = 1
    while i <= dim
        h = sha256(vcat(bytes, [counter]))
        for j in 1:32
            i > dim && break
            # Map byte 0..255 to [-1, 1)
            out[i] = (Float32(h[j]) - 127.5f0) / 127.5f0
            i += 1
        end
        counter += UInt8(1)
    end
    out
end

# -----------------------------------------------------------------------
# Pairwise drift — Semantic × Vector (d_SV)
# -----------------------------------------------------------------------

"""
    d_SV(semantic_type_uris, semantic_proof, vector_embedding) -> Float64

Semantic-Vector drift. Defined for the experiment as: cosine distance
between the peer's stored embedding and a hash-derived embedding of
Core's Semantic blob (type URIs + proof bytes).

This is a research-prototype metric, not drawn directly from TeX §4.3
(which defines d_VD rather than d_SV). d_SV is chosen here because
both shapes involved are implementable with minimal plumbing: S is
in Core, V is the first Federable peer.

Both arguments must be present (non-nothing); absence is handled by
the `drift` dispatcher, not here.
"""
function d_SV(type_uris::Vector{String},
              proof_bytes::Vector{UInt8},
              vector_embedding::Vector{Float32})::Float64
    semantic_bytes = vcat(
        collect(codeunits(join(type_uris, ","))),
        proof_bytes,
    )
    ref = hash_embedding(semantic_bytes, length(vector_embedding))
    cosine_distance(ref, vector_embedding)
end

# -----------------------------------------------------------------------
# Pairwise drift — Vector × Document (d_VD, TeX §4.3)
# -----------------------------------------------------------------------

"""
    d_VD(vector_embedding, document_bytes) -> Float64

Vector-Document drift (TeX §4.3, d_{V,D}): cosine distance between
stored embedding and the embedding that *would* be computed from the
current document content. A drift value near 0 indicates the embedding
is fresh; near 1 indicates the document has changed since the
embedding was computed.
"""
function d_VD(vector_embedding::Vector{Float32},
              document_bytes::Vector{UInt8})::Float64
    ref = hash_embedding(document_bytes, length(vector_embedding))
    cosine_distance(ref, vector_embedding)
end

# -----------------------------------------------------------------------
# Pairwise drift — Semantic × Document (d_SD)
# -----------------------------------------------------------------------

"""
    d_SD(semantic_type_uris, semantic_proof, document_bytes) -> Float64

Semantic-Document drift. Research-prototype definition: cosine distance
between hash-derived embeddings of the Semantic blob and the Document
bytes. Plays the role TeX §4.3 leaves implicit for this pair.
"""
function d_SD(type_uris::Vector{String},
              proof_bytes::Vector{UInt8},
              document_bytes::Vector{UInt8})::Float64
    semantic_bytes = vcat(
        collect(codeunits(join(type_uris, ","))),
        proof_bytes,
    )
    dim = 384
    s_ref = hash_embedding(semantic_bytes, dim)
    d_ref = hash_embedding(document_bytes, dim)
    cosine_distance(s_ref, d_ref)
end

# -----------------------------------------------------------------------
# Drift dispatcher — absent-pair convention
# -----------------------------------------------------------------------

"""
    drift(shape1, val1, shape2, val2) -> Float64

Dispatcher over the 28 shape pairs. Returns 0 when either value is
`nothing` (absent-pair convention, def:pairwise-drift). Returns the
appropriate d_{m1,m2} when both present.

Only d_SV is implemented in Phase 3. Other pairs throw an error to
surface missing implementations loudly rather than silently returning
0 when they're meant to contribute.
"""
function drift(shape1::Symbol, val1,
               shape2::Symbol, val2)::Float64
    # Absent-pair convention: d(⊥, ·) = d(·, ⊥) = 0.
    (val1 === nothing || val2 === nothing) && return 0.0

    # Normalise pair order — canonicalise so (A,B) and (B,A) dispatch the
    # same way. Priority order: :semantic < :vector < :document.
    canonical_order = Dict(:semantic => 1, :vector => 2, :document => 3)
    if haskey(canonical_order, shape1) && haskey(canonical_order, shape2)
        if canonical_order[shape1] > canonical_order[shape2]
            shape1, shape2 = shape2, shape1
            val1, val2 = val2, val1
        end
    end

    if shape1 == :semantic && shape2 == :vector
        return d_SV(val1.type_uris, val1.proof_bytes, val2)
    elseif shape1 == :vector && shape2 == :document
        return d_VD(val1, val2)
    elseif shape1 == :semantic && shape2 == :document
        return d_SD(val1.type_uris, val1.proof_bytes, val2)
    end

    error("drift: pair ($shape1, $shape2) not implemented. " *
          "Wired pairs: (S,V), (V,D), (S,D). Add to drift/Metrics.jl.")
end

end # module
