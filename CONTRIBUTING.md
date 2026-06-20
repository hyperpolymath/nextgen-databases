# Clone the repository
git clone https://github.com/hyperpolymath/nextgen-databases.git
cd nextgen-databases

# Using Nix (recommended for reproducibility)
nix develop

# Or using toolbox/distrobox
toolbox create nextgen-databases-dev
toolbox enter nextgen-databases-dev
# Install dependencies manually

# Verify setup
just check   # or: cargo check / mix compile / etc.
just test    # Run test suite
```

### Repository Structure

`nextgen-databases` is a **coordination repo** — it does not hold database
implementations. Each database and query language has its own repo (see `REGISTRY.adoc`).

```
nextgen-databases/
├── README.adoc / EXPLAINME.adoc / TOPOLOGY.md / ROADMAP.adoc  # Portfolio docs
├── REGISTRY.adoc        # Authoritative map: database/language -> its own repo
├── CLAUDE.md / AGENTS.md / 0-AI-MANIFEST.a2ml                 # Agent guardrails
├── docs/                # Coordination docs (incl. migration runbooks)
├── tests/               # CROSS-database integration tests only
├── .machine_readable/   # Canonical SCM metadata
├── .github/             # CI/CD, issue templates, governance
├── .well-known/ LICENSES/
└── flake.nix / Justfile / stapeln.toml / opsm.toml           # Shared env & orchestration
```

#### What belongs here vs. in a database repo

- ✅ **Here**: portfolio docs, the registry, cross-database integration tests, shared
  infrastructure/orchestration, governance and machine-readable metadata.
- ❌ **Not here — use the database's own repo**: per-database source code, schemas,
  migrations, storage engines, query-language implementations, per-database design docs,
  whitepapers, benchmarks, and datasets. See `REGISTRY.adoc` for the destination repo.

A CI guard (`.github/workflows/placement-guard.yml`) and a local pre-write hook
(`.claude/hooks/block-db-writes.sh`) enforce this.

---

## How to Contribute

### Reporting Bugs

**Before reporting**:
1. Search existing issues
2. Check if it's already fixed in `main`
3. Determine which perimeter the bug affects

**When reporting**:

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) and include:

- Clear, descriptive title
- Environment details (OS, versions, toolchain)
- Steps to reproduce
- Expected vs actual behaviour
- Logs, screenshots, or minimal reproduction

### Suggesting Features

**Before suggesting**:
1. Check the [roadmap](ROADMAP.md) if available
2. Search existing issues and discussions
3. Consider which perimeter the feature belongs to

**When suggesting**:

Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md) and include:

- Problem statement (what pain point does this solve?)
- Proposed solution
- Alternatives considered
- Which perimeter this affects

### Your First Contribution

Look for issues labelled:

- [`good first issue`](https://github.com/hyperpolymath/nextgen-databases/labels/good%20first%20issue) — Simple Perimeter 3 tasks
- [`help wanted`](https://github.com/hyperpolymath/nextgen-databases/labels/help%20wanted) — Community help needed
- [`documentation`](https://github.com/hyperpolymath/nextgen-databases/labels/documentation) — Docs improvements
- [`perimeter-3`](https://github.com/hyperpolymath/nextgen-databases/labels/perimeter-3) — Community sandbox scope

---

## Development Workflow

### Branch Naming
```
docs/short-description       # Documentation (P3)
test/what-added              # Test additions (P3)
feat/short-description       # New features (P2)
fix/issue-number-description # Bug fixes (P2)
refactor/what-changed        # Code improvements (P2)
security/what-fixed          # Security fixes (P1-2)
```

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):
```
<type>(<scope>): <description>

[optional body]

[optional footer]
