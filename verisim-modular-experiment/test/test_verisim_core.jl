# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test_verisim_core.jl — Core-only smoke tests.
#
# Validates:
#   - Store creation + empty-store behavior
#   - enrich! atomicity (both Temporal and Provenance written on Semantic write)
#   - Identity Persistence (inv:persist): id stable across mutations
#   - Hash chain integrity in Provenance
#   - Attestation round-trip (attest → verify_attest)
#   - Freshness window rejection (stale attestation fails)

using Test

include(joinpath(@__DIR__, "..", "impl", "Crypto.jl"))
include(joinpath(@__DIR__, "..", "impl", "VerisimCore.jl"))
using .Crypto
using .VerisimCore

# Helper: make a synthetic 16-byte OctadId.
make_id(byte::UInt8) = OctadId(fill(byte, 16))

# Helper: make a synthetic SemanticBlob.
make_blob(tag::String) = SemanticBlob(
    ["http://verisim.test/#$tag"],
    collect(codeunits("payload-$tag")),
)

@testset "VerisimCore — Core-only smoke tests" begin

    @testset "empty store" begin
        store = Store()
        @test get_core(store, make_id(0x01)) === nothing
    end

    @testset "enrich! creates octad and writes to both P and R" begin
        store = Store()
        id = make_id(0x02)
        blob = make_blob("alpha")

        octad = enrich!(store, id, :semantic, blob, "alice")

        @test octad.id == id
        @test octad.semantic !== nothing
        @test octad.semantic.type_uris == ["http://verisim.test/#alpha"]

        # def:enrichment invariant: both Temporal AND Provenance were written.
        @test octad.temporal !== nothing
        @test length(octad.temporal.leaves) == 1

        @test octad.provenance !== nothing
        @test length(octad.provenance.entries) == 1

        entry = octad.provenance.entries[1]
        @test entry.actor == "alice"
        @test isempty(entry.prev_hash)  # first entry has no predecessor
        @test length(entry.this_hash) == 32  # SHA-256
    end

    @testset "Identity Persistence (inv:persist): id stable across mutations" begin
        store = Store()
        id = make_id(0x03)

        enrich!(store, id, :semantic, make_blob("v1"), "alice")
        enrich!(store, id, :semantic, make_blob("v2"), "bob")
        enrich!(store, id, :semantic, make_blob("v3"), "alice")

        octad = get_core(store, id)
        @test octad !== nothing
        @test octad.id == id  # id stable
        @test octad.semantic.type_uris == ["http://verisim.test/#v3"]  # latest

        # Each mutation recorded in BOTH Temporal and Provenance.
        @test length(octad.temporal.leaves) == 3
        @test length(octad.provenance.entries) == 3

        # Temporal strictly monotonic.
        ts = octad.temporal.leaves
        @test ts[1] < ts[2] < ts[3]
    end

    @testset "Provenance hash chain integrity" begin
        store = Store()
        id = make_id(0x04)

        enrich!(store, id, :semantic, make_blob("e1"), "alice")
        enrich!(store, id, :semantic, make_blob("e2"), "bob")
        enrich!(store, id, :semantic, make_blob("e3"), "alice")

        octad = get_core(store, id)
        entries = octad.provenance.entries

        @test entries[1].prev_hash == UInt8[]
        @test entries[2].prev_hash == entries[1].this_hash
        @test entries[3].prev_hash == entries[2].this_hash
    end

    @testset "attestation round-trip" begin
        store = Store()
        id = make_id(0x05)
        enrich!(store, id, :semantic, make_blob("beta"), "carol")

        result = attest(store, id)
        @test result !== nothing
        octad, sig, t = result

        @test verify_attest(store, octad, sig, t)
    end

    @testset "freshness window rejects stale attestation" begin
        # Use tiny freshness window so any real delay will cause rejection
        # of an artificially-aged timestamp.
        store = Store(freshness_window_ns = 1_000)  # 1 microsecond
        id = make_id(0x06)
        enrich!(store, id, :semantic, make_blob("gamma"), "dave")

        result = attest(store, id)
        @test result !== nothing
        octad, sig, t_fresh = result

        # Synthesize an artificially-old timestamp (1 hour ago).
        t_stale = VerisimCore.Timestamp(t_fresh.epoch_nanos - 3_600_000_000_000)
        @test !verify_attest(store, octad, sig, t_stale)
    end

    @testset "attest on missing octad returns nothing" begin
        store = Store()
        @test attest(store, make_id(0xFF)) === nothing
    end

end
