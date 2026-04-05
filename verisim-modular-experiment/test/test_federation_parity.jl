# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test_federation_parity.jl — THE CRITICAL PHASE 3 GATE.
#
# Validates the central hypothesis of Path B:
#
#   "Aggregate drift computed over {Core + Federable peers} must equal
#    aggregate drift computed over a monolithic store holding the same
#    shape values for the same octad."
#
# If this holds, VCL PROOF CONSISTENCY claims compose soundly across
# the Core/Federable boundary — Path B is runtime-confirmed.
#
# The test also exercises the reduced-scope renormalisation path:
# when a Federable shape is entirely absent at store level, aggregate
# drift over renormalised weights gives a coherent result.

using Test

# Ordering matters: Metrics is used by VectorPeer and FederationManager.
include(joinpath(@__DIR__, "..", "impl", "drift", "Metrics.jl"))
include(joinpath(@__DIR__, "..", "impl", "VerisimCore.jl"))
include(joinpath(@__DIR__, "..", "impl", "peers", "VectorPeer.jl"))
include(joinpath(@__DIR__, "..", "impl", "FederationManager.jl"))

using .VerisimCore
using .Metrics
using .VectorPeerMod
using .FederationManager

# -----------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------

make_id(byte::UInt8) = OctadId(fill(byte, 16))

make_blob(tag::String) = SemanticBlob(
    ["http://verisim.test/#$tag"],
    collect(codeunits("payload-$tag")),
)

"Deterministic embedding for a given tag, for reproducibility."
function make_embedding(tag::String, dim::Int = 384)::Vector{Float32}
    hash_embedding(collect(codeunits("embedding-$tag")), dim)
end

# -----------------------------------------------------------------------
# Monolithic reference: same aggregate_drift logic but all values inline.
# -----------------------------------------------------------------------

"""
Reference implementation: compute aggregate drift given all shape
values inline (no federation, no peers). This is the ground-truth
the federated computation must match.
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

@testset "Federation parity — Path B critical gate" begin

    @testset "Clause 1: renormalise preserves Σ=1 over present pairs" begin
        # Full weights over 3 pairs summing to 1.
        w = DriftWeights(
            (:semantic, :vector) => 0.5,
            (:graph, :document)  => 0.3,
            (:vector, :document) => 0.2,
        )

        # Present: just {:semantic, :vector} — keeps only (S,V) pair.
        r = renormalise([:semantic, :vector], w)
        @test sum(values(r.pair_weights)) ≈ 1.0
        @test length(r.pair_weights) == 1
        @test haskey(r.pair_weights, (:semantic, :vector))
        @test r.pair_weights[(:semantic, :vector)] == 1.0

        # Present: {:semantic, :vector, :document} — keeps (S,V) and (V,D).
        r2 = renormalise([:semantic, :vector, :document], w)
        @test sum(values(r2.pair_weights)) ≈ 1.0
        @test length(r2.pair_weights) == 2
        # Original 0.5 and 0.2 renormalise to 5/7 and 2/7.
        @test r2.pair_weights[(:semantic, :vector)] ≈ 5/7
        @test r2.pair_weights[(:document, :vector)] ≈ 2/7

        # Present: {} → empty kept set, aggregate drift structurally 0.
        r3 = renormalise(Symbol[], w)
        @test isempty(r3.pair_weights)
    end

    @testset "Parity: federated aggregate_drift == monolithic aggregate_drift" begin
        # Both runs hold the SAME Semantic blob and Vector embedding
        # for the same octad. The federated run routes Vector through
        # a VectorPeer; the monolithic run holds it inline.

        id = make_id(0x10)
        blob = make_blob("parity")
        emb = make_embedding("parity")

        weights = DriftWeights((:semantic, :vector) => 1.0)

        # --- Monolithic ---
        mono_values = Dict{Symbol, Any}(
            :semantic => blob,
            :vector   => emb,
        )
        mono_result = monolithic_aggregate_drift(mono_values, weights)

        # --- Federated: Core holds Semantic, VectorPeer holds Vector ---
        core_store = Store()
        enrich!(core_store, id, :semantic, blob, "alice")

        peer = VectorPeer()
        put_embedding!(peer, id, emb)

        manager = Manager()
        register_peer!(manager, :vector, peer)

        core_octad = get_core(core_store, id)
        core_values = Dict{Symbol, Any}(:semantic => core_octad.semantic)

        fed_result = aggregate_drift(core_values, manager, id, weights)

        @test mono_result ≈ fed_result
        @test mono_result > 0  # sanity: unrelated tag strings drift nonzero
    end

    @testset "Parity across multiple octads" begin
        weights = DriftWeights((:semantic, :vector) => 1.0)

        core_store = Store()
        peer = VectorPeer()
        manager = Manager()
        register_peer!(manager, :vector, peer)

        for i in 1:5
            tag = "oct$i"
            id = make_id(UInt8(0x20 + i))
            blob = make_blob(tag)
            emb = make_embedding(tag)

            enrich!(core_store, id, :semantic, blob, "alice")
            put_embedding!(peer, id, emb)

            # Monolithic reference.
            mono_values = Dict{Symbol, Any}(:semantic => blob, :vector => emb)
            mono_result = monolithic_aggregate_drift(mono_values, weights)

            # Federated.
            octad = get_core(core_store, id)
            fed_values = Dict{Symbol, Any}(:semantic => octad.semantic)
            fed_result = aggregate_drift(fed_values, manager, id, weights)

            @test mono_result ≈ fed_result
        end
    end

    @testset "Reduced scope: Vector absent → drift vacuous over (S,V)" begin
        # Core holds Semantic. No VectorPeer registered.
        # Claim: aggregate drift over renormalised weights is 0
        # (because the only remaining pair has no Vector to pair with).

        id = make_id(0x30)
        blob = make_blob("reduced")

        core_store = Store()
        enrich!(core_store, id, :semantic, blob, "alice")

        manager = Manager()  # empty — no peers

        # Full weights (single pair).
        weights = DriftWeights((:semantic, :vector) => 1.0)

        # What shapes are PRESENT? Only Semantic (Core) — Vector is
        # absent at store level (no peer, no Core Vector).
        present = [:semantic]
        renormed = renormalise(present, weights)

        # After renormalisation keeping only pairs where BOTH present:
        # (S,V) is dropped because V is absent → empty weight map.
        @test isempty(renormed.pair_weights)

        core_octad = get_core(core_store, id)
        core_values = Dict{Symbol, Any}(:semantic => core_octad.semantic)
        result = aggregate_drift(core_values, manager, id, renormed)

        @test result == 0.0
    end

    @testset "Reduced scope: Vector absent, (S,V) still in unreduced weights" begin
        # Same as above but we DON'T renormalise — use the un-renormalised
        # weights directly. Absent-pair convention (d(⊥,·)=0) should kick
        # in and give 0 drift. This tests that Clause 1 renormalisation
        # is OPTIONAL for soundness when using absent-pair convention —
        # renormalisation is needed when interpreting thresholds, not for
        # bare drift values.

        id = make_id(0x31)
        blob = make_blob("absent-vector")
        core_store = Store()
        enrich!(core_store, id, :semantic, blob, "alice")
        manager = Manager()

        weights = DriftWeights((:semantic, :vector) => 1.0)
        core_values = Dict{Symbol, Any}(:semantic => get_core(core_store, id).semantic)
        result = aggregate_drift(core_values, manager, id, weights)

        # d(semantic, ⊥) = 0 by convention → aggregate = 1.0 * 0 = 0.
        @test result == 0.0
    end

    @testset "Clause 5: LWW acceptor rejects stale writes" begin
        peer = VectorPeer()
        id = make_id(0x40)
        emb_v1 = make_embedding("v1")
        emb_v2 = make_embedding("v2")

        bytes_v1 = reinterpret(UInt8, emb_v1) |> collect
        bytes_v2 = reinterpret(UInt8, emb_v2) |> collect

        t1 = VerisimCore.Timestamp(1000)
        t2 = VerisimCore.Timestamp(2000)
        t_stale = VerisimCore.Timestamp(500)  # before t1

        @test apply_lww!(peer, id, t1, bytes_v1) == true
        @test apply_lww!(peer, id, t_stale, bytes_v2) == false
        # Embedding should still be v1.
        @test get_embedding(peer, id) == emb_v1

        # Newer write accepted.
        @test apply_lww!(peer, id, t2, bytes_v2) == true
        @test get_embedding(peer, id) == emb_v2
    end

end
