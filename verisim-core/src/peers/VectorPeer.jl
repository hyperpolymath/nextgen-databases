# SPDX-License-Identifier: PMPL-1.0-or-later
#
# peers/VectorPeer.jl — the first Federable shape peer.
#
# Implements the three per-shape interfaces from
# src/Abi/FederationContract.idr:
#   - DriftProjector      (Clause 2)
#   - CoherenceProjector  (Clause 4)
#   - LWWAcceptor         (Clause 5)
# Plus peer_attestation and peer_shape metadata.
#
# Backing store: Dict{OctadId, Vector{Float32}} (embeddings).
# LWW: Dict{OctadId, Timestamp} (last Core-supplied write timestamp per octad).

module VectorPeers

import ..Core
import ..Crypto
import ..Metrics
import ..Federation

# VerisimCore sits alongside us; we receive its types (OctadId, Timestamp,
# Signature) as arguments rather than importing to avoid ordering games
# in a research scaffold. Duck-typed fields: .bytes, .epoch_nanos.

using SHA

export VectorPeer,
       put_embedding!, get_embedding, public_key,
       drift_against, coherence_proj, apply_lww!,
       peer_shape, peer_attestation_info, verify_peer_attestation

"""
Federable Vector peer. Holds its own Ed25519 keypair for attestations.
"""
struct VectorPeer
    embeddings::Dict{Any, Vector{Float32}}          # key: OctadId
    lww_stamps::Dict{Any, Any}                       # key: OctadId, val: Timestamp
    keypair::Any                                     # Crypto.Ed25519KeyPair
    freshness_window_ns::Int64
    dim::Int
end

VectorPeer(; dim::Int = 384,
             freshness_window_ns::Int64 = Int64(60_000_000_000)) = VectorPeer(
    Dict{Any, Vector{Float32}}(),
    Dict{Any, Any}(),
    Crypto.generate_keypair(),
    freshness_window_ns,
    dim,
)

"Peer's 32-byte public key, usable as its identity."
public_key(peer::VectorPeer) = copy(peer.keypair.pk)

peer_shape(::VectorPeer) = :vector

"Test-helper: seed an embedding directly (bypasses LWW)."
function put_embedding!(peer::VectorPeer, id, emb::Vector{Float32})
    length(emb) == peer.dim || throw(DimensionMismatch(
        "VectorPeer expects dim $(peer.dim), got $(length(emb))"))
    peer.embeddings[id] = emb
    peer
end

"Query-side: return peer's stored embedding for `id`, or nothing."
get_embedding(peer::VectorPeer, id) = get(peer.embeddings, id, nothing)

# -----------------------------------------------------------------------
# Clause 2: DriftProjector
# -----------------------------------------------------------------------

"""
    drift_against(peer, octad_id, other_shape, other_value) -> Union{Float64, Nothing}

Compute d_{:vector, other_shape}(peer_embedding, other_value) for the
octad identified by `octad_id`. Returns `nothing` if the peer does not
hold this octad (per-octad absence).

Design note: the Idris2 ABI signature is `driftAgainst : OctadId -> Shape
-> m (Either String Double)` — the peer is told the other shape but not
given its value. In a networked federation, the peer would either pull
from Core or Core would include the other value in the request. The
Julia impl passes `other_value` inline for directness. This is a
minor deviation from the Idris2 ABI that should be reconciled — see
docs/FOLDBACK.adoc TODO list.
"""
function drift_against(peer::VectorPeer, octad_id,
                       other_shape::Symbol, other_value)
    emb = get_embedding(peer, octad_id)
    emb === nothing && return nothing
    other_value === nothing && return 0.0  # absent-pair convention

    # Flat-include layout — Metrics resolved via Main namespace.
    Metrics.drift(:vector, emb, other_shape, other_value)
end

# -----------------------------------------------------------------------
# Clause 4: CoherenceProjector
# -----------------------------------------------------------------------

"""
    coherence_proj(peer, octad_id, core_shape) -> Union{Vector{UInt8}, Nothing}

Expose byte projection of this peer's data for coherence-constraint
evaluation with a Core shape. For Vector, the natural projection is
the embedding bytes themselves (pretty-printed via Float32 IEEE754
encoding).

Phase 3 only wires the Semantic coherence target (used by d_SV).
"""
function coherence_proj(peer::VectorPeer, octad_id, core_shape::Symbol)
    emb = get_embedding(peer, octad_id)
    emb === nothing && return nothing
    if core_shape == :semantic
        # Return IEEE754 byte encoding of the embedding.
        return reinterpret(UInt8, emb) |> collect
    end
    error("VectorPeer.coherence_proj: core_shape :$core_shape not wired " *
          "in Phase 3 (only :semantic is).")
end

# -----------------------------------------------------------------------
# Clause 5: LWWAcceptor
# -----------------------------------------------------------------------

"""
    apply_lww!(peer, octad_id, core_ts, payload) -> Bool

Accept a write under Core-provided Temporal LWW ordering. Returns
true iff accepted (core_ts > local last-write ts), false otherwise.

The `payload` is expected to be an embedding (Vector{Float32}) encoded
as bytes. Phase 3 decodes and stores it.
"""
function apply_lww!(peer::VectorPeer, octad_id, core_ts, payload::Vector{UInt8})::Bool
    local_ts = get(peer.lww_stamps, octad_id, nothing)
    if local_ts !== nothing && core_ts.epoch_nanos <= local_ts.epoch_nanos
        return false
    end
    # Decode payload as Vector{Float32} (expects peer.dim * 4 bytes).
    expected_bytes = peer.dim * 4
    length(payload) == expected_bytes || return false
    emb = reinterpret(Float32, payload) |> collect
    peer.embeddings[octad_id] = emb
    peer.lww_stamps[octad_id] = core_ts
    true
end

# -----------------------------------------------------------------------
# Attestation surface (Clause 3 support)
# -----------------------------------------------------------------------

"""
    peer_attestation_info(peer, now_ts) -> PeerAttestation

Return the peer's attestation metadata (mirrors Idris2 `PeerAttestation`
record). Signs a state summary of the peer's current embedding keys
plus the current timestamp with the peer's own Ed25519 keypair.
"""
function peer_attestation_info(peer::VectorPeer, now_ts)
    # Signing target: current state summary.
    state_summary = sha256(vcat(
        reduce(vcat, (collect(codeunits(string(k))) for k in keys(peer.embeddings)); init = UInt8[]),
        reinterpret(UInt8, [now_ts.epoch_nanos]),
    ))
    sig_bytes = Crypto.sign_detached(peer.keypair, state_summary)
    sig = Core.Signature(public_key(peer), sig_bytes)
    Federation.PeerAttestation(
        public_key(peer),
        sig,
        now_ts,
        peer.freshness_window_ns,
    )
end

"""
    verify_peer_attestation(peer_attest, state_summary) -> Bool

Verify a peer attestation's signature over a given state summary.
"""
function verify_peer_attestation(peer_attest, state_summary::Vector{UInt8})::Bool
    Crypto.verify_detached(
        peer_attest.public_key_id,
        peer_attest.latest_attest.sig_bytes,
        state_summary,
    )
end

end # module
