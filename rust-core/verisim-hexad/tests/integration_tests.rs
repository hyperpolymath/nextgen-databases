// SPDX-License-Identifier: PMPL-1.0-or-later
//! Integration tests for VeriSimDB
//!
//! Tests cross-modal consistency and end-to-end workflows.
//! Persistence tests are gated behind `#[ignore]` until store serialization is implemented.

use std::sync::Arc;
use verisim_hexad::{
    HexadBuilder, HexadConfig, HexadStore, InMemoryHexadStore,
};
use verisim_document::TantivyDocumentStore;
use verisim_graph::SimpleGraphStore;
use verisim_semantic::InMemorySemanticStore;
use verisim_temporal::InMemoryVersionStore;
use verisim_tensor::InMemoryTensorStore;
use verisim_vector::{BruteForceVectorStore, DistanceMetric, VectorStore as _};

type TestHexadStore = InMemoryHexadStore<
    SimpleGraphStore,
    BruteForceVectorStore,
    TantivyDocumentStore,
    InMemoryTensorStore,
    InMemorySemanticStore,
    InMemoryVersionStore<verisim_hexad::HexadSnapshot>,
    verisim_provenance::InMemoryProvenanceStore,
    verisim_spatial::InMemorySpatialStore,
>;

fn create_test_store(vector_dim: usize) -> TestHexadStore {
    let config = HexadConfig {
        vector_dimension: vector_dim,
        ..Default::default()
    };

    InMemoryHexadStore::new(
        config,
        Arc::new(SimpleGraphStore::in_memory().unwrap()),
        Arc::new(BruteForceVectorStore::new(vector_dim, DistanceMetric::Cosine)),
        Arc::new(TantivyDocumentStore::in_memory().unwrap()),
        Arc::new(InMemoryTensorStore::new()),
        Arc::new(InMemorySemanticStore::new()),
        Arc::new(InMemoryVersionStore::new()),
        Arc::new(verisim_provenance::InMemoryProvenanceStore::new()),
        Arc::new(verisim_spatial::InMemorySpatialStore::new()),
    )
}

/// Test that all six modalities are properly synchronized
#[tokio::test]
async fn test_cross_modal_consistency() {
    let store = create_test_store(128);

    // Create a hexad with all modalities populated
    let input = HexadBuilder::new()
        .with_document("Cross-Modal Test", "Testing all modalities together")
        .with_embedding(vec![0.1; 128])
        .with_tensor(vec![2, 2], vec![1.0, 2.0, 3.0, 4.0])
        .with_types(vec!["https://example.org/TestType"])
        .with_relationships(vec![("relatedTo", "other-entity")])
        .build();

    let hexad = store.create(input).await.unwrap();

    // Verify all modalities are populated
    let status = &hexad.status.modality_status;
    assert!(status.graph, "Graph modality should be populated");
    assert!(status.vector, "Vector modality should be populated");
    assert!(status.tensor, "Tensor modality should be populated");
    assert!(status.semantic, "Semantic modality should be populated");
    assert!(status.document, "Document modality should be populated");
    assert!(status.temporal, "Temporal modality should be populated");

    // Verify the hexad can be retrieved
    let retrieved = store.get(&hexad.id).await.unwrap();
    assert!(retrieved.is_some(), "Hexad should be retrievable");

    let retrieved = retrieved.unwrap();
    assert_eq!(retrieved.id, hexad.id);
    assert!(retrieved.embedding.is_some());
    assert!(retrieved.tensor.is_some());
    assert!(retrieved.semantic.is_some());
    assert!(retrieved.document.is_some());
}

/// Test vector similarity search
#[tokio::test]
async fn test_vector_similarity_search() {
    let store = create_test_store(3);

    // Create entities with different embeddings
    let inputs = vec![
        (vec![1.0, 0.0, 0.0], "X-axis aligned"),
        (vec![0.9, 0.1, 0.0], "Near X-axis"),
        (vec![0.0, 1.0, 0.0], "Y-axis aligned"),
        (vec![0.0, 0.0, 1.0], "Z-axis aligned"),
    ];

    for (embedding, title) in &inputs {
        let input = HexadBuilder::new()
            .with_document(title, &format!("Entity at {:?}", embedding))
            .with_embedding(embedding.clone())
            .build();
        store.create(input).await.unwrap();
    }

    // Search for entities similar to X-axis
    let results = store.search_similar(&[1.0, 0.0, 0.0], 2).await.unwrap();
    assert_eq!(results.len(), 2);

    // The two closest should be X-axis and near-X-axis
    let titles: Vec<_> = results
        .iter()
        .filter_map(|h| h.document.as_ref().map(|d| d.title.as_str()))
        .collect();

    assert!(
        titles.contains(&"X-axis aligned") || titles.contains(&"Near X-axis"),
        "Search results should include X-axis or near-X-axis entities"
    );
}

/// Test full-text search across documents
#[tokio::test]
async fn test_full_text_search() {
    let store = create_test_store(3);

    // Create entities with different content
    let docs = vec![
        ("Rust Programming", "Rust is a systems programming language focused on safety"),
        ("Python Guide", "Python is a high-level programming language"),
        ("Database Design", "Relational databases use SQL for querying"),
    ];

    for (title, body) in &docs {
        let input = HexadBuilder::new()
            .with_document(title, body)
            .with_embedding(vec![0.1, 0.2, 0.3])
            .build();
        store.create(input).await.unwrap();
    }

    // Search for "Rust"
    let results = store.search_text("Rust", 10).await.unwrap();
    assert_eq!(results.len(), 1);
    assert!(results[0].document.as_ref().unwrap().title.contains("Rust"));

    // Search for "programming" - should match multiple
    let results = store.search_text("programming", 10).await.unwrap();
    assert!(results.len() >= 2, "Should match at least 2 programming docs");
}

/// Test temporal versioning
#[tokio::test]
async fn test_versioning() {
    let store = create_test_store(3);

    // Create initial entity
    let input = HexadBuilder::new()
        .with_document("Version 1", "Initial content")
        .with_embedding(vec![0.1, 0.2, 0.3])
        .build();

    let hexad = store.create(input).await.unwrap();
    assert_eq!(hexad.status.version, 1);

    // Update the entity
    let update1 = HexadBuilder::new()
        .with_document("Version 2", "Updated content")
        .build();

    let updated = store.update(&hexad.id, update1).await.unwrap();
    assert_eq!(updated.status.version, 2);

    // Update again
    let update2 = HexadBuilder::new()
        .with_document("Version 3", "Final content")
        .build();

    let updated = store.update(&hexad.id, update2).await.unwrap();
    assert_eq!(updated.status.version, 3);
    assert_eq!(updated.version_count, 3);
}

/// Test CRUD operations
#[tokio::test]
async fn test_crud_operations() {
    let store = create_test_store(3);

    // Create
    let input = HexadBuilder::new()
        .with_document("Test Entity", "Test body")
        .with_embedding(vec![0.1, 0.2, 0.3])
        .build();

    let hexad = store.create(input).await.unwrap();
    let id = hexad.id.clone();

    // Read
    let retrieved = store.get(&id).await.unwrap();
    assert!(retrieved.is_some());

    // Update
    let update_input = HexadBuilder::new()
        .with_document("Updated Entity", "Updated body")
        .build();

    let updated = store.update(&id, update_input).await.unwrap();
    assert!(updated.document.as_ref().unwrap().title.contains("Updated"));

    // Delete
    store.delete(&id).await.unwrap();

    // Verify deletion
    let deleted = store.get(&id).await.unwrap();
    assert!(deleted.is_none());
}

/// Test vector store persistence
/// Ignored: BruteForceVectorStore does not yet have save_to_file/load_from_file.
/// See SONNET-TASKS.md for the persistence implementation task.
#[tokio::test]
#[ignore = "persistence not yet implemented on BruteForceVectorStore"]
async fn test_vector_persistence() {
    let store = BruteForceVectorStore::new(64, DistanceMetric::Cosine);

    // Insert vectors
    for i in 0..20 {
        let mut vec = vec![0.0f32; 64];
        vec[i % 64] = 1.0;
        let embedding = verisim_vector::Embedding::new(format!("vec_{}", i), vec);
        store.upsert(&embedding).await.unwrap();
    }

    // TODO: Implement save_to_file/load_from_file on BruteForceVectorStore
    // store.save_to_file(temp_path).unwrap();
    // let loaded = BruteForceVectorStore::load_from_file(temp_path).unwrap();
    // assert_eq!(loaded.stats().total_vectors, 20);
}

/// Test tensor store persistence
/// Ignored: InMemoryTensorStore does not yet have save_to_file/load_from_file.
#[tokio::test]
#[ignore = "persistence not yet implemented on InMemoryTensorStore"]
async fn test_tensor_persistence() {
    use verisim_tensor::{Tensor, TensorStore as _};

    let store = InMemoryTensorStore::new();

    let t1 = Tensor::new("tensor_1", vec![2, 3], vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
    let t2 = Tensor::new("tensor_2", vec![3, 3], vec![1.0; 9]).unwrap();

    store.put(&t1).await.unwrap();
    store.put(&t2).await.unwrap();

    // TODO: Implement save_to_file/load_from_file on InMemoryTensorStore
    // store.save_to_file(temp_path).unwrap();
    // let loaded = InMemoryTensorStore::load_from_file(temp_path).unwrap();
}

/// Test semantic store persistence
/// Ignored: InMemorySemanticStore does not yet have save_to_file/load_from_file.
#[tokio::test]
#[ignore = "persistence not yet implemented on InMemorySemanticStore"]
async fn test_semantic_persistence() {
    use verisim_semantic::{SemanticStore as _, SemanticType, Constraint, ConstraintKind};

    let store = InMemorySemanticStore::new();

    let person_type = SemanticType::new("https://example.org/Person", "Person")
        .with_supertype("https://example.org/Entity")
        .with_constraint(Constraint {
            name: "name_required".to_string(),
            kind: ConstraintKind::Required("name".to_string()),
            message: "Person must have a name".to_string(),
        });

    store.register_type(&person_type).await.unwrap();

    // TODO: Implement save_to_file/load_from_file on InMemorySemanticStore
    // store.save_to_file(temp_path).unwrap();
    // let loaded = InMemorySemanticStore::load_from_file(temp_path).unwrap();
}

/// Test temporal store persistence
/// Ignored: InMemoryVersionStore does not yet have save_to_file/load_from_file.
#[tokio::test]
#[ignore = "persistence not yet implemented on InMemoryVersionStore"]
async fn test_temporal_persistence() {
    use verisim_temporal::TemporalStore as _;

    let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

    store.append("entity1", "v1 data".to_string(), "alice", Some("first")).await.unwrap();
    store.append("entity1", "v2 data".to_string(), "bob", Some("second")).await.unwrap();

    // TODO: Implement save_to_file/load_from_file on InMemoryVersionStore
    // store.save_to_file(temp_path).unwrap();
    // let loaded: InMemoryVersionStore<String> = InMemoryVersionStore::load_from_file(temp_path).unwrap();
}

/// Test that modality operations are isolated
#[tokio::test]
async fn test_modality_isolation() {
    let store = create_test_store(3);

    // Create entity with only document
    let input1 = HexadBuilder::new()
        .with_document("Doc Only", "Only document modality")
        .build();

    let h1 = store.create(input1).await.unwrap();
    assert!(h1.status.modality_status.document);
    assert!(!h1.status.modality_status.vector);
    assert!(!h1.status.modality_status.tensor);

    // Create entity with only vector
    let input2 = HexadBuilder::new()
        .with_embedding(vec![0.1, 0.2, 0.3])
        .build();

    let h2 = store.create(input2).await.unwrap();
    assert!(!h2.status.modality_status.document);
    assert!(h2.status.modality_status.vector);
    assert!(!h2.status.modality_status.tensor);

    // Verify searches don't cross-contaminate
    let doc_results = store.search_text("Only document", 10).await.unwrap();
    assert_eq!(doc_results.len(), 1);

    // Vector search should only find vector-enabled entities
    let vec_results = store.search_similar(&[0.1, 0.2, 0.3], 10).await.unwrap();
    // h2 has vector, h1 does not
    let vec_ids: Vec<_> = vec_results.iter().map(|h| h.id.as_str()).collect();
    assert!(vec_ids.contains(&h2.id.as_str()));
}

/// Test high-dimension vector search
#[tokio::test]
async fn test_high_dimension_vector_search() {
    let store = create_test_store(768); // BERT-like dimension

    // Create 50 entities with high-dimensional embeddings
    for i in 0..50 {
        let mut embedding = vec![0.0f32; 768];
        embedding[i % 768] = 1.0;
        embedding[(i * 7) % 768] = 0.5;

        let input = HexadBuilder::new()
            .with_document(&format!("Entity {}", i), &format!("High-dim entity number {}", i))
            .with_embedding(embedding)
            .build();

        store.create(input).await.unwrap();
    }

    // Search should complete even with high dimensions
    let mut query = vec![0.0f32; 768];
    query[0] = 1.0;

    let results = store.search_similar(&query, 5).await.unwrap();
    assert_eq!(results.len(), 5);
}
