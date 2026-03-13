# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 hyperpolymath
#
# GQLdt Development Container
# Lean 4 + Zig + Build Tools

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="GQLdt Development Environment"
LABEL org.opencontainers.image.description="Lean 4 + Zig for dependently-typed Lith queries"
LABEL org.opencontainers.image.authors="Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>"
LABEL org.opencontainers.image.licenses="PMPL-1.0-or-later"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    cmake \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install elan (Lean version manager)
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf \
    | sh -s -- -y --default-toolchain leanprover/lean4:v4.15.0

ENV PATH="/root/.elan/bin:${PATH}"

# Install Zig
RUN wget -q https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz \
    && tar -xf zig-linux-x86_64-0.13.0.tar.xz \
    && mv zig-linux-x86_64-0.13.0 /usr/local/zig \
    && ln -s /usr/local/zig/zig /usr/local/bin/zig \
    && rm zig-linux-x86_64-0.13.0.tar.xz

# Verify installations
RUN lean --version && lake --version && zig version

# Set working directory
WORKDIR /workspace

# Copy project files
COPY . /workspace/

# Build Lean 4 project (download dependencies)
RUN lake build || echo "Build failed - dependencies may need to be fetched first"

# Build Zig FFI bridge
WORKDIR /workspace/bridge/zig
RUN zig build || echo "Zig build failed - may need project setup"

# Return to workspace root
WORKDIR /workspace

# Default command: interactive shell
CMD ["/bin/bash"]
