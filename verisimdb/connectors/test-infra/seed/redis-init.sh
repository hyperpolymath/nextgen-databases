#!/bin/sh
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VeriSimDB Test Infrastructure — Redis Stack Seed Script
#
# Creates RediSearch indexes for hexad data, loads RedisJSON documents,
# and creates RedisTimeSeries keys for temporal modality data.
#
# Prerequisites:
#   - Redis Stack container running on localhost:6379
#   - redis-cli available in PATH
#
# Usage:
#   ./redis-init.sh                         # Default: localhost:6379
#   REDIS_HOST=redis REDIS_PORT=6379 ./redis-init.sh
#
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

set -eu

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

CLI="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"

echo "=== VeriSimDB Redis Stack Seed ==="
echo "  Host: ${REDIS_HOST}:${REDIS_PORT}"

# ---------------------------------------------------------------------------
# Wait for Redis to be ready
# ---------------------------------------------------------------------------

echo "--- Waiting for Redis..."
for attempt in $(seq 1 30); do
    if ${CLI} ping 2>/dev/null | grep -q PONG; then
        echo "  Redis is ready."
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "  ERROR: Redis did not become ready within 30 seconds."
        exit 1
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# Create RediSearch indexes
# ---------------------------------------------------------------------------

echo "--- Creating RediSearch indexes..."

# Hexad document search index
# Indexes JSON documents stored at hexad:* keys
${CLI} FT.CREATE idx:hexads ON JSON PREFIX 1 "hexad:" SCHEMA \
    '$.id' AS id TAG SORTABLE \
    '$.modalities[?(@.type=="document")].data.title' AS title TEXT WEIGHT 2.0 \
    '$.modalities[?(@.type=="document")].data.content' AS content TEXT WEIGHT 1.0 \
    '$.modalities[?(@.type=="graph")].data.types[*]' AS entity_type TAG \
    '$.version' AS version NUMERIC SORTABLE \
    '$.created_at' AS created_at NUMERIC SORTABLE \
    '$.updated_at' AS updated_at NUMERIC SORTABLE \
    2>/dev/null || echo "  Index idx:hexads already exists (OK)"

# Drift scores search index
${CLI} FT.CREATE idx:drift ON JSON PREFIX 1 "drift:" SCHEMA \
    '$.hexad_id' AS hexad_id TAG SORTABLE \
    '$.overall' AS overall NUMERIC SORTABLE \
    '$.status' AS status TAG \
    '$.measured_at' AS measured_at NUMERIC SORTABLE \
    2>/dev/null || echo "  Index idx:drift already exists (OK)"

echo "  RediSearch indexes created."

# ---------------------------------------------------------------------------
# Load RedisJSON documents — test hexads
# ---------------------------------------------------------------------------

echo "--- Loading RedisJSON hexad documents..."

NOW=$(date +%s)
ONE_HOUR_AGO=$((NOW - 3600))
ONE_DAY_AGO=$((NOW - 86400))

# Hexad 1: multi-modality entity with document, vector, graph, temporal
${CLI} JSON.SET "hexad:test-001" '$' "$(cat <<ENDJSON
{
    "id": "hexad-test-001",
    "created_at": ${ONE_DAY_AGO},
    "updated_at": ${NOW},
    "version": 3,
    "modalities": [
        {
            "type": "document",
            "data": {
                "title": "Introduction to Cross-Modal Consistency",
                "content": "VeriSimDB maintains consistency across 8 modality representations. Each entity exists simultaneously as graph, vector, tensor, semantic, document, temporal, provenance, and spatial data."
            }
        },
        {
            "type": "vector",
            "data": {
                "embedding": [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
                "model": "test-embedding-v1",
                "dimensions": 8
            }
        },
        {
            "type": "graph",
            "data": {
                "types": ["http://schema.org/Article", "http://verisimdb.org/ontology/Entity"],
                "relationships": [
                    {"predicate": "relates_to", "target": "hexad-test-002", "weight": 0.85}
                ]
            }
        },
        {
            "type": "temporal",
            "data": {
                "valid_from": ${ONE_DAY_AGO},
                "valid_to": null,
                "version_history": [
                    {"version": 1, "timestamp": ${ONE_DAY_AGO}, "action": "created"},
                    {"version": 2, "timestamp": ${ONE_HOUR_AGO}, "action": "updated_vector"},
                    {"version": 3, "timestamp": ${NOW}, "action": "updated_document"}
                ]
            }
        }
    ]
}
ENDJSON
)"

# Hexad 2: drift detection article
${CLI} JSON.SET "hexad:test-002" '$' "$(cat <<ENDJSON
{
    "id": "hexad-test-002",
    "created_at": ${ONE_DAY_AGO},
    "updated_at": ${ONE_HOUR_AGO},
    "version": 1,
    "modalities": [
        {
            "type": "document",
            "data": {
                "title": "Drift Detection Algorithms",
                "content": "Drift is measured as divergence between modalities using cosine similarity for vectors, Jaccard distance for sets, and temporal decay functions for time-series data."
            }
        },
        {
            "type": "vector",
            "data": {
                "embedding": [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2],
                "model": "test-embedding-v1",
                "dimensions": 8
            }
        }
    ]
}
ENDJSON
)"

# Hexad 3: normalisation process
${CLI} JSON.SET "hexad:test-003" '$' "$(cat <<ENDJSON
{
    "id": "hexad-test-003",
    "created_at": ${NOW},
    "updated_at": ${NOW},
    "version": 1,
    "modalities": [
        {
            "type": "document",
            "data": {
                "title": "Self-Normalisation Process",
                "content": "When drift exceeds configurable thresholds, the normaliser identifies the most authoritative modality, regenerates drifted representations, validates consistency, and updates all modalities atomically."
            }
        },
        {
            "type": "semantic",
            "data": {
                "categories": ["normalisation", "consistency", "drift"],
                "confidence": 0.92
            }
        }
    ]
}
ENDJSON
)"

echo "  Loaded 3 hexad JSON documents."

# ---------------------------------------------------------------------------
# Load drift score documents
# ---------------------------------------------------------------------------

echo "--- Loading drift score documents..."

${CLI} JSON.SET "drift:test-001" '$' "$(cat <<ENDJSON
{
    "hexad_id": "hexad-test-001",
    "measured_at": ${NOW},
    "overall": 0.045,
    "status": "healthy",
    "scores": {
        "semantic_vector_drift": 0.12,
        "graph_document_drift": 0.05,
        "temporal_consistency_drift": 0.02,
        "tensor_drift": 0.0,
        "schema_drift": 0.0,
        "quality_drift": 0.08
    }
}
ENDJSON
)"

${CLI} JSON.SET "drift:test-002" '$' "$(cat <<ENDJSON
{
    "hexad_id": "hexad-test-002",
    "measured_at": ${NOW},
    "overall": 0.213,
    "status": "drifted",
    "scores": {
        "semantic_vector_drift": 0.45,
        "graph_document_drift": 0.32,
        "temporal_consistency_drift": 0.15,
        "tensor_drift": 0.0,
        "schema_drift": 0.08,
        "quality_drift": 0.28
    }
}
ENDJSON
)"

echo "  Loaded 2 drift score documents."

# ---------------------------------------------------------------------------
# Create RedisTimeSeries keys for temporal data
# ---------------------------------------------------------------------------

echo "--- Creating RedisTimeSeries keys..."

# Drift score time-series for hexad-test-001
${CLI} TS.CREATE "ts:drift:test-001:overall" \
    RETENTION 86400000 \
    LABELS hexad_id hexad-test-001 metric overall \
    2>/dev/null || echo "  ts:drift:test-001:overall already exists (OK)"

${CLI} TS.CREATE "ts:drift:test-001:semantic_vector" \
    RETENTION 86400000 \
    LABELS hexad_id hexad-test-001 metric semantic_vector_drift \
    2>/dev/null || echo "  ts:drift:test-001:semantic_vector already exists (OK)"

# Add sample data points (timestamps in milliseconds)
NOW_MS=$((NOW * 1000))
for offset in 0 300 600 900 1200 1500 1800; do
    TS=$((NOW_MS - offset * 1000))
    # Simulate gradually increasing drift
    DRIFT_VAL=$(echo "scale=3; 0.01 + ${offset} * 0.00002" | bc 2>/dev/null || echo "0.045")
    ${CLI} TS.ADD "ts:drift:test-001:overall" "${TS}" "${DRIFT_VAL}" 2>/dev/null || true
done

# Query latency time-series
${CLI} TS.CREATE "ts:query:latency_ms" \
    RETENTION 86400000 \
    LABELS service verisimdb metric query_latency_ms \
    2>/dev/null || echo "  ts:query:latency_ms already exists (OK)"

for offset in 0 60 120 180 240 300; do
    TS=$((NOW_MS - offset * 1000))
    ${CLI} TS.ADD "ts:query:latency_ms" "${TS}" "$(( (offset % 50) + 5 ))" 2>/dev/null || true
done

echo "  RedisTimeSeries keys created with sample data."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Redis Stack seed complete ==="
echo "  Hexads:     3 (hexad:test-001, hexad:test-002, hexad:test-003)"
echo "  Drift:      2 (drift:test-001, drift:test-002)"
echo "  TimeSeries: 3 keys with sample data points"
echo "  Indexes:    idx:hexads, idx:drift"
echo ""
echo "  Verify with:"
echo "    redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} FT.SEARCH idx:hexads '*'"
echo "    redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} JSON.GET hexad:test-001"
