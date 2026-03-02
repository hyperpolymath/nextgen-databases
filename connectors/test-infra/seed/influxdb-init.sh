#!/bin/sh
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VeriSimDB Test Infrastructure — InfluxDB 2 Seed Script
#
# Creates the verisimdb org and metrics bucket, then writes test data
# points for drift scores, query latency, and federation health metrics.
#
# Prerequisites:
#   - InfluxDB 2 container running on localhost:8086
#   - influx CLI available in PATH
#   - InfluxDB already initialised (auto-setup via environment variables)
#
# Usage:
#   ./influxdb-init.sh                    # Default: localhost:8086
#   INFLUX_HOST=http://influxdb:8086 INFLUX_TOKEN=my-token ./influxdb-init.sh
#
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

set -eu

INFLUX_HOST="${INFLUX_HOST:-http://localhost:8086}"
INFLUX_TOKEN="${INFLUX_TOKEN:-verisim-test-token-do-not-use-in-production}"
INFLUX_ORG="${INFLUX_ORG:-verisimdb}"

echo "=== VeriSimDB InfluxDB 2 Seed ==="
echo "  Host:  ${INFLUX_HOST}"
echo "  Org:   ${INFLUX_ORG}"

# ---------------------------------------------------------------------------
# Wait for InfluxDB to be ready
# ---------------------------------------------------------------------------

echo "--- Waiting for InfluxDB..."
for attempt in $(seq 1 30); do
    if curl -sf "${INFLUX_HOST}/health" >/dev/null 2>&1; then
        echo "  InfluxDB is ready."
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "  ERROR: InfluxDB did not become ready within 30 seconds."
        exit 1
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# Create additional buckets
# ---------------------------------------------------------------------------

echo "--- Creating additional buckets..."

# 'metrics' bucket is created by auto-setup; create additional ones
influx bucket create \
    --host "${INFLUX_HOST}" \
    --token "${INFLUX_TOKEN}" \
    --org "${INFLUX_ORG}" \
    --name "drift_scores" \
    --retention 30d \
    2>/dev/null || echo "  Bucket 'drift_scores' already exists (OK)"

influx bucket create \
    --host "${INFLUX_HOST}" \
    --token "${INFLUX_TOKEN}" \
    --org "${INFLUX_ORG}" \
    --name "federation_health" \
    --retention 7d \
    2>/dev/null || echo "  Bucket 'federation_health' already exists (OK)"

echo "  Buckets created: metrics (auto), drift_scores, federation_health"

# ---------------------------------------------------------------------------
# Helper: generate timestamps relative to now (seconds precision)
# ---------------------------------------------------------------------------

NOW=$(date +%s)

# Write data using Line Protocol via the API
write_lines() {
    BUCKET="$1"
    shift
    printf '%s\n' "$@" | curl -sf -XPOST \
        "${INFLUX_HOST}/api/v2/write?org=${INFLUX_ORG}&bucket=${BUCKET}&precision=s" \
        -H "Authorization: Token ${INFLUX_TOKEN}" \
        -H "Content-Type: text/plain" \
        --data-binary @- \
        || echo "  WARNING: Failed to write to bucket ${BUCKET}"
}

# ---------------------------------------------------------------------------
# Write drift score metrics
# ---------------------------------------------------------------------------

echo "--- Writing drift score metrics..."

# Drift scores for hexad-test-001 (healthy, gradual drift)
write_lines "drift_scores" \
    "drift,hexad_id=hexad-test-001,status=healthy semantic_vector=0.08,graph_document=0.03,temporal=0.01,overall=0.028 $((NOW - 3600))" \
    "drift,hexad_id=hexad-test-001,status=healthy semantic_vector=0.10,graph_document=0.04,temporal=0.02,overall=0.037 $((NOW - 1800))" \
    "drift,hexad_id=hexad-test-001,status=healthy semantic_vector=0.12,graph_document=0.05,temporal=0.02,overall=0.045 ${NOW}"

# Drift scores for hexad-test-002 (drifted, increasing)
write_lines "drift_scores" \
    "drift,hexad_id=hexad-test-002,status=drifted semantic_vector=0.30,graph_document=0.22,temporal=0.10,overall=0.150 $((NOW - 7200))" \
    "drift,hexad_id=hexad-test-002,status=drifted semantic_vector=0.38,graph_document=0.28,temporal=0.12,overall=0.177 $((NOW - 3600))" \
    "drift,hexad_id=hexad-test-002,status=drifted semantic_vector=0.45,graph_document=0.32,temporal=0.15,overall=0.213 ${NOW}"

# Drift scores for hexad-test-003 (healthy, zero drift)
write_lines "drift_scores" \
    "drift,hexad_id=hexad-test-003,status=healthy semantic_vector=0.0,graph_document=0.0,temporal=0.0,overall=0.0 ${NOW}"

echo "  Drift scores written (7 data points across 3 hexads)."

# ---------------------------------------------------------------------------
# Write query latency metrics
# ---------------------------------------------------------------------------

echo "--- Writing query latency metrics..."

# Simulate query latency over the last hour (1-minute intervals)
for offset in $(seq 0 5 60); do
    TS=$((NOW - offset * 60))
    # Vary latency between 3ms and 45ms
    LATENCY=$(( (offset * 7 + 13) % 45 + 3 ))
    write_lines "metrics" \
        "query_latency,service=verisimdb,query_type=search duration_ms=${LATENCY}i ${TS}"
done

# VQL query latency (separate measurement)
for offset in $(seq 0 10 60); do
    TS=$((NOW - offset * 60))
    LATENCY=$(( (offset * 11 + 7) % 80 + 5 ))
    write_lines "metrics" \
        "query_latency,service=verisimdb,query_type=vql duration_ms=${LATENCY}i ${TS}"
done

echo "  Query latency metrics written."

# ---------------------------------------------------------------------------
# Write federation health metrics
# ---------------------------------------------------------------------------

echo "--- Writing federation health metrics..."

# Federation adapter health (1 = up, 0 = down)
write_lines "federation_health" \
    "adapter_health,adapter=mongodb,host=mongodb:27017 status=1i,latency_ms=12i ${NOW}" \
    "adapter_health,adapter=redis,host=redis:6379 status=1i,latency_ms=3i ${NOW}" \
    "adapter_health,adapter=neo4j,host=neo4j:7687 status=1i,latency_ms=18i ${NOW}" \
    "adapter_health,adapter=clickhouse,host=clickhouse:8123 status=1i,latency_ms=8i ${NOW}" \
    "adapter_health,adapter=surrealdb,host=surrealdb:8000 status=1i,latency_ms=15i ${NOW}" \
    "adapter_health,adapter=influxdb,host=influxdb:8086 status=1i,latency_ms=5i ${NOW}" \
    "adapter_health,adapter=minio,host=minio:9000 status=1i,latency_ms=7i ${NOW}"

# Federation sync events
write_lines "federation_health" \
    "federation_sync,source=verisimdb,target=mongodb hexads_synced=150i,errors=0i,duration_ms=1200i $((NOW - 300))" \
    "federation_sync,source=verisimdb,target=redis hexads_synced=150i,errors=2i,duration_ms=350i $((NOW - 300))" \
    "federation_sync,source=verisimdb,target=neo4j hexads_synced=148i,errors=2i,duration_ms=2100i $((NOW - 300))"

echo "  Federation health metrics written."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== InfluxDB 2 seed complete ==="
echo "  Buckets:    metrics, drift_scores, federation_health"
echo "  Drift:      7 data points across 3 hexads"
echo "  Latency:    ~20 data points (search + VQL)"
echo "  Federation: 7 adapter health checks + 3 sync events"
echo ""
echo "  Verify with:"
echo "    influx query --host ${INFLUX_HOST} --token ${INFLUX_TOKEN} --org ${INFLUX_ORG} \\"
echo "      'from(bucket: \"drift_scores\") |> range(start: -1h) |> limit(n: 5)'"
