# GQL-DT Lexical Specification

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

**Version:** 1.0.0
**Date:** 2026-02-01

## Table of Contents

1. [Character Set](#character-set)
2. [Lexical Elements](#lexical-elements)
3. [Keywords](#keywords)
4. [Identifiers](#identifiers)
5. [Literals](#literals)
6. [Operators](#operators)
7. [Punctuation](#punctuation)
8. [Comments](#comments)
9. [Whitespace](#whitespace)
10. [Operator Precedence](#operator-precedence)

---

## 1. Character Set

GQL-DT source files are encoded in **UTF-8**.

**Character Classes:**
- **ASCII:** U+0000 to U+007F
- **Unicode:** Full Unicode 15.0 support (U+0000 to U+10FFFF)
- **Line terminators:** LF (U+000A), CR (U+000D), CRLF (U+000D U+000A)

---

## 2. Lexical Elements

GQL-DT source text is a sequence of **tokens** separated by **whitespace** and **comments**.

**Token Types:**
1. **Keywords** - Reserved words
2. **Identifiers** - Names (variables, tables, columns)
3. **Literals** - Constants (numbers, strings, booleans)
4. **Operators** - Symbols for operations
5. **Punctuation** - Delimiters and separators
6. **Comments** - Ignored by lexer

---

## 3. Keywords

### 3.1 SQL-Style Keywords

Keywords are **case-insensitive** (accepted in any case, but conventionally UPPERCASE).

```
AND, APPLY, AS, ASC, AUDIENCE, BECAUSE, BETWEEN, BY
CHECK, COLLECTION, CONFIDENCE, CONSTRAINT, CORRECTION_HISTORY, CORRECTION_TYPE
CREATE, CREATED_BY
DELETE, DENORMALIZE, DEPENDENCIES, DEPENDENT_TYPES, DESC, DISCOVER, DISCLOSED_AT, DISCLOSED_BY
EDGE, EDGE_COLLECTION, EXISTS
FOR, FROM, FULL, FUNCTIONAL_DEPENDENCIES
GROUP
IF, IN, INNER, INSERT, INTO, INTROSPECT, INVESTIGATION, IRREVERSIBLE, IS
JOIN
LEFT, LIKE, LIMIT
NAVIGATION_PATH, NORMALIZATION, NOT, NULL
ON, OR, ORDER, ORDERED_BY
PROPOSE, PROVENANCE, PROVENANCE_TRACKING
RATIONALE, REASON, RETURNING, RIGHT, ROLLBACK
SAMPLE, SELECT, SET, STRATEGY
TARGET_NORMAL_FORM, TO
UNIQUE, UPDATE
VALUES, VERIFY_PROOFS
WHERE, WITH, WITH_INVERSE, WITH_JUSTIFICATION, WITH_PROOF
```

### 3.2 Type Keywords

Type keywords are **case-sensitive** (must match exactly as shown).

**Primitive Types:**
```
Nat, Int, String, Bool, Float, Char, Unit, UUID, Timestamp
```

**Refinement Types:**
```
BoundedNat, BoundedInt, BoundedFloat
NonEmptyString, Email, ValidUUID
Confidence, PromptDimension, Percentage, Rationale, ActorId
```

**Dependent Types:**
```
Vector, Tracked, PromptScores, NavigationPath, Claim, Belief
Collection, Edge, ReversibleOp
```

**Type Constructors:**
```
Option, Either
```

### 3.3 Normal Form Keywords

```
1NF, 2NF, 3NF, BCNF, 4NF, 5NF
```

### 3.4 Strategy Keywords

```
PreferPreserving, to3NF, toBCNF, toBCNFPreferPreserving
```

### 3.5 Proof Tactic Keywords

```
by, omega, simp, decide, trivial, norm_num, ring, aesop
lithoglyph_bounds, lithoglyph_prov, lithoglyph_prompt
fd_tactic, nf_tactic, lossless_tactic
```

---

## 4. Identifiers

### 4.1 Syntax

**ASCII Identifiers:**
```regex
[A-Za-z_][A-Za-z0-9_]*
```

**Examples:**
```
user_id, evidence, PromptScore, _internal, table123
```

### 4.2 Unicode Identifiers

GQL-DT supports **Unicode identifiers** following Unicode Standard Annex #31:

- **First character:** `XID_Start` category (letters, ideographs, etc.)
- **Subsequent characters:** `XID_Continue` category (letters, digits, underscore, etc.)

**Examples:**
```
café, 用户, données, Σ, α, λ_expr
```

### 4.3 Reserved Identifiers

The following identifiers are **reserved** and cannot be used as user identifiers:

- All keywords (see section 3)
- Built-in function names: `NOW`, `INTERVAL`
- Special identifiers: `$GENERATED_ID`

### 4.4 Case Sensitivity

- **SQL keywords:** Case-insensitive (`SELECT` = `select` = `SeLeCt`)
- **Type keywords:** Case-sensitive (`BoundedNat` ≠ `boundednat`)
- **User identifiers:** Case-sensitive (`userId` ≠ `UserId`)

---

## 5. Literals

### 5.1 Natural Number Literals

**Syntax:**
```regex
[0-9]+
```

**Examples:**
```
0, 42, 100, 9999
```

**Type:** `Nat`

### 5.2 Integer Literals

**Syntax:**
```regex
-?[0-9]+
```

**Examples:**
```
-42, 0, 42, -9999
```

**Type:** `Int`

### 5.3 Float Literals

**Syntax:**
```regex
-?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?
```

**Examples:**
```
0.0, 3.14, -2.718, 1.23e10, 6.022e-23
```

**Type:** `Float`

### 5.4 String Literals

**Single-quoted:**
```
'Hello, world!'
'It''s a beautiful day'  -- Escaped quote
```

**Double-quoted:**
```
"Hello, world!"
"She said \"hi\""  -- Escaped quote
```

**Escape Sequences:**
- `\\` - Backslash
- `\'` - Single quote
- `\"` - Double quote
- `\n` - Newline
- `\r` - Carriage return
- `\t` - Tab
- `\uXXXX` - Unicode code point (4 hex digits)
- `\UXXXXXXXX` - Unicode code point (8 hex digits)

**Type:** `String`

### 5.5 Boolean Literals

```
true, false
```

**Type:** `Bool`

**Note:** Case-insensitive (`TRUE` = `true`)

### 5.6 Unit Literal

```
()
```

**Type:** `Unit`

### 5.7 Timestamp Literals

**Syntax:** ISO 8601 format as string literal

```
'2026-02-01T12:34:56Z'
'2026-02-01T12:34:56.123+00:00'
```

**Type:** `Timestamp`

---

## 6. Operators

### 6.1 Arithmetic Operators

| Operator | Name | Precedence | Associativity |
|----------|------|------------|---------------|
| `^` | Exponentiation | 9 | Right |
| `*` | Multiplication | 8 | Left |
| `/` | Division | 8 | Left |
| `div` | Integer division | 8 | Left |
| `mod` | Modulo | 8 | Left |
| `+` | Addition | 7 | Left |
| `-` | Subtraction (binary) | 7 | Left |
| `-` | Negation (unary) | 10 | Right |

### 6.2 Comparison Operators

| Operator | Name | Precedence | Associativity |
|----------|------|------------|---------------|
| `=` | Equality | 5 | Non-assoc |
| `<>` | Inequality (SQL) | 5 | Non-assoc |
| `!=` | Inequality | 5 | Non-assoc |
| `<` | Less than | 5 | Non-assoc |
| `>` | Greater than | 5 | Non-assoc |
| `<=` | Less or equal | 5 | Non-assoc |
| `>=` | Greater or equal | 5 | Non-assoc |

### 6.3 Set Operators

| Operator | Name | Precedence | Associativity |
|----------|------|------------|---------------|
| `∈` | Element of | 5 | Non-assoc |
| `∉` | Not element of | 5 | Non-assoc |
| `⊆` | Subset | 5 | Non-assoc |
| `⊇` | Superset | 5 | Non-assoc |

### 6.4 Logical Operators

| Operator | ASCII Alt | Name | Precedence | Associativity |
|----------|-----------|------|------------|---------------|
| `¬` | `NOT` | Negation | 4 | Right |
| `∧` | `AND`, `&&` | Conjunction | 3 | Left |
| `∨` | `OR`, `\|\|` | Disjunction | 2 | Left |
| `→` | `=>` | Implication | 1 | Right |
| `⇒` | `==>` | Implication | 1 | Right |
| `↔` | `<=>` | Biconditional | 1 | Right |
| `⇔` | `<==>` | Biconditional | 1 | Right |

### 6.5 Type Operators

| Operator | Name | Precedence | Associativity |
|----------|------|------------|---------------|
| `->` | Function type | 1 | Right |
| `×` | Product type | 6 | Left |
| `⊕` | Sum type | 6 | Left |

### 6.6 Special Operators

| Operator | Name | Precedence | Associativity |
|----------|------|------------|---------------|
| `.` | Field access | 11 | Left |
| `::` | Cons (list prepend) | 6 | Right |
| `,` | Comma (tuple/list sep) | 0 | Left |
| `:` | Type annotation | N/A | N/A |
| `\|` | Type refinement | N/A | N/A |

### 6.7 Lambda Operators

| Operator | ASCII Alt | Name |
|----------|-----------|------|
| `λ` | `\` | Lambda abstraction |

---

## 7. Punctuation

### 7.1 Delimiters

| Symbol | Name |
|--------|------|
| `(` | Left parenthesis |
| `)` | Right parenthesis |
| `[` | Left bracket |
| `]` | Right bracket |
| `{` | Left brace |
| `}` | Right brace |
| `⟨` | Left angle (Lean proof) |
| `⟩` | Right angle (Lean proof) |

### 7.2 Separators

| Symbol | Name |
|--------|------|
| `,` | Comma |
| `;` | Semicolon |
| `.` | Period/dot |
| `:` | Colon |
| `\|` | Pipe/bar |

### 7.3 Special

| Symbol | Name |
|--------|------|
| `--` | Line comment start |
| `/*` | Block comment start |
| `*/` | Block comment end |
| `{-` | Haskell-style comment start |
| `-}` | Haskell-style comment end |

---

## 8. Comments

### 8.1 Line Comments

**Syntax:**
```
-- This is a line comment
```

- Start with `--`
- Extend to end of line
- Can appear anywhere whitespace is allowed

**Example:**
```sql
SELECT * FROM evidence  -- Get all evidence
WHERE prompt_overall > 90  -- High quality only
```

### 8.2 Block Comments

**Syntax (C-style):**
```
/* This is a block comment
   spanning multiple lines */
```

**Syntax (Haskell-style):**
```
{- This is a block comment
   spanning multiple lines -}
```

**Nesting:** Haskell-style comments can nest. C-style cannot.

```haskell
{- Outer comment
   {- Inner comment -}
   Still in outer comment
-}  -- All closed
```

---

## 9. Whitespace

### 9.1 Whitespace Characters

GQL-DT treats the following as **whitespace**:

| Character | Unicode | Name |
|-----------|---------|------|
| Space | U+0020 | SPACE |
| Tab | U+0009 | CHARACTER TABULATION |
| LF | U+000A | LINE FEED |
| CR | U+000D | CARRIAGE RETURN |
| VT | U+000B | LINE TABULATION |
| FF | U+000C | FORM FEED |

### 9.2 Significance

- **Required:** Between adjacent keywords/identifiers
- **Optional:** Around operators, punctuation
- **Ignored:** Multiple consecutive whitespace = single whitespace

**Examples:**
```sql
-- Valid (whitespace required)
SELECT * FROM evidence

-- Invalid (no whitespace)
SELECT*FROMevidence

-- Valid (extra whitespace ignored)
SELECT  *    FROM     evidence
```

### 9.3 Line Terminators

Accepted line terminators:
- **LF** (Unix/Linux/macOS): `\n`
- **CRLF** (Windows): `\r\n`
- **CR** (old Mac): `\r`

---

## 10. Operator Precedence

**Complete precedence table (highest to lowest):**

| Level | Operators | Associativity | Description |
|-------|-----------|---------------|-------------|
| 11 | `.` | Left | Field access |
| 10 | Function application | Left | `f x` |
| 9 | `^` | Right | Exponentiation |
| 8 | `*`, `/`, `div`, `mod` | Left | Multiplicative |
| 7 | `+`, `-` (binary) | Left | Additive |
| 6 | `::`, `×`, `⊕` | Right/Left | List cons, type product/sum |
| 5 | `=`, `<>`, `!=`, `<`, `>`, `<=`, `>=` | Non-assoc | Comparison |
| 5 | `∈`, `∉`, `⊆`, `⊇` | Non-assoc | Set membership |
| 4 | `¬`, `NOT` | Right | Logical negation |
| 3 | `∧`, `AND`, `&&` | Left | Logical conjunction |
| 2 | `∨`, `OR`, `\|\|` | Left | Logical disjunction |
| 1 | `→`, `⇒`, `↔`, `⇔`, `->` | Right | Implication, type arrow |
| 0 | `,` | Left | Comma (separator) |

### 10.1 Associativity Rules

**Left-associative:**
```
a + b + c  =  (a + b) + c
a * b * c  =  (a * b) * c
```

**Right-associative:**
```
a ^ b ^ c  =  a ^ (b ^ c)
a -> b -> c  =  a -> (b -> c)
```

**Non-associative:**
```
a < b < c  =  (SYNTAX ERROR - use a < b AND b < c)
```

### 10.2 Parentheses

Use parentheses to override precedence:

```sql
(a + b) * c  -- Addition first
a + (b * c)  -- Multiplication first (default)
```

---

## 11. Lexical Analysis Algorithm

### 11.1 Maximal Munch Rule

The lexer uses **maximal munch** (longest match):

```
<=  →  Token: <=  (not < followed by =)
->  →  Token: ->  (not - followed by >)
123.45  →  Token: 123.45  (float, not 123 . 45)
```

### 11.2 Token Recognition Priority

1. **Whitespace and comments** - Skipped
2. **Keywords** - Matched before identifiers
3. **Multi-character operators** - Matched before single-char
4. **Literals** - Numbers, strings, booleans
5. **Identifiers** - Alphanumeric + underscore
6. **Single-character operators/punctuation**

### 11.3 Ambiguity Resolution

**Example:** `SELECT*FROM`

- Greedy matching: `SELECT`, `*`, `FROM` (correct)
- Not: `SELECT*F`, `ROM` (incorrect)

**Rule:** Always prefer keyword matches over identifiers.

---

## 12. Lexical Extensions

### 12.1 Unicode Mathematical Symbols

GQL-DT accepts Unicode mathematical symbols with ASCII alternatives:

| Unicode | ASCII | Meaning |
|---------|-------|---------|
| `λ` | `\` | Lambda |
| `∀` | `forall` | Universal quantifier |
| `∃` | `exists` | Existential quantifier |
| `∧` | `AND`, `&&` | Logical AND |
| `∨` | `OR`, `\|\|` | Logical OR |
| `¬` | `NOT` | Logical NOT |
| `→` | `->`, `=>` | Implication, function arrow |
| `⇒` | `==>` | Double implication |
| `↔` | `<=>` | Biconditional |
| `⇔` | `<==>` | Double biconditional |
| `×` | `*` (in type context) | Product type |
| `⊕` | `+` (in type context) | Sum type |
| `∈` | `IN` | Set membership |
| `∉` | `NOT IN` | Not in set |
| `⊆` | `SUBSET` | Subset |
| `⊇` | `SUPERSET` | Superset |

### 12.2 Proof Literals

**Lean 4 proof terms:**
```lean
⟨95, by omega, by omega⟩
```

**Idris 2 proof holes:**
```idris
?proof_name
```

**Inline tactics:**
```lean
by omega
by simp [rule1, rule2]; omega
```

---

## 13. Compatibility Notes

### 13.1 Standard GQL Compatibility

GQL-DT is a **superset** of standard Lithoglyph GQL:

- **All standard GQL keywords** are recognized
- **Type annotations** are optional (inferred if omitted)
- **Proof clauses** are optional (auto-generated or admitted)

### 13.2 SQL Compatibility

GQL-DT follows SQL conventions:

- **Keywords are case-insensitive** (SELECT = select)
- **String literals** use single quotes (standard) or double quotes (PostgreSQL-style)
- **Comments** use `--` (SQL standard) or `/* */` (C-style)

### 13.3 Lean 4 / Idris 2 Compatibility

Type expressions and proof terms can embed:

- **Lean 4 syntax** - Full Lean 4 type expressions in type annotations
- **Idris 2 syntax** - Full Idris 2 proof terms in WITH_PROOF clauses

---

## 14. Error Recovery

### 14.1 Lexical Errors

**Unterminated string:**
```sql
INSERT INTO t VALUES ('unterminated
-- ERROR: Unterminated string literal at line 1
```

**Invalid character:**
```sql
SELECT @ FROM t
-- ERROR: Unexpected character '@' at line 1, column 8
```

**Invalid number:**
```sql
SELECT 1.2.3 FROM t
-- ERROR: Invalid float literal '1.2.3' at line 1, column 8
```

### 14.2 Recovery Strategy

On lexical error:
1. **Report error** with line and column number
2. **Skip to next whitespace** or punctuation
3. **Continue tokenization** (collect all errors)

---

## 15. Implementation Notes

### 15.1 Recommended Tools

- **Lexer generator:** Alex (Haskell), ocamllex (OCaml), Flex (C/C++)
- **Hand-rolled:** Lean 4 Parsec, Rust nom, ReScript combinators

### 15.2 Performance Considerations

- **Unicode normalization:** Normalize identifiers to NFC form
- **Keyword lookup:** Use hash table for O(1) keyword recognition
- **Number parsing:** Use fast float parsing (e.g., `from_str_radix`)

---

## References

1. **ISO/IEC 14977** - EBNF Syntax Notation
2. **Unicode Standard Annex #31** - Unicode Identifier and Pattern Syntax
3. **SQL:2023 Standard** - ISO/IEC 9075
4. **Lean 4 Reference** - https://lean-lang.org/
5. **Idris 2 Tutorial** - https://idris2.readthedocs.io/

---

**Document Status:** Complete lexical specification for GQL-DT v1.0

**See Also:**
- `GQL-DT-Grammar.ebnf` - Formal EBNF grammar
- `GQL_Dependent_Types_Complete_Specification.md` - Type system specification
