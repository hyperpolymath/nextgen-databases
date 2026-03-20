// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent provenance store backed by redb via verisim-storage.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use tracing::info;
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{ProvenanceChain, ProvenanceError, ProvenanceRecord, ProvenanceStore};

/// Persistent provenance store: redb for durability, in-memory cache for queries.
pub struct RedbProvenanceStore {
    store: TypedStore<RedbBackend>,
    cache: Arc<RwLock<HashMap<String, ProvenanceChain>>>,
}

impl RedbProvenanceStore {
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, ProvenanceError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| ProvenanceError::StorageError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "prov");

        let entries: Vec<(String, ProvenanceChain)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| ProvenanceError::StorageError(format!("scan: {}", e)))?;

        let mut cache = HashMap::new();
        for (id, chain) in entries {
            cache.insert(id, chain);
        }

        info!(count = cache.len(), "Loaded provenance store from redb");
        Ok(Self { store, cache: Arc::new(RwLock::new(cache)) })
    }

    async fn persist_chain(&self, entity_id: &str) -> Result<(), ProvenanceError> {
        let c = self.cache.read().map_err(|_| ProvenanceError::LockPoisoned)?;
        if let Some(chain) = c.get(entity_id) {
            self.store.put(entity_id, chain).await
                .map_err(|e| ProvenanceError::StorageError(format!("put: {}", e)))?;
        }
        Ok(())
    }
}

#[async_trait]
impl ProvenanceStore for RedbProvenanceStore {
    async fn record(&self, record: ProvenanceRecord) -> Result<(), ProvenanceError> {
        let entity_id = record.entity_id.clone();
        {
            let mut c = self.cache.write().map_err(|_| ProvenanceError::LockPoisoned)?;
            let chain = c.entry(entity_id.clone()).or_insert_with(|| ProvenanceChain {
                entity_id: entity_id.clone(),
                records: Vec::new(),
            });
            chain.records.push(record);
        }
        self.persist_chain(&entity_id).await
    }

    async fn get_chain(&self, entity_id: &str) -> Result<Option<ProvenanceChain>, ProvenanceError> {
        let c = self.cache.read().map_err(|_| ProvenanceError::LockPoisoned)?;
        Ok(c.get(entity_id).cloned())
    }

    async fn verify_chain(&self, entity_id: &str) -> Result<bool, ProvenanceError> {
        let c = self.cache.read().map_err(|_| ProvenanceError::LockPoisoned)?;
        match c.get(entity_id) {
            Some(chain) => Ok(chain.verify()),
            None => Err(ProvenanceError::NotFound(entity_id.to_string())),
        }
    }

    async fn get_latest(&self, entity_id: &str) -> Result<Option<ProvenanceRecord>, ProvenanceError> {
        let c = self.cache.read().map_err(|_| ProvenanceError::LockPoisoned)?;
        Ok(c.get(entity_id).and_then(|chain| chain.records.last().cloned()))
    }

    async fn search_by_actor(&self, actor: &str) -> Result<Vec<ProvenanceRecord>, ProvenanceError> {
        let c = self.cache.read().map_err(|_| ProvenanceError::LockPoisoned)?;
        let mut results = Vec::new();
        for chain in c.values() {
            for record in &chain.records {
                if record.actor == actor {
                    results.push(record.clone());
                }
            }
        }
        Ok(results)
    }

    async fn delete_chain(&self, entity_id: &str) -> Result<(), ProvenanceError> {
        self.store.delete(entity_id).await
            .map_err(|e| ProvenanceError::StorageError(format!("delete: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| ProvenanceError::LockPoisoned)?;
        c.remove(entity_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_persistent_provenance_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("prov.redb");

        {
            let store = RedbProvenanceStore::open(&path).await.unwrap();
            let record = ProvenanceRecord::new("e1", "create", "user1");
            store.record(record).await.unwrap();
        }

        {
            let store = RedbProvenanceStore::open(&path).await.unwrap();
            let chain = store.get_chain("e1").await.unwrap().unwrap();
            assert_eq!(chain.records.len(), 1);
            assert_eq!(chain.records[0].actor, "user1");
        }
    }
}
