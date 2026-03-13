# M11 HTTP API Specification

**Date:** 2026-02-04
**Milestone:** M11 (HTTP API for Lith-Geo & Lith-Analytics)
**Status:** Draft Specification

## Overview

M11 adds HTTP/REST API endpoints to Lithoglyph for remote access to:
- Lith-Geo (geospatial data with provenance)
- Lith-Analytics (time-series analytics with provenance)
- Core Lithoglyph operations (transactions, schema, journal)

## Technology Stack

**Framework:** Phoenix (Elixir)
- Proven production-ready HTTP server
- Built on BEAM (same runtime as Gleam/Erlang)
- Native support for NIFs
- WebSocket support for real-time journal subscriptions
- Excellent performance (millions of concurrent connections)

**Alternative (if Phoenix too heavy):** Plug + Cowboy
- Minimal HTTP server
- Direct Erlang/Gleam integration
- Lower overhead

## API Endpoints

### Core Lithoglyph Operations

#### GET /api/v1/version
Get Lithoglyph version

**Response:**
```json
{
  "version": "1.0.0",
  "api_version": "v1"
}
```

#### POST /api/v1/databases
Create/open a database

**Request:**
```json
{
  "path": "/data/mydb",
  "mode": "create" | "open"
}
```

**Response:**
```json
{
  "database_id": "db_abc123",
  "path": "/data/mydb"
}
```

#### POST /api/v1/databases/:db_id/transactions
Begin a transaction

**Request:**
```json
{
  "mode": "read_only" | "read_write"
}
```

**Response:**
```json
{
  "transaction_id": "txn_xyz789",
  "mode": "read_write"
}
```

#### POST /api/v1/transactions/:txn_id/operations
Apply an operation (CBOR-encoded)

**Request:**
```json
{
  "operation": "<base64-encoded-cbor>",
  "provenance": "<optional-provenance-cbor>"
}
```

**Response:**
```json
{
  "block_id": "<base64-encoded-block-id>",
  "timestamp": "2026-02-04T12:34:56Z"
}
```

#### POST /api/v1/transactions/:txn_id/commit
Commit a transaction

**Response:**
```json
{
  "status": "committed",
  "block_count": 42
}
```

#### POST /api/v1/transactions/:txn_id/abort
Abort a transaction

**Response:**
```json
{
  "status": "aborted"
}
```

#### GET /api/v1/databases/:db_id/schema
Get database schema (CBOR)

**Response:**
```json
{
  "schema": "<base64-encoded-cbor>",
  "version": 1
}
```

#### GET /api/v1/databases/:db_id/journal
Get journal entries

**Query Parameters:**
- `since`: Sequence number (default: 0)
- `limit`: Max entries (default: 100)

**Response:**
```json
{
  "entries": "<base64-encoded-cbor>",
  "next_sequence": 142
}
```

#### DELETE /api/v1/databases/:db_id
Close database

**Response:**
```json
{
  "status": "closed"
}
```

### Lith-Geo Endpoints

#### POST /api/v1/geo/insert
Insert geospatial data with provenance

**Request:**
```json
{
  "database_id": "db_abc123",
  "geometry": {
    "type": "Point",
    "coordinates": [-122.4194, 37.7749]
  },
  "properties": {
    "name": "San Francisco",
    "population": 873965
  },
  "provenance": {
    "source": "USGS",
    "timestamp": "2026-02-04T12:00:00Z",
    "confidence": 0.95
  }
}
```

**Response:**
```json
{
  "feature_id": "feat_123",
  "block_id": "<base64-encoded-block-id>"
}
```

#### GET /api/v1/geo/query
Query geospatial data

**Query Parameters:**
- `bbox`: Bounding box (minx,miny,maxx,maxy)
- `geometry`: GeoJSON geometry filter
- `filter`: Property filter (JSON)
- `limit`: Max results (default: 100)

**Response:**
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "feat_123",
      "geometry": { ... },
      "properties": { ... },
      "provenance": { ... }
    }
  ]
}
```

#### GET /api/v1/geo/features/:feature_id/provenance
Get feature provenance history

**Response:**
```json
{
  "feature_id": "feat_123",
  "provenance_chain": [
    {
      "block_id": "<base64>",
      "timestamp": "2026-02-04T12:00:00Z",
      "source": "USGS",
      "operation": "insert"
    }
  ]
}
```

### Lith-Analytics Endpoints

#### POST /api/v1/analytics/timeseries
Insert time-series data with provenance

**Request:**
```json
{
  "database_id": "db_abc123",
  "series_id": "sensor_temp_01",
  "timestamp": "2026-02-04T12:34:56Z",
  "value": 72.5,
  "metadata": {
    "sensor_id": "temp_01",
    "location": "building_a"
  },
  "provenance": {
    "source": "iot_gateway",
    "quality": "calibrated"
  }
}
```

**Response:**
```json
{
  "point_id": "ts_456",
  "block_id": "<base64-encoded-block-id>"
}
```

#### GET /api/v1/analytics/timeseries
Query time-series data

**Query Parameters:**
- `series_id`: Series identifier
- `start`: Start timestamp (ISO 8601)
- `end`: End timestamp (ISO 8601)
- `aggregation`: none | avg | min | max | sum
- `interval`: Aggregation interval (1m, 5m, 1h, 1d)
- `limit`: Max results (default: 1000)

**Response:**
```json
{
  "series_id": "sensor_temp_01",
  "data": [
    {
      "timestamp": "2026-02-04T12:00:00Z",
      "value": 72.5,
      "provenance": { ... }
    }
  ]
}
```

#### GET /api/v1/analytics/timeseries/:series_id/provenance
Get time-series provenance

**Response:**
```json
{
  "series_id": "sensor_temp_01",
  "provenance_summary": {
    "sources": ["iot_gateway", "manual_entry"],
    "quality_distribution": {
      "calibrated": 0.95,
      "uncalibrated": 0.05
    }
  }
}
```

### Real-Time Subscriptions (WebSocket)

#### WS /api/v1/journal/subscribe
Subscribe to journal updates

**Subscribe Message:**
```json
{
  "action": "subscribe",
  "database_id": "db_abc123",
  "since": 100
}
```

**Update Message (server → client):**
```json
{
  "type": "journal_entry",
  "sequence": 101,
  "block_id": "<base64>",
  "timestamp": "2026-02-04T12:34:56Z",
  "operation": "<base64-cbor>"
}
```

## Authentication & Authorization

### M11 PoC: Basic Auth
- HTTP Basic Authentication
- Single admin user for testing

### M12 Production: JWT + Provenance
- JWT tokens with HMAC-SHA256
- User provenance tracking
- Permission-based access control
- API key support for service-to-service

## Error Responses

Standard error format:
```json
{
  "error": {
    "code": "INVALID_OPERATION",
    "message": "CBOR parsing failed: invalid major type",
    "details": {
      "expected": "map",
      "received": "array"
    }
  }
}
```

### Error Codes
- `INVALID_OPERATION`: CBOR/operation error
- `TRANSACTION_ERROR`: Transaction state error
- `CONNECTION_ERROR`: Database connection error
- `NOT_FOUND`: Resource not found
- `UNAUTHORIZED`: Authentication required
- `FORBIDDEN`: Permission denied
- `RATE_LIMIT_EXCEEDED`: Too many requests

## Rate Limiting

M11 PoC:
- 1000 requests/minute per IP
- 100 concurrent connections per IP

M12 Production:
- Configurable per-user/per-API-key limits
- Redis-backed distributed rate limiting

## Implementation Plan

### Phase 1: Core API (2-3 hours)
1. Phoenix project setup
2. NIF integration (reuse Lith-BEAM)
3. Core endpoints (version, database, transaction, operations)
4. Error handling
5. Basic tests

### Phase 2: Geo Endpoints (1-2 hours)
1. GeoJSON parsing
2. Spatial query implementation
3. Provenance tracking
4. Bounding box queries

### Phase 3: Analytics Endpoints (1-2 hours)
1. Time-series data model
2. Aggregation queries
3. Provenance summary
4. Timestamp indexing

### Phase 4: WebSocket Subscriptions (1 hour)
1. Phoenix Channel setup
2. Journal subscription
3. Real-time updates
4. Connection management

### Total Estimate: 5-8 hours

## Testing Strategy

### Unit Tests
- Each endpoint
- CBOR encoding/decoding
- Error handling

### Integration Tests
- End-to-end transaction flow
- Geo query with provenance
- Analytics aggregation
- WebSocket subscription

### Load Tests
- Apache Bench (ab) or wrk
- Target: 10,000 req/s on basic operations
- WebSocket: 10,000 concurrent connections

## Deployment

### M11 PoC
- Single Elixir release
- Embedded Erlang VM
- Port 4000

### M12 Production
- Distributed Erlang cluster
- Load balancer (nginx/HAProxy)
- HTTPS/TLS
- Health checks
- Metrics (Prometheus)

## Next Steps

1. Create Phoenix project: `mix phx.new lith_http --no-html --no-assets --database=false`
2. Add Lith-BEAM NIF dependency
3. Implement core endpoints
4. Add Geo/Analytics modules
5. Write tests
6. Document API with OpenAPI/Swagger

---

**Status:** Specification complete, ready for implementation
**Dependencies:** Lith-BEAM (complete), Phoenix/Plug (to be installed)
**Target:** M11 milestone (HTTP API operational)
