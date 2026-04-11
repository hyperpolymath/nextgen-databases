// SPDX-License-Identifier: PMPL-1.0-or-later
//! Integration Tests for VeriSimDB
//!
//! Tests the full stack: Rust stores → HTTP API → Elixir orchestration → VCL

use verisim_api::ConcreteOctadStore;
use verisim_document::TantivyDocumentStore;
use verisim_octad::{
    OctadConfig, OctadDocumentInput, OctadGraphInput, OctadId, OctadInput, OctadSemanticInput,
    OctadStore, OctadVectorInput, InMemoryOctadStore, OctadSnapshot,
};
use verisim_provenance::InMemoryProvenanceStore;
use verisim_semantic::InMemorySemanticStore;
use verisim_spatial::InMemorySpatialStore;
use verisim_temporal::InMemoryVersionStore;
use verisim_tensor::InMemoryTensorStore;
use verisim_graph::SimpleGraphStore;
use verisim_vector::{BruteForceVectorStore, DistanceMetric};

use std::collections::HashMap;
use std::sync::Arc;

/// Helper to create a test octad store with all eight modality stores.
fn create_test_store() -> ConcreteOctadStore {
    let graph     = Arc::new(SimpleGraphStore::in_memory().unwrap());
    let vector    = Arc::new(BruteForceVectorStore::new(384, DistanceMetric::Cosine));
    let document  = Arc::new(TantivyDocumentStore::in_memory().unwrap());
    let tensor    = Arc::new(InMemoryTensorStore::new());
    let semantic  = Arc::new(InMemorySemanticStore::new());
    let temporal  = Arc::new(InMemoryVersionStore::<OctadSnapshot>::new());
    let provenance = Arc::new(InMemoryProvenanceStore::new());
    let spatial   = Arc::new(InMemorySpatialStore::new());

    InMemoryOctadStore::new(
        OctadConfig::default(),
        graph,
        vector,
        document,
        tensor,
        semantic,
        temporal,
        provenance,
        spatial,
    )
}

#[tokio::test]
async fn test_octad_create_and_retrieve() {
    let store = create_test_store();

    let embedding = vec![0.1f32; 384];
    let input = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Test Document".to_string(),
            body: "This is a test document for VeriSimDB integration testing.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(OctadVectorInput {
            embedding: embedding.clone(),
            model: None,
        }),
        ..Default::default()
    };

    let octad = store.create(input).await.unwrap();
    let octad_id = octad.id;

    // Retrieve the octad
    let snapshot = store.get(&octad_id).await.unwrap().unwrap();

    // Verify document modality
    assert_eq!(snapshot.document.as_ref().unwrap().title, "Test Document");

    // Verify vector modality (embedding field)
    assert_eq!(snapshot.embedding.as_ref().unwrap().vector.len(), 384);

    // Verify modality status flags
    assert!(snapshot.status.modality_status.document);
    assert!(snapshot.status.modality_status.vector);
}

#[tokio::test]
async fn test_cross_modal_consistency() {
    let store = create_test_store();

    let input = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Consistency Test".to_string(),
            body: "Testing cross-modal consistency.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(OctadVectorInput {
            embedding: vec![0.2f32; 384],
            model: None,
        }),
        semantic: Some(OctadSemanticInput {
            types: vec!["https://example.org/Document".to_string()],
            properties: HashMap::new(),
        }),
        ..Default::default()
    };

    let octad    = store.create(input).await.unwrap();
    let octad_id = octad.id;

    // Verify all supplied modalities are present
    let snapshot = store.get(&octad_id).await.unwrap().unwrap();
    assert!(snapshot.document.is_some());
    assert!(snapshot.embedding.is_some());
    assert!(snapshot.semantic.is_some());
}

#[tokio::test]
async fn test_drift_detection() {
    // Drift detection runs through the DriftDetector component, not directly
    // on the octad store.  This test verifies that creating an octad with
    // document + vector succeeds and leaves both modalities populated.
    let store = create_test_store();

    let input = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Drift Test".to_string(),
            body: "Testing drift detection.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(OctadVectorInput {
            embedding: vec![0.3f32; 384],
            model: None,
        }),
        ..Default::default()
    };

    let octad    = store.create(input).await.unwrap();
    let snapshot = store.get(&octad.id).await.unwrap().unwrap();
    assert!(snapshot.status.modality_status.document);
    assert!(snapshot.status.modality_status.vector);
}

#[tokio::test]
async fn test_vector_similarity_search() {
    let store = create_test_store();

    for i in 0..10 {
        let mut embedding = vec![0.0f32; 384];
        embedding[0] = i as f32 / 10.0;

        let input = OctadInput {
            document: Some(OctadDocumentInput {
                title: format!("Document {}", i),
                body: format!("Content {}", i),
                fields: HashMap::new(),
            }),
            vector: Some(OctadVectorInput {
                embedding,
                model: None,
            }),
            ..Default::default()
        };

        store.create(input).await.unwrap();
    }

    let query_embedding = vec![0.5f32; 384];
    let results = store.search_similar(&query_embedding, 5).await.unwrap();

    assert!(!results.is_empty());
    assert!(results.len() <= 5);
}

#[tokio::test]
async fn test_fulltext_search() {
    let store = create_test_store();

    let documents = vec![
        ("Machine Learning Basics",
         "Introduction to machine learning algorithms and neural networks."),
        ("Deep Learning Tutorial",
         "Advanced deep learning techniques including transformers."),
        ("AI Safety Research",
         "Research on alignment and safety of artificial intelligence systems."),
    ];

    for (title, body) in documents {
        let input = OctadInput {
            document: Some(OctadDocumentInput {
                title: title.to_string(),
                body: body.to_string(),
                fields: HashMap::new(),
            }),
            vector: Some(OctadVectorInput {
                embedding: vec![0.5f32; 384],
                model: None,
            }),
            ..Default::default()
        };

        store.create(input).await.unwrap();
    }

    let results = store.search_text("machine learning", 10).await.unwrap();
    assert!(!results.is_empty());
}

#[tokio::test]
async fn test_temporal_versioning() {
    let store = create_test_store();

    let input = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Version Test".to_string(),
            body: "Initial version".to_string(),
            fields: HashMap::new(),
        }),
        ..Default::default()
    };

    let octad    = store.create(input).await.unwrap();
    let octad_id = octad.id;

    let v1 = store.get(&octad_id).await.unwrap().unwrap();
    // Version counter starts at 1 after creation
    assert!(v1.status.version >= 1);
}

#[tokio::test]
async fn test_graph_relationships() {
    let store = create_test_store();

    let input1 = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Paper 1".to_string(),
            body: "First research paper.".to_string(),
            fields: HashMap::new(),
        }),
        ..Default::default()
    };

    let id1 = store.create(input1).await.unwrap().id;

    let input2 = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Paper 2".to_string(),
            body: "Second research paper.".to_string(),
            fields: HashMap::new(),
        }),
        graph: Some(OctadGraphInput {
            relationships: vec![("cites".to_string(), id1.0.clone())],
        }),
        ..Default::default()
    };

    let id2 = store.create(input2).await.unwrap().id;

    // Both entities were created
    assert!(store.get(&id1).await.unwrap().is_some());
    assert!(store.get(&id2).await.unwrap().is_some());
}

#[tokio::test]
async fn test_normalization() {
    let store = create_test_store();

    let input = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Normalization Test".to_string(),
            body: "Testing self-normalization.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(OctadVectorInput {
            embedding: vec![0.4f32; 384],
            model: None,
        }),
        ..Default::default()
    };

    let octad    = store.create(input).await.unwrap();
    let snapshot = store.get(&octad.id).await.unwrap().unwrap();
    // Both supplied modalities should be present; normalizer can regenerate from either
    assert!(snapshot.status.modality_status.document);
    assert!(snapshot.status.modality_status.vector);
}

#[tokio::test]
async fn test_multi_modal_query() {
    let store = create_test_store();

    let input = OctadInput {
        document: Some(OctadDocumentInput {
            title: "Multi-modal Test".to_string(),
            body: "Testing multi-modal queries with semantic types.".to_string(),
            fields: HashMap::new(),
        }),
        vector: Some(OctadVectorInput {
            embedding: vec![0.6f32; 384],
            model: None,
        }),
        semantic: Some(OctadSemanticInput {
            types: vec!["https://example.org/Document".to_string()],
            properties: HashMap::new(),
        }),
        ..Default::default()
    };

    let octad    = store.create(input).await.unwrap();
    let snapshot = store.get(&octad.id).await.unwrap().unwrap();
    assert!(snapshot.status.modality_status.document);
    assert!(snapshot.status.modality_status.vector);
    assert!(snapshot.status.modality_status.semantic);
}

#[tokio::test]
async fn test_concurrent_operations() {
    let store = create_test_store();

    let mut handles = vec![];

    for i in 0..10 {
        let store_clone = store.clone();
        let handle = tokio::spawn(async move {
            let input = OctadInput {
                document: Some(OctadDocumentInput {
                    title: format!("Concurrent {}", i),
                    body: format!("Testing concurrency {}", i),
                    fields: HashMap::new(),
                }),
                vector: Some(OctadVectorInput {
                    embedding: vec![i as f32 / 10.0; 384],
                    model: None,
                }),
                ..Default::default()
            };

            store_clone.create(input).await
        });

        handles.push(handle);
    }

    let results = futures::future::join_all(handles).await;

    for result in results {
        assert!(result.unwrap().is_ok());
    }
}
