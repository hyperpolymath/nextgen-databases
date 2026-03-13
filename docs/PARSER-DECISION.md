# GQL-DT Parser Architecture Decision

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

**Date:** 2026-02-01
**Status:** Decision Required
**Stakeholder:** Production deployment for secure audit projects

## Executive Summary

**Question:** Which parser should GQL-DT use: ANTLR, Tree-sitter, or Idris2/Lean 4-based?

**Answer:** **Lean 4 Parser Combinators** for type checker, **ANTLR** for production tooling

**Rationale:** Dependent types require type-level computation (Lean 4/Idris 2), but production tools can use ANTLR with Lean 4 as verification backend.

---

## Current State: No Parser Yet

### What Exists ✅
- [x] Complete EBNF grammar (`spec/GQL-DT-Grammar.ebnf`)
- [x] Lexical specification
- [x] Type system in Lean 4 (refinement + dependent types)
- [x] Proof tactics and automation

### What's Missing ❌
- [ ] Parser implementation
- [ ] Type checker integration
- [ ] Error messages with suggestions
- [ ] IDE integration (LSP)

**Status:** Milestone 6 (Parser) is ready to start (unblocked by grammar completion today)

---

## The Central Question: Can You Have Dependent Types Without Idris2/Lean?

### Short Answer: **No**

**Dependent types require compile-time computation, which requires a proof assistant.**

### Why?

Dependent types allow **types to depend on values**:

```lean
-- This is a TYPE that depends on VALUES (n, min, max)
def BoundedNat (min max : Nat) := { n : Nat // min ≤ n ∧ n ≤ max }

-- The type checker must PROVE this at compile time
def score95 : BoundedNat 0 100 := ⟨95, by omega, by omega⟩
--                                        ^^^^^^^^  ^^^^^^^^
--                                        PROOFS executed at compile time
```

**This computation happens in:**
- **Lean 4** - Type checker executes tactics (`omega`, `simp`, etc.)
- **Idris 2** - Type checker executes proof scripts
- **Coq** - Type checker verifies proof terms
- **Agda** - Type checker normalizes terms

**ANTLR/Tree-sitter cannot do this** - they parse syntax, not execute proofs.

---

## Parser Options Analysis

### Option 1: Lean 4 Parser Combinators (RECOMMENDED)

**Architecture:**
```
GQL Source
    ↓
Lean 4 Parser (Parsec combinators)
    ↓
Lean 4 AST
    ↓
Type Checker (with proof search)
    ↓
Type-checked IR + Proofs
    ↓
Code Generator → Standard GQL (for Lithoglyph runtime)
```

**Pros:**
- ✅ **Native proof support** - Type checker can verify proofs inline
- ✅ **Tight integration** - Parser + type checker in same language
- ✅ **Proof automation** - Tactics (`omega`, `simp`) work seamlessly
- ✅ **LSP support** - Lean 4 has excellent IDE integration
- ✅ **Type inference** - Lean 4 can infer types where not specified
- ✅ **Error messages** - Lean 4 provides detailed type error messages

**Cons:**
- ⚠️ **Lean 4 dependency** - Users need Lean 4 installed
- ⚠️ **Learning curve** - Developers need Lean 4 knowledge
- ⚠️ **Compilation time** - Lean 4 can be slow (caching helps)

**Production Readiness:**
- **Lean 4 is production-ready** (used by Microsoft Research, Galois, etc.)
- **Large ecosystem** - Mathlib4 (400k+ lines of verified math)
- **Active development** - v4.15.0 (2025), stable releases every 2 months
- **Commercial use** - Used in aerospace (Galois), finance (Jane Street via OCaml extraction)

**Example Implementation:**
```lean
-- src/FbqlDt/Parser.lean
import Lean.Data.Parsec

namespace FbqlDt.Parser

open Lean Parsec

-- Parse INSERT statement
def parseInsert : Parsec InsertStmt := do
  skipString "INSERT"
  skipWs
  skipString "INTO"
  skipWs
  let table ← parseIdentifier
  skipWs
  let columns ← parseColumnList
  skipWs
  skipString "VALUES"
  skipWs
  let values ← parseValueList
  skipWs
  let rationale ← parseRationale
  skipWs
  let proof ← optional parseProofClause
  return { table, columns, values, rationale, proof }

-- Parse proof clause
def parseProofClause : Parsec ProofClause := do
  skipString "WITH_PROOF"
  skipWs
  skipChar '{'
  skipWs
  let obligations ← sepBy parseProofObligation (skipChar ',')
  skipWs
  skipChar '}'
  return { obligations }
```

---

### Option 2: ANTLR (Grammar-First)

**Architecture:**
```
GQL Source
    ↓
ANTLR Parser (Java/Python/C++)
    ↓
Generic AST (JSON/protobuf)
    ↓
Lean 4 Type Checker (via FFI)
    ↓
Type-checked IR + Proofs
```

**Pros:**
- ✅ **Language-agnostic** - Generate parsers in Java, Python, C++, JavaScript
- ✅ **Fast parsing** - LL(*) parsing is efficient
- ✅ **Tooling** - ANTLRWorks for grammar visualization
- ✅ **Mature** - Used in production (Hive, Presto, Spark SQL)

**Cons:**
- ❌ **Two-phase architecture** - Parse in ANTLR, type-check in Lean 4
- ❌ **FFI overhead** - Need to serialize AST between ANTLR and Lean 4
- ❌ **Duplicate logic** - Grammar in ANTLR, types in Lean 4
- ❌ **Error reporting** - Syntax errors from ANTLR, type errors from Lean 4 (inconsistent UX)
- ❌ **No proof integration** - ANTLR can't execute `by omega`

**When to use:**
- Tooling that doesn't need type checking (syntax highlighters, formatters)
- Migration path (parse GQL with ANTLR, upgrade to Lean 4 later)

---

### Option 3: Tree-sitter (Incremental Parsing)

**Architecture:**
```
GQL Source
    ↓
Tree-sitter Parser (C)
    ↓
Syntax Tree (C API)
    ↓
Lean 4 Type Checker (via C FFI)
```

**Pros:**
- ✅ **Incremental parsing** - Fast re-parsing on edit (great for IDE)
- ✅ **Error recovery** - Produces partial trees even with syntax errors
- ✅ **Language-agnostic** - Bindings for Rust, JavaScript, Python
- ✅ **Used in production** - GitHub code search, Neovim, Atom

**Cons:**
- ❌ **C dependency** - Must write grammar in JavaScript, generates C code
- ❌ **Same FFI issues as ANTLR** - Need bridge to Lean 4
- ❌ **No proof support** - Can't execute tactics
- ❌ **Complex grammar format** - Tree-sitter DSL is different from EBNF

**When to use:**
- IDE plugins (syntax highlighting, code folding)
- Incremental re-parsing for interactive editors

---

### Option 4: Idris 2 (Alternative to Lean 4)

**Architecture:**
```
GQL Source
    ↓
Idris 2 Parser (Lightyear combinators)
    ↓
Idris 2 AST
    ↓
Type Checker (with proof search)
    ↓
Type-checked IR + Proofs
```

**Pros:**
- ✅ **Full dependent types** - Same power as Lean 4
- ✅ **Simpler syntax** - More Haskell-like (easier for FP developers)
- ✅ **Proof support** - Can verify proofs inline

**Cons:**
- ⚠️ **Smaller ecosystem** - Mathlib4 (Lean) >> Contrib (Idris)
- ⚠️ **Less industrial use** - Lean 4 has more commercial adoption
- ⚠️ **LSP less mature** - Lean 4 LSP is more polished
- ⚠️ **Your concern applies here too** - Idris 2 is also specialist

**Production Readiness:**
- **Idris 2 is production-ready** (v0.7.0, Jan 2024)
- **Used in:** Embedded systems, blockchain smart contracts
- **Smaller community** than Lean 4

---

## Addressing Your Concerns

### Concern 1: "Idris2 brings me concerns, as it is quite specialist"

**You're right to be concerned.** Here's the reality:

#### Specialist vs. Production Trade-off

| Language | Specialist? | Production Use? |
|----------|-------------|-----------------|
| **Lean 4** | **Yes** (proof assistant) | **Yes** (Microsoft Research, Galois, AWS) |
| **Idris 2** | **Yes** (proof assistant) | **Some** (embedded, blockchain) |
| **Coq** | **Yes** (proof assistant) | **Yes** (CompCert, Fiat-Crypto) |
| **F*** | **Yes** (proof assistant) | **Yes** (HACL*, miTLS) |
| **Dafny** | **Yes** (verification) | **Yes** (Amazon, Microsoft) |

**The pattern:** All verification tools are specialist. But they're used in production for critical systems.

#### Why Lean 4 is the "Least Specialist" Choice

1. **Industrial backing** - Microsoft Research, AWS (s2n-quic verified TLS)
2. **Large ecosystem** - Mathlib4 (400k+ lines), active community
3. **Best LSP** - IntelliJ, VSCode, Emacs support out of the box
4. **Regular releases** - Stable, predictable release cycle
5. **Migration path** - Can extract to OCaml/C for production runtime

---

### Concern 2: "I want this to be a production language for extreme secure audit projects"

**Good news:** Dependent types + production use is proven in industry.

#### Production Deployments of Dependent Types

1. **HACL*** (F*)
   - Cryptography library (TLS, X25519, Curve25519)
   - Used in: Firefox, mbedTLS, EverCrypt
   - **Fully verified**, compiles to C

2. **CompCert** (Coq)
   - C compiler with **proven correctness**
   - Used in: Aerospace (Airbus), automotive (Renault)

3. **seL4** (Isabelle/HOL)
   - Microkernel with **full functional correctness proof**
   - Used in: Defense, autonomous vehicles

4. **Dafny** (Microsoft)
   - Used at Amazon for cryptographic correctness
   - IronFleet (distributed systems verification)

**The lesson:** Dependent types ARE production-ready, but only for teams with verification expertise.

---

## Recommended Architecture: Hybrid Approach

### For GQL-DT: **Lean 4 Core + ANTLR Tooling**

```
┌─────────────────────────────────────────────────────────────┐
│  Production Tools (ANTLR-based)                              │
│  - Syntax highlighter (VSCode extension)                     │
│  - Code formatter                                            │
│  - Quick syntax validation                                   │
│  → Fast, no proof checking                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Type Checker (Lean 4-based)                                 │
│  - Parse GQL with Lean 4 Parsec                              │
│  - Type check with proof obligations                         │
│  - Generate proofs with tactics                              │
│  → Slow, but correct                                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Runtime (Lithoglyph)                                            │
│  - Execute type-erased GQL                                   │
│  - Proofs stored in journal (optional verification)          │
│  → Fast, proofs already verified                             │
└─────────────────────────────────────────────────────────────┘
```

### Workflow

**Development (Lean 4):**
```bash
# Developer writes GQL with types
vim query.gql.lean

# Type check with Lean 4 (includes proof search)
lean4 --check query.gql.lean
# ✓ All proofs valid

# Generate runtime GQL (proofs erased)
lean4 --codegen gql query.gql.lean > query.gql

# Execute on Lithoglyph
lithoglyph execute query.gql
```

**Production (optional):**
```bash
# Quick syntax check with ANTLR (fast, no proofs)
gqldt-lint query.gql
# ✓ Syntax OK (proofs not checked)

# Full verification with Lean 4 (slow, complete)
gqldt-verify query.gql
# ✓ Type-checked, proofs valid
```

---

## Decision Matrix

| Criterion | Lean 4 | ANTLR | Tree-sitter | Idris 2 |
|-----------|--------|-------|-------------|---------|
| **Proof support** | ✅ Native | ❌ Via FFI | ❌ Via FFI | ✅ Native |
| **Production use** | ✅ Microsoft, AWS | ✅ Widespread | ✅ GitHub, Neovim | ⚠️ Limited |
| **IDE support** | ✅ Excellent LSP | ✅ Good | ✅ Excellent | ⚠️ Basic |
| **Learning curve** | ⚠️ Steep | ✅ Moderate | ✅ Moderate | ⚠️ Steep |
| **Performance** | ⚠️ Slow compile | ✅ Fast | ✅ Fast | ⚠️ Slow compile |
| **Ecosystem** | ✅ Mathlib4 | ✅ Large | ✅ Large | ⚠️ Small |
| **Type inference** | ✅ Yes | ❌ No | ❌ No | ✅ Yes |
| **Error messages** | ✅ Excellent | ✅ Good | ⚠️ Basic | ✅ Good |

---

## Recommendation: Lean 4 Parser Combinators

### Why Lean 4?

1. **Dependent types require proof execution** - Only Lean 4/Idris 2/Coq can do this
2. **Production-ready** - Used in industry for critical systems
3. **Best ecosystem** - Mathlib4, active community, regular releases
4. **Best LSP** - Lean 4 VSCode extension is excellent
5. **Proven in secure contexts** - AWS s2n-quic, aerospace verification

### Addressing "Too Specialist" Concern

**Reality check:** If you need dependent types, you need a proof assistant. There's no way around this.

**Options:**
1. **Accept Lean 4 as dependency** - It's the best tool for the job
2. **Provide ANTLR fallback** - Fast syntax-only checking for tooling
3. **Extract to C/OCaml** - Compile verified code for runtime (proof erasure)

**Analogy:** You wouldn't avoid Rust because "ownership types are specialist." Lean 4 is the Rust of theorem provers - modern, practical, production-ready.

---

## Implementation Plan

### Phase 1: Lean 4 Parser (Milestone 6)

**File:** `src/FbqlDt/Parser.lean`

```lean
import Lean.Data.Parsec
import FbqlDt.Types
import FbqlDt.AST

namespace FbqlDt.Parser

-- Use Lean 4 Parsec combinators
def parseGQL : String → Except String TypedAST := ...
```

**Deliverables:**
- [ ] Lexer (tokenization)
- [ ] Parser (EBNF → Lean 4 Parsec)
- [ ] Type checker integration
- [ ] Error messages

### Phase 2: ANTLR Tooling (Optional)

**File:** `tools/GQL-DT.g4`

```antlr
grammar GQL-DT;

program : statement* EOF ;

statement
    : createCollection
    | insertStatement
    | selectStatement
    ;

// ... (rest of grammar from EBNF)
```

**Use cases:**
- VSCode syntax highlighting
- Code formatter
- Quick lint (no proofs)

### Phase 3: Production Hardening

- [ ] Proof caching (incremental type checking)
- [ ] Error recovery (partial parsing)
- [ ] LSP integration (autocomplete, go-to-definition)

---

## Conclusion

**Answer to your question:**

> Which parser should I use: ANTLR, Tree-sitter, or Idris2-based?

**Recommended:** **Lean 4 Parser Combinators**

**Reasoning:**
1. Dependent types **require** proof execution → Need Lean 4/Idris 2
2. Lean 4 is **more production-ready** than Idris 2 (larger ecosystem, better tooling)
3. ANTLR/Tree-sitter **cannot execute proofs** → Can only do syntax, not semantics
4. Lean 4 is used in **production for secure systems** (AWS, aerospace)

**Your concern about "too specialist" is valid, but:**
- All verification tools are specialist (Lean 4, Idris 2, Coq, Dafny)
- Lean 4 is the **least specialist** of the proof assistants (best LSP, largest community)
- For "extreme secure audit projects", proof assistants are the **right tool**

**Fallback:** Add ANTLR-based tooling for fast syntax checking (IDEs, linters), but keep Lean 4 for type checking.

---

## Next Steps

1. ✅ **Accept Lean 4 as core dependency** (already done - Milestones 1-4 use Lean 4)
2. Start Milestone 6: Implement parser in `src/FbqlDt/Parser.lean`
3. Add ANTLR grammar for tooling (optional, later)
4. Document Lean 4 installation for users

---

## References

1. **Lean 4 in Production:**
   - AWS s2n-quic: https://github.com/aws/s2n-quic
   - Galois formal methods: https://galois.com/

2. **Other Production Proof Assistants:**
   - HACL* (F*): https://github.com/hacl-star/hacl-star
   - CompCert (Coq): https://compcert.org/
   - seL4 (Isabelle): https://sel4.systems/

3. **Lean 4 Documentation:**
   - Official: https://lean-lang.org/
   - Theorem Proving in Lean 4: https://leanprover.github.io/theorem_proving_in_lean4/

---

**Document Status:** Recommendation for parser architecture

**Decision Required:** Accept Lean 4 as core dependency?

**Stakeholder:** Jonathan D.A. Jewell (production deployment for secure audits)
