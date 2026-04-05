# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test_seams.jl — seam-fix verification (post-Phase-3 audit).
#
# Validates the fixes applied after docs/SEAMS.adoc audit:
#   - register_peer! rejects Core shapes at runtime (Seam #7 equivalent)
#   - is_fresh takes a PeerAttestation struct (Seam #2)
#   - peer_attestation_info returns PeerAttestation (Seam #1)

using Test

include(joinpath(@__DIR__, "..", "impl", "drift", "Metrics.jl"))
include(joinpath(@__DIR__, "..", "impl", "VerisimCore.jl"))
include(joinpath(@__DIR__, "..", "impl", "peers", "VectorPeer.jl"))
include(joinpath(@__DIR__, "..", "impl", "FederationManager.jl"))

using .VerisimCore
using .Metrics
using .VectorPeerMod
using .FederationManager

@testset "Seam fixes" begin

    @testset "register_peer! rejects Core shapes" begin
        mgr = Manager()
        peer = VectorPeer()

        # Core shapes: registering as Federable is a category error.
        @test_throws ErrorException register_peer!(mgr, :semantic, peer)
        @test_throws ErrorException register_peer!(mgr, :temporal, peer)
        @test_throws ErrorException register_peer!(mgr, :provenance, peer)

        # Federable shapes: accepted.
        register_peer!(mgr, :vector, peer)
        @test :vector in registered_shapes(mgr)

        # Conditional shape (Graph): accepted (experiment-level decision
        # to require cross-entity-claim gating at runtime, not here).
        peer2 = VectorPeer()
        register_peer!(mgr, :graph, peer2)
        @test :graph in registered_shapes(mgr)

        # Duplicate registration rejected.
        @test_throws ErrorException register_peer!(mgr, :vector, peer)
    end

    @testset "is_fresh takes PeerAttestation struct" begin
        # Build a PeerAttestation manually.
        now = VerisimCore.Timestamp(1_000_000_000)
        fresh_ts = VerisimCore.Timestamp(now.epoch_nanos - 500_000_000)
        stale_ts = VerisimCore.Timestamp(now.epoch_nanos - 10_000_000_000)

        sig = VerisimCore.Signature(UInt8[1,2,3], UInt8[4,5,6])

        fresh_attest = PeerAttestation(
            UInt8[1,2,3], sig, fresh_ts, Int64(1_000_000_000)  # 1s window
        )
        stale_attest = PeerAttestation(
            UInt8[1,2,3], sig, stale_ts, Int64(1_000_000_000)
        )

        @test is_fresh(now, fresh_attest) == true
        @test is_fresh(now, stale_attest) == false

        # Future-dated attestation rejected.
        future_ts = VerisimCore.Timestamp(now.epoch_nanos + 500_000_000)
        future_attest = PeerAttestation(
            UInt8[1,2,3], sig, future_ts, Int64(1_000_000_000)
        )
        @test is_fresh(now, future_attest) == false
    end

    @testset "peer_attestation_info returns PeerAttestation" begin
        peer = VectorPeer()
        put_embedding!(peer, OctadId(fill(0x50, 16)),
                       hash_embedding(UInt8[0xAA, 0xBB], peer.dim))

        now = VerisimCore.Timestamp(Int64(time_ns()))
        # Supply a placeholder signing function matching VerisimCore's.
        make_sig = VerisimCore.placeholder_sign
        attest = peer_attestation_info(peer, now, make_sig)

        @test attest isa PeerAttestation
        @test attest.public_key_id == peer.key_id
        @test attest.attest_timestamp === now
        @test attest.freshness_window_ns == peer.freshness_window_ns

        # Round-trip: attest should be fresh NOW.
        @test is_fresh(now, attest) == true
    end

    @testset "Classification constants match Phase 1 resolution" begin
        @test CORE_SHAPES == Set([:semantic, :temporal, :provenance])
        @test FEDERABLE_SHAPES == Set([:vector, :tensor, :document, :spatial])
        @test CONDITIONAL_SHAPES == Set([:graph])

        # Every octad shape is in exactly one set.
        all_shapes = union(CORE_SHAPES, FEDERABLE_SHAPES, CONDITIONAL_SHAPES)
        @test length(all_shapes) == 8
        @test isempty(intersect(CORE_SHAPES, FEDERABLE_SHAPES))
        @test isempty(intersect(CORE_SHAPES, CONDITIONAL_SHAPES))
        @test isempty(intersect(FEDERABLE_SHAPES, CONDITIONAL_SHAPES))
    end

end
