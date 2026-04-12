<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Changelog — QuandleDB

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- EXPLAINME.adoc: honest scope, invariants, boundaries, polyglot stack map
- TEST-NEEDS.md: 21 assertions today, gaps documented per test category
- PROOF-NEEDS.md: 4 mathematical obligations (quandle axioms, Reidemeister
  invariance, canonicalisation idempotence, colouring well-definedness)
  + 3 systems obligations (cross-platform determinism, ABI-FFI layout,
  NIF safety)
- CRG v2 READINESS.md (grade D)

### Changed
- Absorbed into `nextgen-databases/` monorepo (removed nested .git dir)
- KRL → renamed reference to align with KRL stack naming

## [Absorbed into monorepo] 2026-04-05

Previously lived as a nested git repo under nextgen-databases/. Flattened
into the parent monorepo per the "no .git dirs in monorepo subdirs" rule.
History preserved in the absorption commit message.

### Included in absorption
- `server/serve.jl`: HTTP server with quandle_semantic_index SQLite sidecar
- `server/quandle_semantic.jl`: QuandleSemantic module — presentation
  extraction, canonicalisation, descriptor hashing (SHA-256)
- `src/abi/Types.idr`: Idris2 ABI type layer
- `src/ffi/semantic_ffi.zig`: Zig FFI layer
- `src/api/*.v`: V-lang API triples
- `beam/`: Elixir BEAM client with NIFs

### Prior history (pre-absorption)
- fix: replace Obj.magic with typed Fetch API bindings in Api.res
- chore: batch RSR compliance
- docs: KRL safety model — two-tier architecture with TypeLL levels
- feat: KRL resolution language design — SQL compat + dependent type variants
