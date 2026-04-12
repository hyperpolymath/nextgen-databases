# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
KRL Query Evaluator — translates a `KRLProgram` AST into result rows.

The evaluator operates in a purely functional style over `Vector{Dict{String,Any}}`
rows. It delegates actual data fetching to two pluggable interfaces:

  DataProvider  — abstraction over Skein.DB (allows test injection)
  SemProvider   — abstraction over the semantic sidecar (allows test injection)

This split means:
  - unit tests can inject canned providers without a live Skein database,
  - the server wires in real Skein/SemanticIndex providers with circuit breakers,
  - future WASM or embedded builds can substitute lightweight providers.

Point-to-point tracing:
  Every `eval_krl_program` call returns an `EvalResult` that records:
    - per-stage row counts before and after
    - per-stage wall-clock timings
    - which predicates were pushed down to the data provider
    - any non-fatal warnings (type mismatches, missing fields, etc.)

  Fatal errors throw `KRLEvalError`; non-fatal issues accumulate in `EvalResult.warnings`.

Supported pipeline stages:
  filter       — in-memory predicate evaluation with optional provider pushdown
  sort         — in-memory stable sort (ascending by default)
  take / skip  — slice
  return       — field projection with optional alias
  group_by     — in-memory grouping; keys are evaluated expressions
  aggregate    — count/min/max/avg/sum over grouped or flat rows
  let          — bind an expression result into the row environment
  with         — attach provenance or computed fields to rows
  find_equivalent — semantic index equivalence lookup (strong/weak buckets)
  find_path    — diagram move path search (Reidemeister; stub for full BFS)
  match        — graph pattern match (structural; stub for full pattern engine)
"""

export eval_krl_program, eval_krl_query, EvalContext, EvalResult, KRLEvalError,
       DataProvider, SemProvider, make_eval_context

# ─────────────────────────────────────────────────────────────────────────────
# Errors
# ─────────────────────────────────────────────────────────────────────────────

"""
    KRLEvalError(msg, stage, line, col)

Thrown when a pipeline stage fails fatally (wrong type, unknown field, etc.).
`stage` is a human-readable stage name ("filter", "sort", …) or "" for top-level.
"""
struct KRLEvalError <: Exception
    msg::String
    stage::String
    line::Int
    col::Int
end

Base.showerror(io::IO, e::KRLEvalError) =
    print(io, "KRLEvalError($(e.stage)) at L$(e.line):C$(e.col): $(e.msg)")

# ─────────────────────────────────────────────────────────────────────────────
# Provider interfaces
# ─────────────────────────────────────────────────────────────────────────────

"""
    DataProvider

Abstract type for the Skein DB access layer. Implement the following methods:

  fetch_all(p::DataProvider; kwargs...) -> Vector{Dict{String,Any}}
      Fetch knot rows with optional pushdown filters (crossing_number, writhe, …).

  fetch_one(p::DataProvider, name::String) -> Union{Dict{String,Any}, Nothing}
      Fetch a single knot by name.

  count(p::DataProvider) -> Int
      Return the total number of knots.
"""
abstract type DataProvider end

"""
    SemProvider

Abstract type for the semantic sidecar access layer.

  equiv_buckets(p::SemProvider, name::String) -> Union{NamedTuple, Nothing}
      Return (strong=Vector, weak=Vector) equivalence buckets for a knot name.
      Returns `nothing` if the knot is not in the semantic index.
"""
abstract type SemProvider end

# ─────────────────────────────────────────────────────────────────────────────
# Pushdown parameter extraction
# ─────────────────────────────────────────────────────────────────────────────

"""
    PushdownHints

Fields that can be passed directly to the DataProvider's `fetch_all` to reduce
the number of rows returned. All fields are `nothing` when no pushdown applies.
"""
mutable struct PushdownHints
    crossing_number::Union{Int, Nothing}
    writhe::Union{Int, Nothing}
    genus::Union{Int, Nothing}
    determinant::Union{Int, Nothing}
    signature::Union{Int, Nothing}
    name_like::Union{String, Nothing}
    limit::Union{Int, Nothing}
    offset::Union{Int, Nothing}
end

PushdownHints() = PushdownHints(nothing, nothing, nothing, nothing,
                                nothing, nothing, nothing, nothing)

"""
    extract_pushdown!(hints::PushdownHints, expr::KRLExpr) -> residual::KRLExpr

Walk `expr` extracting equality predicates on pushdown-eligible fields into
`hints`. Returns the residual predicate (what could not be pushed down) — may
be `nothing` if everything was consumed.

Only simple `field == literal` or `field == knot_name` patterns are extracted.
"""
function extract_pushdown!(hints::PushdownHints,
                           expr::KRLExpr)::Union{KRLExpr, Nothing}
    # AND: try to push down both sides; combine residuals
    if expr isa KRLAnd
        lres = extract_pushdown!(hints, expr.left)
        rres = extract_pushdown!(hints, expr.right)
        return if isnothing(lres) && isnothing(rres); nothing
               elseif isnothing(lres); rres
               elseif isnothing(rres); lres
               else KRLAnd(lres, rres, expr.line, expr.col)
               end
    end

    # Simple equality: (var == literal)
    if expr isa KRLCompare && expr.op == :eq
        name = nothing
        val  = nothing

        if expr.left isa KRLVar && (expr.right isa KRLInt || expr.right isa KRLString ||
                                    expr.right isa KRLKnotName)
            name = expr.left.name
            val  = _literal_value(expr.right)
        elseif expr.right isa KRLVar && (expr.left isa KRLInt || expr.left isa KRLString ||
                                         expr.left isa KRLKnotName)
            name = expr.right.name
            val  = _literal_value(expr.left)
        end

        if !isnothing(name)
            pushed = _try_push!(hints, name, val)
            return pushed ? nothing : expr
        end
    end

    expr  # not pushable
end

function _literal_value(e::KRLExpr)
    e isa KRLInt      && return e.n
    e isa KRLFloat    && return e.x
    e isa KRLString   && return e.s
    e isa KRLKnotName && return e.name
    nothing
end

function _try_push!(h::PushdownHints, field::String, val)
    field == "crossing_number" && val isa Int && (h.crossing_number = val; return true)
    field == "writhe"          && val isa Int && (h.writhe = val; return true)
    field == "genus"           && val isa Int && (h.genus = val; return true)
    field == "determinant"     && val isa Int && (h.determinant = val; return true)
    field == "signature"       && val isa Int && (h.signature = val; return true)
    field == "name"            && val isa String && (h.name_like = val; return true)
    false
end

# ─────────────────────────────────────────────────────────────────────────────
# Eval context
# ─────────────────────────────────────────────────────────────────────────────

"""
    EvalContext

Carries all external dependencies needed during evaluation.

  data     — pluggable data provider (Skein or mock)
  sem      — pluggable semantic provider
  bindings — let-bound variable values, accumulated during evaluation
  max_rows — hard cap on rows at any stage (default 50 000)
  timeout_s — per-query timeout in seconds (default 30)
"""
mutable struct EvalContext
    data::DataProvider
    sem::SemProvider
    bindings::Dict{String, Any}
    max_rows::Int
    timeout_s::Float64
    start_time::Float64   # set at eval_krl_program entry
end

function make_eval_context(data::DataProvider, sem::SemProvider;
                           max_rows::Int = 50_000,
                           timeout_s::Float64 = 30.0)
    EvalContext(data, sem, Dict{String,Any}(), max_rows, timeout_s, 0.0)
end

# ─────────────────────────────────────────────────────────────────────────────
# Eval result and tracing
# ─────────────────────────────────────────────────────────────────────────────

"""
    StageTrace(stage_name, rows_in, rows_out, elapsed_ms, note)

One record in the point-to-point trace.
"""
struct StageTrace
    stage_name::String
    rows_in::Int
    rows_out::Int
    elapsed_ms::Float64
    note::String
end

"""
    EvalResult(rows, traces, warnings, pushdown_used, parse_source)

Returned by `eval_krl_program`. Contains result rows plus full diagnostics.
"""
struct EvalResult
    rows::Vector{Dict{String, Any}}
    traces::Vector{StageTrace}
    warnings::Vector{String}
    pushdown_used::Bool
    parse_source::Symbol       # :krl or :sql
end

function eval_result_summary(r::EvalResult)::Dict{String, Any}
    Dict{String, Any}(
        "count"         => length(r.rows),
        "pushdown_used" => r.pushdown_used,
        "parse_source"  => string(r.parse_source),
        "warnings"      => r.warnings,
        "trace"         => [Dict{String,Any}(
            "stage"       => t.stage_name,
            "rows_in"     => t.rows_in,
            "rows_out"    => t.rows_out,
            "elapsed_ms"  => round(t.elapsed_ms, digits = 2),
            "note"        => t.note,
        ) for t in r.traces],
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Top-level entry
# ─────────────────────────────────────────────────────────────────────────────

"""
    eval_krl_program(prog::KRLProgram, ctx::EvalContext; parse_source=:krl) -> EvalResult

Evaluate a `KRLProgram` and return an `EvalResult`.

Only `KRLQueryStmt` and `KRLLetStmt` are directly evaluated; `KRLRuleDef` and
`KRLAxiomDef` are registered for future resolution but do not produce rows.
"""
function eval_krl_program(prog::KRLProgram, ctx::EvalContext;
                          parse_source::Symbol = :krl)::EvalResult
    ctx.start_time = time()
    traces   = StageTrace[]
    warnings = String[]
    rows     = Dict{String, Any}[]
    pushdown = false

    for stmt in prog.statements
        if stmt isa KRLQueryStmt
            result_rows, stage_traces, stmt_pushdown, stmt_warns =
                _eval_query(stmt.query, ctx)
            append!(traces, stage_traces)
            append!(warnings, stmt_warns)
            rows = result_rows
            pushdown = pushdown || stmt_pushdown

        elseif stmt isa KRLLetStmt
            t0 = time()
            val = _eval_expr(stmt.expr, Dict{String,Any}(), ctx)
            ctx.bindings[stmt.name] = val
            push!(traces, StageTrace("let:$(stmt.name)", 0, 0,
                                     (time()-t0)*1000, "bound"))
        elseif stmt isa KRLRuleDef
            push!(warnings, "rule $(stmt.name) registered (evaluation of rules deferred)")
        elseif stmt isa KRLAxiomDef
            push!(warnings, "axiom $(stmt.name) registered (proof checking deferred)")
        else
            push!(warnings, "unrecognised statement type $(typeof(stmt)) — skipped")
        end
    end

    EvalResult(rows, traces, warnings, pushdown, parse_source)
end

# ─────────────────────────────────────────────────────────────────────────────
# Query evaluation
# ─────────────────────────────────────────────────────────────────────────────

function _eval_query(query::KRLQuery, ctx::EvalContext)
    traces   = StageTrace[]
    warnings = String[]
    pushdown = false

    # ── Resolve source ──────────────────────────────────────────────────────
    src_t0 = time()
    rows, src_pushdown, src_note = _resolve_source(query.source, ctx, query.stages)
    pushdown = src_pushdown
    push!(traces, StageTrace("source:$(typeof(query.source).name.name)",
                             0, length(rows),
                             (time()-src_t0)*1000, src_note))

    # ── Apply stages ────────────────────────────────────────────────────────
    for stage in query.stages
        _check_timeout(ctx)
        n_in = length(rows)
        t0   = time()

        rows, note, stage_warns = _apply_stage(rows, stage, ctx)
        append!(warnings, stage_warns)
        push!(traces, StageTrace(_stage_name(stage), n_in, length(rows),
                                 (time()-t0)*1000, note))

        if length(rows) > ctx.max_rows
            resize!(rows, ctx.max_rows)
            push!(warnings, "row cap $(ctx.max_rows) applied after stage $(_stage_name(stage))")
        end
    end

    rows, traces, pushdown, warnings
end

function _check_timeout(ctx::EvalContext)
    elapsed = time() - ctx.start_time
    if elapsed > ctx.timeout_s
        throw(KRLEvalError(
            "query exceeded timeout of $(ctx.timeout_s)s ($(round(elapsed, digits=1))s elapsed)",
            "timeout", 0, 0))
    end
end

function _stage_name(s::KRLPipeStage)
    s isa KRLFilterStage    && return "filter"
    s isa KRLSortStage      && return "sort"
    s isa KRLTakeStage      && return "take"
    s isa KRLSkipStage      && return "skip"
    s isa KRLReturnStage    && return "return"
    s isa KRLGroupByStage   && return "group_by"
    s isa KRLAggregateStage && return "aggregate"
    s isa KRLFindEquivStage && return "find_equivalent"
    s isa KRLFindPathStage  && return "find_path"
    s isa KRLMatchStage     && return "match"
    s isa KRLLetStage       && return "let"
    s isa KRLWithStage      && return "with"
    string(typeof(s).name.name)
end

# ─────────────────────────────────────────────────────────────────────────────
# Source resolution
# ─────────────────────────────────────────────────────────────────────────────

"""
Resolve a `KRLSource` into an initial row set.

For `KRLSourceKnots`, `KRLSourceDiagrams`, and `KRLSourceInvariants`, examine
the following `filter` stage (if present) to extract pushdown predicates.
"""
function _resolve_source(src::KRLSource,
                         ctx::EvalContext,
                         stages::Vector{KRLPipeStage})
    if src isa KRLSourceKnots || src isa KRLSourceDiagrams
        return _resolve_skein_source(ctx, stages)
    elseif src isa KRLSourceInvariants
        return _resolve_invariants_source(ctx)
    elseif src isa KRLSourceNamed
        if haskey(ctx.bindings, src.name)
            rows = _to_row_vec(ctx.bindings[src.name])
            alias = src.alias
            if !isnothing(alias)
                rows = [Dict{String,Any}(alias => r, k => v for (k,v) in r) for r in rows]
            end
            return rows, false, "from binding $(src.name)"
        else
            throw(KRLEvalError("undefined source: $(src.name)", "source", src.line, src.col))
        end
    elseif src isa KRLSourceSubquery
        sub_rows, _, _, _ = _eval_query(src.query, ctx)
        return sub_rows, false, "subquery"
    end
    throw(KRLEvalError("unsupported source type: $(typeof(src))", "source", 0, 0))
end

function _resolve_skein_source(ctx::EvalContext, stages::Vector{KRLPipeStage})
    hints = PushdownHints()
    note  = "full scan"

    # Peek at the first filter stage for pushdown opportunities
    first_filter = findfirst(s -> s isa KRLFilterStage, stages)
    if !isnothing(first_filter)
        residual = extract_pushdown!(hints, stages[first_filter].pred)
        if residual !== stages[first_filter].pred
            note = "pushdown: cn=$(hints.crossing_number) writhe=$(hints.writhe)"
        end
    end

    rows = fetch_all(ctx.data;
                     crossing_number = hints.crossing_number,
                     writhe          = hints.writhe,
                     genus           = hints.genus,
                     determinant     = hints.determinant,
                     signature       = hints.signature,
                     name_like       = hints.name_like,
                     limit           = something(hints.limit, ctx.max_rows))
    pushdown_used = note != "full scan"
    rows, pushdown_used, note
end

function _resolve_invariants_source(ctx::EvalContext)
    rows = fetch_invariants(ctx.sem)
    rows, false, "semantic index scan"
end

function _to_row_vec(v)
    v isa Vector{Dict{String,Any}} && return v
    v isa Dict{String,Any}         && return [v]
    throw(KRLEvalError("binding is not a row or row-set: $(typeof(v))", "source", 0, 0))
end

# ─────────────────────────────────────────────────────────────────────────────
# Stage dispatch
# ─────────────────────────────────────────────────────────────────────────────

function _apply_stage(rows::Vector{Dict{String,Any}},
                      stage::KRLPipeStage,
                      ctx::EvalContext)
    stage isa KRLFilterStage    && return _apply_filter(rows, stage, ctx)
    stage isa KRLSortStage      && return _apply_sort(rows, stage, ctx)
    stage isa KRLTakeStage      && return _apply_take(rows, stage)
    stage isa KRLSkipStage      && return _apply_skip(rows, stage)
    stage isa KRLReturnStage    && return _apply_return(rows, stage, ctx)
    stage isa KRLGroupByStage   && return _apply_group_by(rows, stage, ctx)
    stage isa KRLAggregateStage && return _apply_aggregate(rows, stage, ctx)
    stage isa KRLFindEquivStage && return _apply_find_equiv(rows, stage, ctx)
    stage isa KRLFindPathStage  && return _apply_find_path(rows, stage, ctx)
    stage isa KRLMatchStage     && return _apply_match(rows, stage, ctx)
    stage isa KRLLetStage       && return _apply_let(rows, stage, ctx)
    stage isa KRLWithStage      && return _apply_with(rows, stage, ctx)
    throw(KRLEvalError("unimplemented stage: $(typeof(stage))", _stage_name(stage),
                       stage.line, stage.col))
end

# ── filter ───────────────────────────────────────────────────────────────────

function _apply_filter(rows, stage::KRLFilterStage, ctx)
    warns = String[]
    result = Dict{String, Any}[]
    for row in rows
        try
            val = _eval_expr(stage.pred, row, ctx)
            if val === true; push!(result, row); end
        catch e
            push!(warns, "filter row skipped: $e")
        end
    end
    result, "$(length(rows)) → $(length(result))", warns
end

# ── sort ─────────────────────────────────────────────────────────────────────

function _apply_sort(rows, stage::KRLSortStage, ctx)
    isempty(rows) && return rows, "empty", String[]

    sorted = sort(rows; lt = (a, b) -> begin
        for (expr, ord) in stage.items
            va = _eval_expr_safe(expr, a, ctx)
            vb = _eval_expr_safe(expr, b, ctx)
            cmp = _compare_values(va, vb)
            cmp == 0 && continue
            return ord == SortAsc ? cmp < 0 : cmp > 0
        end
        false
    end, alg = Base.Sort.MergeSort)

    sorted, "stable sort $(length(rows)) rows", String[]
end

function _compare_values(a, b)
    try; isless(a, b) ? -1 : isless(b, a) ? 1 : 0
    catch; 0; end
end

# ── take / skip ───────────────────────────────────────────────────────────────

function _apply_take(rows, stage::KRLTakeStage)
    n    = min(stage.n, length(rows))
    note = "$(length(rows)) → $n"
    rows[1:n], note, String[]
end

function _apply_skip(rows, stage::KRLSkipStage)
    n    = min(stage.n, length(rows))
    result = rows[n+1:end]
    result, "skipped $n of $(length(rows))", String[]
end

# ── return ───────────────────────────────────────────────────────────────────

function _apply_return(rows, stage::KRLReturnStage, ctx)
    warns = String[]
    result = map(rows) do row
        d = Dict{String, Any}()
        for item in stage.items
            if item isa KRLReturnStar
                merge!(d, row)
            elseif item isa KRLReturnExpr
                val = _eval_expr_safe(item.expr, row, ctx)
                key = something(item.alias, _expr_display_key(item.expr))
                d[key] = val
            elseif item isa KRLReturnEquivs
                d["equivalences"] = get(row, "_equivalences", nothing)
            elseif item isa KRLReturnEquivClass
                d["equiv_class"] = get(row, "_equiv_class", nothing)
            elseif item isa KRLReturnProof
                d["proof"] = get(row, "_proof", nothing)
            else
                push!(warns, "unrecognised return item type $(typeof(item)) — skipped")
            end
        end
        if stage.with_provenance
            d["_provenance"] = get(row, "_provenance", nothing)
        end
        d
    end
    result, "projected $(length(result)) rows", warns
end

function _expr_display_key(e::KRLExpr)
    e isa KRLVar         && return e.name
    e isa KRLFieldAccess && return e.field
    e isa KRLCall        && (e.func isa KRLVar) && return e.func.name
    "_col"
end

# ── group_by ─────────────────────────────────────────────────────────────────

function _apply_group_by(rows, stage::KRLGroupByStage, ctx)
    groups = Dict{Any, Vector{Dict{String,Any}}}()
    for row in rows
        key = Tuple(_eval_expr_safe(k, row, ctx) for k in stage.keys)
        push!(get!(groups, key, Dict{String,Any}[]), row)
    end
    # Flatten: each group becomes one row with _group_rows
    result = [begin
        rep = copy(first(grp))
        rep["_group_rows"] = grp
        rep["_group_count"] = length(grp)
        rep
    end for grp in values(groups)]
    result, "$(length(rows)) rows → $(length(result)) groups", String[]
end

# ── aggregate ────────────────────────────────────────────────────────────────

function _apply_aggregate(rows, stage::KRLAggregateStage, ctx)
    warns = String[]
    result = map(rows) do row
        group = get(row, "_group_rows", [row])
        d = copy(row)
        for item in stage.items
            vals = [_eval_expr_safe(item.arg, r, ctx) for r in group]
            vals = filter(!isnothing, vals)
            val = _aggregate_fn(item.fn, vals)
            key = something(item.alias, string(item.fn))
            d[key] = val
        end
        d
    end
    result, "aggregated $(length(result)) groups", warns
end

function _aggregate_fn(fn::Symbol, vals::Vector)
    isempty(vals) && return nothing
    fn == :count && return length(vals)
    fn == :min   && return minimum(vals; init = nothing)
    fn == :max   && return maximum(vals; init = nothing)
    fn == :sum   && return sum(vals)
    fn == :avg   && return sum(vals) / length(vals)
    nothing
end

# ── find_equivalent ───────────────────────────────────────────────────────────

function _apply_find_equiv(rows, stage::KRLFindEquivStage, ctx)
    warns = String[]
    result = Dict{String, Any}[]

    # Evaluate target expression to get a knot name string
    target_val = _eval_expr_safe(stage.target, Dict{String,Any}(), ctx)
    target_name = string(target_val)

    buckets = equiv_buckets(ctx.sem, target_name)
    if isnothing(buckets)
        push!(warns, "find_equivalent: '$target_name' not in semantic index — no equivalents found")
        return result, "0 equivalents (not indexed)", warns
    end

    # Select candidate set based on confidence
    conf = something(stage.min_confidence, ConfHeuristic)
    candidates = if conf == ConfExact || conf == ConfSufficient
        buckets.strong
    else
        buckets.weak
    end

    # Attach equivalence metadata to each matching row
    candidate_names = Set(candidates)
    for row in rows
        row_name = get(row, "name", nothing)
        if !isnothing(row_name) && row_name in candidate_names
            r = copy(row)
            r["_equiv_target"]     = target_name
            r["_equiv_confidence"] = string(conf)
            r["_equiv_class"]      = buckets.strong
            push!(result, r)
        end
    end

    # If no rows were in the input (bare find_equivalent), emit one row per candidate
    if isempty(rows)
        for name in candidates
            push!(result, Dict{String,Any}(
                "name"                => name,
                "_equiv_target"       => target_name,
                "_equiv_confidence"   => string(conf),
            ))
        end
    end

    note = "$(length(result)) equivalents of '$target_name' (confidence >= $(conf))"
    result, note, warns
end

# ── find_path ────────────────────────────────────────────────────────────────

function _apply_find_path(rows, stage::KRLFindPathStage, ctx)
    warns = String[]
    push!(warns, "find_path: full BFS path search deferred (returns structural candidates only)")

    src_val  = _eval_expr_safe(stage.source_expr, Dict{String,Any}(), ctx)
    tgt_val  = _eval_expr_safe(stage.target,      Dict{String,Any}(), ctx)
    method   = stage.method

    # Structural stub: return rows that share a descriptor_hash with the target
    target_name = string(tgt_val)
    buckets = equiv_buckets(ctx.sem, target_name)
    if isnothing(buckets)
        push!(warns, "find_path: '$target_name' not indexed — no path candidates")
        return rows, "0 path candidates", warns
    end

    cands = Set(buckets.strong)
    result = [begin
        r = copy(row)
        r["_path_source"] = string(src_val)
        r["_path_target"] = target_name
        r["_path_method"] = string(method)
        r["_path_note"]   = "structural (BFS deferred)"
        r
    end for row in rows if get(row, "name", "") in cands]

    result, "$(length(result)) path candidates (structural)", warns
end

# ── match ─────────────────────────────────────────────────────────────────────

function _apply_match(rows, stage::KRLMatchStage, ctx)
    warns = String[]
    push!(warns, "match: full graph pattern engine deferred — returning all rows unfiltered")
    rows, "graph pattern match (deferred)", warns
end

# ── let (stage) ───────────────────────────────────────────────────────────────

function _apply_let(rows, stage::KRLLetStage, ctx)
    val = _eval_expr_safe(stage.expr, Dict{String,Any}(), ctx)
    ctx.bindings[stage.name] = val
    result = [begin r = copy(row); r[stage.name] = val; r end for row in rows]
    result, "bound $(stage.name)", String[]
end

# ── with ──────────────────────────────────────────────────────────────────────

function _apply_with(rows, stage::KRLWithStage, ctx)
    warns = String[]
    result = map(rows) do row
        r = copy(row)
        for mod in stage.modifiers
            if mod isa Symbol && mod == :provenance
                r["_provenance"] = Dict{String,Any}(
                    "source"  => get(r, "_source", "unknown"),
                    "indexed" => get(r, "indexed_at", nothing),
                )
            elseif mod isa Pair{String, KRLExpr}
                name, expr = mod
                r[name] = _eval_expr_safe(expr, r, ctx)
            else
                push!(warns, "with: unrecognised modifier type $(typeof(mod)) — skipped")
            end
        end
        r
    end
    result, "with modifiers applied", warns
end

# ─────────────────────────────────────────────────────────────────────────────
# Expression evaluator
# ─────────────────────────────────────────────────────────────────────────────

"""
    _eval_expr(expr, row, ctx) -> Any

Evaluate a KRL expression against a single row (Dict{String,Any}).
Throws `KRLEvalError` on type errors or missing fields.
"""
function _eval_expr(expr::KRLExpr, row::Dict{String,Any}, ctx::EvalContext)
    # Literals
    expr isa KRLInt      && return expr.n
    expr isa KRLFloat    && return expr.x
    expr isa KRLString   && return expr.s
    expr isa KRLBool     && return expr.b
    expr isa KRLNone     && return nothing
    expr isa KRLKnotName && return expr.name

    # Variables / field access
    if expr isa KRLVar
        # Row fields first, then let bindings
        haskey(row, expr.name)         && return row[expr.name]
        haskey(ctx.bindings, expr.name) && return ctx.bindings[expr.name]
        return nothing  # missing field → none (warn in safe wrapper)
    end

    if expr isa KRLFieldAccess
        obj = _eval_expr(expr.obj, row, ctx)
        obj isa Dict && return get(obj, expr.field, nothing)
        throw(KRLEvalError("field access on non-dict: $(typeof(obj))",
                           "expression", expr.line, expr.col))
    end

    # Logical
    if expr isa KRLNot
        v = _eval_expr(expr.operand, row, ctx)
        v isa Bool && return !v
        throw(KRLEvalError("not requires Bool, got $(typeof(v))",
                           "not", expr.line, expr.col))
    end
    if expr isa KRLAnd
        l = _eval_expr(expr.left, row, ctx)
        l isa Bool && !l && return false   # short-circuit
        r = _eval_expr(expr.right, row, ctx)
        l isa Bool && r isa Bool && return l && r
        throw(KRLEvalError("and requires Bool operands", "and", expr.line, expr.col))
    end
    if expr isa KRLOr
        l = _eval_expr(expr.left, row, ctx)
        l isa Bool && l && return true     # short-circuit
        r = _eval_expr(expr.right, row, ctx)
        l isa Bool && r isa Bool && return l || r
        throw(KRLEvalError("or requires Bool operands", "or", expr.line, expr.col))
    end

    # Null coalesce
    if expr isa KRLNullCoalesce
        l = _eval_expr(expr.left, row, ctx)
        return isnothing(l) ? _eval_expr(expr.right, row, ctx) : l
    end

    # Comparison
    if expr isa KRLCompare
        l = _eval_expr(expr.left,  row, ctx)
        r = _eval_expr(expr.right, row, ctx)
        return _eval_compare(expr.op, l, r, expr.line, expr.col)
    end

    # Arithmetic
    if expr isa KRLBinOp
        l = _eval_expr(expr.left,  row, ctx)
        r = _eval_expr(expr.right, row, ctx)
        return _eval_binop(expr.op, l, r, expr.line, expr.col)
    end

    # Unary minus
    if expr isa KRLUnaryNeg
        v = _eval_expr(expr.operand, row, ctx)
        v isa Number && return -v
        throw(KRLEvalError("unary minus on non-number: $(typeof(v))",
                           "expression", expr.line, expr.col))
    end

    # Type annotation — evaluates the inner expression (runtime cast is a no-op here)
    if expr isa KRLTypeAnn
        return _eval_expr(expr.expr, row, ctx)
    end

    # Array literal
    if expr isa KRLArray
        return [_eval_expr(e, row, ctx) for e in expr.elems]
    end

    # Record literal
    if expr isa KRLRecord
        return Dict{String,Any}(k => _eval_expr(v, row, ctx) for (k,v) in expr.fields)
    end

    # Index
    if expr isa KRLIndex
        obj = _eval_expr(expr.obj,   row, ctx)
        idx = _eval_expr(expr.index, row, ctx)
        obj isa Vector && idx isa Int && 1 <= idx <= length(obj) && return obj[idx]
        obj isa Dict   && idx isa String && return get(obj, idx, nothing)
        return nothing
    end

    # Function call
    if expr isa KRLCall
        func_val = expr.func isa KRLVar ? expr.func.name : nothing
        args = [_eval_expr(a, row, ctx) for a in expr.args]
        return _eval_call(func_val, args, expr.line, expr.col)
    end

    # Gauss code literal — return as vector of ints
    expr isa KRLGaussCode && return expr.codes

    throw(KRLEvalError("unimplemented expression type: $(typeof(expr))",
                       "expression", expr.line, expr.col))
end

function _eval_compare(op::Symbol, l, r, line, col)
    op == :eq  && return isequal(l, r)
    op == :neq && return !isequal(l, r)
    op == :lt  && return _cmp_or_nothing(l, r) == -1
    op == :lte && return let c = _cmp_or_nothing(l, r); c == -1 || c == 0; end
    op == :gt  && return _cmp_or_nothing(l, r) == 1
    op == :gte && return let c = _cmp_or_nothing(l, r); c == 1 || c == 0; end
    op == :iso && return isequal(l, r)   # runtime quandle iso — structural equiv here
    op == :in  && return r isa AbstractVector ? l in r : false
    throw(KRLEvalError("unknown comparison op: $op", "comparison", line, col))
end

function _cmp_or_nothing(a, b)
    try; isless(a, b) ? -1 : isless(b, a) ? 1 : 0
    catch; 0
    end
end

function _eval_binop(op::Symbol, l, r, line, col)
    op == :add && return l + r
    op == :sub && return l - r
    op == :mul && return l * r
    op == :div && r == 0 && throw(KRLEvalError("division by zero", "arithmetic", line, col))
    op == :div && return l / r
    op == :mod && r == 0 && throw(KRLEvalError("mod by zero", "arithmetic", line, col))
    op == :mod && return l % r
    throw(KRLEvalError("unknown binary op: $op", "arithmetic", line, col))
end

const _BUILTIN_FNS = Dict{String, Function}(
    "abs"     => x -> abs(x[1]),
    "floor"   => x -> floor(Int, x[1]),
    "ceil"    => x -> ceil(Int, x[1]),
    "min"     => x -> minimum(x),
    "max"     => x -> maximum(x),
    "length"  => x -> length(x[1]),
    "concat"  => x -> join(x, ""),
    "string"  => x -> string(x[1]),
    "int"     => x -> Int(x[1]),
    "float"   => x -> Float64(x[1]),
    "is_none" => x -> isnothing(x[1]),
    "not"     => x -> !x[1],
)

function _eval_call(name::Union{String,Nothing}, args::Vector, line, col)
    isnothing(name) &&
        throw(KRLEvalError("call to non-identifier function expression", "call", line, col))
    f = get(_BUILTIN_FNS, name, nothing)
    !isnothing(f) && return f(args)
    throw(KRLEvalError("unknown function: $name", "call", line, col))
end

function _eval_expr_safe(expr::KRLExpr, row::Dict{String,Any}, ctx::EvalContext)
    try; _eval_expr(expr, row, ctx)
    catch; nothing
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# DataProvider interface methods (to be implemented by callers)
# ─────────────────────────────────────────────────────────────────────────────

# Callers define concrete subtypes and implement these methods.
# The server does this in serve.jl using Skein + circuit breaker.

function fetch_all(p::DataProvider; kwargs...)
    error("fetch_all not implemented for $(typeof(p))")
end

function fetch_one(p::DataProvider, name::String)
    error("fetch_one not implemented for $(typeof(p))")
end

function count(p::DataProvider)
    error("count not implemented for $(typeof(p))")
end

# ─────────────────────────────────────────────────────────────────────────────
# SemProvider interface methods
# ─────────────────────────────────────────────────────────────────────────────

function equiv_buckets(p::SemProvider, name::String)
    error("equiv_buckets not implemented for $(typeof(p))")
end

function fetch_invariants(p::SemProvider)
    error("fetch_invariants not implemented for $(typeof(p))")
end
