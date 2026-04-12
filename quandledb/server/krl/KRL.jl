# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
KRL — Knot Resolution Language parser for QuandleDB.

Implements the parser for KRL v0.1.0 (grammar.ebnf, spec/type-system.md).
Components:
  Lexer.jl        — tokeniser (Token, tokenise, KRLLexError)
  Ast.jl          — AST node types (KRLProgram, KRLQuery, …)
  Parser.jl       — recursive-descent parser (parse_krl, parse_krl_query)
  SqlFrontend.jl  — SQL→KRL translation layer (parse_sql)

Entry points (re-exported):
  parse_krl(src)        — parse KRL source → KRLProgram
  parse_krl_query(src)  — parse a single pipeline query → KRLQuery
  parse_sql(src)        — parse SQL SELECT → KRLProgram (translated to KRL AST)
  parse_any(src)        — auto-detect SQL vs KRL and dispatch

Usage from serve.jl:
  include("krl/KRL.jl")
  using .KRL: parse_any, parse_krl_query, KRLParseError
"""
module KRL

include("Lexer.jl")
include("Ast.jl")
include("Parser.jl")
include("SqlFrontend.jl")
include("Evaluator.jl")

end # module KRL
