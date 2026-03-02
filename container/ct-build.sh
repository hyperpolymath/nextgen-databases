#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VeriSimDB — Cerro Torre build, sign, and verify pipeline
#
# Builds the container image, packages it as a verified .ctp bundle,
# signs it with Ed25519, and verifies the result.
#
# Prerequisites:
#   - podman (container build)
#   - ct (cerro-torre CLI: pack, sign, verify)
#   - cerro-sign (Ed25519 signing, from stapeln/container-stack/cerro-torre)
#
# Usage:
#   ./ct-build.sh                           # Build + sign (in-memory)
#   ./ct-build.sh persistent                # Build + sign (persistent storage)
#   ./ct-build.sh persistent --push         # Build + sign + push to registry
#   CT_KEY_ID=my-key ./ct-build.sh          # Use specific signing key
#
# Environment variables:
#   CT_KEY_ID       — Signing key identifier (default: verisimdb-release)
#   CT_REGISTRY     — OCI registry to push to (default: ghcr.io/hyperpolymath)
#   CT_TAG          — Image tag (default: latest)
#   FEATURES        — Cargo feature flags (default: "" or "persistent")

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FEATURES="${1:-}"
PUSH="${2:-}"
CT_KEY_ID="${CT_KEY_ID:-verisimdb-release}"
CT_REGISTRY="${CT_REGISTRY:-ghcr.io/hyperpolymath}"
CT_TAG="${CT_TAG:-latest}"

IMAGE_NAME="verisimdb"
if [ "$FEATURES" = "persistent" ]; then
    IMAGE_NAME="verisimdb-persistent"
fi

FULL_IMAGE="${CT_REGISTRY}/${IMAGE_NAME}:${CT_TAG}"
CTP_FILE="${SCRIPT_DIR}/${IMAGE_NAME}-${CT_TAG}.ctp"

echo "=== VeriSimDB Cerro Torre Build Pipeline ==="
echo "  Image:    ${FULL_IMAGE}"
echo "  Features: ${FEATURES:-none (in-memory)}"
echo "  Key:      ${CT_KEY_ID}"
echo "  Bundle:   ${CTP_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Build container image with Podman
# ---------------------------------------------------------------------------

echo "--- Step 1: Building container image ---"

BUILD_ARGS=()
if [ -n "$FEATURES" ]; then
    BUILD_ARGS+=(--build-arg "FEATURES=${FEATURES}")
fi

podman build \
    -t "${FULL_IMAGE}" \
    "${BUILD_ARGS[@]}" \
    -f "${SCRIPT_DIR}/Containerfile" \
    "${REPO_ROOT}"

echo "  Built: ${FULL_IMAGE}"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Pack into .ctp bundle
# ---------------------------------------------------------------------------

echo "--- Step 2: Packing into .ctp bundle ---"

if command -v ct &>/dev/null; then
    ct pack "${FULL_IMAGE}" -o "${CTP_FILE}"
    echo "  Packed: ${CTP_FILE}"
else
    echo "  SKIP: ct not found (install cerro-torre CLI from stapeln/container-stack/cerro-torre)"
    echo "  The container image is built and tagged but not packed as a .ctp bundle."
    echo "  To pack manually: ct pack ${FULL_IMAGE} -o ${CTP_FILE}"
    echo ""
    echo "=== Build complete (without .ctp signing) ==="
    exit 0
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Sign the .ctp bundle
# ---------------------------------------------------------------------------

echo "--- Step 3: Signing .ctp bundle ---"

if command -v cerro-sign &>/dev/null; then
    cerro-sign sign "${CTP_FILE}" --key-id "${CT_KEY_ID}"
    echo "  Signed: ${CTP_FILE} (key: ${CT_KEY_ID})"
elif command -v ct &>/dev/null; then
    ct sign "${CTP_FILE}" --key "${CT_KEY_ID}"
    echo "  Signed: ${CTP_FILE} (key: ${CT_KEY_ID})"
else
    echo "  SKIP: cerro-sign not found (install from stapeln/container-stack/cerro-torre)"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4: Verify the .ctp bundle
# ---------------------------------------------------------------------------

echo "--- Step 4: Verifying .ctp bundle ---"

if command -v ct &>/dev/null; then
    ct verify "${CTP_FILE}"
    echo "  Verified: ${CTP_FILE}"
else
    echo "  SKIP: ct not found"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 5: Push to registry (optional)
# ---------------------------------------------------------------------------

if [ "$PUSH" = "--push" ]; then
    echo "--- Step 5: Pushing to registry ---"

    if command -v ct &>/dev/null; then
        ct push "${CTP_FILE}" "${FULL_IMAGE}"
        echo "  Pushed: ${FULL_IMAGE}"
    else
        # Fall back to podman push (unsigned OCI image)
        echo "  ct not available, falling back to podman push (unsigned)"
        podman push "${FULL_IMAGE}"
        echo "  Pushed: ${FULL_IMAGE} (unsigned OCI — not a .ctp bundle)"
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "=== Build pipeline complete ==="
echo "  Image:  ${FULL_IMAGE}"
echo "  Bundle: ${CTP_FILE}"
echo ""
echo "  To deploy with selur-compose:"
echo "    cd container && selur-compose up"
echo ""
echo "  To verify at any time:"
echo "    ct verify ${CTP_FILE}"
echo ""
echo "  To explain the verification chain:"
echo "    ct explain ${CTP_FILE}"
