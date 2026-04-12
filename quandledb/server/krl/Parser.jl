# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
KRL Recursive-Descent Parser (QuandleDB Knot Resolution Language).

Converts a `Vector{Token}` (from Lexer.jl) into a `KRLProgram` AST (Ast.jl).
Follows grammar.ebnf v0.1.0 exactly.

Entry points:
  `parse_krl(src::String) -> KRLProgram`  — lex + parse a KRL source string
  `parse_krl_query(src::String) -> KRLQuery` — convenience: exactly one query

Innovations vs KRLAdapter.jl:
  - Pipeline error recovery: errors inside a pipeline stage are collected and
    stored in the `ParseResult`; parsing continues at the next `|` boundary.
    This enables IDE "show all errors" mode rather than abort-on-first.
  - `parse_any(src)` detects SQL vs KRL by checking for leading SELECT/WITH keywords.
  - Gauss code validation at parse time: non-empty, no zero values.
  - `in` as a comparison-level binary operator (for `| filter x in collection`).
  - Type annotations parsed as first-class AST nodes (not just strings).
"""

export parse_krl, parse_krl_query, parse_any, KRLParseError

# ─────────────────────────────────────────────────────────────────────────────
# Parse error
# ─────────────────────────────────────────────────────────────────────────────

"""
    KRLParseError(msg, line, col)

Thrown when the token stream does not match the grammar.
"""
struct KRLParseError <: Exception
    msg::String
    line::Int
    col::Int
end

Base.showerror(io::IO, e::KRLParseError) =
    print(io, "KRLParseError at L$(e.line):C$(e.col): $(e.msg)")

# ─────────────────────────────────────────────────────────────────────────────
# Parser state
# ─────────────────────────────────────────────────────────────────────────────

"""
    ParserState

Mutable cursor over a `Vector{Token}`. Carries a recoverable error list so
the parser can continue after pipeline-stage errors.
"""
mutable struct ParserState
    tokens::Vector{Token}
    pos::Int                      # next-to-consume index
    errors::Vector{KRLParseError} # accumulated non-fatal errors
end

ParserState(tokens::Vector{Token}) = ParserState(tokens, 1, KRLParseError[])

_peek(ps::ParserState)::Token         = ps.tokens[ps.pos]
_peek2(ps::ParserState)::Token        = ps.tokens[min(ps.pos + 1, length(ps.tokens))]
_at_eof(ps::ParserState)::Bool        = _peek(ps).kind == :eof

function _advance!(ps::ParserState)::Token
    t = ps.tokens[ps.pos]
    ps.pos = min(ps.pos + 1, length(ps.tokens))
    t
end

"""
Consume if current token has `kind` (and optionally `value`). Throws `KRLParseError`.
"""
function _expect!(ps::ParserState, kind::Symbol,
                  value::Union{String, Nothing} = nothing)::Token
    t = _peek(ps)
    ok = t.kind == kind && (isnothing(value) || t.value == value)
    if !ok
        exp = isnothing(value) ? string(kind) : "$(kind)($(repr(value)))"
        got = t.kind == :eof ? "end-of-file" : "$(t.kind)($(repr(t.value)))"
        throw(KRLParseError("expected $exp, got $got", t.line, t.col))
    end
    _advance!(ps)
end

"""
Consume and return `true` if current token matches; otherwise return `false`.
"""
function _match!(ps::ParserState, kind::Symbol,
                 value::Union{String, Nothing} = nothing)::Bool
    t = _peek(ps)
    if t.kind == kind && (isnothing(value) || t.value == value)
        _advance!(ps); return true
    end
    false
end

"""
Predicate: current token is keyword `kw`.
"""
_kw(ps::ParserState, kw::String)::Bool =
    _peek(ps).kind == :keyword && _peek(ps).value == kw

"""
Predicate: current token has kind `k`.
"""
_is(ps::ParserState, k::Symbol)::Bool = _peek(ps).kind == k

# ─────────────────────────────────────────────────────────────────────────────
# Entry points
# ─────────────────────────────────────────────────────────────────────────────

"""
    parse_krl(src::String) -> KRLProgram

Lex and parse a KRL source string. Returns a `KRLProgram` AST.
Throws `KRLLexError` on invalid characters, `KRLParseError` on grammar violations.
"""
function parse_krl(src::String)::KRLProgram
    tokens = tokenise(src)
    ps     = ParserState(tokens)
    prog   = _parse_program(ps)
    isempty(ps.errors) || throw(first(ps.errors))
    prog
end

"""
    parse_krl_query(src::String) -> KRLQuery

Convenience: parse `src` as exactly one pipeline query.
Throws if the source contains anything other than a single `from … | …` query.
"""
function parse_krl_query(src::String)::KRLQuery
    prog = parse_krl(src)
    length(prog.statements) == 1 ||
        throw(KRLParseError("expected exactly one query, got $(length(prog.statements)) statements",
                            prog.line, prog.col))
    stmt = prog.statements[1]
    stmt isa KRLQueryStmt ||
        throw(KRLParseError("expected a pipeline query, got $(typeof(stmt))",
                            stmt.line, stmt.col))
    stmt.query
end

"""
    parse_any(src::String) -> KRLProgram

Auto-detect SQL vs KRL and dispatch accordingly.
SQL is identified by a leading `SELECT` or `WITH` keyword (case-insensitive).
"""
function parse_any(src::String)::KRLProgram
    stripped = lstrip(src)
    if occursin(r"^(SELECT|WITH)\b"i, stripped)
        return parse_sql(src)
    end
    parse_krl(src)
end

# ─────────────────────────────────────────────────────────────────────────────
# Program
# ─────────────────────────────────────────────────────────────────────────────

function _parse_program(ps::ParserState)::KRLProgram
    sl, sc = _peek(ps).line, _peek(ps).col
    stmts  = KRLStatement[]
    while !_at_eof(ps)
        push!(stmts, _parse_statement(ps))
    end
    KRLProgram(stmts, sl, sc)
end

# ─────────────────────────────────────────────────────────────────────────────
# Statements
# ─────────────────────────────────────────────────────────────────────────────

function _parse_statement(ps::ParserState)::KRLStatement
    t = _peek(ps)

    # rule <name>(params) :- body
    _kw(ps, "rule")  && return _parse_rule_def(ps)

    # axiom <name> : …
    _kw(ps, "axiom") && return _parse_axiom_def(ps)

    # let <name> [: type] = expr     (top-level binding, no pipeline pipe follows)
    if _kw(ps, "let")
        return _parse_let_stmt(ps)
    end

    # from … | … (pipeline query)
    if _kw(ps, "from")
        q = _parse_query(ps)
        return KRLQueryStmt(q, q.line, q.col)
    end

    t = _peek(ps)
    throw(KRLParseError(
        "expected statement (from/let/rule/axiom), got $(t.kind)($(repr(t.value)))",
        t.line, t.col))
end

function _parse_let_stmt(ps::ParserState)::KRLLetStmt
    let_tok = _expect!(ps, :keyword, "let")
    name_tok = _expect!(ps, :identifier)
    type_ann = nothing
    if _match!(ps, :colon)
        type_ann = _parse_type(ps)
    end
    _expect!(ps, :eq)
    expr = _parse_expr(ps)
    KRLLetStmt(name_tok.value, type_ann, expr, let_tok.line, let_tok.col)
end

function _parse_rule_def(ps::ParserState)::KRLRuleDef
    rule_tok = _expect!(ps, :keyword, "rule")
    name_tok = _expect!(ps, :identifier)
    _expect!(ps, :lparen)
    params = _parse_param_list(ps)
    _expect!(ps, :rparen)
    _expect!(ps, :colon); _expect!(ps, :minus)   # ":-"
    clauses = KRLExpr[_parse_expr(ps)]
    while _match!(ps, :comma)
        push!(clauses, _parse_expr(ps))
    end
    KRLRuleDef(name_tok.value, params, clauses, rule_tok.line, rule_tok.col)
end

function _parse_axiom_def(ps::ParserState)::KRLAxiomDef
    ax_tok = _expect!(ps, :keyword, "axiom")
    name_tok = _expect!(ps, :identifier)
    _expect!(ps, :colon)
    params = String[]
    if _kw(ps, "forall")
        _advance!(ps)
        params = _parse_param_list(ps)
        _expect!(ps, :comma)
    end
    premise    = _parse_expr(ps)
    _expect!(ps, :arrow)
    conclusion = _parse_expr(ps)
    KRLAxiomDef(name_tok.value, params, premise, conclusion, ax_tok.line, ax_tok.col)
end

function _parse_param_list(ps::ParserState)::Vector{String}
    params = String[]
    isempty(params) && _is(ps, :identifier) && push!(params, _advance!(ps).value)
    while _match!(ps, :comma)
        push!(params, _expect!(ps, :identifier).value)
    end
    params
end

# ─────────────────────────────────────────────────────────────────────────────
# Query (pipeline)
# ─────────────────────────────────────────────────────────────────────────────

"""
Parse a full pipeline query: `from <source> { "|" <stage> }`.

Error recovery: if a pipeline stage fails to parse, the error is recorded in
`ps.errors` and scanning resumes at the next `|` token or EOF, so the parser
reports all stage errors rather than stopping at the first.
"""
function _parse_query(ps::ParserState)::KRLQuery
    from_tok = _expect!(ps, :keyword, "from")
    source   = _parse_source(ps)
    stages   = KRLPipeStage[]

    while _match!(ps, :pipe)
        try
            push!(stages, _parse_pipeline_stage(ps))
        catch e
            e isa KRLParseError || rethrow()
            push!(ps.errors, e)
            # Recovery: skip tokens until next `|` or EOF
            while !_at_eof(ps) && !_is(ps, :pipe)
                _advance!(ps)
            end
        end
    end

    KRLQuery(source, stages, from_tok.line, from_tok.col)
end

function _parse_source(ps::ParserState)::KRLSource
    t = _peek(ps)

    _kw(ps, "knots")      && (_advance!(ps); return KRLSourceKnots(t.line, t.col))
    _kw(ps, "diagrams")   && (_advance!(ps); return KRLSourceDiagrams(t.line, t.col))
    _kw(ps, "invariants") && (_advance!(ps); return KRLSourceInvariants(t.line, t.col))

    if _is(ps, :lparen)
        _advance!(ps)
        q = _parse_query(ps)
        _expect!(ps, :rparen)
        return KRLSourceSubquery(q, t.line, t.col)
    end

    if _is(ps, :identifier)
        name = _advance!(ps).value
        alias = nothing
        if _kw(ps, "as")
            _advance!(ps)
            alias = _expect!(ps, :identifier).value
        end
        return KRLSourceNamed(name, alias, t.line, t.col)
    end

    throw(KRLParseError(
        "expected source (knots/diagrams/invariants/identifier/(subquery)), got $(t.kind)",
        t.line, t.col))
end

# ─────────────────────────────────────────────────────────────────────────────
# Pipeline stages
# ─────────────────────────────────────────────────────────────────────────────

const _AGGREGATE_FNS = Set(["count", "min", "max", "avg", "sum"])

function _parse_pipeline_stage(ps::ParserState)::KRLPipeStage
    t = _peek(ps)
    t.kind == :keyword || throw(KRLParseError(
        "expected pipeline stage keyword, got $(t.kind)($(repr(t.value)))", t.line, t.col))

    t.value == "filter"          && return _parse_filter_stage(ps)
    t.value == "sort"            && return _parse_sort_stage(ps)
    t.value == "take"            && return _parse_take_stage(ps)
    t.value == "skip"            && return _parse_skip_stage(ps)
    t.value == "return"          && return _parse_return_stage(ps)
    t.value == "group_by"        && return _parse_group_by_stage(ps)
    t.value == "aggregate"       && return _parse_aggregate_stage(ps)
    t.value == "find_equivalent" && return _parse_find_equiv_stage(ps)
    t.value == "find_path"       && return _parse_find_path_stage(ps)
    t.value == "match"           && return _parse_match_stage(ps)
    t.value == "let"             && return _parse_let_stage(ps)
    t.value == "with"            && return _parse_with_stage(ps)

    throw(KRLParseError("unknown pipeline stage: $(repr(t.value))", t.line, t.col))
end

function _parse_filter_stage(ps::ParserState)::KRLFilterStage
    t = _expect!(ps, :keyword, "filter")
    KRLFilterStage(_parse_expr(ps), t.line, t.col)
end

function _parse_sort_stage(ps::ParserState)::KRLSortStage
    t = _expect!(ps, :keyword, "sort")
    items = Tuple{KRLExpr, SortOrder}[]
    push!(items, _parse_sort_item(ps))
    while _match!(ps, :comma)
        push!(items, _parse_sort_item(ps))
    end
    KRLSortStage(items, t.line, t.col)
end

function _parse_sort_item(ps::ParserState)
    expr = _parse_expr(ps)
    order = SortAsc
    if _kw(ps, "asc");  _advance!(ps); order = SortAsc;  end
    if _kw(ps, "desc"); _advance!(ps); order = SortDesc; end
    (expr, order)
end

function _parse_take_stage(ps::ParserState)::KRLTakeStage
    t = _expect!(ps, :keyword, "take")
    n_tok = _expect!(ps, :integer)
    KRLTakeStage(parse(Int, n_tok.value), t.line, t.col)
end

function _parse_skip_stage(ps::ParserState)::KRLSkipStage
    t = _expect!(ps, :keyword, "skip")
    n_tok = _expect!(ps, :integer)
    KRLSkipStage(parse(Int, n_tok.value), t.line, t.col)
end

function _parse_return_stage(ps::ParserState)::KRLReturnStage
    t = _expect!(ps, :keyword, "return")
    items = KRLReturnItem[_parse_return_item(ps)]
    while _match!(ps, :comma)
        push!(items, _parse_return_item(ps))
    end
    with_prov = false
    if _kw(ps, "with")
        _advance!(ps)
        _expect!(ps, :keyword, "provenance")
        with_prov = true
    end
    KRLReturnStage(items, with_prov, t.line, t.col)
end

function _parse_return_item(ps::ParserState)::KRLReturnItem
    t = _peek(ps)

    t.kind == :star      && (_advance!(ps); return KRLReturnStar(t.line, t.col))

    if t.kind == :keyword
        t.value == "equivalences"      && (_advance!(ps); return KRLReturnEquivs(t.line, t.col))
        t.value == "equivalence_class" && (_advance!(ps); return KRLReturnEquivClass(t.line, t.col))
        t.value == "proof"             && (_advance!(ps); return KRLReturnProof(t.line, t.col))
    end

    expr  = _parse_expr(ps)
    alias = nothing
    if _kw(ps, "as")
        _advance!(ps)
        alias = _expect!(ps, :identifier).value
    end
    KRLReturnExpr(expr, alias, t.line, t.col)
end

function _parse_group_by_stage(ps::ParserState)::KRLGroupByStage
    t = _expect!(ps, :keyword, "group_by")
    keys = KRLExpr[_parse_expr(ps)]
    while _match!(ps, :comma)
        push!(keys, _parse_expr(ps))
    end
    KRLGroupByStage(keys, t.line, t.col)
end

function _parse_aggregate_stage(ps::ParserState)::KRLAggregateStage
    t = _expect!(ps, :keyword, "aggregate")
    items = KRLAggregateItem[_parse_agg_item(ps)]
    while _match!(ps, :comma)
        push!(items, _parse_agg_item(ps))
    end
    KRLAggregateStage(items, t.line, t.col)
end

function _parse_agg_item(ps::ParserState)::KRLAggregateItem
    t = _peek(ps)
    fn_str = (t.kind == :keyword || t.kind == :identifier) ? t.value : ""
    fn_str in _AGGREGATE_FNS ||
        throw(KRLParseError("expected aggregate function (count/min/max/avg/sum), got $(repr(t.value))",
                            t.line, t.col))
    _advance!(ps)
    _expect!(ps, :lparen)
    arg = _parse_expr(ps)
    _expect!(ps, :rparen)
    alias = nothing
    if _kw(ps, "as"); _advance!(ps); alias = _expect!(ps, :identifier).value; end
    KRLAggregateItem(Symbol(fn_str), arg, alias, t.line, t.col)
end

function _parse_find_equiv_stage(ps::ParserState)::KRLFindEquivStage
    t = _expect!(ps, :keyword, "find_equivalent")
    target = _parse_expr(ps)

    via_invs = String[]
    if _kw(ps, "via")
        _advance!(ps)
        _expect!(ps, :lbracket)
        push!(via_invs, _parse_invariant_name(ps))
        while _match!(ps, :comma)
            push!(via_invs, _parse_invariant_name(ps))
        end
        _expect!(ps, :rbracket)
    end

    min_conf = nothing
    if _kw(ps, "confidence")
        _advance!(ps)
        _expect!(ps, :gte)
        min_conf = _parse_confidence_level(ps)
    end

    KRLFindEquivStage(target, via_invs, min_conf, t.line, t.col)
end

function _parse_invariant_name(ps::ParserState)::String
    t = _peek(ps)
    (t.kind == :identifier || t.kind == :keyword) ||
        throw(KRLParseError("expected invariant name", t.line, t.col))
    _advance!(ps); t.value
end

function _parse_confidence_level(ps::ParserState)::ConfidenceLevel
    t = _peek(ps)
    t.kind == :keyword || throw(KRLParseError("expected confidence level", t.line, t.col))
    _advance!(ps)
    t.value == "exact"      && return ConfExact
    t.value == "sufficient" && return ConfSufficient
    t.value == "necessary"  && return ConfNecessary
    t.value == "heuristic"  && return ConfHeuristic
    throw(KRLParseError("unknown confidence level: $(repr(t.value))", t.line, t.col))
end

function _parse_find_path_stage(ps::ParserState)::KRLFindPathStage
    t     = _expect!(ps, :keyword, "find_path")
    src_e = _parse_expr(ps)
    _expect!(ps, :tilde_arrow)   # ~>
    tgt   = _parse_expr(ps)
    _expect!(ps, :keyword, "via")
    method_tok = _peek(ps)
    (method_tok.kind == :keyword || method_tok.kind == :identifier) ||
        throw(KRLParseError("expected path method", method_tok.line, method_tok.col))
    _advance!(ps)
    KRLFindPathStage(src_e, tgt, Symbol(method_tok.value), t.line, t.col)
end

function _parse_match_stage(ps::ParserState)::KRLMatchStage
    t = _expect!(ps, :keyword, "match")
    KRLMatchStage(_parse_graph_pattern(ps), t.line, t.col)
end

function _parse_let_stage(ps::ParserState)::KRLLetStage
    t = _expect!(ps, :keyword, "let")
    name = _expect!(ps, :identifier).value
    _expect!(ps, :eq)
    expr = _parse_expr(ps)
    KRLLetStage(name, expr, t.line, t.col)
end

function _parse_with_stage(ps::ParserState)::KRLWithStage
    t = _expect!(ps, :keyword, "with")
    mods = Union{Symbol, Pair{String, KRLExpr}}[_parse_with_modifier(ps)]
    while _match!(ps, :comma)
        push!(mods, _parse_with_modifier(ps))
    end
    KRLWithStage(mods, t.line, t.col)
end

function _parse_with_modifier(ps::ParserState)
    if _kw(ps, "provenance"); _advance!(ps); return :provenance; end
    name = _expect!(ps, :identifier).value
    _expect!(ps, :eq)
    expr = _parse_expr(ps)
    name => expr
end

# ─────────────────────────────────────────────────────────────────────────────
# Expressions  (9-level precedence, grammar.ebnf §SYNTACTIC)
# ─────────────────────────────────────────────────────────────────────────────
#
# Dispatch chain (lowest → highest precedence):
#   _parse_expr → _parse_null_coalesce → _parse_or → _parse_and
#     → _parse_not → _parse_comparison → _parse_additive
#       → _parse_multiplicative → _parse_unary → _parse_postfix → _parse_primary

_parse_expr(ps::ParserState)::KRLExpr = _parse_null_coalesce(ps)

# Level 0 — null coalesce  ??
function _parse_null_coalesce(ps::ParserState)::KRLExpr
    left = _parse_or(ps)
    while _is(ps, :null_coalesce)
        tok = _advance!(ps)
        right = _parse_or(ps)
        left = KRLNullCoalesce(left, right, tok.line, tok.col)
    end
    left
end

# Level 1 — or
function _parse_or(ps::ParserState)::KRLExpr
    left = _parse_and(ps)
    while _kw(ps, "or")
        tok = _advance!(ps)
        right = _parse_and(ps)
        left = KRLOr(left, right, tok.line, tok.col)
    end
    left
end

# Level 2 — and
function _parse_and(ps::ParserState)::KRLExpr
    left = _parse_not(ps)
    while _kw(ps, "and")
        tok = _advance!(ps)
        right = _parse_not(ps)
        left = KRLAnd(left, right, tok.line, tok.col)
    end
    left
end

# Level 3 — not (prefix)
function _parse_not(ps::ParserState)::KRLExpr
    if _kw(ps, "not")
        tok = _advance!(ps)
        return KRLNot(_parse_not(ps), tok.line, tok.col)
    end
    _parse_comparison(ps)
end

# Level 4 — comparison  (at most one operator, not chained)
const _CMP_KINDS = Set([:eq, :neq, :lt, :lte, :gt, :gte, :iso, :tilde_arrow])

function _parse_comparison(ps::ParserState)::KRLExpr
    left = _parse_additive(ps)
    t = _peek(ps)

    if _kw(ps, "in")
        tok = _advance!(ps)
        right = _parse_additive(ps)
        return KRLCompare(left, :in, right, tok.line, tok.col)
    end

    if t.kind in _CMP_KINDS
        tok = _advance!(ps)
        op = t.kind == :eq           ? :eq    :
             t.kind == :neq          ? :neq   :
             t.kind == :lt           ? :lt    :
             t.kind == :lte          ? :lte   :
             t.kind == :gt           ? :gt    :
             t.kind == :gte          ? :gte   :
             t.kind == :iso          ? :iso   :
             :path
        right = _parse_additive(ps)
        return KRLCompare(left, op, right, tok.line, tok.col)
    end

    left
end

# Level 5 — additive  + -
function _parse_additive(ps::ParserState)::KRLExpr
    left = _parse_multiplicative(ps)
    while _is(ps, :plus) || _is(ps, :minus)
        tok = _advance!(ps)
        op  = tok.kind == :plus ? :add : :sub
        right = _parse_multiplicative(ps)
        left = KRLBinOp(left, op, right, tok.line, tok.col)
    end
    left
end

# Level 6 — multiplicative  * / %
function _parse_multiplicative(ps::ParserState)::KRLExpr
    left = _parse_unary(ps)
    while _is(ps, :star) || _is(ps, :slash) || _is(ps, :percent)
        tok = _advance!(ps)
        op  = tok.kind == :star ? :mul : tok.kind == :slash ? :div : :mod
        right = _parse_unary(ps)
        left = KRLBinOp(left, op, right, tok.line, tok.col)
    end
    left
end

# Level 7 — unary negation
function _parse_unary(ps::ParserState)::KRLExpr
    if _is(ps, :minus)
        tok = _advance!(ps)
        return KRLUnaryNeg(_parse_unary(ps), tok.line, tok.col)
    end
    _parse_postfix(ps)
end

# Level 8 — postfix  . () []
function _parse_postfix(ps::ParserState)::KRLExpr
    expr = _parse_primary(ps)
    while true
        if _is(ps, :dot)
            tok = _advance!(ps)
            field_tok = _expect!(ps, :identifier)
            expr = KRLFieldAccess(expr, field_tok.value, tok.line, tok.col)

        elseif _is(ps, :lparen)
            tok = _advance!(ps)
            args = KRLExpr[]
            if !_is(ps, :rparen)
                push!(args, _parse_expr(ps))
                while _match!(ps, :comma)
                    push!(args, _parse_expr(ps))
                end
            end
            _expect!(ps, :rparen)
            expr = KRLCall(expr, args, tok.line, tok.col)

        elseif _is(ps, :lbracket)
            tok = _advance!(ps)
            idx = _parse_expr(ps)
            _expect!(ps, :rbracket)
            expr = KRLIndex(expr, idx, tok.line, tok.col)

        else
            break
        end
    end
    expr
end

# Level 9 — primary
function _parse_primary(ps::ParserState)::KRLExpr
    t = _peek(ps)

    # boolean literals (keyword "true" / "false")
    if t.kind == :keyword && t.value == "true";  _advance!(ps); return KRLBool(true,  t.line, t.col); end
    if t.kind == :keyword && t.value == "false"; _advance!(ps); return KRLBool(false, t.line, t.col); end
    if t.kind == :keyword && t.value == "none";  _advance!(ps); return KRLNone(t.line, t.col); end

    # gauss code:  gauss(1, -2, 3, …)
    if (t.kind == :keyword || t.kind == :identifier) && t.value == "gauss"
        return _parse_gauss_code(ps)
    end

    # string literal
    t.kind == :string  && (_advance!(ps); return KRLString(t.value,         t.line, t.col))
    # integer literal
    t.kind == :integer && (_advance!(ps); return KRLInt(parse(Int, t.value), t.line, t.col))
    # float literal
    t.kind == :float   && (_advance!(ps); return KRLFloat(parse(Float64, t.value), t.line, t.col))
    # knot name: 3_1, 5_2, 10_139
    t.kind == :knot_name && (_advance!(ps); return KRLKnotName(t.value, t.line, t.col))

    # array literal:  [e1, e2, …]
    if t.kind == :lbracket
        _advance!(ps)
        elems = KRLExpr[]
        if !_is(ps, :rbracket)
            push!(elems, _parse_expr(ps))
            while _match!(ps, :comma)
                push!(elems, _parse_expr(ps))
            end
        end
        _expect!(ps, :rbracket)
        return KRLArray(elems, t.line, t.col)
    end

    # record literal:  {f: e, …}
    if t.kind == :lbrace
        _advance!(ps)
        fields = Pair{String, KRLExpr}[]
        if !_is(ps, :rbrace)
            push!(fields, _parse_record_field(ps))
            while _match!(ps, :comma)
                push!(fields, _parse_record_field(ps))
            end
        end
        _expect!(ps, :rbrace)
        return KRLRecord(fields, t.line, t.col)
    end

    # parenthesised expression
    if t.kind == :lparen
        _advance!(ps)
        e = _parse_expr(ps)
        _expect!(ps, :rparen)
        return e   # transparent — no KRLParen wrapper needed
    end

    # identifier or keyword used as a name
    if t.kind == :identifier || t.kind == :keyword
        _advance!(ps)
        return KRLVar(t.value, t.line, t.col)
    end

    got = t.kind == :eof ? "end-of-file" : "$(t.kind)($(repr(t.value)))"
    throw(KRLParseError("expected expression, got $got", t.line, t.col))
end

function _parse_record_field(ps::ParserState)::Pair{String, KRLExpr}
    key = _expect!(ps, :identifier).value
    _expect!(ps, :colon)
    val = _parse_expr(ps)
    key => val
end

# ─────────────────────────────────────────────────────────────────────────────
# Gauss codes
# ─────────────────────────────────────────────────────────────────────────────

"""
Parse `gauss(<signed_int>, …)`.

Validation (parse-time):
  - At least one integer.
  - No zero values (0 has no topological meaning in a Gauss code).
"""
function _parse_gauss_code(ps::ParserState)::KRLGaussCode
    t = _peek(ps)
    _advance!(ps)   # consume "gauss"
    _expect!(ps, :lparen)
    codes = Int[]
    push!(codes, _parse_signed_int(ps))
    while _match!(ps, :comma)
        push!(codes, _parse_signed_int(ps))
    end
    _expect!(ps, :rparen)

    # Validation: no zeros
    for (i, v) in enumerate(codes)
        v == 0 && throw(KRLParseError(
            "Gauss code position $i is 0 — zero is not a valid crossing label",
            t.line, t.col))
    end
    isempty(codes) && throw(KRLParseError("Gauss code must be non-empty", t.line, t.col))

    KRLGaussCode(codes, t.line, t.col)
end

function _parse_signed_int(ps::ParserState)::Int
    neg = _match!(ps, :minus)
    tok = _expect!(ps, :integer)
    v   = parse(Int, tok.value)
    neg ? -v : v
end

# ─────────────────────────────────────────────────────────────────────────────
# Graph patterns
# ─────────────────────────────────────────────────────────────────────────────

"""
Parse a graph pattern: `(N1)-[E1]->(N2) …`
At least one node required; edges and subsequent nodes follow in pairs.
"""
function _parse_graph_pattern(ps::ParserState)::KRLGraphPattern
    t = _peek(ps)
    nodes = KRLNodePattern[]
    edges = KRLEdgePattern[]
    push!(nodes, _parse_node_pattern(ps))
    while _is(ps, :minus) || _is(ps, :lt)
        push!(edges, _parse_edge_pattern(ps))
        push!(nodes, _parse_node_pattern(ps))
    end
    KRLGraphPattern(nodes, edges, t.line, t.col)
end

function _parse_node_pattern(ps::ParserState)::KRLNodePattern
    t = _expect!(ps, :lparen)
    var   = _is(ps, :identifier) ? _advance!(ps).value : nothing
    label = nothing
    if _match!(ps, :colon)
        label = _expect!(ps, :identifier).value
    end
    props = Pair{String, KRLExpr}[]
    if _is(ps, :lbrace)
        _advance!(ps)
        props = [_parse_record_field(ps)]
        while _match!(ps, :comma); push!(props, _parse_record_field(ps)); end
        _expect!(ps, :rbrace)
    end
    _expect!(ps, :rparen)
    KRLNodePattern(var, label, props, t.line, t.col)
end

function _parse_edge_pattern(ps::ParserState)::KRLEdgePattern
    t = _peek(ps)
    # backward:  <-[…]-
    if _is(ps, :lt)
        _advance!(ps)
        _expect!(ps, :minus)
        lbl, props = _parse_edge_body(ps)
        _expect!(ps, :minus)
        return KRLEdgePattern(lbl, props, EdgeBackward, t.line, t.col)
    end
    # forward:  -[…]->  or undirected:  -[…]-
    _expect!(ps, :minus)
    lbl, props = _parse_edge_body(ps)
    _expect!(ps, :minus)
    if _is(ps, :gt)
        _advance!(ps)
        return KRLEdgePattern(lbl, props, EdgeForward, t.line, t.col)
    end
    KRLEdgePattern(lbl, props, EdgeUndirected, t.line, t.col)
end

function _parse_edge_body(ps::ParserState)
    _expect!(ps, :lbracket)
    label = nothing
    if _match!(ps, :colon)
        label = _expect!(ps, :identifier).value
    end
    props = Pair{String, KRLExpr}[]
    if _is(ps, :lbrace)
        _advance!(ps)
        push!(props, _parse_record_field(ps))
        while _match!(ps, :comma); push!(props, _parse_record_field(ps)); end
        _expect!(ps, :rbrace)
    end
    _expect!(ps, :rbracket)
    (label, props)
end

# ─────────────────────────────────────────────────────────────────────────────
# Type annotations
# ─────────────────────────────────────────────────────────────────────────────

function _parse_type(ps::ParserState)::KRLType
    t = _peek(ps)
    (t.kind == :keyword || t.kind == :identifier) ||
        throw(KRLParseError("expected type name", t.line, t.col))
    _advance!(ps)

    name = t.value

    # Parameterised types:  Option[τ], List[τ], Set[τ], ResultSet[τ],
    #                       Equivalence[τ] or Equivalence[τ, confidence],
    #                       Map[τ, τ]
    if _is(ps, :lbracket)
        _advance!(ps)
        inner = _parse_type(ps)
        if name == "Map"
            _expect!(ps, :comma)
            val = _parse_type(ps)
            _expect!(ps, :rbracket)
            return KRLTyMap(inner, val, t.line, t.col)
        end
        if name == "Equivalence" && _match!(ps, :comma)
            conf = _parse_confidence_level(ps)
            _expect!(ps, :rbracket)
            return KRLTyEquivConf(inner, conf, t.line, t.col)
        end
        _expect!(ps, :rbracket)
        name == "Option"    && return KRLTyOption(inner,    t.line, t.col)
        name == "List"      && return KRLTyList(inner,      t.line, t.col)
        name == "Set"       && return KRLTySet(inner,       t.line, t.col)
        name == "ResultSet" && return KRLTyResultSet(inner, t.line, t.col)
        name == "Equivalence" && return KRLTyEquiv(inner,  t.line, t.col)
        # Unknown parameterised type — treat as user type with one argument (best effort)
        return KRLTyNamed(name, t.line, t.col)
    end

    # Tuple:  ( τ, τ, … )
    if t.kind == :lparen
        elems = KRLType[_parse_type(ps)]
        while _match!(ps, :comma); push!(elems, _parse_type(ps)); end
        _expect!(ps, :rparen)
        return KRLTyTuple(elems, t.line, t.col)
    end

    # Scalar / named types
    name in ("Int", "Float", "String", "Bool") &&
        return KRLTyScalar(Symbol(name), t.line, t.col)

    KRLTyNamed(name, t.line, t.col)
end
