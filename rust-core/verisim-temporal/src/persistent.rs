// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent temporal version store backed by redb via verisim-storage.
// Stores version history as serialised JSON per entity.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use tracing::info;
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{TemporalStore, Version, VersionError};

/// Persistent version store: redb for durability, in-memory cache for queries.
/// Each entity's full version history is stored as a single JSON blob keyed by entity_id.
pub struct RedbVersionStore {
    store: TypedStore<RedbBackend>,
    cache: Arc<RwLock<HashMap<String, Vec<Version<serde_json::Value>>>>>,
}

impl RedbVersionStore {
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, VersionError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| VersionError::StorageError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "ver");

        let entries: Vec<(String, Vec<Version<serde_json::Value>>)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| VersionError::StorageError(format!("scan: {}", e)))?;

        let mut cache = HashMap::new();
        for (id, versions) in entries {
            cache.insert(id, versions);
        }

        info!(count = cache.len(), "Loaded temporal version store from redb");
        Ok(Self { store, cache: Arc::new(RwLock::new(cache)) })
    }

    async fn persist_entity(&self, entity_id: &str) -> Result<(), VersionError> {
        let c = self.cache.read().map_err(|_| VersionError::LockPoisoned)?;
        if let Some(versions) = c.get(entity_id) {
            self.store.put(entity_id, versions).await
                .map_err(|e| VersionError::StorageError(format!("put: {}", e)))?;
        }
        Ok(())
    }
}

// Note: Generic TemporalStore trait uses type parameter T.
// For persistent storage, we use serde_json::Value as the universal type.
// Higher layers can convert to/from concrete types.
#[async_trait]
impl TemporalStore for RedbVersionStore {
    type Item = serde_json::Value;

    async fn put_version(&self, entity_id: &str, version: Version<serde_json::Value>) -> Result<(), VersionError> {
        {
            let mut c = self.cache.write().map_err(|_| VersionError::LockPoisoned)?;
            c.entry(entity_id.to_string()).or_default().push(version);
        }
        self.persist_entity(entity_id).await
    }

    async fn get_latest(&self, entity_id: &str) -> Result<Option<Version<serde_json::Value>>, VersionError> {
        let c = self.cache.read().map_err(|_| VersionError::LockPoisoned)?;
        Ok(c.get(entity_id).and_then(|v| v.last().cloned()))
    }

    async fn get_version(&self, entity_id: &str, version_num: u64) -> Result<Option<Version<serde_json::Value>>, VersionError> {
        let c = self.cache.read().map_err(|_| VersionError::LockPoisoned)?;
        Ok(c.get(entity_id)
            .and_then(|versions| versions.iter().find(|v| v.version == version_num).cloned()))
    }

    async fn get_history(&self, entity_id: &str) -> Result<Vec<Version<serde_json::Value>>, VersionError> {
        let c = self.cache.read().map_err(|_| VersionError::LockPoisoned)?;
        Ok(c.get(entity_id).cloned().unwrap_or_default())
    }

    async fn delete_history(&self, entity_id: &str) -> Result<(), VersionError> {
        self.store.delete(entity_id).await
            .map_err(|e| VersionError::StorageError(format!("delete: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| VersionError::LockPoisoned)?;
        c.remove(entity_id);
        Ok(())
    }
}
