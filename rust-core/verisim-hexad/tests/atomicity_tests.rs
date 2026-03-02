// SPDX-License-Identifier: PMPL-1.0-or-later
//! Atomicity tests for VeriSimDB hexad operations.
//!
//! Verifies that cross-modal write operations are atomic: either all modality
//! writes succeed and are committed, or all are rolled back with no partial
//! state left behind. These tests exercise the [`TransactionManager`]
//! integration in [`InMemoryHexadStore`].

use std::sync::Arc;
use verisim_hexad::{
    HexadBuilder, HexadConfig, HexadId, HexadStore, InMemoryHexadStore,
};
use verisim_document::TantivyDocumentStore;
use verisim_graph::SimpleGraphStore;
use verisim_provenance::InMemoryProvenanceStore;
use verisim_semantic::InMemorySemanticStore;
use verisim_spatial::InMemorySpatialStore;
use verisim_temporal::InMemoryVersionStore;
use verisim_tensor::InMemoryTensorStore;
use verisim_vector::{BruteForceVectorStore, DistanceMetric};

type TestHexadStore = InMemoryHexadStore<
    SimpleGraphStore,
    BruteForceVectorStore,
    TantivyDocumentStore,
    InMemoryTensorStore,
    InMemorySemanticStore,
    InMemoryVersionStore<verisim_hexad::HexadSnapshot>,
    InMemoryProvenanceStore,
    InMemorySpatialStore,
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
        Arc::new(InMemoryProvenanceStore::new()),
        Arc::new(InMemorySpatialStore::new()),
    )
}

// ===========================================================================
// Create atomicity tests
// ===========================================================================

#[tokio::test]
async fn test_create_all_modalities_committed() {
    // When a create with all 8 modalities succeeds, all modality statuses
    // must be true and the transaction must be committed.
    let store = create_test_store(3);

    let input = HexadBuilder::new()
        .with_document("Atomicity Test", "All modalities populated")
        .with_embedding(vec![0.1, 0.2, 0.3])
        .with_tensor(vec![2, 2], vec![1.0, 2.0, 3.0, 4.0])
        .with_types(vec!["https://example.org/AtomicEntity"])
        .with_relationships(vec![("related_to", "other-entity")])
        .with_provenance("created", "test-actor", "Atomicity test creation")
        .with_spatial(51.5074, -0.1278) // London
        .build();

    let hexad = store.create(input).await.unwrap();

    // All 8 modalities should be populated
    let status = &hexad.status.modality_status;
    assert!(status.graph, "Graph modality should be populated");
    assert!(status.vector, "Vector modality should be populated");
    assert!(status.document, "Document modality should be populated");
    assert!(status.tensor, "Tensor modality should be populated");
    assert!(status.semantic, "Semantic modality should be populated");
    assert!(status.temporal, "Temporal modality should be populated");
    assert!(status.provenance, "Provenance modality should be populated");
    assert!(status.spatial, "Spatial modality should be populated");
    assert!(status.is_complete(), "All modalities should be complete");

    // Entity must be retrievable
    let retrieved = store.get(&hexad.id).await.unwrap();
    assert!(retrieved.is_some(), "Created hexad must be retrievable");

    // Transaction manager should have no active transactions after commit
    assert_eq!(
        store.transaction_manager().active_count().await,
        0,
        "No transactions should be active after successful create"
    );
}

#[tokio::test]
async fn test_create_vector_dimension_mismatch_rolls_back() {
    // When a create fails due to vector dimension mismatch, all previously
    // written modalities must be rolled back — no partial state.
    let store = create_test_store(3); // Store expects 3-dim vectors

    let input = HexadBuilder::new()
        .with_document("Should Be Rolled Back", "This document must not persist")
        .with_embedding(vec![0.1, 0.2]) // WRONG: 2 dimensions instead of 3
        .build();

    let result = store.create(input).await;
    assert!(result.is_err(), "Create with wrong vector dimension should fail");

    // Verify no hexads exist (the document write should have been rolled back)
    let all = store.list(100, 0).await.unwrap();
    assert!(
        all.is_empty(),
        "No hexads should exist after failed create — rollback must clean up"
    );

    // Transaction manager should have no active transactions
    assert_eq!(
        store.transaction_manager().active_count().await,
        0,
        "No transactions should be active after rollback"
    );
}

#[tokio::test]
async fn test_create_partial_modalities_succeeds() {
    // A create with only some modalities should succeed and only mark
    // those modalities as populated.
    let store = create_test_store(3);

    let input = HexadBuilder::new()
        .with_document("Partial Create", "Only document and temporal")
        .build();

    let hexad = store.create(input).await.unwrap();

    assert!(hexad.status.modality_status.document);
    assert!(hexad.status.modality_status.temporal);
    assert!(!hexad.status.modality_status.graph);
    assert!(!hexad.status.modality_status.vector);
    assert!(!hexad.status.modality_status.tensor);
    assert!(!hexad.status.modality_status.semantic);
    assert!(!hexad.status.modality_status.provenance);
    assert!(!hexad.status.modality_status.spatial);
}

// ===========================================================================
// Update atomicity tests
// ===========================================================================

#[tokio::test]
async fn test_update_all_modalities_committed() {
    // After a successful update, the hexad must reflect the new data and
    // the version must be incremented.
    let store = create_test_store(3);

    let create_input = HexadBuilder::new()
        .with_document("Original Title", "Original body")
        .with_embedding(vec![1.0, 0.0, 0.0])
        .build();

    let hexad = store.create(create_input).await.unwrap();
    assert_eq!(hexad.status.version, 1);

    let update_input = HexadBuilder::new()
        .with_document("Updated Title", "Updated body")
        .with_embedding(vec![0.0, 1.0, 0.0])
        .with_provenance("modified", "test-actor", "Update test")
        .build();

    let updated = store.update(&hexad.id, update_input).await.unwrap();
    assert_eq!(updated.status.version, 2);
    assert!(updated.status.modality_status.document);
    assert!(updated.status.modality_status.vector);
    assert!(updated.status.modality_status.provenance);

    // Document should reflect the update
    assert!(updated.document.as_ref().unwrap().title.contains("Updated"));
}

#[tokio::test]
async fn test_update_nonexistent_fails() {
    // Updating a nonexistent entity must return NotFound, not create a new one.
    let store = create_test_store(3);

    let fake_id = HexadId::new("nonexistent-id");
    let input = HexadBuilder::new()
        .with_document("Should Fail", "Entity does not exist")
        .build();

    let result = store.update(&fake_id, input).await;
    assert!(result.is_err(), "Update of nonexistent entity should fail");
}

#[tokio::test]
async fn test_update_with_invalid_vector_dimension_rolls_back() {
    // If an update fails (e.g., wrong vector dimension), the entity must
    // retain its pre-update state.
    let store = create_test_store(3);

    let create_input = HexadBuilder::new()
        .with_document("Original", "Should survive failed update")
        .with_embedding(vec![1.0, 0.0, 0.0])
        .build();

    let hexad = store.create(create_input).await.unwrap();

    // Attempt update with wrong vector dimension
    let bad_update = HexadBuilder::new()
        .with_embedding(vec![0.1, 0.2]) // WRONG: 2 dimensions instead of 3
        .build();

    let result = store.update(&hexad.id, bad_update).await;
    assert!(result.is_err(), "Update with wrong vector dimension should fail");

    // Original entity should still be intact
    let original = store.get(&hexad.id).await.unwrap().unwrap();
    assert_eq!(original.status.version, 1, "Version should not change on failed update");
    assert!(
        original.document.as_ref().unwrap().title.contains("Original"),
        "Original data should survive failed update"
    );
}

// ===========================================================================
// Delete atomicity tests
// ===========================================================================

#[tokio::test]
async fn test_delete_removes_entity() {
    let store = create_test_store(3);

    let input = HexadBuilder::new()
        .with_document("To Delete", "Will be removed")
        .with_embedding(vec![0.5, 0.5, 0.5])
        .build();

    let hexad = store.create(input).await.unwrap();
    assert!(store.get(&hexad.id).await.unwrap().is_some());

    store.delete(&hexad.id).await.unwrap();
    assert!(
        store.get(&hexad.id).await.unwrap().is_none(),
        "Entity should not exist after delete"
    );
}

#[tokio::test]
async fn test_delete_nonexistent_fails() {
    let store = create_test_store(3);
    let fake_id = HexadId::new("does-not-exist");

    let result = store.delete(&fake_id).await;
    assert!(result.is_err(), "Delete of nonexistent entity should fail");
}

// ===========================================================================
// Transaction manager state tests
// ===========================================================================

#[tokio::test]
async fn test_transaction_manager_integrated() {
    // Verify the transaction manager is accessible and functional through
    // the store's public API.
    let store = create_test_store(3);
    let txn_mgr = store.transaction_manager();

    // Initially no active transactions
    assert_eq!(txn_mgr.active_count().await, 0);

    // Create a hexad — should begin and commit a transaction
    let input = HexadBuilder::new()
        .with_document("TxnTest", "Transaction manager test")
        .build();
    store.create(input).await.unwrap();

    // After create, no transactions should be active
    assert_eq!(txn_mgr.active_count().await, 0);
}

#[tokio::test]
async fn test_transaction_modality_versions_increment() {
    // After a create + update, the MVCC version for each written modality
    // should reflect the number of writes.
    let store = create_test_store(3);
    let txn_mgr = store.transaction_manager();

    let input = HexadBuilder::new()
        .with_document("Version Test", "Version tracking")
        .with_embedding(vec![0.1, 0.2, 0.3])
        .build();

    let hexad = store.create(input).await.unwrap();
    let entity_id = hexad.id.as_str();

    // After create, document and vector should have version 1
    let doc_v = txn_mgr.current_version(entity_id, "document").await;
    let vec_v = txn_mgr.current_version(entity_id, "vector").await;
    assert_eq!(doc_v, 1, "Document MVCC version should be 1 after create");
    assert_eq!(vec_v, 1, "Vector MVCC version should be 1 after create");

    // Update the document
    let update = HexadBuilder::new()
        .with_document("Updated Version Test", "Version 2")
        .build();
    store.update(&hexad.id, update).await.unwrap();

    let doc_v2 = txn_mgr.current_version(entity_id, "document").await;
    assert_eq!(doc_v2, 2, "Document MVCC version should be 2 after update");

    // Vector was not updated, so its version should still be 1
    let vec_v2 = txn_mgr.current_version(entity_id, "vector").await;
    assert_eq!(vec_v2, 1, "Vector MVCC version should still be 1");
}

// ===========================================================================
// Concurrent write serialization test
// ===========================================================================

#[tokio::test]
async fn test_concurrent_creates_succeed() {
    // Multiple concurrent creates to different entities should all succeed.
    // This verifies that the locking mechanism does not over-serialize.
    let store = Arc::new(create_test_store(3));

    let mut handles = Vec::new();
    for i in 0..10 {
        let store_clone = Arc::clone(&store);
        handles.push(tokio::spawn(async move {
            let input = HexadBuilder::new()
                .with_document(&format!("Concurrent-{i}"), &format!("Body {i}"))
                .with_embedding(vec![i as f32 * 0.1, 0.5, 0.5])
                .build();
            store_clone.create(input).await
        }));
    }

    let mut successes = 0;
    for handle in handles {
        if handle.await.unwrap().is_ok() {
            successes += 1;
        }
    }

    assert_eq!(successes, 10, "All 10 concurrent creates should succeed");

    let all = store.list(100, 0).await.unwrap();
    assert_eq!(all.len(), 10, "All 10 hexads should be stored");
}
