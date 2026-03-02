#!/bin/sh
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VeriSimDB Test Infrastructure — MinIO (S3) Seed Script
#
# Creates the verisimdb-objects bucket and uploads test objects including
# sample binary blobs and JSON metadata files. MinIO provides S3-compatible
# object storage for the object storage federation adapter.
#
# Prerequisites:
#   - MinIO container running (API on port 9002, console on port 9001)
#   - mc (MinIO client) available in PATH
#
# Usage:
#   ./minio-init.sh                       # Default: localhost:9002
#   MINIO_HOST=http://minio:9000 MINIO_USER=admin MINIO_PASS=secret ./minio-init.sh
#
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

set -eu

MINIO_HOST="${MINIO_HOST:-http://localhost:9002}"
MINIO_USER="${MINIO_USER:-verisim}"
MINIO_PASS="${MINIO_PASS:-verisim-test-password}"
MINIO_ALIAS="verisim-test"

echo "=== VeriSimDB MinIO (S3) Seed ==="
echo "  Host: ${MINIO_HOST}"
echo "  User: ${MINIO_USER}"

# ---------------------------------------------------------------------------
# Wait for MinIO to be ready
# ---------------------------------------------------------------------------

echo "--- Waiting for MinIO..."
for attempt in $(seq 1 30); do
    if curl -sf "${MINIO_HOST}/minio/health/live" >/dev/null 2>&1; then
        echo "  MinIO is ready."
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "  ERROR: MinIO did not become ready within 30 seconds."
        exit 1
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# Configure mc alias
# ---------------------------------------------------------------------------

echo "--- Configuring MinIO client alias..."

mc alias set "${MINIO_ALIAS}" "${MINIO_HOST}" "${MINIO_USER}" "${MINIO_PASS}" --api S3v4 \
    2>/dev/null || true

echo "  Alias '${MINIO_ALIAS}' configured."

# ---------------------------------------------------------------------------
# Create buckets
# ---------------------------------------------------------------------------

echo "--- Creating buckets..."

mc mb "${MINIO_ALIAS}/verisimdb-objects" 2>/dev/null || echo "  Bucket 'verisimdb-objects' already exists (OK)"
mc mb "${MINIO_ALIAS}/verisimdb-backups" 2>/dev/null || echo "  Bucket 'verisimdb-backups' already exists (OK)"
mc mb "${MINIO_ALIAS}/verisimdb-embeddings" 2>/dev/null || echo "  Bucket 'verisimdb-embeddings' already exists (OK)"

echo "  Buckets: verisimdb-objects, verisimdb-backups, verisimdb-embeddings"

# ---------------------------------------------------------------------------
# Create temporary directory for test objects
# ---------------------------------------------------------------------------

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# ---------------------------------------------------------------------------
# Generate and upload test objects
# ---------------------------------------------------------------------------

echo "--- Uploading test objects..."

# Hexad metadata (JSON documents)
cat > "${TMPDIR}/hexad-test-001.json" <<'ENDJSON'
{
    "id": "hexad-test-001",
    "title": "Introduction to Cross-Modal Consistency",
    "entity_type": "Article",
    "version": 3,
    "modality_count": 6,
    "storage_class": "STANDARD",
    "created_at": "2026-02-27T00:00:00Z",
    "updated_at": "2026-02-28T00:00:00Z",
    "object_refs": {
        "document": "hexads/hexad-test-001/document.txt",
        "embedding": "embeddings/hexad-test-001.bin",
        "provenance": "hexads/hexad-test-001/provenance.cbor"
    }
}
ENDJSON

cat > "${TMPDIR}/hexad-test-002.json" <<'ENDJSON'
{
    "id": "hexad-test-002",
    "title": "Drift Detection Algorithms",
    "entity_type": "TechArticle",
    "version": 1,
    "modality_count": 3,
    "storage_class": "STANDARD",
    "created_at": "2026-02-27T00:00:00Z",
    "updated_at": "2026-02-27T23:00:00Z",
    "object_refs": {
        "document": "hexads/hexad-test-002/document.txt",
        "embedding": "embeddings/hexad-test-002.bin"
    }
}
ENDJSON

# Upload hexad metadata
mc cp "${TMPDIR}/hexad-test-001.json" "${MINIO_ALIAS}/verisimdb-objects/hexads/hexad-test-001/metadata.json"
mc cp "${TMPDIR}/hexad-test-002.json" "${MINIO_ALIAS}/verisimdb-objects/hexads/hexad-test-002/metadata.json"

echo "  Uploaded 2 hexad metadata JSON files."

# Document modality content (plain text)
printf '%s' "VeriSimDB maintains consistency across 8 modality representations. Each entity exists simultaneously as graph, vector, tensor, semantic, document, temporal, provenance, and spatial data." \
    > "${TMPDIR}/document-001.txt"

printf '%s' "Drift is measured as divergence between modalities using cosine similarity for vectors, Jaccard distance for sets, and temporal decay functions for time-series data." \
    > "${TMPDIR}/document-002.txt"

mc cp "${TMPDIR}/document-001.txt" "${MINIO_ALIAS}/verisimdb-objects/hexads/hexad-test-001/document.txt"
mc cp "${TMPDIR}/document-002.txt" "${MINIO_ALIAS}/verisimdb-objects/hexads/hexad-test-002/document.txt"

echo "  Uploaded 2 document content files."

# Binary embedding blobs (simulated — 128 floats = 512 bytes each)
dd if=/dev/urandom bs=512 count=1 2>/dev/null > "${TMPDIR}/embedding-001.bin"
dd if=/dev/urandom bs=512 count=1 2>/dev/null > "${TMPDIR}/embedding-002.bin"

mc cp "${TMPDIR}/embedding-001.bin" "${MINIO_ALIAS}/verisimdb-embeddings/hexad-test-001.bin"
mc cp "${TMPDIR}/embedding-002.bin" "${MINIO_ALIAS}/verisimdb-embeddings/hexad-test-002.bin"

echo "  Uploaded 2 embedding binary blobs (512 bytes each)."

# Provenance CBOR placeholder (just a marker file for testing)
printf '{"_note": "CBOR placeholder for testing", "chain_length": 2, "hash": "sha256:a1b2c3d4e5f6"}' \
    > "${TMPDIR}/provenance-001.json"

mc cp "${TMPDIR}/provenance-001.json" "${MINIO_ALIAS}/verisimdb-objects/hexads/hexad-test-001/provenance.cbor"

echo "  Uploaded 1 provenance placeholder."

# Backup snapshot (simulated)
printf '{"snapshot_id": "snap-test-001", "timestamp": "2026-02-28T00:00:00Z", "hexad_count": 3, "size_bytes": 4096}' \
    > "${TMPDIR}/snapshot-meta.json"

mc cp "${TMPDIR}/snapshot-meta.json" "${MINIO_ALIAS}/verisimdb-backups/snapshots/snap-test-001/metadata.json"

echo "  Uploaded 1 backup snapshot metadata."

# ---------------------------------------------------------------------------
# Set bucket policies (read-only public access for objects bucket)
# ---------------------------------------------------------------------------

echo "--- Setting bucket policies..."

# Allow anonymous read on objects bucket (for test convenience)
mc anonymous set download "${MINIO_ALIAS}/verisimdb-objects" 2>/dev/null \
    || echo "  Could not set anonymous policy (OK for testing)"

echo "  Policies configured."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== MinIO seed complete ==="
echo "  Buckets:   verisimdb-objects, verisimdb-backups, verisimdb-embeddings"
echo "  Objects:   8 total"
echo "    - 2 hexad metadata JSON"
echo "    - 2 document content TXT"
echo "    - 2 embedding binaries"
echo "    - 1 provenance placeholder"
echo "    - 1 backup snapshot metadata"
echo ""
echo "  Verify with:"
echo "    mc ls ${MINIO_ALIAS}/verisimdb-objects/ --recursive"
echo "    mc cat ${MINIO_ALIAS}/verisimdb-objects/hexads/hexad-test-001/metadata.json"
echo ""
echo "  Console: ${MINIO_HOST%:*}:9001 (user: ${MINIO_USER})"
