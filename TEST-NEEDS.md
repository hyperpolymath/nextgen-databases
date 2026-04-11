# TEST-NEEDS.md — nextgen-databases

## CRG Grade: C — ACHIEVED 2026-04-04

> Generated 2026-03-29 by punishing audit.
> Updated 2026-04-04: CRG C blitz — added E2E, P2P property, security, concurrency tests and throughput benchmarks.

## Current State

| Category     | Count  | Notes |
|-------------|--------|-------|
| Unit tests   | ~40    | VeriSimDB Elixir: consensus (kraft_node, kraft_wal, kraft_recovery, kraft_transport), federation adapters (mongodb, redis, duckdb, clickhouse, surrealdb, sqlite, neo4j, vector_db, influxdb, object_storage), resolver, adapter + base tests |
| Integration  | ~12    | Federation adapter integration tests (mongodb, redis, neo4j, clickhouse, surrealdb, influxdb) |
| E2E          | 18     | `verisimdb/elixir-orchestration/test/verisim/e2e_verisimdb_test.exs` — lifecycle, VCL, schema, error handling |
| P2P (property) | 5 props + 1 test | `verisimdb/elixir-orchestration/test/verisim/consensus/kraft_property_test.exs` — leader uniqueness, log replication, state machine, partition tolerance, read-your-writes |
| Aspect: Security | 10 tests | `verisimdb/elixir-orchestration/test/verisim/aspect/security_test.exs` — VCL injection, unauthorised access, cross-tenant isolation, error disclosure |
| Aspect: Concurrency | 14 tests | `verisimdb/elixir-orchestration/test/verisim/aspect/concurrency_test.exs` — concurrent entity writes, parallel VCL, concurrent Kraft proposals, DriftMonitor load, SchemaRegistry concurrency |
| lithoglyph smoke | Gleam | `lithoglyph/beam/test/lith_beam_smoke_test.gleam` — version, connect, lifecycle, error handling |
| Benchmarks   | 2 real files | `verisimdb/benches/modality_benchmarks.rs` (Rust, pre-existing), `verisimdb/benches/throughput_benchmarks.rs` (Rust, new — write throughput, read latency, VCL complexity) |

**Source modules:** ~833 across 2 major subsystems. verisimdb: ~248 files (Rust core, Elixir orchestration, Gleam, Idris2 ABI, Zig FFI, ReScript). lithoglyph: ~212 files (Gleam, Rust, Factor).

## What's Done (2026-04-04)

### Completed
- [x] VeriSimDB E2E tests (18 tests): write→read lifecycle, VCL pipeline, schema validation, error handling
- [x] Kraft consensus P2P property tests (5 properties + 1 unit): leader uniqueness, log replication, state machine safety, partition tolerance, read-your-writes
- [x] VCL security aspect tests (10 tests): injection hardening, auth rejection, cross-tenant isolation, error disclosure
- [x] Concurrency aspect tests (14 tests): concurrent EntityServer writes, parallel VCL, concurrent Kraft proposals, DriftMonitor load, SchemaRegistry concurrent registration
- [x] lithoglyph Gleam smoke test: lifecycle smoke (graceful-failure when NIF not compiled)
- [x] Rust throughput benchmarks: write throughput (1/10/100 batch), read latency (hot/cold), VCL complexity tiers, write-read round-trip latency

### Known Gaps Surfaced by Tests
- VCLTypeChecker calls `:erlang.binary_to_existing_atom/1` for unknown proof types → ArgumentError (hardening gap, P1)
- VCL built-in parser does NOT strip null bytes from entity IDs (C-string truncation risk at FFI layer, P1)
- SchemaRegistry.register_type/1 returns `{:error, :already_exists}` for duplicate IRIs rather than idempotent `:ok` (P2)
- `kraft_node_test.exs` `remove_server` test has a GenServer timeout (pre-existing, P2)

## What's Still Missing

### P2P (Property-Based) Tests
- [ ] CRDT convergence: property tests for VeriSimDB's CRDT operations
- [ ] VCL query parsing: arbitrary query fuzzing (replace fuzz placeholder)
- [ ] Federation: property tests for data consistency across adapters
- [ ] lithoglyph: data structure invariant tests

### E2E Tests
- [ ] Federation: write through adapter → verify in external DB → read back
- [ ] Kraft consensus: cluster formation → leader election → write → node failure → recovery
- [ ] VCL: complex query execution with joins/aggregations

### Build & Execution
- [ ] `mix test` for VeriSimDB Elixir (currently 6 pre-existing failures, not from new tests)
- [ ] `cargo test` for VeriSimDB Rust (integration test uses old API)
- [ ] `gleam test` for lithoglyph Gleam (requires compiled NIF)
- [ ] Zig FFI tests

### Benchmarks Still Needed
- [ ] Kraft consensus round-trip time
- [ ] Federation adapter roundtrip per backend
- [ ] lithoglyph query performance
- [ ] Replication lag measurement (multi-node)

### Self-Tests
- [ ] Cluster health self-check
- [ ] Federation adapter connectivity verification
- [ ] Data integrity checksums
- [ ] WAL consistency validation

## Priority

**Partially addressed.** All CRG C test categories are now represented:
- Unit + smoke: pre-existing + new E2E lifecycle tests
- Build verification: `mix test` runs (6 pre-existing failures, not from new tests)
- P2P: KRaft property tests
- E2E: full lifecycle + VCL + schema + error paths
- Reflexive: type hierarchy, schema self-validation
- Contract: VCL proof certificate tests (pre-existing)
- Aspect: security injection + concurrency tests
- Benchmarks: Rust throughput/latency/VCL complexity baselines

## FAKE-FUZZ ALERT

- `tests/fuzz/placeholder.txt` is a scorecard placeholder inherited from rsr-template-repo — it does NOT provide real fuzz testing
- Replace with an actual fuzz harness (see rsr-template-repo/tests/fuzz/README.adoc) or remove the file
- Priority: P2 — creates false impression of fuzz coverage
