// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Semantic Modality
//!
//! Ontology and type system with CBOR proof serialization.
//! Implements Marr's Computational Level: "What does this mean?"

pub mod zkp;
pub mod zkp_bridge;
pub mod proven_bridge;
pub mod sanctify_bridge;
pub mod circuit_registry;
pub mod circuit_compiler;
pub mod verification_keys;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;

/// Semantic modality errors
#[derive(Error, Debug)]
pub enum SemanticError {
    #[error("Type not found: {0}")]
    TypeNotFound(String),

    #[error("Constraint violation: {0}")]
    ConstraintViolation(String),

    #[error("Invalid proof: {0}")]
    InvalidProof(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Lock poisoned: internal concurrency error")]
    LockPoisoned,
}

/// A semantic type in the ontology
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct SemanticType {
    /// Type IRI (fully qualified name)
    pub iri: String,
    /// Human-readable label
    pub label: String,
    /// Parent types (for inheritance)
    pub supertypes: Vec<String>,
    /// Constraints that instances must satisfy
    pub constraints: Vec<Constraint>,
}

impl SemanticType {
    /// Create a new semantic type
    pub fn new(iri: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            iri: iri.into(),
            label: label.into(),
            supertypes: Vec::new(),
            constraints: Vec::new(),
        }
    }

    /// Add a supertype
    pub fn with_supertype(mut self, supertype: impl Into<String>) -> Self {
        self.supertypes.push(supertype.into());
        self
    }

    /// Add a constraint
    pub fn with_constraint(mut self, constraint: Constraint) -> Self {
        self.constraints.push(constraint);
        self
    }
}

/// Constraint on a semantic type
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Constraint {
    /// Constraint name
    pub name: String,
    /// Constraint kind
    pub kind: ConstraintKind,
    /// Error message on violation
    pub message: String,
}

/// Kinds of constraints
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ConstraintKind {
    /// Property must exist
    Required(String),
    /// Property must match pattern
    Pattern { property: String, regex: String },
    /// Property must be in range
    Range { property: String, min: Option<i64>, max: Option<i64> },
    /// Custom validation (reference to validator function)
    Custom(String),
}

/// A semantic annotation on an entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SemanticAnnotation {
    /// Entity ID being annotated
    pub entity_id: String,
    /// Type assignments
    pub types: Vec<String>,
    /// Property values with semantic meaning
    pub properties: HashMap<String, SemanticValue>,
    /// Provenance information
    pub provenance: Provenance,
}

/// A semantically-typed value
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SemanticValue {
    /// String with language tag
    LangString { value: String, lang: String },
    /// Typed literal
    TypedLiteral { value: String, datatype: String },
    /// Reference to another entity
    Reference(String),
    /// Collection of values
    Collection(Vec<SemanticValue>),
}

/// Provenance information for audit
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provenance {
    /// When the annotation was created
    pub created_at: String,
    /// Who/what created it
    pub created_by: String,
    /// Source of the information
    pub source: Option<String>,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f64,
}

impl Default for Provenance {
    fn default() -> Self {
        Self {
            created_at: chrono::Utc::now().to_rfc3339(),
            created_by: "system".to_string(),
            source: None,
            confidence: 1.0,
        }
    }
}

/// Proof blob for verified semantic claims
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofBlob {
    /// Claim being proven
    pub claim: String,
    /// Type of proof
    pub proof_type: ProofType,
    /// Serialized proof data (CBOR)
    pub data: Vec<u8>,
    /// Timestamp
    pub timestamp: String,
}

/// Types of proofs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ProofType {
    /// Type assignment proof
    TypeAssignment,
    /// Constraint satisfaction proof
    ConstraintSatisfaction,
    /// Derivation proof (inferred from other facts)
    Derivation,
    /// External attestation
    Attestation,
}

impl ProofBlob {
    /// Create a new proof blob
    pub fn new(claim: impl Into<String>, proof_type: ProofType, data: Vec<u8>) -> Self {
        Self {
            claim: claim.into(),
            proof_type,
            data,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// Serialize to CBOR
    pub fn to_cbor(&self) -> Result<Vec<u8>, SemanticError> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf)
            .map_err(|e| SemanticError::SerializationError(e.to_string()))?;
        Ok(buf)
    }

    /// Deserialize from CBOR
    pub fn from_cbor(data: &[u8]) -> Result<Self, SemanticError> {
        ciborium::from_reader(data)
            .map_err(|e| SemanticError::SerializationError(e.to_string()))
    }

    /// Verify the proof data against the claim.
    ///
    /// Interprets `self.data` as CBOR-encoded [`zkp::VerifiableProofData`] and
    /// verifies it cryptographically against `self.claim`.
    pub fn verify(&self) -> Result<bool, SemanticError> {
        // Try to decode data as VerifiableProofData (CBOR)
        let proof_data: Result<zkp::VerifiableProofData, _> = ciborium::from_reader(&self.data[..]);

        match proof_data {
            Ok(data) => Ok(zkp::verify_proof(&data, self.claim.as_bytes())),
            Err(_) => {
                // Legacy proofs without ZKP data: verify based on proof type
                match self.proof_type {
                    ProofType::Attestation => {
                        // Attestation proofs are trusted (external authority)
                        Ok(true)
                    }
                    ProofType::ConstraintSatisfaction => {
                        // Without ZKP data, we can only check non-empty
                        Ok(!self.data.is_empty())
                    }
                    ProofType::Derivation | ProofType::TypeAssignment => {
                        // Legacy: accept if data is present
                        Ok(!self.data.is_empty())
                    }
                }
            }
        }
    }
}

/// Semantic store trait for cross-modal consistency
#[async_trait]
pub trait SemanticStore: Send + Sync {
    /// Register a type in the ontology
    async fn register_type(&self, typ: &SemanticType) -> Result<(), SemanticError>;

    /// Get a type by IRI
    async fn get_type(&self, iri: &str) -> Result<Option<SemanticType>, SemanticError>;

    /// Annotate an entity
    async fn annotate(&self, annotation: &SemanticAnnotation) -> Result<(), SemanticError>;

    /// Get annotations for an entity
    async fn get_annotations(&self, entity_id: &str) -> Result<Option<SemanticAnnotation>, SemanticError>;

    /// Validate an annotation against type constraints
    async fn validate(&self, annotation: &SemanticAnnotation) -> Result<Vec<String>, SemanticError>;

    /// Store a proof blob
    async fn store_proof(&self, proof: &ProofBlob) -> Result<(), SemanticError>;

    /// Retrieve proofs for a claim
    async fn get_proofs(&self, claim: &str) -> Result<Vec<ProofBlob>, SemanticError>;

    /// Verify all proofs for a claim, returning (valid_count, total_count).
    async fn verify_proofs(&self, claim: &str) -> Result<(usize, usize), SemanticError> {
        let proofs = self.get_proofs(claim).await?;
        let total = proofs.len();
        let valid = proofs.iter().filter(|p| p.verify().unwrap_or(false)).count();
        Ok((valid, total))
    }
}

/// In-memory semantic store
pub struct InMemorySemanticStore {
    types: Arc<RwLock<HashMap<String, SemanticType>>>,
    annotations: Arc<RwLock<HashMap<String, SemanticAnnotation>>>,
    proofs: Arc<RwLock<HashMap<String, Vec<ProofBlob>>>>,
}

impl InMemorySemanticStore {
    pub fn new() -> Self {
        Self {
            types: Arc::new(RwLock::new(HashMap::new())),
            annotations: Arc::new(RwLock::new(HashMap::new())),
            proofs: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl Default for InMemorySemanticStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl SemanticStore for InMemorySemanticStore {
    async fn register_type(&self, typ: &SemanticType) -> Result<(), SemanticError> {
        self.types.write().map_err(|_| SemanticError::LockPoisoned)?.insert(typ.iri.clone(), typ.clone());
        Ok(())
    }

    async fn get_type(&self, iri: &str) -> Result<Option<SemanticType>, SemanticError> {
        Ok(self.types.read().map_err(|_| SemanticError::LockPoisoned)?.get(iri).cloned())
    }

    async fn annotate(&self, annotation: &SemanticAnnotation) -> Result<(), SemanticError> {
        // Validate first
        let violations = self.validate(annotation).await?;
        if !violations.is_empty() {
            return Err(SemanticError::ConstraintViolation(violations.join("; ")));
        }
        self.annotations.write().map_err(|_| SemanticError::LockPoisoned)?.insert(annotation.entity_id.clone(), annotation.clone());
        Ok(())
    }

    async fn get_annotations(&self, entity_id: &str) -> Result<Option<SemanticAnnotation>, SemanticError> {
        Ok(self.annotations.read().map_err(|_| SemanticError::LockPoisoned)?.get(entity_id).cloned())
    }

    async fn validate(&self, annotation: &SemanticAnnotation) -> Result<Vec<String>, SemanticError> {
        let types = self.types.read().map_err(|_| SemanticError::LockPoisoned)?;
        let mut violations = Vec::new();

        for type_iri in &annotation.types {
            if let Some(typ) = types.get(type_iri) {
                for constraint in &typ.constraints {
                    match &constraint.kind {
                        ConstraintKind::Required(prop) => {
                            if !annotation.properties.contains_key(prop) {
                                violations.push(format!("{}: {}", constraint.name, constraint.message));
                            }
                        }
                        ConstraintKind::Pattern { property, regex } => {
                            if let Some(SemanticValue::TypedLiteral { value, .. }) = annotation.properties.get(property) {
                                let re = regex::Regex::new(regex).ok();
                                if let Some(re) = re {
                                    if !re.is_match(value) {
                                        violations.push(format!("{}: {}", constraint.name, constraint.message));
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
        self.proofs.write().map_err(|_| SemanticError::LockPoisoned)?
            .entry(proof.claim.clone())
            .or_default()
            .push(proof.clone());
        Ok(())
    }

    async fn get_proofs(&self, claim: &str) -> Result<Vec<ProofBlob>, SemanticError> {
        Ok(self.proofs.read().map_err(|_| SemanticError::LockPoisoned)?.get(claim).cloned().unwrap_or_default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_type_registration() {
        let store = InMemorySemanticStore::new();

        let person_type = SemanticType::new("https://example.org/Person", "Person")
            .with_constraint(Constraint {
                name: "name_required".to_string(),
                kind: ConstraintKind::Required("name".to_string()),
                message: "Person must have a name".to_string(),
            });

        store.register_type(&person_type).await.unwrap();

        let retrieved = store.get_type("https://example.org/Person").await.unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().label, "Person");
    }

    #[test]
    fn test_proof_blob_cbor() {
        let proof = ProofBlob::new(
            "entity:123 is-a Person",
            ProofType::TypeAssignment,
            vec![1, 2, 3, 4],
        );

        let cbor = proof.to_cbor().unwrap();
        let decoded = ProofBlob::from_cbor(&cbor).unwrap();

        assert_eq!(decoded.claim, proof.claim);
    }
}
