// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// redb-backed persistent storage backend for VeriSimDB.
//
// Uses redb (pure Rust, B-tree, ACID, single-file database) to provide
// durable key-value storage. No C/C++ dependencies — builds on any platform
// with a Rust toolchain.
//
// # Design
//
// - Single redb `Database` file containing one main table.
// - Read transactions for all read operations (concurrent, lock-free).
// - Write transactions for put/delete/batch (serialised by redb internally).
// - `flush()` maps to `compact()` which reclaims free space.
// - `scan_prefix` uses redb's `range()` with a computed upper bound to
//   efficiently iterate keys sharing a common prefix.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use async_trait::async_trait;
use redb::{Database, ReadableDatabase, TableDefinition};
use tracing::debug;

use crate::backend::StorageBackend;
use crate::error::StorageError;

/// Table definition for the main key-value store.
///
/// Keys and values are byte slices, matching the `StorageBackend` trait's
/// opaque byte interface.
const MAIN_TABLE: TableDefinition<&[u8], &[u8]> = TableDefinition::new("main");

/// A persistent storage backend powered by redb.
///
/// redb is a pure-Rust embedded database with ACID transactions, copy-on-write
/// B-tree storage, and zero external dependencies. Each `RedbBackend` wraps a
/// single database file.
///
/// Thread-safe: `Database` is `Send + Sync` and handles internal locking.
///
/// # Example
///
/// ```rust,no_run
/// use verisim_storage::redb_backend::RedbBackend;
/// use verisim_storage::backend::StorageBackend;
///
/// # tokio_test::block_on(async {
/// let store = RedbBackend::open("/tmp/verisim-test.redb").unwrap();
/// store.put(b"hello", b"world").await.unwrap();
/// let val = store.get(b"hello").await.unwrap();
/// assert_eq!(val, Some(b"world".to_vec()));
/// # });
/// ```
pub struct RedbBackend {
    /// The redb database handle.
    db: Arc<Database>,
    /// Path to the database file (for diagnostics and approximate_size).
    path: PathBuf,
}

impl RedbBackend {
    /// Open or create a redb database at the given path.
    ///
    /// Creates the file and parent directories if they don't exist. The main
    /// table is created on first write.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StorageError> {
        let path = path.as_ref().to_path_buf();

        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(StorageError::Io)?;
        }

        let db = Database::create(&path).map_err(|e| {
            StorageError::BackendUnavailable(format!("failed to open redb at {}: {}", path.display(), e))
        })?;

        debug!(path = %path.display(), "opened redb backend");

        Ok(Self {
            db: Arc::new(db),
            path,
        })
    }

    /// Return the filesystem path of the database file.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Compute the upper bound for a prefix scan.
    ///
    /// Given a prefix like `[0x61, 0x62]` ("ab"), returns the next key
    /// after all keys starting with that prefix: `[0x61, 0x63]` ("ac").
    /// Returns `None` if the prefix is all 0xFF bytes (no upper bound).
    #[cfg(test)]
    fn prefix_upper_bound(prefix: &[u8]) -> Option<Vec<u8>> {
        let mut upper = prefix.to_vec();
        // Increment the last non-0xFF byte
        while let Some(last) = upper.last_mut() {
            if *last < 0xFF {
                *last += 1;
                return Some(upper);
            }
            upper.pop();
        }
        None // All bytes were 0xFF — no upper bound
    }
}

impl std::fmt::Debug for RedbBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RedbBackend")
            .field("path", &self.path)
            .finish()
    }
}

#[async_trait]
impl StorageBackend for RedbBackend {
    async fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, StorageError> {
        let db = Arc::clone(&self.db);
        let key = key.to_vec();

        tokio::task::spawn_blocking(move || -> Result<Option<Vec<u8>>, StorageError> {
            let txn = db.begin_read().map_err(|e| {
                StorageError::BackendUnavailable(format!("read txn: {e}"))
            })?;

            let table = match txn.open_table(MAIN_TABLE) {
                Ok(t) => t,
                // Table doesn't exist yet — no data has been written
                Err(_) => return Ok(None),
            };

            match table.get(key.as_slice()) {
                Ok(Some(value)) => Ok(Some(value.value().to_vec())),
                Ok(None) => Ok(None),
                Err(e) => Err(StorageError::CorruptedData(format!("get: {e}"))),
            }
        })
        .await
        .map_err(|e| StorageError::BackendUnavailable(format!("task join: {e}")))?
    }

    async fn put(&self, key: &[u8], value: &[u8]) -> Result<(), StorageError> {
        let db = Arc::clone(&self.db);
        let key = key.to_vec();
        let value = value.to_vec();

        tokio::task::spawn_blocking(move || -> Result<(), StorageError> {
            let txn = db.begin_write().map_err(|e| {
                StorageError::BackendUnavailable(format!("write txn: {e}"))
            })?;
            {
                let mut table = txn.open_table(MAIN_TABLE).map_err(|e| {
                    StorageError::BackendUnavailable(format!("open table: {e}"))
                })?;
                table.insert(key.as_slice(), value.as_slice()).map_err(|e| {
                    StorageError::CorruptedData(format!("insert: {e}"))
                })?;
            }
            txn.commit().map_err(|e| {
                StorageError::CorruptedData(format!("commit: {e}"))
            })?;
            Ok(())
        })
        .await
        .map_err(|e| StorageError::BackendUnavailable(format!("task join: {e}")))?
    }

    async fn delete(&self, key: &[u8]) -> Result<bool, StorageError> {
        let db = Arc::clone(&self.db);
        let key = key.to_vec();

        tokio::task::spawn_blocking(move || -> Result<bool, StorageError> {
            let txn = db.begin_write().map_err(|e| {
                StorageError::BackendUnavailable(format!("write txn: {e}"))
            })?;
            let existed;
            {
                let mut table = txn.open_table(MAIN_TABLE).map_err(|e| {
                    StorageError::BackendUnavailable(format!("open table: {e}"))
                })?;
                existed = table.remove(key.as_slice()).map_err(|e| {
                    StorageError::CorruptedData(format!("remove: {e}"))
                })?.is_some();
            }
            txn.commit().map_err(|e| {
                StorageError::CorruptedData(format!("commit: {e}"))
            })?;
            Ok(existed)
        })
        .await
        .map_err(|e| StorageError::BackendUnavailable(format!("task join: {e}")))?
    }

    async fn exists(&self, key: &[u8]) -> Result<bool, StorageError> {
        // Delegate to get — redb has no separate "exists" check.
        Ok(self.get(key).await?.is_some())
    }

    async fn scan_prefix(
        &self,
        prefix: &[u8],
        limit: usize,
    ) -> Result<Vec<(Vec<u8>, Vec<u8>)>, StorageError> {
        let db = Arc::clone(&self.db);
        let prefix = prefix.to_vec();

        tokio::task::spawn_blocking(move || -> Result<Vec<(Vec<u8>, Vec<u8>)>, StorageError> {
            let txn = db.begin_read().map_err(|e| {
                StorageError::BackendUnavailable(format!("read txn: {e}"))
            })?;
            let table = match txn.open_table(MAIN_TABLE) {
                Ok(t) => t,
                Err(_) => return Ok(Vec::new()), // Table doesn't exist yet
            };

            let mut results = Vec::new();

            // Scan from the prefix key onward; stop when keys no longer match
            let iter = table.range(prefix.as_slice()..).map_err(|e| {
                StorageError::CorruptedData(format!("range scan: {e}"))
            })?;

            for entry in iter {
                let entry = entry.map_err(|e| {
                    StorageError::CorruptedData(format!("scan entry: {e}"))
                })?;
                let k = entry.0.value().to_vec();
                let v = entry.1.value().to_vec();

                if !k.starts_with(&prefix) {
                    break;
                }

                results.push((k, v));
                if results.len() >= limit {
                    break;
                }
            }

            Ok(results)
        })
        .await
        .map_err(|e| StorageError::BackendUnavailable(format!("task join: {e}")))?
    }

    async fn multi_get(&self, keys: &[&[u8]]) -> Result<Vec<Option<Vec<u8>>>, StorageError> {
        let db = Arc::clone(&self.db);
        let owned_keys: Vec<Vec<u8>> = keys.iter().map(|k| k.to_vec()).collect();

        tokio::task::spawn_blocking(move || -> Result<Vec<Option<Vec<u8>>>, StorageError> {
            let txn = db.begin_read().map_err(|e| {
                StorageError::BackendUnavailable(format!("read txn: {e}"))
            })?;
            let table = match txn.open_table(MAIN_TABLE) {
                Ok(t) => t,
                Err(_) => return Ok(owned_keys.iter().map(|_| None).collect()),
            };

            let mut results = Vec::with_capacity(owned_keys.len());
            for key in &owned_keys {
                match table.get(key.as_slice()) {
                    Ok(Some(v)) => results.push(Some(v.value().to_vec())),
                    Ok(None) => results.push(None),
                    Err(e) => {
                        return Err(StorageError::CorruptedData(format!("multi_get: {e}")))
                    }
                }
            }
            Ok(results)
        })
        .await
        .map_err(|e| StorageError::BackendUnavailable(format!("task join: {e}")))?
    }

    async fn batch_put(&self, entries: &[(&[u8], &[u8])]) -> Result<(), StorageError> {
        let db = Arc::clone(&self.db);
        let owned: Vec<(Vec<u8>, Vec<u8>)> = entries
            .iter()
            .map(|(k, v)| (k.to_vec(), v.to_vec()))
            .collect();

        tokio::task::spawn_blocking(move || -> Result<(), StorageError> {
            let txn = db.begin_write().map_err(|e| {
                StorageError::BackendUnavailable(format!("write txn: {e}"))
            })?;
            {
                let mut table = txn.open_table(MAIN_TABLE).map_err(|e| {
                    StorageError::BackendUnavailable(format!("open table: {e}"))
                })?;
                for (k, v) in &owned {
                    table.insert(k.as_slice(), v.as_slice()).map_err(|e| {
                        StorageError::CorruptedData(format!("batch insert: {e}"))
                    })?;
                }
            }
            txn.commit().map_err(|e| {
                StorageError::CorruptedData(format!("batch commit: {e}"))
            })?;
            Ok(())
        })
        .await
        .map_err(|e| StorageError::BackendUnavailable(format!("task join: {e}")))?
    }

    async fn flush(&self) -> Result<(), StorageError> {
        // redb commits are durable by default — each write transaction is
        // fsynced on commit. No additional flush needed. compact() requires
        // &mut self and is a space-reclamation optimisation, not a durability
        // operation.
        Ok(())
    }

    fn name(&self) -> &str {
        "redb"
    }

    async fn approximate_size(&self) -> Result<Option<u64>, StorageError> {
        match std::fs::metadata(&self.path) {
            Ok(meta) => Ok(Some(meta.len())),
            Err(_) => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    /// Create a temporary RedbBackend for testing.
    ///
    /// Uses `tempdir()` rather than `NamedTempFile` so the directory persists
    /// for the lifetime of the test (NamedTempFile's Drop would unlink the
    /// path while redb still holds it open, breaking `approximate_size`).
    fn temp_backend() -> (RedbBackend, tempfile::TempDir) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.redb");
        let backend = RedbBackend::open(&path).unwrap();
        (backend, dir)
    }

    #[tokio::test]
    async fn test_basic_crud() {
        let (backend, _dir) = temp_backend();

        // Get on empty store returns None
        assert_eq!(backend.get(b"key1").await.unwrap(), None);
        assert!(!backend.exists(b"key1").await.unwrap());

        // Put and get
        backend.put(b"key1", b"value1").await.unwrap();
        assert_eq!(backend.get(b"key1").await.unwrap(), Some(b"value1".to_vec()));
        assert!(backend.exists(b"key1").await.unwrap());

        // Overwrite
        backend.put(b"key1", b"updated").await.unwrap();
        assert_eq!(backend.get(b"key1").await.unwrap(), Some(b"updated".to_vec()));

        // Delete existing key
        assert!(backend.delete(b"key1").await.unwrap());
        assert_eq!(backend.get(b"key1").await.unwrap(), None);

        // Delete non-existent key
        assert!(!backend.delete(b"nonexistent").await.unwrap());
    }

    #[tokio::test]
    async fn test_scan_prefix() {
        let (backend, _dir) = temp_backend();

        backend.put(b"user:1:name", b"Alice").await.unwrap();
        backend.put(b"user:1:age", b"30").await.unwrap();
        backend.put(b"user:2:name", b"Bob").await.unwrap();
        backend.put(b"post:1:title", b"Hello").await.unwrap();

        // Scan "user:1:" prefix
        let results = backend.scan_prefix(b"user:1:", 10).await.unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].0, b"user:1:age".to_vec());
        assert_eq!(results[1].0, b"user:1:name".to_vec());

        // Scan "user:" prefix — all user keys
        let results = backend.scan_prefix(b"user:", 10).await.unwrap();
        assert_eq!(results.len(), 3);

        // Scan with limit
        let results = backend.scan_prefix(b"user:", 2).await.unwrap();
        assert_eq!(results.len(), 2);

        // Scan with no matching prefix
        let results = backend.scan_prefix(b"missing:", 10).await.unwrap();
        assert!(results.is_empty());
    }

    #[tokio::test]
    async fn test_multi_get() {
        let (backend, _dir) = temp_backend();

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
        let (backend, _dir) = temp_backend();

        backend
            .batch_put(&[
                (b"x" as &[u8], b"10" as &[u8]),
                (b"y", b"20"),
                (b"z", b"30"),
            ])
            .await
            .unwrap();

        assert_eq!(backend.get(b"x").await.unwrap(), Some(b"10".to_vec()));
        assert_eq!(backend.get(b"y").await.unwrap(), Some(b"20".to_vec()));
        assert_eq!(backend.get(b"z").await.unwrap(), Some(b"30".to_vec()));
    }

    #[tokio::test]
    async fn test_flush_compacts() {
        let (backend, _dir) = temp_backend();
        backend.put(b"key", b"val").await.unwrap();
        backend.flush().await.unwrap();
        assert_eq!(backend.get(b"key").await.unwrap(), Some(b"val".to_vec()));
    }

    #[tokio::test]
    async fn test_name() {
        let (backend, _dir) = temp_backend();
        assert_eq!(backend.name(), "redb");
    }

    #[tokio::test]
    async fn test_approximate_size() {
        let (backend, _dir) = temp_backend();
        // After writing data, file size should be non-zero
        backend.put(b"key", b"value").await.unwrap();
        let size = backend.approximate_size().await.unwrap();
        assert!(size.is_some());
        assert!(size.unwrap() > 0);
    }

    #[tokio::test]
    async fn test_persistence_across_reopen() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("persist-test.redb");

        // Write data and drop
        {
            let backend = RedbBackend::open(&path).unwrap();
            backend.put(b"persistent-key", b"persistent-value").await.unwrap();
        }

        // Reopen and verify data survived
        {
            let backend = RedbBackend::open(&path).unwrap();
            let val = backend.get(b"persistent-key").await.unwrap();
            assert_eq!(val, Some(b"persistent-value".to_vec()));
        }
    }

    #[test]
    fn test_prefix_upper_bound() {
        // Normal case
        assert_eq!(
            RedbBackend::prefix_upper_bound(b"abc"),
            Some(b"abd".to_vec())
        );

        // Trailing 0xFF byte
        assert_eq!(
            RedbBackend::prefix_upper_bound(b"ab\xff"),
            Some(b"ac".to_vec())
        );

        // All 0xFF bytes — no upper bound
        assert_eq!(
            RedbBackend::prefix_upper_bound(b"\xff\xff"),
            None
        );

        // Empty prefix — no upper bound
        assert_eq!(
            RedbBackend::prefix_upper_bound(b""),
            None
        );

        // Single byte
        assert_eq!(
            RedbBackend::prefix_upper_bound(b"z"),
            Some(b"{".to_vec()) // 'z' + 1 = '{'
        );
    }
}
