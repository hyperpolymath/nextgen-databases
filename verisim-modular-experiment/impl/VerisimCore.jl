# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VerisimCore.jl — Julia implementation of the identity-core ABI.
#
# Mirrors src/Abi/VerisimCore.idr. Grounded in:
#   - verisimdb/arcvix-octad-data-model.tex def:octad (identity, ⊥)
#   - inv:persist (Identity Persistence requires Temporal)
#   - def:enrichment (write primitive writes to both P and R atomically)
#   - thm:attestation (attestation freshness window)
#
# NOT production code. Research prototype — correctness > performance.
# In-memory ephemeral store, no persistence, no concurrency control.

module VerisimCore

using SHA

export OctadId, Timestamp, Signature, SemanticBlob,
       ProvenanceEntry, ProvenanceChain, TemporalHistory,
       CoreOctad, Store,
       get_core, enrich!, attest, verify_attest, now_ts

# -----------------------------------------------------------------------
# Primitive types (mirror Idris2 ABI)
# -----------------------------------------------------------------------

"128-bit octad identifier (def:octad, id ∈ UUID)."
struct OctadId
    bytes::Vector{UInt8}
    function OctadId(bytes::Vector{UInt8})
        length(bytes) == 16 || throw(ArgumentError("OctadId must be 16 bytes, got $(length(bytes))"))
        new(bytes)
    end
end

Base.:(==)(a::OctadId, b::OctadId) = a.bytes == b.bytes
Base.hash(id::OctadId, h::UInt) = hash(id.bytes, h)
Base.show(io::IO, id::OctadId) = print(io, "OctadId(", bytes2hex(id.bytes), ")")

"""
Monotonic logical timestamp, Temporal-modality-provided.
Per thm:attestation, attestations bear a timestamp t that must lie
within the freshness window. Per §7, LWW uses Temporal as total order
on writes.
"""
struct Timestamp
    epoch_nanos::Int64
end

Base.isless(a::Timestamp, b::Timestamp) = a.epoch_nanos < b.epoch_nanos
Base.:(==)(a::Timestamp, b::Timestamp) = a.epoch_nanos == b.epoch_nanos
now_ts() = Timestamp(Int64(time_ns()))

"""
Signature placeholder. TODO(Phase 3 defaults validation): replace with
Ed25519 via Nettle.jl or similar. For scaffold, using SHA-256 as a
stand-in 'signature' (signer_id || payload). This is NOT cryptographic
signing — it is a placeholder so the ABI shapes compile and test paths
work. Cryptographic fidelity is not required for Phase 3's correctness
experiment; it IS required before any production consideration.
"""
struct Signature
    key_id::Vector{UInt8}
    sig_bytes::Vector{UInt8}
end

"Semantic modality blob (def:modset, Σ_S)."
struct SemanticBlob
    type_uris::Vector{String}
    proof_bytes::Vector{UInt8}
end

"One entry in the Provenance hash chain (Σ_R)."
struct ProvenanceEntry
    prev_hash::Vector{UInt8}   # SHA-256 of previous entry
    this_hash::Vector{UInt8}   # SHA-256 of this entry
    actor::String
    timestamp::Timestamp
    signature::Signature
end

"Provenance modality (Σ_R = SHA-256 hash chain of signed events)."
mutable struct ProvenanceChain
    entries::Vector{ProvenanceEntry}
end
ProvenanceChain() = ProvenanceChain(ProvenanceEntry[])

"Temporal modality (Σ_P = Merkle-tree version history)."
mutable struct TemporalHistory
    leaves::Vector{Timestamp}
end
TemporalHistory() = TemporalHistory(Timestamp[])

"""
A Core octad holds the three store-level-required modalities.
Any may be ⊥ per-entity (`nothing` in Julia), matching def:octad.
But the store itself must implement all three for def:enrichment
and inv:persist to hold.
"""
mutable struct CoreOctad
    id::OctadId
    semantic::Union{SemanticBlob, Nothing}
    temporal::Union{TemporalHistory, Nothing}
    provenance::Union{ProvenanceChain, Nothing}
end

# -----------------------------------------------------------------------
# Store
# -----------------------------------------------------------------------

"In-memory ephemeral Core store. Dict-backed, no persistence."
struct Store
    octads::Dict{OctadId, CoreOctad}
    # For placeholder signing — real impl would hold an Ed25519 keypair
    signing_key_id::Vector{UInt8}
    # Attestation freshness window, in nanoseconds (default: 60s)
    freshness_window_ns::Int64
end

Store(; freshness_window_ns::Int64 = Int64(60_000_000_000)) = Store(
    Dict{OctadId, CoreOctad}(),
    collect(codeunits("verisim-core-test-key")),
    freshness_window_ns,
)

"""
    get_core(store, id) -> Union{CoreOctad, Nothing}

Fetch an octad's core projection. Returns `nothing` if not present.
"""
function get_core(store::Store, id::OctadId)::Union{CoreOctad, Nothing}
    get(store.octads, id, nothing)
end

# -----------------------------------------------------------------------
# Enrichment (def:enrichment) — the fundamental write primitive
# -----------------------------------------------------------------------

"""
    enrich!(store, id, shape_tag, payload, actor) -> CoreOctad

The fundamental write primitive (def:enrichment from the TeX).

    "Every enrichment appends a record to φ'(P) and φ'(R)."

Atomically:
  1. Locate or create the octad with identifier `id`.
  2. Apply `payload` to the shape identified by `shape_tag` (Semantic
     only, since Core = {S, P, R} and P/R are internally managed).
  3. Append a new Timestamp to Temporal (P).
  4. Append a signed ProvenanceEntry to Provenance (R).

This enforces Identity Persistence (inv:persist) by construction: every
mutation is recorded in both audit modalities.

Supported `shape_tag` values for Core: `:semantic`. Attempting to
enrich a non-Core shape via this entry point returns an error — Federable
shapes are written through the federation peer, not Core.
"""
function enrich!(store::Store,
                 id::OctadId,
                 shape_tag::Symbol,
                 payload::SemanticBlob,
                 actor::String)::CoreOctad
    shape_tag == :semantic || error(
        "enrich! Core only accepts :semantic shape. " *
        "Got :$shape_tag. Federable shapes write via federation peer."
    )

    octad = get!(store.octads, id) do
        CoreOctad(id, nothing, TemporalHistory(), ProvenanceChain())
    end

    # Lazy-init Core modalities if absent (per-octad ⊥ allowed, but
    # enrichment forces T and R to be present after first write).
    octad.temporal   === nothing && (octad.temporal   = TemporalHistory())
    octad.provenance === nothing && (octad.provenance = ProvenanceChain())

    # Apply Semantic enrichment.
    octad.semantic = payload

    # Enrichment-invariant: append to both P and R atomically.
    t = now_ts()
    push!(octad.temporal.leaves, t)

    prev = isempty(octad.provenance.entries) ?
           UInt8[] :
           octad.provenance.entries[end].this_hash

    # Compute this_hash over (prev_hash || actor || payload_summary || timestamp).
    to_hash = vcat(
        prev,
        collect(codeunits(actor)),
        bytes2hex_summary(payload),
        reinterpret(UInt8, [t.epoch_nanos]),
    )
    this_hash = sha256(to_hash)

    # Placeholder signature — see Signature docstring.
    sig = placeholder_sign(store.signing_key_id, this_hash)

    push!(octad.provenance.entries, ProvenanceEntry(
        prev, this_hash, actor, t, sig,
    ))

    octad
end

"Opaque summary of a SemanticBlob for hashing purposes."
function bytes2hex_summary(blob::SemanticBlob)::Vector{UInt8}
    sha256(vcat(
        collect(codeunits(join(blob.type_uris, ","))),
        blob.proof_bytes,
    ))
end

"""
    placeholder_sign(key_id, payload) -> Signature

Placeholder for Ed25519 signing. Current impl: SHA-256 of
(key_id || payload). NOT cryptographically sound. See Signature docstring.
"""
function placeholder_sign(key_id::Vector{UInt8},
                          payload::Vector{UInt8})::Signature
    sig = sha256(vcat(key_id, payload))
    Signature(key_id, sig)
end

"""
    placeholder_verify(sig, payload) -> Bool

Placeholder verification matching placeholder_sign. Recomputes the
expected SHA-256 and compares. This provides the ABI shape; real
Ed25519 verification is a Phase 4+ task.
"""
function placeholder_verify(sig::Signature, payload::Vector{UInt8})::Bool
    expected = sha256(vcat(sig.key_id, payload))
    expected == sig.sig_bytes
end

# -----------------------------------------------------------------------
# Attestation (thm:attestation)
# -----------------------------------------------------------------------

"""
    attest(store, id) -> Union{Tuple{CoreOctad, Signature, Timestamp}, Nothing}

Produce a signed attestation of the octad's current Core state.
Used both locally (for verifying own data) and when responding to
federation peers.
"""
function attest(store::Store, id::OctadId)
    octad = get_core(store, id)
    octad === nothing && return nothing
    t = now_ts()
    # Sign a digest of (id || t || semantic summary).
    sem_summary = octad.semantic === nothing ? UInt8[] : bytes2hex_summary(octad.semantic)
    payload = vcat(octad.id.bytes, reinterpret(UInt8, [t.epoch_nanos]), sem_summary)
    sig = placeholder_sign(store.signing_key_id, payload)
    (octad, sig, t)
end

"""
    verify_attest(store, octad, sig, t) -> Bool

Verify an attestation. Checks:
  1. Signature validity (placeholder — see Signature docstring).
  2. Timestamp lies within the freshness window relative to store's
     current time.
"""
function verify_attest(store::Store,
                       octad::CoreOctad,
                       sig::Signature,
                       t::Timestamp)::Bool
    # Freshness check first (cheaper).
    n = now_ts()
    age = n.epoch_nanos - t.epoch_nanos
    (age >= 0 && age <= store.freshness_window_ns) || return false

    # Recompute expected payload and verify.
    sem_summary = octad.semantic === nothing ? UInt8[] : bytes2hex_summary(octad.semantic)
    payload = vcat(octad.id.bytes, reinterpret(UInt8, [t.epoch_nanos]), sem_summary)
    placeholder_verify(sig, payload)
end

end # module
