// SPDX-License-Identifier: PMPL-1.0-or-later
//! Verification Key Management for VeriSimDB Custom Circuits
//!
//! Stores verification keys per circuit with support for key rotation
//! and federation key export/import (peers need matching keys to verify
//! proofs from other instances).

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::RwLock;

use super::circuit_registry::CircuitError;

/// A verification key entry with rotation support
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationKeyEntry {
    /// Circuit name this key belongs to
    pub circuit_name: String,
    /// Current active key
    pub active_key: Vec<u8>,
    /// Key version (monotonically increasing)
    pub version: u64,
    /// SHA-256 fingerprint of the key (for quick comparison)
    pub fingerprint: String,
    /// Previous key (for graceful rotation — accept proofs from both during transition)
    pub previous_key: Option<Vec<u8>>,
    /// When this key version was created (ISO 8601)
    pub created_at: String,
}

impl VerificationKeyEntry {
    /// Create a new key entry
    pub fn new(circuit_name: &str, key: Vec<u8>) -> Self {
        let fingerprint = key_fingerprint(&key);
        Self {
            circuit_name: circuit_name.to_string(),
            active_key: key,
            version: 1,
            fingerprint,
            previous_key: None,
            created_at: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// Rotate to a new key, keeping the old one as previous
    pub fn rotate(&mut self, new_key: Vec<u8>) {
        self.previous_key = Some(self.active_key.clone());
        self.active_key = new_key;
        self.fingerprint = key_fingerprint(&self.active_key);
        self.version += 1;
        self.created_at = chrono::Utc::now().to_rfc3339();
    }

    /// Check if a given key matches the active or previous key
    pub fn matches(&self, key: &[u8]) -> bool {
        self.active_key == key
            || self
                .previous_key
                .as_ref()
                .is_some_and(|prev| prev == key)
    }
}

/// Compute SHA-256 fingerprint of a key
fn key_fingerprint(key: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(key);
    let result = hasher.finalize();
    result.iter().map(|b| format!("{:02x}", b)).collect()
}

/// Exportable key bundle for federation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyExportBundle {
    /// Source instance identifier
    pub source_instance: String,
    /// Map of circuit_name → (key_bytes, version, fingerprint)
    pub keys: Vec<ExportedKey>,
}

/// A single exported key
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportedKey {
    pub circuit_name: String,
    pub key: Vec<u8>,
    pub version: u64,
    pub fingerprint: String,
}

/// The verification key store
pub struct VerificationKeyStore {
    keys: RwLock<HashMap<String, VerificationKeyEntry>>,
    instance_id: String,
}

impl VerificationKeyStore {
    /// Create a new key store
    pub fn new(instance_id: &str) -> Self {
        Self {
            keys: RwLock::new(HashMap::new()),
            instance_id: instance_id.to_string(),
        }
    }

    /// Store a verification key for a circuit
    pub fn store_key(
        &self,
        circuit_name: &str,
        key: Vec<u8>,
    ) -> Result<(), CircuitError> {
        let mut keys = self.keys.write().map_err(|_| CircuitError::LockPoisoned)?;

        if let Some(entry) = keys.get_mut(circuit_name) {
            entry.rotate(key);
        } else {
            keys.insert(
                circuit_name.to_string(),
                VerificationKeyEntry::new(circuit_name, key),
            );
        }

        Ok(())
    }

    /// Get the active key for a circuit
    pub fn get_key(&self, circuit_name: &str) -> Result<Option<Vec<u8>>, CircuitError> {
        let keys = self.keys.read().map_err(|_| CircuitError::LockPoisoned)?;
        Ok(keys.get(circuit_name).map(|e| e.active_key.clone()))
    }

    /// Get full key entry (including version and previous key)
    pub fn get_entry(
        &self,
        circuit_name: &str,
    ) -> Result<Option<VerificationKeyEntry>, CircuitError> {
        let keys = self.keys.read().map_err(|_| CircuitError::LockPoisoned)?;
        Ok(keys.get(circuit_name).cloned())
    }

    /// Export all keys for federation sharing
    pub fn export_keys(&self) -> Result<KeyExportBundle, CircuitError> {
        let keys = self.keys.read().map_err(|_| CircuitError::LockPoisoned)?;

        let exported = keys
            .values()
            .map(|entry| ExportedKey {
                circuit_name: entry.circuit_name.clone(),
                key: entry.active_key.clone(),
                version: entry.version,
                fingerprint: entry.fingerprint.clone(),
            })
            .collect();

        Ok(KeyExportBundle {
            source_instance: self.instance_id.clone(),
            keys: exported,
        })
    }

    /// Import keys from a federation peer
    pub fn import_keys(&self, bundle: &KeyExportBundle) -> Result<usize, CircuitError> {
        let mut keys = self.keys.write().map_err(|_| CircuitError::LockPoisoned)?;
        let mut imported = 0;

        for exported in &bundle.keys {
            let federated_name = format!("{}:{}", bundle.source_instance, exported.circuit_name);

            match keys.get_mut(&federated_name) {
                Some(entry) if entry.version < exported.version => {
                    entry.rotate(exported.key.clone());
                    imported += 1;
                }
                None => {
                    keys.insert(
                        federated_name,
                        VerificationKeyEntry::new(&exported.circuit_name, exported.key.clone()),
                    );
                    imported += 1;
                }
                _ => {
                    // Already have same or newer version — skip
                }
            }
        }

        Ok(imported)
    }

    /// List all stored circuit names
    pub fn list_circuits(&self) -> Result<Vec<String>, CircuitError> {
        let keys = self.keys.read().map_err(|_| CircuitError::LockPoisoned)?;
        Ok(keys.keys().cloned().collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_store_and_retrieve() {
        let store = VerificationKeyStore::new("test-instance");
        let key = vec![1, 2, 3, 4];

        store.store_key("my-circuit", key.clone()).unwrap();

        let retrieved = store.get_key("my-circuit").unwrap().unwrap();
        assert_eq!(retrieved, key);
    }

    #[test]
    fn test_key_rotation() {
        let store = VerificationKeyStore::new("test");
        let key1 = vec![1, 2, 3];
        let key2 = vec![4, 5, 6];

        store.store_key("circuit", key1.clone()).unwrap();
        store.store_key("circuit", key2.clone()).unwrap();

        let entry = store.get_entry("circuit").unwrap().unwrap();
        assert_eq!(entry.active_key, key2);
        assert_eq!(entry.previous_key, Some(key1.clone()));
        assert_eq!(entry.version, 2);
        assert!(entry.matches(&key1));
        assert!(entry.matches(&key2));
    }

    #[test]
    fn test_export_import() {
        let store_a = VerificationKeyStore::new("instance-a");
        store_a.store_key("circuit-1", vec![10, 20]).unwrap();
        store_a.store_key("circuit-2", vec![30, 40]).unwrap();

        let bundle = store_a.export_keys().unwrap();
        assert_eq!(bundle.keys.len(), 2);

        let store_b = VerificationKeyStore::new("instance-b");
        let imported = store_b.import_keys(&bundle).unwrap();
        assert_eq!(imported, 2);

        // Keys are stored with federated prefix
        let circuits = store_b.list_circuits().unwrap();
        assert!(circuits.iter().any(|c| c.starts_with("instance-a:")));
    }
}
