# SPDX-License-Identifier: PMPL-1.0-or-later
"""
Lith-Analytics test suite
"""

using Test
using LithAnalytics
using DataFrames
using Dates

@testset "LithAnalytics" begin
    @testset "Config" begin
        # Test default config
        config = Config()
        @test config.lith.api_url == "http://localhost:8080"
        @test config.server.port == 8082
        @test config.storage.data_dir == "./data"
    end

    @testset "ColumnarStore" begin
        # Test store creation
        mktempdir() do tmpdir
            store = ColumnarStore(tmpdir)
            @test isempty(store.collections)

            # Test stats on empty store
            s = stats(store)
            @test isempty(s)
        end
    end

    @testset "PROMPT extraction" begin
        # Test document with PROMPT scores
        doc = Document(
            "test-001",
            Dict{String,Any}(
                "title" => "Test Document",
                "prompt_scores" => Dict{String,Any}(
                    "provenance" => 0.8,
                    "replicability" => 0.7,
                    "objective" => 0.9,
                    "methodology" => 0.85,
                    "publication" => 0.6,
                    "transparency" => 0.95
                )
            ),
            nothing
        )

        prompt = extract_prompt_scores(doc)
        @test !isnothing(prompt)
        @test prompt.provenance == 0.8
        @test prompt.transparency == 0.95

        # Test document without PROMPT scores
        doc_no_prompt = Document(
            "test-002",
            Dict{String,Any}("title" => "No PROMPT"),
            nothing
        )

        @test isnothing(extract_prompt_scores(doc_no_prompt))
    end

    @testset "Timestamp extraction" begin
        # Test provenance timestamp
        doc = Document(
            "test-001",
            Dict{String,Any}(),
            Dict{String,Any}("created_at" => "2025-01-16T12:00:00Z")
        )

        ts = extract_timestamp(doc)
        @test !isnothing(ts)
        @test year(ts) == 2025

        # Test data timestamp
        doc_data_ts = Document(
            "test-002",
            Dict{String,Any}("timestamp" => "2025-01-15T10:00:00"),
            nothing
        )

        ts2 = extract_timestamp(doc_data_ts)
        @test !isnothing(ts2)
        @test day(ts2) == 15
    end
end
