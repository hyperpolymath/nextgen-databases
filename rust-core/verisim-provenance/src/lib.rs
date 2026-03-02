// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Provenance Modality
//!
//! Tracks the origin, transformation history, and actor trail for each entity.
//! Provenance records form a hash chain — each record's `parent_hash` is the
//! SHA-256 digest of the previous record, creating an immutable audit trail.
//!
//! # Architecture
//!
//! - **ProvenanceRecord**: A single event in an entity's lineage (creation,
//!   modification, import, normalization, etc.).
//! - **ProvenanceChain**: An ordered sequence of records with hash-chain
//!   integrity verification.
//! - **ProvenanceStore** trait: Async storage interface for recording and
//!   querying provenance data.
//! - **InMemoryProvenanceStore**: Reference implementation backed by a
//!   `HashMap<String, Vec<ProvenanceRecord>>`.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::RwLock;
use tracing::{debug, instrument};

/// Provenance-specific errors
#[derive(Error, Debug)]
pub enum ProvenanceError {
    /// Entity provenance chain not found
    #[error("Provenance chain not found for entity: {0}")]
    NotFound(String),

    /// Hash chain integrity violation — records have been tampered with or
    /// a parent_hash does not match the SHA-256 of the preceding record
    #[error("Provenance chain corrupted for entity {entity}: {reason}")]
    ChainCorrupted {
        entity: String,
        reason: String,
    },

    /// A record's computed hash does not match its stored content_hash
    #[error("Hash mismatch at index {index} for entity {entity}")]
    HashMismatch {
        entity: String,
        index: usize,
    },

    /// Generic I/O or storage error
    #[error("Provenance I/O error: {0}")]
    IoError(String),
}

/// Classification of provenance events
///
/// Each variant captures a distinct lifecycle transition that an entity can
/// undergo.  The `Custom(String)` variant allows domain-specific extensions
/// without modifying this enum.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ProvenanceEventType {
    /// Entity was created for the first time
    Created,
    /// Entity was modified (content or metadata changed)
    Modified,
    /// Entity was imported from an external source
    Imported,
    /// Entity underwent drift normalization
    Normalized,
    /// Entity was repaired after drift detection
    DriftRepaired,
    /// Entity was soft- or hard-deleted
    Deleted,
    /// Two or more entities were merged into this one
    Merged,
    /// Domain-specific event type
    Custom(String),
}

impl std::fmt::Display for ProvenanceEventType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProvenanceEventType::Created => write!(f, "created"),
            ProvenanceEventType::Modified => write!(f, "modified"),
            ProvenanceEventType::Imported => write!(f, "imported"),
            ProvenanceEventType::Normalized => write!(f, "normalized"),
            ProvenanceEventType::DriftRepaired => write!(f, "drift_repaired"),
            ProvenanceEventType::Deleted => write!(f, "deleted"),
            ProvenanceEventType::Merged => write!(f, "merged"),
            ProvenanceEventType::Custom(name) => write!(f, "custom:{}", name),
        }
    }
}

/// A single provenance record — one event in an entity's lineage chain.
///
/// Records are linked by `parent_hash`: the SHA-256 of the serialized
/// previous record.  The first record in a chain has `parent_hash` set to
/// the SHA-256 of the empty string.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProvenanceRecord {
    /// What happened to the entity
    pub event_type: ProvenanceEventType,
    /// Who or what caused this event (user ID, system component, bot name)
    pub actor: String,
    /// When this event occurred
    pub timestamp: DateTime<Utc>,
    /// Optional source identifier (URL, file path, upstream entity ID)
    pub source: Option<String>,
    /// Human-readable description of the event
    pub description: String,
    /// SHA-256 hex digest of the previous record (or of "" for the first)
    pub parent_hash: String,
    /// SHA-256 hex digest of this record's canonical serialization
    pub content_hash: String,
}

impl ProvenanceRecord {
    /// Compute the SHA-256 hex digest of the canonical (deterministic) JSON
    /// serialization of a record's *content* fields — everything except
    /// `content_hash` itself.
    pub fn compute_hash(
        event_type: &ProvenanceEventType,
        actor: &str,
        timestamp: &DateTime<Utc>,
        source: &Option<String>,
        description: &str,
        parent_hash: &str,
    ) -> String {
        let canonical = serde_json::json!({
            "event_type": event_type,
            "actor": actor,
            "timestamp": timestamp.to_rfc3339(),
            "source": source,
            "description": description,
            "parent_hash": parent_hash,
        });
        let bytes = canonical.to_string().into_bytes();
        let digest = Sha256::digest(&bytes);
        format!("{:x}", digest)
    }

    /// Build a new record, computing its `content_hash` automatically.
    pub fn new(
        event_type: ProvenanceEventType,
        actor: impl Into<String>,
        source: Option<String>,
        description: impl Into<String>,
        parent_hash: impl Into<String>,
    ) -> Self {
        let actor = actor.into();
        let description = description.into();
        let parent_hash = parent_hash.into();
        let timestamp = Utc::now();

        let content_hash = Self::compute_hash(
            &event_type,
            &actor,
            &timestamp,
            &source,
            &description,
            &parent_hash,
        );

        Self {
            event_type,
            actor,
            timestamp,
            source,
            description,
            parent_hash,
            content_hash,
        }
    }

    /// Verify that `content_hash` matches the re-computed hash of this
    /// record's fields.
    pub fn verify(&self) -> bool {
        let expected = Self::compute_hash(
            &self.event_type,
            &self.actor,
            &self.timestamp,
            &self.source,
            &self.description,
            &self.parent_hash,
        );
        self.content_hash == expected
    }
}

/// An ordered provenance chain for a single entity.
///
/// The chain is a `Vec<ProvenanceRecord>` where each record's
/// `parent_hash` equals the `content_hash` of its predecessor.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProvenanceChain {
    /// The entity this chain belongs to
    pub entity_id: String,
    /// Ordered list of provenance records (oldest first)
    pub records: Vec<ProvenanceRecord>,
}

impl ProvenanceChain {
    /// Create an empty chain for a given entity.
    pub fn new(entity_id: impl Into<String>) -> Self {
        Self {
            entity_id: entity_id.into(),
            records: Vec::new(),
        }
    }

    /// Number of records in the chain.
    pub fn len(&self) -> usize {
        self.records.len()
    }

    /// Whether the chain is empty.
    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    /// Get the hash of the genesis record (SHA-256 of "").
    fn genesis_hash() -> String {
        let digest = Sha256::digest(b"");
        format!("{:x}", digest)
    }

    /// Verify the entire hash chain.
    ///
    /// Returns `Ok(())` if every record's `parent_hash` matches the
    /// `content_hash` of the previous record (or the genesis hash for
    /// the first), and every record's `content_hash` re-computes correctly.
    pub fn verify(&self) -> Result<(), ProvenanceError> {
        let mut expected_parent = Self::genesis_hash();

        for (i, record) in self.records.iter().enumerate() {
            // Check parent linkage
            if record.parent_hash != expected_parent {
                return Err(ProvenanceError::ChainCorrupted {
                    entity: self.entity_id.clone(),
                    reason: format!(
                        "Record {} parent_hash mismatch: expected {}, got {}",
                        i, expected_parent, record.parent_hash
                    ),
                });
            }

            // Check record self-integrity
            if !record.verify() {
                return Err(ProvenanceError::HashMismatch {
                    entity: self.entity_id.clone(),
                    index: i,
                });
            }

            expected_parent = record.content_hash.clone();
        }

        Ok(())
    }

    /// Get the origin (first) record, if any.
    pub fn origin(&self) -> Option<&ProvenanceRecord> {
        self.records.first()
    }

    /// Get the latest (most recent) record, if any.
    pub fn latest(&self) -> Option<&ProvenanceRecord> {
        self.records.last()
    }

    /// Append a new record to the chain.
    ///
    /// The `parent_hash` is set automatically from the previous record's
    /// `content_hash` (or the genesis hash if this is the first record).
    pub fn append(
        &mut self,
        event_type: ProvenanceEventType,
        actor: impl Into<String>,
        source: Option<String>,
        description: impl Into<String>,
    ) -> &ProvenanceRecord {
        let parent_hash = self
            .records
            .last()
            .map(|r| r.content_hash.clone())
            .unwrap_or_else(Self::genesis_hash);

        let record = ProvenanceRecord::new(event_type, actor, source, description, parent_hash);
        self.records.push(record);
        self.records.last().unwrap()
    }
}

/// Async trait for provenance storage backends.
///
/// Implementations must be `Send + Sync` so they can be shared across
/// Tokio tasks.
#[async_trait]
pub trait ProvenanceStore: Send + Sync {
    /// Record a new provenance event for an entity.
    ///
    /// If the entity has no existing chain, one is created with this as the
    /// genesis record.  Returns the newly appended record.
    async fn record_event(
        &self,
        entity_id: &str,
        event_type: ProvenanceEventType,
        actor: &str,
        source: Option<String>,
        description: &str,
    ) -> Result<ProvenanceRecord, ProvenanceError>;

    /// Retrieve the full provenance chain for an entity.
    async fn get_chain(&self, entity_id: &str) -> Result<ProvenanceChain, ProvenanceError>;

    /// Verify the hash-chain integrity for an entity.
    ///
    /// Returns `Ok(true)` if the chain is valid, `Ok(false)` if the entity
    /// has no chain, or `Err` if the chain is corrupted.
    async fn verify_chain(&self, entity_id: &str) -> Result<bool, ProvenanceError>;

    /// Get the origin (first) record for an entity.
    async fn get_origin(&self, entity_id: &str) -> Result<Option<ProvenanceRecord>, ProvenanceError>;

    /// Get the latest (most recent) record for an entity.
    async fn get_latest(&self, entity_id: &str) -> Result<Option<ProvenanceRecord>, ProvenanceError>;

    /// Search for provenance records by actor across all entities.
    async fn search_by_actor(&self, actor: &str) -> Result<Vec<(String, ProvenanceRecord)>, ProvenanceError>;

    /// Delete the provenance chain for an entity (for testing / admin use).
    async fn delete_chain(&self, entity_id: &str) -> Result<(), ProvenanceError>;
}

/// In-memory implementation of [`ProvenanceStore`].
///
/// Suitable for development, testing, and single-node deployments.
/// All data is lost on process exit.
pub struct InMemoryProvenanceStore {
    chains: Arc<RwLock<HashMap<String, ProvenanceChain>>>,
}

impl InMemoryProvenanceStore {
    /// Create a new empty in-memory provenance store.
    pub fn new() -> Self {
        Self {
            chains: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl Default for InMemoryProvenanceStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl ProvenanceStore for InMemoryProvenanceStore {
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

        let record = chain.records.last().unwrap().clone();
        debug!(
            entity_id = %entity_id,
            event = %record.event_type,
            actor = %record.actor,
            chain_length = chain.len(),
            "Provenance event recorded"
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

    async fn get_origin(&self, entity_id: &str) -> Result<Option<ProvenanceRecord>, ProvenanceError> {
        let chains = self.chains.read().await;
        Ok(chains.get(entity_id).and_then(|c| c.origin().cloned()))
    }

    async fn get_latest(&self, entity_id: &str) -> Result<Option<ProvenanceRecord>, ProvenanceError> {
        let chains = self.chains.read().await;
        Ok(chains.get(entity_id).and_then(|c| c.latest().cloned()))
    }

    async fn search_by_actor(&self, actor: &str) -> Result<Vec<(String, ProvenanceRecord)>, ProvenanceError> {
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
        let mut chains = self.chains.write().await;
        chains.remove(entity_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_provenance_record_hash_verification() {
        let record = ProvenanceRecord::new(
            ProvenanceEventType::Created,
            "alice",
            Some("https://source.example.com".to_string()),
            "Initial creation of entity",
            "0000000000000000",
        );
        assert!(record.verify(), "Freshly created record should verify");
    }

    #[test]
    fn test_provenance_record_tampered_fails_verification() {
        let mut record = ProvenanceRecord::new(
            ProvenanceEventType::Created,
            "alice",
            None,
            "Initial creation",
            "0000000000000000",
        );
        // Tamper with the description after creation
        record.description = "TAMPERED".to_string();
        assert!(!record.verify(), "Tampered record should fail verification");
    }

    #[test]
    fn test_provenance_chain_integrity() {
        let mut chain = ProvenanceChain::new("entity-1");
        chain.append(ProvenanceEventType::Created, "alice", None, "Created entity");
        chain.append(ProvenanceEventType::Modified, "bob", None, "Updated title");
        chain.append(
            ProvenanceEventType::Normalized,
            "system",
            None,
            "Auto-normalized after drift detection",
        );

        assert_eq!(chain.len(), 3);
        assert!(chain.verify().is_ok(), "Valid chain should verify");
    }

    #[test]
    fn test_provenance_chain_corruption_detected() {
        let mut chain = ProvenanceChain::new("entity-2");
        chain.append(ProvenanceEventType::Created, "alice", None, "Created");
        chain.append(ProvenanceEventType::Modified, "bob", None, "Modified");

        // Corrupt the second record's parent_hash
        chain.records[1].parent_hash = "corrupted_hash".to_string();

        let result = chain.verify();
        assert!(result.is_err(), "Corrupted chain should fail verification");
        match result {
            Err(ProvenanceError::ChainCorrupted { entity, .. }) => {
                assert_eq!(entity, "entity-2");
            }
            other => panic!("Expected ChainCorrupted, got {:?}", other),
        }
    }

    #[test]
    fn test_provenance_chain_origin_and_latest() {
        let mut chain = ProvenanceChain::new("entity-3");
        assert!(chain.origin().is_none());
        assert!(chain.latest().is_none());

        chain.append(ProvenanceEventType::Created, "alice", None, "Created");
        chain.append(ProvenanceEventType::Modified, "bob", None, "Modified");

        assert_eq!(chain.origin().unwrap().actor, "alice");
        assert_eq!(chain.latest().unwrap().actor, "bob");
    }

    #[tokio::test]
    async fn test_in_memory_store_record_and_get() {
        let store = InMemoryProvenanceStore::new();

        // Record first event
        let record = store
            .record_event(
                "entity-100",
                ProvenanceEventType::Created,
                "alice",
                Some("https://import.example.com".to_string()),
                "Imported from external source",
            )
            .await
            .unwrap();
        assert_eq!(record.event_type, ProvenanceEventType::Created);

        // Record second event
        store
            .record_event(
                "entity-100",
                ProvenanceEventType::Modified,
                "bob",
                None,
                "Updated vector embedding",
            )
            .await
            .unwrap();

        // Retrieve chain
        let chain = store.get_chain("entity-100").await.unwrap();
        assert_eq!(chain.len(), 2);
        assert!(chain.verify().is_ok());
    }

    #[tokio::test]
    async fn test_in_memory_store_verify_chain() {
        let store = InMemoryProvenanceStore::new();

        // Non-existent chain returns false (not an error)
        assert!(!store.verify_chain("no-such-entity").await.unwrap());

        // Create a chain and verify it
        store
            .record_event("e1", ProvenanceEventType::Created, "alice", None, "Created")
            .await
            .unwrap();
        store
            .record_event("e1", ProvenanceEventType::Modified, "bob", None, "Modified")
            .await
            .unwrap();

        assert!(store.verify_chain("e1").await.unwrap());
    }

    #[tokio::test]
    async fn test_in_memory_store_search_by_actor() {
        let store = InMemoryProvenanceStore::new();

        store
            .record_event("e1", ProvenanceEventType::Created, "alice", None, "Created e1")
            .await
            .unwrap();
        store
            .record_event("e2", ProvenanceEventType::Created, "bob", None, "Created e2")
            .await
            .unwrap();
        store
            .record_event("e3", ProvenanceEventType::Imported, "alice", None, "Imported e3")
            .await
            .unwrap();

        let alice_records = store.search_by_actor("alice").await.unwrap();
        assert_eq!(alice_records.len(), 2);

        let bob_records = store.search_by_actor("bob").await.unwrap();
        assert_eq!(bob_records.len(), 1);
    }

    #[tokio::test]
    async fn test_in_memory_store_origin_and_latest() {
        let store = InMemoryProvenanceStore::new();

        store
            .record_event("e1", ProvenanceEventType::Created, "alice", None, "Created")
            .await
            .unwrap();
        store
            .record_event("e1", ProvenanceEventType::Modified, "bob", None, "Modified")
            .await
            .unwrap();

        let origin = store.get_origin("e1").await.unwrap().unwrap();
        assert_eq!(origin.actor, "alice");

        let latest = store.get_latest("e1").await.unwrap().unwrap();
        assert_eq!(latest.actor, "bob");
    }

    #[tokio::test]
    async fn test_in_memory_store_delete_chain() {
        let store = InMemoryProvenanceStore::new();

        store
            .record_event("e1", ProvenanceEventType::Created, "alice", None, "Created")
            .await
            .unwrap();
        assert!(store.get_chain("e1").await.is_ok());

        store.delete_chain("e1").await.unwrap();
        assert!(store.get_chain("e1").await.is_err());
    }

    #[tokio::test]
    async fn test_in_memory_store_not_found() {
        let store = InMemoryProvenanceStore::new();
        let result = store.get_chain("nonexistent").await;
        assert!(matches!(result, Err(ProvenanceError::NotFound(_))));
    }
}
