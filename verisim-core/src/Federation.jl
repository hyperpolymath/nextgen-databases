# SPDX-License-Identifier: PMPL-1.0-or-later
#
# FederationManager.jl — Clauses 1 & 3 (shape-orthogonal) + peer
# registration + aggregate-drift orchestration.
#
# Clause 1: weight renormalisation (per Remark rem:agg-drift-renorm
#           added to TeX §4.2 — see FOLDBACK.adoc).
# Clause 3: peer attestation + freshness window enforcement.

module Federation

import ..Metrics

export DriftWeights, Manager, PeerAttestation,
       renormalise, register_peer!, registered_shapes,
       is_fresh, aggregate_drift,
       CORE_SHAPES, FEDERABLE_SHAPES, CONDITIONAL_SHAPES

# Phase 1 classification — runtime equivalent of Idris2 IsFederable predicate.
const CORE_SHAPES        = Set{Symbol}([:semantic, :temporal, :provenance])
const FEDERABLE_SHAPES   = Set{Symbol}([:vector, :tensor, :document, :spatial])
const CONDITIONAL_SHAPES = Set{Symbol}([:graph])

"""
Weight assignment over unordered modality pairs (def:agg-drift).
Invariant: Σ values = 1 over all pairs in the map.

Pairs are stored with canonical ordering (sort by symbol name) so
(:semantic, :vector) and (:vector, :semantic) refer to the same entry.
"""
struct DriftWeights
    pair_weights::Dict{Tuple{Symbol, Symbol}, Float64}
end

"Canonicalise a shape pair by lexicographic ordering."
canonical_pair(a::Symbol, b::Symbol) = a <= b ? (a, b) : (b, a)

"""
    DriftWeights(pairs::Pair...)

Convenience constructor with unordered pair literals:

    DriftWeights((:semantic, :vector) => 0.5, (:graph, :document) => 0.5)
"""
function DriftWeights(pairs::Pair...)
    d = Dict{Tuple{Symbol, Symbol}, Float64}()
    for (p, w) in pairs
        d[canonical_pair(p...)] = w
    end
    DriftWeights(d)
end

# -----------------------------------------------------------------------
# Clause 1: weight renormalisation
# -----------------------------------------------------------------------

"""
    renormalise(present::Vector{Symbol}, weights::DriftWeights) -> DriftWeights

Keep only pairs where both shapes are in `present`; renormalise to
sum 1. Matches Remark rem:agg-drift-renorm added to the TeX.

If total weight of present pairs is 0, returns the (empty or kept)
map unchanged — aggregate drift over such a scope is structurally 0.
"""
function renormalise(present::Vector{Symbol}, weights::DriftWeights)::DriftWeights
    keep = Dict{Tuple{Symbol, Symbol}, Float64}()
    for ((a, b), w) in weights.pair_weights
        if a in present && b in present
            keep[(a, b)] = w
        end
    end
    total = sum(values(keep); init = 0.0)
    if total == 0.0
        return DriftWeights(keep)
    end
    DriftWeights(Dict(pair => w / total for (pair, w) in keep))
end

# -----------------------------------------------------------------------
# Clause 3: attestation surface
# -----------------------------------------------------------------------

"""
Peer's attestation metadata (mirrors Idris2 `PeerAttestation` record
in FederationContract.idr). Uses duck-typing on Timestamp and Signature
fields to avoid importing VerisimCore here (load-order neutral).
"""
struct PeerAttestation
    public_key_id::Vector{UInt8}
    latest_attest::Any        # VerisimCore.Signature (duck-typed)
    attest_timestamp::Any     # VerisimCore.Timestamp (duck-typed)
    freshness_window_ns::Int64
end

"""
    is_fresh(now_ts, peer_attest::PeerAttestation) -> Bool

Matches Idris2 `isFresh : Timestamp -> PeerAttestation -> Bool`.
True iff attestation's timestamp is within the freshness window
relative to `now_ts`, and is not from the future.
"""
function is_fresh(now_ts, peer_attest::PeerAttestation)::Bool
    age = now_ts.epoch_nanos - peer_attest.attest_timestamp.epoch_nanos
    age >= 0 && age <= peer_attest.freshness_window_ns
end

# -----------------------------------------------------------------------
# Manager: registers peers + orchestrates aggregate drift
# -----------------------------------------------------------------------

"""
Holds registered Federable peers keyed by shape symbol.
One peer per shape — federations can only federate a given shape through
a single peer in this prototype.
"""
mutable struct Manager
    peers::Dict{Symbol, Any}
end
Manager() = Manager(Dict{Symbol, Any}())

"""
    register_peer!(mgr, shape, peer) -> Manager

Register `peer` as the federation peer for `shape`. Runtime equivalent
of the Idris2 `IsFederable` predicate: rejects Core shapes (Semantic,
Temporal, Provenance) with an error, since Core shapes cannot be
federated by construction (Phase 1 resolution).
"""
function register_peer!(mgr::Manager, shape::Symbol, peer)
    shape in CORE_SHAPES && error(
        "FederationManager.register_peer!: :$shape is a Core shape " *
        "and cannot be federated. Core = $(collect(CORE_SHAPES))."
    )
    haskey(mgr.peers, shape) && error(
        "FederationManager: shape :$shape already has a registered peer."
    )
    mgr.peers[shape] = peer
    mgr
end

"Which shapes have a Federable peer registered with this manager."
registered_shapes(mgr::Manager)::Vector{Symbol} = sort(collect(keys(mgr.peers)))

# -----------------------------------------------------------------------
# Aggregate drift — the federation-parity-critical computation
# -----------------------------------------------------------------------

"""
    aggregate_drift(core_shape_values, manager, octad_id, weights)
        -> Float64

Compute aggregate drift over `weights.pair_weights` where each pair's
contribution is `w_{m1,m2} * d_{m1,m2}(φ(m1), φ(m2))`.

`core_shape_values` is a Dict{Symbol, Any} mapping Core shape symbols
to their values (or `nothing` if absent). Federable values are fetched
from registered peers via `drift_against`.

Weights are NOT renormalised here — caller must renormalise first if
reducing over a sub-scope.

Absent-pair convention: d(⊥, ·) = 0, handled inside the shape-specific
drift functions via the dispatcher.
"""
function aggregate_drift(core_shape_values::Dict{Symbol, Any},
                         manager::Manager,
                         octad_id,
                         weights::DriftWeights)::Float64
    acc = 0.0
    for ((a, b), w) in weights.pair_weights
        val_a = _shape_value(core_shape_values, manager, a, octad_id)
        val_b = _shape_value(core_shape_values, manager, b, octad_id)
        # If either is still nothing after the lookup path, drift = 0
        # (absent-pair convention).
        if val_a === nothing || val_b === nothing
            continue
        end
        d = _pair_drift(a, val_a, b, val_b, manager, octad_id)
        acc += w * d
    end
    acc
end

function _shape_value(core_values::Dict{Symbol, Any},
                      manager::Manager,
                      shape::Symbol,
                      octad_id)
    if haskey(core_values, shape)
        return core_values[shape]
    elseif haskey(manager.peers, shape)
        peer = manager.peers[shape]
        # Peer data is fetched via peer-shape-specific accessor.
        # For VectorPeer, that's get_embedding.
        return _peer_value(peer, octad_id)
    else
        return nothing
    end
end

# Duck-typed peer value retrieval. Each peer type provides a `_peer_value`
# specialisation at the call site via method dispatch or via this path.
function _peer_value(peer, octad_id)
    # Duck-typed peer storage access. Each peer type carries its shape's
    # values in a named Dict field; we check the known ones.
    if hasfield(typeof(peer), :embeddings)
        return get(peer.embeddings, octad_id, nothing)
    elseif hasfield(typeof(peer), :documents)
        return get(peer.documents, octad_id, nothing)
    end
    error("FederationManager: don't know how to extract value from peer type $(typeof(peer))")
end

function _pair_drift(a::Symbol, val_a, b::Symbol, val_b,
                     manager::Manager, octad_id)::Float64
    # If one side is Federable (has a registered peer), ask that peer.
    if haskey(manager.peers, a)
        peer = manager.peers[a]
        # The peer computes d_{a, b}(val_a, val_b). Peer expects
        # `drift_against(peer, id, other_shape, other_value)` — but we
        # already have val_a locally, so delegate to local Metrics.
        # The peer API is primarily for NETWORKED federation where the
        # peer holds val_a; in-process we can shortcut.
        return _local_drift(a, val_a, b, val_b)
    elseif haskey(manager.peers, b)
        return _local_drift(a, val_a, b, val_b)
    else
        return _local_drift(a, val_a, b, val_b)
    end
end

function _local_drift(a::Symbol, val_a, b::Symbol, val_b)::Float64
    # Dispatch to Metrics.drift, which handles pair ordering and
    # absent-pair convention. Resolved at runtime via Main namespace
    # (research-scaffold flat-include layout — not a package).
    Metrics.drift(a, val_a, b, val_b)
end

end # module
