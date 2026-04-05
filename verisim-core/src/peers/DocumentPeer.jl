# SPDX-License-Identifier: PMPL-1.0-or-later
#
# peers/DocumentPeer.jl — second Federable shape peer.
#
# Implements DriftProjector + CoherenceProjector + LWWAcceptor for the
# Document shape. Research-prototype representation: documents stored
# as raw byte content. Real impl would use Tantivy inverted index.
#
# Used by test/test_noninterference.jl to validate multi-peer
# non-interference: federating Vector and Document simultaneously must
# not silently weaken claims about either, or about Core.

module DocumentPeers

import ..Core
import ..Crypto
import ..Metrics
import ..Federation

using SHA

export DocumentPeer,
       put_document!, get_document, public_key_doc,
       drift_against_doc, coherence_proj_doc, apply_lww_doc!,
       peer_shape_doc, peer_attestation_info_doc

struct DocumentPeer
    documents::Dict{Any, Vector{UInt8}}
    lww_stamps::Dict{Any, Any}
    keypair::Any
    freshness_window_ns::Int64
end

DocumentPeer(; freshness_window_ns::Int64 = Int64(60_000_000_000)) = DocumentPeer(
    Dict{Any, Vector{UInt8}}(),
    Dict{Any, Any}(),
    Crypto.generate_keypair(),
    freshness_window_ns,
)

peer_shape_doc(::DocumentPeer) = :document
public_key_doc(peer::DocumentPeer) = copy(peer.keypair.pk)

function put_document!(peer::DocumentPeer, id, bytes::Vector{UInt8})
    peer.documents[id] = bytes
    peer
end

get_document(peer::DocumentPeer, id) = get(peer.documents, id, nothing)

# Clause 2: DriftProjector
function drift_against_doc(peer::DocumentPeer, octad_id,
                           other_shape::Symbol, other_value)
    doc = get_document(peer, octad_id)
    doc === nothing && return nothing
    other_value === nothing && return 0.0
    Metrics.drift(:document, doc, other_shape, other_value)
end

# Clause 4: CoherenceProjector
function coherence_proj_doc(peer::DocumentPeer, octad_id, core_shape::Symbol)
    doc = get_document(peer, octad_id)
    doc === nothing && return nothing
    # For Semantic coherence, return document's hash digest.
    core_shape == :semantic && return collect(sha256(doc))
    error("DocumentPeer.coherence_proj_doc: core_shape :$core_shape " *
          "not wired (only :semantic is).")
end

# Clause 5: LWWAcceptor
function apply_lww_doc!(peer::DocumentPeer, octad_id, core_ts,
                        payload::Vector{UInt8})::Bool
    local_ts = get(peer.lww_stamps, octad_id, nothing)
    if local_ts !== nothing && core_ts.epoch_nanos <= local_ts.epoch_nanos
        return false
    end
    peer.documents[octad_id] = payload
    peer.lww_stamps[octad_id] = core_ts
    true
end

function peer_attestation_info_doc(peer::DocumentPeer, now_ts)
    state_summary = sha256(vcat(
        reduce(vcat, (collect(codeunits(string(k))) for k in keys(peer.documents)); init = UInt8[]),
        reinterpret(UInt8, [now_ts.epoch_nanos]),
    ))
    sig_bytes = Crypto.sign_detached(peer.keypair, state_summary)
    sig = Core.Signature(public_key_doc(peer), sig_bytes)
    Federation.PeerAttestation(
        public_key_doc(peer),
        sig,
        now_ts,
        peer.freshness_window_ns,
    )
end

end # module
