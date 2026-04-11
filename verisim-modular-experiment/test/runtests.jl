# SPDX-License-Identifier: PMPL-1.0-or-later
#
# test/runtests.jl — Pkg.test() entry point for the Verisim package.
#
# Architecture note:
#   Each included test file self-loads the impl modules it needs via
#   `include(...)`, which is the "flat-include scaffold" convention used
#   throughout this research prototype.  Running files in sequence causes
#   Julia to replace modules on each re-include (a WARNING, not an error);
#   this is acceptable here because each @testset creates fresh stores and
#   types from the just-loaded module instances.
#
#   One additional top-level @testset exercises the package API
#   (`using Verisim`) before the individual suites run, verifying that
#   src/Verisim.jl loads cleanly and delegates correctly.

using Test

# -----------------------------------------------------------------------
# Package smoke test — must pass before any impl-level tests
# -----------------------------------------------------------------------

@testset "Verisim package API (src/Verisim.jl)" begin
    using Verisim
    import KnotTheory  # needed by TangleGraph at Main level

    @testset "package loads and __init__ populates Main" begin
        @test isdefined(Main, :VerisimCore)
        @test isdefined(Main, :VCLProver)
        @test isdefined(Main, :TropicalMatrix)
        @test isdefined(Main, :TangleGraph)
    end

    @testset "prove(ProofIntegrity) via package API" begin
        store   = Verisim.Store()
        manager = Verisim.Manager()
        id      = Verisim.OctadId(fill(0x42, 16))
        blob    = Verisim.SemanticBlob(["http://verisim.pkg.test/#smoke"], b"smoke")

        Verisim.enrich!(store, id, :semantic, blob, "pkg-test")

        v = Verisim.prove(Verisim.ProofIntegrity(id), store, manager)
        @test v isa Main.VCLQuery.VerdictPass
    end

    @testset "parse_vcl round-trip via package API" begin
        q = Verisim.parse_vcl("PROOF INTEGRITY FOR " * "ab" ^ 16)
        @test q isa Main.VCLQuery.ProofIntegrity
    end
end

# -----------------------------------------------------------------------
# Impl-level test suites (each self-loads its own subset of impl modules)
# -----------------------------------------------------------------------
# Module replacement warnings are expected and harmless here.

@testset "VerisimCore"            begin include("test_verisim_core.jl")           end
@testset "Federation parity"      begin include("test_federation_parity.jl")      end
@testset "Non-interference"       begin include("test_noninterference.jl")        end
@testset "Seams"                  begin include("test_seams.jl")                  end
@testset "KRLAdapter integration" begin include("test_krladapter_integration.jl") end
@testset "VCL"                    begin include("test_vcl.jl")                    end
