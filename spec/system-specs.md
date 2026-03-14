# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# VeriSimDB System Specifications

VeriSimDB is a multi-modal verification database with 8 modality stores and
built-in proof verification. Implementation stack: Rust core storage engine,
Elixir/OTP API layer, ReScript frontend.

---

## Memory Model

VeriSimDB's memory model spans three layers, each with distinct ownership
and allocation strategies.

### Rust Storage Engine

- **B-tree indices**: Rust-owned `BTreeMap` variants with custom page sizes.
  Pages are allocated via a slab allocator for predictable latency.
- **Vector indices**: Dense f32/f64 arrays for similarity search, allocated
  as contiguous `Vec<f32>` buffers. SIMD-aligned to 32-byte boundaries.
- **Write-ahead log (WAL)**: Memory-mapped file (`mmap`) with append-only
  writes. Rust owns the mapping lifetime via `MmapMut`.
- **Buffer pool**: Fixed-size page cache (configurable, default 256 MB).
  Pages are reference-counted (`Arc<Page>`) with LRU eviction.

### 8 Modality Stores

Each modality store manages its own memory independently:

| Modality       | Storage Type            | Memory Strategy              |
|----------------|-------------------------|------------------------------|
| Textual        | B-tree + inverted index | Slab-allocated postings      |
| Numeric        | B-tree                  | Inline leaf values           |
| Temporal       | Interval tree           | Arena-allocated nodes        |
| Spatial        | R-tree                  | Page-based with bulk loading |
| Vector         | HNSW graph              | Contiguous f32 buffers       |
| Graph          | Adjacency lists         | CSR format, arena-allocated  |
| Provenance     | Merkle DAG              | Hash-addressed content store |
| Categorical    | Bitmap index            | Roaring bitmaps              |

### Elixir API Layer

- Elixir/BEAM manages all API-layer memory via its per-process heap GC.
- Each Elixir process has an isolated heap — no shared mutable state.
- Query results crossing from Rust to Elixir are serialised as Erlang terms
  via NIF (Native Implemented Function) calls.
- Large result sets use resource objects (`enif_alloc_resource`) to avoid
  copying — Rust retains ownership, Elixir holds a reference.

### ReScript Frontend

- ReScript compiles to JavaScript; browser GC manages all frontend memory.
- Query results are received as JSON over HTTP/WebSocket.
- No direct memory sharing between frontend and backend.

---

## Concurrency Model

VeriSimDB uses a hybrid concurrency model combining Elixir's actor model
with Rust's async runtime.

### Elixir/OTP Actor Model (Query Processing)

- Each incoming query spawns a dedicated Elixir process (lightweight, ~2 KB).
- Query planning, optimisation, and result assembly happen in Elixir processes.
- OTP supervisors manage process lifecycles and restart on failure.
- GenServer processes manage connection pools to the Rust storage engine.

### Rust Tokio Runtime (Storage I/O)

- The Rust storage engine runs on a multi-threaded `tokio` runtime.
- Read operations use shared locks (`RwLock<T>`) on B-tree pages.
- Write operations acquire exclusive locks with WAL-based crash recovery.
- Background tasks (compaction, index rebuilding) run as spawned tokio tasks
  with lower priority.

### Cross-Modal Query Coordination

- Queries spanning multiple modalities are decomposed by the Elixir query
  planner into per-modality sub-queries.
- Sub-queries execute concurrently (one tokio task per modality store).
- Results are collected via `tokio::sync::mpsc` channels.
- The Elixir process assembles final results from all modality responses.
- Join operations across modalities use hash-join or merge-join depending
  on the query planner's cost estimate.

### Consistency Model

- Single-modality operations are serialisable (WAL + exclusive write locks).
- Cross-modal transactions use a two-phase commit protocol coordinated by
  the Elixir transaction manager.
- Read snapshots use MVCC — readers never block writers.

---

## Effect System

VeriSimDB's effect system centres on proof verification. Every query result
carries proof metadata.

### Proof Effects

Proof verification occurs during query execution, not after:

| Proof Type    | Verification                                    | Cost     |
|---------------|------------------------------------------------|----------|
| `EXISTENCE`   | Merkle proof that the record exists in the store| O(log n) |
| `INTEGRITY`   | Hash chain verification of record contents      | O(1)     |
| `CITATION`    | Provenance DAG traversal to source records      | O(d)     |
| `TEMPORAL`    | Timestamp ordering proof via interval tree      | O(log n) |
| `SPATIAL`     | Bounding-box containment proof via R-tree       | O(log n) |

### Query Proof Composition

- A cross-modal query produces a **composite proof**: one sub-proof per
  modality involved.
- Composite proofs are serialised as a Merkle tree of sub-proofs.
- The root hash of the composite proof is returned with the query result.

### Proof Verification Modes

| Mode        | Behaviour                                        |
|-------------|--------------------------------------------------|
| `Strict`    | All proof types verified; query fails on any failure |
| `Optimistic`| Proofs computed but verification deferred to client |
| `None`      | No proofs computed (performance mode)              |

### Effect Tracking in the Elixir Layer

- Each query carries an effect context (`%ProofContext{}` struct).
- The context accumulates proof obligations as the query plan executes.
- NIF calls to the Rust engine return proof artifacts alongside data.
- The Elixir layer assembles the final proof tree before returning results.

---

## Module System

VeriSimDB's module system reflects its polyglot architecture.

### Rust Crate Workspace

| Crate              | Responsibility                                  |
|--------------------|------------------------------------------------|
| `verisimdb-core`   | Storage engine, page management, WAL            |
| `verisimdb-index`  | B-tree, R-tree, HNSW, bitmap index implementations |
| `verisimdb-proof`  | Merkle proofs, hash chains, proof composition    |
| `verisimdb-nif`    | Erlang NIF bindings (Rustler)                   |
| `verisimdb-query`  | Query IR, physical operators, execution engine   |

### Elixir OTP Application

| Module                    | Responsibility                          |
|---------------------------|-----------------------------------------|
| `VeriSimDB.Application`   | OTP application entry, supervisor tree  |
| `VeriSimDB.QueryPlanner`  | SQL-like query parsing and planning     |
| `VeriSimDB.ModalRouter`   | Routes sub-queries to modality stores   |
| `VeriSimDB.ProofAssembler`| Collects and composes modality proofs   |
| `VeriSimDB.Connection`    | NIF connection pool to Rust engine      |
| `VeriSimDB.Transaction`   | Two-phase commit coordinator            |

### ReScript Frontend

| Module               | Responsibility                             |
|----------------------|--------------------------------------------|
| `QueryBuilder`       | Type-safe query construction               |
| `ProofViewer`        | Proof tree visualisation component         |
| `ModalitySelector`   | UI for selecting query modalities           |
| `ResultTable`        | Tabular result display with proof badges    |

### Inter-Layer Communication

- **Rust <-> Elixir**: Erlang NIFs via Rustler. Binary protocol with
  zero-copy where possible (resource objects).
- **Elixir <-> ReScript**: JSON over HTTP (REST) or WebSocket (streaming
  results). Phoenix Channels for live query subscriptions.
