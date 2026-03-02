// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Test Infrastructure — MongoDB Seed Script
//
// Creates the verisimdb database with a hexads collection and supporting
// indexes. Inserts test hexad documents with multiple modalities (text,
// vector, spatial, temporal) to exercise the MongoDB federation adapter.
//
// This script runs automatically via the /docker-entrypoint-initdb.d/
// mechanism on first container startup.
//
// Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

// ---------------------------------------------------------------------------
// Initialise replica set (required for change streams)
// ---------------------------------------------------------------------------

try {
    rs.initiate({
        _id: "rs0",
        members: [{ _id: 0, host: "localhost:27017" }],
    });
    print("Replica set rs0 initiated.");
} catch (e) {
    // Already initialised — ignore
    print("Replica set already initialised or error: " + e.message);
}

// Wait for the replica set to become ready
let ready = false;
for (let attempt = 0; attempt < 30; attempt++) {
    try {
        const status = rs.status();
        if (status.myState === 1) {
            ready = true;
            break;
        }
    } catch (_e) {
        // Not ready yet
    }
    sleep(1000);
}

if (!ready) {
    print("WARNING: Replica set did not become PRIMARY within 30 seconds.");
}

// ---------------------------------------------------------------------------
// Switch to verisimdb database
// ---------------------------------------------------------------------------

const db = db.getSiblingDB("verisimdb");

// ---------------------------------------------------------------------------
// Create collections
// ---------------------------------------------------------------------------

db.createCollection("hexads");
db.createCollection("drift_scores");
db.createCollection("provenance_events");

print("Collections created: hexads, drift_scores, provenance_events");

// ---------------------------------------------------------------------------
// Create indexes on hexads collection
// ---------------------------------------------------------------------------

// Unique index on hexad ID
db.hexads.createIndex({ id: 1 }, { unique: true, name: "idx_hexad_id" });

// Index on modality type for filtered queries
db.hexads.createIndex(
    { "modalities.type": 1 },
    { name: "idx_modality_type" },
);

// Text index on document modality content (full-text search)
db.hexads.createIndex(
    { "modalities.data.content": "text", "modalities.data.title": "text" },
    { name: "idx_fulltext_content", default_language: "english" },
);

// 2dsphere index on spatial modality location (geospatial queries)
db.hexads.createIndex(
    { "modalities.data.location": "2dsphere" },
    { name: "idx_spatial_location" },
);

// Compound index on created_at + updated_at for temporal queries
db.hexads.createIndex(
    { created_at: -1, updated_at: -1 },
    { name: "idx_temporal" },
);

// Index on drift scores collection
db.drift_scores.createIndex(
    { hexad_id: 1, measured_at: -1 },
    { name: "idx_drift_hexad_time" },
);

// Index on provenance events
db.provenance_events.createIndex(
    { hexad_id: 1, timestamp: -1 },
    { name: "idx_provenance_hexad_time" },
);

print("Indexes created on hexads, drift_scores, provenance_events");

// ---------------------------------------------------------------------------
// Insert test hexad documents
// ---------------------------------------------------------------------------

const now = new Date();
const oneHourAgo = new Date(now.getTime() - 3600 * 1000);
const oneDayAgo = new Date(now.getTime() - 86400 * 1000);

db.hexads.insertMany([
    {
        id: "hexad-test-001",
        created_at: oneDayAgo,
        updated_at: now,
        version: 3,
        modalities: [
            {
                type: "document",
                data: {
                    title: "Introduction to Cross-Modal Consistency",
                    content:
                        "VeriSimDB maintains consistency across 8 modality representations. " +
                        "Each entity exists simultaneously as graph, vector, tensor, semantic, " +
                        "document, temporal, provenance, and spatial data.",
                    format: "text/plain",
                },
            },
            {
                type: "vector",
                data: {
                    embedding: Array.from({ length: 128 }, (_, i) =>
                        Math.sin(i * 0.1),
                    ),
                    model: "test-embedding-v1",
                    dimensions: 128,
                },
            },
            {
                type: "spatial",
                data: {
                    location: {
                        type: "Point",
                        coordinates: [-0.1278, 51.5074], // London
                    },
                    radius_km: 5.0,
                },
            },
            {
                type: "temporal",
                data: {
                    valid_from: oneDayAgo,
                    valid_to: null,
                    version_history: [
                        { version: 1, timestamp: oneDayAgo, action: "created" },
                        {
                            version: 2,
                            timestamp: oneHourAgo,
                            action: "updated_vector",
                        },
                        {
                            version: 3,
                            timestamp: now,
                            action: "updated_document",
                        },
                    ],
                },
            },
            {
                type: "graph",
                data: {
                    types: [
                        "http://schema.org/Article",
                        "http://verisimdb.org/ontology/Entity",
                    ],
                    relationships: [
                        {
                            predicate: "relates_to",
                            target: "hexad-test-002",
                            weight: 0.85,
                        },
                        {
                            predicate: "cites",
                            target: "hexad-test-003",
                            weight: 0.72,
                        },
                    ],
                },
            },
            {
                type: "provenance",
                data: {
                    origin: "manual-import",
                    actor: "test-seed-script",
                    chain: [
                        {
                            hash: "sha256:a1b2c3d4e5f6",
                            action: "created",
                            timestamp: oneDayAgo,
                        },
                    ],
                },
            },
        ],
    },
    {
        id: "hexad-test-002",
        created_at: oneDayAgo,
        updated_at: oneHourAgo,
        version: 1,
        modalities: [
            {
                type: "document",
                data: {
                    title: "Drift Detection Algorithms",
                    content:
                        "Drift is measured as divergence between modalities using cosine " +
                        "similarity for vectors, Jaccard distance for sets, and temporal " +
                        "decay functions for time-series data.",
                    format: "text/plain",
                },
            },
            {
                type: "vector",
                data: {
                    embedding: Array.from({ length: 128 }, (_, i) =>
                        Math.cos(i * 0.1),
                    ),
                    model: "test-embedding-v1",
                    dimensions: 128,
                },
            },
            {
                type: "spatial",
                data: {
                    location: {
                        type: "Point",
                        coordinates: [-73.9857, 40.7484], // New York
                    },
                    radius_km: 10.0,
                },
            },
            {
                type: "graph",
                data: {
                    types: ["http://schema.org/TechArticle"],
                    relationships: [
                        {
                            predicate: "relates_to",
                            target: "hexad-test-001",
                            weight: 0.85,
                        },
                    ],
                },
            },
        ],
    },
    {
        id: "hexad-test-003",
        created_at: now,
        updated_at: now,
        version: 1,
        modalities: [
            {
                type: "document",
                data: {
                    title: "Self-Normalisation Process",
                    content:
                        "When drift exceeds configurable thresholds, the normaliser identifies " +
                        "the most authoritative modality, regenerates drifted representations, " +
                        "validates consistency, and updates all modalities atomically.",
                    format: "text/plain",
                },
            },
            {
                type: "vector",
                data: {
                    embedding: Array.from({ length: 128 }, (_, i) =>
                        Math.sin(i * 0.2) + Math.cos(i * 0.3),
                    ),
                    model: "test-embedding-v1",
                    dimensions: 128,
                },
            },
            {
                type: "semantic",
                data: {
                    categories: ["normalisation", "consistency", "drift"],
                    confidence: 0.92,
                    proof_blob: "cbor:test-placeholder",
                },
            },
        ],
    },
]);

print("Inserted 3 test hexad documents");

// ---------------------------------------------------------------------------
// Insert test drift scores
// ---------------------------------------------------------------------------

db.drift_scores.insertMany([
    {
        hexad_id: "hexad-test-001",
        measured_at: now,
        scores: {
            semantic_vector_drift: 0.12,
            graph_document_drift: 0.05,
            temporal_consistency_drift: 0.02,
            tensor_drift: 0.0,
            schema_drift: 0.0,
            quality_drift: 0.08,
        },
        overall: 0.045,
        status: "healthy",
    },
    {
        hexad_id: "hexad-test-002",
        measured_at: now,
        scores: {
            semantic_vector_drift: 0.45,
            graph_document_drift: 0.32,
            temporal_consistency_drift: 0.15,
            tensor_drift: 0.0,
            schema_drift: 0.08,
            quality_drift: 0.28,
        },
        overall: 0.213,
        status: "drifted",
    },
]);

print("Inserted 2 test drift score documents");

// ---------------------------------------------------------------------------
// Insert test provenance events
// ---------------------------------------------------------------------------

db.provenance_events.insertMany([
    {
        hexad_id: "hexad-test-001",
        event_type: "created",
        timestamp: oneDayAgo,
        actor: "test-seed-script",
        details: { source: "mongodb-init.js", method: "direct-insert" },
    },
    {
        hexad_id: "hexad-test-001",
        event_type: "modality_updated",
        timestamp: now,
        actor: "test-seed-script",
        details: { modality: "vector", reason: "embedding regenerated" },
    },
]);

print("Inserted 2 test provenance events");
print("MongoDB seed complete.");
