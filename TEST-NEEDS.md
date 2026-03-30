# TEST-NEEDS.md — nextgen-databases

> Generated 2026-03-29 by punishing audit.

## Current State

| Category     | Count | Notes |
|-------------|-------|-------|
| Unit tests   | ~40   | VeriSimDB Elixir: consensus (kraft_node, kraft_wal, kraft_recovery, kraft_transport), federation adapters (mongodb, redis, duckdb, clickhouse, surrealdb, sqlite, neo4j, vector_db, influxdb, object_storage), resolver, adapter + base tests |
| Integration  | ~12   | Federation adapter integration tests (mongodb, redis, neo4j, clickhouse, surrealdb, influxdb) |
| E2E          | 0     | None |
| Benchmarks   | 2     | verisimdb/benches/modality_benchmarks.rs (Rust), lithoglyph core-factor benchmarks.factor |

**Source modules:** ~833 across 2 major subsystems. verisimdb: ~248 files (Rust core, Elixir orchestration, Gleam, Idris2 ABI, Zig FFI, ReScript). lithoglyph: ~212 files (Gleam, Rust, Factor).

## What's Missing

### P2P (Property-Based) Tests
- [ ] Kraft consensus: property tests for leader election, log replication, partition tolerance
- [ ] CRDT convergence: property tests for VeriSimDB's CRDT operations
- [ ] VQL query parsing: arbitrary query fuzzing
- [ ] Federation: property tests for data consistency across adapters
- [ ] lithoglyph: data structure invariant tests

### E2E Tests
- [ ] VeriSimDB: full write -> replicate -> read across nodes
- [ ] Federation: write through adapter -> verify in external DB -> read back
- [ ] Kraft consensus: cluster formation -> leader election -> write -> node failure -> recovery
- [ ] lithoglyph: full lifecycle (create -> write -> query -> archive)
- [ ] VQL: complex query execution with joins/aggregations

### Aspect Tests
- **Security:** No tests for authentication bypass, unauthorized federation access, injection through VQL, data exfiltration across adapters
- **Performance:** Rust modality benchmark exists. Missing: Elixir orchestration throughput, Kraft consensus latency, federation adapter comparison benchmarks
- **Concurrency:** No tests for concurrent writes across Kraft nodes, federation adapter connection pooling, VQL query contention
- **Error handling:** No tests for adapter connection failure, Kraft split-brain recovery, malformed VQL, storage corruption

### Build & Execution
- [ ] `mix test` for VeriSimDB Elixir
- [ ] `cargo test` for VeriSimDB Rust
- [ ] `gleam test` for lithoglyph
- [ ] Zig FFI tests
- [ ] Container-based multi-node tests

### Benchmarks Needed
- [ ] Write throughput (single node, cluster)
- [ ] Read latency (hot, cold, cache miss)
- [ ] Kraft consensus round-trip time
- [ ] Federation adapter roundtrip per backend
- [ ] VQL query execution time by complexity
- [ ] lithoglyph query performance
- [ ] Replication lag measurement

### Self-Tests
- [ ] Cluster health self-check
- [ ] Federation adapter connectivity verification
- [ ] Data integrity checksums
- [ ] WAL consistency validation

## Priority

**CRITICAL.** Two database systems with 833 source files and ~52 tests (6.2%). The consensus layer (Kraft) has 4 tests for a distributed consensus protocol — that is dangerously low. Federation adapters have decent unit coverage but zero E2E. lithoglyph appears to have no dedicated tests at all. A database with no concurrency tests is a ticking time bomb.

## FAKE-FUZZ ALERT

- `tests/fuzz/placeholder.txt` is a scorecard placeholder inherited from rsr-template-repo — it does NOT provide real fuzz testing
- Replace with an actual fuzz harness (see rsr-template-repo/tests/fuzz/README.adoc) or remove the file
- Priority: P2 — creates false impression of fuzz coverage
