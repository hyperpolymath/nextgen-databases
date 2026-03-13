#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Lithoglyph HTTP API Test Script

set -e

BASE_URL="http://localhost:4000/api/v1"

echo ""
echo "=== Lithoglyph HTTP API Test ==="
echo ""

# Test 1: Version
echo "Test 1: GET /api/v1/version"
curl -s "$BASE_URL/version" | jq '.'
echo ""

# Test 2: Create database
echo "Test 2: POST /api/v1/databases"
DB_RESPONSE=$(curl -s -X POST "$BASE_URL/databases" \
  -H "Content-Type: application/json" \
  -d '{"path": "/tmp/lith_http_test", "mode": "create"}')
echo "$DB_RESPONSE" | jq '.'
DB_ID=$(echo "$DB_RESPONSE" | jq -r '.database_id')
echo "Database ID: $DB_ID"
echo ""

# Test 3: Get schema
echo "Test 3: GET /api/v1/databases/:db_id/schema"
curl -s "$BASE_URL/databases/$DB_ID/schema" | jq '.'
echo ""

# Test 4: Get journal
echo "Test 4: GET /api/v1/databases/:db_id/journal"
curl -s "$BASE_URL/databases/$DB_ID/journal?since=0" | jq '.'
echo ""

# Test 5: Begin transaction
echo "Test 5: POST /api/v1/databases/:db_id/transactions"
TXN_RESPONSE=$(curl -s -X POST "$BASE_URL/databases/$DB_ID/transactions" \
  -H "Content-Type: application/json" \
  -d '{"mode": "read_write"}')
echo "$TXN_RESPONSE" | jq '.'
TXN_ID=$(echo "$TXN_RESPONSE" | jq -r '.transaction_id')
echo "Transaction ID: $TXN_ID"
echo ""

# Test 6: Apply operation
echo "Test 6: POST /api/v1/transactions/:txn_id/operations"
# CBOR map {1: 2} = 0xa1 0x01 0x02 in base64
CBOR_BASE64=$(echo -n -e '\xa1\x01\x02' | base64)
OP_RESPONSE=$(curl -s -X POST "$BASE_URL/transactions/$TXN_ID/operations" \
  -H "Content-Type: application/json" \
  -d "{\"operation\": \"$CBOR_BASE64\"}")
echo "$OP_RESPONSE" | jq '.'
echo ""

# Test 7: Commit transaction
echo "Test 7: POST /api/v1/transactions/:txn_id/commit"
curl -s -X POST "$BASE_URL/transactions/$TXN_ID/commit" | jq '.'
echo ""

# Test 8: Close database
echo "Test 8: DELETE /api/v1/databases/:db_id"
curl -s -X DELETE "$BASE_URL/databases/$DB_ID" | jq '.'
echo ""

echo "=== All HTTP API tests passed! ==="
echo ""
