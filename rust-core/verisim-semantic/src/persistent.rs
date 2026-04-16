// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Persistent semantic store backed by redb via verisim-storage.
//
// Stores semantic types, annotations, and proofs in redb for durability.
// An in-memory cache is rebuilt from redb on open() for fast read access.
// Writes go to redb first (durable), then update the cache.
//
// A single TypedStore with namespace "sem" is used. Keys are manually
// prefixed to separate the three data kinds:
//   - `type:<iri>` — semantic types (ontology)
//   - `ann:<entity_id>` — semantic annotations
//   - `proof:<claim>` — proof blobs (Vec<ProofBlob>)

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use async_trait::async_trait;
use tracing::info;
use verisim_storage::redb_backend::RedbBackend;
use verisim_storage::typed::TypedStore;

use crate::{
    ConstraintKind, ProofBlob, SemanticAnnotation, SemanticError, SemanticStore, SemanticType,
    SemanticValue,
};

/// Key prefix for semantic types within the "sem" namespace.
const TYPE_PREFIX: &str = "type:";
/// Key prefix for annotations within the "sem" namespace.
const ANN_PREFIX: &str = "ann:";
/// Key prefix for proof blobs within the "sem" namespace.
const PROOF_PREFIX: &str = "proof:";

/// Persistent semantic store: redb for durability, in-memory cache for queries.
///
/// Three logical partitions share a single TypedStore via key prefixes.
pub struct RedbSemanticStore {
    /// Single typed store for all semantic data.
    store: TypedStore<RedbBackend>,
    /// In-memory cache of all registered types.
    types: Arc<RwLock<HashMap<String, SemanticType>>>,
    /// In-memory cache of all annotations.
    annotations: Arc<RwLock<HashMap<String, SemanticAnnotation>>>,
    /// In-memory cache of all proofs grouped by claim.
    proofs: Arc<RwLock<HashMap<String, Vec<ProofBlob>>>>,
}

impl RedbSemanticStore {
    /// Open (or create) a persistent semantic store at the given path.
    ///
    /// On open, all existing data is scanned from redb into the in-memory
    /// caches so that reads never hit disk.
    pub async fn open(path: impl AsRef<Path>) -> Result<Self, SemanticError> {
        let backend = RedbBackend::open(path.as_ref())
            .map_err(|e| SemanticError::SerializationError(format!("redb open: {}", e)))?;
        let store = TypedStore::new(backend, "sem");

        // Scan types from redb into cache.
        let type_entries: Vec<(String, SemanticType)> = store
            .scan_prefix(TYPE_PREFIX, 1_000_000)
            .await
            .map_err(|e| SemanticError::SerializationError(format!("scan types: {}", e)))?;
        let mut types = HashMap::new();
        for (key, typ) in type_entries {
            // Strip the prefix to recover the IRI.
            let iri = key.strip_prefix(TYPE_PREFIX).unwrap_or(&key).to_string();
            types.insert(iri, typ);
        }

        // Scan annotations from redb into cache.
        let ann_entries: Vec<(String, SemanticAnnotation)> = store
            .scan_prefix(ANN_PREFIX, 1_000_000)
            .await
            .map_err(|e| SemanticError::SerializationError(format!("scan annotations: {}", e)))?;
        let mut annotations = HashMap::new();
        for (key, ann) in ann_entries {
            let id = key.strip_prefix(ANN_PREFIX).unwrap_or(&key).to_string();
            annotations.insert(id, ann);
        }

        // Scan proofs from redb into cache.
        let proof_entries: Vec<(String, Vec<ProofBlob>)> = store
            .scan_prefix(PROOF_PREFIX, 1_000_000)
            .await
            .map_err(|e| SemanticError::SerializationError(format!("scan proofs: {}", e)))?;
        let mut proofs = HashMap::new();
        for (key, blobs) in proof_entries {
            let claim = key.strip_prefix(PROOF_PREFIX).unwrap_or(&key).to_string();
            proofs.insert(claim, blobs);
        }

        info!(
            types = types.len(),
            annotations = annotations.len(),
            proofs = proofs.len(),
            "Loaded semantic store from redb"
        );

        Ok(Self {
            store,
            types: Arc::new(RwLock::new(types)),
            annotations: Arc::new(RwLock::new(annotations)),
            proofs: Arc::new(RwLock::new(proofs)),
        })
    }
}

#[async_trait]
impl SemanticStore for RedbSemanticStore {
    async fn register_type(&self, typ: &SemanticType) -> Result<(), SemanticError> {
        let key = format!("{}{}", TYPE_PREFIX, typ.iri);

        // Write to redb first (durable).
        self.store
            .put(&key, typ)
            .await
            .map_err(|e| SemanticError::SerializationError(format!("put type: {}", e)))?;

        // Then update in-memory cache.
        self.types
            .write()
            .map_err(|_| SemanticError::LockPoisoned)?
            .insert(typ.iri.clone(), typ.clone());
        Ok(())
    }

    async fn get_type(&self, iri: &str) -> Result<Option<SemanticType>, SemanticError> {
        let cache = self.types.read().map_err(|_| SemanticError::LockPoisoned)?;
        Ok(cache.get(iri).cloned())
    }

    async fn annotate(&self, annotation: &SemanticAnnotation) -> Result<(), SemanticError> {
        // Validate first — mirrors the InMemory behaviour.
        let violations = self.validate(annotation).await?;
        if !violations.is_empty() {
            return Err(SemanticError::ConstraintViolation(violations.join("; ")));
        }

        let key = format!("{}{}", ANN_PREFIX, annotation.entity_id);

        // Write to redb first.
        self.store
            .put(&key, annotation)
            .await
            .map_err(|e| SemanticError::SerializationError(format!("put annotation: {}", e)))?;

        // Update cache.
        self.annotations
            .write()
            .map_err(|_| SemanticError::LockPoisoned)?
            .insert(annotation.entity_id.clone(), annotation.clone());
        Ok(())
    }

    async fn get_annotations(
        &self,
        entity_id: &str,
    ) -> Result<Option<SemanticAnnotation>, SemanticError> {
        let cache = self
            .annotations
            .read()
            .map_err(|_| SemanticError::LockPoisoned)?;
        Ok(cache.get(entity_id).cloned())
    }

    async fn validate(
        &self,
        annotation: &SemanticAnnotation,
    ) -> Result<Vec<String>, SemanticError> {
        let types = self.types.read().map_err(|_| SemanticError::LockPoisoned)?;
        let mut violations = Vec::new();

        for type_iri in &annotation.types {
            if let Some(typ) = types.get(type_iri) {
                for constraint in &typ.constraints {
                    match &constraint.kind {
                        ConstraintKind::Required(prop) => {
                            if !annotation.properties.contains_key(prop) {
                                violations.push(format!(
                                    "{}: {}",
                                    constraint.name, constraint.message
                                ));
                            }
                        }
                        ConstraintKind::Pattern { property, regex } => {
                            if let Some(SemanticValue::TypedLiteral { value, .. }) =
                                annotation.properties.get(property)
                            {
                                let re = regex::Regex::new(regex).ok();
                                if let Some(re) = re {
                                    if !re.is_match(value) {
                                        violations.push(format!(
                                            "{}: {}",
                                            constraint.name, constraint.message
                                        ));
                                    }
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }
        }

        Ok(violations)
    }

    async fn store_proof(&self, proof: &ProofBlob) -> Result<(), SemanticError> {
        // Update cache first to build the new vec, then persist.
        let updated_proofs = {
            let mut cache = self
                .proofs
                .write()
                .map_err(|_| SemanticError::LockPoisoned)?;
            let entry = cache.entry(proof.claim.clone()).or_default();
            entry.push(proof.clone());
            entry.clone()
        };

        let key = format!("{}{}", PROOF_PREFIX, proof.claim);

        // Persist the entire proof list for this claim to redb.
        self.store
            .put(&key, &updated_proofs)
            .await
            .map_err(|e| SemanticError::SerializationError(format!("put proofs: {}", e)))?;

        Ok(())
    }

    async fn get_proofs(&self, claim: &str) -> Result<Vec<ProofBlob>, SemanticError> {
        let cache = self
            .proofs
            .read()
            .map_err(|_| SemanticError::LockPoisoned)?;
        Ok(cache.get(claim).cloned().unwrap_or_default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Constraint, Provenance};

    #[tokio::test]
    async fn test_persistent_semantic_roundtrip() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("semantic.redb");

        // Write data in one session.
        {
            let store = RedbSemanticStore::open(&path).await.expect("TODO: handle error");

            let person_type =
                SemanticType::new("https://example.org/Person", "Person").with_constraint(
                    Constraint {
                        name: "name_required".to_string(),
                        kind: ConstraintKind::Required("name".to_string()),
                        message: "Person must have a name".to_string(),
                    },
                );
            store.register_type(&person_type).await.expect("TODO: handle error");

            let mut properties = HashMap::new();
            properties.insert(
                "name".to_string(),
                SemanticValue::TypedLiteral {
                    value: "Alice".to_string(),
                    datatype: "xsd:string".to_string(),
                },
            );
            let ann = SemanticAnnotation {
                entity_id: "e1".to_string(),
                types: vec!["https://example.org/Person".to_string()],
                properties,
                provenance: Provenance::default(),
            };
            store.annotate(&ann).await.expect("TODO: handle error");

            let proof = ProofBlob::new(
                "e1 is-a Person",
                crate::ProofType::TypeAssignment,
                vec![1, 2, 3],
            );
            store.store_proof(&proof).await.expect("TODO: handle error");
        }

        // Reopen and verify data survived.
        {
            let store = RedbSemanticStore::open(&path).await.expect("TODO: handle error");

            let typ = store
                .get_type("https://example.org/Person")
                .await
                .expect("TODO: handle error");
            assert!(typ.is_some());
            assert_eq!(typ.expect("TODO: handle error").label, "Person");

            let ann = store.get_annotations("e1").await.expect("TODO: handle error");
            assert!(ann.is_some());
            assert_eq!(ann.expect("TODO: handle error").entity_id, "e1");

            let proofs = store.get_proofs("e1 is-a Person").await.expect("TODO: handle error");
            assert_eq!(proofs.len(), 1);
            assert_eq!(proofs[0].claim, "e1 is-a Person");
        }
    }
}
