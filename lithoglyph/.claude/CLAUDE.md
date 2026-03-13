# CLAUDE.md - AI Assistant Instructions for Lithoglyph

## Project Overview

Lithoglyph (formerly "Lith") is a narrative-first, reversible, audit-grade database core. Every mutation is a story event with full provenance. The tagline: "The database where the database is part of the story."

Multi-language stack in dependency order:
1. **Forth** (core-forth/) — Block storage kernel, journaling, data model
2. **Zig** (core-zig/) — C ABI bridge with WAL, 19 functions, block allocator
3. **Zig** (ffi/zig/) — Delegation layer that forwards to core-zig
4. **Idris2** (src/Lith/) — Dependent-type ABI proofs, memory layout verification
5. **Factor** (core-factor/) — FQL runtime: parser, planner, executor
6. **Lean 4** (normalizer/) — Normalization proofs, FD discovery (52 proofs)
7. **Lean 4** (gql-dt/) — Dependently-typed Glyph Query Language
8. **Zig + Rust** (beam/) — BEAM NIFs for Elixir/Erlang integration
9. **Elixir** (lith-http/) — Phoenix HTTP API, control plane
10. **Rust + Web** (studio/) — Tauri desktop GUI (mock data, early stage)
11. **Zig** (api/) — REST + gRPC API (BROKEN — needs Zig 0.15.2 migration)

Subprojects with own `.machine_readable/`: gql-dt/, glyphbase/, lith-http/

## Architecture

```
svalinn (TLS) → lith-http (Elixir :4000) → BEAM NIFs → core-zig (C ABI) → core-forth (blocks)
                                                 ↑
                              Idris2 ABI proofs (src/Lith/) verify bridge contracts
                              Lean 4 normalizer verifies schema correctness
                              GQL-DT (Lean 4) verifies query correctness
                              Factor FQL plans and executes queries
```

## Critical Invariants

1. **IP Rename PENDING**: Code uses `Lith`/`Form` internally. Must rename to `Litho`/`Lithoglyph` before any public release. Keep "form" only where it literally means HTML/data forms.
2. **Zero `believe_me`** in Idris2 ABI (`src/Lith/`). This is a HARD invariant — no exceptions.
3. **Zero `sorry`** in Lean 4 proofs (normalizer/, gql-dt/). All proofs must be constructive.
4. **`core-zig/src/bridge.zig`** is the WORKING implementation. `ffi/zig/` only delegates to it. Never add new functionality to `ffi/zig/` directly.
5. **Proven library** lives at `/var/mnt/eclipse/repos/proven/` (104+ modules) — never bundle a copy.
6. All Zig `@ptrCast`/`@alignCast`/`@intToPtr` must have `// SAFETY:` comments.
7. **SCM files** ONLY in `.machine_readable/` — never in root directories.
8. **Container runtime**: Podman, never Docker. Files: `Containerfile`, never `Dockerfile`.
9. **Base images**: `cgr.dev/chainguard/wolfi-base:latest` or `cgr.dev/chainguard/static:latest`.

## Machine-Readable Artefacts

`.machine_readable/` contains:
- `STATE.scm` — Current project state, component status, completion percentages
- `META.scm` — Architecture decisions, development practices, design rationale
- `ECOSYSTEM.scm` — Position in ecosystem, related projects
- `AGENTIC.scm` — AI agent interaction patterns, autonomous agent designs
- `NEUROSYM.scm` — Neurosymbolic integration (symbolic proofs + planned neural layer)
- `PLAYBOOK.scm` — Operational runbook, build procedures, incident response
- `HANDOVER.scm` — Legacy handover artefact (historical)
- `ROADMAP.scm` — Unified roadmap across all lithoglyph subprojects

## Language Policy

### ALLOWED
- **Forth** — Storage kernel (gforth)
- **Zig** — Bridge, BEAM NIF, API layer
- **Idris2** — ABI proofs (dependent types)
- **Lean 4** — Normalization proofs, GQL-DT
- **Factor** — FQL runtime (concatenative)
- **Elixir** — OTP control plane, HTTP API
- **Rust** — BEAM NIF (Rustler), studio backend
- **ReScript** — Client libraries (if needed)
- **Nickel** — Configuration

### BANNED
- TypeScript, Python, Go, Java, Node.js, npm

## Build Commands

### Core Components (dependency order)
```bash
# 1. Forth kernel (17 tests)
cd core-forth && gforth test/lithoglyph-tests.fs

# 2. Zig bridge (primary — all tests)
cd core-zig && zig build test

# 3. Zig FFI delegation (delegates to core-zig)
cd ffi/zig && zig build test

# 4. Idris2 ABI type-check (3 files, must be clean)
idris2 --source-dir src --check src/Lith/LithBridge.idr
idris2 --source-dir src --check src/Lith/LithLayout.idr
idris2 --source-dir src --check src/Lith/LithForeign.idr

# 5. Lean 4 normalizer (52 proofs)
cd normalizer && lake build

# 6. Factor runtime
cd core-factor && factor -run=listener  # manual verification
```

### Satellites
```bash
# BEAM NIF (Rust — 0 warnings required)
cd beam/native_rust && cargo build

# BEAM NIF (Zig)
cd beam/native && zig build

# Elixir HTTP (lith-http)
cd lith-http && mix deps.get && mix compile && mix test

# GQL-DT (Lean 4)
cd gql-dt && lake build

# Studio (Tauri — mostly mock data)
cd studio && cargo build
```

### Quick Verification
```bash
just test      # core-zig + ffi/zig + core-forth
just build-all # everything in dependency order
```

## Component Status

| Component | Build | Tests | Notes |
|-----------|-------|-------|-------|
| core-forth | PASS | 17/17 | Block storage, journal, data model |
| core-zig | PASS | PASS | 19 real functions, WAL commit |
| ffi/zig | PASS | PASS | Delegates to core-zig |
| Idris2 ABI | PASS | N/A | 3 files type-check clean, 0 believe_me |
| Lean 4 normalizer | PASS | 52 PASS | FD discovery proofs |
| core-factor | PASS | N/A | FQL parser/planner/executor |
| BEAM NIF (Zig) | PASS | N/A | Real FFI calls |
| BEAM NIF (Rust) | PASS | N/A | Rustler 0.35, 0 warnings |
| lith-http | PASS | PASS | M15 complete |
| gql-dt | PASS | claims 100% | Needs honest audit |
| glyphbase | ? | ? | Needs honest audit |
| api (Zig) | BROKEN | N/A | 83 old std.http.Server call sites |
| studio | PASS | N/A | 11 commands return mock data |

## Patterns and Anti-Patterns

### Banned Patterns (CI enforced)
- `believe_me` in Idris2 — use `%foreign prim__callbackToAnyPtr` pattern instead
- `assert_total`, `assert_smaller`, `unsafePerformIO` in Idris2
- `sorry` in Lean 4
- `Admitted` in Coq (if any)
- Zig unsafe casts without `// SAFETY:` annotation
- SQL string concatenation — use parameterized query builders
- Hardcoded secrets — use env vars with `${VAR:-}` defaults

### Key Design Patterns
- **Bridge delegation**: `ffi/zig/` → `core-zig/` (never reverse)
- **ABI-first**: Idris2 proofs define the interface contract, Zig implements it
- **Proof-verified schemas**: Lean 4 normalizer proves schema correctness
- **Narrative provenance**: Every mutation has a story — who, what, when, why
- **WAL-first writes**: All mutations go through Write-Ahead Log before blocks

## Related Projects

- **verisimdb** — Octad database sibling (shares GQL patterns)
- **quandledb** — Knot-theoretic database sibling
- **nqc** — Normal-form Query Compiler
- **proven** — Formally verified safety library (SafeString, SafeJson, etc.)
- **hypatia** — Neurosymbolic CI/CD scanner
- **gitbot-fleet** — Bot orchestration (rhodibot, echidnabot, sustainabot)

## Known Issues

- **API layer**: `api/src/rest.zig` and `api/src/grpc.zig` use old `std.http.Server` API — 83 call sites need Zig 0.15.2 migration
- **Studio**: 11 Tauri commands return mock data, not real bridge calls
- **IP rename**: `Lith`/`Form` namespace must be renamed before public release
- **Idris2 Nat reduction**: Proof type signatures must use concrete literals, not function-defined constants (Idris2 0.8 limitation)
- **gql-dt/glyphbase**: Claim 100% completion — need honest audit
