<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
# CLAUDE.md — nextgen-databases (COORDINATION REPO)

## CRITICAL: This is a coordination repo. No database implementation lives here. (Read First)

`nextgen-databases` **coordinates** a portfolio of database projects. It does **not**
hold their implementations. Each database and each query language has its **own repo**
(see `REGISTRY.adoc`).

**Before you create or edit a file here, STOP and ask: is this coordination, or is it
about one specific database?** If it is about one database, it belongs in that database's
own repo.

### NEVER (in this repo)

1. **NEVER** add per-database source code, schemas, migrations, storage engines, or
   query-language implementations here.
2. **NEVER** add per-database design docs, whitepapers, benchmarks, or datasets here.
3. **NEVER** create a new top-level directory for a database or language — create or
   extend its own repo instead (`REGISTRY.adoc`).
4. **NEVER** "just put it here for now." That is exactly the drift this repo is
   recovering from.

### ALWAYS (what DOES belong here)

1. **Portfolio coordination**: `README.adoc`, `TOPOLOGY.md`, `ROADMAP.adoc`,
   `EXPLAINME.adoc`.
2. **The registry** of databases/languages → their repos: `REGISTRY.adoc`.
3. **Cross-database** integration tests (`tests/`) and shared infrastructure
   (`flake.nix`, `Justfile`, `stapeln.toml`, `opsm.toml`).
4. **Governance & metadata**: `.github/`, `.machine_readable/`, `.well-known/`,
   `LICENSES/`, `CONTRIBUTING.md`, `SECURITY.md`, `0-AI-MANIFEST.a2ml`.

### Where database content goes

See **`REGISTRY.adoc`** for the authoritative map. Examples: VeriSimDB →
`hyperpolymath/verisimdb`; Lithoglyph → `hyperpolymath/lithoglyph`; Glyphbase →
`hyperpolymath/glyphbase`; the Glyph query language → `hyperpolymath/gnpl`; NQC →
`hyperpolymath/nqc`.

### Transitional note

`lithoglyph/` is **done**: extraction completed 2026-07-27 and its 819 files were
removed, leaving a pointer README. Everything it held is preserved at its original
path in the `split-history/lithoglyph` tag on `origin` — never prune that tag or the
`_split_lithoglyph` branch.

The directories `verisimdb/`, `quandledb/`, `nqc/`,
`typeql-experimental/`, `verisim-core/`, and `verisim-modular-experiment/` are **legacy
content being extracted** to their own repos — see
`docs/migration/RESITE-DATABASES-TO-OWN-REPOS.adoc`. **Do not grow them.** A CI guard
(`.github/workflows/placement-guard.yml`) and a local pre-write hook
(`.claude/hooks/block-db-writes.sh`) enforce this: creating a *new* file inside those
directories is blocked, because it belongs in that database's own repo.

---
*Also read `0-AI-MANIFEST.a2ml` (universal AI entry point) and `AGENTS.md`.*
