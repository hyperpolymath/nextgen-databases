# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test_seams.jl — seam-fix verification (post-Phase-3 audit).
#
# Validates the fixes applied after docs/SEAMS.adoc audit:
#   - register_peer! rejects Core shapes at runtime (Seam #7 equivalent)
#   - is_fresh takes a PeerAttestation struct (Seam #2)
#   - peer_attestation_info returns PeerAttestation (Seam #1)

using Test

include(joinpath(@__DIR__, "..", "impl", "Crypto.jl"))
include(joinpath(@__DIR__, "..", "impl", "drift", "Metrics.jl"))
include(joinpath(@__DIR__, "..", "impl", "VerisimCore.jl"))
include(joinpath(@__DIR__, "..", "impl", "peers", "VectorPeer.jl"))
include(joinpath(@__DIR__, "..", "impl", "FederationManager.jl"))

using .Crypto
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
        # Build a PeerAttestation with real-length Ed25519 values.
        now = VerisimCore.Timestamp(1_000_000_000)
        fresh_ts = VerisimCore.Timestamp(now.epoch_nanos - 500_000_000)
        stale_ts = VerisimCore.Timestamp(now.epoch_nanos - 10_000_000_000)

        pk  = zeros(UInt8, 32)  # dummy Ed25519 pubkey (is_fresh doesn't verify)
        sigb = zeros(UInt8, 64)
        sig = VerisimCore.Signature(pk, sigb)

        fresh_attest = PeerAttestation(pk, sig, fresh_ts, Int64(1_000_000_000))
        stale_attest = PeerAttestation(pk, sig, stale_ts, Int64(1_000_000_000))

        @test is_fresh(now, fresh_attest) == true
        @test is_fresh(now, stale_attest) == false

        # Future-dated attestation rejected.
        future_ts = VerisimCore.Timestamp(now.epoch_nanos + 500_000_000)
        future_attest = PeerAttestation(pk, sig, future_ts, Int64(1_000_000_000))
        @test is_fresh(now, future_attest) == false
    end

    @testset "peer_attestation_info returns PeerAttestation (Ed25519)" begin
        peer = VectorPeer()
        put_embedding!(peer, OctadId(fill(0x50, 16)),
                       hash_embedding(UInt8[0xAA, 0xBB], peer.dim))

        now = VerisimCore.Timestamp(Int64(time_ns()))
        attest = peer_attestation_info(peer, now)

        @test attest isa PeerAttestation
        @test attest.public_key_id == public_key(peer)
        @test length(attest.public_key_id) == 32  # Ed25519 pubkey
        @test length(attest.latest_attest.sig_bytes) == 64  # Ed25519 sig
        @test attest.attest_timestamp === now
        @test attest.freshness_window_ns == peer.freshness_window_ns

        # Round-trip: attest should be fresh NOW.
        @test is_fresh(now, attest) == true
    end

    @testset "Ed25519 round-trip via VerisimCore" begin
        # End-to-end: fresh Store generates real Ed25519 keypair,
        # enrichment produces a real Ed25519-signed ProvenanceEntry,
        # verify_attest validates the signature cryptographically.
        store = Store()
        id = OctadId(fill(0x99, 16))
        blob = SemanticBlob(["http://verisim.test/#ed25519"],
                            collect(codeunits("crypto-payload")))

        enrich!(store, id, :semantic, blob, "alice")
        octad = get_core(store, id)

        # ProvenanceEntry's signature must be real Ed25519 (64 bytes).
        entry = octad.provenance.entries[1]
        @test length(entry.signature.key_id)   == 32  # pubkey
        @test length(entry.signature.sig_bytes) == 64  # signature

        # Direct verify: VerisimCore.ed25519_verify over this_hash.
        @test VerisimCore.ed25519_verify(entry.signature, entry.this_hash)

        # Tamper: a different hash must fail verification.
        bad_hash = copy(entry.this_hash)
        bad_hash[1] ⊻= 0xFF
        @test !VerisimCore.ed25519_verify(entry.signature, bad_hash)

        # attest → verify_attest round-trip.
        result = attest(store, id)
        @test result !== nothing
        octad_snap, sig, t = result
        @test verify_attest(store, octad_snap, sig, t)

        # Tampered signature fails verify_attest.
        tampered = VerisimCore.Signature(sig.key_id, vcat(sig.sig_bytes[2:end], UInt8[0x00]))
        @test !verify_attest(store, octad_snap, tampered, t)
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
