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
    @if [ -x "/var/mnt/eclipse/repos/panic-attacker/target/release/panic-attack" ]; then \
        /var/mnt/eclipse/repos/panic-attacker/target/release/panic-attack assail . --verbose; \
    else \
        echo "panic-attack not built — run 'cd /var/mnt/eclipse/repos/panic-attacker && cargo build --release'"; \
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
