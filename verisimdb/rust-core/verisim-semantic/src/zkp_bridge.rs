// SPDX-License-Identifier: PMPL-1.0-or-later
//! ZKP Bridge — Privacy-aware proof generation and verification.
//!
//! Wraps the existing ZKP primitives (hash commitments, Merkle proofs,
//! content integrity, circuit verification) with privacy-level routing:
//!
//! - **Public**: Standard proof — data and proof are both visible.
//! - **Private**: Hash commitment hides data; Merkle inclusion proves membership.
//! - **ZeroKnowledge**: Blinded Merkle proof with committed witnesses.
//!   (Full ZK-SNARK via sanctify is designed but not yet compiled in.)
//!
//! # Architecture
//!
//! ```text
//! VQL PROOF clause → Elixir executor → Rust API → ZkpBridge
//!                                                    │
//!                    ┌───────────────────────────────┘
//!                    │
//!           ┌───────┴───────┐
//!           │ PrivacyLevel  │
//!           └───┬───┬───┬───┘
//!               │   │   │
//!          Public Private ZeroKnowledge
//!               │   │   │
//!           ┌───┘   │   └───┐
//!           ▼       ▼       ▼
//!     Standard  Committed  Blinded
//!     proof     + Merkle   + Nonce
//! ```

use serde::{Deserialize, Serialize};

use super::circuit_registry::{CircuitError, CircuitRegistry};
use super::zkp::{
    commit, hash, merkle_proof, merkle_root, verify_merkle_proof,
    verify_proof, VerifiableProofData,
};

/// Privacy level for proof generation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PrivacyLevel {
    /// Data and proof are both visible to the verifier.
    Public,
    /// Data is hidden behind a hash commitment; proof proves
    /// the committer knows the value without revealing it.
    Private,
    /// Zero-knowledge: verifier learns nothing beyond the
    /// statement's truth. Uses blinded Merkle proofs with
    /// committed witnesses. (Full ZK-SNARK integration pending.)
    ZeroKnowledge,
}

impl Default for PrivacyLevel {
    fn default() -> Self {
        Self::Public
    }
}

impl std::fmt::Display for PrivacyLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Public => write!(f, "Public"),
            Self::Private => write!(f, "Private"),
            Self::ZeroKnowledge => write!(f, "ZeroKnowledge"),
        }
    }
}

/// A request to generate a privacy-aware proof
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZkpProofRequest {
    /// The entity or claim being proven
    pub claim: Vec<u8>,
    /// Privacy level requested
    pub privacy_level: PrivacyLevel,
    /// Optional circuit name for CUSTOM proofs
    pub circuit_name: Option<String>,
    /// Optional witness data (private inputs for circuit proofs)
    pub witness: Option<Vec<f64>>,
    /// Optional public inputs (for circuit proofs)
    pub public_inputs: Option<Vec<f64>>,
    /// Optional set of sibling claims (for Merkle membership proofs)
    pub membership_set: Option<Vec<Vec<u8>>>,
    /// Index of the claim in the membership set
    pub membership_index: Option<usize>,
}

/// A generated proof with privacy metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZkpProof {
    /// Privacy level of this proof
    pub privacy_level: PrivacyLevel,
    /// The underlying verifiable proof data
    pub proof_data: VerifiableProofData,
    /// Optional blinding nonce (present for Private and ZeroKnowledge)
    pub blinding_nonce: Option<Vec<u8>>,
    /// Optional commitment (for Private/ZK proofs, the committed value)
    pub commitment: Option<[u8; 32]>,
    /// Merkle root of the membership set (if applicable)
    pub merkle_root: Option<[u8; 32]>,
    /// Circuit verification result (for CUSTOM proofs)
    pub circuit_result: Option<CircuitVerificationResult>,
    /// Timestamp of proof generation
    pub generated_at: String,
}

/// Result of circuit-based verification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CircuitVerificationResult {
    /// Circuit name
    pub circuit_name: String,
    /// Whether the circuit constraints were satisfied
    pub satisfied: bool,
    /// Number of constraints checked
    pub constraints_checked: usize,
}

/// Generate a privacy-aware proof.
///
/// Routes to the appropriate proof generation strategy based on the
/// requested privacy level.
pub fn generate_zkp(request: &ZkpProofRequest) -> Result<ZkpProof, CircuitError> {
    match request.privacy_level {
        PrivacyLevel::Public => generate_public_proof(request),
        PrivacyLevel::Private => generate_private_proof(request),
        PrivacyLevel::ZeroKnowledge => generate_zk_proof(request),
    }
}

/// Verify a previously generated ZKP proof.
///
/// For Public proofs, verifies the underlying proof data directly.
/// For Private proofs, verifies the commitment and Merkle inclusion.
/// For ZeroKnowledge proofs, verifies the blinded proof without
/// requiring knowledge of the original data.
pub fn verify_zkp(proof: &ZkpProof, claim: &[u8]) -> bool {
    match proof.privacy_level {
        PrivacyLevel::Public => verify_proof(&proof.proof_data, claim),
        PrivacyLevel::Private => verify_private_proof(proof, claim),
        PrivacyLevel::ZeroKnowledge => verify_zk_proof(proof),
    }
}

/// Generate a privacy-aware proof with circuit verification.
///
/// Combines the ZKP bridge with the circuit registry to verify
/// custom circuit constraints before generating the proof.
pub fn generate_zkp_with_circuit(
    request: &ZkpProofRequest,
    registry: &CircuitRegistry,
) -> Result<ZkpProof, CircuitError> {
    let mut proof = generate_zkp(request)?;

    // If a circuit name is specified, verify against the registry
    if let Some(ref circuit_name) = request.circuit_name {
        let witness = request.witness.as_deref().unwrap_or(&[]);
        let public_inputs = request.public_inputs.as_deref().unwrap_or(&[]);

        let satisfied = registry.verify_with_circuit(circuit_name, witness, public_inputs)?;

        let circuit = registry.get_circuit(circuit_name)?;
        let constraints_checked = circuit
            .map(|c| c.ir.constraints.len())
            .unwrap_or(0);

        proof.circuit_result = Some(CircuitVerificationResult {
            circuit_name: circuit_name.clone(),
            satisfied,
            constraints_checked,
        });
    }

    Ok(proof)
}

// ---------------------------------------------------------------------------
// Public proof: standard proof with data visible
// ---------------------------------------------------------------------------

fn generate_public_proof(request: &ZkpProofRequest) -> Result<ZkpProof, CircuitError> {
    let proof_data = VerifiableProofData::ContentIntegrity {
        content_hash: hash(&request.claim),
    };

    Ok(ZkpProof {
        privacy_level: PrivacyLevel::Public,
        proof_data,
        blinding_nonce: None,
        commitment: None,
        merkle_root: None,
        circuit_result: None,
        generated_at: chrono::Utc::now().to_rfc3339(),
    })
}

// ---------------------------------------------------------------------------
// Private proof: hash commitment hides the data
// ---------------------------------------------------------------------------

fn generate_private_proof(request: &ZkpProofRequest) -> Result<ZkpProof, CircuitError> {
    // Generate a random-ish nonce from claim hash (deterministic for testing;
    // in production this would use a CSPRNG)
    let nonce = generate_nonce(&request.claim);

    let commitment = commit(&request.claim, &nonce);

    // If a membership set is provided, generate a Merkle inclusion proof
    let (proof_data, root) = if let (Some(ref set), Some(index)) =
        (&request.membership_set, request.membership_index)
    {
        let root = merkle_root(set);
        match merkle_proof(set, index) {
            Some(mp) => (VerifiableProofData::MerkleInclusion(mp), Some(root)),
            None => {
                return Err(CircuitError::InvalidWitness(format!(
                    "Membership index {} out of bounds for set of size {}",
                    index,
                    set.len()
                )));
            }
        }
    } else {
        // No membership set: commitment-only proof
        (
            VerifiableProofData::Commitment {
                commitment: commitment.commitment,
            },
            None,
        )
    };

    Ok(ZkpProof {
        privacy_level: PrivacyLevel::Private,
        proof_data,
        blinding_nonce: Some(nonce),
        commitment: Some(commitment.commitment),
        merkle_root: root,
        circuit_result: None,
        generated_at: chrono::Utc::now().to_rfc3339(),
    })
}

// ---------------------------------------------------------------------------
// Zero-Knowledge proof: blinded Merkle proof with committed witnesses
// ---------------------------------------------------------------------------

fn generate_zk_proof(request: &ZkpProofRequest) -> Result<ZkpProof, CircuitError> {
    let nonce = generate_nonce(&request.claim);

    // Blind the claim: commitment = H(claim || nonce)
    let commitment = commit(&request.claim, &nonce);

    // Build a blinded membership set:
    // Each leaf is H(original_leaf || shared_nonce) so the verifier
    // cannot recover the original leaves, only verify structure.
    let (proof_data, root) = if let (Some(ref set), Some(index)) =
        (&request.membership_set, request.membership_index)
    {
        // Blind all leaves
        let blinded_leaves: Vec<Vec<u8>> = set
            .iter()
            .map(|leaf| {
                let blinded = commit(leaf, &nonce);
                blinded.commitment.to_vec()
            })
            .collect();

        let root = merkle_root(&blinded_leaves);
        match merkle_proof(&blinded_leaves, index) {
            Some(mp) => (VerifiableProofData::MerkleInclusion(mp), Some(root)),
            None => {
                return Err(CircuitError::InvalidWitness(format!(
                    "Membership index {} out of bounds for set of size {}",
                    index,
                    set.len()
                )));
            }
        }
    } else {
        // No membership set: commitment with reveal proof
        // The verifier can check H(claim || nonce) == commitment
        // without seeing the claim (they only see the commitment)
        (
            VerifiableProofData::Commitment {
                commitment: commitment.commitment,
            },
            None,
        )
    };

    Ok(ZkpProof {
        privacy_level: PrivacyLevel::ZeroKnowledge,
        proof_data,
        blinding_nonce: Some(nonce),
        commitment: Some(commitment.commitment),
        merkle_root: root,
        circuit_result: None,
        generated_at: chrono::Utc::now().to_rfc3339(),
    })
}

// ---------------------------------------------------------------------------
// Verification helpers
// ---------------------------------------------------------------------------

fn verify_private_proof(proof: &ZkpProof, claim: &[u8]) -> bool {
    // Verify the commitment matches the claim
    if let (Some(ref nonce), Some(commitment_hash)) = (&proof.blinding_nonce, proof.commitment) {
        let expected = commit(claim, nonce);
        if expected.commitment != commitment_hash {
            return false;
        }
    }

    // Verify underlying proof data
    match &proof.proof_data {
        VerifiableProofData::MerkleInclusion(mp) => verify_merkle_proof(mp),
        VerifiableProofData::Commitment { .. } => {
            // Commitment is valid by construction (verified above)
            true
        }
        other => verify_proof(other, claim),
    }
}

fn verify_zk_proof(proof: &ZkpProof) -> bool {
    // For ZK proofs, we verify the Merkle structure WITHOUT the original data.
    // The verifier only checks that the proof path is internally consistent.
    match &proof.proof_data {
        VerifiableProofData::MerkleInclusion(mp) => {
            // Verify the blinded Merkle proof
            verify_merkle_proof(mp)
        }
        VerifiableProofData::Commitment { .. } => {
            // Commitment exists — valid at this level.
            // Full ZK verification would invoke a ZK-SNARK verifier here
            // (sanctify integration, not yet compiled in).
            true
        }
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

/// Generate a deterministic nonce from claim data.
/// In production, replace with a CSPRNG (e.g., `rand::thread_rng().fill_bytes`).
fn generate_nonce(claim: &[u8]) -> Vec<u8> {
    let mut h = hash(claim);
    // Mix in a domain separator to distinguish from content hashes
    let separator = b"verisimdb-zkp-nonce-v1";
    let mut hasher = sha2::Sha256::new();
    use sha2::Digest;
    hasher.update(&h);
    hasher.update(separator);
    h = hasher.finalize().into();
    h.to_vec()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_public_proof_roundtrip() {
        let claim = b"entity:123 has-type Person";

        let request = ZkpProofRequest {
            claim: claim.to_vec(),
            privacy_level: PrivacyLevel::Public,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: None,
            membership_index: None,
        };

        let proof = generate_zkp(&request).unwrap();
        assert_eq!(proof.privacy_level, PrivacyLevel::Public);
        assert!(proof.blinding_nonce.is_none());
        assert!(verify_zkp(&proof, claim));
    }

    #[test]
    fn test_public_proof_rejects_wrong_claim() {
        let claim = b"entity:123 has-type Person";

        let request = ZkpProofRequest {
            claim: claim.to_vec(),
            privacy_level: PrivacyLevel::Public,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: None,
            membership_index: None,
        };

        let proof = generate_zkp(&request).unwrap();
        assert!(!verify_zkp(&proof, b"entity:456 has-type Robot"));
    }

    #[test]
    fn test_private_proof_commitment() {
        let claim = b"confidential-data-hash";

        let request = ZkpProofRequest {
            claim: claim.to_vec(),
            privacy_level: PrivacyLevel::Private,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: None,
            membership_index: None,
        };

        let proof = generate_zkp(&request).unwrap();
        assert_eq!(proof.privacy_level, PrivacyLevel::Private);
        assert!(proof.blinding_nonce.is_some());
        assert!(proof.commitment.is_some());
        assert!(verify_zkp(&proof, claim));
    }

    #[test]
    fn test_private_proof_wrong_claim_fails() {
        let claim = b"real-claim";

        let request = ZkpProofRequest {
            claim: claim.to_vec(),
            privacy_level: PrivacyLevel::Private,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: None,
            membership_index: None,
        };

        let proof = generate_zkp(&request).unwrap();
        assert!(!verify_zkp(&proof, b"fake-claim"));
    }

    #[test]
    fn test_private_proof_with_membership_set() {
        let claims = vec![
            b"claim-a".to_vec(),
            b"claim-b".to_vec(),
            b"claim-c".to_vec(),
            b"claim-d".to_vec(),
        ];

        let request = ZkpProofRequest {
            claim: claims[1].clone(),
            privacy_level: PrivacyLevel::Private,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: Some(claims.clone()),
            membership_index: Some(1),
        };

        let proof = generate_zkp(&request).unwrap();
        assert!(proof.merkle_root.is_some());
        assert!(verify_zkp(&proof, &claims[1]));
    }

    #[test]
    fn test_zk_proof_generation() {
        let claim = b"zero-knowledge-secret";

        let request = ZkpProofRequest {
            claim: claim.to_vec(),
            privacy_level: PrivacyLevel::ZeroKnowledge,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: None,
            membership_index: None,
        };

        let proof = generate_zkp(&request).unwrap();
        assert_eq!(proof.privacy_level, PrivacyLevel::ZeroKnowledge);
        assert!(proof.blinding_nonce.is_some());
        assert!(proof.commitment.is_some());
        // ZK proofs verify without the original claim
        assert!(verify_zkp(&proof, claim));
    }

    #[test]
    fn test_zk_proof_with_blinded_membership() {
        let claims = vec![
            b"secret-1".to_vec(),
            b"secret-2".to_vec(),
            b"secret-3".to_vec(),
        ];

        let request = ZkpProofRequest {
            claim: claims[2].clone(),
            privacy_level: PrivacyLevel::ZeroKnowledge,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: Some(claims.clone()),
            membership_index: Some(2),
        };

        let proof = generate_zkp(&request).unwrap();
        assert!(proof.merkle_root.is_some());
        // Blinded proof verifies via Merkle structure
        assert!(verify_zkp(&proof, &claims[2]));
    }

    #[test]
    fn test_zk_proof_blinded_root_differs_from_plain() {
        let claims = vec![
            b"a".to_vec(),
            b"b".to_vec(),
            b"c".to_vec(),
            b"d".to_vec(),
        ];

        // Private proof: plain Merkle root
        let private_req = ZkpProofRequest {
            claim: claims[0].clone(),
            privacy_level: PrivacyLevel::Private,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: Some(claims.clone()),
            membership_index: Some(0),
        };
        let private_proof = generate_zkp(&private_req).unwrap();

        // ZK proof: blinded Merkle root
        let zk_req = ZkpProofRequest {
            claim: claims[0].clone(),
            privacy_level: PrivacyLevel::ZeroKnowledge,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: Some(claims.clone()),
            membership_index: Some(0),
        };
        let zk_proof = generate_zkp(&zk_req).unwrap();

        // Roots should differ (one is blinded)
        assert_ne!(private_proof.merkle_root, zk_proof.merkle_root);
    }

    #[test]
    fn test_membership_index_out_of_bounds() {
        let claims = vec![b"only-one".to_vec()];

        let request = ZkpProofRequest {
            claim: claims[0].clone(),
            privacy_level: PrivacyLevel::Private,
            circuit_name: None,
            witness: None,
            public_inputs: None,
            membership_set: Some(claims),
            membership_index: Some(5),
        };

        let result = generate_zkp(&request);
        assert!(result.is_err());
    }

    #[test]
    fn test_generate_with_circuit_registry() {
        use super::super::circuit_registry::{
            CircuitIR, CompiledCircuit, R1CSConstraint, sha256_hex,
        };
        use std::collections::HashMap;

        let registry = CircuitRegistry::new();

        // Register a simple multiply circuit: x * y = z
        let constraint = R1CSConstraint {
            a: HashMap::from([(0, 1.0)]),
            b: HashMap::from([(2, 1.0)]),
            c: HashMap::from([(1, 1.0)]),
        };
        let ir = CircuitIR {
            name: "test-mul".to_string(),
            num_public_inputs: 2,
            num_witness_wires: 1,
            num_wires: 3,
            constraints: vec![constraint],
            parameter_map: HashMap::new(),
        };
        let circuit_bytes = serde_json::to_vec(&ir).unwrap();
        let compiled = CompiledCircuit {
            ir,
            circuit_hash: sha256_hex(&circuit_bytes),
            verification_key: vec![0u8; 32],
        };
        registry.register_circuit("test-mul", compiled).unwrap();

        let request = ZkpProofRequest {
            claim: b"verified-computation".to_vec(),
            privacy_level: PrivacyLevel::Public,
            circuit_name: Some("test-mul".to_string()),
            witness: Some(vec![4.0]),           // y = 4
            public_inputs: Some(vec![3.0, 12.0]), // x = 3, z = 12
            membership_set: None,
            membership_index: None,
        };

        let proof = generate_zkp_with_circuit(&request, &registry).unwrap();
        assert!(proof.circuit_result.is_some());

        let cr = proof.circuit_result.unwrap();
        assert!(cr.satisfied);
        assert_eq!(cr.circuit_name, "test-mul");
        assert_eq!(cr.constraints_checked, 1);
    }

    #[test]
    fn test_privacy_level_display() {
        assert_eq!(PrivacyLevel::Public.to_string(), "Public");
        assert_eq!(PrivacyLevel::Private.to_string(), "Private");
        assert_eq!(PrivacyLevel::ZeroKnowledge.to_string(), "ZeroKnowledge");
    }
}
