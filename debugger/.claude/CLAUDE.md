# CLAUDE.md — VeriSimDB Debugger

## Purpose

The VeriSimDB debugger is a Rust TUI (ratatui/crossterm) tool that provides interactive debugging, inspection, and visualisation of VeriSimDB internals. It serves **two simultaneous roles**:

1. **Production debugger** for VeriSimDB operators and developers
2. **Reference example** demonstrating how PanLL's database design/development/evaluation functions work with a real database

## Architecture Mandate

This debugger MUST be designed so that **PanLL can embed and drive it programmatically**. Every UI panel in the TUI corresponds to a PanLL pane concept:

| TUI Panel | PanLL Pane | Function |
|-----------|-----------|----------|
| Modality Inspector | Pane-W (results) | View all 8 octad modalities for a given entity |
| Drift Heatmap | Pane-W (results) | Colour-coded grid of drift scores across entities |
| VQL Trace | Pane-N (reasoning) | Step-by-step VQL query execution trace |
| Proof Verifier | Pane-L (constraints) | VQL-DT proof obligation checking and certificate display |
| Federation Map | Pane-W (results) | Live peer status, replication lag, adapter types |
| Performance Flamegraph | Pane-W (results) | Query latency breakdown by modality |
| Normalisation Timeline | Pane-N (reasoning) | History of self-normalisation events, before/after states |
| Error Budget Dashboard | Pane-L (constraints) | SLO tracking, error rates, circuit breaker status |

## Example Use Cases (for PanLL integration)

### Database Design/Development/Evaluation

PanLL should use this debugger as its **canonical example** for the database design/development/evaluation module. When implementing PanLL's database evaluation functions, reference this debugger's:

- **Entity inspection**: How to display multi-modal data (8 modalities) in a coherent view
- **Drift detection visualisation**: How to show data quality metrics across a large entity set
- **Query tracing**: How to step through query execution plans and show which modality stores were hit
- **Proof certificates**: How to display formal verification results in a human-readable way
- **Federation monitoring**: How to show distributed system health across multiple database backends

### Language Design/Development/Evaluation

PanLL should use **Eclexia** (from `nextgen-languages/eclexia/`) as the canonical example for its language design/development/evaluation module. The VeriSimDB debugger connects to Eclexia via:

- VQL is defined in Eclexia's grammar format → debugger can show VQL parse trees
- VQL-DT proof obligations are typed in Eclexia's type system → debugger can show type derivation trees
- Eclexia's REPL can be embedded as a debugger panel for interactive VQL exploration

## Implementation Spec

### Phase 1: Core Infrastructure (Do This First)

Build the TUI skeleton with these panels:

```
┌──────────────────────────────────┬──────────────────────────────────┐
│  Entity Inspector                │  Drift Heatmap                   │
│  ├── hexad_id                    │  ┌────────────────────────────┐  │
│  ├── graph: [edges]              │  │ ■■■■■■■■ entity-001  0.02  │  │
│  ├── vector: [dims]              │  │ ■■■■■■■□ entity-002  0.15  │  │
│  ├── tensor: [shape]             │  │ ■■■□□□□□ entity-003  0.67  │  │
│  ├── semantic: [types]           │  │ ■■■■■■■■ entity-004  0.01  │  │
│  ├── document: [text preview]    │  └────────────────────────────┘  │
│  ├── temporal: [versions]        │                                  │
│  ├── provenance: [chain]         │                                  │
│  └── spatial: [coords]           │                                  │
├──────────────────────────────────┼──────────────────────────────────┤
│  VQL Trace                       │  Proof Verifier                  │
│  > SELECT * FROM hexads          │  PROOF EXISTENCE(entity-001)     │
│    1. Parse: 2ms                 │    ✅ hexad_id: found            │
│    2. Type-check: 15ms           │    ✅ modality_count: 8          │
│    3. Route → graph,vector: 8ms  │    ✅ certificate: SHA-256 ok    │
│    4. Execute graph: 12ms        │                                  │
│    5. Execute vector: 9ms        │  PROOF PROVENANCE(entity-001)    │
│    6. Cross-modal merge: 3ms     │    ✅ chain_length: 5            │
│    7. Return 42 rows: 1ms        │    ✅ chain_hash: verified       │
│  Total: 50ms                     │    ✅ certificate: SHA-256 ok    │
└──────────────────────────────────┴──────────────────────────────────┘
```

### Phase 2: API Client

Connect to VeriSimDB via:
- **Rust core** at `http://localhost:8080/api/v1/` — entity CRUD, search, drift
- **Elixir orchestration** at `http://localhost:4080/` — telemetry, health, consensus status
- **gRPC** at `localhost:50051` — for high-throughput entity streaming

### Phase 3: PanLL Protocol

Expose a JSON-over-stdio protocol so PanLL can drive the debugger headlessly:
- `{"cmd": "inspect", "entity_id": "..."}` → returns entity data for all 8 modalities
- `{"cmd": "drift_scan", "threshold": 0.3}` → returns entities with drift above threshold
- `{"cmd": "trace_vql", "query": "SELECT ..."}` → returns execution trace
- `{"cmd": "verify_proof", "query": "... PROOF ..."}` → returns proof certificates
- `{"cmd": "health"}` → returns full telemetry snapshot

### Phase 4: Eclexia Integration

Add a panel that can:
- Parse VQL using Eclexia's grammar and show the parse tree
- Show VQL-DT type derivation trees using Eclexia's type system
- Provide an interactive VQL REPL powered by Eclexia's evaluator

## Build Commands

```bash
cd debugger
cargo build
cargo test
cargo run -- --help

# Connect to running VeriSimDB
cargo run -- --rust-url http://localhost:8080 --orch-url http://localhost:4080
```

## Key Dependencies

- `ratatui` 0.29 + `crossterm` 0.28 — TUI framework
- `reqwest` — HTTP client for VeriSimDB API
- `tokio` — async runtime
- `clap` — CLI argument parsing
- `serde_json` — JSON serialization for PanLL protocol

## What NOT To Do

- Do NOT duplicate VeriSimDB logic in the debugger — always call the API
- Do NOT add a web UI — TUI only (PanLL handles the web layer)
- Do NOT use Python, Go, TypeScript, or Node.js
- Do NOT use unsafe Rust without `// SAFETY:` comments
- Do NOT store entity data locally — the debugger is stateless
