# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
KRL AST — one Julia type per grammar production in grammar.ebnf v0.1.0.

Every node carries `line::Int` and `col::Int` (1-based start position) for
downstream error messages and IDE integration. Source positions propagate
through the pipeline so an equivalence engine error can point back to the
original query text.

Abstract supertypes organise the hierarchy for typed dispatch:

    KRLNode            — everything
    ├── KRLStatement   — top-level program elements
    ├── KRLSource      — from-clause sources
    ├── KRLPipeStage   — pipeline stage nodes (|filter, |sort, …)
    ├── KRLReturnItem  — items in a return clause
    ├── KRLExpr        — expressions (9 precedence levels)
    ├── KRLPatternNode — graph pattern sub-nodes
    └── KRLType        — type annotation nodes

Invariants (checked by the parser, not the AST constructors):
  - `KRLPipeline.stages` is never empty (always has at least the source).
  - `KRLFindEquivStage.via_invs` contains only known invariant names
    (validated at type-check time, not parse time, per spec).
  - `KRLGaussCode.codes` is non-empty and all values are non-zero
    (validated at parse time — see Parser.jl).
"""

export KRLNode, KRLStatement, KRLSource, KRLPipeStage, KRLReturnItem,
       KRLExpr, KRLPatternNode, KRLType

# ─── Confidence level ────────────────────────────────────────────────────────

"""
    ConfidenceLevel

Four levels of equivalence certainty, matching the KRL type system
(spec/type-system.md §3, spec/dependent-type-variants.md §3).
"""
@enum ConfidenceLevel begin
    ConfExact      # quandle isomorphism — sufficient
    ConfSufficient # combination sufficient for equivalence
    ConfNecessary  # necessary conditions met, not proven
    ConfHeuristic  # statistical / tabulated
end

# ─── Sort order ──────────────────────────────────────────────────────────────

@enum SortOrder SortAsc SortDesc

# ─── Edge direction (graph patterns) ─────────────────────────────────────────

@enum EdgeDir EdgeForward EdgeBackward EdgeUndirected

# ─────────────────────────────────────────────────────────────────────────────
# Abstract base types
# ─────────────────────────────────────────────────────────────────────────────

abstract type KRLNode end
abstract type KRLStatement  <: KRLNode end
abstract type KRLSource     <: KRLNode end
abstract type KRLPipeStage  <: KRLNode end
abstract type KRLReturnItem <: KRLNode end
abstract type KRLExpr       <: KRLNode end
abstract type KRLPatternNode <: KRLNode end
abstract type KRLType       <: KRLNode end

# ─────────────────────────────────────────────────────────────────────────────
# Program root
# ─────────────────────────────────────────────────────────────────────────────

"""
    KRLProgram(statements, line, col)

Root of the AST. `statements` is an ordered list of top-level declarations.
"""
struct KRLProgram <: KRLNode
    statements::Vector{KRLStatement}
    line::Int
    col::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Statements
# ─────────────────────────────────────────────────────────────────────────────

"""
    KRLQueryStmt(query, line, col)

A pipeline query used as a statement (the primary use case in QuandleDB).
"""
struct KRLQueryStmt <: KRLStatement
    query::KRLNode   # KRLQuery
    line::Int
    col::Int
end

"""
    KRLLetStmt(name, type_ann, expr, line, col)

Top-level let binding: `let <name> [: <type>] = <expr>`.
`type_ann` is `nothing` if no type annotation was given.
"""
struct KRLLetStmt <: KRLStatement
    name::String
    type_ann::Union{KRLType, Nothing}
    expr::KRLExpr
    line::Int
    col::Int
end

"""
    KRLRuleDef(name, params, body_clauses, line, col)

Datalog-style rule: `rule <name>(<params>) :- <body>`.
`body_clauses` are predicate applications or guard expressions.
"""
struct KRLRuleDef <: KRLStatement
    name::String
    params::Vector{String}
    body_clauses::Vector{KRLExpr}
    line::Int
    col::Int
end

"""
    KRLAxiomDef(name, params, premise, conclusion, line, col)

Axiom: `axiom <name> [: forall <params>,] <premise> -> <conclusion>`.
`params` is empty when no `forall` quantifier is present.
"""
struct KRLAxiomDef <: KRLStatement
    name::String
    params::Vector{String}
    premise::KRLExpr
    conclusion::KRLExpr
    line::Int
    col::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Query (pipeline)
# ─────────────────────────────────────────────────────────────────────────────

"""
    KRLQuery(source, stages, line, col)

A complete pipeline query: `from <source> | stage1 | stage2 | …`.
`stages` may be empty (bare `from knots` is a valid query).
"""
struct KRLQuery <: KRLNode
    source::KRLSource
    stages::Vector{KRLPipeStage}
    line::Int
    col::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Sources
# ─────────────────────────────────────────────────────────────────────────────

struct KRLSourceKnots     <: KRLSource; line::Int; col::Int; end
struct KRLSourceDiagrams  <: KRLSource; line::Int; col::Int; end
struct KRLSourceInvariants <: KRLSource; line::Int; col::Int; end

"""
    KRLSourceNamed(name, alias, line, col)

`<identifier>` or `<identifier> as <alias>`.
`alias` is `nothing` when no `as` clause is present.
"""
struct KRLSourceNamed <: KRLSource
    name::String
    alias::Union{String, Nothing}
    line::Int
    col::Int
end

"""
    KRLSourceSubquery(query, line, col)

`( <query> )` — a subquery used as a source.
"""
struct KRLSourceSubquery <: KRLSource
    query::KRLQuery
    line::Int
    col::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Pipeline stages
# ─────────────────────────────────────────────────────────────────────────────

"""    KRLFilterStage(pred, line, col)   `| filter <pred>` """
struct KRLFilterStage <: KRLPipeStage
    pred::KRLExpr
    line::Int; col::Int
end

"""
    KRLSortStage(items, line, col)

`| sort <expr> [asc|desc], …`
Each item is a `(expr, SortOrder)` pair.
"""
struct KRLSortStage <: KRLPipeStage
    items::Vector{Tuple{KRLExpr, SortOrder}}
    line::Int; col::Int
end

"""    KRLTakeStage(n, line, col)   `| take <n>` """
struct KRLTakeStage <: KRLPipeStage
    n::Int
    line::Int; col::Int
end

"""    KRLSkipStage(n, line, col)   `| skip <n>` """
struct KRLSkipStage <: KRLPipeStage
    n::Int
    line::Int; col::Int
end

"""
    KRLReturnStage(items, with_provenance, line, col)

`| return <item>, … [with provenance]`
"""
struct KRLReturnStage <: KRLPipeStage
    items::Vector{KRLReturnItem}
    with_provenance::Bool
    line::Int; col::Int
end

"""    KRLGroupByStage(keys, line, col)   `| group_by <expr>, …` """
struct KRLGroupByStage <: KRLPipeStage
    keys::Vector{KRLExpr}
    line::Int; col::Int
end

"""
    KRLAggregateItem(fn, arg, alias, line, col)

One item in an aggregate stage: `<fn>(<arg>) [as <alias>]`.
`fn` is one of `:count`, `:min`, `:max`, `:avg`, `:sum`.
"""
struct KRLAggregateItem <: KRLNode
    fn::Symbol
    arg::KRLExpr
    alias::Union{String, Nothing}
    line::Int; col::Int
end

"""    KRLAggregateStage(items, line, col)   `| aggregate <item>, …` """
struct KRLAggregateStage <: KRLPipeStage
    items::Vector{KRLAggregateItem}
    line::Int; col::Int
end

"""
    KRLFindEquivStage(target, via_invs, min_confidence, line, col)

`| find_equivalent <target> [via [inv, …]] [confidence >= <level>]`

`via_invs` is empty when no `via` clause is present (all invariants tried).
`min_confidence` is `nothing` when no threshold is specified (any confidence).
"""
struct KRLFindEquivStage <: KRLPipeStage
    target::KRLExpr
    via_invs::Vector{String}
    min_confidence::Union{ConfidenceLevel, Nothing}
    line::Int; col::Int
end

"""
    KRLFindPathStage(source_expr, target, method, line, col)

`| find_path <source> ~> <target> via <method>`
`method` is `:reidemeister`, `:isotopy`, or a user identifier.
"""
struct KRLFindPathStage <: KRLPipeStage
    source_expr::KRLExpr
    target::KRLExpr
    method::Symbol
    line::Int; col::Int
end

"""    KRLMatchStage(pattern, line, col)   `| match <graph_pattern>` """
struct KRLMatchStage <: KRLPipeStage
    pattern::KRLNode   # KRLGraphPattern
    line::Int; col::Int
end

"""    KRLLetStage(name, expr, line, col)   `| let <name> = <expr>` """
struct KRLLetStage <: KRLPipeStage
    name::String
    expr::KRLExpr
    line::Int; col::Int
end

"""
    KRLWithStage(modifiers, line, col)

`| with <modifier>, …`
Each modifier is either the symbol `:provenance` or a `(name, expr)` pair.
"""
struct KRLWithStage <: KRLPipeStage
    modifiers::Vector{Union{Symbol, Pair{String, KRLExpr}}}
    line::Int; col::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Return items
# ─────────────────────────────────────────────────────────────────────────────

"""    KRLReturnExpr(expr, alias, line, col)   `<expr> [as <alias>]` """
struct KRLReturnExpr <: KRLReturnItem
    expr::KRLExpr
    alias::Union{String, Nothing}
    line::Int; col::Int
end

struct KRLReturnStar       <: KRLReturnItem; line::Int; col::Int; end
struct KRLReturnEquivs     <: KRLReturnItem; line::Int; col::Int; end
struct KRLReturnEquivClass <: KRLReturnItem; line::Int; col::Int; end
struct KRLReturnProof      <: KRLReturnItem; line::Int; col::Int; end

# ─────────────────────────────────────────────────────────────────────────────
# Expressions
# ─────────────────────────────────────────────────────────────────────────────

# Precedence (lowest → highest, matching grammar.ebnf comment):
#   0  null_coalesce  ??
#   1  or
#   2  and
#   3  not (prefix)
#   4  compare  ==, !=, <, <=, >, >=, ≅, ~>
#   5  additive  +, -
#   6  multiplicative  *, /, %
#   7  unary  - (prefix)
#   8  postfix  . () []
#   9  primary  literal / identifier / ( ) / [ ] / { } / gauss(…)

struct KRLNullCoalesce <: KRLExpr
    left::KRLExpr; right::KRLExpr; line::Int; col::Int
end
struct KRLOr <: KRLExpr
    left::KRLExpr; right::KRLExpr; line::Int; col::Int
end
struct KRLAnd <: KRLExpr
    left::KRLExpr; right::KRLExpr; line::Int; col::Int
end
struct KRLNot <: KRLExpr
    operand::KRLExpr; line::Int; col::Int
end

"""
    KRLCompare(left, op, right, line, col)

Binary comparison. `op` is one of:
  `:eq`, `:neq`, `:lt`, `:lte`, `:gt`, `:gte`,
  `:iso` (propositional equivalence ≅/~=),
  `:path` (path equivalence ~>),
  `:in`  (set membership).
"""
struct KRLCompare <: KRLExpr
    left::KRLExpr; op::Symbol; right::KRLExpr; line::Int; col::Int
end

"""
    KRLBinOp(left, op, right, line, col)

Arithmetic binary op. `op` is `:add`, `:sub`, `:mul`, `:div`, or `:mod`.
"""
struct KRLBinOp <: KRLExpr
    left::KRLExpr; op::Symbol; right::KRLExpr; line::Int; col::Int
end

struct KRLUnaryNeg <: KRLExpr; operand::KRLExpr; line::Int; col::Int; end

"""    KRLFieldAccess(obj, field, line, col)   `<obj>.<field>` """
struct KRLFieldAccess <: KRLExpr
    obj::KRLExpr; field::String; line::Int; col::Int
end

"""    KRLCall(func, args, line, col)   `<func>(<args…>)` """
struct KRLCall <: KRLExpr
    func::KRLExpr
    args::Vector{KRLExpr}
    line::Int; col::Int
end

"""    KRLIndex(obj, index, line, col)   `<obj>[<index>]` """
struct KRLIndex <: KRLExpr
    obj::KRLExpr; index::KRLExpr; line::Int; col::Int
end

# Primary literals
struct KRLVar      <: KRLExpr; name::String;  line::Int; col::Int; end
struct KRLKnotName <: KRLExpr; name::String;  line::Int; col::Int; end  # "3_1"
struct KRLInt      <: KRLExpr; n::Int;        line::Int; col::Int; end
struct KRLFloat    <: KRLExpr; x::Float64;    line::Int; col::Int; end
struct KRLString   <: KRLExpr; s::String;     line::Int; col::Int; end
struct KRLBool     <: KRLExpr; b::Bool;       line::Int; col::Int; end
struct KRLNone     <: KRLExpr; line::Int; col::Int; end   # none / Option absent

"""    KRLArray(elems, line, col)   `[e1, e2, …]` """
struct KRLArray <: KRLExpr
    elems::Vector{KRLExpr}
    line::Int; col::Int
end

"""    KRLRecord(fields, line, col)   `{f1: e1, f2: e2}` """
struct KRLRecord <: KRLExpr
    fields::Vector{Pair{String, KRLExpr}}
    line::Int; col::Int
end

"""
    KRLGaussCode(codes, line, col)

`gauss(1, -2, 3, -1, 2, -3)` — Gauss code for a knot diagram.

Invariant (enforced by parser): `codes` is non-empty and no element is 0.
"""
struct KRLGaussCode <: KRLExpr
    codes::Vector{Int}
    line::Int; col::Int
end

"""    KRLTypeAnn(expr, type_ann, line, col)   `<expr> : <type>` (CAST) """
struct KRLTypeAnn <: KRLExpr
    expr::KRLExpr
    type_ann::KRLType
    line::Int; col::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Graph pattern nodes
# ─────────────────────────────────────────────────────────────────────────────

"""
    KRLNodePattern(var, label, props, line, col)

`( [var] [: Label] [{props}] )`
`var` and `label` are `nothing` when absent.
"""
struct KRLNodePattern <: KRLPatternNode
    var::Union{String, Nothing}
    label::Union{String, Nothing}
    props::Vector{Pair{String, KRLExpr}}
    line::Int; col::Int
end

"""
    KRLEdgePattern(label, props, direction, line, col)

`-[:LABEL {props}]->` (forward), `<-[…]-` (backward), or `-[…]-` (undirected).
"""
struct KRLEdgePattern <: KRLPatternNode
    label::Union{String, Nothing}
    props::Vector{Pair{String, KRLExpr}}
    direction::EdgeDir
    line::Int; col::Int
end

"""
    KRLGraphPattern(nodes, edges, line, col)

`(N1)-[E1]->(N2)-[E2]->(N3) …`
`nodes` and `edges` alternate: `length(nodes) == length(edges) + 1`.
"""
struct KRLGraphPattern <: KRLNode
    nodes::Vector{KRLNodePattern}
    edges::Vector{KRLEdgePattern}
    line::Int; col::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Type annotation nodes
# ─────────────────────────────────────────────────────────────────────────────

struct KRLTyScalar  <: KRLType; name::Symbol; line::Int; col::Int; end  # :Int, :Float, …
struct KRLTyOption  <: KRLType; inner::KRLType; line::Int; col::Int; end
struct KRLTyList    <: KRLType; inner::KRLType; line::Int; col::Int; end
struct KRLTySet     <: KRLType; inner::KRLType; line::Int; col::Int; end
struct KRLTyResultSet <: KRLType; inner::KRLType; line::Int; col::Int; end
struct KRLTyEquiv   <: KRLType; inner::KRLType; line::Int; col::Int; end
struct KRLTyEquivConf <: KRLType; inner::KRLType; confidence::ConfidenceLevel; line::Int; col::Int; end
struct KRLTyMap     <: KRLType; key::KRLType; val::KRLType; line::Int; col::Int; end
struct KRLTyTuple   <: KRLType; elems::Vector{KRLType}; line::Int; col::Int; end
struct KRLTyNamed   <: KRLType; name::String; line::Int; col::Int; end  # Knot, Diagram, user types
