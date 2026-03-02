# CLAUDE.md - VeriSimDB AI Assistant Instructions

## Project Overview

VeriSimDB (Veridical Simulacrum Database) is a cross-system entity consistency engine with drift detection, self-normalisation, and formally verified queries. Each entity exists simultaneously across 8 modalities — the octad (Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, Spatial) — with drift detection and automatic consistency maintenance. Operates as standalone database OR heterogeneous federation coordinator over existing databases.

## Machine-Readable Artefacts

The following files in `.machine_readable/` contain structured project metadata:
- `STATE.scm` - Current project state and progress
- `META.scm` - Architecture decisions and development practices
- `ECOSYSTEM.scm` - Position in the ecosystem and related projects

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Elixir Orchestration Layer                                 │
│    ├── VeriSim.EntityServer (GenServer per entity)          │
│    ├── VeriSim.DriftMonitor (drift detection coordinator)   │
│    ├── VeriSim.QueryRouter (distributes queries)            │
│    └── VeriSim.SchemaRegistry (type system coordinator)     │
│              ↓ HTTP                                         │
├─────────────────────────────────────────────────────────────┤
│  Rust Core (verisim-api)                                    │
│    ├── verisim-graph (Oxigraph RDF/Property Graph)          │
│    ├── verisim-vector (HNSW similarity search)              │
│    ├── verisim-tensor (ndarray/Burn tensors)                │
│    ├── verisim-semantic (CBOR proof blobs)                  │
│    ├── verisim-document (Tantivy full-text)                 │
│    ├── verisim-temporal (versioning/time-series)            │
│    ├── verisim-provenance (origin/lineage tracking)          │
│    ├── verisim-spatial (geospatial/R-tree)                   │
│    ├── verisim-hexad (unified entity → octad evolution)     │
│    ├── verisim-drift (drift detection)                      │
│    └── verisim-normalizer (self-normalization)              │
└─────────────────────────────────────────────────────────────┘
```

## Design Philosophy (Marr's Three Levels)

1. **Computational Level**: What problem are we solving?
   - Maintain cross-modal consistency across 8 representations of the same entity (octad)
   - Detect and repair drift before it causes data quality issues
   - Provide unified querying across all modalities

2. **Algorithmic Level**: How do we solve it?
   - Octad entities: one ID, eight synchronized stores
   - Drift detection with configurable thresholds
   - Self-normalization triggered by drift events
   - OTP supervision for fault tolerance

3. **Implementational Level**: How is it built?
   - Rust for performance-critical modality stores
   - Elixir/OTP for distributed coordination
   - HTTP API for communication
   - Prometheus metrics for observability

## Language Policy

### ALLOWED
- **Rust** - Core database engine, modality stores
- **Elixir** - OTP orchestration layer
- **ReScript** - VQL parser, federation registry
- **VQL** - VeriSim Query Language (native query interface, NOT SQL)

### BANNED
- Python - Use Rust instead
- Go - Use Rust instead
- Node.js - Use Elixir instead

## Build Commands

### Rust Core
```bash
cd rust-core
cargo build
cargo test
cargo clippy
```

### Elixir Orchestration
```bash
cd elixir-orchestration
mix deps.get
mix compile
mix test
```

### Full Build
```bash
# Rust first (Elixir depends on it at runtime)
cargo build --release

# Then Elixir
cd elixir-orchestration && mix compile
```

## Container Deployment

Use Podman (NOT Docker):
```bash
# In-memory (default)
podman build -t verisimdb:latest -f container/Containerfile .
podman run -p 8080:8080 verisimdb:latest

# Persistent storage (redb graph + file-backed Tantivy + WAL)
podman build -t verisimdb:persistent --build-arg FEATURES=persistent -f container/Containerfile .
podman run -p 8080:8080 -v verisimdb-data:/data verisimdb:persistent
```

### Verified Container Deployment (stapeln)

For supply-chain-verified deployment with the stapeln ecosystem:
```bash
# Build, sign, verify as .ctp bundle
cd container && ./ct-build.sh persistent --push

# Full stack via selur-compose (rust-core + elixir + svalinn gateway)
selur-compose up --detach
```

Key files in `container/`:
- `compose.toml` — selur-compose stack definition (3 services + volumes + networks)
- `.gatekeeper.yaml` — svalinn edge gateway policy (auth, rate limits, trust)
- `manifest.toml` — cerro-torre .ctp bundle manifest (provenance, attestations, security)
- `ct-build.sh` — build/sign/verify pipeline script

## Test Infrastructure

Integration test stack in `connectors/test-infra/`:

```bash
# Start test databases
cd connectors/test-infra && selur-compose up -d
# Or fallback: podman-compose up -d

# Run integration tests
cd elixir-orchestration && mix test --include integration

# Stop stack
cd connectors/test-infra && selur-compose down
```

Services: MongoDB (27017), Redis Stack (6379), Neo4j (7474/7687), ClickHouse (8123/9000), SurrealDB (8000), InfluxDB (8086), MinIO (9002/9001).

All images use `cgr.dev/chainguard/wolfi-base:latest`.

## Key Concepts

### Octad Entity (formerly Hexad)
An Octad is one entity with 8 synchronized representations:
- **Graph**: RDF triples and property graph edges
- **Vector**: Embedding for similarity search
- **Tensor**: Multi-dimensional representation — active research into novel applications (details forthcoming)
- **Semantic**: Type annotations and proof blobs
- **Document**: Full-text searchable content
- **Temporal**: Version history and time-series
- **Provenance**: Origin tracking, transformation chain, actor trail (implemented — hash-chain integrity, actor search)
- **Spatial**: Geospatial coordinates, geometries, proximity queries (implemented — R-tree index, radius/bounds/nearest search)

### Drift Detection
Drift is measured as divergence between modalities:
- `semantic_vector_drift`: Embedding doesn't match semantic content
- `graph_document_drift`: Graph structure doesn't match document
- `temporal_consistency_drift`: Version history issues
- `tensor_drift`: Tensor representation diverged
- `schema_drift`: Type constraint violations
- `quality_drift`: Overall data quality

### Self-Normalization
When drift exceeds thresholds, the normalizer:
1. Identifies the most authoritative modality
2. Regenerates drifted modalities from it
3. Validates consistency
4. Updates all modalities atomically

## Code Patterns

### Creating a Hexad (Rust)
```rust
let input = HexadBuilder::new()
    .with_document("Title", "Body content")
    .with_embedding(vec![0.1, 0.2, ...])
    .with_types(vec!["http://example.org/Document"])
    .with_relationships(vec![("relates_to", "other-entity-id")])
    .build();

let hexad = store.create(input).await?;
```

### Entity Server (Elixir)
```elixir
# Start entity server
{:ok, _pid} = VeriSim.EntityServer.start_link("entity-123")

# Get state
{:ok, state} = VeriSim.EntityServer.get("entity-123")

# Update
{:ok, new_state} = VeriSim.EntityServer.update("entity-123", [
  {:modality, :vector, true}
])
```

## Testing

### Unit Tests
```bash
cargo test                    # Rust
mix test                      # Elixir
```

### Integration Tests
```bash
cargo test --test integration # Rust integration tests
mix test test/integration     # Elixir integration tests
```

### Federation Adapter Integration Tests
```bash
# Requires test-infra stack running (see Test Infrastructure section above)
cd elixir-orchestration && mix test --include integration
# 105 tests across 7 adapter test files (MongoDB, Redis, Neo4j, ClickHouse, SurrealDB, InfluxDB, MinIO)
```

## GitHub CI Integration (Priority - Sonnet Task)

VeriSimDB needs to service all ~290 hyperpolymath repos from GitHub Actions CI.

### Architecture: Git-Backed Flat-File Store

Instead of running verisimdb as a persistent server in GitHub, use a **git-backed data repo**:

```
hyperpolymath/verisimdb-data (new repo)
├── scans/                    # panic-attack scan results per repo
│   ├── echidna.json
│   ├── verisimdb.json
│   └── ...
├── hardware/                 # hardware-crash-team findings
│   └── latest-scan.json
├── drift/                    # drift detection snapshots
│   └── drift-status.json
├── index.json                # Master index of all hexads
└── .github/workflows/
    └── ingest.yml            # Workflow: receive data, update index
```

### How It Works

1. **Each repo's CI** runs panic-attack, produces JSON, pushes to `verisimdb-data` via workflow dispatch
2. **verisimdb-data ingest workflow** receives the JSON, stores it, updates the index
3. **Query** by checking out verisimdb-data and reading JSON (no server needed)
4. **Local dev**: Run `verisim-api` server locally, load from the data repo

### Implementation Steps (for Sonnet)

1. Create `verisimdb-data` repo from rsr-template-repo
2. Add `ingest.yml` workflow that accepts repository_dispatch events with scan payloads
3. Add a reusable workflow `scan-and-report.yml` that repos can call:
   - Runs `panic-attack assail` on the repo
   - Sends results to verisimdb-data via repository_dispatch
4. Add the reusable workflow to 2-3 pilot repos first (echidna, panic-attacker, ambientops)
5. Add a `query.sh` script that clones verisimdb-data and searches the index

### Future: Persistent Server

When ready to scale beyond flat files:
- Deploy verisim-api to **Fly.io free tier** (3 shared VMs, 1GB persistent volume)
- Use the Containerfile already in `container/`
- GitHub Actions calls the Fly.io endpoint instead of repository_dispatch
- Keep verisimdb-data as backup/mirror

## Hypatia Integration Pipeline

### Data Flow (IMPLEMENTED)

```
panic-attack assail → ScanIngester → octad hexads → PatternQuery → DispatchBridge → gitbot-fleet
                      ↑ WORKS        ↑ WORKS        ↑ WORKS        ↑ WORKS          ↑ JSONL logged
```

### VeriSimDB-Side Modules (elixir-orchestration/lib/verisim/hypatia/)

1. **ScanIngester** (`scan_ingester.ex`): Ingests panic-attack scan results as octad hexad entities
   - Builds Document (searchable text), Graph (triples), Temporal (timestamps), Vector (embeddings),
     Provenance (scanner origin), Semantic (category tags) modalities
   - Falls back to ETS (`:hypatia_scans`) when Rust core unavailable
   - API: `ingest_scan/1`, `ingest_file/1`, `ingest_directory/1`, `list_scans/0`, `get_scan/1`

2. **PatternQuery** (`pattern_query.ex`): Cross-repo pattern analytics over ingested scans
   - API: `pipeline_health/0`, `cross_repo_patterns/1`, `severity_distribution/0`,
     `category_distribution/0`, `temporal_trends/1`, `repos_by_severity/1`, `weakness_hotspots/0`

3. **DispatchBridge** (`dispatch_bridge.ex`): Bridge to Hypatia dispatch pipeline
   - Reads JSONL dispatch manifests from `verisimdb-data/dispatch/`
   - Tracks execution status and feeds outcomes back for drift tracking
   - API: `read_pending/1`, `read_dispatch_log/2`, `read_all_dispatch_logs/1`,
     `read_outcomes/1`, `summarize/1`, `feedback_to_drift/1`, `ingest_dispatch_summary/1`

### Remaining: Fleet Dispatch (Live Execution)

Fleet dispatch is logged to JSONL but not yet executing live GraphQL mutations.
Requires GitHub PAT with `repo` scope — see `verisimdb-data/INTEGRATION.md`.

## Model Router (Future Tool - Sonnet Task)

A tool to auto-select Claude model based on task complexity. Architecture:

```
User prompt → Haiku classifier → Route to:
  ├── Haiku:  single-file edits, template creation, simple queries
  ├── Sonnet: multi-file implementation, feature work, testing
  └── Opus:   architecture decisions, debugging, cross-repo design
```

### Classification Signals
- File count affected (1 = Haiku, 2-5 = Sonnet, 5+ = Opus)
- Task type (create = Sonnet, debug = Opus, edit = Haiku)
- CLAUDE.md complexity rating per repo
- Presence of "why", "how", "design" in prompt → Opus
- Presence of "add", "create", "implement" → Sonnet
- Presence of "fix typo", "rename", "update version" → Haiku

### Implementation
- Rust CLI tool or Claude Code hook
- Reads CLAUDE.md to understand repo complexity
- Uses Haiku API call (~0.001 cents) to classify
- Returns recommended model as stdout

## Known Issues

See `KNOWN-ISSUES.adoc` at repo root for all honest gaps. All 25 issues resolved.

Resolved in recent sessions:
- VQL-DT type checker wired end-to-end (Elixir-native + ReScript + Rust ZKP bridge)
- 11 proof types: EXISTENCE, INTEGRITY, CONSISTENCY, PROVENANCE, FRESHNESS, ACCESS, CITATION, CUSTOM, ZKP, PROVEN, SANCTIFY
- Multi-proof parsing: PROOF A(x) AND B(y) splits correctly
- Modality compatibility validation (INTEGRITY needs semantic, PROVENANCE needs provenance, etc.)
- proven library integrated (certificate-based JSON/CBOR bridge)
- verisim-repl builds clean (67 tests pass)
- oxrocksdb-sys C++ dependency eliminated (Oxigraph feature-flagged, redb pure-Rust backend added)
- protoc build dependency eliminated (proto code pre-generated)
- stapeln container ecosystem integrated (compose.toml, .gatekeeper.yaml, manifest.toml, ct-build.sh)
- VQL Playground wired to real backend (ApiClient.res, async execution, demo mode fallback, octad modalities)
- PanLL database module protocol (DatabaseModule.res, DatabaseRegistry.res — VeriSimDB/QuandleDB/LithoGlyph)
- Product telemetry: opt-in collector (ETS), reporter (JSON), 19 telemetry tests, VQL executor + drift monitor wired
- PanLL telemetry dashboard panel with modality heatmap, query patterns, performance metrics

## Hypatia Integration Status

**Working (VeriSimDB side — 3 modules, 37 tests):**
- ScanIngester: panic-attack JSON → octad hexads (Document, Graph, Temporal, Vector, Provenance, Semantic)
- PatternQuery: cross-repo analytics (pipeline health, severity distribution, temporal trends, hotspots)
- DispatchBridge: reads JSONL dispatch manifests, summarizes outcomes, feeds drift tracking
- Hypatia VQL layer reads verisimdb-data flat files directly
- Built-in Elixir VQL parser (no external Deno/Node needed)
- 954 canonical patterns tracked across 298 repos

**Needs PAT:** Automated cross-repo dispatch requires a GitHub PAT with `repo` scope.
See `verisimdb-data/INTEGRATION.md` for PAT setup instructions.

## User Preferences

- **Container runtime**: Podman > Docker
- **Source hosting**: GitLab > GitHub
- **Package manager**: Cargo (Rust), Mix (Elixir)
- **No Python**: Use Rust for systems, Julia for data processing

## Repository Structure

```
verisimdb/
├── Cargo.toml                 # Workspace definition
├── rust-core/                 # Rust crates
│   ├── verisim-graph/
│   ├── verisim-vector/
│   ├── verisim-tensor/
│   ├── verisim-semantic/
│   ├── verisim-document/
│   ├── verisim-temporal/
│   ├── verisim-hexad/
│   ├── verisim-drift/
│   ├── verisim-normalizer/
│   └── verisim-api/
├── elixir-orchestration/      # Elixir/OTP layer
│   ├── lib/verisim/
│   ├── config/
│   └── mix.exs
├── connectors/                # Federation adapters + client SDKs + test infra
│   ├── clients/               # 6 SDKs: Rust, V, Elixir, ReScript, Julia, Gleam
│   ├── shared/                # JSON Schema, OpenAPI, protobuf
│   └── test-infra/            # selur-compose: 7 databases for integration testing
├── container/                 # Containerfiles
├── docs/                      # Documentation
└── tests/                     # Integration tests
```
