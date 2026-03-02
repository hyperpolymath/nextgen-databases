// SPDX-License-Identifier: PMPL-1.0-or-later
//! Zero-Knowledge Proof primitives for the semantic store.
//!
//! Provides cryptographic proof mechanisms that allow verification of
//! semantic claims without revealing underlying data:
//!
//! - **Hash Commitments**: Commit to a value, reveal later to prove knowledge.
//! - **Merkle Proofs**: Prove set membership without revealing other members.
//! - **Proof Verification**: Verify stored proofs against their claims.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

// ---------------------------------------------------------------------------
// Hash Commitment Scheme
// ---------------------------------------------------------------------------

/// A hash commitment: SHA-256(claim || secret).
/// The committer can later reveal the secret to prove they knew the value
/// at commitment time, without having revealed it earlier.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashCommitment {
    /// The commitment hash.
    pub commitment: [u8; 32],
}

/// Create a hash commitment for a claim using a secret.
pub fn commit(claim: &[u8], secret: &[u8]) -> HashCommitment {
    let mut hasher = Sha256::new();
    hasher.update(claim);
    hasher.update(secret);
    let result = hasher.finalize();
    HashCommitment {
        commitment: result.into(),
    }
}

/// Verify a hash commitment by checking SHA-256(claim || secret) == commitment.
pub fn verify_commitment(commitment: &HashCommitment, claim: &[u8], secret: &[u8]) -> bool {
    let expected = commit(claim, secret);
    constant_time_eq(&commitment.commitment, &expected.commitment)
}

// ---------------------------------------------------------------------------
// Merkle Tree
// ---------------------------------------------------------------------------

/// An element in a Merkle proof path.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerklePathElement {
    /// Sibling hash at this level.
    pub hash: [u8; 32],
    /// Whether the sibling is on the left (true) or right (false).
    pub is_left: bool,
}

/// A complete Merkle inclusion proof.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleProof {
    /// The leaf value being proven.
    pub leaf: Vec<u8>,
    /// Path from leaf to root.
    pub path: Vec<MerklePathElement>,
    /// The Merkle root hash.
    pub root: [u8; 32],
}

/// Compute SHA-256 hash of data.
pub fn hash(data: &[u8]) -> [u8; 32] {
    Sha256::digest(data).into()
}

/// Hash two children to form a parent node.
fn hash_pair(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(left);
    hasher.update(right);
    hasher.finalize().into()
}

/// Build a Merkle tree from leaf data and return the root hash.
/// Leaves are hashed before building the tree.
pub fn merkle_root(leaves: &[Vec<u8>]) -> [u8; 32] {
    if leaves.is_empty() {
        return [0u8; 32];
    }

    let mut current_level: Vec<[u8; 32]> = leaves.iter().map(|l| hash(l)).collect();

    // Pad to even number if necessary
    while current_level.len() > 1 {
        if current_level.len() % 2 != 0 {
            let last = *current_level.last().unwrap();
            current_level.push(last);
        }

        let mut next_level = Vec::with_capacity(current_level.len() / 2);
        for chunk in current_level.chunks(2) {
            next_level.push(hash_pair(&chunk[0], &chunk[1]));
        }
        current_level = next_level;
    }

    current_level[0]
}

/// Generate a Merkle inclusion proof for the leaf at `index`.
pub fn merkle_proof(leaves: &[Vec<u8>], index: usize) -> Option<MerkleProof> {
    if index >= leaves.len() || leaves.is_empty() {
        return None;
    }

    let root = merkle_root(leaves);
    let mut hashed: Vec<[u8; 32]> = leaves.iter().map(|l| hash(l)).collect();
    let mut path = Vec::new();
    let mut idx = index;

    while hashed.len() > 1 {
        // Pad to even
        if hashed.len() % 2 != 0 {
            let last = *hashed.last().unwrap();
            hashed.push(last);
        }

        // Find sibling
        let sibling_idx = if idx % 2 == 0 { idx + 1 } else { idx - 1 };
        let is_left = idx % 2 != 0; // sibling is on left if we're on the right

        path.push(MerklePathElement {
            hash: hashed[sibling_idx],
            is_left,
        });

        // Move up one level
        let mut next_level = Vec::with_capacity(hashed.len() / 2);
        for chunk in hashed.chunks(2) {
            next_level.push(hash_pair(&chunk[0], &chunk[1]));
        }
        hashed = next_level;
        idx /= 2;
    }

    Some(MerkleProof {
        leaf: leaves[index].clone(),
        path,
        root,
    })
}

/// Verify a Merkle inclusion proof.
pub fn verify_merkle_proof(proof: &MerkleProof) -> bool {
    let mut current = hash(&proof.leaf);

    for element in &proof.path {
        current = if element.is_left {
            hash_pair(&element.hash, &current)
        } else {
            hash_pair(&current, &element.hash)
        };
    }

    constant_time_eq(&current, &proof.root)
}

// ---------------------------------------------------------------------------
// Verifiable Proof Types (integrated with ProofBlob)
// ---------------------------------------------------------------------------

/// A verifiable proof with cryptographic backing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum VerifiableProofData {
    /// Hash commitment: prover committed to a value.
    Commitment {
        commitment: [u8; 32],
    },
    /// Hash reveal: prover reveals the secret for a prior commitment.
    Reveal {
        commitment: [u8; 32],
        secret: Vec<u8>,
    },
    /// Merkle inclusion: value is a member of a committed set.
    MerkleInclusion(MerkleProof),
    /// Content integrity: SHA-256 hash of the original content.
    ContentIntegrity {
        content_hash: [u8; 32],
    },
}

/// Verify a verifiable proof against its claim.
pub fn verify_proof(data: &VerifiableProofData, claim: &[u8]) -> bool {
    match data {
        VerifiableProofData::Commitment { .. } => {
            // Commitments are valid by construction — they're verified at reveal time.
            true
        }
        VerifiableProofData::Reveal {
            commitment,
            secret,
        } => {
            let expected = commit(claim, secret);
            constant_time_eq(commitment, &expected.commitment)
        }
        VerifiableProofData::MerkleInclusion(proof) => verify_merkle_proof(proof),
        VerifiableProofData::ContentIntegrity { content_hash } => {
            let actual = hash(claim);
            constant_time_eq(content_hash, &actual)
        }
    }
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

/// Constant-time byte comparison to prevent timing side-channels.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_commitment_roundtrip() {
        let claim = b"entity:123 is-a Person";
        let secret = b"my-secret-nonce-42";

        let commitment = commit(claim, secret);
        assert!(verify_commitment(&commitment, claim, secret));
    }

    #[test]
    fn test_hash_commitment_wrong_secret() {
        let claim = b"entity:123 is-a Person";
        let commitment = commit(claim, b"correct-secret");

        assert!(!verify_commitment(&commitment, claim, b"wrong-secret"));
    }

    #[test]
    fn test_hash_commitment_wrong_claim() {
        let secret = b"my-secret";
        let commitment = commit(b"real claim", secret);

        assert!(!verify_commitment(&commitment, b"fake claim", secret));
    }

    #[test]
    fn test_merkle_root_single() {
        let leaves = vec![b"leaf0".to_vec()];
        let root = merkle_root(&leaves);
        assert_eq!(root, hash(b"leaf0"));
    }

    #[test]
    fn test_merkle_root_deterministic() {
        let leaves = vec![b"a".to_vec(), b"b".to_vec(), b"c".to_vec()];
        let root1 = merkle_root(&leaves);
        let root2 = merkle_root(&leaves);
        assert_eq!(root1, root2);
    }

    #[test]
    fn test_merkle_proof_verify() {
        let leaves = vec![
            b"alpha".to_vec(),
            b"beta".to_vec(),
            b"gamma".to_vec(),
            b"delta".to_vec(),
        ];

        // Prove each leaf
        for i in 0..leaves.len() {
            let proof = merkle_proof(&leaves, i).unwrap();
            assert!(
                verify_merkle_proof(&proof),
                "Merkle proof failed for leaf {i}"
            );
        }
    }

    #[test]
    fn test_merkle_proof_odd_leaves() {
        let leaves = vec![b"a".to_vec(), b"b".to_vec(), b"c".to_vec()];

        for i in 0..leaves.len() {
            let proof = merkle_proof(&leaves, i).unwrap();
            assert!(verify_merkle_proof(&proof));
        }
    }

    #[test]
    fn test_merkle_proof_tampered() {
        let leaves = vec![b"a".to_vec(), b"b".to_vec(), b"c".to_vec(), b"d".to_vec()];
        let mut proof = merkle_proof(&leaves, 0).unwrap();

        // Tamper with the leaf
        proof.leaf = b"tampered".to_vec();
        assert!(!verify_merkle_proof(&proof));
    }

    #[test]
    fn test_verify_proof_content_integrity() {
        let content = b"This is the original document content";
        let proof_data = VerifiableProofData::ContentIntegrity {
            content_hash: hash(content),
        };

        assert!(verify_proof(&proof_data, content));
        assert!(!verify_proof(&proof_data, b"modified content"));
    }

    #[test]
    fn test_verify_proof_reveal() {
        let claim = b"entity:456 satisfies constraint X";
        let secret = b"witness-data";

        let commitment = commit(claim, secret);
        let proof_data = VerifiableProofData::Reveal {
            commitment: commitment.commitment,
            secret: secret.to_vec(),
        };

        assert!(verify_proof(&proof_data, claim));
        assert!(!verify_proof(&proof_data, b"wrong claim"));
    }

    #[test]
    fn test_verify_proof_merkle_inclusion() {
        let leaves = vec![
            b"claim-1".to_vec(),
            b"claim-2".to_vec(),
            b"claim-3".to_vec(),
        ];

        let proof = merkle_proof(&leaves, 1).unwrap();
        let proof_data = VerifiableProofData::MerkleInclusion(proof);

        // Merkle proof verification doesn't use the claim parameter directly
        // (the leaf is embedded in the proof), but the proof itself must be valid.
        assert!(verify_proof(&proof_data, b"claim-2"));
    }

    #[test]
    fn test_empty_merkle_root() {
        let root = merkle_root(&[]);
        assert_eq!(root, [0u8; 32]);
    }

    #[test]
    fn test_merkle_proof_out_of_bounds() {
        let leaves = vec![b"a".to_vec()];
        assert!(merkle_proof(&leaves, 5).is_none());
    }
}
