# VeriSimDB — LLM Context (User)

## What It Is

VeriSimDB is an 8-modality database engine. Every entity is stored across
Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, and Spatial
representations simultaneously (the "octad"). Drift between modalities is
detected and self-healed.

## Architecture

- **Rust core** (`rust-core/`): 10 crates for modality stores + API server
- **Elixir/OTP** (`elixir-orchestration/`): GenServer per entity, drift
  monitoring, query routing, schema registry
- **VCL**: Custom query language (not SQL)
- **Federation**: 10 adapters (MongoDB, Redis, Neo4j, ClickHouse, SurrealDB,
  SQLite, DuckDB, VectorDB, InfluxDB, ObjectStorage)
- **ABI/FFI**: Idris2 formal spec + Zig C-ABI bridge

## Quick Commands

```bash
just build          # Build Rust (release)
just build-elixir   # Build Elixir layer
just build-all      # Both
just serve          # API server on :8080
just serve-otp      # Full OTP orchestrator
just test-all       # All tests
just doctor         # Check prerequisites
```

## Core Concepts

- **Octad**: One entity, 8 synchronized representations
- **Drift**: Divergence between modalities (semantic-vector, graph-document, etc.)
- **Self-normalisation**: When drift exceeds threshold, most authoritative
  modality regenerates the others atomically
- **Federation**: Coordinates existing databases (MongoDB, Redis, etc.) as
  modality backends

## Prerequisites

Rust (nightly), Elixir 1.17+, Erlang/OTP 27+, Zig 0.14+,
openssl-devel, pkg-config, just. Optional: Idris2, Podman.

## Container

```bash
just container-build   # Podman build
just container-run     # Run on :8080
```

## Instance Policy

This repo is source code + examples only. Each consuming project
(IDApTIK, Burble, Hypatia) runs its own VeriSimDB instance on a
dedicated port with its own data volume.

## Key Paths

| Path | Purpose |
|------|---------|
| `rust-core/` | Rust modality crates |
| `elixir-orchestration/` | OTP supervision tree |
| `connectors/clients/` | 6 SDKs (Rust, V, Elixir, ReScript, Julia, Gleam) |
| `connectors/test-infra/` | 7-database integration test stack |
| `container/` | Containerfile + compose |
| `playground/` | VCL playground (ReScript) |
| `.claude/CLAUDE.md` | Full AI context |
