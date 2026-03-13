# GQL-DT Specification Suite

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

**Version:** 1.0.0
**Status:** Complete formal specification
**Date:** 2026-02-01

## Overview

This directory contains the complete formal specification for **GQL-DT** (Lithoglyph Query Language with Dependent Types), including grammar, semantics, examples, and visual diagrams.

## Specification Documents

### 1. Core Specifications

| Document | Purpose | Status | Lines |
|----------|---------|--------|-------|
| **GQL_Dependent_Types_Complete_Specification.md** | Type system, semantics, examples | ✅ Complete | 1,337 |
| **normalization-types.md** | Functional dependencies, normal forms | ✅ Complete | 753 |
| **GQL-DT-Grammar.ebnf** | Formal EBNF grammar | ✅ Complete | 800+ |
| **GQL-DT-Lexical.md** | Lexical specification | ✅ Complete | 700+ |
| **GQL-DT-Railroad-Diagrams.md** | Visual syntax diagrams | ✅ Complete | 600+ |

### 2. Supporting Documentation

| Document | Purpose | Location |
|----------|---------|----------|
| **WP06_Dependently_Typed_Lithoglyph.md** | Research whitepaper | `../docs/` |
| **STATE.scm** | Project state tracking | `../` |
| **ECOSYSTEM.scm** | Ecosystem positioning | `../` |

## Quick Start

### For Implementers

1. **Start with:** `GQL-DT-Grammar.ebnf` - Complete syntax
2. **Then read:** `GQL-DT-Lexical.md` - Tokenization rules
3. **Reference:** `GQL_Dependent_Types_Complete_Specification.md` - Type system
4. **Visual aid:** `GQL-DT-Railroad-Diagrams.md` - Syntax diagrams

### For Users

1. **Start with:** `GQL_Dependent_Types_Complete_Specification.md` - Examples and usage
2. **Deep dive:** `normalization-types.md` - Database normalization
3. **Visual aid:** `GQL-DT-Railroad-Diagrams.md` - See syntax visually
4. **Research:** `../docs/WP06_Dependently_Typed_Lithoglyph.md` - Motivation and theory

### For Researchers

1. **Theory:** `../docs/WP06_Dependently_Typed_Lithoglyph.md` - Dependent types for databases
2. **Type system:** `GQL_Dependent_Types_Complete_Specification.md` (Section 2-4)
3. **Proofs:** `GQL_Dependent_Types_Complete_Specification.md` (Section 8-9)
4. **Normalization:** `normalization-types.md` - Proof-carrying evolution

## Specification Status

### ✅ Complete

- [x] Type system documentation (Lean 4 notation)
- [x] Refinement types (BoundedNat, NonEmptyString, etc.)
- [x] Dependent types (Vector, Tracked, PromptScores, etc.)
- [x] Proof obligations and tactics
- [x] Complete examples (BoFIG case study)
- [x] Normalization types (functional dependencies, normal forms)
- [x] **Formal EBNF grammar** (NEW: 2026-02-01)
- [x] **Lexical specification** (NEW: 2026-02-01)
- [x] **Railroad diagrams** (NEW: 2026-02-01)

### 🔄 In Progress

- [ ] Reference implementation (Lean 4 parser + type checker)
- [ ] Proof automation tactics library
- [ ] IDE integration (VSCode extension)

### 📋 Planned

- [ ] Formal semantics in Lean 4 (operational + type soundness)
- [ ] Performance benchmarks
- [ ] User study (developer experience)

## Key Features

### Type System

- **Refinement types:** Values with compile-time constraints
  - `BoundedNat 0 100` - Natural numbers in [0, 100]
  - `NonEmptyString` - Strings that cannot be empty
  - `Confidence` - Floats in [0.0, 1.0]

- **Dependent types:** Types that depend on values
  - `Vector α n` - Arrays of exactly n elements
  - `Tracked α` - Values with mandatory provenance
  - `PromptScores` - PROMPT framework scores with computed overall

- **Proof obligations:** Compile-time verification
  - `WITH_PROOF { score_valid: by lithoglyph_prompt }`
  - Automatic proof search (omega, simp, decide)
  - Manual proofs for complex cases

### DDL Extensions

```gql
-- Type-safe collection with normal form guarantee
CREATE COLLECTION evidence (
  id : UUID PRIMARY KEY,
  title : NonEmptyString,
  prompt_scores : PromptScores
) WITH DEPENDENT_TYPES, TARGET_NORMAL_FORM BCNF;
```

### DML with Proofs

```gql
-- Insert with automatic proof generation
INSERT INTO evidence (title, prompt_scores)
VALUES ('ONS CPI Data', {
  provenance: 100,
  replicability: 100,
  objective: 95,
  methodology: 95,
  publication: 100,
  transparency: 95
  -- overall: computed automatically with proof
})
RATIONALE "Official UK government statistics"
WITH_PROOF {
  scores_in_bounds: by lithoglyph_prompt,
  provenance_tracked: by lithoglyph_prov
};
```

### Queries with Refinements

```gql
-- Query with type-level guarantee
SELECT (e : Evidence | e.prompt_overall > 90)
FROM evidence e
WHERE investigation_id = 'uk_inflation_2023'
RETURNING (List (Evidence | prompt_overall > 90));
-- Return type PROVES all results have prompt_overall > 90
```

### Normalization

```gql
-- Discover functional dependencies
DISCOVER DEPENDENCIES FROM employees
SAMPLE 10000 CONFIDENCE 0.95;

-- Propose normalization to BCNF
PROPOSE NORMALIZATION employees TO BCNF
STRATEGY PreferPreserving;

-- Apply with lossless proof
APPLY NORMALIZATION proposal_id
WITH_PROOF {
  lossless: by decomposition_lossless,
  achieves_bcnf: by bcnf_decomposition_correct
}
RATIONALE "Eliminating transitive dependency";
```

## Grammar Overview

### Statements

```
Statement ::= DDL | DML | Query | Normalization | Introspection

DDL ::= CREATE COLLECTION | CREATE EDGE_COLLECTION | CREATE CONSTRAINT
      | CREATE NAVIGATION_PATH

DML ::= INSERT | UPDATE | DELETE | INSERT EDGE

Query ::= SELECT ... FROM ... WHERE ... RETURNING ...

Normalization ::= DISCOVER | CHECK | PROPOSE | APPLY | DENORMALIZE

Introspection ::= INTROSPECT ... | ROLLBACK NORMALIZATION
```

### Type Expressions

```
TypeExpr ::= Primitive | Refined | Dependent | Function | Product | Quantified

Primitive ::= Nat | Int | String | Bool | Float | UUID | Timestamp

Refined ::= BoundedNat min max | BoundedFloat min max
          | NonEmptyString | Email | Confidence

Dependent ::= Vector α n | Tracked α | PromptScores
            | NavigationPath ordering | Claim confidence

Function ::= α -> β | (params) -> β

Product ::= α × β | (α, β, ...)

Quantified ::= ∀ (x : α), P x | ∃ (x : α), P x
```

## Implementation Status

### Phase 1: Refinement Types (✅ Milestone 1-4 Complete)

- [x] Lean 4 project setup (v4.15.0 + Mathlib4)
- [x] BoundedNat, BoundedInt with proofs
- [x] NonEmptyString, Confidence
- [x] PromptScores with auto-computed overall
- [x] Provenance tracking (ActorId, Rationale, Tracked)

### Phase 2: Zig FFI Bridge (⏳ Milestone 5 - Next)

- [ ] `bridge/fdb_types.zig` - FFI type definitions
- [ ] `bridge/fdb_insert.zig` - Insert with proof blob
- [ ] Lean 4 @[extern] declarations
- [ ] Integration tests

### Phase 3: GQL Parser (📋 Milestone 6 - Blocked on M5)

- [ ] Parser from EBNF grammar (NOW UNBLOCKED - grammar complete!)
- [ ] Type inference
- [ ] Proof obligation generation
- [ ] Error messages with suggestions

## Testing

### Example Datasets

1. **BoFIG UK Inflation 2023** - Complete case study in spec
   - 7 claims, 10 evidence items, 10 relationships
   - PROMPT scores, provenance tracking
   - Navigation paths for different audiences

2. **Zotero-Lithoglyph** - Production pilot
   - Reference manager with PROMPT scores
   - Real-world refinement type usage

### Proof Tactics

```lean
-- Lithoglyph-specific tactics
lithoglyph_bounds   -- Auto-solve bounded value proofs
lithoglyph_prov     -- Auto-solve provenance proofs
lithoglyph_prompt   -- Auto-solve PROMPT score proofs
fd_tactic       -- Functional dependency reasoning
nf_tactic       -- Normal form proofs
lossless_tactic -- Lossless transformation proofs
```

## Contributing

### Adding New Types

1. Define type in Lean 4 (`src/FbqlDt/Types/YourType.lean`)
2. Add constructor proofs
3. Add to type system spec (Section 3 or 4)
4. Add to EBNF grammar (`<refined-type>` or `<dependent-type>`)
5. Add examples to spec (Section 10)

### Adding New Syntax

1. Update EBNF grammar (`GQL-DT-Grammar.ebnf`)
2. Update railroad diagrams (`GQL-DT-Railroad-Diagrams.md`)
3. Update lexical spec if new keywords/operators
4. Add to main spec with examples
5. Implement in parser (once M6 starts)

### Adding New Proofs

1. Add theorem to appropriate module
2. Add to proof library (Section 8.4 of main spec)
3. Add tactic if pattern is common
4. Document usage in examples

## References

### Primary References

1. **Lean 4 Reference:** https://lean-lang.org/
2. **Mathlib4 Documentation:** https://leanprover-community.github.io/mathlib4_docs/
3. **Idris 2 Tutorial:** https://idris2.readthedocs.io/

### Related Work

1. **Liquid Haskell:** Refinement types for Haskell
2. **F*:** Dependent types + SMT solving
3. **Dafny:** Verification-aware programming language
4. **Coq:** Proof assistant with dependent types

### Database Theory

1. **Functional Dependencies:** Armstrong's Axioms (1974)
2. **Normal Forms:** Codd (1NF-3NF), Boyce-Codd (BCNF)
3. **Multi-Valued Dependencies:** Fagin (4NF)
4. **Proof-Carrying Code:** Necula (1997)

## License

All specification documents are licensed under **PMPL-1.0-or-later** (Palimpsest License).

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

## Contact

- **Project:** Lithoglyph Query Language with Dependent Types (GQL-DT)
- **Repository:** https://github.com/hyperpolymath/gql-dt
- **Organization:** hyperpolymath
- **Author:** Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>

---

**Last Updated:** 2026-02-01
**Specification Version:** 1.0.0
**Implementation Version:** 0.2.0 (65% complete, Milestones 1-4 done)
