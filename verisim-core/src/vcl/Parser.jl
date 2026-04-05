# SPDX-License-Identifier: PMPL-1.0-or-later
#
# vcl/Parser.jl — minimal string parser for VCL PROOF subset.
#
# Hand-written tokeniser + recursive descent. Research-prototype — not
# the production VCL parser (that lives in verisimdb/ in ReScript).
#
# Accepts:
#   PROOF INTEGRITY FOR <hex_octad_id>
#   PROOF CONSISTENCY FOR <hex_octad_id>
#     [ OVER { <shape>, ... } ]
#     WITH DRIFT < <float>
#   PROOF FRESHNESS FOR <hex_octad_id> WITHIN <int>ns
#
# Example:
#   PROOF CONSISTENCY FOR 0102030405060708090a0b0c0d0e0f10
#     OVER {semantic, vector}
#     WITH DRIFT < 0.5

module VCLParser

import ..Core
import ..Federation
import ..VCLQuery

export parse_vcl

# -----------------------------------------------------------------------
# Tokeniser
# -----------------------------------------------------------------------

function tokenise(src::AbstractString)::Vector{String}
    # Normalise: uppercase keywords, keep {}, commas, < distinct.
    s = replace(src, "\n" => " ", "\t" => " ")
    # Insert spaces around symbols we need to split on.
    for sym in ["{", "}", ",", "<"]
        s = replace(s, sym => " $sym ")
    end
    filter(!isempty, split(s, " "; keepempty = false))
end

# -----------------------------------------------------------------------
# Parser
# -----------------------------------------------------------------------

mutable struct ParseCursor
    tokens::Vector{String}
    pos::Int
end

peek_tok(c::ParseCursor) = c.pos <= length(c.tokens) ? c.tokens[c.pos] : ""

function consume!(c::ParseCursor)
    c.pos > length(c.tokens) && error("VCLParser: unexpected end of input")
    tok = c.tokens[c.pos]
    c.pos += 1
    tok
end

function expect_kw!(c::ParseCursor, kw::String)
    tok = consume!(c)
    uppercase(tok) == uppercase(kw) || error(
        "VCLParser: expected '$kw', got '$tok' at position $(c.pos-1)")
end

function parse_octad_id(hex::AbstractString)
    length(hex) == 32 || error("VCLParser: octad id must be 32 hex chars, got '$hex'")
    bytes = UInt8[]
    for i in 1:2:31
        push!(bytes, parse(UInt8, hex[i:i+1]; base=16))
    end
    Core.OctadId(bytes)
end

function parse_scope!(c::ParseCursor)::Vector{Symbol}
    expect_kw!(c, "{")
    shapes = Symbol[]
    while true
        tok = consume!(c)
        tok == "}" && break
        tok == "," && continue
        push!(shapes, Symbol(lowercase(tok)))
    end
    shapes
end

function parse_proof!(c::ParseCursor)
    expect_kw!(c, "PROOF")
    kind = uppercase(consume!(c))

    if kind == "INTEGRITY"
        expect_kw!(c, "FOR")
        id = parse_octad_id(consume!(c))
        return VCLQuery.ProofIntegrity(id)

    elseif kind == "CONSISTENCY"
        expect_kw!(c, "FOR")
        id = parse_octad_id(consume!(c))
        scope = Symbol[]
        if uppercase(peek_tok(c)) == "OVER"
            consume!(c)
            scope = parse_scope!(c)
        end
        expect_kw!(c, "WITH")
        expect_kw!(c, "DRIFT")
        expect_kw!(c, "<")
        threshold = parse(Float64, consume!(c))
        # Default weights: uniform over known pairs in scope.
        # Caller can override by constructing ProofConsistency directly.
        weights = _default_weights(scope)
        return VCLQuery.ProofConsistency(id, scope, threshold, weights)

    elseif kind == "FRESHNESS"
        expect_kw!(c, "FOR")
        id = parse_octad_id(consume!(c))
        expect_kw!(c, "WITHIN")
        durtok = consume!(c)
        m = match(r"^(\d+)ns$", durtok)
        m === nothing && error("VCLParser: FRESHNESS expects <N>ns, got '$durtok'")
        window = parse(Int64, m.captures[1])
        return VCLQuery.ProofFreshness(id, window)

    else
        error("VCLParser: unknown PROOF kind '$kind'")
    end
end

function _default_weights(scope::Vector{Symbol})
    # Uniform weights over all ordered pairs among scope. Caller-supplied
    # weights via direct ProofConsistency construction override this.
    pairs = Tuple{Symbol, Symbol}[]
    for i in 1:length(scope), j in i+1:length(scope)
        push!(pairs, (scope[i], scope[j]))
    end
    if isempty(pairs)
        return Federation.DriftWeights(
            Dict{Tuple{Symbol, Symbol}, Float64}())
    end
    w = 1.0 / length(pairs)
    d = Dict{Tuple{Symbol, Symbol}, Float64}()
    for p in pairs
        d[Federation.canonical_pair(p...)] = w
    end
    Federation.DriftWeights(d)
end

"""
    parse_vcl(src::AbstractString) -> ProofClause

Parse a single VCL PROOF clause. Throws on syntax error.
"""
function parse_vcl(src::AbstractString)
    toks = tokenise(src)
    cursor = ParseCursor(toks, 1)
    clause = parse_proof!(cursor)
    cursor.pos <= length(cursor.tokens) && error(
        "VCLParser: trailing tokens after proof clause: " *
        join(cursor.tokens[cursor.pos:end], " "))
    clause
end

end # module
