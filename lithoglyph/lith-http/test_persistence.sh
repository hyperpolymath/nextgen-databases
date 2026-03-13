#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Lithoglyph HTTP Real Data Persistence Test Script

set -e

BASE_URL="http://localhost:4000/api/v1"

echo ""
echo "=== Lithoglyph HTTP Real Data Persistence Test ==="
echo ""

# Test 1: Create database
echo "Test 1: Create database"
DB_RESPONSE=$(curl -s -X POST "$BASE_URL/databases" \
  -H "Content-Type: application/json" \
  -d '{
    "path": "/tmp/lith_persistence_test.db"
  }')
echo "$DB_RESPONSE" | jq '.'
DB_ID=$(echo "$DB_RESPONSE" | jq -r '.database_id')
echo "Database ID: $DB_ID"
echo ""

# Test 2: Insert geospatial feature with real persistence
echo "Test 2: Insert GeoJSON feature (real persistence)"
FEATURE_RESPONSE=$(curl -s -X POST "$BASE_URL/geo/insert" \
  -H "Content-Type: application/json" \
  -d "{
    \"database_id\": \"$DB_ID\",
    \"geometry\": {
      \"type\": \"Point\",
      \"coordinates\": [-122.4194, 37.7749]
    },
    \"properties\": {
      \"name\": \"San Francisco City Hall\",
      \"address\": \"1 Dr Carlton B Goodlett Pl\",
      \"city\": \"San Francisco\"
    },
    \"provenance\": {
      \"source\": \"OpenStreetMap\",
      \"confidence\": 0.99,
      \"collected_at\": \"2026-02-04T12:00:00Z\"
    }
  }")
echo "$FEATURE_RESPONSE" | jq '.'
FEATURE_ID=$(echo "$FEATURE_RESPONSE" | jq -r '.feature_id')
BLOCK_ID=$(echo "$FEATURE_RESPONSE" | jq -r '.block_id')
echo "Feature ID: $FEATURE_ID"
echo "Block ID: $BLOCK_ID"
echo ""

# Test 3: Insert time-series data with real persistence
echo "Test 3: Insert time-series point (real persistence)"
TS_RESPONSE=$(curl -s -X POST "$BASE_URL/analytics/timeseries" \
  -H "Content-Type: application/json" \
  -d "{
    \"database_id\": \"$DB_ID\",
    \"series_id\": \"temperature_sensor_01\",
    \"timestamp\": \"2026-02-04T12:00:00Z\",
    \"value\": 72.5,
    \"metadata\": {
      \"sensor_id\": \"temp_01\",
      \"location\": \"building_a\",
      \"floor\": 3
    },
    \"provenance\": {
      \"source\": \"iot_gateway\",
      \"quality\": \"calibrated\",
      \"calibration_date\": \"2026-02-01\"
    }
  }")
echo "$TS_RESPONSE" | jq '.'
POINT_ID=$(echo "$TS_RESPONSE" | jq -r '.point_id')
echo "Point ID: $POINT_ID"
echo ""

# Test 4: Insert more time-series points
echo "Test 4: Insert multiple time-series points"
for i in {1..5}; do
  HOUR=$(printf "%02d" $((12 + i)))
  VALUE=$(echo "72.5 + $i * 0.5" | bc)

  curl -s -X POST "$BASE_URL/analytics/timeseries" \
    -H "Content-Type: application/json" \
    -d "{
      \"database_id\": \"$DB_ID\",
      \"series_id\": \"temperature_sensor_01\",
      \"timestamp\": \"2026-02-04T${HOUR}:00:00Z\",
      \"value\": $VALUE,
      \"metadata\": {\"sensor_id\": \"temp_01\"},
      \"provenance\": {\"source\": \"iot_gateway\"}
    }" > /dev/null

  echo "  Inserted point at ${HOUR}:00 with value $VALUE"
done
echo ""

# Test 5: Query time-series data
echo "Test 5: Query time-series (should return stored data)"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=temperature_sensor_01&start=2026-02-04T12:00:00Z&end=2026-02-04T18:00:00Z&limit=10" | jq '.'
echo ""

# Test 6: Query with aggregation
echo "Test 6: Query with AVG aggregation"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=temperature_sensor_01&start=2026-02-04T12:00:00Z&end=2026-02-04T18:00:00Z&aggregation=avg" | jq '.'
echo ""

# Test 7: Get database schema (CBOR-encoded)
echo "Test 7: Get database schema"
curl -s "$BASE_URL/databases/$DB_ID/schema" | jq '.'
echo ""

# Test 8: Get journal entries
echo "Test 8: Get journal entries"
curl -s "$BASE_URL/databases/$DB_ID/journal?since=0" | jq '.'
echo ""

# Test 9: Close database
echo "Test 9: Close database"
curl -s -X DELETE "$BASE_URL/databases/$DB_ID" | jq '.'
echo ""

echo "=== All persistence tests complete! ==="
echo ""
echo "Note: M12 uses CBOR encoding and real Lithoglyph NIF operations."
echo "Data is persisted to /tmp/lith_persistence_test.db"
echo ""
