// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Core storage backend trait for VeriSimDB.
//
// Defines the `StorageBackend` trait that all storage implementations must
// satisfy. The trait provides a key-value interface with support for batch
// operations, prefix scanning, and flush semantics. Backends are expected
// to be thread-safe (`Send + Sync`) and fully asynchronous.

use async_trait::async_trait;

use crate::error::StorageError;

/// A pluggable key-value storage backend.
///
/// All keys and values are opaque byte slices. Higher-level typed access
/// is provided by [`crate::typed::TypedStore`], which wraps a backend with
/// serde-based serialization and namespace prefixing.
///
/// Implementations must be safe to share across threads and tokio tasks.
#[async_trait]
pub trait StorageBackend: Send + Sync {
    /// Retrieve the value associated with `key`.
    ///
    /// Returns `Ok(None)` if the key does not exist, rather than an error.
    async fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, StorageError>;

    /// Store a key-value pair, overwriting any previous value for `key`.
    async fn put(&self, key: &[u8], value: &[u8]) -> Result<(), StorageError>;

    /// Delete the value associated with `key`.
    ///
    /// Returns `Ok(true)` if the key existed and was removed, `Ok(false)` if
    /// the key was not present.
    async fn delete(&self, key: &[u8]) -> Result<bool, StorageError>;

    /// Check whether `key` exists in the store without retrieving its value.
    async fn exists(&self, key: &[u8]) -> Result<bool, StorageError>;

    /// Scan all keys that start with `prefix`, returning up to `limit`
    /// (key, value) pairs in lexicographic order.
    async fn scan_prefix(
        &self,
        prefix: &[u8],
        limit: usize,
    ) -> Result<Vec<(Vec<u8>, Vec<u8>)>, StorageError>;

    /// Retrieve multiple keys in a single call.
    ///
    /// The returned vector has the same length as `keys`, with `None` for any
    /// key that was not found.
    async fn multi_get(&self, keys: &[&[u8]]) -> Result<Vec<Option<Vec<u8>>>, StorageError>;

    /// Write multiple key-value pairs atomically.
    ///
    /// Either all entries are written or none are. Implementations that cannot
    /// guarantee atomicity should document this limitation.
    async fn batch_put(&self, entries: &[(&[u8], &[u8])]) -> Result<(), StorageError>;

    /// Flush any buffered writes to durable storage.
    ///
    /// For in-memory backends this is a no-op. For disk-backed backends this
    /// should ensure that all previously written data survives a process crash.
    async fn flush(&self) -> Result<(), StorageError>;

    /// A human-readable name for this backend, used in logging and metrics.
    fn name(&self) -> &str;

    /// Return the approximate total size of stored data in bytes, if known.
    ///
    /// Backends that cannot cheaply compute this may return `Ok(None)`.
    async fn approximate_size(&self) -> Result<Option<u64>, StorageError>;
}
