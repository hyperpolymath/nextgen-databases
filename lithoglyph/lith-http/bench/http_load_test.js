// SPDX-License-Identifier: PMPL-1.0-or-later
// HTTP Load Testing with k6
// Run: k6 run bench/http_load_test.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const cacheHitRate = new Rate('cache_hits');
const insertLatency = new Trend('insert_latency');
const queryLatency = new Trend('query_latency');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up to 10 users
    { duration: '1m', target: 50 },    // Ramp up to 50 users
    { duration: '2m', target: 50 },    // Stay at 50 users
    { duration: '30s', target: 100 },  // Spike to 100 users
    { duration: '1m', target: 100 },   // Stay at 100 users
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // 95% < 500ms, 99% < 1s
    errors: ['rate<0.1'],                            // Error rate < 10%
    cache_hits: ['rate>0.5'],                        // Cache hit rate > 50%
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000/api/v1';
let db_id;

// Setup: Create database once
export function setup() {
  const res = http.post(`${BASE_URL}/databases`, JSON.stringify({
    name: `loadtest_${Date.now()}`,
    description: 'Load testing database'
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  check(res, {
    'database created': (r) => r.status === 200 || r.status === 201,
  });

  const body = JSON.parse(res.body);
  console.log(`Database created: ${body.db_id}`);
  return { db_id: body.db_id };
}

// Main test scenario
export default function(data) {
  db_id = data.db_id;

  // Weighted scenario: 60% reads, 30% inserts, 10% aggregations
  const scenario = Math.random();

  if (scenario < 0.3) {
    // 30% - Insert geospatial features
    insertFeature();
  } else if (scenario < 0.9) {
    // 60% - Query features (should hit cache)
    queryFeatures();
  } else {
    // 10% - Time-series operations
    timeSeriesOperations();
  }

  sleep(Math.random() * 2); // Random sleep 0-2s
}

function insertFeature() {
  const start = Date.now();

  const lat = -90 + Math.random() * 180;
  const lng = -180 + Math.random() * 360;

  const res = http.post(`${BASE_URL}/databases/${db_id}/features`, JSON.stringify({
    geometry: {
      type: 'Point',
      coordinates: [lng, lat]
    },
    properties: {
      name: `Feature ${Date.now()}`,
      value: Math.random() * 100
    },
    provenance: {
      source: 'k6_loadtest',
      timestamp: new Date().toISOString()
    }
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  const success = check(res, {
    'feature inserted': (r) => r.status === 200 || r.status === 201,
  });

  errorRate.add(!success);
  insertLatency.add(Date.now() - start);
}

function queryFeatures() {
  const start = Date.now();

  // Random bounding box queries
  const minLat = -90 + Math.random() * 170;
  const minLng = -180 + Math.random() * 350;
  const maxLat = minLat + 10;
  const maxLng = minLng + 10;

  const res = http.get(
    `${BASE_URL}/databases/${db_id}/features/bbox?` +
    `min_lat=${minLat}&min_lng=${minLng}&max_lat=${maxLat}&max_lng=${maxLng}&limit=100`,
    {
      headers: { 'Accept': 'application/json' },
    }
  );

  const success = check(res, {
    'query successful': (r) => r.status === 200,
    'has features': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.type === 'FeatureCollection';
      } catch {
        return false;
      }
    }
  });

  errorRate.add(!success);
  queryLatency.add(Date.now() - start);

  // Track cache hits (same query twice)
  if (Math.random() < 0.3) {
    const res2 = http.get(
      `${BASE_URL}/databases/${db_id}/features/bbox?` +
      `min_lat=${minLat}&min_lng=${minLng}&max_lat=${maxLat}&max_lng=${maxLng}&limit=100`
    );
    // Second request should be faster (cached)
    cacheHitRate.add(res2.timings.duration < res.timings.duration);
  }
}

function timeSeriesOperations() {
  const series_id = `sensor_${Math.floor(Math.random() * 10)}`;

  // Insert time-series point
  const res1 = http.post(`${BASE_URL}/databases/${db_id}/timeseries`, JSON.stringify({
    series_id: series_id,
    timestamp: new Date().toISOString(),
    value: Math.random() * 100,
    tags: { sensor_type: 'temperature' }
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  check(res1, {
    'timeseries inserted': (r) => r.status === 200 || r.status === 201,
  });

  // Query time-series
  const end_time = new Date().toISOString();
  const start_time = new Date(Date.now() - 3600000).toISOString();

  const res2 = http.get(
    `${BASE_URL}/databases/${db_id}/timeseries/${series_id}?` +
    `start_time=${start_time}&end_time=${end_time}&aggregation=avg&interval=5m`,
    {
      headers: { 'Accept': 'application/json' },
    }
  );

  check(res2, {
    'timeseries queried': (r) => r.status === 200,
  });
}

// Teardown: Optionally clean up
export function teardown(data) {
  console.log(`Load test complete for database: ${data.db_id}`);
  // Could delete database here if needed
}
