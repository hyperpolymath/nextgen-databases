-- SPDX-License-Identifier: PMPL-1.0-or-later
--
-- VeriSimDB Test Infrastructure — ClickHouse Seed Script
--
-- Creates the verisimdb database with tables for hexads, modalities, and
-- drift scores. ClickHouse is used for columnar analytics over large
-- modality datasets — aggregate drift queries, modality distribution
-- statistics, and cross-entity analytics at scale.
--
-- Execute with:
--   clickhouse-client --host localhost --port 9000 --multiquery < clickhouse-init.sql
--   curl -s http://localhost:8123/ --data-binary @clickhouse-init.sql
--
-- Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS verisimdb;

-- ---------------------------------------------------------------------------
-- Hexads table — core entity metadata (MergeTree for fast OLAP scans)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS verisimdb.hexads
(
    id              String,
    title           String,
    content         String,
    entity_type     String,
    primary_modality String,
    version         UInt32,
    drift_status    Enum8('healthy' = 0, 'drifted' = 1, 'normalising' = 2, 'stale' = 3),
    drift_score     Float64,
    modality_count  UInt8,
    created_at      DateTime64(3),
    updated_at      DateTime64(3),
    -- Spatial data (nullable — not all hexads have spatial modalities)
    spatial_lat     Nullable(Float64),
    spatial_lon     Nullable(Float64),
    -- Vector metadata
    embedding_model     Nullable(String),
    embedding_dimensions Nullable(UInt16),
    -- Tags for fast filtering
    tags            Array(String)
)
ENGINE = MergeTree()
ORDER BY (created_at, id)
PARTITION BY toYYYYMM(created_at)
SETTINGS index_granularity = 8192;

-- ---------------------------------------------------------------------------
-- Modalities table — individual modality records per hexad
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS verisimdb.modalities
(
    hexad_id        String,
    modality_type   Enum8('graph' = 0, 'vector' = 1, 'tensor' = 2, 'semantic' = 3,
                          'document' = 4, 'temporal' = 5, 'provenance' = 6, 'spatial' = 7),
    data_size_bytes UInt64,
    last_updated    DateTime64(3),
    is_authoritative UInt8,       -- Boolean: 1 = authoritative source of truth
    quality_score   Float64,
    metadata        String        -- JSON blob for modality-specific data
)
ENGINE = MergeTree()
ORDER BY (hexad_id, modality_type)
SETTINGS index_granularity = 8192;

-- ---------------------------------------------------------------------------
-- Drift scores table — time-series of drift measurements
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS verisimdb.drift_scores
(
    hexad_id                    String,
    measured_at                 DateTime64(3),
    semantic_vector_drift       Float64,
    graph_document_drift        Float64,
    temporal_consistency_drift  Float64,
    tensor_drift                Float64,
    schema_drift                Float64,
    quality_drift               Float64,
    overall                     Float64,
    status                      Enum8('healthy' = 0, 'drifted' = 1, 'normalising' = 2, 'stale' = 3)
)
ENGINE = MergeTree()
ORDER BY (hexad_id, measured_at)
PARTITION BY toYYYYMM(measured_at)
SETTINGS index_granularity = 8192;

-- ---------------------------------------------------------------------------
-- Provenance events table — lineage tracking
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS verisimdb.provenance_events
(
    event_id        String,
    hexad_id        String,
    event_type      String,
    actor           String,
    timestamp       DateTime64(3),
    hash            String,
    parent_hash     Nullable(String),
    details         String
)
ENGINE = MergeTree()
ORDER BY (hexad_id, timestamp)
SETTINGS index_granularity = 8192;

-- ---------------------------------------------------------------------------
-- Materialized views for fast aggregate queries
-- ---------------------------------------------------------------------------

-- Drift status distribution (how many hexads per drift status?)
CREATE MATERIALIZED VIEW IF NOT EXISTS verisimdb.mv_drift_status_counts
ENGINE = SummingMergeTree()
ORDER BY (status, day)
AS SELECT
    status,
    toDate(measured_at) AS day,
    count() AS hexad_count
FROM verisimdb.drift_scores
GROUP BY status, day;

-- Modality distribution (which modalities are most common?)
CREATE MATERIALIZED VIEW IF NOT EXISTS verisimdb.mv_modality_distribution
ENGINE = SummingMergeTree()
ORDER BY modality_type
AS SELECT
    modality_type,
    count() AS occurrence_count,
    avg(quality_score) AS avg_quality
FROM verisimdb.modalities
GROUP BY modality_type;

-- Average drift by entity type
CREATE MATERIALIZED VIEW IF NOT EXISTS verisimdb.mv_avg_drift_by_type
ENGINE = AggregatingMergeTree()
ORDER BY entity_type
AS SELECT
    h.entity_type AS entity_type,
    avgState(d.overall) AS avg_drift,
    countState() AS entity_count
FROM verisimdb.drift_scores d
INNER JOIN verisimdb.hexads h ON d.hexad_id = h.id
GROUP BY h.entity_type;

-- ---------------------------------------------------------------------------
-- Insert test data — hexads
-- ---------------------------------------------------------------------------

INSERT INTO verisimdb.hexads VALUES
(
    'hexad-test-001',
    'Introduction to Cross-Modal Consistency',
    'VeriSimDB maintains consistency across 8 modality representations.',
    'Article',
    'document',
    3,
    'healthy',
    0.045,
    6,
    now() - INTERVAL 1 DAY,
    now(),
    51.5074,
    -0.1278,
    'test-embedding-v1',
    128,
    ['consistency', 'cross-modal', 'verisimdb']
),
(
    'hexad-test-002',
    'Drift Detection Algorithms',
    'Drift is measured as divergence between modalities using cosine similarity.',
    'TechArticle',
    'document',
    1,
    'drifted',
    0.213,
    3,
    now() - INTERVAL 1 DAY,
    now() - INTERVAL 1 HOUR,
    40.7484,
    -73.9857,
    'test-embedding-v1',
    128,
    ['drift', 'algorithms', 'cosine-similarity']
),
(
    'hexad-test-003',
    'Self-Normalisation Process',
    'When drift exceeds configurable thresholds, the normaliser regenerates modalities.',
    'Article',
    'document',
    1,
    'healthy',
    0.0,
    2,
    now(),
    now(),
    NULL,
    NULL,
    NULL,
    NULL,
    ['normalisation', 'consistency', 'drift']
);

-- ---------------------------------------------------------------------------
-- Insert test data — modalities
-- ---------------------------------------------------------------------------

INSERT INTO verisimdb.modalities VALUES
('hexad-test-001', 'document', 1024, now(), 1, 0.95, '{"format": "text/plain"}'),
('hexad-test-001', 'vector',   512,  now(), 0, 0.88, '{"model": "test-embedding-v1", "dim": 128}'),
('hexad-test-001', 'graph',    256,  now(), 0, 0.92, '{"triples": 5, "types": 2}'),
('hexad-test-001', 'temporal', 128,  now(), 0, 0.97, '{"versions": 3}'),
('hexad-test-001', 'spatial',  64,   now(), 0, 0.90, '{"type": "Point", "srid": 4326}'),
('hexad-test-001', 'provenance', 96, now(), 0, 0.99, '{"chain_length": 2}'),
('hexad-test-002', 'document', 896,  now() - INTERVAL 1 HOUR, 1, 0.82, '{"format": "text/plain"}'),
('hexad-test-002', 'vector',   512,  now() - INTERVAL 1 HOUR, 0, 0.55, '{"model": "test-embedding-v1", "dim": 128}'),
('hexad-test-002', 'spatial',  64,   now() - INTERVAL 1 HOUR, 0, 0.78, '{"type": "Point", "srid": 4326}'),
('hexad-test-003', 'document', 768,  now(), 1, 0.91, '{"format": "text/plain"}'),
('hexad-test-003', 'semantic', 128,  now(), 0, 0.92, '{"categories": 3, "confidence": 0.92}');

-- ---------------------------------------------------------------------------
-- Insert test data — drift scores (time-series)
-- ---------------------------------------------------------------------------

INSERT INTO verisimdb.drift_scores VALUES
('hexad-test-001', now() - INTERVAL 1 HOUR, 0.08, 0.03, 0.01, 0.0, 0.0, 0.05, 0.028, 'healthy'),
('hexad-test-001', now() - INTERVAL 30 MINUTE, 0.10, 0.04, 0.02, 0.0, 0.0, 0.06, 0.037, 'healthy'),
('hexad-test-001', now(), 0.12, 0.05, 0.02, 0.0, 0.0, 0.08, 0.045, 'healthy'),
('hexad-test-002', now() - INTERVAL 1 HOUR, 0.38, 0.28, 0.12, 0.0, 0.06, 0.22, 0.177, 'drifted'),
('hexad-test-002', now(), 0.45, 0.32, 0.15, 0.0, 0.08, 0.28, 0.213, 'drifted');

-- ---------------------------------------------------------------------------
-- Insert test data — provenance events
-- ---------------------------------------------------------------------------

INSERT INTO verisimdb.provenance_events VALUES
('prov-001-create', 'hexad-test-001', 'created', 'test-seed-script', now() - INTERVAL 1 DAY, 'sha256:a1b2c3d4e5f6', NULL, 'Initial creation via clickhouse-init.sql'),
('prov-001-update', 'hexad-test-001', 'modality_updated', 'test-seed-script', now() - INTERVAL 1 HOUR, 'sha256:f6e5d4c3b2a1', 'sha256:a1b2c3d4e5f6', 'Vector embedding regenerated'),
('prov-002-create', 'hexad-test-002', 'created', 'test-seed-script', now() - INTERVAL 1 DAY, 'sha256:b2c3d4e5f6a1', NULL, 'Initial creation'),
('prov-003-create', 'hexad-test-003', 'created', 'test-seed-script', now(), 'sha256:c3d4e5f6a1b2', NULL, 'Initial creation');
