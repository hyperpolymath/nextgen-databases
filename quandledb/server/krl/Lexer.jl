# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 for Julia ecosystem consistency)
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
KRL Lexer — tokenises a KRL (Knot Resolution Language) source string.

Follows grammar.ebnf v0.1.0 exactly. All 50+ keywords are recognised.

Token kinds (Symbol tags):
  Literals:   :integer   — `123`
              :float     — `1.5`
              :string    — `"hello"`
              :bool      — `true` / `false`
              :knot_name — `3_1`, `10_139` (digit `_` digit form)
  Names:      :keyword   — reserved word
              :identifier — user name or invariant name
  Operators:  :eq          (`==`)
              :neq         (`!=`)
              :lt          (`<`)
              :lte         (`<=`)
              :gt          (`>`)
              :gte         (`>=`)
              :plus        (`+`)
              :minus       (`-`)
              :star        (`*`)
              :slash       (`/`)
              :percent     (`%`)
              :pipe        (`|`)
              :arrow       (`->`)
              :fat_arrow   (`=>`)
              :tilde_arrow (`~>`)
              :iso         (`≅` or `~=` — normalised to one token kind)
              :null_coalesce (`??`)
              :dot         (`.`)
              :colon       (`:`)
              :comma       (`,`)
              :semi        (`;`)
  Delimiters: :lparen, :rparen, :lbracket, :rbracket, :lbrace, :rbrace
  Special:    :eof

Innovations vs KRLAdapter.jl:
  - `:knot_name` token: `3_1`, `5_2`, `10_139` (digit-underscore-digit) emitted
    as a dedicated token, not split into integer + identifier.
  - Float literals: `1.5`, `3.14`.
  - Block comments `{- ... -}` with nesting depth tracking (depth > 1 is an
    innovation allowing nested comment-out blocks).
  - Unicode operator `≅` normalised to `:iso` (same as ASCII `~=`).
  - All 50 KRL keywords, including compound forms (`find_equivalent`, `group_by`).
"""

export Token, TokenKind, tokenise, KRLLexError

# ─────────────────────────────────────────────────────────────────────────────
# Token kind
# ─────────────────────────────────────────────────────────────────────────────

const TokenKind = Symbol

# ─────────────────────────────────────────────────────────────────────────────
# Reserved words (must stay in sync with grammar.ebnf keyword list)
# ─────────────────────────────────────────────────────────────────────────────

const KRL_KEYWORDS = Set([
    # pipeline stages
    "from", "filter", "sort", "take", "skip", "return",
    "group_by", "aggregate",
    # equivalence / path queries
    "find_equivalent", "find_path", "match", "via",
    # logical / comparison
    "and", "or", "not", "in",
    # specifiers
    "as", "with", "let", "where",
    # provenance
    "provenance",
    # confidence levels
    "confidence", "exact", "necessary", "sufficient", "heuristic",
    # sort direction
    "asc", "desc",
    # aggregate functions (also plain identifiers in function-call position)
    "count", "min", "max", "avg", "sum",
    # collections
    "knots", "diagrams", "invariants",
    # path methods
    "reidemeister", "isotopy",
    # return items
    "equivalences", "equivalence_class", "proof",
    # rule / axiom
    "rule", "define", "axiom", "forall",
    # boolean literals (also handled in literal branch, keyword tag wins)
    "true", "false",
    # option absent
    "none",
    # type names (doubled as keywords so the parser can recognise them)
    "Int", "Float", "String", "Bool",
    "Knot", "Diagram", "Polynomial", "GaussCode", "Quandle",
    "Equivalence", "Option", "List", "Set", "Map", "ResultSet", "Provenance",
])

# ─────────────────────────────────────────────────────────────────────────────
# Token
# ─────────────────────────────────────────────────────────────────────────────

"""
    Token

A single lexical unit produced by `tokenise`.

Fields:
- `kind::TokenKind` — symbolic tag (see Lexer.jl header)
- `value::String`   — raw text of the token (empty for `:eof`)
- `line::Int`       — 1-based source line of first character
- `col::Int`        — 1-based column of first character
"""
struct Token
    kind::TokenKind
    value::String
    line::Int
    col::Int
end

Base.show(io::IO, t::Token) =
    print(io, "Token($(t.kind), $(repr(t.value)), L$(t.line):C$(t.col))")

# ─────────────────────────────────────────────────────────────────────────────
# Lex error
# ─────────────────────────────────────────────────────────────────────────────

"""
    KRLLexError(msg, line, col)

Thrown by `tokenise` on unexpected characters, unterminated strings, or
unterminated block comments.
"""
struct KRLLexError <: Exception
    msg::String
    line::Int
    col::Int
end

Base.showerror(io::IO, e::KRLLexError) =
    print(io, "KRLLexError at L$(e.line):C$(e.col): $(e.msg)")

# ─────────────────────────────────────────────────────────────────────────────
# Tokeniser
# ─────────────────────────────────────────────────────────────────────────────

"""
    tokenise(src::String) -> Vector{Token}

Scan `src` and return all tokens. The last element is always `Token(:eof, "", …)`.

Throws `KRLLexError` on unrecognised characters, unterminated string literals,
or unterminated block comments.
"""
function tokenise(src::String)::Vector{Token}
    tokens = Token[]
    chars  = collect(src)   # Unicode-aware char array
    n      = length(chars)
    i      = 1
    line   = 1
    col    = 1

    # Inline helpers ─────────────────────────────────────────────────────────

    @inline function advance!()
        c = chars[i]; i += 1
        if c == '\n'; line += 1; col = 1; else; col += 1; end
        c
    end

    @inline peek()  = i     <= n ? chars[i]     : '\0'
    @inline peek2() = i + 1 <= n ? chars[i + 1] : '\0'

    @inline function emit(kind, val, sl, sc)
        push!(tokens, Token(kind, val, sl, sc))
    end

    # Main scan loop ─────────────────────────────────────────────────────────

    while i <= n
        sl = line; sc = col   # start line/col of this token
        c = advance!()

        # ── whitespace ───────────────────────────────────────────────────────
        if c == ' ' || c == '\t' || c == '\r' || c == '\n'
            continue
        end

        # ── line comment: -- to EOL ──────────────────────────────────────────
        if c == '-' && peek() == '-'
            advance!()
            while i <= n && chars[i] != '\n'; advance!(); end
            continue
        end

        # ── block comment: {- ... -} with nesting ────────────────────────────
        if c == '{' && peek() == '-'
            advance!()          # consume '-'
            depth = 1
            while depth > 0
                i > n && throw(KRLLexError("unterminated block comment", sl, sc))
                ch = advance!()
                if ch == '{' && peek() == '-'; advance!(); depth += 1
                elseif ch == '-' && peek() == '}'; advance!(); depth -= 1
                end
            end
            continue
        end

        # ── string literals ──────────────────────────────────────────────────
        if c == '"'
            buf = Char[]
            while true
                i > n && throw(KRLLexError("unterminated string literal", sl, sc))
                ch = advance!()
                if ch == '"'; break
                elseif ch == '\\'
                    i > n && throw(KRLLexError("unterminated escape sequence", sl, sc))
                    esc = advance!()
                    push!(buf, esc == 'n' ? '\n' :
                               esc == 't' ? '\t' :
                               esc == 'r' ? '\r' : esc)
                else
                    push!(buf, ch)
                end
            end
            emit(:string, String(buf), sl, sc)
            continue
        end

        # ── numeric literals: integer, float, or knot_name ───────────────────
        #   knot_name pattern: digit+ '_' digit+   (e.g. 3_1, 10_139)
        #   float pattern:     digit+ '.' digit+
        #   integer pattern:   digit+
        if isdigit(c)
            buf = [c]
            while i <= n && isdigit(peek()); push!(buf, advance!()); end
            if peek() == '_' && i + 1 <= n && isdigit(peek2())
                push!(buf, advance!())   # consume '_'
                while i <= n && isdigit(peek()); push!(buf, advance!()); end
                emit(:knot_name, String(buf), sl, sc)
            elseif peek() == '.' && i + 1 <= n && isdigit(peek2())
                push!(buf, advance!())   # consume '.'
                while i <= n && isdigit(peek()); push!(buf, advance!()); end
                emit(:float, String(buf), sl, sc)
            else
                emit(:integer, String(buf), sl, sc)
            end
            continue
        end

        # ── identifiers and keywords ─────────────────────────────────────────
        #   Identifiers may contain letters, digits, underscores, hyphens.
        #   Compound keywords like `find_equivalent` and `group_by` are matched
        #   as single identifiers and then classified via KRL_KEYWORDS.
        if isletter(c) || c == '_'
            buf = [c]
            while i <= n && (isletter(peek()) || isdigit(peek()) || peek() == '_' || peek() == '-')
                push!(buf, advance!())
            end
            word = String(buf)
            kind = word in KRL_KEYWORDS ? :keyword : :identifier
            emit(kind, word, sl, sc)
            continue
        end

        # ── Unicode operator: ≅ (propositional equivalence) ──────────────────
        if c == '≅'
            emit(:iso, "≅", sl, sc)
            continue
        end

        # ── two-character and single-character operators ──────────────────────

        if c == '='
            if peek() == '='
                advance!(); emit(:eq, "==", sl, sc)
            else
                throw(KRLLexError("bare `=` is not a KRL operator; did you mean `==`?", sl, sc))
            end
            continue
        end

        if c == '!'
            peek() == '=' || throw(KRLLexError("expected `!=`, got bare `!`", sl, sc))
            advance!(); emit(:neq, "!=", sl, sc)
            continue
        end

        if c == '<'
            if peek() == '='; advance!(); emit(:lte, "<=", sl, sc)
            else; emit(:lt, "<", sl, sc); end
            continue
        end

        if c == '>'
            if peek() == '='; advance!(); emit(:gte, ">=", sl, sc)
            else; emit(:gt, ">", sl, sc); end
            continue
        end

        if c == '-'
            if peek() == '>'; advance!(); emit(:arrow, "->", sl, sc)
            else; emit(:minus, "-", sl, sc); end
            continue
        end

        if c == '='
            if peek() == '>'; advance!(); emit(:fat_arrow, "=>", sl, sc)
            else; emit(:eq, "=", sl, sc); end
            continue
        end

        if c == '~'
            if peek() == '>'; advance!(); emit(:tilde_arrow, "~>", sl, sc)
            elseif peek() == '='; advance!(); emit(:iso, "~=", sl, sc)
            else; throw(KRLLexError("expected `~>` or `~=`, got bare `~`", sl, sc)); end
            continue
        end

        if c == '?'
            peek() == '?' || throw(KRLLexError("expected `??`, got bare `?`", sl, sc))
            advance!(); emit(:null_coalesce, "??", sl, sc)
            continue
        end

        # single-char operators
        if c == '+';  emit(:plus,     "+", sl, sc); continue; end
        if c == '*';  emit(:star,     "*", sl, sc); continue; end
        if c == '/';  emit(:slash,    "/", sl, sc); continue; end
        if c == '%';  emit(:percent,  "%", sl, sc); continue; end
        if c == '|';  emit(:pipe,     "|", sl, sc); continue; end
        if c == '.';  emit(:dot,      ".", sl, sc); continue; end
        if c == ':';  emit(:colon,    ":", sl, sc); continue; end
        if c == ',';  emit(:comma,    ",", sl, sc); continue; end
        if c == ';';  emit(:semi,     ";", sl, sc); continue; end
        if c == '(';  emit(:lparen,   "(", sl, sc); continue; end
        if c == ')';  emit(:rparen,   ")", sl, sc); continue; end
        if c == '[';  emit(:lbracket, "[", sl, sc); continue; end
        if c == ']';  emit(:rbracket, "]", sl, sc); continue; end
        if c == '}';  emit(:rbrace,   "}", sl, sc); continue; end

        # '{' is a block-comment start only if followed by '-' (handled above).
        # Otherwise it opens a record literal.
        if c == '{';  emit(:lbrace,   "{", sl, sc); continue; end

        throw(KRLLexError("unexpected character $(repr(c))", sl, sc))
    end

    emit(:eof, "", line, col)
    tokens
end
