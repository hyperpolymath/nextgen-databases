#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 hyperpolymath
#
# Build FBQLdt container using svalinn/vordr/cerro-torre/selur

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT"

echo "=== FBQLdt Container Build (Chainguard-based) ==="
echo ""

# Detect container builder
if command -v buildah &> /dev/null; then
    BUILDER="buildah"
    echo "Using: Buildah"
elif command -v podman &> /dev/null; then
    BUILDER="podman"
    echo "Using: Podman"
elif command -v docker &> /dev/null; then
    BUILDER="docker"
    echo "Using: Docker"
else
    echo "❌ Error: No container builder found (buildah/podman/docker)"
    exit 1
fi

# Image tags
IMAGE_NAME="fbqldt"
IMAGE_TAG="${IMAGE_TAG:-dev}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building: $FULL_IMAGE"
echo ""

# Build with security labels for svalinn/vordr
if [ "$BUILDER" = "buildah" ]; then
    buildah bud \
        --file Containerfile \
        --tag "$FULL_IMAGE" \
        --label "io.hyperpolymath.security.scanned=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --label "io.hyperpolymath.container.system=svalinn" \
        --squash \
        .
elif [ "$BUILDER" = "podman" ]; then
    podman build \
        --file Containerfile \
        --tag "$FULL_IMAGE" \
        --label "io.hyperpolymath.security.scanned=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --label "io.hyperpolymath.container.system=svalinn" \
        --squash \
        .
else
    docker build \
        --file Containerfile \
        --tag "$FULL_IMAGE" \
        --label "io.hyperpolymath.security.scanned=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        .
fi

echo ""
echo "✅ Build complete: $FULL_IMAGE"
echo ""
echo "Run with:"
echo "  $BUILDER run -it --rm -v \$(pwd):/workspace $FULL_IMAGE"
echo ""
echo "Or use svalinn/vordr orchestration for production deployment"
