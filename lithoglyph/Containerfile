# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Lithoglyph Lith — Container build
# Base: Chainguard wolfi (NEVER debian/ubuntu)
#
# Build with: podman build -t lithoglyph-lith -f Containerfile .
# Run with:   podman run -p 8080:8080 lithoglyph-lith
#
# Multi-stage build: wolfi-base for compilation, static for minimal runtime.

# =============================================================================
# Stage 1: Build — install Zig, compile core-zig bridge and demo-server
# =============================================================================
FROM cgr.dev/chainguard/wolfi-base:latest AS builder

# Install build dependencies
RUN apk add --no-cache \
    curl \
    xz \
    tar \
    glibc-dev

# Install Zig 0.15.2
RUN curl -L https://ziglang.org/download/0.15.2/zig-linux-x86_64-0.15.2.tar.xz | tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-linux-x86_64-0.15.2/zig /usr/local/bin/zig

WORKDIR /build

# Copy source files
COPY core-zig/ /build/core-zig/
COPY demo-server.zig /build/

# Build core-zig using the build system (produces static + shared libs)
WORKDIR /build/core-zig
RUN zig build -Doptimize=ReleaseFast

# Also build standalone shared library for FFI consumers
RUN zig build-lib src/bridge.zig -dynamic -lc -O ReleaseFast

# Build demo-server (the API binary)
WORKDIR /build
RUN zig build-exe demo-server.zig -lc -O ReleaseFast

# =============================================================================
# Stage 2: Runtime — minimal static image with only the binary
# =============================================================================
FROM cgr.dev/chainguard/static:latest

WORKDIR /app

# Copy only the compiled binary and shared library from builder
COPY --from=builder /build/demo-server /app/
COPY --from=builder /build/core-zig/libbridge.so /app/

# Set library path so the binary can find libbridge.so
ENV LD_LIBRARY_PATH=/app

# Auth token must be provided at runtime via environment variable.
# Example: podman run -e LITHOGLYPH_AUTH_TOKEN=<token> ...
# See api/src/auth.zig for details.
# ENV LITHOGLYPH_AUTH_TOKEN=  (intentionally not set — must be provided)

# Expose API port
EXPOSE 8080

# Run server as the default entrypoint
ENTRYPOINT ["/app/demo-server"]
