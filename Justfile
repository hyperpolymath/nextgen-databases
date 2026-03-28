# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# justfile — VeriSimDB
# Run with: just <recipe>

set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe: show help
default:
    @just --list

# ── Build ──────────────────────────────────────────────────────

# Build Rust core (release)
build:
    OPENSSL_NO_VENDOR=1 cargo build --release

# Build Rust core (debug)
build-dev:
    OPENSSL_NO_VENDOR=1 cargo build

# Build Elixir orchestration layer
build-elixir:
    cd elixir-orchestration && mix deps.get && mix compile

# Build everything (Rust + Elixir)
build-all: build build-elixir

# Compile Idris2 ABI definitions
build-abi:
    cd src/abi && idris2 --build hypatia-abi.ipkg

# Build Zig FFI bridge
build-ffi:
    cd ffi/zig && zig build

# ── Test ───────────────────────────────────────────────────────

# Run Rust tests
test:
    OPENSSL_NO_VENDOR=1 cargo test

# Run Elixir tests
test-elixir:
    cd elixir-orchestration && mix test

# Run Rust integration tests
test-integration:
    OPENSSL_NO_VENDOR=1 cargo test --test integration

# Run all tests (Rust + Elixir)
test-all: test test-elixir

# ── Lint & Format ──────────────────────────────────────────────

# Format all Rust code
fmt:
    cargo fmt

# Run clippy lints
lint:
    cargo clippy -- -D warnings

# Format Elixir code
fmt-elixir:
    cd elixir-orchestration && mix format

# ── Run ────────────────────────────────────────────────────────

# Run verisimdb API server (dev mode)
serve:
    RUST_LOG=debug cargo run -p verisim-api

# Run Elixir OTP orchestrator
serve-otp:
    cd elixir-orchestration && MIX_ENV=dev mix run --no-halt

# ── Container ──────────────────────────────────────────────────

# Build container image with Podman
container-build:
    podman build -t verisimdb:latest -f container/Containerfile .

# Run container locally
container-run:
    podman run --rm -p 8080:8080 verisimdb:latest

# Build with stapeln layers
stapeln-build:
    @if command -v stapeln &>/dev/null; then \
        stapeln build --config stapeln.toml --target production; \
    else \
        echo "stapeln not found — falling back to podman build"; \
        just container-build; \
    fi

# Deploy full stack with selur
deploy:
    @if command -v selur &>/dev/null; then \
        selur seal && podman-compose -f selur-compose.yml up -d; \
    else \
        echo "selur not found — using podman-compose directly"; \
        podman-compose -f selur-compose.yml up -d; \
    fi

# Stop deployed stack
deploy-stop:
    podman-compose -f selur-compose.yml down

# Sign container with cerro-torre
container-sign:
    @if command -v cerro-torre &>/dev/null; then \
        cerro-torre sign verisimdb:latest --algorithm ML-DSA-87; \
    else \
        echo "cerro-torre not found — skipping image signing"; \
    fi

# ── Security ───────────────────────────────────────────────────

# Run panic-attack static analysis
panic-scan:
    @if [ -x "/var$REPOS_DIR/panic-attacker/target/release/panic-attack" ]; then \
        /var$REPOS_DIR/panic-attacker/target/release/panic-attack assail . --verbose; \
    else \
        echo "panic-attack not built — run 'cd /var$REPOS_DIR/panic-attacker && cargo build --release'"; \
    fi

# Run hypatia neurosymbolic scan
hypatia-scan:
    @if command -v hypatia-v2 &>/dev/null; then \
        hypatia-v2 . --severity=critical --severity=high; \
    else \
        echo "hypatia-v2 not found — run via CI workflow instead"; \
    fi

# Run vordr runtime verification
vordr-verify:
    @if command -v vordr &>/dev/null; then \
        vordr verify --target localhost:8080 --policy strict; \
    else \
        echo "vordr not found — skipping runtime verification"; \
    fi

# Check license compliance
license-check:
    @echo "Checking for banned AGPL-3.0 headers..."
    @if grep -rl "AGPL-3.0" --include='*.rs' --include='*.ex' --include='*.exs' --include='*.idr' --include='*.zig' --include='*.yml' . 2>/dev/null; then \
        echo "FAIL: Found AGPL-3.0 headers"; \
        exit 1; \
    else \
        echo "PASS: No AGPL-3.0 headers found"; \
    fi

# Validate SCM files are in .machine_readable/ only
check-scm:
    @for f in STATE.scm META.scm ECOSYSTEM.scm; do \
        if [ -f "$$f" ]; then \
            echo "ERROR: $$f found in root"; exit 1; \
        fi; \
    done
    @echo "PASS: No SCM files in root"

# ── Clean ──────────────────────────────────────────────────────

# Clean all build artifacts
clean:
    cargo clean
    cd elixir-orchestration && mix clean 2>/dev/null || true
    @echo "Cleaned."

# Run panic-attacker pre-commit scan
assail:
    @command -v panic-attack >/dev/null 2>&1 && panic-attack assail . || echo "panic-attack not found — install from https://github.com/hyperpolymath/panic-attacker"

# ── Onboarding ────────────────────────────────────────────────

# Check all required tools are installed
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    ok=0; fail=0
    check() {
        if "$@" >/dev/null 2>&1; then
            echo "  [ok] $1"
            ((ok++))
        else
            echo "  [MISSING] $1 — $2"
            ((fail++))
        fi
    }
    echo "=== VeriSimDB Doctor ==="
    check rustc --version "install via asdf: asdf install rust nightly"
    check cargo --version "comes with Rust"
    check rustup --version "https://rustup.rs"
    check pkg-config --version "sudo dnf install pkg-config"
    if pkg-config --exists openssl 2>/dev/null; then
        echo "  [ok] openssl-devel (pkg-config)"
        ((ok++))
    else
        echo "  [MISSING] openssl-devel — sudo dnf install openssl-devel"
        ((fail++))
    fi
    check elixir --version "asdf install elixir 1.17.3-otp-27"
    check mix --version "comes with Elixir"
    check erl -version "asdf install erlang 27.2"
    check zig version "asdf install zig 0.14.0"
    check just --version "cargo install just"
    check podman --version "sudo dnf install podman (optional, for containers)"
    if command -v idris2 >/dev/null 2>&1; then
        echo "  [ok] idris2 (optional — ABI layer)"
        ((ok++))
    else
        echo "  [info] idris2 not found (optional — only for ABI definitions)"
    fi
    echo ""
    echo "Result: $ok passed, $fail failed"
    if [ "$fail" -gt 0 ]; then
        echo "Fix the MISSING items above, then re-run: just doctor"
        exit 1
    else
        echo "All prerequisites satisfied."
    fi

# Auto-install missing tools where possible
heal:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== VeriSimDB Heal ==="
    if ! command -v rustc &>/dev/null; then
        echo "Installing Rust via asdf..."
        asdf install rust nightly || echo "Try: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    fi
    if ! command -v just &>/dev/null; then
        echo "Installing just..."
        cargo install just
    fi
    if ! command -v elixir &>/dev/null; then
        echo "Installing Elixir via asdf..."
        asdf install elixir 1.17.3-otp-27 || echo "Try: asdf plugin add elixir && asdf install elixir 1.17.3-otp-27"
    fi
    if ! command -v zig &>/dev/null; then
        echo "Installing Zig via asdf..."
        asdf install zig 0.14.0 || echo "Try: asdf plugin add zig && asdf install zig 0.14.0"
    fi
    if ! pkg-config --exists openssl 2>/dev/null; then
        echo "openssl-devel missing — run: sudo dnf install openssl-devel"
    fi
    if ! command -v podman &>/dev/null; then
        echo "Podman missing — run: sudo dnf install podman podman-compose"
    fi
    echo ""
    echo "Re-run 'just doctor' to verify."

# Guided tour of the codebase
tour:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== VeriSimDB Tour ==="
    echo ""
    echo "1. ARCHITECTURE"
    echo "   Rust core (rust-core/) provides 10 modality crates:"
    echo "   graph, vector, tensor, semantic, document, temporal,"
    echo "   provenance, spatial, octad, drift, normalizer, api"
    echo "   Elixir OTP (elixir-orchestration/) coordinates them."
    echo ""
    echo "2. BUILD & RUN"
    echo "   just build          Build Rust release"
    echo "   just build-elixir   Build Elixir layer"
    echo "   just serve           Start API on :8080"
    echo ""
    echo "3. THE OCTAD"
    echo "   Every entity is stored across 8 modalities simultaneously."
    echo "   Drift between them is detected and self-healed."
    echo ""
    echo "4. QUERY LANGUAGE"
    echo "   VQL (VeriSim Query Language) — NOT SQL."
    echo "   See docs/ and playground/ for examples."
    echo ""
    echo "5. FEDERATION"
    echo "   10 adapters (MongoDB, Redis, Neo4j, ClickHouse, SurrealDB,"
    echo "   SQLite, DuckDB, VectorDB, InfluxDB, ObjectStorage)."
    echo "   6 client SDKs (Rust, V, Elixir, ReScript, Julia, Gleam)."
    echo ""
    echo "6. CONTAINERS"
    echo "   just container-build   Build with Podman"
    echo "   just container-run     Run on :8080"
    echo ""
    echo "7. KEY FILES"
    echo "   Cargo.toml             Workspace definition"
    echo "   elixir-orchestration/  OTP layer"
    echo "   connectors/            Federation + SDKs"
    echo "   container/             Containerfile + compose"
    echo "   .claude/CLAUDE.md      Full AI context"
    echo ""
    echo "Run 'just' to see all available recipes."

# What to do when things go wrong
help-me:
    #!/usr/bin/env bash
    echo "=== VeriSimDB Help ==="
    echo ""
    echo "BUILD FAILS:"
    echo "  'openssl' errors   -> sudo dnf install openssl-devel"
    echo "  'protoc' errors    -> Proto code is pre-generated, check Cargo features"
    echo "  'oxrocksdb' errors -> Eliminated; if seen, run: cargo clean && just build"
    echo "  Elixir errors      -> cd elixir-orchestration && mix deps.get"
    echo ""
    echo "RUNTIME ISSUES:"
    echo "  Port 8080 in use   -> Change port: VERISIM_PORT=8081 just serve"
    echo "  'connection refused'-> Is the Rust API running? just serve"
    echo "  Drift not detected -> Check thresholds in config/config.exs"
    echo ""
    echo "TESTING:"
    echo "  Integration tests need the test-infra stack running:"
    echo "    cd connectors/test-infra && podman-compose up -d"
    echo "  Then: just test-integration"
    echo ""
    echo "STILL STUCK?"
    echo "  1. just doctor     (check prerequisites)"
    echo "  2. just heal       (auto-install what's missing)"
    echo "  3. cargo clean && just build  (fresh build)"
    echo "  4. Read .claude/CLAUDE.md for full context"
