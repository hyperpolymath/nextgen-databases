// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent provenance store backed by redb via verisim-storage.
//
// Each entity's ProvenanceChain is stored as a single JSON blob keyed by
// entity_id. On open(), all chains are scanned into an in-memory cache
// protected by a tokio::sync::RwLock (matching the InMemory implementation).
// Writes go to redb first, then update the cache.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use tracing::{debug, info, instrument};
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{
    ProvenanceChain, ProvenanceError, ProvenanceEventType, ProvenanceRecord, ProvenanceStore,
};

/// Persistent provenance store: redb for durability, async RwLock cache for
/// fast reads.
///
/// The cache uses `tokio::sync::RwLock` to match the async locking pattern of
/// `InMemoryProvenanceStore`.
pub struct RedbProvenanceStore {
    /// Typed store for provenance chains, keyed by entity_id.
    store: TypedStore<RedbBackend>,
    /// In-memory cache of all provenance chains.
    chains: Arc<tokio::sync::RwLock<HashMap<String, ProvenanceChain>>>,
}

impl RedbProvenanceStore {
    /// Open (or create) a persistent provenance store at the given path.
    ///
    /// On open, all existing chains are scanned from redb into the in-memory
    /// cache so that reads never hit disk.
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, ProvenanceError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| ProvenanceError::IoError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "prov");

        let entries: Vec<(String, ProvenanceChain)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| ProvenanceError::IoError(format!("scan: {}", e)))?;

        let mut cache = HashMap::new();
        for (id, chain) in entries {
            cache.insert(id, chain);
        }

        info!(count = cache.len(), "Loaded provenance store from redb");
        Ok(Self {
            store,
            chains: Arc::new(tokio::sync::RwLock::new(cache)),
        })
    }

    /// Persist a single entity's chain to redb.
    async fn persist_chain(
        &self,
        entity_id: &str,
        chain: &ProvenanceChain,
    ) -> Result<(), ProvenanceError> {
        self.store
            .put(entity_id, chain)
            .await
            .map_err(|e| ProvenanceError::IoError(format!("put: {}", e)))
    }
}

#[async_trait]
impl ProvenanceStore for RedbProvenanceStore {
    #[instrument(skip(self))]
    async fn record_event(
        &self,
        entity_id: &str,
        event_type: ProvenanceEventType,
        actor: &str,
        source: Option<String>,
        description: &str,
    ) -> Result<ProvenanceRecord, ProvenanceError> {
        let mut chains = self.chains.write().await;
        let chain = chains
            .entry(entity_id.to_string())
            .or_insert_with(|| ProvenanceChain::new(entity_id));

        chain.append(event_type, actor, source, description);
        let record = chain.records.last().expect("TODO: handle error").clone();

        // Persist the updated chain to redb.
        self.persist_chain(entity_id, chain).await?;

        debug!(
            entity_id = %entity_id,
            event = %record.event_type,
            actor = %record.actor,
            chain_length = chain.len(),
            "Provenance event recorded (persistent)"
        );
        Ok(record)
    }

    async fn get_chain(&self, entity_id: &str) -> Result<ProvenanceChain, ProvenanceError> {
        let chains = self.chains.read().await;
        chains
            .get(entity_id)
            .cloned()
            .ok_or_else(|| ProvenanceError::NotFound(entity_id.to_string()))
    }

    async fn verify_chain(&self, entity_id: &str) -> Result<bool, ProvenanceError> {
        let chains = self.chains.read().await;
        match chains.get(entity_id) {
            Some(chain) => {
                chain.verify()?;
                Ok(true)
            }
            None => Ok(false),
        }
    }

    async fn get_origin(
        &self,
        entity_id: &str,
    ) -> Result<Option<ProvenanceRecord>, ProvenanceError> {
        let chains = self.chains.read().await;
        Ok(chains.get(entity_id).and_then(|c| c.origin().cloned()))
    }

    async fn get_latest(
        &self,
        entity_id: &str,
    ) -> Result<Option<ProvenanceRecord>, ProvenanceError> {
        let chains = self.chains.read().await;
        Ok(chains.get(entity_id).and_then(|c| c.latest().cloned()))
    }

    async fn search_by_actor(
        &self,
        actor: &str,
    ) -> Result<Vec<(String, ProvenanceRecord)>, ProvenanceError> {
        let chains = self.chains.read().await;
        let mut results = Vec::new();
        for (entity_id, chain) in chains.iter() {
            for record in &chain.records {
                if record.actor == actor {
                    results.push((entity_id.clone(), record.clone()));
                }
            }
        }
        Ok(results)
    }

    async fn delete_chain(&self, entity_id: &str) -> Result<(), ProvenanceError> {
        // Delete from redb first.
        self.store
            .delete(entity_id)
            .await
            .map_err(|e| ProvenanceError::IoError(format!("delete: {}", e)))?;
        // Then remove from cache.
        let mut chains = self.chains.write().await;
        chains.remove(entity_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_persistent_provenance_roundtrip() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("prov.redb");

        // Write data in one session.
        {
            let store = RedbProvenanceStore::open(&path).await.expect("TODO: handle error");
            store
                .record_event(
                    "entity-1",
                    ProvenanceEventType::Created,
                    "alice",
                    Some("https://source.example.com".to_string()),
                    "Initial creation",
                )
                .await
                .expect("TODO: handle error");
            store
                .record_event(
                    "entity-1",
                    ProvenanceEventType::Modified,
                    "bob",
                    None,
                    "Updated vector embedding",
                )
                .await
                .expect("TODO: handle error");
        }

        // Reopen and verify data survived.
        {
            let store = RedbProvenanceStore::open(&path).await.expect("TODO: handle error");

            let chain = store.get_chain("entity-1").await.expect("TODO: handle error");
            assert_eq!(chain.len(), 2);
            assert!(chain.verify().is_ok());

            let origin = store.get_origin("entity-1").await.expect("TODO: handle error").expect("TODO: handle error");
            assert_eq!(origin.actor, "alice");
            assert_eq!(origin.event_type, ProvenanceEventType::Created);

            let latest = store.get_latest("entity-1").await.expect("TODO: handle error").expect("TODO: handle error");
            assert_eq!(latest.actor, "bob");
            assert_eq!(latest.event_type, ProvenanceEventType::Modified);

            // Verify chain integrity
            assert!(store.verify_chain("entity-1").await.expect("TODO: handle error"));

            // Non-existent entity returns false, not error
            assert!(!store.verify_chain("no-such-entity").await.expect("TODO: handle error"));
        }
    }

    #[tokio::test]
    async fn test_persistent_provenance_search_by_actor() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("prov-search.redb");

        let store = RedbProvenanceStore::open(&path).await.expect("TODO: handle error");
        store
            .record_event("e1", ProvenanceEventType::Created, "alice", None, "Created e1")
            .await
            .expect("TODO: handle error");
        store
            .record_event("e2", ProvenanceEventType::Created, "bob", None, "Created e2")
            .await
            .expect("TODO: handle error");
        store
            .record_event(
                "e3",
                ProvenanceEventType::Imported,
                "alice",
                None,
                "Imported e3",
            )
            .await
            .expect("TODO: handle error");

        let alice_records = store.search_by_actor("alice").await.expect("TODO: handle error");
        assert_eq!(alice_records.len(), 2);

        let bob_records = store.search_by_actor("bob").await.expect("TODO: handle error");
        assert_eq!(bob_records.len(), 1);
    }

    #[tokio::test]
    async fn test_persistent_provenance_delete_chain() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("prov-delete.redb");

        let store = RedbProvenanceStore::open(&path).await.expect("TODO: handle error");
        store
            .record_event("e1", ProvenanceEventType::Created, "alice", None, "Created")
            .await
            .expect("TODO: handle error");

        store.delete_chain("e1").await.expect("TODO: handle error");
        assert!(store.get_chain("e1").await.is_err());
    }
}
