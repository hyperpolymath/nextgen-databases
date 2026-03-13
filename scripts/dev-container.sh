#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 hyperpolymath
#
# Quick development container launcher

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT"

echo "=== FBQLdt Development Container ==="
echo ""

# Check if Docker or Podman is available
if command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
else
    echo "❌ Error: Neither Docker nor Podman found"
    echo "Install one of:"
    echo "  - Docker: https://docs.docker.com/get-docker/"
    echo "  - Podman: https://podman.io/getting-started/installation"
    exit 1
fi

echo "Using: $CONTAINER_CMD"
echo ""

# Build image
echo "Building image..."
$CONTAINER_CMD build -t fbqldt:dev .

# Run container
echo ""
echo "Starting development container..."
$CONTAINER_CMD run -it --rm \
    -v "$REPO_ROOT:/workspace" \
    fbqldt:dev

echo ""
echo "Container exited"
