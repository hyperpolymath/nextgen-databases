# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test_vcl.jl — VCL PROOF clause evaluation end-to-end.
#
# Exercises the four target query patterns from PHASE-3-IMPLEMENTATION-PLAN.adoc:
#   1. PROOF INTEGRITY on Core-only octad
#   2. PROOF CONSISTENCY WITH DRIFT < θ over (S,V)
#   3. PROOF CONSISTENCY with a shape absent → renormalisation
#   4. PROOF FRESHNESS WITHIN <window>
#
# Plus: string-level parsing via VCLParser.parse_vcl.

using Test

include(joinpath(@__DIR__, "..", "impl", "Crypto.jl"))
include(joinpath(@__DIR__, "..", "impl", "drift", "Metrics.jl"))
include(joinpath(@__DIR__, "..", "impl", "VerisimCore.jl"))
include(joinpath(@__DIR__, "..", "impl", "peers", "VectorPeer.jl"))
include(joinpath(@__DIR__, "..", "impl", "FederationManager.jl"))
# Tropical modules must be loaded before VCLProver
include(joinpath(@__DIR__, "..", "impl", "tropical", "TropicalMatrix.jl"))
include(joinpath(@__DIR__, "..", "impl", "tropical", "TangleGraph.jl"))
include(joinpath(@__DIR__, "..", "impl", "tropical", "TropicalDeterminant.jl"))
include(joinpath(@__DIR__, "..", "impl", "vcl", "Query.jl"))
include(joinpath(@__DIR__, "..", "impl", "vcl", "Prover.jl"))
include(joinpath(@__DIR__, "..", "impl", "vcl", "Parser.jl"))

using .Crypto
using .VerisimCore
using .Metrics
using .VectorPeerMod
using .FederationManager
using .TropicalMatrix
using .TangleGraph
using .TropicalDeterminant
using .VCLQuery
using .VCLProver
using .VCLParser

# -----------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------

make_id(byte::UInt8) = OctadId(fill(byte, 16))
make_blob(tag) = SemanticBlob(["http://verisim.test/#$tag"],
                              collect(codeunits("payload-$tag")))
make_emb(tag, dim=384) = hash_embedding(collect(codeunits("embedding-$tag")), dim)

# -----------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------

@testset "VCL PROOF clause evaluation" begin

    @testset "PROOF INTEGRITY: Core-only octad" begin
        store = Store()
        id = make_id(0x70)
        mgr = Manager()

        # Missing octad → fail.
        v1 = prove(ProofIntegrity(id), store, mgr)
        @test v1 isa VerdictFail

        # After enrichment → pass.
        enrich!(store, id, :semantic, make_blob("int"), "alice")
        v2 = prove(ProofIntegrity(id), store, mgr)
        @test v2 isa VerdictPass
        @test occursin("hash chain intact", v2.witness)
        @test occursin("1 enrichment", v2.witness)

        # After 3 enrichments.
        enrich!(store, id, :semantic, make_blob("int2"), "bob")
        enrich!(store, id, :semantic, make_blob("int3"), "alice")
        v3 = prove(ProofIntegrity(id), store, mgr)
        @test v3 isa VerdictPass
        @test occursin("3 enrichment", v3.witness)
    end

    @testset "PROOF INTEGRITY: tampered hash chain fails" begin
        store = Store()
        id = make_id(0x71)
        enrich!(store, id, :semantic, make_blob("t1"), "alice")
        enrich!(store, id, :semantic, make_blob("t2"), "bob")
        enrich!(store, id, :semantic, make_blob("t3"), "carol")

        # Tamper with the middle entry's this_hash by direct mutation.
        octad = get_core(store, id)
        octad.provenance.entries[2] = VerisimCore.ProvenanceEntry(
            octad.provenance.entries[2].prev_hash,
            zeros(UInt8, 32),  # tampered this_hash
            octad.provenance.entries[2].actor,
            octad.provenance.entries[2].timestamp,
            octad.provenance.entries[2].signature,
        )

        v = prove(ProofIntegrity(id), store, Manager())
        @test v isa VerdictFail
        @test occursin("hash chain broken", v.reason)
    end

    @testset "PROOF CONSISTENCY over (S,V) with federated Vector peer" begin
        store = Store()
        id = make_id(0x72)
        blob = make_blob("cons")
        emb = make_emb("cons")

        enrich!(store, id, :semantic, blob, "alice")
        peer = VectorPeer()
        put_embedding!(peer, id, emb)

        mgr = Manager()
        register_peer!(mgr, :vector, peer)

        weights = DriftWeights((:semantic, :vector) => 1.0)

        # Generous threshold — should pass.
        c_loose = ProofConsistency(id, [:semantic, :vector], 10.0, weights)
        @test prove(c_loose, store, mgr) isa VerdictPass

        # Strict threshold — should fail (unrelated tags drift ~1.0).
        c_tight = ProofConsistency(id, [:semantic, :vector], 0.01, weights)
        v_tight = prove(c_tight, store, mgr)
        @test v_tight isa VerdictFail
        @test occursin("aggregate drift", v_tight.reason)
    end

    @testset "PROOF CONSISTENCY with absent shape → renormalisation" begin
        # Scope declares {semantic, vector, document} but Document peer
        # not registered → renormalise weights keeping only pairs with
        # both shapes present.
        store = Store()
        id = make_id(0x73)
        enrich!(store, id, :semantic, make_blob("renorm"), "alice")
        peer = VectorPeer()
        put_embedding!(peer, id, make_emb("renorm"))

        mgr = Manager()
        register_peer!(mgr, :vector, peer)

        # Weights assume all 3 pairs.
        weights = DriftWeights(
            (:semantic, :vector)   => 0.5,
            (:semantic, :document) => 0.25,
            (:vector,   :document) => 0.25,
        )

        # Scope: only shapes actually present.
        scope_reduced = [:semantic, :vector]
        clause = ProofConsistency(id, scope_reduced, 10.0, weights)
        @test prove(clause, store, mgr) isa VerdictPass
    end

    @testset "PROOF FRESHNESS" begin
        store = Store()
        id = make_id(0x74)
        enrich!(store, id, :semantic, make_blob("fresh"), "alice")

        # 1 second window: fresh enrichment should pass.
        v_fresh = prove(ProofFreshness(id, Int64(1_000_000_000)), store, Manager())
        @test v_fresh isa VerdictPass

        # 1 nanosecond window: essentially unreachable — should fail.
        sleep(0.001)
        v_stale = prove(ProofFreshness(id, Int64(1)), store, Manager())
        @test v_stale isa VerdictFail
        @test occursin("exceeds window", v_stale.reason)
    end

    @testset "VCLParser: round-trip parsing" begin
        # INTEGRITY
        q1 = parse_vcl("PROOF INTEGRITY FOR 00112233445566778899aabbccddeeff")
        @test q1 isa ProofIntegrity
        @test q1.octad_id.bytes[1] == 0x00
        @test q1.octad_id.bytes[16] == 0xff

        # CONSISTENCY without OVER
        q2 = parse_vcl("PROOF CONSISTENCY FOR 01010101010101010101010101010101 WITH DRIFT < 0.5")
        @test q2 isa ProofConsistency
        @test q2.threshold == 0.5
        @test isempty(q2.scope)

        # CONSISTENCY with OVER
        q3 = parse_vcl("""
            PROOF CONSISTENCY FOR 02020202020202020202020202020202
            OVER {semantic, vector}
            WITH DRIFT < 0.1
        """)
        @test q3 isa ProofConsistency
        @test q3.threshold == 0.1
        @test q3.scope == [:semantic, :vector]
        @test length(q3.weights.pair_weights) == 1  # one pair (S,V)

        # FRESHNESS
        q4 = parse_vcl("PROOF FRESHNESS FOR 03030303030303030303030303030303 WITHIN 1000000000ns")
        @test q4 isa ProofFreshness
        @test q4.window_ns == 1_000_000_000
    end

    @testset "VCLParser: errors on bad input" begin
        @test_throws ErrorException parse_vcl("SELECT * FROM octads")
        @test_throws ErrorException parse_vcl("PROOF INTEGRITY")  # no FOR
        @test_throws ErrorException parse_vcl("PROOF FOO FOR 00112233445566778899aabbccddeeff")
        @test_throws ErrorException parse_vcl("PROOF INTEGRITY FOR abc")  # short hex
    end

    @testset "End-to-end: parse then prove" begin
        # Parse a string, evaluate against a live store+manager.
        store = Store()
        id_hex = "aa" ^ 16
        id = OctadId(fill(0xaa, 16))
        enrich!(store, id, :semantic, make_blob("e2e"), "alice")

        q = parse_vcl("PROOF INTEGRITY FOR $id_hex")
        v = prove(q, store, Manager())
        @test v isa VerdictPass
    end

end

# -----------------------------------------------------------------------
# ProofOptimalAssignment — tropical determinant assignment check
# -----------------------------------------------------------------------

@testset "PROOF OPTIMAL_ASSIGNMENT — tropical determinant" begin

    # Helper: encode an n×n matrix of nat costs as a proof_bytes blob
    # (little-endian uint32; 0xFFFFFFFF = PosInf)
    function encode_cost_matrix(costs::Matrix{UInt32})::Vector{UInt8}
        n = size(costs, 1)
        bytes = UInt8[]
        for row in 1:n, col in 1:n
            v = costs[row, col]
            push!(bytes, v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF)
        end
        return bytes
    end

    @testset "1×1 matrix: identity assignment" begin
        # Single agent, single task, cost 5.
        store = Store()
        id    = OctadId(fill(0xA1, 16))
        mat   = UInt32[5;;]   # 1×1 matrix with cost 5
        blob  = SemanticBlob(["http://verisim.test/#assignment"],
                             encode_cost_matrix(mat))
        enrich!(store, id, :semantic, blob, "test")

        # bound = Tropical(10): 5 ≤ 10 → PASS
        clause = ProofOptimalAssignment(id, 1, Tropical(10.0))
        v = prove(clause, store, Manager())
        @test v isa VerdictPass

        # bound = Tropical(3): 5 > 3 → FAIL
        clause2 = ProofOptimalAssignment(id, 1, Tropical(3.0))
        v2 = prove(clause2, store, Manager())
        @test v2 isa VerdictFail
    end

    @testset "2×2 matrix: optimal assignment chosen" begin
        # Cost matrix:  [1  4]   Optimal: id     → 1+6=7
        #               [3  6]            swap  → 4+3=7
        # Both have cost 7; det = 7.
        store = Store()
        id    = OctadId(fill(0xA2, 16))
        mat   = UInt32[1 4; 3 6]
        blob  = SemanticBlob(["http://verisim.test/#assignment2x2"],
                             encode_cost_matrix(mat))
        enrich!(store, id, :semantic, blob, "test")

        # Optimal cost is min(1+6, 4+3) = min(7,7) = 7
        clause = ProofOptimalAssignment(id, 2, Tropical(7.0))
        v = prove(clause, store, Manager())
        @test v isa VerdictPass

        # bound = 6: cost 7 > 6 → FAIL
        clause2 = ProofOptimalAssignment(id, 2, Tropical(6.0))
        v2 = prove(clause2, store, Manager())
        @test v2 isa VerdictFail
    end

    @testset "2×2 matrix: non-symmetric costs pick diagonal" begin
        # Cost matrix:  [1  100]   Optimal: id → 1+2=3
        #               [100  2]             swap → 100+100=200
        store = Store()
        id    = OctadId(fill(0xA3, 16))
        mat   = UInt32[1 100; 100 2]
        blob  = SemanticBlob(["http://verisim.test/#assignment2x2b"],
                             encode_cost_matrix(mat))
        enrich!(store, id, :semantic, blob, "test")

        clause = ProofOptimalAssignment(id, 2, Tropical(3.0))
        v = prove(clause, store, Manager())
        @test v isa VerdictPass
    end

    @testset "octad not found → VerdictFail" begin
        store  = Store()
        id     = OctadId(fill(0xFF, 16))
        clause = ProofOptimalAssignment(id, 2, Tropical(10.0))
        v = prove(clause, store, Manager())
        @test v isa VerdictFail
        @test occursin("not found", v.reason)
    end

    @testset "no Semantic shape → VerdictFail" begin
        store = Store()
        id    = OctadId(fill(0xA4, 16))
        # Enrich with temporal only (no semantic)
        leaf = TemporalLeaf(Timestamp(1_000_000_000), "sha256:abc")
        enrich!(store, id, :temporal, TemporalTrail([leaf]), "test")
        clause = ProofOptimalAssignment(id, 2, Tropical(10.0))
        v = prove(clause, store, Manager())
        @test v isa VerdictFail
        @test occursin("Semantic", v.reason)
    end

    @testset "n > 8 → VerdictFail (not supported)" begin
        store = Store()
        id    = OctadId(fill(0xA5, 16))
        blob  = SemanticBlob(["http://verisim.test/#big"], UInt8[])
        enrich!(store, id, :semantic, blob, "test")
        clause = ProofOptimalAssignment(id, 9, Tropical(100.0))
        v = prove(clause, store, Manager())
        @test v isa VerdictFail
        @test occursin("Hungarian", v.reason)
    end

end
