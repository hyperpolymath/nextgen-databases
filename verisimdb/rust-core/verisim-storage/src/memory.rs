// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// In-memory storage backend for VeriSimDB.
//
// Uses a `BTreeMap` wrapped in a tokio `RwLock` for thread-safe, ordered
// key-value storage. The BTreeMap ordering enables efficient prefix scanning.
// Intended for testing, development, and small ephemeral datasets.

use std::collections::BTreeMap;
use std::sync::Arc;

use async_trait::async_trait;
use tokio::sync::RwLock;

use crate::backend::StorageBackend;
use crate::error::StorageError;

/// An in-memory storage backend backed by a sorted `BTreeMap`.
///
/// All data lives in process memory and is lost on drop. Thread-safe via
/// `Arc<RwLock<...>>`, making it suitable for concurrent tokio tasks.
///
/// # Example
///
/// ```rust
/// use verisim_storage::memory::InMemoryBackend;
/// use verisim_storage::backend::StorageBackend;
///
/// # tokio_test::block_on(async {
/// let store = InMemoryBackend::new();
/// store.put(b"hello", b"world").await.unwrap();
/// let val = store.get(b"hello").await.unwrap();
/// assert_eq!(val, Some(b"world".to_vec()));
/// # });
/// ```
#[derive(Debug, Clone)]
pub struct InMemoryBackend {
    /// The underlying sorted map, protected by a read-write lock.
    data: Arc<RwLock<BTreeMap<Vec<u8>, Vec<u8>>>>,
}

impl InMemoryBackend {
    /// Create a new, empty in-memory backend.
    pub fn new() -> Self {
        Self {
            data: Arc::new(RwLock::new(BTreeMap::new())),
        }
    }

    /// Return the number of keys currently stored.
    pub async fn len(&self) -> usize {
        self.data.read().await.len()
    }

    /// Return true if the store contains no keys.
    pub async fn is_empty(&self) -> bool {
        self.data.read().await.is_empty()
    }
}

impl Default for InMemoryBackend {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl StorageBackend for InMemoryBackend {
    async fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, StorageError> {
        let map = self.data.read().await;
        Ok(map.get(key).cloned())
    }

    async fn put(&self, key: &[u8], value: &[u8]) -> Result<(), StorageError> {
        let mut map = self.data.write().await;
        map.insert(key.to_vec(), value.to_vec());
        Ok(())
    }

    async fn delete(&self, key: &[u8]) -> Result<bool, StorageError> {
        let mut map = self.data.write().await;
        Ok(map.remove(key).is_some())
    }

    async fn exists(&self, key: &[u8]) -> Result<bool, StorageError> {
        let map = self.data.read().await;
        Ok(map.contains_key(key))
    }

    async fn scan_prefix(
        &self,
        prefix: &[u8],
        limit: usize,
    ) -> Result<Vec<(Vec<u8>, Vec<u8>)>, StorageError> {
        let map = self.data.read().await;
        let results = map
            .range(prefix.to_vec()..)
            .take_while(|(k, _)| k.starts_with(prefix))
            .take(limit)
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        Ok(results)
    }

    async fn multi_get(&self, keys: &[&[u8]]) -> Result<Vec<Option<Vec<u8>>>, StorageError> {
        let map = self.data.read().await;
        let results = keys
            .iter()
            .map(|key| map.get(*key).cloned())
            .collect();
        Ok(results)
    }

    async fn batch_put(&self, entries: &[(&[u8], &[u8])]) -> Result<(), StorageError> {
        let mut map = self.data.write().await;
        for (key, value) in entries {
            map.insert(key.to_vec(), value.to_vec());
        }
        Ok(())
    }

    async fn flush(&self) -> Result<(), StorageError> {
        // No-op for in-memory backend: all writes are immediately visible.
        Ok(())
    }

    fn name(&self) -> &str {
        "in-memory"
    }

    async fn approximate_size(&self) -> Result<Option<u64>, StorageError> {
        let map = self.data.read().await;
        let size: u64 = map
            .iter()
            .map(|(k, v)| (k.len() + v.len()) as u64)
            .sum();
        Ok(Some(size))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_basic_crud() {
        let backend = InMemoryBackend::new();

        // Initially empty.
        assert!(backend.is_empty().await);
        assert_eq!(backend.get(b"key1").await.unwrap(), None);
        assert!(!backend.exists(b"key1").await.unwrap());

        // Put and get.
        backend.put(b"key1", b"value1").await.unwrap();
        assert_eq!(backend.get(b"key1").await.unwrap(), Some(b"value1".to_vec()));
        assert!(backend.exists(b"key1").await.unwrap());
        assert_eq!(backend.len().await, 1);

        // Overwrite.
        backend.put(b"key1", b"updated").await.unwrap();
        assert_eq!(backend.get(b"key1").await.unwrap(), Some(b"updated".to_vec()));
        assert_eq!(backend.len().await, 1);

        // Delete existing key.
        assert!(backend.delete(b"key1").await.unwrap());
        assert_eq!(backend.get(b"key1").await.unwrap(), None);
        assert!(backend.is_empty().await);

        // Delete non-existent key.
        assert!(!backend.delete(b"nonexistent").await.unwrap());
    }

    #[tokio::test]
    async fn test_scan_prefix() {
        let backend = InMemoryBackend::new();

        // Insert keys with different prefixes.
        backend.put(b"user:1:name", b"Alice").await.unwrap();
        backend.put(b"user:1:age", b"30").await.unwrap();
        backend.put(b"user:2:name", b"Bob").await.unwrap();
        backend.put(b"post:1:title", b"Hello").await.unwrap();

        // Scan with prefix "user:1:".
        let results = backend.scan_prefix(b"user:1:", 10).await.unwrap();
        assert_eq!(results.len(), 2);
        // BTreeMap ordering: "user:1:age" < "user:1:name".
        assert_eq!(results[0].0, b"user:1:age".to_vec());
        assert_eq!(results[1].0, b"user:1:name".to_vec());

        // Scan with prefix "user:" — should return all user keys.
        let results = backend.scan_prefix(b"user:", 10).await.unwrap();
        assert_eq!(results.len(), 3);

        // Scan with limit.
        let results = backend.scan_prefix(b"user:", 2).await.unwrap();
        assert_eq!(results.len(), 2);

        // Scan with no matching prefix.
        let results = backend.scan_prefix(b"missing:", 10).await.unwrap();
        assert!(results.is_empty());
    }

    #[tokio::test]
    async fn test_multi_get() {
        let backend = InMemoryBackend::new();

        backend.put(b"a", b"1").await.unwrap();
        backend.put(b"b", b"2").await.unwrap();
        backend.put(b"c", b"3").await.unwrap();

        let results = backend
            .multi_get(&[b"a" as &[u8], b"missing", b"c"])
            .await
            .unwrap();

        assert_eq!(results.len(), 3);
        assert_eq!(results[0], Some(b"1".to_vec()));
        assert_eq!(results[1], None);
        assert_eq!(results[2], Some(b"3".to_vec()));
    }

    #[tokio::test]
    async fn test_batch_put() {
        let backend = InMemoryBackend::new();

        backend
            .batch_put(&[
                (b"x" as &[u8], b"10" as &[u8]),
                (b"y", b"20"),
                (b"z", b"30"),
            ])
            .await
            .unwrap();

        assert_eq!(backend.len().await, 3);
        assert_eq!(backend.get(b"x").await.unwrap(), Some(b"10".to_vec()));
        assert_eq!(backend.get(b"y").await.unwrap(), Some(b"20".to_vec()));
        assert_eq!(backend.get(b"z").await.unwrap(), Some(b"30".to_vec()));
    }

    #[tokio::test]
    async fn test_flush_is_noop() {
        let backend = InMemoryBackend::new();
        backend.put(b"key", b"val").await.unwrap();
        // Flush should succeed without error.
        backend.flush().await.unwrap();
        // Data should still be there.
        assert_eq!(backend.get(b"key").await.unwrap(), Some(b"val".to_vec()));
    }

    #[tokio::test]
    async fn test_name() {
        let backend = InMemoryBackend::new();
        assert_eq!(backend.name(), "in-memory");
    }

    #[tokio::test]
    async fn test_approximate_size() {
        let backend = InMemoryBackend::new();

        // Empty store has zero size.
        assert_eq!(backend.approximate_size().await.unwrap(), Some(0));

        // Size accounts for both keys and values.
        backend.put(b"abc", b"defgh").await.unwrap(); // 3 + 5 = 8
        assert_eq!(backend.approximate_size().await.unwrap(), Some(8));

        backend.put(b"xy", b"z").await.unwrap(); // 2 + 1 = 3, total = 11
        assert_eq!(backend.approximate_size().await.unwrap(), Some(11));
    }

    #[tokio::test]
    async fn test_clone_shares_state() {
        let backend = InMemoryBackend::new();
        let clone = backend.clone();

        backend.put(b"shared", b"data").await.unwrap();
        assert_eq!(clone.get(b"shared").await.unwrap(), Some(b"data".to_vec()));
    }
}
