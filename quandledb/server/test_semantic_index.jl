# SPDX-License-Identifier: PMPL-1.0-or-later

using Test
using Skein
using KnotTheory

include(joinpath(@__DIR__, "quandle_semantic.jl"))
include(joinpath(@__DIR__, "serve.jl"))

@testset "Quandle extraction module" begin
    t_pd = trefoil().pd
    f_pd = figure_eight().pd
    u_pd = unknot().pd

    t_pres = QuandleSemantic.extract_presentation(t_pd)
    f_pres = QuandleSemantic.extract_presentation(f_pd)
    u_pres = QuandleSemantic.extract_presentation(u_pd)
    @test t_pres.generator_count >= 1
    @test length(t_pres.relations) == length(t_pd.crossings)
    @test length(f_pres.relations) == length(f_pd.crossings)
    @test length(u_pres.relations) == length(u_pd.crossings)

    # Test BLAKE3 fingerprinting
    t_blob = QuandleSemantic.canonical_presentation_blob(t_pres)
    t_blob2 = QuandleSemantic.canonical_presentation_blob(t_pres)
    @test t_blob == t_blob2
    @test length(t_blob) == 64  # BLAKE3 hash is 64 characters

    f_blob = QuandleSemantic.canonical_presentation_blob(f_pres)
    u_blob = QuandleSemantic.canonical_presentation_blob(u_pres)
    @test t_blob != f_blob
    @test t_blob != u_blob
    @test f_blob != u_blob

    # Test colouring counts
    t_desc = QuandleSemantic.quandle_descriptor(t_pd)
    f_desc = QuandleSemantic.quandle_descriptor(f_pd)
    u_desc = QuandleSemantic.quandle_descriptor(u_pd)
    @test t_desc.presentation_hash isa String
    @test length(t_desc.presentation_hash) == 64
    @test t_desc.presentation_hash != f_desc.presentation_hash
    @test t_desc.colouring_count_3 != f_desc.colouring_count_3 ||
          t_desc.colouring_count_5 != f_desc.colouring_count_5
    @test u_desc.colouring_count_3 == 3  # Unknot should have 3 colourings for modulus 3
    @test u_desc.colouring_count_5 == 5  # Unknot should have 5 colourings for modulus 5
end

@testset "Semantic index sidecar integration" begin
    db = SkeinDB(":memory:")
    store!(db, "trefoil_pd", trefoil())
    store!(db, "figure_eight_pd", figure_eight())
    store!(db, "gauss_only", Skein.GaussCode([1, -2, 3, -1, 2, -3]))

    semantic_path = tempname() * ".db"
    sdb = SemanticIndexDB(semantic_path)
    indexed = rebuild_semantic_index!(sdb, db)
    @test indexed == 3

    t_row = semantic_row_by_name(sdb, "trefoil_pd")
    @test !isnothing(t_row)
    t_detail = semantic_to_dict(t_row)
    @test t_detail["descriptor_version"] == "qpres-v1"
    @test !isnothing(t_detail["quandle_generator_count"])
    @test !isnothing(t_detail["quandle_relation_count"])
    @test !isnothing(t_detail["colouring_count_3"])
    @test !isnothing(t_detail["colouring_count_5"])

    g_row = semantic_row_by_name(sdb, "gauss_only")
    @test !isnothing(g_row)
    g_detail = semantic_to_dict(g_row)
    @test g_detail["descriptor_version"] == "fallback-v1"

    buckets = semantic_equivalence_buckets(sdb, "trefoil_pd")
    @test !isnothing(buckets)
    @test "trefoil_pd" in buckets.strong
    @test "trefoil_pd" in buckets.combined

    close(sdb)
    close(db)
    rm(semantic_path; force = true)
end

println("semantic-index-tests-ok")
