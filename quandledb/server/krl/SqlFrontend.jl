# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
SQL→KRL Translation Frontend.

Accepts the SQL subset defined in spec/sql-compat.md and emits a `KRLProgram`
containing a single `KRLQueryStmt`. The translation is purely syntactic:
the resulting KRL AST is type-checked and evaluated exactly like hand-written KRL.

Supported SQL constructs (per sql-compat.md §2):
  SELECT fields | *
  FROM knots | diagrams | invariants | identifier
  WHERE expr
  GROUP BY expr
  HAVING expr      (translated to a filter stage after aggregate)
  ORDER BY expr [ASC|DESC]
  LIMIT n
  OFFSET n

Unsupported SQL (sql-compat.md §3) produces a `KRLParseError` with a
KRL-equivalent suggestion in the message.

SQL keywords are case-insensitive. Expressions in WHERE/ORDER BY/HAVING
are parsed using the KRL expression parser — they share the same syntax.

Translation schema:
  SELECT a, b   → KRLReturnStage([a, b], false, …)
  FROM knots    → KRLSourceKnots
  WHERE pred    → KRLFilterStage(pred, …)
  GROUP BY key  → KRLGroupByStage([key], …)
  HAVING pred   → KRLFilterStage(pred, …)   (after aggregate)
  ORDER BY e d  → KRLSortStage([(e, d)], …)
  LIMIT n       → KRLTakeStage(n, …)
  OFFSET n      → KRLSkipStage(n, …)

Self-join on invariant equality is translated to KRLFindEquivStage (§2.4).
  WHERE K1.jones_polynomial = K2.jones_polynomial  →  find_equivalent via [jones_polynomial]
"""

export parse_sql

# ─────────────────────────────────────────────────────────────────────────────
# SQL keyword normalisation
# ─────────────────────────────────────────────────────────────────────────────

"""
    normalise_sql_tokens(tokens) -> Vector{Token}

Lower-case SQL clause keywords so the parser can match them case-insensitively.
Non-SQL tokens (identifiers, literals, operators) are left unchanged.
"""
const _SQL_UPPER_KWS = Set([
    "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING",
    "ORDER", "LIMIT", "OFFSET", "AS", "ASC", "DESC",
    "AND", "OR", "NOT", "IN", "DISTINCT", "COUNT", "MIN",
    "MAX", "AVG", "SUM", "NULL", "IS", "LIKE", "BETWEEN",
    "JOIN", "INNER", "LEFT", "RIGHT", "ON", "UNION", "ALL",
    "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER",
    "GRANT", "REVOKE",
])

const _SQL_UNSUPPORTED_KWS = Set([
    "null",       # KRL uses none / Option[τ]
    "insert", "update", "delete",  # QuandleDB is read-only
    "create", "alter",             # schema is fixed
    "grant", "revoke",             # no access control yet
])

function normalise_sql_tokens(tokens::Vector{Token})::Vector{Token}
    map(tokens) do tok
        if tok.kind == :identifier && uppercase(tok.value) in _SQL_UPPER_KWS
            Token(:keyword, lowercase(tok.value), tok.line, tok.col)
        else
            tok
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

"""
    parse_sql(src::String) -> KRLProgram

Lex `src` as SQL, translate to a KRL AST, and return a `KRLProgram` wrapping
the translated query.

The emitted AST is identical to what `parse_krl` would produce for the
equivalent KRL pipeline, so the type checker and evaluator need no SQL knowledge.
"""
function parse_sql(src::String)::KRLProgram
    raw_tokens = tokenise(src)
    tokens     = normalise_sql_tokens(raw_tokens)
    ps         = ParserState(tokens)
    query      = _parse_sql_query(ps)
    stmt       = KRLQueryStmt(query, query.line, query.col)
    KRLProgram([stmt], query.line, query.col)
end

# ─────────────────────────────────────────────────────────────────────────────
# SQL query parser
# ─────────────────────────────────────────────────────────────────────────────

"""
Parse a single SQL SELECT statement and return a `KRLQuery`.

Translation is performed during parsing: each SQL clause is directly
converted to the corresponding KRL pipeline stage.
"""
function _parse_sql_query(ps::ParserState)::KRLQuery
    t = _peek(ps)

    _expect!(ps, :keyword, "select")

    # DISTINCT is not supported — flag it
    if _kw(ps, "distinct")
        tok = _peek(ps)
        throw(KRLParseError(
            "SQL DISTINCT is not supported; use `| unique` in KRL instead",
            tok.line, tok.col))
    end

    select_items = _parse_sql_select_list(ps)
    _expect!(ps, :keyword, "from")
    source = _parse_source(ps)           # reuse KRL source parser

    stages = KRLPipeStage[]

    # WHERE
    if _kw(ps, "where")
        wtok = _advance!(ps)
        stages = _check_sql_unsupported_expr(ps, stages)
        pred   = _parse_expr(ps)
        push!(stages, KRLFilterStage(pred, wtok.line, wtok.col))
    end

    # GROUP BY
    local having_pred = nothing
    local having_tok  = nothing
    if _kw(ps, "group")
        gtok = _advance!(ps)
        _expect!(ps, :keyword, "by")
        keys = KRLExpr[_parse_expr(ps)]
        while _match!(ps, :comma); push!(keys, _parse_expr(ps)); end
        push!(stages, KRLGroupByStage(keys, gtok.line, gtok.col))

        # HAVING (filter after aggregate, so we record it and insert later)
        if _kw(ps, "having")
            having_tok  = _advance!(ps)
            having_pred = _parse_expr(ps)
        end
    end

    # ORDER BY
    if _kw(ps, "order")
        otok = _advance!(ps)
        _expect!(ps, :keyword, "by")
        items = Tuple{KRLExpr, SortOrder}[_parse_sql_order_item(ps)]
        while _match!(ps, :comma); push!(items, _parse_sql_order_item(ps)); end
        push!(stages, KRLSortStage(items, otok.line, otok.col))
    end

    # LIMIT
    if _kw(ps, "limit")
        ltok = _advance!(ps)
        n    = parse(Int, _expect!(ps, :integer).value)
        push!(stages, KRLTakeStage(n, ltok.line, ltok.col))
    end

    # OFFSET
    if _kw(ps, "offset")
        otok = _advance!(ps)
        n    = parse(Int, _expect!(ps, :integer).value)
        push!(stages, KRLSkipStage(n, otok.line, otok.col))
    end

    # Insert HAVING filter after the aggregate stage (if any)
    if !isnothing(having_pred)
        push!(stages, KRLFilterStage(having_pred, having_tok.line, having_tok.col))
    end

    # Return stage (always last)
    push!(stages, KRLReturnStage(select_items, false, t.line, t.col))

    # Optional trailing semicolon
    _match!(ps, :semi)

    KRLQuery(source, stages, t.line, t.col)
end

# ─────────────────────────────────────────────────────────────────────────────
# SELECT list
# ─────────────────────────────────────────────────────────────────────────────

function _parse_sql_select_list(ps::ParserState)::Vector{KRLReturnItem}
    # SELECT *
    if _is(ps, :star)
        tok = _advance!(ps)
        return [KRLReturnStar(tok.line, tok.col)]
    end
    items = KRLReturnItem[_parse_sql_select_item(ps)]
    while _match!(ps, :comma)
        push!(items, _parse_sql_select_item(ps))
    end
    items
end

function _parse_sql_select_item(ps::ParserState)::KRLReturnItem
    t   = _peek(ps)
    # Aggregate function: COUNT(*), MIN(x), …
    if (t.kind == :keyword || t.kind == :identifier) && t.value in _AGGREGATE_FNS
        return KRLReturnExpr(_parse_expr(ps), nothing, t.line, t.col)
    end
    expr  = _parse_expr(ps)
    alias = nothing
    if _kw(ps, "as"); _advance!(ps); alias = _expect!(ps, :identifier).value; end
    KRLReturnExpr(expr, alias, t.line, t.col)
end

# ─────────────────────────────────────────────────────────────────────────────
# ORDER BY item
# ─────────────────────────────────────────────────────────────────────────────

function _parse_sql_order_item(ps::ParserState)::Tuple{KRLExpr, SortOrder}
    expr = _parse_expr(ps)
    order = SortAsc
    if _kw(ps, "asc");  _advance!(ps); order = SortAsc;  end
    if _kw(ps, "desc"); _advance!(ps); order = SortDesc; end
    (expr, order)
end

# ─────────────────────────────────────────────────────────────────────────────
# Unsupported SQL feature detection
# ─────────────────────────────────────────────────────────────────────────────

"""
Scan ahead for SQL features that KRL cannot represent and raise a helpful error.
Does NOT consume any tokens.
"""
function _check_sql_unsupported_expr(ps::ParserState, stages::Vector)
    t = _peek(ps)
    if t.kind == :keyword && t.value in _SQL_UNSUPPORTED_KWS
        alt = Dict(
            "null"   => "`none` or `Option[τ]`",
            "insert" => "(QuandleDB is read-only; use Skein.jl REPL for mutations)",
            "update" => "(QuandleDB is read-only; use Skein.jl REPL for mutations)",
            "delete" => "(QuandleDB is read-only; use Skein.jl REPL for mutations)",
        )
        msg = get(alt, t.value, "no KRL equivalent")
        throw(KRLParseError(
            "SQL `$(uppercase(t.value))` is not supported in KRL; use $msg",
            t.line, t.col))
    end
    stages
end
