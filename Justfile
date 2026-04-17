# SPDX-License-Identifier: PMPL-1.0-or-later
# Glyphbase - Build Commands

# Default recipe
default:
    @just --list

# Development - run both UI and server
dev:
    @echo "Starting Glyphbase development servers..."
    @just dev-server &
    @just dev-ui

# UI development server
dev-ui:
    cd ui && deno task dev

# Server development
dev-server:
    cd server && gleam run

# Build everything
build:
    @just build-ui
    @just build-server

# Build UI
build-ui:
    cd ui && deno task build

# Build server
build-server:
    cd server && gleam build

# Run all tests
test:
    @just test-ui
    @just test-server

# UI tests
test-ui:
    cd ui && deno task test

# Server tests
test-server:
    cd server && gleam test

# Format all code
fmt:
    cd ui && deno task fmt
    cd server && gleam format

# Lint all code
lint:
    cd ui && deno task lint

# Clean build artifacts
clean:
    rm -rf ui/dist
    rm -rf server/build

# Docker build
docker-build:
    podman build -t glyphbase:latest .

# Docker run
docker-run:
    podman run -p 4000:4000 -v ./data:/data glyphbase:latest

# Full docker-compose stack
up:
    podman-compose up

# Stop docker-compose stack
down:
    podman-compose down
