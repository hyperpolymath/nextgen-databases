# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VerisimCore.jl — slim identity-core sibling to main verisimdb.
#
# Ships a 3-shape core (Semantic, Temporal, Provenance) + optional
# Federable peer contracts, for clients that need identity + audit
# trail without the full octad. Promoted from verisim-modular-experiment
# after Path B runtime confirmation (145/145 assertions).
#
# See README.adoc for design rationale and when to adopt this vs. the
# full verisimdb octad.

module VerisimCore

# Load order matters — leaf modules first, then modules that depend on them.
include("Crypto.jl")              # uses Sodium
include("drift/Metrics.jl")       # uses SHA (standalone)
include("Core.jl")                # uses Crypto
include("Federation.jl")          # uses Metrics (via .Federation internals)
include("peers/VectorPeer.jl")    # uses Core, Crypto, Metrics, Federation
include("peers/DocumentPeer.jl")  # uses Core, Crypto, Metrics, Federation
include("vcl/Query.jl")           # standalone
include("vcl/Prover.jl")          # uses Core, Federation, VCLQuery
include("vcl/Parser.jl")          # uses Core, Federation, VCLQuery

# Re-export top-level identifiers users typically need.
using .Core: OctadId, Timestamp, Signature, SemanticBlob,
             ProvenanceEntry, ProvenanceChain, TemporalHistory,
             CoreOctad, Store,
             get_core, enrich!, attest, verify_attest, now_ts,
             ed25519_sign, ed25519_verify
using .Crypto: Ed25519KeyPair, generate_keypair, sign_detached, verify_detached
using .Metrics: cosine_distance, hash_embedding, d_SV, d_VD, d_SD, drift
using .Federation: DriftWeights, Manager, PeerAttestation,
                   renormalise, register_peer!, registered_shapes,
                   is_fresh, aggregate_drift,
                   CORE_SHAPES, FEDERABLE_SHAPES, CONDITIONAL_SHAPES
using .VectorPeers: VectorPeer, put_embedding!, get_embedding, public_key,
                    drift_against, coherence_proj, apply_lww!,
                    peer_shape, peer_attestation_info, verify_peer_attestation
using .DocumentPeers: DocumentPeer, put_document!, get_document, public_key_doc,
                      drift_against_doc, coherence_proj_doc, apply_lww_doc!,
                      peer_shape_doc, peer_attestation_info_doc
using .VCLQuery: ProofClause, ProofIntegrity, ProofConsistency, ProofFreshness,
                 ProofVerdict, VerdictPass, VerdictFail
using .VCLProver: prove
using .VCLParser: parse_vcl

export OctadId, Timestamp, Signature, SemanticBlob,
       ProvenanceEntry, ProvenanceChain, TemporalHistory,
       CoreOctad, Store,
       get_core, enrich!, attest, verify_attest, now_ts,
       ed25519_sign, ed25519_verify,
       Ed25519KeyPair, generate_keypair, sign_detached, verify_detached,
       cosine_distance, hash_embedding, d_SV, d_VD, d_SD, drift,
       DriftWeights, Manager, PeerAttestation,
       renormalise, register_peer!, registered_shapes,
       is_fresh, aggregate_drift,
       CORE_SHAPES, FEDERABLE_SHAPES, CONDITIONAL_SHAPES,
       VectorPeer, put_embedding!, get_embedding, public_key,
       drift_against, coherence_proj, apply_lww!,
       peer_shape, peer_attestation_info, verify_peer_attestation,
       DocumentPeer, put_document!, get_document, public_key_doc,
       drift_against_doc, coherence_proj_doc, apply_lww_doc!,
       peer_shape_doc, peer_attestation_info_doc,
       ProofClause, ProofIntegrity, ProofConsistency, ProofFreshness,
       ProofVerdict, VerdictPass, VerdictFail,
       prove, parse_vcl

end # module
