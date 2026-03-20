// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Crash recovery integration tests for VeriSimDB Phase 1.4.

use std::collections::HashMap;
use std::sync::Arc;

use verisim_octad::{
    InMemoryOctadStore, OctadConfig, OctadInput, OctadDocumentInput,
    OctadSnapshot, OctadStore,
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

fn create_store(wal_dir: &str) -> TestStore {
    let config = OctadConfig::default();
    InMemoryOctadStore::new(
        config,
        Arc::new(SimpleGraphStore::new()),
        Arc::new(BruteForceVectorStore::new(3, DistanceMetric::Cosine)),
        Arc::new(TantivyDocumentStore::in_memory().unwrap()),
        Arc::new(InMemoryTensorStore::new()),
        Arc::new(InMemorySemanticStore::new()),
        Arc::new(InMemoryVersionStore::new()),
        Arc::new(verisim_provenance::InMemoryProvenanceStore::new()),
        Arc::new(verisim_spatial::InMemorySpatialStore::new()),
    )
    .with_wal(wal_dir, verisim_wal::SyncMode::Fsync)
    .expect("WAL init")
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

#[tokio::test]
async fn crash_recovery_single_entity() {
    let dir = tempfile::tempdir().unwrap();
    let wal = dir.path().join("wal");
    std::fs::create_dir_all(&wal).unwrap();

    let entity_id;
    {
        let store = create_store(wal.to_str().unwrap());
        let octad = store.create(doc("Test", "Survives crash")).await.unwrap();
        entity_id = octad.id;
        // Crash — no graceful_shutdown
    }

    {
        let store = create_store(wal.to_str().unwrap());
        let n: usize = store.replay_wal(&wal).await.unwrap();
        assert!(n > 0, "Should recover entity");
        assert!(store.get(&entity_id).await.unwrap().is_some());
    }
}

#[tokio::test]
async fn graceful_shutdown_then_restart() {
    let dir = tempfile::tempdir().unwrap();
    let wal = dir.path().join("wal");
    std::fs::create_dir_all(&wal).unwrap();

    let entity_id;
    {
        let store = create_store(wal.to_str().unwrap());
        let octad = store.create(doc("Graceful", "Clean")).await.unwrap();
        entity_id = octad.id;
        store.graceful_shutdown().await.unwrap();
    }

    {
        let store = create_store(wal.to_str().unwrap());
        let n: usize = store.replay_wal(&wal).await.unwrap();
        assert!(n > 0);
        assert!(store.get(&entity_id).await.unwrap().is_some());
    }
}

#[tokio::test]
async fn ten_entities_survive_crash() {
    let dir = tempfile::tempdir().unwrap();
    let wal = dir.path().join("wal");
    std::fs::create_dir_all(&wal).unwrap();

    let mut ids = Vec::new();
    {
        let store = create_store(wal.to_str().unwrap());
        for i in 0..10 {
            let octad = store.create(doc(&format!("E{i}"), &format!("B{i}"))).await.unwrap();
            ids.push(octad.id);
        }
        // Crash
    }

    {
        let store = create_store(wal.to_str().unwrap());
        let n: usize = store.replay_wal(&wal).await.unwrap();
        assert_eq!(n, 10);
        for id in &ids {
            assert!(store.get(id).await.unwrap().is_some(), "{id} missing");
        }
    }
}

#[tokio::test]
async fn delete_survives_crash() {
    let dir = tempfile::tempdir().unwrap();
    let wal = dir.path().join("wal");
    std::fs::create_dir_all(&wal).unwrap();

    let entity_id;
    {
        let store = create_store(wal.to_str().unwrap());
        let octad = store.create(doc("Delete Me", "Gone")).await.unwrap();
        entity_id = octad.id;
        store.delete(&entity_id).await.unwrap();
        // Crash
    }

    {
        let store = create_store(wal.to_str().unwrap());
        let _n: usize = store.replay_wal(&wal).await.unwrap();
        assert!(store.get(&entity_id).await.unwrap().is_none(), "Should stay deleted");
    }
}

#[tokio::test]
async fn empty_wal_clean_start() {
    let dir = tempfile::tempdir().unwrap();
    let wal = dir.path().join("wal");
    std::fs::create_dir_all(&wal).unwrap();

    let store = create_store(wal.to_str().unwrap());
    let n: usize = store.replay_wal(&wal).await.unwrap();
    assert_eq!(n, 0);
}
