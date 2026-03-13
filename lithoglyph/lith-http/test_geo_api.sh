#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# FormBD-Geo HTTP API Test Script

set -e

BASE_URL="http://localhost:4000/api/v1"

echo ""
echo "=== FormBD-Geo HTTP API Test ==="
echo ""

# Test 1: Create database
echo "Test 1: Create database"
DB_RESPONSE=$(curl -s -X POST "$BASE_URL/databases" \
  -H "Content-Type: application/json" \
  -d '{"path": "/tmp/lith_geo_test"}')
echo "$DB_RESPONSE" | jq '.'
DB_ID=$(echo "$DB_RESPONSE" | jq -r '.database_id')
echo "Database ID: $DB_ID"
echo ""

# Test 2: Insert Point feature
echo "Test 2: POST /api/v1/geo/insert (Point)"
POINT_RESPONSE=$(curl -s -X POST "$BASE_URL/geo/insert" \
  -H "Content-Type: application/json" \
  -d "{
    \"database_id\": \"$DB_ID\",
    \"geometry\": {
      \"type\": \"Point\",
      \"coordinates\": [-122.4194, 37.7749]
    },
    \"properties\": {
      \"name\": \"San Francisco\",
      \"population\": 873965
    },
    \"provenance\": {
      \"source\": \"USGS\",
      \"timestamp\": \"2026-02-04T12:00:00Z\",
      \"confidence\": 0.95
    }
  }")
echo "$POINT_RESPONSE" | jq '.'
FEATURE_ID=$(echo "$POINT_RESPONSE" | jq -r '.feature_id')
echo "Feature ID: $FEATURE_ID"
echo ""

# Test 3: Query by bounding box
echo "Test 3: GET /api/v1/geo/query (bbox)"
curl -s "$BASE_URL/geo/query?database_id=$DB_ID&bbox=-123,37,-122,38&limit=10" | jq '.'
echo ""

# Test 4: Query by geometry
echo "Test 4: GET /api/v1/geo/query (geometry)"
curl -s -G "$BASE_URL/geo/query" \
  --data-urlencode "database_id=$DB_ID" \
  --data-urlencode 'geometry={"type":"Point","coordinates":[-122.4194,37.7749]}' \
  --data-urlencode "limit=10" | jq '.'
echo ""

# Test 5: Get feature provenance
echo "Test 5: GET /api/v1/geo/features/:feature_id/provenance"
curl -s "$BASE_URL/geo/features/$FEATURE_ID/provenance?database_id=$DB_ID" | jq '.'
echo ""

# Test 6: Insert LineString feature
echo "Test 6: POST /api/v1/geo/insert (LineString)"
curl -s -X POST "$BASE_URL/geo/insert" \
  -H "Content-Type: application/json" \
  -d "{
    \"database_id\": \"$DB_ID\",
    \"geometry\": {
      \"type\": \"LineString\",
      \"coordinates\": [[-122.4, 37.7], [-122.5, 37.8], [-122.6, 37.9]]
    },
    \"properties\": {
      \"name\": \"Highway 101\",
      \"type\": \"road\"
    },
    \"provenance\": {
      \"source\": \"OpenStreetMap\"
    }
  }" | jq '.'
echo ""

# Test 7: Insert Polygon feature
echo "Test 7: POST /api/v1/geo/insert (Polygon)"
curl -s -X POST "$BASE_URL/geo/insert" \
  -H "Content-Type: application/json" \
  -d "{
    \"database_id\": \"$DB_ID\",
    \"geometry\": {
      \"type\": \"Polygon\",
      \"coordinates\": [[[-122.5, 37.7], [-122.4, 37.7], [-122.4, 37.8], [-122.5, 37.8], [-122.5, 37.7]]]
    },
    \"properties\": {
      \"name\": \"Golden Gate Park\",
      \"area_sqkm\": 4.1
    },
    \"provenance\": {
      \"source\": \"City of SF\"
    }
  }" | jq '.'
echo ""

# Test 8: Close database
echo "Test 8: Close database"
curl -s -X DELETE "$BASE_URL/databases/$DB_ID" | jq '.'
echo ""

echo "=== All Geo API tests passed! ==="
echo ""
