# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test_noninterference.jl — multi-peer (N≥2) non-interference.
#
# Validates the second half of the central experiment hypothesis:
# federating shape E1 does not silently weaken VCL claims about
# shape E2 or about Core. Phase 3 parity tests used a single peer;
# this suite registers TWO peers simultaneously (Vector + Document)
# and exercises all three pair combinations: (S,V), (S,D), (V,D).

using Test

include(joinpath(@__DIR__, "..", "impl", "Crypto.jl"))
include(joinpath(@__DIR__, "..", "impl", "drift", "Metrics.jl"))
include(joinpath(@__DIR__, "..", "impl", "VerisimCore.jl"))
include(joinpath(@__DIR__, "..", "impl", "peers", "VectorPeer.jl"))
include(joinpath(@__DIR__, "..", "impl", "peers", "DocumentPeer.jl"))
include(joinpath(@__DIR__, "..", "impl", "FederationManager.jl"))

using .Crypto
using .VerisimCore
using .Metrics
using .VectorPeerMod
using .DocumentPeerMod
using .FederationManager

# -----------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------

make_id(byte::UInt8) = OctadId(fill(byte, 16))

make_blob(tag::String) = SemanticBlob(
    ["http://verisim.test/#$tag"],
    collect(codeunits("payload-$tag")),
)

make_embedding(tag::String, dim::Int = 384) = hash_embedding(
    collect(codeunits("embedding-$tag")), dim)

make_document(tag::String) = collect(codeunits("document-content-$tag-blah-blah"))

"""
Monolithic reference: compute aggregate drift with all shape values inline.
"""
function monolithic_aggregate_drift(shape_values::Dict{Symbol, Any},
                                    weights::DriftWeights)::Float64
    acc = 0.0
    for ((a, b), w) in weights.pair_weights
        val_a = get(shape_values, a, nothing)
        val_b = get(shape_values, b, nothing)
        (val_a === nothing || val_b === nothing) && continue
        acc += w * Metrics.drift(a, val_a, b, val_b)
    end
    acc
end

# -----------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------

@testset "Non-interference: N≥2 simultaneous Federable peers" begin

    @testset "3-way parity over (S,V), (S,D), (V,D)" begin
        # Same octad data; compare monolithic vs federated(Core + Vector + Document).
        id = make_id(0x60)
        blob = make_blob("tri")
        emb = make_embedding("tri")
        doc = make_document("tri")

        # Weights distribute across all 3 pairs, summing to 1.
        weights = DriftWeights(
            (:semantic, :vector)   => 0.4,
            (:semantic, :document) => 0.3,
            (:vector,   :document) => 0.3,
        )

        # Monolithic reference.
        mono_values = Dict{Symbol, Any}(
            :semantic => blob,
            :vector   => emb,
            :document => doc,
        )
        mono_result = monolithic_aggregate_drift(mono_values, weights)

        # Federated: Core holds Semantic, two peers hold Vector and Document.
        core_store = Store()
        enrich!(core_store, id, :semantic, blob, "alice")

        v_peer = VectorPeer()
        put_embedding!(v_peer, id, emb)

        d_peer = DocumentPeer()
        put_document!(d_peer, id, doc)

        manager = Manager()
        register_peer!(manager, :vector, v_peer)
        register_peer!(manager, :document, d_peer)

        core_values = Dict{Symbol, Any}(:semantic => get_core(core_store, id).semantic)
        fed_result = aggregate_drift(core_values, manager, id, weights)

        @test mono_result ≈ fed_result
        @test mono_result > 0
    end

    @testset "Non-interference: adding Document peer doesn't affect (S,V) drift" begin
        # Compute (S,V) drift with only Vector peer registered.
        # Then register Document peer and verify (S,V) drift is unchanged.
        id = make_id(0x61)
        blob = make_blob("ni")
        emb = make_embedding("ni")
        doc = make_document("ni")

        core_store = Store()
        enrich!(core_store, id, :semantic, blob, "alice")
        v_peer = VectorPeer()
        put_embedding!(v_peer, id, emb)

        # Single-peer manager.
        mgr_solo = Manager()
        register_peer!(mgr_solo, :vector, v_peer)

        weights_sv = DriftWeights((:semantic, :vector) => 1.0)
        core_values = Dict{Symbol, Any}(:semantic => get_core(core_store, id).semantic)
        result_solo = aggregate_drift(core_values, mgr_solo, id, weights_sv)

        # Now a second manager with both peers — compute (S,V) drift only.
        d_peer = DocumentPeer()
        put_document!(d_peer, id, doc)
        mgr_both = Manager()
        register_peer!(mgr_both, :vector, v_peer)
        register_peer!(mgr_both, :document, d_peer)

        result_both = aggregate_drift(core_values, mgr_both, id, weights_sv)

        # (S,V) drift must be identical regardless of whether Document is registered.
        @test result_solo ≈ result_both
    end

    @testset "Non-interference: Document peer's LWW writes don't affect Vector" begin
        # Write to Document peer; verify Vector peer's embedding unchanged
        # and (S,V) drift contribution stays constant.
        id = make_id(0x62)
        blob = make_blob("iso")
        emb = make_embedding("iso")
        doc_v1 = make_document("iso-v1")
        doc_v2 = make_document("iso-v2-updated")

        core_store = Store()
        enrich!(core_store, id, :semantic, blob, "alice")
        v_peer = VectorPeer()
        put_embedding!(v_peer, id, emb)
        d_peer = DocumentPeer()
        put_document!(d_peer, id, doc_v1)

        mgr = Manager()
        register_peer!(mgr, :vector, v_peer)
        register_peer!(mgr, :document, d_peer)

        core_values = Dict{Symbol, Any}(:semantic => get_core(core_store, id).semantic)
        weights_sv = DriftWeights((:semantic, :vector) => 1.0)
        sv_before = aggregate_drift(core_values, mgr, id, weights_sv)

        # Update Document via LWW.
        t_new = VerisimCore.Timestamp(Int64(time_ns()) + 1_000_000_000)
        @test apply_lww_doc!(d_peer, id, t_new, doc_v2)

        sv_after = aggregate_drift(core_values, mgr, id, weights_sv)
        @test sv_before == sv_after  # Vector wasn't touched.
        @test v_peer.embeddings[id] == emb  # Sanity.
    end

    @testset "Degradation: dropping Document peer weakens only document-involving claims" begin
        # With both peers: PROOF CONSISTENCY (drift < θ) computed over
        # all 3 pairs. Drop Document peer: renormalise weights. Claims
        # scoped to (S,V) remain identical; claims involving Document
        # become vacuous.
        id = make_id(0x63)
        blob = make_blob("deg")
        emb = make_embedding("deg")
        doc = make_document("deg")

        core_store = Store()
        enrich!(core_store, id, :semantic, blob, "alice")
        v_peer = VectorPeer()
        put_embedding!(v_peer, id, emb)
        d_peer = DocumentPeer()
        put_document!(d_peer, id, doc)

        mgr_both = Manager()
        register_peer!(mgr_both, :vector, v_peer)
        register_peer!(mgr_both, :document, d_peer)

        mgr_vonly = Manager()
        register_peer!(mgr_vonly, :vector, v_peer)

        weights_all = DriftWeights(
            (:semantic, :vector)   => 0.5,
            (:semantic, :document) => 0.25,
            (:vector,   :document) => 0.25,
        )

        core_values = Dict{Symbol, Any}(:semantic => get_core(core_store, id).semantic)

        # Full 3-way drift.
        drift_all = aggregate_drift(core_values, mgr_both, id, weights_all)

        # Drop Document: renormalise keeping only (S,V).
        present_no_doc = [:semantic, :vector]
        weights_renormed = renormalise(present_no_doc, weights_all)
        @test sum(values(weights_renormed.pair_weights)) ≈ 1.0
        @test length(weights_renormed.pair_weights) == 1

        drift_renormed = aggregate_drift(core_values, mgr_vonly, id, weights_renormed)

        # Renormalised claim is scoped differently but well-defined.
        # It equals d_SV (the only remaining pair) since weight = 1.
        expected_sv = Metrics.d_SV(blob.type_uris, blob.proof_bytes, emb)
        @test drift_renormed ≈ expected_sv
    end

    @testset "Signature attestations: per-peer Ed25519 keypairs are independent" begin
        v_peer = VectorPeer()
        d_peer = DocumentPeer()

        vk = public_key(v_peer)
        dk = public_key_doc(d_peer)

        # Peers have different keypairs.
        @test vk != dk
        @test length(vk) == 32
        @test length(dk) == 32

        # Each peer's attestation is signed with its own key.
        now = VerisimCore.Timestamp(Int64(time_ns()))
        v_attest = peer_attestation_info(v_peer, now)
        d_attest = peer_attestation_info_doc(d_peer, now)

        @test v_attest.public_key_id == vk
        @test d_attest.public_key_id == dk
        @test v_attest.public_key_id != d_attest.public_key_id
    end

end
