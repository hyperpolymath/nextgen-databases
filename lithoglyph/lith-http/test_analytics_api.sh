#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# FormBD-Analytics HTTP API Test Script

set -e

BASE_URL="http://localhost:4000/api/v1"

echo ""
echo "=== FormBD-Analytics HTTP API Test ==="
echo ""

# Test 1: Create database
echo "Test 1: Create database"
DB_RESPONSE=$(curl -s -X POST "$BASE_URL/databases" \
  -H "Content-Type: application/json" \
  -d '{"path": "/tmp/lith_analytics_test"}')
echo "$DB_RESPONSE" | jq '.'
DB_ID=$(echo "$DB_RESPONSE" | jq -r '.database_id')
echo "Database ID: $DB_ID"
echo ""

# Test 2: Insert time-series data point
echo "Test 2: POST /api/v1/analytics/timeseries"
TS1=$(curl -s -X POST "$BASE_URL/analytics/timeseries" \
  -H "Content-Type: application/json" \
  -d "{
    \"database_id\": \"$DB_ID\",
    \"series_id\": \"sensor_temp_01\",
    \"timestamp\": \"2026-02-04T12:00:00Z\",
    \"value\": 72.5,
    \"metadata\": {
      \"sensor_id\": \"temp_01\",
      \"location\": \"building_a\",
      \"unit\": \"fahrenheit\"
    },
    \"provenance\": {
      \"source\": \"iot_gateway\",
      \"quality\": \"calibrated\"
    }
  }")
echo "$TS1" | jq '.'
POINT_ID=$(echo "$TS1" | jq -r '.point_id')
echo "Point ID: $POINT_ID"
echo ""

# Test 3: Insert more data points
echo "Test 3: Insert multiple time-series points"
for hour in {1..5}; do
  TIMESTAMP=$(date -u -d "2026-02-04 12:0$hour:00" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-$((5-hour))H +"%Y-%m-%dT%H:%M:%SZ")
  VALUE=$(echo "72 + $hour * 0.5" | bc)

  curl -s -X POST "$BASE_URL/analytics/timeseries" \
    -H "Content-Type: application/json" \
    -d "{
      \"database_id\": \"$DB_ID\",
      \"series_id\": \"sensor_temp_01\",
      \"timestamp\": \"$TIMESTAMP\",
      \"value\": $VALUE,
      \"metadata\": {\"sensor_id\": \"temp_01\"},
      \"provenance\": {\"source\": \"iot_gateway\"}
    }" > /dev/null
  echo "  Inserted point at $TIMESTAMP with value $VALUE"
done
echo ""

# Test 4: Query time-series (no aggregation)
echo "Test 4: GET /api/v1/analytics/timeseries (no aggregation)"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=sensor_temp_01&start=2026-02-04T12:00:00Z&end=2026-02-04T13:00:00Z&limit=100" | jq '.'
echo ""

# Test 5: Query with AVG aggregation
echo "Test 5: GET /api/v1/analytics/timeseries (avg aggregation)"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=sensor_temp_01&start=2026-02-04T12:00:00Z&end=2026-02-04T13:00:00Z&aggregation=avg&interval=5m" | jq '.'
echo ""

# Test 6: Query with MIN aggregation
echo "Test 6: GET /api/v1/analytics/timeseries (min aggregation)"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=sensor_temp_01&start=2026-02-04T12:00:00Z&end=2026-02-04T13:00:00Z&aggregation=min" | jq '.'
echo ""

# Test 7: Query with MAX aggregation
echo "Test 7: GET /api/v1/analytics/timeseries (max aggregation)"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=sensor_temp_01&start=2026-02-04T12:00:00Z&end=2026-02-04T13:00:00Z&aggregation=max" | jq '.'
echo ""

# Test 8: Query with SUM aggregation
echo "Test 8: GET /api/v1/analytics/timeseries (sum aggregation)"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=sensor_temp_01&start=2026-02-04T12:00:00Z&end=2026-02-04T13:00:00Z&aggregation=sum" | jq '.'
echo ""

# Test 9: Query with COUNT aggregation
echo "Test 9: GET /api/v1/analytics/timeseries (count aggregation)"
curl -s "$BASE_URL/analytics/timeseries?database_id=$DB_ID&series_id=sensor_temp_01&start=2026-02-04T12:00:00Z&end=2026-02-04T13:00:00Z&aggregation=count" | jq '.'
echo ""

# Test 10: Get time-series provenance
echo "Test 10: GET /api/v1/analytics/timeseries/:series_id/provenance"
curl -s "$BASE_URL/analytics/timeseries/sensor_temp_01/provenance?database_id=$DB_ID" | jq '.'
echo ""

# Test 11: Insert different series
echo "Test 11: Insert data for different series"
curl -s -X POST "$BASE_URL/analytics/timeseries" \
  -H "Content-Type: application/json" \
  -d "{
    \"database_id\": \"$DB_ID\",
    \"series_id\": \"sensor_humidity_01\",
    \"timestamp\": \"2026-02-04T12:00:00Z\",
    \"value\": 45.2,
    \"metadata\": {
      \"sensor_id\": \"humidity_01\",
      \"location\": \"building_a\",
      \"unit\": \"percent\"
    },
    \"provenance\": {
      \"source\": \"iot_gateway\",
      \"quality\": \"calibrated\"
    }
  }" | jq '.'
echo ""

# Test 12: Close database
echo "Test 12: Close database"
curl -s -X DELETE "$BASE_URL/databases/$DB_ID" | jq '.'
echo ""

echo "=== All Analytics API tests passed! ==="
echo ""
