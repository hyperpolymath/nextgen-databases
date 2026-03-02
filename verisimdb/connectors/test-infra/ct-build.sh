#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VeriSimDB Test Infrastructure — Build Pipeline
#
# Builds all 5 custom container images for the test database stack.
# Unlike the production ct-build.sh, test images are NOT signed
# (--no-sign) and do not require cerro-torre attestations.
#
# The 2 remaining services (mongodb, minio) use upstream Chainguard
# images directly and do not need local builds.
#
# Prerequisites:
#   - podman (container build)
#   - ct (optional — cerro-torre CLI for .ctp bundles)
#
# Usage:
#   ./ct-build.sh                    # Build all test images
#   ./ct-build.sh --parallel         # Build in parallel (faster)
#   ./ct-build.sh --clean            # Remove old test images first
#
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"

# Image name prefix for test images
PREFIX="verisimdb-test"

# Images to build (name:containerfile pairs)
# Ordered by typical build time (fastest first)
IMAGES=(
    "surrealdb:Containerfile.surrealdb"
    "influxdb:Containerfile.influxdb"
    "clickhouse:Containerfile.clickhouse"
    "neo4j:Containerfile.neo4j"
    "redis-stack:Containerfile.redis-stack"
)

PARALLEL=false
CLEAN=false

for arg in "$@"; do
    case "$arg" in
        --parallel) PARALLEL=true ;;
        --clean) CLEAN=true ;;
        --help|-h)
            echo "Usage: $0 [--parallel] [--clean]"
            echo ""
            echo "Options:"
            echo "  --parallel    Build images in parallel (faster, more memory)"
            echo "  --clean       Remove existing test images before building"
            echo ""
            echo "Builds 5 custom images:"
            echo "  ${PREFIX}-surrealdb"
            echo "  ${PREFIX}-influxdb"
            echo "  ${PREFIX}-clickhouse"
            echo "  ${PREFIX}-neo4j"
            echo "  ${PREFIX}-redis-stack"
            exit 0
            ;;
        *)
            echo "Unknown option: ${arg}"
            exit 1
            ;;
    esac
done

echo "=== VeriSimDB Test Infrastructure — Build Pipeline ==="
echo "  Images dir:  ${IMAGES_DIR}"
echo "  Prefix:      ${PREFIX}"
echo "  Parallel:    ${PARALLEL}"
echo "  Clean:       ${CLEAN}"
echo "  Images:      ${#IMAGES[@]}"
echo ""

# ---------------------------------------------------------------------------
# Step 0: Clean (optional)
# ---------------------------------------------------------------------------

if [ "$CLEAN" = true ]; then
    echo "--- Step 0: Cleaning existing test images ---"
    for entry in "${IMAGES[@]}"; do
        name="${entry%%:*}"
        podman rmi "${PREFIX}-${name}:latest" 2>/dev/null || true
        echo "  Removed: ${PREFIX}-${name}:latest (if it existed)"
    done
    echo ""
fi

# ---------------------------------------------------------------------------
# Step 1: Build custom images
# ---------------------------------------------------------------------------

echo "--- Step 1: Building ${#IMAGES[@]} custom images ---"

build_image() {
    local name="$1"
    local containerfile="$2"
    local full_name="${PREFIX}-${name}:latest"

    echo "  Building ${full_name} from ${containerfile}..."

    podman build \
        --no-cache=false \
        -t "${full_name}" \
        -f "${IMAGES_DIR}/${containerfile}" \
        "${IMAGES_DIR}"

    echo "  Built: ${full_name}"
}

if [ "$PARALLEL" = true ]; then
    # Build in parallel (requires enough memory for concurrent builds)
    PIDS=()
    for entry in "${IMAGES[@]}"; do
        name="${entry%%:*}"
        containerfile="${entry#*:}"
        build_image "${name}" "${containerfile}" &
        PIDS+=($!)
    done

    # Wait for all builds to complete
    FAILED=0
    for pid in "${PIDS[@]}"; do
        if ! wait "$pid"; then
            FAILED=$((FAILED + 1))
        fi
    done

    if [ "$FAILED" -gt 0 ]; then
        echo "  ERROR: ${FAILED} image build(s) failed."
        exit 1
    fi
else
    # Build sequentially
    for entry in "${IMAGES[@]}"; do
        name="${entry%%:*}"
        containerfile="${entry#*:}"
        build_image "${name}" "${containerfile}"
        echo ""
    done
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Pull upstream images
# ---------------------------------------------------------------------------

echo "--- Step 2: Pulling upstream images ---"

podman pull cgr.dev/chainguard/mongodb:latest
echo "  Pulled: cgr.dev/chainguard/mongodb:latest"

podman pull cgr.dev/chainguard/minio:latest
echo "  Pulled: cgr.dev/chainguard/minio:latest"

echo ""

# ---------------------------------------------------------------------------
# Step 3: Pack as .ctp bundles (optional, --no-sign for test images)
# ---------------------------------------------------------------------------

echo "--- Step 3: Packing .ctp bundles (if cerro-torre available) ---"

if command -v ct &>/dev/null; then
    for entry in "${IMAGES[@]}"; do
        name="${entry%%:*}"
        full_name="${PREFIX}-${name}:latest"
        ctp_file="${SCRIPT_DIR}/${PREFIX}-${name}-latest.ctp"

        ct pack "${full_name}" -o "${ctp_file}" --no-sign
        echo "  Packed (unsigned): ${ctp_file}"
    done
else
    echo "  SKIP: ct not found (install cerro-torre CLI from stapeln/container-stack/cerro-torre)"
    echo "  Images are built and tagged but not packed as .ctp bundles."
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4: Verify images
# ---------------------------------------------------------------------------

echo "--- Step 4: Listing built images ---"

echo ""
echo "  Custom images:"
for entry in "${IMAGES[@]}"; do
    name="${entry%%:*}"
    podman image inspect "${PREFIX}-${name}:latest" --format '    {{.Id | printf "%.12s"}}  {{.Size | printf "%10d"}}  {{index .RepoTags 0}}' 2>/dev/null \
        || echo "    MISSING: ${PREFIX}-${name}:latest"
done

echo ""
echo "  Upstream images:"
podman image inspect cgr.dev/chainguard/mongodb:latest --format '    {{.Id | printf "%.12s"}}  {{.Size | printf "%10d"}}  {{index .RepoTags 0}}' 2>/dev/null \
    || echo "    MISSING: cgr.dev/chainguard/mongodb:latest"
podman image inspect cgr.dev/chainguard/minio:latest --format '    {{.Id | printf "%.12s"}}  {{.Size | printf "%10d"}}  {{index .RepoTags 0}}' 2>/dev/null \
    || echo "    MISSING: cgr.dev/chainguard/minio:latest"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "=== Build pipeline complete ==="
echo ""
echo "  To start the test stack:"
echo "    cd ${SCRIPT_DIR}"
echo "    selur-compose up --detach      # or: podman-compose up --detach"
echo ""
echo "  To seed test data:"
echo "    ./seed/redis-init.sh"
echo "    ./seed/influxdb-init.sh"
echo "    ./seed/minio-init.sh"
echo "    cat ./seed/neo4j-init.cypher | cypher-shell -a bolt://localhost:7687"
echo "    clickhouse-client --multiquery < ./seed/clickhouse-init.sql"
echo "    cat ./seed/surrealdb-init.surql | surreal sql --endpoint http://localhost:8000 --ns verisimdb --db test"
echo ""
echo "  MongoDB seeds automatically via /docker-entrypoint-initdb.d/init.js"
