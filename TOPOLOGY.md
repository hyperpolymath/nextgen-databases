<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# TOPOLOGY.md — VeriSimDB

## System Architecture

```
                    ┌─────────────────────────────────────┐
                    │        svalinn (TLS gateway)        │
                    │    ML-DSA-87 · policy: strict       │
                    └────────────────┬────────────────────┘
                                     │ :8443
                    ┌────────────────▼────────────────────┐
                    │     Elixir OTP Orchestration        │
                    │  ┌──────────┐ ┌──────────────────┐  │
                    │  │ Entity   │ │ Drift            │  │
                    │  │ Server   │ │ Monitor          │  │
                    │  │(GenServer│ │(threshold-gated) │  │
                    │  │ per      │ │                  │  │
                    │  │ hexad)   │ │ Schema Registry  │  │
                    │  └──────────┘ └──────────────────┘  │
                    │  ┌──────────┐ ┌──────────────────┐  │
                    │  │ Query    │ │ VQL Parser        │  │
                    │  │ Router   │ │ (ReScript)        │  │
                    │  └──────────┘ └──────────────────┘  │
                    └────────────────┬────────────────────┘
                                     │ HTTP :8080
    ┌────────────────────────────────▼────────────────────────────────┐
    │                    Rust Core (verisim-api)                      │
    │                                                                 │
    │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
    │  │  Graph   │ │  Vector  │ │  Tensor  │ │    Semantic      │  │
    │  │ Oxigraph │ │  HNSW    │ │ndarray/  │ │   CBOR proofs    │  │
    │  │ RDF +    │ │ ANN      │ │  Burn    │ │   ZKP blobs      │  │
    │  │ property │ │ search   │ │ compute  │ │                  │  │
    │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │
    │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
    │  │ Document │ │ Temporal │ │  Hexad   │ │   Normalizer     │  │
    │  │ Tantivy  │ │ version  │ │ unified  │ │ self-normalizing │  │
    │  │ full-text│ │ + time   │ │ entity   │ │ drift repair     │  │
    │  │ index    │ │ series   │ │ 6-modal  │ │                  │  │
    │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │
    └────────────────────────────────────────────────────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
    ┌──────────────┐     ┌──────────────────┐    ┌──────────────────┐
    │    vordr     │     │   cerro-torre    │    │     rokur        │
    │   runtime    │     │  image signing   │    │   secret         │
    │ verification │     │  ML-DSA-87       │    │   rotation       │
    │ formal proofs│     │  SBOM + SLSA 3   │    │   argon2id       │
    └──────────────┘     └──────────────────┘    └──────────────────┘

    Data flow:
    panic-attack → verisimdb-data (flat-file) → hypatia (rules) → gitbot-fleet (fixes)
```

## Completion Dashboard

| Component              | Progress                     | Status       |
|------------------------|------------------------------|--------------|
| verisim-graph          | `████████░░` 80%             | Active       |
| verisim-vector         | `████████░░` 80%             | Active       |
| verisim-tensor         | `███████░░░` 70%             | Active       |
| verisim-semantic       | `██████░░░░` 60%             | Active       |
| verisim-document       | `████████░░` 80%             | Active       |
| verisim-temporal       | `███████░░░` 70%             | Active       |
| verisim-hexad          | `████████░░` 80%             | Active       |
| verisim-drift          | `███████░░░` 70%             | Active       |
| verisim-normalizer     | `██████░░░░` 60%             | Active       |
| verisim-api            | `████████░░` 80%             | Active       |
| Elixir OTP layer       | `███████░░░` 70%             | Active       |
| VQL parser             | `█████████░` 95%             | Active       |
| VQL-DT (Lean checker)  | `░░░░░░░░░░` 0%              | Not started  |
| Idris2 ABI             | `████░░░░░░` 40%             | In progress  |
| Zig FFI                | `████░░░░░░` 40%             | In progress  |
| Containerfile          | `██████████` 100%            | Complete     |
| selur-compose          | `██████████` 100%            | Complete     |
| stapeln.toml           | `██████████` 100%            | Complete     |
| verisimdb-data (CI)    | `████████░░` 80%             | Active       |
| Hypatia integration    | `████░░░░░░` 40%             | In progress  |
| proven integration     | `░░░░░░░░░░` 0%              | Planned      |
| **Overall**            | `██████░░░░` **65%**         |              |

## Key Dependencies

```
verisimdb
├── oxigraph (graph store — RDF + property graph)
├── hnsw_rs (vector similarity — ANN search)
├── tantivy (document store — full-text indexing)
├── burn (tensor compute — ML inference)
├── ndarray (tensor operations)
├── chrono (temporal versioning)
├── cbor (semantic proof blobs)
├── axum (HTTP API framework)
├── tokio (async runtime)
├── elixir 1.18 / OTP 27 (orchestration)
│
├── Container ecosystem:
│   ├── svalinn (TLS gateway + policy enforcement)
│   ├── vordr (runtime verification)
│   ├── cerro-torre (image signing, ML-DSA-87)
│   ├── rokur (secret rotation, argon2id)
│   └── stapeln (layer-based builds)
│
└── Data pipeline:
    ├── panic-attacker → scan results
    ├── verisimdb-data → flat-file store
    ├── hypatia → rule engine
    └── gitbot-fleet → automated fixes
```
