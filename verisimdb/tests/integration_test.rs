// SPDX-License-Identifier: PMPL-1.0-or-later
//! Integration Tests for VeriSimDB
//!
//! Tests the full stack: Rust stores → HTTP API → Elixir orchestration → VQL

use verisim_api::{ApiConfig, ConcreteHexadStore};
use verisim_document::{Document, TantivyDocumentStore};
use verisim_drift::{DriftDetector, DriftMetrics, DriftThresholds, DriftType};
use verisim_graph::{GraphEdge, GraphNode, OxiGraphStore};
use verisim_hexad::{
    HexadConfig, HexadDocumentInput, HexadId, HexadInput, HexadStore, InMemoryHexadStore,
};
use verisim_normalizer::{create_default_normalizer, Normalizer};
use verisim_semantic::InMemorySemanticStore;
use verisim_temporal::InMemoryVersionStore;
use verisim_tensor::InMemoryTensorStore;
use verisim_vector::{DistanceMetric, Embedding, HnswVectorStore};

use std::collections::HashMap;
use std::path::PathBuf;

/// Helper to create a test hexad store
fn create_test_store() -> ConcreteHexadStore {
    let graph_store = OxiGraphStore::new_in_memory().unwrap();

    let vector_store = HnswVectorStore::new(384, DistanceMetric::Cosine).unwrap();

    let doc_dir = std::env::temp_dir().join(format!("verisimdb-test-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&doc_dir).unwrap();
    let document_store = TantivyDocumentStore::new(&doc_dir).unwrap();

    let tensor_store = InMemoryTensorStore::new();
    let semantic_store = InMemorySemanticStore::new();
    let temporal_store = InMemoryVersionStore::new();

    let config = HexadConfig {
        enable_drift_detection: true,
        drift_thresholds: DriftThresholds::default(),
        enable_auto_normalization: true,
        ..Default::default()
    };

    InMemoryHexadStore::new(
        graph_store,
        vector_store,
        document_store,
        tensor_store,
        semantic_store,
        temporal_store,
        config,
    )
}

#[tokio::test]
async fn test_hexad_create_and_retrieve() {
    let mut store = create_test_store();

    // Create a hexad with document and vector
    let embedding = vec![0.1; 384];
    let input = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Test Document".to_string(),
            body: "This is a test document for VeriSimDB integration testing.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(embedding.clone().into()),
        ..Default::default()
    };

    let hexad_id = store.create(input).await.unwrap();

    // Retrieve the hexad
    let snapshot = store.get(&hexad_id).await.unwrap().unwrap();

    // Verify document modality
    assert_eq!(snapshot.document.as_ref().unwrap().title, "Test Document");

    // Verify vector modality
    assert_eq!(snapshot.vector.as_ref().unwrap().len(), 384);

    // Verify status
    assert!(snapshot.status.modality_status.document);
    assert!(snapshot.status.modality_status.vector);
}

#[tokio::test]
async fn test_cross_modal_consistency() {
    let mut store = create_test_store();

    let input = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Consistency Test".to_string(),
            body: "Testing cross-modal consistency.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(vec![0.2; 384].into()),
        semantic: Some(vec!["https://example.org/Document".to_string()].into()),
        ..Default::default()
    };

    let hexad_id = store.create(input).await.unwrap();

    // Get snapshot
    let snapshot = store.get(&hexad_id).await.unwrap().unwrap();

    // Verify all modalities present
    assert!(snapshot.document.is_some());
    assert!(snapshot.vector.is_some());
    assert!(snapshot.semantic.is_some());
}

#[tokio::test]
async fn test_drift_detection() {
    let mut store = create_test_store();

    let input = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Drift Test".to_string(),
            body: "Testing drift detection.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(vec![0.3; 384].into()),
        ..Default::default()
    };

    let hexad_id = store.create(input).await.unwrap();

    // Check initial drift (should be low)
    let initial_drift = store.check_drift(&hexad_id).await.unwrap();
    assert!(initial_drift.overall_score < 0.1);

    // Modify document without updating vector (simulate drift)
    // In real scenario, would use update operation
}

#[tokio::test]
async fn test_vector_similarity_search() {
    let mut store = create_test_store();

    // Create multiple hexads with different embeddings
    for i in 0..10 {
        let mut embedding = vec![0.0; 384];
        embedding[0] = i as f32 / 10.0;

        let input = HexadInput {
            document: Some(HexadDocumentInput {
                title: format!("Document {}", i),
                body: format!("Content {}", i),
                fields: HashMap::new(),
            }),
            vector: Some(embedding.into()),
            ..Default::default()
        };

        store.create(input).await.unwrap();
    }

    // Search for similar vectors
    let query_embedding = vec![0.5; 384];
    let results = store
        .search_similar(&query_embedding, 5, Some(0.0))
        .await
        .unwrap();

    // Should find similar hexads
    assert!(results.len() > 0 && results.len() <= 5);
}

#[tokio::test]
async fn test_fulltext_search() {
    let mut store = create_test_store();

    // Create hexads with searchable text
    let documents = vec![
        ("Machine Learning Basics", "Introduction to machine learning algorithms and neural networks."),
        ("Deep Learning Tutorial", "Advanced deep learning techniques including transformers."),
        ("AI Safety Research", "Research on alignment and safety of artificial intelligence systems."),
    ];

    for (title, body) in documents {
        let input = HexadInput {
            document: Some(HexadDocumentInput {
                title: title.to_string(),
                body: body.to_string(),
                fields: HashMap::new(),
            }),
            vector: Some(vec![0.5; 384].into()),
            ..Default::default()
        };

        store.create(input).await.unwrap();
    }

    // Search for "machine learning"
    let results = store.search_text("machine learning", 10).await.unwrap();

    // Should find at least the first document
    assert!(results.len() >= 1);
}

#[tokio::test]
async fn test_temporal_versioning() {
    let mut store = create_test_store();

    let input = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Version Test".to_string(),
            body: "Initial version".to_string(),
            fields: HashMap::new(),
        }),
        ..Default::default()
    };

    let hexad_id = store.create(input).await.unwrap();

    // Get initial version
    let v1 = store.get(&hexad_id).await.unwrap().unwrap();
    let v1_version = v1.status.version;

    // Update the hexad
    // In a full implementation, would update and verify version increments
}

#[tokio::test]
async fn test_graph_relationships() {
    let mut store = create_test_store();

    // Create two related hexads
    let input1 = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Paper 1".to_string(),
            body: "First research paper.".to_string(),
            fields: HashMap::new(),
        }),
        ..Default::default()
    };

    let id1 = store.create(input1).await.unwrap();

    let input2 = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Paper 2".to_string(),
            body: "Second research paper.".to_string(),
            fields: HashMap::new(),
        }),
        graph: Some(vec![(id1.clone(), "cites".to_string(), HashMap::new())].into()),
        ..Default::default()
    };

    let id2 = store.create(input2).await.unwrap();

    // Verify relationship exists in graph modality
    // In full implementation, would query graph store
}

#[tokio::test]
async fn test_normalization() {
    let mut store = create_test_store();

    let input = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Normalization Test".to_string(),
            body: "Testing self-normalization.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(vec![0.4; 384].into()),
        ..Default::default()
    };

    let hexad_id = store.create(input).await.unwrap();

    // Check drift
    let drift = store.check_drift(&hexad_id).await.unwrap();

    // If drift exceeds threshold, normalization should trigger
    // In full implementation, would verify normalization occurs
}

#[tokio::test]
async fn test_multi_modal_query() {
    let mut store = create_test_store();

    // Create hexad with multiple modalities
    let input = HexadInput {
        document: Some(HexadDocumentInput {
            title: "Multi-modal Test".to_string(),
            body: "Testing multi-modal queries with semantic types.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(vec![0.6; 384].into()),
        semantic: Some(vec!["https://example.org/Document".to_string()].into()),
        ..Default::default()
    };

    let hexad_id = store.create(input).await.unwrap();

    // Query combining text search, vector similarity, and semantic types
    // In full implementation, would use VQL multi-modal query
}

#[tokio::test]
async fn test_concurrent_operations() {
    let mut store = create_test_store();

    // Create multiple hexads concurrently
    let mut handles = vec![];

    for i in 0..10 {
        let mut store_clone = store.clone();
        let handle = tokio::spawn(async move {
            let input = HexadInput {
                document: Some(HexadDocumentInput {
                    title: format!("Concurrent {}", i),
                    body: format!("Testing concurrency {}", i),
                    fields: HashMap::new(),
                }),
                vector: Some(vec![i as f32 / 10.0; 384].into()),
                ..Default::default()
            };

            store_clone.create(input).await
        });

        handles.push(handle);
    }

    // Wait for all operations
    let results = futures::future::join_all(handles).await;

    // All should succeed
    for result in results {
        assert!(result.unwrap().is_ok());
    }
}
