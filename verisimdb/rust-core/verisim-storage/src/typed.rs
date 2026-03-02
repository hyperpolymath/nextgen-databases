// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Typed storage wrapper for VeriSimDB.
//
// Provides a higher-level, serde-based interface on top of any `StorageBackend`.
// Values are serialized as JSON and all keys are automatically prefixed with a
// configurable namespace, enabling multiple logical stores to share a single
// physical backend without key collisions.

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::backend::StorageBackend;
use crate::error::StorageError;

/// A typed wrapper around a [`StorageBackend`] that handles serialization
/// and namespace prefixing automatically.
///
/// Keys are prefixed with `"{namespace}:"` before being passed to the
/// underlying backend. Values are serialized to JSON on write and
/// deserialized on read.
///
/// # Example
///
/// ```rust
/// use verisim_storage::memory::InMemoryBackend;
/// use verisim_storage::typed::TypedStore;
/// use serde::{Serialize, Deserialize};
///
/// #[derive(Debug, Serialize, Deserialize, PartialEq)]
/// struct User { name: String, age: u32 }
///
/// # tokio_test::block_on(async {
/// let backend = InMemoryBackend::new();
/// let store = TypedStore::new(backend, "users");
///
/// let alice = User { name: "Alice".into(), age: 30 };
/// store.put("alice", &alice).await.unwrap();
///
/// let retrieved: User = store.get("alice").await.unwrap().unwrap();
/// assert_eq!(retrieved, alice);
/// # });
/// ```
pub struct TypedStore<B: StorageBackend> {
    /// The underlying raw key-value backend.
    backend: B,
    /// Namespace prefix applied to all keys.
    namespace: String,
}

impl<B: StorageBackend> TypedStore<B> {
    /// Create a new typed store wrapping `backend` with the given namespace.
    ///
    /// All keys will be prefixed with `"{namespace}:"`.
    pub fn new(backend: B, namespace: &str) -> Self {
        Self {
            backend,
            namespace: namespace.to_string(),
        }
    }

    /// Return a reference to the underlying backend.
    pub fn backend(&self) -> &B {
        &self.backend
    }

    /// Return the namespace prefix used by this store.
    pub fn namespace(&self) -> &str {
        &self.namespace
    }

    /// Build the full namespaced key from a logical key string.
    fn prefixed_key(&self, key: &str) -> Vec<u8> {
        format!("{}:{}", self.namespace, key).into_bytes()
    }

    /// Build the namespace prefix (for scanning).
    fn prefix_bytes(&self) -> Vec<u8> {
        format!("{}:", self.namespace).into_bytes()
    }

    /// Retrieve and deserialize a value by its logical key.
    ///
    /// Returns `Ok(None)` if the key does not exist.
    pub async fn get<T: DeserializeOwned>(&self, key: &str) -> Result<Option<T>, StorageError> {
        let full_key = self.prefixed_key(key);
        match self.backend.get(&full_key).await? {
            Some(bytes) => {
                let value: T = serde_json::from_slice(&bytes).map_err(|err| {
                    StorageError::SerializationError(format!(
                        "failed to deserialize value for key '{}': {}",
                        key, err
                    ))
                })?;
                Ok(Some(value))
            }
            None => Ok(None),
        }
    }

    /// Serialize and store a value under the given logical key.
    pub async fn put<T: Serialize>(&self, key: &str, value: &T) -> Result<(), StorageError> {
        let full_key = self.prefixed_key(key);
        let bytes = serde_json::to_vec(value).map_err(|err| {
            StorageError::SerializationError(format!(
                "failed to serialize value for key '{}': {}",
                key, err
            ))
        })?;
        self.backend.put(&full_key, &bytes).await
    }

    /// Delete a value by its logical key.
    ///
    /// Returns `Ok(true)` if the key existed and was removed.
    pub async fn delete(&self, key: &str) -> Result<bool, StorageError> {
        let full_key = self.prefixed_key(key);
        self.backend.delete(&full_key).await
    }

    /// Scan all entries in this namespace whose keys (after the namespace
    /// prefix) start with the given `key_prefix`, returning up to `limit`
    /// deserialized (key-suffix, value) pairs.
    pub async fn scan_prefix<T: DeserializeOwned>(
        &self,
        key_prefix: &str,
        limit: usize,
    ) -> Result<Vec<(String, T)>, StorageError> {
        let full_prefix = format!("{}:{}", self.namespace, key_prefix).into_bytes();
        let ns_prefix = self.prefix_bytes();
        let ns_prefix_len = ns_prefix.len();

        let raw_results = self.backend.scan_prefix(&full_prefix, limit).await?;

        let mut results = Vec::with_capacity(raw_results.len());
        for (raw_key, raw_value) in raw_results {
            // Strip the namespace prefix to recover the logical key.
            let logical_key = if raw_key.len() >= ns_prefix_len {
                String::from_utf8_lossy(&raw_key[ns_prefix_len..]).to_string()
            } else {
                String::from_utf8_lossy(&raw_key).to_string()
            };

            let value: T = serde_json::from_slice(&raw_value).map_err(|err| {
                StorageError::SerializationError(format!(
                    "failed to deserialize scanned value for key '{}': {}",
                    logical_key, err
                ))
            })?;

            results.push((logical_key, value));
        }

        Ok(results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::InMemoryBackend;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
    struct TestRecord {
        name: String,
        score: f64,
    }

    #[tokio::test]
    async fn test_typed_round_trip() {
        let backend = InMemoryBackend::new();
        let store = TypedStore::new(backend, "test");

        let record = TestRecord {
            name: "Alice".to_string(),
            score: 95.5,
        };

        // Put and get.
        store.put("rec1", &record).await.unwrap();
        let retrieved: TestRecord = store.get("rec1").await.unwrap().unwrap();
        assert_eq!(retrieved, record);

        // Missing key.
        let missing: Option<TestRecord> = store.get("nonexistent").await.unwrap();
        assert!(missing.is_none());

        // Delete.
        assert!(store.delete("rec1").await.unwrap());
        assert!(store.get::<TestRecord>("rec1").await.unwrap().is_none());

        // Delete non-existent.
        assert!(!store.delete("rec1").await.unwrap());
    }

    #[tokio::test]
    async fn test_namespace_isolation() {
        let backend = InMemoryBackend::new();
        let store_a = TypedStore::new(backend.clone(), "ns_a");
        let store_b = TypedStore::new(backend.clone(), "ns_b");

        store_a.put("key", &"value_a".to_string()).await.unwrap();
        store_b.put("key", &"value_b".to_string()).await.unwrap();

        // Each namespace sees its own value.
        let val_a: String = store_a.get("key").await.unwrap().unwrap();
        let val_b: String = store_b.get("key").await.unwrap().unwrap();
        assert_eq!(val_a, "value_a");
        assert_eq!(val_b, "value_b");

        // Deleting from one namespace does not affect the other.
        store_a.delete("key").await.unwrap();
        assert!(store_a.get::<String>("key").await.unwrap().is_none());
        assert_eq!(
            store_b.get::<String>("key").await.unwrap().unwrap(),
            "value_b"
        );
    }

    #[tokio::test]
    async fn test_typed_scan_prefix() {
        let backend = InMemoryBackend::new();
        let store = TypedStore::new(backend, "items");

        store.put("fruit:apple", &10u32).await.unwrap();
        store.put("fruit:banana", &20u32).await.unwrap();
        store.put("vegetable:carrot", &30u32).await.unwrap();

        let fruits: Vec<(String, u32)> = store.scan_prefix("fruit:", 10).await.unwrap();
        assert_eq!(fruits.len(), 2);
        assert_eq!(fruits[0].0, "fruit:apple");
        assert_eq!(fruits[0].1, 10);
        assert_eq!(fruits[1].0, "fruit:banana");
        assert_eq!(fruits[1].1, 20);

        // Scan with limit.
        let limited: Vec<(String, u32)> = store.scan_prefix("fruit:", 1).await.unwrap();
        assert_eq!(limited.len(), 1);
    }

    #[tokio::test]
    async fn test_typed_primitive_types() {
        let backend = InMemoryBackend::new();
        let store = TypedStore::new(backend, "prims");

        // Integer.
        store.put("int", &42i64).await.unwrap();
        assert_eq!(store.get::<i64>("int").await.unwrap().unwrap(), 42);

        // Boolean.
        store.put("flag", &true).await.unwrap();
        assert_eq!(store.get::<bool>("flag").await.unwrap().unwrap(), true);

        // Vec.
        store.put("list", &vec![1, 2, 3]).await.unwrap();
        assert_eq!(
            store.get::<Vec<i32>>("list").await.unwrap().unwrap(),
            vec![1, 2, 3]
        );
    }

    #[tokio::test]
    async fn test_deserialization_error() {
        let backend = InMemoryBackend::new();
        let store = TypedStore::new(backend.clone(), "bad");

        // Write raw invalid JSON bytes directly via the backend.
        let key = b"bad:broken";
        backend.put(key, b"not-valid-json!!!").await.unwrap();

        // Attempt to deserialize as a struct should fail.
        let result = store.get::<TestRecord>("broken").await;
        assert!(result.is_err());
        match result.unwrap_err() {
            StorageError::SerializationError(msg) => {
                assert!(msg.contains("failed to deserialize"));
            }
            other => panic!("expected SerializationError, got: {:?}", other),
        }
    }

    #[tokio::test]
    async fn test_namespace_and_backend_accessors() {
        let backend = InMemoryBackend::new();
        let store = TypedStore::new(backend, "myns");
        assert_eq!(store.namespace(), "myns");
        assert_eq!(store.backend().name(), "in-memory");
    }
}
