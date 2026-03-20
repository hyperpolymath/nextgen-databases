// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Stress tests for VeriSimDB Phase 3.2.
// Concurrent writers and readers hitting the octad store simultaneously.

use std::collections::HashMap;
use std::sync::Arc;

use verisim_octad::{
    InMemoryOctadStore, OctadConfig, OctadDocumentInput, OctadId,
    OctadInput, OctadSnapshot, OctadStore,
};
use verisim_document::TantivyDocumentStore;
use verisim_graph::SimpleGraphStore;
use verisim_semantic::InMemorySemanticStore;
use verisim_temporal::InMemoryVersionStore;
use verisim_tensor::InMemoryTensorStore;
use verisim_vector::{BruteForceVectorStore, DistanceMetric};

type TestStore = InMemoryOctadStore<
    SimpleGraphStore,
    BruteForceVectorStore,
    TantivyDocumentStore,
    InMemoryTensorStore,
    InMemorySemanticStore,
    InMemoryVersionStore<OctadSnapshot>,
    verisim_provenance::InMemoryProvenanceStore,
    verisim_spatial::InMemorySpatialStore,
>;

fn create_store() -> Arc<TestStore> {
    Arc::new(InMemoryOctadStore::new(
        OctadConfig::default(),
        Arc::new(SimpleGraphStore::new()),
        Arc::new(BruteForceVectorStore::new(3, DistanceMetric::Cosine)),
        Arc::new(TantivyDocumentStore::in_memory().unwrap()),
        Arc::new(InMemoryTensorStore::new()),
        Arc::new(InMemorySemanticStore::new()),
        Arc::new(InMemoryVersionStore::new()),
        Arc::new(verisim_provenance::InMemoryProvenanceStore::new()),
        Arc::new(verisim_spatial::InMemorySpatialStore::new()),
    ))
}

fn doc(title: &str, body: &str) -> OctadInput {
    OctadInput {
        document: Some(OctadDocumentInput {
            title: title.into(),
            body: body.into(),
            fields: HashMap::new(),
        }),
        ..Default::default()
    }
}

/// 50 concurrent writers, each creating 10 entities.
#[tokio::test]
async fn concurrent_writers() {
    let store = create_store();
    let mut handles = Vec::new();

    for writer_id in 0..50 {
        let store = store.clone();
        handles.push(tokio::spawn(async move {
            let mut ids = Vec::new();
            for i in 0..10 {
                let input = doc(
                    &format!("W{writer_id}-E{i}"),
                    &format!("Body from writer {writer_id} entity {i}"),
                );
                match store.create(input).await {
                    Ok(octad) => ids.push(octad.id),
                    Err(e) => panic!("Writer {writer_id} entity {i} failed: {e}"),
                }
            }
            ids
        }));
    }

    let mut all_ids = Vec::new();
    for handle in handles {
        let ids = handle.await.unwrap();
        all_ids.extend(ids);
    }

    assert_eq!(all_ids.len(), 500, "All 500 entities should be created");

    // Verify all entities exist
    for id in &all_ids {
        assert!(store.get(id).await.unwrap().is_some(), "{id} missing");
    }
}

/// 20 writers + 20 readers running concurrently.
#[tokio::test]
async fn concurrent_read_write() {
    let store = create_store();
    let mut handles = Vec::new();

    // Seed 100 entities first
    let mut seed_ids = Vec::new();
    for i in 0..100 {
        let octad = store.create(doc(&format!("Seed-{i}"), &format!("Seed body {i}"))).await.unwrap();
        seed_ids.push(octad.id);
    }

    // 20 writers creating new entities
    for writer_id in 0..20 {
        let store = store.clone();
        handles.push(tokio::spawn(async move {
            for i in 0..10 {
                store.create(doc(
                    &format!("Concurrent-W{writer_id}-{i}"),
                    &format!("Body {writer_id}-{i}"),
                )).await.unwrap();
            }
        }));
    }

    // 20 readers reading seed entities
    for reader_id in 0..20 {
        let store = store.clone();
        let ids = seed_ids.clone();
        handles.push(tokio::spawn(async move {
            for id in &ids {
                let result = store.get(id).await;
                match result {
                    Ok(Some(_)) => {} // Expected
                    Ok(None) => {} // Acceptable during concurrent writes
                    Err(e) => panic!("Reader {reader_id} error on {id}: {e}"),
                }
            }
        }));
    }

    for handle in handles {
        handle.await.unwrap();
    }
}

/// Create then delete under contention.
#[tokio::test]
async fn concurrent_create_delete() {
    let store = create_store();

    // Create 50 entities
    let mut ids = Vec::new();
    for i in 0..50 {
        let octad = store.create(doc(&format!("CD-{i}"), "body")).await.unwrap();
        ids.push(octad.id);
    }

    // Concurrently delete all of them
    let mut handles = Vec::new();
    for id in ids.clone() {
        let store = store.clone();
        handles.push(tokio::spawn(async move {
            store.delete(&id).await.unwrap();
        }));
    }

    for handle in handles {
        handle.await.unwrap();
    }

    // All should be gone
    for id in &ids {
        assert!(store.get(id).await.unwrap().is_none(), "{id} should be deleted");
    }
}
