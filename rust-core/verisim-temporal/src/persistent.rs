// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent temporal version store backed by redb via verisim-storage.
//
// Each entity's full version history is stored as a single JSON blob keyed by
// entity_id.  On open(), all histories are scanned into an in-memory BTreeMap
// cache for fast reads.  Writes go to redb first (durable), then update the
// cache.
//
// The associated type `Data` is `serde_json::Value`, making this store a
// universal versioned key-value store.  Higher layers can convert to/from
// concrete types using serde.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use tracing::info;
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{TemporalError, TemporalStore, TimeRange, Version};

/// Type alias matching the InMemory store's internal structure.
type VersionHistory = HashMap<String, BTreeMap<u64, Version<serde_json::Value>>>;

/// Persistent version store: redb for durability, in-memory BTreeMap cache for
/// fast reads and range queries.
///
/// Each entity's entire version history is stored as a serialized
/// `BTreeMap<u64, Version<serde_json::Value>>` under the entity_id key.
pub struct RedbVersionStore {
    /// Typed store for version histories, keyed by entity_id.
    store: TypedStore<RedbBackend>,
    /// In-memory cache of all version histories.
    versions: Arc<RwLock<VersionHistory>>,
}

impl RedbVersionStore {
    /// Open (or create) a persistent version store at the given path.
    ///
    /// On open, all existing version histories are scanned from redb into the
    /// in-memory cache so that reads never hit disk.
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, TemporalError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| TemporalError::Conflict(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "ver");

        let entries: Vec<(String, BTreeMap<u64, Version<serde_json::Value>>)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| TemporalError::Conflict(format!("scan: {}", e)))?;

        let mut cache: VersionHistory = HashMap::new();
        for (id, history) in entries {
            cache.insert(id, history);
        }

        info!(
            entities = cache.len(),
            "Loaded temporal version store from redb"
        );
        Ok(Self {
            store,
            versions: Arc::new(RwLock::new(cache)),
        })
    }

    /// Persist a single entity's version history to redb.
    async fn persist_entity(&self, entity_id: &str) -> Result<(), TemporalError> {
        let history = {
            let cache = self
                .versions
                .read()
                .map_err(|_| TemporalError::LockPoisoned)?;
            cache.get(entity_id).cloned()
        };
        if let Some(history) = history {
            self.store
                .put(entity_id, &history)
                .await
                .map_err(|e| TemporalError::Conflict(format!("put: {}", e)))?;
        }
        Ok(())
    }
}

#[async_trait]
impl TemporalStore for RedbVersionStore {
    type Data = serde_json::Value;

    async fn append(
        &self,
        entity_id: &str,
        data: Self::Data,
        author: &str,
        message: Option<&str>,
    ) -> Result<u64, TemporalError> {
        let next_version = {
            let mut store = self
                .versions
                .write()
                .map_err(|_| TemporalError::LockPoisoned)?;
            let versions = store.entry(entity_id.to_string()).or_default();

            let next_version = versions.keys().last().map(|v| v + 1).unwrap_or(1);
            let mut version = Version::new(next_version, data, author);
            if let Some(msg) = message {
                version = version.with_message(msg);
            }

            versions.insert(next_version, version);
            next_version
        };

        // Persist to redb after updating cache.
        self.persist_entity(entity_id).await?;
        Ok(next_version)
    }

    async fn latest(
        &self,
        entity_id: &str,
    ) -> Result<Option<Version<Self::Data>>, TemporalError> {
        let store = self
            .versions
            .read()
            .map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .and_then(|versions| versions.values().last().cloned()))
    }

    async fn at_version(
        &self,
        entity_id: &str,
        version: u64,
    ) -> Result<Option<Version<Self::Data>>, TemporalError> {
        let store = self
            .versions
            .read()
            .map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .and_then(|versions| versions.get(&version).cloned()))
    }

    async fn at_time(
        &self,
        entity_id: &str,
        time: DateTime<Utc>,
    ) -> Result<Option<Version<Self::Data>>, TemporalError> {
        let store = self
            .versions
            .read()
            .map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store.get(entity_id).and_then(|versions| {
            versions
                .values()
                .filter(|v| v.timestamp <= time)
                .last()
                .cloned()
        }))
    }

    async fn in_range(
        &self,
        entity_id: &str,
        range: &TimeRange,
    ) -> Result<Vec<Version<Self::Data>>, TemporalError> {
        let store = self
            .versions
            .read()
            .map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .map(|versions| {
                versions
                    .values()
                    .filter(|v| range.contains(&v.timestamp))
                    .cloned()
                    .collect()
            })
            .unwrap_or_default())
    }

    async fn history(
        &self,
        entity_id: &str,
        limit: usize,
    ) -> Result<Vec<Version<Self::Data>>, TemporalError> {
        let store = self
            .versions
            .read()
            .map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .map(|versions| versions.values().rev().take(limit).cloned().collect())
            .unwrap_or_default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_persistent_temporal_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("temporal.redb");

        // Write data in one session.
        {
            let store = RedbVersionStore::open(&path).await.unwrap();
            let v1 = store
                .append(
                    "entity-1",
                    serde_json::json!({"name": "Alice", "version": 1}),
                    "alice",
                    Some("initial creation"),
                )
                .await
                .unwrap();
            assert_eq!(v1, 1);

            let v2 = store
                .append(
                    "entity-1",
                    serde_json::json!({"name": "Alice Updated", "version": 2}),
                    "bob",
                    Some("updated name"),
                )
                .await
                .unwrap();
            assert_eq!(v2, 2);
        }

        // Reopen and verify data survived.
        {
            let store = RedbVersionStore::open(&path).await.unwrap();

            let latest = store.latest("entity-1").await.unwrap().unwrap();
            assert_eq!(latest.version, 2);
            assert_eq!(latest.data["name"], "Alice Updated");
            assert_eq!(latest.author, "bob");

            let v1 = store.at_version("entity-1", 1).await.unwrap().unwrap();
            assert_eq!(v1.data["name"], "Alice");
            assert_eq!(v1.author, "alice");

            let history = store.history("entity-1", 10).await.unwrap();
            assert_eq!(history.len(), 2);
            // History is most recent first.
            assert_eq!(history[0].version, 2);
            assert_eq!(history[1].version, 1);
        }
    }
}
