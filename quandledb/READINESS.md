<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Component Readiness — QuandleDB

**Current Grade:** D
**Assessed:** 2026-04-05
**Standard:** [CRG v2.0 STRICT](../../standards/component-readiness-grades/)

## Grade rationale (evidence for D)

Works on some things + partial RSR compliance. QuandleDB is a polyglot project:
Julia HTTP server (Skein.jl wrapper) + Julia semantic sidecar + Idris2 ABI +
Zig FFI + V-lang API + Elixir BEAM NIFs.

### Evidence

- **Tests:** 21 passing (9 quandle extraction + 12 semantic index integration)
- **Components present:**
  - `server/serve.jl` — HTTP server with quandle_semantic_index SQLite sidecar
  - `server/quandle_semantic.jl` — QuandleSemantic module (presentation extraction + hashing)
  - `src/abi/Types.idr` — Idris2 ABI type layer
  - `src/ffi/semantic_ffi.zig` — Zig FFI layer
  - `src/api/*.v` — V-lang API triples
  - `beam/` — Elixir BEAM client with NIFs
- **RSR compliance:** Partial. Has 5 per-directory READMEs. 0-AI-MANIFEST.a2ml
  present (template). `.machine_readable/6a2/` directory exists.
- **CI:** panic-attack assail 0 findings.

## Gaps preventing higher grades

### Blocks C (works reliably + annotated)
- No EXPLAINME.adoc, TEST-NEEDS.md, PROOF-NEEDS.md at repo root.
- Julia server code has no docstrings.
- Elixir BEAM layer has no dedicated test coverage documented here.
- No integration tests spanning the full Idris2 → Zig → V → Julia → Elixir stack.
- No dogfooding evidence — has anyone actually driven this end-to-end?
- Only 4 commits in history before absorption into nextgen-databases monorepo.

### Blocks B
- Requires C first.

## What to do for C

1. Add EXPLAINME.adoc explaining the polyglot architecture and its intended
   users.
2. Add TEST-NEEDS.md documenting what's tested at each language layer and what isn't.
3. Write docstrings for `server/serve.jl`, `server/quandle_semantic.jl`.
4. Add per-language READMEs at `src/abi/`, `src/ffi/`, `src/api/`, `beam/`
   explaining what each layer contributes.
5. Demonstrate a full-stack dogfood: invoke Idris2 ABI-verified call, through
   Zig FFI, via V-lang API, hitting Julia server, surfacing via BEAM NIF, and
   have a real test assert on it.

## Review cycle

Reassess after the full-stack dogfood test exists.
