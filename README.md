# GQLdt: Dependently-Typed Lithoglyph Query Language

image:https://img.shields.io/badge/License-PMPL--1.0-blue.svg[License: PMPL-1.0,link="https://github.com/hyperpolymath/palimpsest-license"]
// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

GQLdt extends [Lithoglyph](https://github.com/hyperpolymath/lithoglyph)'s query language with **dependent types**, enabling compile-time verification of database constraints, provenance tracking, and reversibility proofs.

> **Note**: GQL stands for "Lithoglyph Query Language"—the native query interface for Lithoglyph. It is not related to HTML forms or form builders.

## Relationship to Lithoglyph

```
┌─────────────────────────────────────────────────────────────┐
│  GQL (Factor)                  │  GQLdt (Lean 4)            │
│  - Runtime constraint checks   │  - Compile-time proofs     │
│  - Dynamic, practical          │  - Static, verified        │
│  - "Just run it"               │  - "Prove it first"        │
└───────────────┬────────────────┴────────────────┬───────────┘
                │                                  │
                ▼                                  ▼
┌─────────────────────────────────────────────────────────────┐
│  Form.Bridge (Zig) - Bidirectional ABI                      │
│  - No C dependency                                          │
│  - callconv(.C) for FFI compatibility                       │
├─────────────────────────────────────────────────────────────┤
│  Form.Model + Form.Blocks (Forth)                           │
│  - Single source of truth                                   │
└─────────────────────────────────────────────────────────────┘
```

**Same database, different guarantees:**

| Aspect | GQL (practical) | GQLdt (verified) |
|--------|-----------------|------------------|
| When constraints checked | Runtime | Compile-time |
| Invalid insert | Runtime error | Won't compile |
| Reversibility | Runtime inverse stored | Proof that inverse exists |
| PROMPT scores | `CHECK (score BETWEEN 0 AND 100)` | `BoundedNat 0 100` in type |
| Provenance | Application enforces | Type system enforces |

## Features

- **Refinement Types**: `BoundedNat 0 100`, `NonEmptyString`, `Confidence`
- **Dependent Types**: Length-indexed vectors, provenance-tracked values
- **Proof Obligations**: Compile-time verification of constraints
- **Reversibility Proofs**: Prove operations have inverses before execution
- **Normalization Types**: Type-encoded functional dependencies, normal form predicates (1NF-BCNF), proof-carrying schema evolution
- **Backward Compatible**: Standard GQL is valid in dependent-type mode

## Current Status

**Build Status**: 34/35 modules compiling (97% success) - Updated 2026-02-01

**Completed Milestones**:
- ✅ M1: Lean 4 project setup (v4.15.0 + Mathlib)
- ✅ M2: Core refinement types (BoundedNat, BoundedInt, NonEmptyString, Confidence)
- ✅ M3: PROMPT score types (PromptDimension, PromptScores with auto-computed overall)
- ✅ M4: Provenance tracking (ActorId, Rationale, Tracked with proofs)
- ✅ M5: Specifications (EBNF grammar, lexical spec, railroad diagrams)
- 🟡 M6: GQL-DT/GQL Parser (substantially complete - see below)

**M6 Parser Status** (Substantially Complete):
- ✅ Lexer: Hand-rolled 540-line implementation (80+ keywords, operators, literals, comments)
- ✅ Parser: Combinator-based parser for INSERT/SELECT/UPDATE/DELETE
- ✅ Type System: Refinement types, PROMPT scores, provenance tracking
- ✅ Pipeline: 6-stage compilation (tokenize → parse → type check → IR → validate → serialize)
- ✅ Serialization: CBOR encoding/decoding (RFC 8949), JSON support
- ✅ Documentation: 8 comprehensive docs (seam analysis, integration, language bindings, etc.)
- ✅ Infrastructure: Containerfile, Dockerfile, CI/CD workflow
- ⚠️  AST.lean: 1 nested inductive type issue (requires restructuring)

**Recent Updates** (2026-02-01):
- Seam analysis: Fixed 76 issues, resolved 33 compilation blockers
- Namespace consistency: Global FqlDt → FbqlDt renaming across 24 files
- Circular dependency: Created Serialization/Types.lean to break IR ↔ Serialization cycle
- CBOR tags: Updated to vendor-specific range (55800-55804) to avoid IANA collisions
- Lexer rewrite: Complete hand-rolled implementation (Parsec unavailable in Lean 4.15.0)

**Next Steps**:
- Fix AST.lean nested inductive issue (TypedValue/Tracked relationship)
- Achieve 35/35 modules compiling (100% build success)
- Start M7 (Idris2 ABI) + M8 (Zig FFI) in parallel
- M9: ReScript bindings (HIGHEST PRIORITY after M7+M8)

For detailed progress tracking, see [.machine_readable/STATE.scm](.machine_readable/STATE.scm).

## Zig FFI (Bidirectional)

GQLdt compiles to operations on Form.Bridge, which uses Zig's stable ABI:

```zig
/// Bidirectional FFI: Lean 4 → Zig → Forth core
/// and Forth core → Zig → Lean 4 callbacks

pub const FdbStatus = struct {
    code: i32,
    error_blob: ?[*]const u8,
    error_len: usize,
};

/// Forward: GQLdt → Form.Bridge
pub export fn fdb_insert(
    db: *FdbDb,
    collection: [*:0]const u8,
    document: [*]const u8,
    doc_len: usize,
    proof_blob: [*]const u8,  // Serialised proof from Lean 4
    proof_len: usize,
) callconv(.C) FdbStatus;

/// Reverse: Form.Bridge → GQLdt (for constraint checking)
pub export fn fdb_register_constraint_checker(
    db: *FdbDb,
    checker: *const fn (doc: [*]const u8, len: usize) callconv(.C) bool,
) callconv(.C) FdbStatus;
```

No C headers or libc required. Zig provides C-compatible calling convention for interop.

## Specification

See [spec/GQL_Dependent_Types_Complete_Specification.md](spec/GQL_Dependent_Types_Complete_Specification.md) for the full specification covering:

1. Type System (universes, primitives, constructors)
2. Refinement Types (bounded values, non-empty strings)
3. Dependent Types (provenance tracking, reversibility)
4. DDL/DML with proofs
5. Proof obligations and tactics
6. Complete examples (BoFIG journalism use case)

See [spec/normalization-types.md](spec/normalization-types.md) for normalization types covering:

1. Functional dependency encoding (FunDep, Armstrong's Axioms)
2. Normal form predicates (1NF, 2NF, 3NF, BCNF, 4NF)
3. Proof-carrying schema evolution (NormalizationStep)
4. Integration with Form.Normalizer
5. GQL syntax extensions for normalization commands

## Setup

1. Ensure `just` and `podman` are installed
2. Run `just check` to verify Lean 4 proofs
3. For non-bash shells, see `scripts/bootstrap_all.sh`

## Implementation Timeline

- **Phase 1** (Month 1-6): Refinement types
- **Phase 2** (Month 7-12): Simple dependent types
- **Phase 3** (Month 13-18): Full verification
- **Phase 4** (Month 19-24): Normalization types (FunDep, normal forms, proof-carrying evolution)

## See Also

- [Lithoglyph](https://github.com/hyperpolymath/lithoglyph) - The narrative-first database
- [Lithoglyph Self-Normalizing Spec](https://github.com/hyperpolymath/lithoglyph/blob/main/spec/self-normalizing.adoc) - Self-normalizing database specification
- [Lithoglyph Studio](https://github.com/hyperpolymath/lithoglyph-studio) - Zero-friction GUI for GQLdt
- [BoFIG](https://github.com/hyperpolymath/bofig) - Evidence graph for investigative journalism
- [Zotero-Lithoglyph](https://github.com/hyperpolymath/zotero-lithoglyph) - Production pilot: reference manager with PROMPT scores
- [Lithoglyph Debugger](https://github.com/hyperpolymath/lithoglyph-debugger) - Proof-carrying database debugger (Lean 4 + Idris 2)
- [FormBase](https://github.com/hyperpolymath/formbase) - Open-source Airtable alternative with provenance
