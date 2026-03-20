// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent semantic store backed by redb via verisim-storage.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use tracing::info;
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{SemanticAnnotation, SemanticError, SemanticStore};

/// Persistent semantic store: redb for durability, in-memory cache for queries.
pub struct RedbSemanticStore {
    store: TypedStore<RedbBackend>,
    cache: Arc<RwLock<HashMap<String, SemanticAnnotation>>>,
}

impl RedbSemanticStore {
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, SemanticError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| SemanticError::StorageError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "sem");

        let entries: Vec<(String, SemanticAnnotation)> = store
            .scan_prefix("", 1_000_000)
            .await
            .map_err(|e| SemanticError::StorageError(format!("scan: {}", e)))?;

        let mut cache = HashMap::new();
        for (id, ann) in entries {
            cache.insert(id, ann);
        }

        info!(count = cache.len(), "Loaded semantic store from redb");
        Ok(Self { store, cache: Arc::new(RwLock::new(cache)) })
    }
}

#[async_trait]
impl SemanticStore for RedbSemanticStore {
    async fn annotate(&self, annotation: &SemanticAnnotation) -> Result<(), SemanticError> {
        self.store.put(&annotation.entity_id, annotation).await
            .map_err(|e| SemanticError::StorageError(format!("put: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| SemanticError::LockPoisoned)?;
        c.insert(annotation.entity_id.clone(), annotation.clone());
        Ok(())
    }

    async fn get_annotation(&self, entity_id: &str) -> Result<Option<SemanticAnnotation>, SemanticError> {
        let c = self.cache.read().map_err(|_| SemanticError::LockPoisoned)?;
        Ok(c.get(entity_id).cloned())
    }

    async fn delete_annotation(&self, entity_id: &str) -> Result<(), SemanticError> {
        self.store.delete(entity_id).await
            .map_err(|e| SemanticError::StorageError(format!("delete: {}", e)))?;
        let mut c = self.cache.write().map_err(|_| SemanticError::LockPoisoned)?;
        c.remove(entity_id);
        Ok(())
    }

    async fn query_by_type(&self, type_uri: &str) -> Result<Vec<SemanticAnnotation>, SemanticError> {
        let c = self.cache.read().map_err(|_| SemanticError::LockPoisoned)?;
        Ok(c.values()
            .filter(|a| a.types.iter().any(|t| t.uri == type_uri))
            .cloned()
            .collect())
    }

    async fn validate(&self, entity_id: &str) -> Result<Vec<String>, SemanticError> {
        let c = self.cache.read().map_err(|_| SemanticError::LockPoisoned)?;
        let ann = c.get(entity_id)
            .ok_or_else(|| SemanticError::NotFound(entity_id.to_string()))?;
        let mut violations = Vec::new();
        for constraint in &ann.constraints {
            if !constraint.satisfied {
                violations.push(format!("Constraint '{}' not satisfied", constraint.name));
            }
        }
        Ok(violations)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::SemanticType;

    #[tokio::test]
    async fn test_persistent_semantic_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("semantic.redb");

        {
            let store = RedbSemanticStore::open(&path).await.unwrap();
            let ann = SemanticAnnotation {
                entity_id: "e1".to_string(),
                types: vec![SemanticType { uri: "http://example.org/Person".to_string(), label: Some("Person".to_string()), confidence: 0.95 }],
                constraints: vec![],
                proofs: vec![],
                provenance: None,
            };
            store.annotate(&ann).await.unwrap();
        }

        {
            let store = RedbSemanticStore::open(&path).await.unwrap();
            let ann = store.get_annotation("e1").await.unwrap().unwrap();
            assert_eq!(ann.types[0].uri, "http://example.org/Person");
        }
    }
}
