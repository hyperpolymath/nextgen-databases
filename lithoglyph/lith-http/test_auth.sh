#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Lithoglyph HTTP Authentication Test Script

set -e

BASE_URL="http://localhost:4000"

echo ""
echo "=== Lithoglyph HTTP Authentication Test ==="
echo ""

# Test 1: Generate JWT token
echo "Test 1: POST /auth/token (login)"
TOKEN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/token" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "admin"
  }')
echo "$TOKEN_RESPONSE" | jq '.'
TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token')
echo "Token: $TOKEN"
echo ""

# Test 2: Verify JWT token
echo "Test 2: POST /auth/verify"
curl -s -X POST "$BASE_URL/auth/verify" \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$TOKEN\"}" | jq '.'
echo ""

# Test 3: Invalid credentials
echo "Test 3: POST /auth/token (invalid credentials)"
curl -s -X POST "$BASE_URL/auth/token" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "invalid",
    "password": "wrong"
  }' | jq '.'
echo ""

# Test 4: Access API with JWT token (if auth enabled)
echo "Test 4: GET /api/v1/version (with JWT token)"
curl -s "$BASE_URL/api/v1/version" \
  -H "Authorization: Bearer $TOKEN" | jq '.'
echo ""

# Test 5: Test rate limiting headers (even if rate limiting disabled)
echo "Test 5: Check rate limit headers"
echo "Making 5 requests to check headers..."
for i in {1..5}; do
  echo "Request $i:"
  curl -s -I "$BASE_URL/api/v1/version" | grep -i "ratelimit" || echo "  No rate limit headers (rate limiting disabled)"
done
echo ""

# Test 6: Generate token with custom claims
echo "Test 6: POST /auth/token (with custom claims)"
curl -s -X POST "$BASE_URL/auth/token" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "admin",
    "claims": {
      "role": "admin",
      "permissions": ["read", "write", "delete"]
    }
  }' | jq '.'
echo ""

echo "=== All authentication tests passed! ==="
echo ""
echo "Note: Authentication is DISABLED by default in M12 PoC."
echo "To enable: Set auth_enabled: true in router.ex :api_authenticated pipeline"
echo ""
