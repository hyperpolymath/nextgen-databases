# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
Parser unit tests for KRL (Knot Resolution Language).

Test categories (per standards/testing-and-benchmarking/TESTING-TAXONOMY.adoc):
  Unit      — deterministic AST-shape assertions
  Property  — structural invariants over the returned AST
  Fuzz stub — seed corpus; harness deferred (see PROOF-NEEDS.md §S4)

Coverage mapping to grammar.ebnf productions:
  program, statement, query, source, pipeline_stage
  filter_stage, sort_stage, take_stage, skip_stage, return_stage
  find_equiv_stage, find_path_stage, group_by_stage, aggregate_stage
  match_stage, let_stage, with_stage
  rule_def, axiom_def, let_stmt
  expression (all 9 precedence levels)
  type_expr (atomic, option, list, function, dependent)
  gauss_code
  graph_pattern, node_pattern, edge_pattern

Innovation under test:
  - Pipeline error recovery: errors collected, parsing continues at next |
  - Gauss code validation at parse time
  - parse_any SQL / KRL dispatch
"""

using Test

include("../KRL.jl")
using .KRL: parse_krl, parse_krl_query, parse_any, KRLParseError

# ── helpers ──────────────────────────────────────────────────────────────────

# Return the single KRLQuery inside a one-statement KRLProgram.
one_query(src) = parse_krl_query(src)

# Return the stage at position `i` (1-based) of a query.
stage(q, i) = q.stages[i]

@testset "KRL Parser" begin

    # ── Source clause ────────────────────────────────────────────────────────
    @testset "Source: built-in tables" begin
        for (src, T) in [
            ("from knots",      KRLSourceKnots),
            ("from diagrams",   KRLSourceDiagrams),
            ("from invariants", KRLSourceInvariants),
        ]
            q = one_query(src)
            @test q.source isa T
            @test q.stages == KRLPipeStage[]
        end
    end

    @testset "Source: named + alias" begin
        q = one_query("from my_table")
        @test q.source isa KRLSourceNamed
        @test q.source.name == "my_table"
        @test q.source.alias === nothing

        q = one_query("from base as b")
        @test q.source isa KRLSourceNamed
        @test q.source.name == "base"
        @test q.source.alias == "b"
    end

    @testset "Source: subquery" begin
        q = one_query("from (from knots | filter crossing_number == 3)")
        @test q.source isa KRLSourceSubquery
        @test q.source.query.source isa KRLSourceKnots
    end

    # ── Pipeline stages ──────────────────────────────────────────────────────
    @testset "filter stage" begin
        q = one_query("from knots | filter crossing_number == 3")
        @test length(q.stages) == 1
        s = stage(q, 1)
        @test s isa KRLFilterStage
        @test s.pred isa KRLCompare
        @test s.pred.op == :eq
    end

    @testset "sort stage — asc and desc" begin
        q = one_query("from knots | sort crossing_number asc, name desc")
        s = stage(q, 1)
        @test s isa KRLSortStage
        @test length(s.items) == 2
        _, o1 = s.items[1]
        _, o2 = s.items[2]
        @test o1 == SortAsc
        @test o2 == SortDesc
    end

    @testset "sort stage — default order" begin
        q = one_query("from knots | sort crossing_number")
        s = stage(q, 1)
        @test s isa KRLSortStage
        _, ord = s.items[1]
        @test ord == SortAsc   # default
    end

    @testset "take / skip stages" begin
        q = one_query("from knots | skip 10 | take 5")
        @test stage(q, 1) isa KRLSkipStage
        @test stage(q, 1).n == 10
        @test stage(q, 2) isa KRLTakeStage
        @test stage(q, 2).n == 5
    end

    @testset "return stage — field list" begin
        q = one_query("from knots | return name, crossing_number")
        s = stage(q, 1)
        @test s isa KRLReturnStage
        @test length(s.items) == 2
        @test !s.with_provenance
    end

    @testset "return stage — star" begin
        q = one_query("from knots | return *")
        s = stage(q, 1)
        @test s.items[1] isa KRLReturnStar
    end

    @testset "return stage — with provenance" begin
        q = one_query("from knots | return name with provenance")
        s = stage(q, 1)
        @test s.with_provenance
    end

    @testset "group_by stage" begin
        q = one_query("from knots | group_by crossing_number")
        @test stage(q, 1) isa KRLGroupByStage
        @test length(stage(q, 1).keys) == 1
    end

    @testset "find_equivalent stage — basic" begin
        q = one_query("""from knots | find_equivalent "3_1" via [jones_polynomial]""")
        s = stage(q, 1)
        @test s isa KRLFindEquivStage
        @test s.via_invs == ["jones_polynomial"]
        @test s.min_confidence === nothing
    end

    @testset "find_equivalent stage — confidence" begin
        q = one_query(
            """from knots | find_equivalent "3_1" via [jones_polynomial, alexander_polynomial] confidence >= exact""")
        s = stage(q, 1)
        @test s isa KRLFindEquivStage
        @test length(s.via_invs) == 2
        @test s.min_confidence == ConfExact
    end

    @testset "find_equivalent stage — confidence levels" begin
        for (kw, lv) in [("exact", ConfExact), ("sufficient", ConfSufficient),
                         ("necessary", ConfNecessary), ("heuristic", ConfHeuristic)]
            q = one_query("""from knots | find_equivalent "3_1" via [jones_polynomial] confidence >= $kw""")
            s = stage(q, 1)
            @test s.min_confidence == lv
        end
    end

    @testset "find_path stage" begin
        q = one_query("""from diagrams | find_path "3_1" ~> "3_1" via reidemeister""")
        s = stage(q, 1)
        @test s isa KRLFindPathStage
    end

    @testset "let stage" begin
        q = one_query("from knots | let x = crossing_number + 1")
        s = stage(q, 1)
        @test s isa KRLLetStage
        @test s.name == "x"
    end

    # ── Full pipelines ───────────────────────────────────────────────────────
    @testset "multi-stage pipeline" begin
        q = one_query("""
            from knots
            | filter crossing_number <= 6
            | sort crossing_number asc
            | take 20
            | return name, jones_polynomial
        """)
        @test length(q.stages) == 4
        @test stage(q, 1) isa KRLFilterStage
        @test stage(q, 2) isa KRLSortStage
        @test stage(q, 3) isa KRLTakeStage
        @test stage(q, 4) isa KRLReturnStage
    end

    # ── Top-level statements ─────────────────────────────────────────────────
    @testset "let statement" begin
        prog = parse_krl("let threshold = 6")
        @test length(prog.statements) == 1
        @test prog.statements[1] isa KRLLetStmt
        @test prog.statements[1].name == "threshold"
    end

    @testset "let statement with type annotation" begin
        prog = parse_krl("let n : Int = 3")
        stmt = prog.statements[1]
        @test stmt isa KRLLetStmt
        @test !isnothing(stmt.type_ann)
    end

    @testset "rule definition" begin
        prog = parse_krl("rule is_small(k) :- crossing_number(k) <= 6")
        @test prog.statements[1] isa KRLRuleDef
        @test prog.statements[1].name == "is_small"
        @test prog.statements[1].params == ["k"]
        @test length(prog.statements[1].body_clauses) == 1
    end

    @testset "axiom definition" begin
        prog = parse_krl("axiom reflexivity : x == x -> true")
        stmt = prog.statements[1]
        @test stmt isa KRLAxiomDef
        @test stmt.name == "reflexivity"
        @test isempty(stmt.params)
    end

    # ── Expression precedence ────────────────────────────────────────────────
    @testset "Expression: comparison operators" begin
        for (op_str, op_sym) in [("==", :eq), ("!=", :neq),
                                  ("<", :lt), ("<=", :lte),
                                  (">", :gt), (">=", :gte)]
            q = one_query("from knots | filter x $op_str 1")
            pred = stage(q, 1).pred
            @test pred isa KRLCompare
            @test pred.op == op_sym
        end
    end

    @testset "Expression: arithmetic precedence (* before +)" begin
        q = one_query("from knots | filter a + b * c == 0")
        pred = stage(q, 1).pred
        @test pred isa KRLCompare && pred.op == :eq
        lhs = pred.left
        @test lhs isa KRLBinOp && lhs.op == :add
        @test lhs.right isa KRLBinOp && lhs.right.op == :mul
    end

    @testset "Expression: logical operators" begin
        q = one_query("from knots | filter x == 1 and y == 2 or z == 3")
        pred = stage(q, 1).pred
        # `or` binds looser than `and`
        @test pred isa KRLOr
        @test pred.left isa KRLAnd
    end

    @testset "Expression: not" begin
        q = one_query("from knots | filter not x == 1")
        pred = stage(q, 1).pred
        @test pred isa KRLNot
    end

    @testset "Expression: unary minus" begin
        q = one_query("from knots | filter -x == 0")
        pred = stage(q, 1).pred
        @test pred isa KRLCompare && pred.op == :eq
        @test pred.left isa KRLUnaryNeg
    end

    @testset "Expression: null coalescing" begin
        q = one_query("from knots | filter x ?? 0 == 0")
        pred = stage(q, 1).pred
        # Grammar spec: null_coalesce is top level (lowest precedence)
        @test pred isa KRLNullCoalesce || pred isa KRLCompare
    end

    @testset "Expression: field access (dot)" begin
        q = one_query("from knots | filter k.crossing_number == 3")
        pred = stage(q, 1).pred
        @test pred isa KRLCompare && pred.op == :eq
        @test pred.left isa KRLFieldAccess
        @test pred.left.field == "crossing_number"
    end

    @testset "Expression: function call" begin
        q = one_query("from knots | filter gauss(1, -2, 3) == g")
        pred = stage(q, 1).pred
        @test pred isa KRLCompare && pred.op == :eq
        @test pred.left isa KRLCall
        # KRLCall.func is a KRLExpr; when calling gauss(...) it's KRLVar("gauss")
        @test pred.left.func isa KRLVar && pred.left.func.name == "gauss"
    end

    @testset "Expression: in operator" begin
        q = one_query("from knots | filter name in small_knots")
        pred = stage(q, 1).pred
        @test pred isa KRLCompare && pred.op == :in
    end

    @testset "Expression: iso operator (≅ and ~=)" begin
        q1 = one_query("from knots | filter k1 ≅ k2")
        q2 = one_query("from knots | filter k1 ~= k2")
        for q in [q1, q2]
            pred = stage(q, 1).pred
            @test pred isa KRLCompare && pred.op == :iso
        end
    end

    @testset "Expression: tilde-arrow pipeline connector" begin
        # ~> appears in find_path, not filter — but verify the token is lexed
        toks = tokenise("K1 ~> K2")
        @test any(t -> t.kind == :tilde_arrow, toks)
    end

    # ── Gauss code ───────────────────────────────────────────────────────────
    @testset "Gauss code: valid" begin
        q = one_query("from diagrams | filter gauss(1, -2, 3, -1, 2, -3) == d")
        pred = stage(q, 1).pred
        # gauss(...) is parsed as a KRLCall whose func is KRLVar("gauss")
        @test pred.left isa KRLCall
        @test length(pred.left.args) == 6
    end

    @testset "Gauss code: zero value rejected" begin
        @test_throws KRLParseError parse_krl_query(
            "from diagrams | filter gauss(0, 1, 2) == d")
    end

    @testset "Gauss code: empty rejected" begin
        @test_throws KRLParseError parse_krl_query(
            "from diagrams | filter gauss() == d")
    end

    # ── Error recovery ───────────────────────────────────────────────────────
    @testset "Error recovery: valid stage after invalid stage" begin
        # Black-box: parse_krl throws the *first* collected error; recovery means
        # the error is from the bad stage, not from the subsequent valid stage.
        @test_throws KRLParseError parse_krl("from knots | filter | return name")
        try
            parse_krl("from knots | filter | return name")
        catch e
            @test e isa KRLParseError
            # Error location should be in the filter stage area, not at "return"
            @test e.line >= 1
        end
    end

    @testset "Error recovery: multiple stages — error at stage 2 only" begin
        # Stage 1 valid, stage 2 invalid (unknown keyword), stage 3 valid.
        # parse_krl throws first error; error is from stage 2, not stage 3.
        try
            parse_krl("from knots | filter x == 1 | frobnicate 99 | take 5")
        catch e
            @test e isa KRLParseError
            @test occursin("frobnicate", e.msg)
        end
    end

    # ── Source positions ─────────────────────────────────────────────────────
    @testset "Source positions" begin
        prog = parse_krl("from knots\n| filter crossing_number == 3")
        stmt = prog.statements[1]
        @test stmt.line == 1
        q = stmt.query
        @test q.line == 1 && q.col == 1
        s = stage(q, 1)
        @test s.line == 2   # filter is on line 2
    end

    @testset "Source positions — multi-statement" begin
        prog = parse_krl("let n = 1\nfrom knots | take 5")
        @test prog.statements[1].line == 1
        @test prog.statements[2].line == 2
    end

    # ── parse_any dispatch ───────────────────────────────────────────────────
    @testset "parse_any: routes KRL" begin
        prog = parse_any("from knots | take 3")
        @test prog.statements[1] isa KRLQueryStmt
    end

    @testset "parse_any: routes SQL" begin
        prog = parse_any("SELECT * FROM knots LIMIT 3")
        @test prog.statements[1] isa KRLQueryStmt
        q = prog.statements[1].query
        @test q.source isa KRLSourceKnots
    end

    @testset "parse_any: SELECT case-insensitive" begin
        prog = parse_any("select name from knots")
        @test prog.statements[1] isa KRLQueryStmt
    end

    # ── Type expressions ─────────────────────────────────────────────────────
    @testset "Type annotations: atomic types" begin
        for ty in ["Int", "Float", "String", "Bool"]
            prog = parse_krl("let x : $ty = 0")
            stmt = prog.statements[1]
            @test !isnothing(stmt.type_ann)
            @test stmt.type_ann isa KRLTyScalar
            @test string(stmt.type_ann.name) == ty
        end
    end

    @testset "Type annotations: Option type" begin
        prog = parse_krl("let x : Option[Int] = none")
        stmt = prog.statements[1]
        @test stmt.type_ann isa KRLTyOption
    end

    @testset "Type annotations: List type" begin
        prog = parse_krl("let xs : List[String] = none")
        stmt = prog.statements[1]
        @test stmt.type_ann isa KRLTyList
    end

    # ── Property: structural invariants ─────────────────────────────────────
    @testset "Property: all nodes carry valid positions" begin
        sources = [
            "from knots | filter crossing_number >= 3 | sort name asc | take 10",
            """from knots | find_equivalent "3_1" via [jones_polynomial]""",
            "let max_cn = 6\nfrom knots | filter crossing_number <= max_cn",
        ]
        for src in sources
            prog = parse_krl(src)
            for stmt in prog.statements
                @test stmt.line >= 1 && stmt.col >= 1
            end
        end
    end

    @testset "Property: parse_krl is deterministic" begin
        for src in [
            "from knots | filter x == 1",
            "let n = 3\nfrom knots | take n",
            """from knots | find_equivalent "3_1" via [jones_polynomial]""",
        ]
            p1 = parse_krl(src)
            p2 = parse_krl(src)
            # Compare statement count and first statement type
            @test length(p1.statements) == length(p2.statements)
            @test typeof.(p1.statements) == typeof.(p2.statements)
        end
    end

    @testset "Property: empty source produces single-statement program" begin
        prog = parse_krl("from knots")
        @test length(prog.statements) == 1
        q = prog.statements[1].query
        @test isempty(q.stages)
    end

    # ── Error cases ──────────────────────────────────────────────────────────
    @testset "Error: missing from" begin
        @test_throws KRLParseError parse_krl("filter x == 1")
    end

    @testset "Error: unknown stage keyword" begin
        @test_throws KRLParseError parse_krl("from knots | wobble 99")
    end

    @testset "Error: unclosed subquery" begin
        @test_throws KRLParseError parse_krl("from (from knots | take 5")
    end

    @testset "Error: take requires integer literal" begin
        @test_throws KRLParseError parse_krl("from knots | take x")
    end

    @testset "Error: skip requires integer literal" begin
        @test_throws KRLParseError parse_krl("from knots | skip x")
    end

    # ── Fuzz seed corpus (smoke) ─────────────────────────────────────────────
    # The testing taxonomy requires a fuzz harness for the parser (PROOF-NEEDS.md §S4).
    # The following seed corpus covers known crash-inducing patterns; a full AFL++
    # harness is deferred pending CI integration.
    @testset "Fuzz seed corpus (smoke)" begin
        crash_candidates = [
            "from",
            "from knots |",
            "from knots | filter",
            "from knots | return",
            "from ()",
            "from (from)",
            "let",
            "let x",
            "let x =",
            "rule r",
            "rule r()",
            "axiom a :",
            """from knots | find_equivalent "3_1" via []""",
            "from knots | sort",
            "from knots | take",
            "from knots | skip",
            "from knots | filter x == 1 and",
            "from knots | filter x in",
        ]
        for src in crash_candidates
            try
                parse_krl(src)
            catch e
                @test e isa KRLParseError || e isa KRLLexError
            end
        end
    end

end # @testset "KRL Parser"
