<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# TEST-NEEDS — QuandleDB

Honest accounting of test coverage across the polyglot stack.

## What's tested today (21 assertions total)

| Layer | Tests | Location |
|---|---|---|
| Julia quandle extraction | 9 | `server/test_semantic_index.jl` |
| Julia semantic index integration | 12 | `server/test_semantic_index.jl` |
| Idris2 ABI | — | none |
| Zig FFI | — | none |
| V-lang API | — | none |
| BEAM NIFs | declared | `beam/test/quandle_db_nif_test.exs`, `beam/test/quandle_db_nif_live_integration_test.exs` (not run in estate-wide sweep) |
| Full-stack (Idris → Zig → V → Julia → BEAM) | — | none |

## What's NOT tested

| Category | Why missing | Priority |
|---|---|---|
| unit (per-layer) | Only Julia has explicit unit tests | high |
| P2P / cross-process | BEAM↔Julia link not stress-tested | medium |
| E2E (polyglot) | No test spans the full stack | high |
| build (all layers) | CI only builds Julia server; ABI/FFI/API/BEAM not verified in CI | high |
| property-based | No property tests for quandle fingerprint determinism, canonicalisation | high |
| mutation | Not set up anywhere | medium |
| fuzz | No fuzz harness for random knot diagrams | medium |
| contract | No OpenAPI / interface contract for HTTP endpoints | medium |
| regression | No named regression suite | medium |
| chaos | No fault injection (e.g. SQLite mid-write) | low |
| compatibility | Single-platform only | low |
| proof-regression | Idris2 ABI has types but no discharged proofs | medium |

## Highest-value tests to add next (for CRG grade D → C)

1. **Quandle fingerprint determinism** (property-based):
   Same input diagram → same fingerprint hash, across N=100+ random test diagrams.
2. **Quandle fingerprint canonicalisation**:
   For known-equivalent presentations (e.g. Reidemeister moves applied), fingerprint matches.
3. **Colouring count on known knots**:
   Trefoil, figure-eight, unknot against expected colouring counts into Z/3, Z/5.
4. **BEAM ↔ Julia NIF handshake**:
   BEAM test actually loads the NIF and executes a quandle extraction end-to-end.
5. **Full-stack smoke**:
   Idris2-typed call → Zig FFI → V → Julia server → round-trip result.

## How to add new tests

For Julia:
- Add to `server/test_semantic_index.jl` under an appropriate `@testset`.
- Run with `julia --project=server -e 'include("server/test_semantic_index.jl")'`.

For BEAM:
- Add to `beam/test/quandle_db_nif_test.exs`.
- Run with `cd beam && mix test`.

For full-stack integration:
- Create `tests/integration/` at repo root.
- Script the Idris2→Zig→V→Julia→BEAM handshake with assertions at each layer.
