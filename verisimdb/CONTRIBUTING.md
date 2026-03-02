# Contributing to VeriSimDB

<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk> -->

Thank you for your interest in contributing to VeriSimDB. This document explains how to get started, our development workflow, and how to submit changes.

## Quick Start

### Prerequisites

- **Rust** (nightly) — `asdf install rust nightly` or `rustup install nightly`
- **Elixir** 1.17+ with Erlang/OTP 27+ — `asdf install elixir` / `asdf install erlang`
- **Podman** — for container builds (never Docker)

### Setup

```bash
# Clone the repository
git clone https://github.com/hyperpolymath/verisimdb.git
cd verisimdb

# Build Rust core
cargo build
cargo test

# Build Elixir orchestration
cd elixir-orchestration
mix deps.get
mix compile
mix test
```

### Repository Structure

```
verisimdb/
├── rust-core/                # Rust crates (14 workspace members)
│   ├── verisim-api/          # HTTP/gRPC API server
│   ├── verisim-graph/        # Graph modality (RDF/Property Graph)
│   ├── verisim-vector/       # Vector modality (HNSW)
│   ├── verisim-tensor/       # Tensor modality (Burn)
│   ├── verisim-semantic/     # Semantic modality (CBOR proofs)
│   ├── verisim-document/     # Document modality (Tantivy)
│   ├── verisim-temporal/     # Temporal modality (versioning)
│   ├── verisim-hexad/        # Unified 6-modal entity
│   ├── verisim-drift/        # Drift detection
│   ├── verisim-normalizer/   # Self-normalization
│   ├── verisim-planner/      # Cost-based query planner
│   ├── verisim-repl/         # Interactive VQL REPL
│   ├── verisim-wal/          # Write-ahead log
│   └── verisim-storage/      # Storage backend abstraction
├── elixir-orchestration/     # Elixir/OTP coordination layer
├── playground/               # VQL Playground PWA (ReScript)
├── container/                # Containerfile for Podman builds
├── docs/                     # Architecture and design documents
├── contractiles/             # Trust, security, and policy contracts
├── .machine_readable/        # SCM checkpoint files
└── .github/workflows/        # CI/CD pipelines
```

---

## How to Contribute

### Reporting Bugs

**Before reporting**:
1. Search existing issues on [GitHub](https://github.com/hyperpolymath/verisimdb/issues) or [GitLab](https://gitlab.com/hyperpolymath/verisimdb/-/issues)
2. Check if it's already fixed in `main`

**When reporting**, include:
- Clear, descriptive title
- Environment details (OS, Rust version, Elixir version)
- Steps to reproduce
- Expected vs actual behaviour
- Logs, error messages, or minimal reproduction

### Suggesting Features

**Before suggesting**:
1. Check the [roadmap](ROADMAP.adoc)
2. Search existing issues and discussions

**When suggesting**, include:
- Problem statement (what pain point does this solve?)
- Proposed solution
- Alternatives considered
- Which modality or component it affects

### Your First Contribution

Look for issues labelled:
- [`good first issue`](https://github.com/hyperpolymath/verisimdb/labels/good%20first%20issue) — Simple tasks
- [`help wanted`](https://github.com/hyperpolymath/verisimdb/labels/help%20wanted) — Community help needed
- [`documentation`](https://github.com/hyperpolymath/verisimdb/labels/documentation) — Docs improvements

---

## Development Workflow

### Branch Naming
```
docs/short-description       # Documentation
test/what-added              # Test additions
feat/short-description       # New features
fix/issue-number-description # Bug fixes
refactor/what-changed        # Code improvements
security/what-fixed          # Security fixes
```

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `security`

### Testing

```bash
# Rust — all tests
cargo test

# Rust — specific crate
cargo test -p verisim-semantic

# Elixir
cd elixir-orchestration && mix test

# Container build verification
podman build -t verisimdb:latest -f container/Containerfile .
```

### Code Quality

```bash
# Rust linting
cargo clippy -- -D warnings

# Check formatting
cargo fmt --check
```

---

## Language Policy

### Allowed Languages

| Language | Use Case |
|----------|----------|
| **Rust** | Core database engine, modality stores, CLI tools |
| **Elixir** | OTP orchestration, distributed coordination |
| **ReScript** | VQL parser, playground PWA |
| **VQL** | VeriSim Query Language (query interface) |

### Not Accepted

- TypeScript (use ReScript instead)
- Python (use Rust or Julia instead)
- Go (use Rust instead)
- Node.js/npm/bun (use Deno if JS runtime needed)

---

## License

By contributing, you agree that your contributions will be licensed under the **PMPL-1.0-or-later** (Palimpsest License). All source files must include:

```
// SPDX-License-Identifier: PMPL-1.0-or-later
```

---

## Contact

- **Issues**: [GitHub](https://github.com/hyperpolymath/verisimdb/issues) or [GitLab](https://gitlab.com/hyperpolymath/verisimdb/-/issues)
- **Security**: See [SECURITY.md](SECURITY.md) for vulnerability reporting
- **Maintainer**: Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>
