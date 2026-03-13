# Lithoglyph Honest Status — 2026-02-13 (Final)

## Session Summary

Two major work phases completed today:

### Phase A: 7-Phase ABI Plan (Interface Contracts)

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Delete template ABI duplicates (`src/abi/`) | Done |
| 2 | Eliminate `believe_me` from `src/Lith/` (10 total) | Done — 0 remain in Lith |
| 3 | Align Idris2 ABI with core-zig bridge (18 FFI declarations) | Done |
| 4 | Generate C header (`generated/abi/bridge.h`) | Done |
| 5 | Update Factor FFI (`storage-backend.factor`) | Done |
| 6 | Expand C FFI integration tests (5→17) | Done |
| 7 | Create ReScript test runners (property + fuzz) | Done |

### Phase B: Compile Verification and Fixes

| Component | Before | After |
|-----------|--------|-------|
| **Idris2 ABI** (`src/Lith/`) | 11 typed holes, 10 believe_me | 0 holes, 0 believe_me, compiles clean |
| **core-zig** | Working but no `pub` exports | BUILD + TEST PASS |
| **ffi/zig** | 23 stubs (dead code) | Delegates to core-zig, BUILD + TEST PASS |
| **core-forth** | Working | 17/17 TESTS PASS |
| **beam/native (Zig NIF)** | Stubs ("M10 PoC") | Real FFI calls, BUILD PASS |
| **beam/native_rust** | Lifetime errors, 6 warnings | BUILD PASS, 0 warnings |
| **API layer** | Placeholder responses + old Zig API | Bridge calls wired, main.zig updated (see PENDING) |
| **Subproject ABIs** | 4 believe_me (banned) | Replaced with %foreign prim__callbackToAnyPtr |
| **Zig unsafe casts** | 22 without SAFETY comments | All annotated with `// SAFETY:` |
| **SQL injection** | String concatenation in test gen | Parameterized query builders |
| **Production infra** | None | Containerfile, selur-compose.yml, CI workflow, env-var auth |
| **Test vectors** | Empty dirs | 5 encoding test vectors + 3 ExUnit test files |

---

## What Actually Compiles and Passes Tests

| Component | Build | Tests | Notes |
|-----------|-------|-------|-------|
| core-zig (bridge + blocks) | PASS | PASS | 19 real functions, WAL commit |
| ffi/zig (delegation layer) | PASS | PASS | Delegates to core-zig |
| core-forth (Forth kernel) | PASS | 17/17 PASS | Block storage, journal, model |
| core-lean (Lean 4 proofs) | PASS | 52 PASS | Normalization proofs |
| Idris2 ABI (src/Lith/) | PASS | N/A | All 3 files type-check clean |
| beam/native (Zig NIF) | PASS | N/A | Real FFI calls to core-zig |
| beam/native_rust (Rust NIF) | PASS (0 warnings) | N/A | Rustler 0.35 NIF |
| core-factor (GQL runtime) | PASS | N/A | GQL parser, planner, executor |

---

## What's Still Broken or Incomplete

### API Layer (api/) — Pre-existing Zig 0.15.2 Incompatibility

`api/src/main.zig` has been updated to 0.15.2 `std.net.Server` pattern.
`api/src/rest.zig` still uses old `std.http.Server` API — **83 call sites** need migration.
`api/src/grpc.zig` has the same issue.

This is a pre-existing problem, not introduced by today's work. The API layer
has real bridge calls wired in (not placeholders), but won't compile until
the HTTP API is migrated.

### Studio (Tauri) — 11 TODO Commands

Every backend command in `studio/src-tauri/src/main.rs` returns mock data.
This is a satellite component, not core infrastructure.

### Naming — Lith/Lith → Lith/Litho (IP Issue)

**CRITICAL — must be done before any public release.**

"Form" and "Lith" had an IP claim. Everything must be renamed:
- `Lith` → `LithBD` or `Litho`
- `Lith` → `LithDB` or `Lithoglyph`
- `Form.Bridge` → `Lith.Bridge`
- `LithLayout` → `LithLayout`
- `LithForeign` → `LithForeign`
- `LithBridge` → `LithBridge`
- `GQL` → `LDQL` or `LithQL`
- `lith_*` C symbols → `lg_*` or `lith_*`
- Module directory `src/Lith/` → `src/LithBD/` or `src/Litho/`
- Factor vocabulary `storage-backend` references
- `generated/abi/bridge.h` type prefixes
- All comments, docs, test names

**Scope:** Entire repo — .idr, .zig, .rs, .res, .factor, .fs, .h, .json, .md, .yml.
Keep "form" only where it literally means HTML/data forms (not the database).

---

## Banned Patterns Status

| Pattern | Before | After |
|---------|--------|-------|
| `believe_me` in src/Lith/ | 10 | **0** |
| `believe_me` in subproject ABIs | 4 | **0** (replaced with %foreign) |
| Unsafe Zig casts without SAFETY | 22 | **0** (all annotated) |
| SQL injection in test generators | 1 | **0** (parameterized) |
| Hardcoded auth tokens | 1 | **0** (env-var based) |

---

## Production Infrastructure Added

- `Containerfile` — Multi-stage build, chainguard/static runtime
- `selur-compose.yml` — Podman-compatible orchestration
- `.github/workflows/ci.yml` — SHA-pinned CI (Zig, Forth, Lean, Idris2, Rust)

---

## Proven Library Integration

The real Proven library exists at `/var/mnt/eclipse/repos/proven/` with 104+ modules
(SafePath, SafeJson, SafeSQL, SafeSchema, SafeBuffer, SafePolicy, etc.) and 89
language bindings. Lithoglyph should import from this external repo, NOT bundle a copy.

Current inline implementations in LithBridge.idr (validateDbPath, validateFqlQuery,
parseJsonDocument) are functional but should eventually delegate to Proven.

---

## panic-attack Scan: 22 Weak Points (Pre-Fix Baseline)

| Severity | Count |
|----------|-------|
| Critical | 5 |
| High | 5 |
| Medium | 8 |
| Low | 4 |

Many of these have been addressed (believe_me elimination, SQL injection fix,
auth hardening, SAFETY annotations). A re-scan is recommended.

---

## Bottom Line

The core storage engine, Zig bridge, Forth kernel, Lean proofs, and Idris2 ABI
all compile and pass tests. The BEAM NIFs (both Zig and Rust) compile clean.
The API layer needs Zig 0.15.2 HTTP migration. The Lith→Lith rename is pending.
This is verified scaffolding with a working foundation — not just a blueprint.
