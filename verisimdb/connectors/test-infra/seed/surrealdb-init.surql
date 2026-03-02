-- SPDX-License-Identifier: PMPL-1.0-or-later
--
-- VeriSimDB Test Infrastructure — SurrealDB Seed Script
--
-- Defines namespace, database, tables with schemafull definitions,
-- edge tables for relationships, and inserts test data. SurrealDB
-- is tested as a multi-model federation target — it supports both
-- document and graph queries natively.
--
-- Execute with:
--   cat surrealdb-init.surql | surreal sql --endpoint http://localhost:8000 --ns verisimdb --db test
--
-- Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

-- ---------------------------------------------------------------------------
-- Namespace and database
-- ---------------------------------------------------------------------------

DEFINE NAMESPACE IF NOT EXISTS verisimdb;
USE NS verisimdb;

DEFINE DATABASE IF NOT EXISTS test;
USE DB test;

-- ---------------------------------------------------------------------------
-- Table definitions (schemafull)
-- ---------------------------------------------------------------------------

-- Hexads: core entity table
DEFINE TABLE IF NOT EXISTS hexads SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS title ON TABLE hexads TYPE string;
DEFINE FIELD IF NOT EXISTS content ON TABLE hexads TYPE string;
DEFINE FIELD IF NOT EXISTS entity_type ON TABLE hexads TYPE string;
DEFINE FIELD IF NOT EXISTS primary_modality ON TABLE hexads TYPE string;
DEFINE FIELD IF NOT EXISTS version ON TABLE hexads TYPE int;
DEFINE FIELD IF NOT EXISTS drift_status ON TABLE hexads TYPE string
    ASSERT $value INSIDE ['healthy', 'drifted', 'normalising', 'stale'];
DEFINE FIELD IF NOT EXISTS drift_score ON TABLE hexads TYPE float;
DEFINE FIELD IF NOT EXISTS tags ON TABLE hexads TYPE array;
DEFINE FIELD IF NOT EXISTS tags.* ON TABLE hexads TYPE string;
DEFINE FIELD IF NOT EXISTS created_at ON TABLE hexads TYPE datetime;
DEFINE FIELD IF NOT EXISTS updated_at ON TABLE hexads TYPE datetime;

-- Modalities: individual modality records
DEFINE TABLE IF NOT EXISTS modalities SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS hexad_id ON TABLE modalities TYPE record<hexads>;
DEFINE FIELD IF NOT EXISTS modality_type ON TABLE modalities TYPE string
    ASSERT $value INSIDE ['graph', 'vector', 'tensor', 'semantic', 'document', 'temporal', 'provenance', 'spatial'];
DEFINE FIELD IF NOT EXISTS data_size_bytes ON TABLE modalities TYPE int;
DEFINE FIELD IF NOT EXISTS is_authoritative ON TABLE modalities TYPE bool;
DEFINE FIELD IF NOT EXISTS quality_score ON TABLE modalities TYPE float;
DEFINE FIELD IF NOT EXISTS metadata ON TABLE modalities TYPE object;
DEFINE FIELD IF NOT EXISTS last_updated ON TABLE modalities TYPE datetime;

-- Drift scores: time-series measurements
DEFINE TABLE IF NOT EXISTS drift_scores SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS hexad_id ON TABLE drift_scores TYPE record<hexads>;
DEFINE FIELD IF NOT EXISTS measured_at ON TABLE drift_scores TYPE datetime;
DEFINE FIELD IF NOT EXISTS semantic_vector_drift ON TABLE drift_scores TYPE float;
DEFINE FIELD IF NOT EXISTS graph_document_drift ON TABLE drift_scores TYPE float;
DEFINE FIELD IF NOT EXISTS temporal_consistency_drift ON TABLE drift_scores TYPE float;
DEFINE FIELD IF NOT EXISTS tensor_drift ON TABLE drift_scores TYPE float;
DEFINE FIELD IF NOT EXISTS schema_drift ON TABLE drift_scores TYPE float;
DEFINE FIELD IF NOT EXISTS quality_drift ON TABLE drift_scores TYPE float;
DEFINE FIELD IF NOT EXISTS overall ON TABLE drift_scores TYPE float;
DEFINE FIELD IF NOT EXISTS status ON TABLE drift_scores TYPE string;

-- Provenance events: lineage tracking
DEFINE TABLE IF NOT EXISTS provenance_events SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS hexad_id ON TABLE provenance_events TYPE record<hexads>;
DEFINE FIELD IF NOT EXISTS event_type ON TABLE provenance_events TYPE string;
DEFINE FIELD IF NOT EXISTS actor ON TABLE provenance_events TYPE string;
DEFINE FIELD IF NOT EXISTS timestamp ON TABLE provenance_events TYPE datetime;
DEFINE FIELD IF NOT EXISTS hash ON TABLE provenance_events TYPE string;
DEFINE FIELD IF NOT EXISTS parent_hash ON TABLE provenance_events TYPE option<string>;
DEFINE FIELD IF NOT EXISTS details ON TABLE provenance_events TYPE string;

-- ---------------------------------------------------------------------------
-- Edge tables (graph relationships between hexads)
-- ---------------------------------------------------------------------------

-- relates_to: bidirectional conceptual link
DEFINE TABLE IF NOT EXISTS relates_to SCHEMAFULL TYPE RELATION IN hexads OUT hexads;
DEFINE FIELD IF NOT EXISTS weight ON TABLE relates_to TYPE float;
DEFINE FIELD IF NOT EXISTS since ON TABLE relates_to TYPE datetime;

-- cites: directed citation
DEFINE TABLE IF NOT EXISTS cites SCHEMAFULL TYPE RELATION IN hexads OUT hexads;
DEFINE FIELD IF NOT EXISTS weight ON TABLE cites TYPE float;
DEFINE FIELD IF NOT EXISTS context ON TABLE cites TYPE string;

-- derived_from: provenance derivation chain
DEFINE TABLE IF NOT EXISTS derived_from SCHEMAFULL TYPE RELATION IN hexads OUT hexads;
DEFINE FIELD IF NOT EXISTS derivation_type ON TABLE derived_from TYPE string;
DEFINE FIELD IF NOT EXISTS confidence ON TABLE derived_from TYPE float;
DEFINE FIELD IF NOT EXISTS timestamp ON TABLE derived_from TYPE datetime;

-- part_of: hierarchical containment
DEFINE TABLE IF NOT EXISTS part_of SCHEMAFULL TYPE RELATION IN hexads OUT hexads;
DEFINE FIELD IF NOT EXISTS role ON TABLE part_of TYPE string;

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

DEFINE INDEX IF NOT EXISTS idx_hexads_entity_type ON TABLE hexads FIELDS entity_type;
DEFINE INDEX IF NOT EXISTS idx_hexads_drift_status ON TABLE hexads FIELDS drift_status;
DEFINE INDEX IF NOT EXISTS idx_hexads_created_at ON TABLE hexads FIELDS created_at;
DEFINE INDEX IF NOT EXISTS idx_modalities_type ON TABLE modalities FIELDS modality_type;
DEFINE INDEX IF NOT EXISTS idx_drift_hexad ON TABLE drift_scores FIELDS hexad_id;
DEFINE INDEX IF NOT EXISTS idx_provenance_hexad ON TABLE provenance_events FIELDS hexad_id;

-- Full-text search index on hexad content
DEFINE ANALYZER IF NOT EXISTS hexad_analyzer TOKENIZERS blank, class FILTERS lowercase, snowball(english);
DEFINE INDEX IF NOT EXISTS idx_hexads_fulltext ON TABLE hexads FIELDS title, content SEARCH ANALYZER hexad_analyzer BM25;

-- ---------------------------------------------------------------------------
-- Insert test data — hexads
-- ---------------------------------------------------------------------------

CREATE hexads:test001 SET
    title = 'Introduction to Cross-Modal Consistency',
    content = 'VeriSimDB maintains consistency across 8 modality representations. Each entity exists simultaneously as graph, vector, tensor, semantic, document, temporal, provenance, and spatial data.',
    entity_type = 'Article',
    primary_modality = 'document',
    version = 3,
    drift_status = 'healthy',
    drift_score = 0.045,
    tags = ['consistency', 'cross-modal', 'verisimdb'],
    created_at = time::now() - 1d,
    updated_at = time::now();

CREATE hexads:test002 SET
    title = 'Drift Detection Algorithms',
    content = 'Drift is measured as divergence between modalities using cosine similarity for vectors, Jaccard distance for sets, and temporal decay functions for time-series data.',
    entity_type = 'TechArticle',
    primary_modality = 'document',
    version = 1,
    drift_status = 'drifted',
    drift_score = 0.213,
    tags = ['drift', 'algorithms', 'cosine-similarity'],
    created_at = time::now() - 1d,
    updated_at = time::now() - 1h;

CREATE hexads:test003 SET
    title = 'Self-Normalisation Process',
    content = 'When drift exceeds configurable thresholds, the normaliser identifies the most authoritative modality, regenerates drifted representations, validates consistency, and updates all modalities atomically.',
    entity_type = 'Article',
    primary_modality = 'document',
    version = 1,
    drift_status = 'healthy',
    drift_score = 0.0,
    tags = ['normalisation', 'consistency', 'drift'],
    created_at = time::now(),
    updated_at = time::now();

CREATE hexads:test004 SET
    title = 'Heterogeneous Federation',
    content = 'VeriSimDB can coordinate across PostgreSQL, ArangoDB, Elasticsearch, MongoDB, Redis, Neo4j, ClickHouse, SurrealDB, InfluxDB, DuckDB, SQLite, and other VeriSimDB instances.',
    entity_type = 'Concept',
    primary_modality = 'graph',
    version = 1,
    drift_status = 'healthy',
    drift_score = 0.0,
    tags = ['federation', 'heterogeneous', 'multi-database'],
    created_at = time::now(),
    updated_at = time::now();

-- ---------------------------------------------------------------------------
-- Insert test data — edge relationships
-- ---------------------------------------------------------------------------

RELATE hexads:test001 -> relates_to -> hexads:test002 SET
    weight = 0.85,
    since = time::now() - 1d;

RELATE hexads:test002 -> relates_to -> hexads:test001 SET
    weight = 0.85,
    since = time::now() - 1d;

RELATE hexads:test001 -> cites -> hexads:test003 SET
    weight = 0.72,
    context = 'normalisation reference';

RELATE hexads:test001 -> part_of -> hexads:test004 SET
    role = 'consistency-component';

RELATE hexads:test002 -> part_of -> hexads:test004 SET
    role = 'drift-detection-component';

RELATE hexads:test003 -> part_of -> hexads:test004 SET
    role = 'normalisation-component';

RELATE hexads:test003 -> derived_from -> hexads:test001 SET
    derivation_type = 'conceptual-extraction',
    confidence = 0.88,
    timestamp = time::now();

-- ---------------------------------------------------------------------------
-- Insert test data — modalities
-- ---------------------------------------------------------------------------

CREATE modalities:m001 SET
    hexad_id = hexads:test001, modality_type = 'document', data_size_bytes = 1024,
    is_authoritative = true, quality_score = 0.95,
    metadata = { format: 'text/plain' }, last_updated = time::now();

CREATE modalities:m002 SET
    hexad_id = hexads:test001, modality_type = 'vector', data_size_bytes = 512,
    is_authoritative = false, quality_score = 0.88,
    metadata = { model: 'test-embedding-v1', dimensions: 128 }, last_updated = time::now();

CREATE modalities:m003 SET
    hexad_id = hexads:test001, modality_type = 'graph', data_size_bytes = 256,
    is_authoritative = false, quality_score = 0.92,
    metadata = { triples: 5, types: 2 }, last_updated = time::now();

CREATE modalities:m004 SET
    hexad_id = hexads:test002, modality_type = 'document', data_size_bytes = 896,
    is_authoritative = true, quality_score = 0.82,
    metadata = { format: 'text/plain' }, last_updated = time::now() - 1h;

CREATE modalities:m005 SET
    hexad_id = hexads:test002, modality_type = 'vector', data_size_bytes = 512,
    is_authoritative = false, quality_score = 0.55,
    metadata = { model: 'test-embedding-v1', dimensions: 128 }, last_updated = time::now() - 1h;

-- ---------------------------------------------------------------------------
-- Insert test data — drift scores
-- ---------------------------------------------------------------------------

CREATE drift_scores:ds001 SET
    hexad_id = hexads:test001, measured_at = time::now(),
    semantic_vector_drift = 0.12, graph_document_drift = 0.05,
    temporal_consistency_drift = 0.02, tensor_drift = 0.0,
    schema_drift = 0.0, quality_drift = 0.08,
    overall = 0.045, status = 'healthy';

CREATE drift_scores:ds002 SET
    hexad_id = hexads:test002, measured_at = time::now(),
    semantic_vector_drift = 0.45, graph_document_drift = 0.32,
    temporal_consistency_drift = 0.15, tensor_drift = 0.0,
    schema_drift = 0.08, quality_drift = 0.28,
    overall = 0.213, status = 'drifted';

-- ---------------------------------------------------------------------------
-- Insert test data — provenance events
-- ---------------------------------------------------------------------------

CREATE provenance_events:pe001 SET
    hexad_id = hexads:test001, event_type = 'created',
    actor = 'test-seed-script', timestamp = time::now() - 1d,
    hash = 'sha256:a1b2c3d4e5f6', parent_hash = NONE,
    details = 'Initial creation via surrealdb-init.surql';

CREATE provenance_events:pe002 SET
    hexad_id = hexads:test001, event_type = 'modality_updated',
    actor = 'test-seed-script', timestamp = time::now() - 1h,
    hash = 'sha256:f6e5d4c3b2a1', parent_hash = 'sha256:a1b2c3d4e5f6',
    details = 'Vector embedding regenerated';
