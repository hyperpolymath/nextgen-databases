# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test_krladapter_integration.jl — Phase 4 dogfood validation.
#
# Verifies that KRLAdapter.jl's TangleIR (surrogate) flows through
# VerisimCore without requiring any Federable shapes.

using Test

include(joinpath(@__DIR__, "..", "examples", "krladapter_integration.jl"))

# (The examples script imports everything the tests need.)

@testset "Phase 4 dogfood: KRLAdapter.jl → VerisimCore" begin

    @testset "TangleIR → SemanticBlob adapter is deterministic" begin
        t1 = TangleIRSurrogate("trefoil", [4,6,2], :user, "B_1^3")
        t2 = TangleIRSurrogate("trefoil", [4,6,2], :user, "B_1^3")
        @test tangle_to_semantic(t1).type_uris == tangle_to_semantic(t2).type_uris
        @test tangle_to_semantic(t1).proof_bytes == tangle_to_semantic(t2).proof_bytes
        @test tangle_octad_id(t1) == tangle_octad_id(t2)
    end

    @testset "Different tangles produce different octad ids" begin
        trefoil = TangleIRSurrogate("trefoil", [4,6,2], :user, "B_1^3")
        figure8 = TangleIRSurrogate("figure8", [4,6,8,2], :user, "B_1^-1 B_2 B_1^-1 B_2")
        @test tangle_octad_id(trefoil) != tangle_octad_id(figure8)
    end

    @testset "Provenance tag flows through SemanticBlob type URIs" begin
        t_user = TangleIRSurrogate("k", [2,4], :user, "src")
        t_rewritten = TangleIRSurrogate("k", [2,4], :rewritten, "src")
        b_user = tangle_to_semantic(t_user)
        b_rewritten = tangle_to_semantic(t_rewritten)
        @test any(occursin("provenance/user", u) for u in b_user.type_uris)
        @test any(occursin("provenance/rewritten", u) for u in b_rewritten.type_uris)
    end

    @testset "End-to-end: TangleIR lifecycle in VerisimCore (no federation)" begin
        store = Store()
        manager = Manager()  # NO peers registered

        trefoil = TangleIRSurrogate("trefoil", [4,6,2], :user, "B_1^3")
        id = tangle_octad_id(trefoil)

        # Create.
        enrich!(store, id, :semantic, tangle_to_semantic(trefoil), "user")

        # Rewrite (Reidemeister move).
        rewritten = TangleIRSurrogate("trefoil", [4,6,2], :rewritten,
                                       "Reidemeister III applied")
        enrich!(store, id, :semantic, tangle_to_semantic(rewritten), "rewriter")

        # Verify identity persisted + audit trail records both events.
        octad = get_core(store, id)
        @test octad !== nothing
        @test octad.id == id
        @test length(octad.temporal.leaves) == 2
        @test length(octad.provenance.entries) == 2
        @test octad.provenance.entries[1].actor == "user"
        @test octad.provenance.entries[2].actor == "rewriter"

        # Chain integrity.
        @test octad.provenance.entries[2].prev_hash == octad.provenance.entries[1].this_hash

        # PROOF INTEGRITY passes with Core-only state.
        @test prove(ProofIntegrity(id), store, manager) isa VerdictPass

        # PROOF FRESHNESS passes within a generous window.
        @test prove(ProofFreshness(id, Int64(60_000_000_000)), store, manager) isa VerdictPass

        # Attestation round-trips.
        result = attest(store, id)
        @test result !== nothing
        oc, sig, t = result
        @test verify_attest(store, oc, sig, t)
    end

    @testset "Client needs no Federable shapes" begin
        # Positive result for Phase 4: the entire TangleIR lifecycle
        # (create, rewrite, verify, attest) completes with an EMPTY
        # federation manager. No Vector, Document, Spatial, Tensor peer
        # required.
        store = Store()
        manager = Manager()

        @test isempty(FederationManager.registered_shapes(manager))

        t = TangleIRSurrogate("hopf-link", [4,2,8,6], :user, "B_1^2")
        id = tangle_octad_id(t)
        enrich!(store, id, :semantic, tangle_to_semantic(t), "user")

        @test prove(ProofIntegrity(id), store, manager) isa VerdictPass
    end

end
