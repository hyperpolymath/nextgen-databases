// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Test Infrastructure — Neo4j Seed Script (Cypher)
//
// Creates constraints, indexes, test nodes, relationships, and provenance
// chains for integration testing of the Neo4j graph federation adapter.
//
// Execute with:
//   cat neo4j-init.cypher | cypher-shell -a bolt://localhost:7687
//
// Or from the Neo4j browser at http://localhost:7474
//
// Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

// ---------------------------------------------------------------------------
// Constraints — uniqueness guarantees
// ---------------------------------------------------------------------------

CREATE CONSTRAINT hexad_id_unique IF NOT EXISTS
FOR (h:Hexad)
REQUIRE h.id IS UNIQUE;

CREATE CONSTRAINT provenance_event_id_unique IF NOT EXISTS
FOR (p:ProvenanceEvent)
REQUIRE p.event_id IS UNIQUE;

// ---------------------------------------------------------------------------
// Indexes — query performance
// ---------------------------------------------------------------------------

// Full-text index on hexad document content
CREATE FULLTEXT INDEX hexad_fulltext IF NOT EXISTS
FOR (h:Hexad)
ON EACH [h.title, h.content];

// Index on modality type
CREATE INDEX hexad_modality_type IF NOT EXISTS
FOR (h:Hexad)
ON (h.primary_modality);

// Index on creation timestamp
CREATE INDEX hexad_created_at IF NOT EXISTS
FOR (h:Hexad)
ON (h.created_at);

// Index on drift status
CREATE INDEX hexad_drift_status IF NOT EXISTS
FOR (h:Hexad)
ON (h.drift_status);

// Index on entity type
CREATE INDEX hexad_entity_type IF NOT EXISTS
FOR (h:Hexad)
ON (h.entity_type);

// ---------------------------------------------------------------------------
// Test Hexad Nodes
// ---------------------------------------------------------------------------

// Hexad 1: Cross-modal consistency article
MERGE (h1:Hexad:Article:Entity {id: 'hexad-test-001'})
SET h1.title = 'Introduction to Cross-Modal Consistency',
    h1.content = 'VeriSimDB maintains consistency across 8 modality representations. Each entity exists simultaneously as graph, vector, tensor, semantic, document, temporal, provenance, and spatial data.',
    h1.entity_type = 'Article',
    h1.primary_modality = 'document',
    h1.version = 3,
    h1.created_at = datetime() - duration('P1D'),
    h1.updated_at = datetime(),
    h1.drift_status = 'healthy',
    h1.drift_score = 0.045,
    h1.embedding_model = 'test-embedding-v1',
    h1.embedding_dimensions = 128,
    h1.spatial_lat = 51.5074,
    h1.spatial_lon = -0.1278;

// Hexad 2: Drift detection article
MERGE (h2:Hexad:TechArticle {id: 'hexad-test-002'})
SET h2.title = 'Drift Detection Algorithms',
    h2.content = 'Drift is measured as divergence between modalities using cosine similarity for vectors, Jaccard distance for sets, and temporal decay functions for time-series data.',
    h2.entity_type = 'TechArticle',
    h2.primary_modality = 'document',
    h2.version = 1,
    h2.created_at = datetime() - duration('P1D'),
    h2.updated_at = datetime() - duration('PT1H'),
    h2.drift_status = 'drifted',
    h2.drift_score = 0.213,
    h2.embedding_model = 'test-embedding-v1',
    h2.embedding_dimensions = 128,
    h2.spatial_lat = 40.7484,
    h2.spatial_lon = -73.9857;

// Hexad 3: Self-normalisation article
MERGE (h3:Hexad:Article {id: 'hexad-test-003'})
SET h3.title = 'Self-Normalisation Process',
    h3.content = 'When drift exceeds configurable thresholds, the normaliser identifies the most authoritative modality, regenerates drifted representations, validates consistency, and updates all modalities atomically.',
    h3.entity_type = 'Article',
    h3.primary_modality = 'document',
    h3.version = 1,
    h3.created_at = datetime(),
    h3.updated_at = datetime(),
    h3.drift_status = 'healthy',
    h3.drift_score = 0.0;

// Hexad 4: Federation concept
MERGE (h4:Hexad:Concept {id: 'hexad-test-004'})
SET h4.title = 'Heterogeneous Federation',
    h4.content = 'VeriSimDB can coordinate across PostgreSQL, ArangoDB, Elasticsearch, MongoDB, Redis, Neo4j, ClickHouse, SurrealDB, InfluxDB, DuckDB, SQLite, and other VeriSimDB instances.',
    h4.entity_type = 'Concept',
    h4.primary_modality = 'graph',
    h4.version = 1,
    h4.created_at = datetime(),
    h4.updated_at = datetime(),
    h4.drift_status = 'healthy',
    h4.drift_score = 0.0;

// ---------------------------------------------------------------------------
// Relationships
// ---------------------------------------------------------------------------

// RELATES_TO: bidirectional conceptual link
MATCH (h1:Hexad {id: 'hexad-test-001'}), (h2:Hexad {id: 'hexad-test-002'})
MERGE (h1)-[r1:RELATES_TO]->(h2)
SET r1.weight = 0.85, r1.since = datetime() - duration('P1D');

MATCH (h2:Hexad {id: 'hexad-test-002'}), (h1:Hexad {id: 'hexad-test-001'})
MERGE (h2)-[r2:RELATES_TO]->(h1)
SET r2.weight = 0.85, r2.since = datetime() - duration('P1D');

// CITES: directed citation
MATCH (h1:Hexad {id: 'hexad-test-001'}), (h3:Hexad {id: 'hexad-test-003'})
MERGE (h1)-[c1:CITES]->(h3)
SET c1.weight = 0.72, c1.context = 'normalisation reference';

// PART_OF: concept containment
MATCH (h1:Hexad {id: 'hexad-test-001'}), (h4:Hexad {id: 'hexad-test-004'})
MERGE (h1)-[p1:PART_OF]->(h4)
SET p1.role = 'consistency-component';

MATCH (h2:Hexad {id: 'hexad-test-002'}), (h4:Hexad {id: 'hexad-test-004'})
MERGE (h2)-[p2:PART_OF]->(h4)
SET p2.role = 'drift-detection-component';

MATCH (h3:Hexad {id: 'hexad-test-003'}), (h4:Hexad {id: 'hexad-test-004'})
MERGE (h3)-[p3:PART_OF]->(h4)
SET p3.role = 'normalisation-component';

// ---------------------------------------------------------------------------
// Provenance chain
// ---------------------------------------------------------------------------

// Provenance events for hexad-test-001
MERGE (pe1:ProvenanceEvent {event_id: 'prov-001-create'})
SET pe1.hexad_id = 'hexad-test-001',
    pe1.event_type = 'created',
    pe1.actor = 'test-seed-script',
    pe1.timestamp = datetime() - duration('P1D'),
    pe1.hash = 'sha256:a1b2c3d4e5f6',
    pe1.details = 'Initial creation via neo4j-init.cypher';

MERGE (pe2:ProvenanceEvent {event_id: 'prov-001-update-vector'})
SET pe2.hexad_id = 'hexad-test-001',
    pe2.event_type = 'modality_updated',
    pe2.actor = 'test-seed-script',
    pe2.timestamp = datetime() - duration('PT1H'),
    pe2.hash = 'sha256:f6e5d4c3b2a1',
    pe2.details = 'Vector embedding regenerated';

// Chain provenance events in order
MATCH (h1:Hexad {id: 'hexad-test-001'}), (pe1:ProvenanceEvent {event_id: 'prov-001-create'})
MERGE (h1)-[:HAS_PROVENANCE]->(pe1);

MATCH (pe1:ProvenanceEvent {event_id: 'prov-001-create'}),
      (pe2:ProvenanceEvent {event_id: 'prov-001-update-vector'})
MERGE (pe1)-[:FOLLOWED_BY]->(pe2);

MATCH (h1:Hexad {id: 'hexad-test-001'}), (pe2:ProvenanceEvent {event_id: 'prov-001-update-vector'})
MERGE (h1)-[:HAS_PROVENANCE]->(pe2);

// ---------------------------------------------------------------------------
// Semantic type nodes (ontology)
// ---------------------------------------------------------------------------

MERGE (t1:OntologyType {uri: 'http://schema.org/Article'})
SET t1.label = 'Article';

MERGE (t2:OntologyType {uri: 'http://schema.org/TechArticle'})
SET t2.label = 'TechArticle';

MERGE (t3:OntologyType {uri: 'http://verisimdb.org/ontology/Entity'})
SET t3.label = 'VeriSimDB Entity';

// Type relationships
MATCH (h1:Hexad {id: 'hexad-test-001'}), (t1:OntologyType {uri: 'http://schema.org/Article'})
MERGE (h1)-[:IS_TYPE]->(t1);

MATCH (h1:Hexad {id: 'hexad-test-001'}), (t3:OntologyType {uri: 'http://verisimdb.org/ontology/Entity'})
MERGE (h1)-[:IS_TYPE]->(t3);

MATCH (h2:Hexad {id: 'hexad-test-002'}), (t2:OntologyType {uri: 'http://schema.org/TechArticle'})
MERGE (h2)-[:IS_TYPE]->(t2);

// TechArticle is subclass of Article
MATCH (t2:OntologyType {uri: 'http://schema.org/TechArticle'}),
      (t1:OntologyType {uri: 'http://schema.org/Article'})
MERGE (t2)-[:SUBCLASS_OF]->(t1);
