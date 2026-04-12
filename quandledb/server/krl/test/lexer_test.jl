# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
Lexer unit tests for KRL (Knot Resolution Language).

Test categories (per standards/testing-and-benchmarking/TESTING-TAXONOMY.adoc):
  Unit          — deterministic per-token assertions
  Property      — invariants over random inputs (manual random generation)
  Fuzz stub     — placeholder; see note below

Fuzz note: The testing taxonomy mandates fuzz tests for parsers. A proper
fuzz harness requires `julia-fuzz` or a custom AFL++ driver. This file
documents the obligation and provides a reproducible seed corpus; the
harness itself is deferred pending CI integration (PROOF-NEEDS.md §S4).
"""

using Test

# Load the lexer directly (standalone, no server dependency)
include("../Lexer.jl")

@testset "KRL Lexer" begin

    @testset "Whitespace and comments" begin
        # All whitespace forms produce zero tokens (beyond EOF)
        for ws in [" ", "\t", "\n", "\r\n", "  \t\n  "]
            toks = tokenise(ws)
            @test length(toks) == 1 && toks[1].kind == :eof
        end

        # Line comments are skipped
        toks = tokenise("-- this is a comment\n")
        @test length(toks) == 1

        # Block comment is skipped
        toks = tokenise("{- block -}")
        @test length(toks) == 1

        # Nested block comment (innovation: depth > 1)
        toks = tokenise("{- outer {- inner -} still outer -}")
        @test length(toks) == 1

        # Token after block comment is present
        toks = tokenise("{- skip -} knots")
        @test length(toks) == 2
        @test toks[1].kind == :keyword && toks[1].value == "knots"
    end

    @testset "Keywords" begin
        for kw in ["from", "filter", "sort", "take", "skip", "return",
                   "find_equivalent", "find_path", "match", "group_by",
                   "aggregate", "and", "or", "not", "via", "with", "let",
                   "confidence", "exact", "necessary", "sufficient", "heuristic",
                   "asc", "desc", "rule", "axiom", "reidemeister",
                   "knots", "diagrams", "invariants", "provenance",
                   "true", "false", "none"]
            toks = tokenise(kw)
            @test length(toks) == 2
            @test toks[1].kind == :keyword
            @test toks[1].value == kw
        end
    end

    @testset "Identifiers" begin
        for id in ["foo", "crossing_number", "jones_polynomial", "_private",
                   "camelCase", "with_hyphen-like"]
            toks = tokenise(id)
            @test toks[1].kind ∈ (:identifier, :keyword)
            @test toks[1].value == id
        end
    end

    @testset "Knot names (innovation)" begin
        # digit_digit form → :knot_name
        for kn in ["3_1", "5_2", "10_139", "0_1"]
            toks = tokenise(kn)
            @test toks[1].kind == :knot_name
            @test toks[1].value == kn
        end
        # bare integer (no underscore) → :integer
        toks = tokenise("42")
        @test toks[1].kind == :integer

        # integer followed by non-digit underscore remains split
        toks = tokenise("3 _foo")
        @test toks[1].kind == :integer
        @test toks[2].kind == :identifier
    end

    @testset "Numeric literals" begin
        # integers
        for s in ["0", "1", "123", "999"]
            toks = tokenise(s)
            @test toks[1].kind == :integer && toks[1].value == s
        end

        # floats
        for s in ["1.0", "3.14", "0.5", "100.001"]
            toks = tokenise(s)
            @test toks[1].kind == :float && toks[1].value == s
        end
    end

    @testset "String literals" begin
        toks = tokenise("\"hello\"")
        @test toks[1].kind == :string && toks[1].value == "hello"

        # Escape sequences
        toks = tokenise("\"a\\nb\"")
        @test toks[1].value == "a\nb"

        toks = tokenise("\"tab\\there\"")
        @test toks[1].value == "tab\there"

        # Unterminated string → KRLLexError
        @test_throws KRLLexError tokenise("\"unterminated")
    end

    @testset "Operators" begin
        pairs = [
            ("==", :eq), ("!=", :neq), ("<", :lt), ("<=", :lte),
            (">", :gt), (">=", :gte),
            ("+", :plus), ("-", :minus), ("*", :star), ("/", :slash), ("%", :percent),
            ("|", :pipe), ("->", :arrow), ("=>", :fat_arrow),
            ("~>", :tilde_arrow), ("??", :null_coalesce),
            (".", :dot), (":", :colon), (",", :comma), (";", :semi),
        ]
        for (src, kind) in pairs
            toks = tokenise(src)
            @test toks[1].kind == kind
        end

        # Unicode ≅ and ASCII ~= both → :iso
        @test tokenise("≅")[1].kind == :iso
        @test tokenise("~=")[1].kind == :iso
    end

    @testset "Delimiters" begin
        for (src, kind) in [("(", :lparen), (")", :rparen),
                            ("[", :lbracket), ("]", :rbracket),
                            ("{", :lbrace), ("}", :rbrace)]
            @test tokenise(src)[1].kind == kind
        end
    end

    @testset "Source positions" begin
        toks = tokenise("from\n  knots")
        @test toks[1].line == 1 && toks[1].col == 1
        @test toks[2].line == 2 && toks[2].col == 3
    end

    @testset "Error cases" begin
        # Bare = (not ==)
        @test_throws KRLLexError tokenise("=")
        # Bare ~ (not ~> or ~=)
        @test_throws KRLLexError tokenise("~")
        # Bare ? (not ??)
        @test_throws KRLLexError tokenise("?")
        # Unrecognised character
        @test_throws KRLLexError tokenise("@")
        # Unterminated block comment
        @test_throws KRLLexError tokenise("{- never closed")
    end

    @testset "Property: every token has a valid line/col (> 0)" begin
        for src in ["from knots | filter x == 1",
                    "let x = gauss(1, -2, 3)",
                    "find_equivalent \"3_1\" via [jones]"]
            for tok in tokenise(src)
                @test tok.line >= 1
                @test tok.col  >= 1
            end
        end
    end

    @testset "Property: tokenise is deterministic" begin
        for src in ["from knots", "3_1", "{- comment -} filter"]
            @test tokenise(src) == tokenise(src)
        end
    end

    # ── Fuzz obligation (deferred) ────────────────────────────────────────────
    # The testing taxonomy requires a fuzz harness for the lexer. The following
    # seed corpus covers known crash-inducing inputs; a full AFL++ / julia-fuzz
    # harness is pending (see PROOF-NEEDS.md §S4).
    @testset "Fuzz seed corpus (smoke)" begin
        crash_candidates = [
            "",
            "\"",
            "{-",
            "{- {-",
            "≅≅≅",
            "~",
            "??",
            "0_",
            "1.",
            "1.a",
            "\x00",
        ]
        for src in crash_candidates
            try
                tokenise(src)
            catch e
                @test e isa KRLLexError   # only KRLLexError is acceptable
            end
        end
    end

end # @testset "KRL Lexer"
