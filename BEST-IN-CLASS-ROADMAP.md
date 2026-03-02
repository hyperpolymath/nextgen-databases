# VeriSimDB Best-in-Class Roadmap

Criticality-ordered plan. Toolchain first, then infrastructure, then ecosystem.

**Completed prerequisites** (this session):
- [x] verisim-planner crate (cost-based query planning)
- [x] Triple API (REST + GraphQL + gRPC)
- [x] VQL AST → LogicalPlan bridge
- [x] Proof obligation costing (per-type: existence→ZKP)
- [x] Adaptive tuning (actual vs estimated latency feedback)
- [x] Post-processing + cross-modal cost models
- [x] ZKP scheme decision: PLONK (documented in Trustfile)

---

## Phase 1: VQL Toolchain (HIGHEST PRIORITY)

### 1.1 VQL REPL — Rust CLI
**Criticality: CRITICAL** | Effort: Medium | Crate: `verisim-repl`

Every database has an interactive shell. Without one, VeriSimDB is unusable
for exploration and debugging.

- Rust CLI binary (`vql` command)
- Readline/rustyline for input editing, history, multiline
- HTTP client to verisim-api (configurable endpoint)
- Commands: `\connect`, `\explain`, `\timing`, `\format json|table|csv`
- Syntax highlighting for VQL keywords
- Tab completion for modalities, proof types
- Output formatters: table (default), JSON, CSV
- `.vqlrc` config file support

### 1.2 VQL REPL — Elixir IEx Extension
**Criticality: HIGH** | Effort: Small | Module: `VeriSim.VQL.IEx`

- `use VeriSim.VQL.IEx` in IEx sessions
- `vql("SELECT GRAPH FROM HEXAD ...")` function
- Pretty-printed results with modality indicators
- `vql_explain/1` for EXPLAIN output
- Direct in-process execution (no HTTP round-trip)

### 1.3 VQL Language Server (LSP)
**Criticality: HIGH** | Effort: Large | Crate: `verisim-lsp`

- Diagnostics: parse errors, unknown modalities, type mismatches
- Completions: modality names, field names, proof types, keywords
- Hover: modality documentation, cost estimates
- Go-to-definition: proof contracts → semantic store
- VS Code extension + Neovim plugin
- Uses existing ReScript parser via JSON bridge

### 1.4 VQL Formatter
**Criticality: MEDIUM** | Effort: Small | Module in `verisim-repl`

- `vql fmt` subcommand
- Canonical formatting for VQL queries
- Keyword uppercasing, consistent indentation
- Integrates with LSP `textDocument/formatting`

---

## Phase 2: Storage & Durability (CRITICAL for deployment)

### 2.1 Write-Ahead Log (WAL)
**Criticality: CRITICAL** | Effort: Large | Crate: `verisim-wal`

Without WAL, any crash loses all data. Non-negotiable for deployment.

- Append-only log of all write operations
- Configurable sync mode: `fsync` (safe) vs `async` (fast)
- Recovery: replay WAL on startup to rebuild state
- Log compaction: periodic checkpoint + truncation
- Per-modality WAL segments for parallel recovery

### 2.2 ACID Transactions
**Criticality: CRITICAL** | Effort: Large | Module in `verisim-hexad`

Cross-modality atomicity. A hexad update must either succeed across all
modalities or fail completely.

- Transaction manager with begin/commit/rollback
- MVCC (Multi-Version Concurrency Control) for isolation
- Undo log for rollback across modalities
- Deadlock detection (modality-level locking)
- Configurable isolation levels: read-committed, serializable

### 2.3 Persistence Layer Abstraction
**Criticality: HIGH** | Effort: Large | Trait: `StorageBackend`

Currently in-memory only. Need pluggable backends.

- `StorageBackend` trait with get/put/delete/scan
- Backends: Memory (current), RocksDB, SQLite, LMDB
- Per-modality backend configuration
- Migration tooling between backends

### 2.4 Snapshots & Backup
**Criticality: HIGH** | Effort: Medium

- Point-in-time snapshots (consistent across all 6 modalities)
- Incremental backup (WAL-based)
- Restore from snapshot + WAL replay
- Export/import in portable format

---

## Phase 3: Security (CRITICAL for deployment)

### 3.1 Authentication
**Criticality: CRITICAL** | Effort: Medium

- API key authentication (REST, GraphQL, gRPC)
- JWT token support for stateless auth
- mTLS for gRPC
- Rate limiting per client

### 3.2 Authorization (RBAC)
**Criticality: HIGH** | Effort: Large

Configurable by admin, overridable by user, defaults to global.

- Role-based access control
- Per-modality permissions (read/write/admin)
- Per-entity access lists
- Admin: set global + per-modality defaults
- User: override within allowed scope
- Audit log of access decisions

### 3.3 Encryption at Rest
**Criticality: MEDIUM** | Effort: Medium

- AES-256-GCM for data files
- Key management via rokur (secrets manager)
- Per-modality encryption keys
- Key rotation without downtime

### 3.4 ZKP Integration (PLONK)
**Criticality: HIGH** | Effort: Large

Real zero-knowledge proof verification for VQL-DT PROOF clause.
Scheme: PLONK (see contractiles/trust/Trustfile for rationale).

- `ark-plonk` integration in verisim-semantic
- Circuit definitions for each proof type
- Universal SRS (Structured Reference String) management
- Proof generation API
- Proof verification in query pipeline
- Proof caching (verified proofs don't need re-verification)

---

## Phase 4: Normalizer (Core Differentiator)

### 4.1 Real Regeneration Strategies
**Criticality: CRITICAL** | Effort: Large

The normalizer is VeriSimDB's killer feature — currently stubs.

- Configurable authority ranking per modality
  - Admin sets global defaults
  - User can override for their entities
  - Default: Document > Semantic > Graph > Vector > Tensor > Temporal
- Regeneration strategies:
  - `from_authoritative`: regenerate drifted modality from highest-authority
  - `merge`: combine information from multiple modalities
  - `user_resolve`: flag for manual resolution
- Regeneration pipelines per modality pair
- Validation after regeneration (verify consistency restored)

### 4.2 Conflict Resolution Policies
**Criticality: HIGH** | Effort: Medium

- Last-writer-wins (default for non-critical data)
- Modality-priority (configurable ranking)
- Manual resolution queue
- Conflict history tracking

### 4.3 Normalization Audit Trail
**Criticality: MEDIUM** | Effort: Medium

- What was normalized, when, why
- Before/after snapshots
- Drift score history
- Admin dashboard for normalization health

---

## Phase 5: Query Engine Maturity

### 5.1 Query Profiling (EXPLAIN ANALYZE)
**Criticality: HIGH** | Effort: Medium

Close the loop between estimated and actual costs.

- `EXPLAIN ANALYZE` mode: execute + measure actual costs
- Per-step actual_ms vs estimated_ms
- Feed results into AdaptiveTuner automatically
- Profile history for query optimization

### 5.2 Prepared Statements / Query Caching
**Criticality: MEDIUM** | Effort: Medium

- Parse-once, execute-many for repeated queries
- Plan caching (skip re-optimization for identical plans)
- Parameterized queries (prevent VQL injection)
- Cache invalidation on schema/config changes

### 5.3 Result Streaming
**Criticality: MEDIUM** | Effort: Medium

- Server-sent events (REST)
- GraphQL subscriptions
- gRPC server streaming
- Backpressure handling
- Cursor-based pagination

### 5.4 Slow Query Log
**Criticality: LOW** | Effort: Small

- Configurable threshold (default: 100ms)
- Log query text, actual cost, plan chosen
- Integration with tracing/Prometheus

---

## Phase 6: Distributed Systems

### 6.1 Replication
**Criticality: HIGH** (for production) | Effort: Very Large

- Raft consensus (KRAFT node stubs exist in Elixir)
- Leader-follower replication
- Automatic failover
- Read replicas for scaling queries

### 6.2 Sharding
**Criticality: MEDIUM** | Effort: Large

- Hexad ID-based consistent hashing
- Per-modality shard assignment
- Cross-shard query routing
- Rebalancing without downtime

### 6.3 Real Federation
**Criticality: MEDIUM** | Effort: Large

- Federation resolver returns real results (currently empty)
- Cross-instance VQL queries
- Drift-aware federation (respect drift policies)
- Federation discovery protocol

---

## Phase 7: Ecosystem & Developer Experience

### 7.1 Benchmarks
**Criticality: HIGH** | Effort: Medium

Can't claim best-in-class without numbers.

- Benchmark suite: insert, query, mixed workload
- Compare against: ArangoDB, SurrealDB, Virtuoso
- Publish results with reproducible methodology
- CI-integrated regression benchmarks (criterion)

### 7.2 Client Libraries
**Criticality: HIGH** | Effort: Medium

- Rust SDK (typed, async, with VQL builder)
- Elixir SDK (direct BEAM integration)
- ReScript SDK (VQL builder + type-safe results)
- Each SDK: connection pooling, retry logic, auth

### 7.3 Documentation Site
**Criticality: MEDIUM** | Effort: Medium

- API reference (auto-generated from proto + GraphQL schema)
- VQL language guide with examples
- Architecture guide (Marr's three levels)
- Tutorial: "Build a multimodal search in 10 minutes"
- Deployment guide (Podman + Containerfile)

### 7.4 Containerized Deployment
**Criticality: MEDIUM** | Effort: Small

- Production Containerfile (multi-stage, chainguard base)
- selur-compose configuration
- Health check endpoints
- Graceful shutdown
- Resource limits and monitoring

### 7.5 Migration Tooling
**Criticality: LOW** | Effort: Medium

- Schema versioning
- Data migration scripts
- Import from: Neo4j (graph), Milvus (vector), PostgreSQL (document)
- Export to portable formats

---

## Phase 8: Observability

### 8.1 Metrics Dashboard
**Criticality: MEDIUM** | Effort: Small

- Grafana dashboard template
- Per-modality latency, throughput, error rate
- Drift score visualization
- Normalization event timeline
- Query cost distribution

### 8.2 Health Checks with Degraded States
**Criticality: LOW** | Effort: Small

- Per-modality health (not just binary healthy/unhealthy)
- Degraded mode: some modalities down, others serving
- Dependency health (Elixir orchestration, store backends)

---

## Summary: Priority Execution Order

| # | Item | Phase | Criticality |
|---|------|-------|-------------|
| 1 | VQL REPL (Rust CLI) | 1.1 | CRITICAL |
| 2 | Write-Ahead Log | 2.1 | CRITICAL |
| 3 | Real normalizer regeneration | 4.1 | CRITICAL |
| 4 | Authentication | 3.1 | CRITICAL |
| 5 | ACID transactions | 2.2 | CRITICAL |
| 6 | VQL REPL (Elixir IEx) | 1.2 | HIGH |
| 7 | ZKP/PLONK integration | 3.4 | HIGH |
| 8 | Authorization (RBAC) | 3.2 | HIGH |
| 9 | Query profiling (EXPLAIN ANALYZE) | 5.1 | HIGH |
| 10 | VQL LSP | 1.3 | HIGH |
| 11 | Persistence backends | 2.3 | HIGH |
| 12 | Benchmarks vs ArangoDB/SurrealDB/Virtuoso | 7.1 | HIGH |
| 13 | Client libraries | 7.2 | HIGH |
| 14 | Snapshots & backup | 2.4 | HIGH |
| 15 | Conflict resolution | 4.2 | HIGH |
| 16 | Replication | 6.1 | HIGH |
| 17 | VQL formatter | 1.4 | MEDIUM |
| 18 | Encryption at rest | 3.3 | MEDIUM |
| 19 | Result streaming | 5.3 | MEDIUM |
| 20 | Prepared statements | 5.2 | MEDIUM |
| 21 | Normalization audit trail | 4.3 | MEDIUM |
| 22 | Documentation site | 7.3 | MEDIUM |
| 23 | Metrics dashboard | 8.1 | MEDIUM |
| 24 | Containerized deployment | 7.4 | MEDIUM |
| 25 | Sharding | 6.2 | MEDIUM |
| 26 | Real federation | 6.3 | MEDIUM |
| 27 | Slow query log | 5.4 | LOW |
| 28 | Health check degraded states | 8.2 | LOW |
| 29 | Migration tooling | 7.5 | LOW |
