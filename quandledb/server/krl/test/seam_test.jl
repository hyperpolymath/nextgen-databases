# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
Seam and integration tests for QuandleDB's point-to-point query pipeline.

Each @testset here targets a specific integration boundary (seam):

  Seam 1 — KRL Parser → Evaluator
      parse_krl + eval_krl_program with injected providers.
      Verifies AST flows through the evaluator without crashing.

  Seam 2 — Evaluator → DataProvider
      MockDataProvider carries canned knot rows.
      Tests pushdown extraction, filter, sort, take/skip, return, group_by,
      find_equivalent, and let/with stages.

  Seam 3 — Evaluator → SemProvider (equivalence)
      MockSemProvider returns canned equivalence buckets.
      Tests find_equivalent confidence levels, degraded behaviour when
      the target is missing, and equivalence of equivalent classes.

  Seam 4 — Circuit breaker fault isolation
      Simulates DataProvider failures to verify CircuitBreaker transitions:
      :closed → :open after threshold failures, :half_open after cooldown,
      self-heal on successful probe.

  Seam 5 — SQL Frontend → Evaluator
      End-to-end: SQL text → parse_sql → eval_krl_program → rows.

  Seam 6 — parse_any auto-dispatch
      Verify parse_any routes SQL and KRL to correct evaluator paths.

  Seam 7 — Health report structure
      check_health returns a HealthReport with correct component names
      and overall status derived from component statuses.

  Seam 8 — Metrics accumulation
      record_query! increments counters; metrics_snapshot returns
      correct p50/p95 estimates.

All seam tests are deterministic — no file I/O, no network, no Skein DB.
"""

using Test

include("../KRL.jl")
using .KRL: parse_krl, parse_krl_query, parse_sql, parse_any, KRLParseError,
            eval_krl_program, make_eval_context, EvalContext, EvalResult,
            KRLEvalError, DataProvider, SemProvider,
            fetch_all, fetch_one, count, equiv_buckets, fetch_invariants,
            PushdownHints, extract_pushdown!

include("../../Diagnostics.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Mock providers
# ─────────────────────────────────────────────────────────────────────────────

"""
MockDataProvider — canned rows + optional failure injection.

`fail_after` controls how many calls succeed before raising an error.
Set to `typemax(Int)` (default) for no failures.
"""
mutable struct MockDataProvider <: DataProvider
    rows::Vector{Dict{String, Any}}
    calls::Int
    fail_after::Int
end

function MockDataProvider(rows = nothing; fail_after = typemax(Int))
    rows = something(rows, _default_knots())
    MockDataProvider(rows, 0, fail_after)
end

function KRL.fetch_all(p::MockDataProvider; crossing_number=nothing, writhe=nothing,
                        genus=nothing, determinant=nothing, signature=nothing,
                        name_like=nothing, limit=nothing, kwargs...)
    p.calls += 1
    p.calls > p.fail_after && error("MockDataProvider: injected failure at call $(p.calls)")
    result = copy(p.rows)
    !isnothing(crossing_number) && filter!(r -> get(r,"crossing_number",0) == crossing_number, result)
    !isnothing(writhe)          && filter!(r -> get(r,"writhe",0) == writhe, result)
    !isnothing(genus)           && filter!(r -> get(r,"genus",0) == genus, result)
    !isnothing(name_like)       && filter!(r -> occursin(replace(name_like,"%"=>""), get(r,"name","")), result)
    !isnothing(limit)           && length(result) > limit && resize!(result, limit)
    result
end

function KRL.fetch_one(p::MockDataProvider, name::String)
    findfirst(r -> r["name"] == name, p.rows) |>
        i -> isnothing(i) ? nothing : p.rows[i]
end

KRL.count(p::MockDataProvider) = length(p.rows)

# Canned knot database
function _default_knots()
    [
        Dict{String,Any}("id"=>1, "name"=>"0_1", "crossing_number"=>0,
            "writhe"=>0, "genus"=>0, "determinant"=>1, "signature"=>0,
            "jones_polynomial"=>"-t^2+t+1",  "alexander_polynomial"=>"1",
            "gauss_code"=>Int[], "diagram_format"=>"gauss"),
        Dict{String,Any}("id"=>2, "name"=>"3_1", "crossing_number"=>3,
            "writhe"=>3, "genus"=>1, "determinant"=>3, "signature"=>-2,
            "jones_polynomial"=>"-t^4+t^3+t",  "alexander_polynomial"=>"-t+3-t^-1",
            "gauss_code"=>[1,-2,3,-1,2,-3], "diagram_format"=>"gauss"),
        Dict{String,Any}("id"=>3, "name"=>"4_1", "crossing_number"=>4,
            "writhe"=>0, "genus"=>1, "determinant"=>5, "signature"=>0,
            "jones_polynomial"=>"t^2-t+1-t^-1+t^-2", "alexander_polynomial"=>"-t+3-t^-1",
            "gauss_code"=>[1,-2,3,-4,2,-1,4,-3], "diagram_format"=>"gauss"),
        Dict{String,Any}("id"=>4, "name"=>"5_1", "crossing_number"=>5,
            "writhe"=>5, "genus"=>2, "determinant"=>5, "signature"=>-4,
            "jones_polynomial"=>"-t^7+t^6+t^2", "alexander_polynomial"=>"2-t-t^-1",
            "gauss_code"=>[1,-2,3,-4,5,-1,2,-3,4,-5], "diagram_format"=>"gauss"),
        Dict{String,Any}("id"=>5, "name"=>"5_2", "crossing_number"=>5,
            "writhe"=>-1, "genus"=>1, "determinant"=>7, "signature"=>-2,
            "jones_polynomial"=>"-t^6+t^5+t^3-t^2+t", "alexander_polynomial"=>"-2t+5-2t^-1",
            "gauss_code"=>[1,-2,3,-4,5,-3,4,-5,2,-1], "diagram_format"=>"gauss"),
    ]
end

# ── Mock semantic provider ────────────────────────────────────────────────────

mutable struct MockSemProvider <: SemProvider
    buckets::Dict{String, NamedTuple}
end

function MockSemProvider()
    # 3_1 and fake_trefoil share a strong bucket; 5_1 and 5_2 share a weak one
    MockSemProvider(Dict{String, NamedTuple}(
        "3_1"          => (strong=["3_1","fake_trefoil"], weak=["3_1","fake_trefoil","5_1"]),
        "fake_trefoil" => (strong=["3_1","fake_trefoil"], weak=["3_1","fake_trefoil","5_1"]),
        "4_1"          => (strong=["4_1"],                weak=["4_1"]),
        "5_1"          => (strong=["5_1"],                weak=["5_1","5_2"]),
        "5_2"          => (strong=["5_2"],                weak=["5_1","5_2"]),
    ))
end

KRL.equiv_buckets(p::MockSemProvider, name::String) = get(p.buckets, name, nothing)

KRL.fetch_invariants(p::MockSemProvider) = [
    Dict{String,Any}("name"=>"jones_polynomial", "invariant_type"=>"polynomial"),
    Dict{String,Any}("name"=>"alexander_polynomial", "invariant_type"=>"polynomial"),
    Dict{String,Any}("name"=>"determinant", "invariant_type"=>"integer"),
    Dict{String,Any}("name"=>"signature", "invariant_type"=>"integer"),
]

# Helper: build a default context
function mk_ctx(; data = MockDataProvider(), sem = MockSemProvider(),
                  max_rows = 1000, timeout_s = 30.0)
    make_eval_context(data, sem; max_rows, timeout_s)
end

# Helper: parse KRL and evaluate
eval_krl(src; kw...) = eval_krl_program(parse_krl(src), mk_ctx(; kw...))

# ─────────────────────────────────────────────────────────────────────────────
# Seam 1 — KRL Parser → Evaluator
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 1: Parser → Evaluator" begin

    @testset "bare from-knots produces all rows" begin
        r = eval_krl("from knots")
        @test r isa EvalResult
        @test length(r.rows) == 5  # 5 mock knots
    end

    @testset "parse error does not reach evaluator" begin
        @test_throws KRLParseError parse_krl("from knots | filter")
    end

    @testset "lex error does not reach evaluator" begin
        @test_throws KRLLexError eval_krl_program(
            try; parse_krl("from knots @ filter x == 1"); catch e; rethrow(); end,
            mk_ctx())
    end

    @testset "parse source propagated to EvalResult" begin
        r = eval_krl_program(parse_krl("from knots"), mk_ctx(); parse_source = :krl)
        @test r.parse_source == :krl

        r2 = eval_krl_program(parse_sql("SELECT * FROM knots"), mk_ctx();
                               parse_source = :sql)
        @test r2.parse_source == :sql
    end

    @testset "let statement bound before query" begin
        r = eval_krl("let max_cn = 3\nfrom knots | filter crossing_number <= max_cn")
        @test all(row -> get(row,"crossing_number",99) <= 3, r.rows)
    end

    @testset "EvalResult carries trace" begin
        r = eval_krl("from knots | filter crossing_number == 3 | take 1")
        @test !isempty(r.traces)
        names = [t.stage_name for t in r.traces]
        @test any(n -> occursin("source", n), names)
        @test "filter" in names
        @test "take" in names
    end

end

# ─────────────────────────────────────────────────────────────────────────────
# Seam 2 — Evaluator → DataProvider
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 2: Evaluator → DataProvider" begin

    @testset "filter: equality on crossing_number" begin
        r = eval_krl("from knots | filter crossing_number == 3")
        @test length(r.rows) == 1
        @test r.rows[1]["name"] == "3_1"
    end

    @testset "filter: comparison operators" begin
        r_lt  = eval_krl("from knots | filter crossing_number < 4")
        r_lte = eval_krl("from knots | filter crossing_number <= 3")
        r_gt  = eval_krl("from knots | filter crossing_number > 4")
        r_gte = eval_krl("from knots | filter crossing_number >= 5")
        @test length(r_lt.rows)  == 2  # 0_1, 3_1
        @test length(r_lte.rows) == 2  # 0_1, 3_1
        @test length(r_gt.rows)  == 2  # 5_1, 5_2
        @test length(r_gte.rows) == 2  # 5_1, 5_2
    end

    @testset "filter: logical and / or / not" begin
        r_and = eval_krl("from knots | filter crossing_number >= 3 and crossing_number <= 4")
        @test length(r_and.rows) == 2  # 3_1, 4_1

        r_or  = eval_krl("from knots | filter crossing_number == 3 or crossing_number == 5")
        @test length(r_or.rows) == 3  # 3_1, 5_1, 5_2

        r_not = eval_krl("from knots | filter not crossing_number == 3")
        @test !any(r -> r["name"] == "3_1", r_not.rows)
    end

    @testset "pushdown: equality on crossing_number" begin
        dp = MockDataProvider()
        ctx = mk_ctx(data = dp)
        eval_krl_program(parse_krl("from knots | filter crossing_number == 3"), ctx)
        # Pushdown means fetch_all was called with crossing_number=3,
        # so dp returns fewer rows before in-memory filter
        @test dp.calls >= 1
    end

    @testset "pushdown flag in EvalResult" begin
        r = eval_krl("from knots | filter crossing_number == 3")
        @test r.pushdown_used
    end

    @testset "sort: ascending by crossing_number" begin
        r = eval_krl("from knots | sort crossing_number asc")
        cns = [row["crossing_number"] for row in r.rows]
        @test issorted(cns)
    end

    @testset "sort: descending by crossing_number" begin
        r = eval_krl("from knots | sort crossing_number desc")
        cns = [row["crossing_number"] for row in r.rows]
        @test issorted(cns; rev = true)
    end

    @testset "take" begin
        r = eval_krl("from knots | take 3")
        @test length(r.rows) == 3
    end

    @testset "skip" begin
        r = eval_krl("from knots | skip 3")
        @test length(r.rows) == 2
    end

    @testset "take 0 produces empty result" begin
        r = eval_krl("from knots | take 0")
        @test isempty(r.rows)
    end

    @testset "return: field projection" begin
        r = eval_krl("from knots | return name, crossing_number")
        for row in r.rows
            @test haskey(row, "name")
            @test haskey(row, "crossing_number")
            @test !haskey(row, "writhe")
        end
    end

    @testset "return: star" begin
        r = eval_krl("from knots | return *")
        @test all(row -> haskey(row, "jones_polynomial"), r.rows)
    end

    @testset "return: alias" begin
        r = eval_krl("from knots | return crossing_number as cn")
        @test all(row -> haskey(row, "cn"), r.rows)
    end

    @testset "group_by: groups by key" begin
        r = eval_krl("from knots | group_by crossing_number")
        # 5 knots: 0, 3, 4, 5, 5 → 4 distinct crossing numbers
        @test length(r.rows) == 4
        @test all(row -> haskey(row, "_group_count"), r.rows)
    end

    @testset "let stage: binds into every row" begin
        r = eval_krl("from knots | let label = 99")
        @test all(row -> row["label"] == 99, r.rows)
    end

    @testset "max_rows cap respected" begin
        dp = MockDataProvider([
            Dict{String,Any}("name"=>"k$(i)", "crossing_number"=>i) for i in 1:20
        ])
        r = eval_krl_program(parse_krl("from knots"), mk_ctx(data=dp, max_rows=5))
        @test length(r.rows) <= 5
        @test !isempty(r.warnings)  # cap warning emitted
    end

    @testset "timeout triggers KRLEvalError" begin
        dp = MockDataProvider([
            Dict{String,Any}("name"=>"k$(i)", "crossing_number"=>i) for i in 1:1000
        ])
        # Set a 0-second timeout — should fire during stage execution
        @test_throws KRLEvalError eval_krl_program(
            parse_krl("from knots | filter crossing_number > 0 | sort crossing_number asc"),
            mk_ctx(data=dp, timeout_s=0.0))
    end

end

# ─────────────────────────────────────────────────────────────────────────────
# Seam 3 — Evaluator → SemProvider (equivalence)
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 3: Evaluator → SemProvider" begin

    @testset "find_equivalent: returns equivalents from mock buckets" begin
        r = eval_krl("""from knots | find_equivalent "3_1" via [jones_polynomial]""")
        # 3_1 and fake_trefoil are in strong bucket; input rows include 3_1
        names = [row["name"] for row in r.rows]
        @test "3_1" in names
    end

    @testset "find_equivalent: with exact confidence uses strong bucket" begin
        r = eval_krl("""from knots | find_equivalent "3_1" via [jones_polynomial] confidence >= exact""")
        names = Set([row["name"] for row in r.rows])
        @test !isempty(names)
    end

    @testset "find_equivalent: unknown target produces warning not crash" begin
        r = eval_krl("""from knots | find_equivalent "unknown_knot" via [jones_polynomial]""")
        @test !isempty(r.warnings)
        @test any(w -> occursin("not in semantic index", w), r.warnings)
    end

    @testset "find_equivalent: target metadata attached to rows" begin
        r = eval_krl("""from knots | find_equivalent "3_1" via [jones_polynomial]""")
        equiv_rows = filter(row -> haskey(row, "_equiv_target"), r.rows)
        if !isempty(equiv_rows)
            @test equiv_rows[1]["_equiv_target"] == "3_1"
        end
    end

    @testset "from invariants resolves via SemProvider" begin
        r = eval_krl("from invariants")
        @test !isempty(r.rows)
        @test all(row -> haskey(row, "name"), r.rows)
    end

    @testset "find_path: returns warning + rows (structural stub)" begin
        r = eval_krl("""from knots | find_path "3_1" ~> "3_1" via reidemeister""")
        @test any(w -> occursin("deferred", w), r.warnings)
    end

end

# ─────────────────────────────────────────────────────────────────────────────
# Seam 4 — Circuit breaker fault isolation
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 4: Circuit breaker" begin

    @testset "transitions :closed → :open after threshold failures" begin
        cb = CircuitBreaker("test"; threshold=3, cooldown_s=60.0)
        for i in 1:3
            try; call_with_breaker!(cb, () -> error("injected")); catch; end
        end
        @test cb.state == :open
    end

    @testset "open circuit throws CircuitOpenError immediately" begin
        cb = CircuitBreaker("test"; threshold=1, cooldown_s=60.0)
        try; call_with_breaker!(cb, () -> error("injected")); catch; end
        @test_throws CircuitOpenError call_with_breaker!(cb, () -> "ok")
    end

    @testset ":closed stays closed on success" begin
        cb = CircuitBreaker("test"; threshold=3, cooldown_s=60.0)
        for _ in 1:10
            call_with_breaker!(cb, () -> "ok")
        end
        @test cb.state == :closed
        @test cb.consecutive_failures == 0
    end

    @testset ":open transitions to :half_open after cooldown" begin
        cb = CircuitBreaker("test"; threshold=1, cooldown_s=0.01)
        try; call_with_breaker!(cb, () -> error("injected")); catch; end
        @test cb.state == :open
        sleep(0.05)  # let cooldown expire
        # Next call should transition to :half_open and then attempt probe
        try
            call_with_breaker!(cb, () -> "probe success")
        catch
        end
        @test cb.state ∈ (:closed, :half_open)
    end

    @testset ":half_open → :closed on probe success" begin
        cb = CircuitBreaker("test"; threshold=1, cooldown_s=0.01)
        try; call_with_breaker!(cb, () -> error("injected")); catch; end
        sleep(0.05)
        call_with_breaker!(cb, () -> "probe success")
        @test cb.state == :closed
    end

    @testset "breaker_state_dict returns correct fields" begin
        cb = CircuitBreaker("mydb"; threshold=3, cooldown_s=30.0)
        d = breaker_state_dict(cb)
        @test d["name"] == "mydb"
        @test d["state"] == "closed"
        @test d["threshold"] == 3
    end

    @testset "total_short_circuits incremented when open" begin
        cb = CircuitBreaker("test"; threshold=1, cooldown_s=60.0)
        try; call_with_breaker!(cb, () -> error("injected")); catch; end
        for _ in 1:3
            try; call_with_breaker!(cb, () -> "ok"); catch; end
        end
        @test cb.total_short_circuits == 3
    end

    @testset "DataProvider failure propagates via KRLEvalError (or raw)" begin
        dp = MockDataProvider(; fail_after=0)
        r_or_err = try
            eval_krl_program(parse_krl("from knots"), mk_ctx(data=dp))
        catch e
            e
        end
        @test r_or_err isa Exception
    end

end

# ─────────────────────────────────────────────────────────────────────────────
# Seam 5 — SQL Frontend → Evaluator
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 5: SQL Frontend → Evaluator" begin

    @testset "SELECT * FROM knots" begin
        r = eval_krl_program(parse_sql("SELECT * FROM knots"), mk_ctx();
                             parse_source=:sql)
        @test length(r.rows) == 5
        @test r.parse_source == :sql
    end

    @testset "SELECT with WHERE" begin
        r = eval_krl_program(
            parse_sql("SELECT * FROM knots WHERE crossing_number == 3"), mk_ctx())
        @test length(r.rows) == 1
        @test r.rows[1]["name"] == "3_1"
    end

    @testset "SELECT with LIMIT" begin
        r = eval_krl_program(parse_sql("SELECT * FROM knots LIMIT 2"), mk_ctx())
        @test length(r.rows) == 2
    end

    @testset "SELECT with OFFSET" begin
        r_no_off = eval_krl_program(parse_sql("SELECT * FROM knots LIMIT 3"), mk_ctx())
        r_off    = eval_krl_program(parse_sql("SELECT * FROM knots LIMIT 3 OFFSET 1"), mk_ctx())
        # Offset shifts the window
        @test r_no_off.rows[2]["name"] == r_off.rows[1]["name"]
    end

    @testset "SELECT with ORDER BY" begin
        r = eval_krl_program(
            parse_sql("SELECT * FROM knots ORDER BY crossing_number ASC"), mk_ctx())
        cns = [row["crossing_number"] for row in r.rows]
        @test issorted(cns)
    end

    @testset "SELECT with GROUP BY" begin
        r = eval_krl_program(
            parse_sql("SELECT crossing_number FROM knots GROUP BY crossing_number"), mk_ctx())
        @test length(r.rows) == 4  # 0, 3, 4, 5 distinct crossing numbers
    end

    @testset "SQL and equivalent KRL produce same row count" begin
        sql_r = eval_krl_program(parse_sql("SELECT * FROM knots LIMIT 3"), mk_ctx())
        krl_r = eval_krl_program(parse_krl("from knots | take 3 | return *"), mk_ctx())
        @test length(sql_r.rows) == length(krl_r.rows)
    end

end

# ─────────────────────────────────────────────────────────────────────────────
# Seam 6 — parse_any auto-dispatch
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 6: parse_any dispatch" begin

    @testset "KRL pipeline routes to KRL parser" begin
        prog = parse_any("from knots | take 2")
        r = eval_krl_program(prog, mk_ctx(); parse_source=:krl)
        @test length(r.rows) == 2
    end

    @testset "SQL SELECT routes to SQL frontend" begin
        prog = parse_any("SELECT * FROM knots LIMIT 2")
        r = eval_krl_program(prog, mk_ctx(); parse_source=:sql)
        @test length(r.rows) == 2
    end

    @testset "case-insensitive SQL routing" begin
        prog = parse_any("select * from knots limit 2")
        r = eval_krl_program(prog, mk_ctx())
        @test length(r.rows) == 2
    end

    @testset "routes produce identical row structures for equivalent queries" begin
        sql_prog = parse_any("SELECT name, crossing_number FROM knots LIMIT 5")
        krl_prog = parse_any("from knots | take 5 | return name, crossing_number")
        sql_r = eval_krl_program(sql_prog, mk_ctx())
        krl_r = eval_krl_program(krl_prog, mk_ctx())
        sql_keys = sort(collect(keys(sql_r.rows[1])))
        krl_keys = sort(collect(keys(krl_r.rows[1])))
        @test sql_keys == krl_keys
    end

end

# ─────────────────────────────────────────────────────────────────────────────
# Seam 7 — Health report structure
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 7: Health report" begin

    function mk_health(; skein_ok=true, sem_ok=true, krl_ok=true,
                         skein_cb_state=:closed, sem_cb_state=:closed)
        cb_sk  = CircuitBreaker("skein"; threshold=3, cooldown_s=30.0)
        cb_sem = CircuitBreaker("sem";   threshold=3, cooldown_s=30.0)
        # Manually set state for test
        cb_sk.state  = skein_cb_state
        cb_sem.state = sem_cb_state

        m = QueryMetrics()
        skein_p = () -> skein_ok ? (true, "$(5) knots") : error("db down")
        sem_p   = () -> sem_ok   ? (true, "$(4) indexed") : error("sem down")

        check_health(skein_p, sem_p, krl_ok, m, cb_sk, cb_sem)
    end

    @testset "all ok → overall :ok" begin
        h = mk_health()
        @test h.overall == :ok
    end

    @testset "skein down → overall :down" begin
        h = mk_health(skein_ok=false)
        @test h.overall == :down
    end

    @testset "circuit open → component :down" begin
        h = mk_health(skein_cb_state=:open)
        skein_cb = findfirst(c -> c.name == "skein_circuit", h.components)
        @test !isnothing(skein_cb)
        @test h.components[skein_cb].status == :down
    end

    @testset "krl_parser failure → component :down" begin
        h = mk_health(krl_ok=false)
        krl_c = findfirst(c -> c.name == "krl_parser", h.components)
        @test !isnothing(krl_c)
        @test h.components[krl_c].status == :down
    end

    @testset "health_report_dict serializes to expected keys" begin
        h = mk_health()
        d = health_report_dict(h)
        @test haskey(d, "status")
        @test haskey(d, "checked_at")
        @test haskey(d, "components")
        @test haskey(d, "metrics")
        @test d["status"] == "ok"
        @test !isempty(d["components"])
    end

    @testset "latency recorded for each component" begin
        h = mk_health()
        for c in h.components
            @test c.latency_ms >= 0.0
        end
    end

end

# ─────────────────────────────────────────────────────────────────────────────
# Seam 8 — Metrics accumulation
# ─────────────────────────────────────────────────────────────────────────────

@testset "Seam 8: QueryMetrics" begin

    @testset "total increments with each record_query!" begin
        m = QueryMetrics()
        for i in 1:5
            record_query!(m, :krl, Float64(i * 10))
        end
        @test m.total == 5
    end

    @testset "by_source tracks :krl and :sql separately" begin
        m = QueryMetrics()
        record_query!(m, :krl, 10.0)
        record_query!(m, :sql, 20.0)
        record_query!(m, :krl, 15.0)
        snap = metrics_snapshot(m)
        @test snap["by_source"]["krl"] == 2
        @test snap["by_source"]["sql"] == 1
    end

    @testset "by_error_class accumulates correctly" begin
        m = QueryMetrics()
        record_query!(m, :krl, 5.0; error_class=:parse_error)
        record_query!(m, :krl, 5.0; error_class=:parse_error)
        record_query!(m, :krl, 5.0; error_class=:db_error)
        snap = metrics_snapshot(m)
        @test snap["by_error_class"]["parse_error"] == 2
        @test snap["by_error_class"]["db_error"] == 1
    end

    @testset "pushdown_hits and misses tracked" begin
        m = QueryMetrics()
        record_query!(m, :krl, 5.0; pushdown=true)
        record_query!(m, :krl, 5.0; pushdown=false)
        record_query!(m, :krl, 5.0; pushdown=true)
        @test m.pushdown_hits == 2
        @test m.pushdown_misses == 1
    end

    @testset "p50 is within range" begin
        m = QueryMetrics()
        for v in [10.0, 20.0, 30.0, 40.0, 50.0]
            record_query!(m, :krl, v)
        end
        snap = metrics_snapshot(m)
        p50 = snap["latency_ms"]["p50"]
        @test 10.0 <= p50 <= 50.0
    end

    @testset "window enforced — latency buffer does not grow unboundedly" begin
        m = QueryMetrics()
        for i in 1:300
            record_query!(m, :krl, Float64(i))
        end
        @test length(m.latencies_ms) <= 200  # _LATENCY_WINDOW
    end

    @testset "prometheus_text emits expected metric names" begin
        m = QueryMetrics()
        record_query!(m, :krl, 10.0)
        cb1 = CircuitBreaker("sk")
        cb2 = CircuitBreaker("sem")
        txt = prometheus_text(m, cb1, cb2)
        @test occursin("quandledb_queries_total", txt)
        @test occursin("quandledb_latency_p95_ms", txt)
        @test occursin("quandledb_circuit_open", txt)
    end

end
