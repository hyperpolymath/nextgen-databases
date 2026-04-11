# VeriSimDB — LLM Context (Developer)

## Identity

VeriSimDB (Veridical Simulacrum Database) — 8-modality entity consistency
engine with drift detection, self-normalisation, and formally verified queries.
Part of the nextgen-databases monorepo. License: PMPL-1.0-or-later.
Author: Jonathan D.A. Jewell.

## Architecture (Marr's Three Levels)

**Computational**: Maintain cross-modal consistency across 8 representations.
**Algorithmic**: Octad entities, drift detection with thresholds, OTP supervision.
**Implementational**: Rust stores + Elixir coordination + VCL queries.

```
Elixir OTP: EntityServer, DriftMonitor, QueryRouter, SchemaRegistry
    ↓ HTTP
Rust Core: graph, vector, tensor, semantic, document, temporal,
           provenance, spatial, octad, drift, normalizer, api
```

## Rust Workspace (`Cargo.toml`)

10 library crates + 1 binary crate (verisim-api). Workspace at root.
Build: `OPENSSL_NO_VENDOR=1 cargo build --release`
oxrocksdb-sys eliminated (redb pure-Rust backend). protoc eliminated
(pre-generated). No C++ deps.

## Elixir Layer (`elixir-orchestration/`)

OTP app with supervision tree. GenServer per entity.
Hypatia integration: ScanIngester, PatternQuery, DispatchBridge (37 tests).
Built-in VCL parser (no external runtime needed).
Product telemetry: opt-in ETS collector + JSON reporter.

## Key Subsystems

### Drift Detection
6 drift types: semantic_vector, graph_document, temporal_consistency,
tensor, schema, quality. Configurable thresholds gate normalisation.

### Self-Normalisation
1. Identify most authoritative modality
2. Regenerate drifted modalities
3. Validate consistency
4. Atomic update

### Federation
10 adapters: MongoDB, Redis, Neo4j, ClickHouse, SurrealDB, SQLite,
DuckDB, VectorDB, InfluxDB, ObjectStorage.
Integration tests: 105 tests across 7 adapters (need test-infra stack).

### VCL (VeriSim Query Language)
Type system: VCL-DT. 11 proof types. Multi-proof parsing.
Modality compatibility validation. ReScript playground wired to backend.

### Hypatia Pipeline
```
panic-attack assail → ScanIngester → octads → PatternQuery → DispatchBridge → gitbot-fleet
```
954 patterns tracked across 298 repos. Fleet dispatch logged (JSONL),
live execution needs GitHub PAT.

## Client SDKs (`connectors/clients/`)

6 SDKs: Rust, V, Elixir, ReScript, Julia, Gleam.
Shared: JSON Schema, OpenAPI, protobuf (`connectors/shared/`).

## ABI/FFI (`src/abi/`, `ffi/zig/`)

Idris2 ABI definitions (formal proofs). Zig FFI C-ABI bridge.
Generated C headers in `generated/abi/`.

## Container Stack

Podman (never Docker). Chainguard base images.
- `container/Containerfile` — main build
- `container/compose.toml` — selur-compose (3 services)
- `container/.gatekeeper.yaml` — svalinn edge gateway
- `container/manifest.toml` — cerro-torre signing
- `container/ct-build.sh` — build/sign/verify pipeline

Test infra: `connectors/test-infra/compose.toml` — 7 databases.

## Instance Policy (CRITICAL)

This repo = source code + examples ONLY. Each consumer runs own instance:
- IDApTIK: port 8090, volume idaptik-verisimdb-data
- Burble: port 8091, volume burble-verisimdb-data
- Hypatia: port 8092, volume hypatia-verisimdb-data

Never store app data here. Never point at localhost:8080.

## Commands

```bash
just build / build-all / build-elixir / build-abi / build-ffi
just test / test-elixir / test-integration / test-all
just serve / serve-otp
just fmt / lint / fmt-elixir
just container-build / container-run / deploy / deploy-stop
just panic-scan / hypatia-scan / license-check / check-scm
just doctor / heal / tour / help-me
```

## Language Policy

Allowed: Rust, Elixir, ReScript, VCL, Idris2, Zig.
Banned: Python, Go, Node.js.

## Code Patterns

### Octad creation (Rust)
```rust
let octad = OctadBuilder::new()
    .with_document("Title", "Body")
    .with_embedding(vec![0.1, 0.2])
    .with_types(vec!["http://example.org/Doc"])
    .build();
```

### Entity server (Elixir)
```elixir
{:ok, _} = VeriSim.EntityServer.start_link("eid")
{:ok, state} = VeriSim.EntityServer.get("eid")
```

## Known Issues

All 25 historical issues resolved. See KNOWN-ISSUES.adoc.

## File Map

| Path | What |
|------|------|
| `Cargo.toml` | Workspace root |
| `rust-core/verisim-*/` | 10 modality crates |
| `elixir-orchestration/lib/verisim/` | OTP modules |
| `elixir-orchestration/lib/verisim/hypatia/` | Hypatia integration |
| `connectors/clients/` | 6 SDKs |
| `connectors/test-infra/` | Integration test databases |
| `container/` | Containerfiles + compose |
| `playground/` | VCL playground (ReScript) |
| `src/abi/` | Idris2 ABI |
| `ffi/zig/` | Zig FFI |
| `spec/` | Grammar EBNF |
| `verification/` | Verification gateway |
| `docs/` | Documentation |
| `verisimdb-data/` | Git-backed flat-file data |
| `.machine_readable/` | STATE.scm, META.scm, ECOSYSTEM.scm |
| `.claude/CLAUDE.md` | Full AI instructions |
| `0-AI-MANIFEST.a2ml` | Universal AI entry point |
