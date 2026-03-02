// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Metrics-collecting wrapper for VeriSimDB storage backends.
//
// Wraps any `StorageBackend` and transparently collects operation counts,
// latency sums, and byte transfer totals. Useful for profiling, dashboards,
// and adaptive query planning within the VeriSimDB normalizer and drift
// detection systems.

use std::sync::Arc;
use std::time::Instant;

use async_trait::async_trait;
use tokio::sync::RwLock;

use crate::backend::StorageBackend;
use crate::error::StorageError;

/// Accumulated statistics for a storage backend.
///
/// All counters are monotonically increasing for the lifetime of the
/// [`MetricsBackend`] that owns them.
#[derive(Debug, Clone, Default)]
pub struct BackendStats {
    /// Number of `get` operations performed.
    pub get_count: u64,
    /// Number of `put` operations performed.
    pub put_count: u64,
    /// Number of `delete` operations performed.
    pub delete_count: u64,
    /// Number of `scan_prefix` operations performed.
    pub scan_count: u64,
    /// Cumulative wall-clock latency of all `get` calls, in milliseconds.
    pub get_latency_sum_ms: f64,
    /// Cumulative wall-clock latency of all `put` calls, in milliseconds.
    pub put_latency_sum_ms: f64,
    /// Total bytes read across all `get` and `multi_get` operations.
    pub total_bytes_read: u64,
    /// Total bytes written across all `put` and `batch_put` operations.
    pub total_bytes_written: u64,
}

/// A storage backend wrapper that collects operation metrics.
///
/// Delegates every operation to an inner backend while measuring wall-clock
/// latency and counting invocations. Statistics are available via
/// [`MetricsBackend::stats`].
///
/// # Example
///
/// ```rust
/// use verisim_storage::memory::InMemoryBackend;
/// use verisim_storage::metrics::MetricsBackend;
/// use verisim_storage::backend::StorageBackend;
///
/// # tokio_test::block_on(async {
/// let inner = InMemoryBackend::new();
/// let metered = MetricsBackend::new(inner);
///
/// metered.put(b"key", b"value").await.unwrap();
/// metered.get(b"key").await.unwrap();
///
/// let stats = metered.stats().await;
/// assert_eq!(stats.put_count, 1);
/// assert_eq!(stats.get_count, 1);
/// # });
/// ```
pub struct MetricsBackend<B: StorageBackend> {
    /// The wrapped backend that performs the actual storage operations.
    inner: B,
    /// Shared, mutable statistics accumulator.
    stats: Arc<RwLock<BackendStats>>,
}

impl<B: StorageBackend> MetricsBackend<B> {
    /// Wrap `inner` with metrics collection.
    pub fn new(inner: B) -> Self {
        Self {
            inner,
            stats: Arc::new(RwLock::new(BackendStats::default())),
        }
    }

    /// Return a snapshot of the current statistics.
    pub async fn stats(&self) -> BackendStats {
        self.stats.read().await.clone()
    }

    /// Reset all statistics to zero.
    pub async fn reset_stats(&self) {
        let mut s = self.stats.write().await;
        *s = BackendStats::default();
    }

    /// Return a reference to the inner backend.
    pub fn inner(&self) -> &B {
        &self.inner
    }
}

#[async_trait]
impl<B: StorageBackend> StorageBackend for MetricsBackend<B> {
    async fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, StorageError> {
        let start = Instant::now();
        let result = self.inner.get(key).await;
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;

        let mut s = self.stats.write().await;
        s.get_count += 1;
        s.get_latency_sum_ms += elapsed_ms;
        if let Ok(Some(ref val)) = result {
            s.total_bytes_read += val.len() as u64;
        }

        result
    }

    async fn put(&self, key: &[u8], value: &[u8]) -> Result<(), StorageError> {
        let start = Instant::now();
        let result = self.inner.put(key, value).await;
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;

        let mut s = self.stats.write().await;
        s.put_count += 1;
        s.put_latency_sum_ms += elapsed_ms;
        if result.is_ok() {
            s.total_bytes_written += value.len() as u64;
        }

        result
    }

    async fn delete(&self, key: &[u8]) -> Result<bool, StorageError> {
        let mut s = self.stats.write().await;
        s.delete_count += 1;
        drop(s); // Release lock before the potentially slow operation.
        self.inner.delete(key).await
    }

    async fn exists(&self, key: &[u8]) -> Result<bool, StorageError> {
        self.inner.exists(key).await
    }

    async fn scan_prefix(
        &self,
        prefix: &[u8],
        limit: usize,
    ) -> Result<Vec<(Vec<u8>, Vec<u8>)>, StorageError> {
        let result = self.inner.scan_prefix(prefix, limit).await;

        let mut s = self.stats.write().await;
        s.scan_count += 1;
        if let Ok(ref entries) = result {
            let bytes: u64 = entries
                .iter()
                .map(|(k, v)| (k.len() + v.len()) as u64)
                .sum();
            s.total_bytes_read += bytes;
        }

        result
    }

    async fn multi_get(&self, keys: &[&[u8]]) -> Result<Vec<Option<Vec<u8>>>, StorageError> {
        let start = Instant::now();
        let result = self.inner.multi_get(keys).await;
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;

        let mut s = self.stats.write().await;
        s.get_count += keys.len() as u64;
        s.get_latency_sum_ms += elapsed_ms;
        if let Ok(ref vals) = result {
            let bytes: u64 = vals
                .iter()
                .filter_map(|v| v.as_ref())
                .map(|v| v.len() as u64)
                .sum();
            s.total_bytes_read += bytes;
        }

        result
    }

    async fn batch_put(&self, entries: &[(&[u8], &[u8])]) -> Result<(), StorageError> {
        let start = Instant::now();
        let result = self.inner.batch_put(entries).await;
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;

        let mut s = self.stats.write().await;
        s.put_count += entries.len() as u64;
        s.put_latency_sum_ms += elapsed_ms;
        if result.is_ok() {
            let bytes: u64 = entries.iter().map(|(_, v)| v.len() as u64).sum();
            s.total_bytes_written += bytes;
        }

        result
    }

    async fn flush(&self) -> Result<(), StorageError> {
        self.inner.flush().await
    }

    fn name(&self) -> &str {
        self.inner.name()
    }

    async fn approximate_size(&self) -> Result<Option<u64>, StorageError> {
        self.inner.approximate_size().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::InMemoryBackend;

    #[tokio::test]
    async fn test_get_increments_count() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered.put(b"k", b"v").await.unwrap();
        metered.get(b"k").await.unwrap();
        metered.get(b"k").await.unwrap();
        metered.get(b"missing").await.unwrap();

        let stats = metered.stats().await;
        assert_eq!(stats.get_count, 3);
        assert_eq!(stats.put_count, 1);
    }

    #[tokio::test]
    async fn test_put_increments_count_and_bytes() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered.put(b"a", b"hello").await.unwrap(); // 5 bytes
        metered.put(b"b", b"world!").await.unwrap(); // 6 bytes

        let stats = metered.stats().await;
        assert_eq!(stats.put_count, 2);
        assert_eq!(stats.total_bytes_written, 11);
    }

    #[tokio::test]
    async fn test_delete_increments_count() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered.put(b"k", b"v").await.unwrap();
        metered.delete(b"k").await.unwrap();
        metered.delete(b"nope").await.unwrap();

        let stats = metered.stats().await;
        assert_eq!(stats.delete_count, 2);
    }

    #[tokio::test]
    async fn test_scan_increments_count_and_bytes() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered.put(b"pfx:a", b"11").await.unwrap(); // key=5 + val=2 = 7
        metered.put(b"pfx:b", b"22").await.unwrap(); // key=5 + val=2 = 7
        metered.put(b"other", b"xx").await.unwrap();

        let results = metered.scan_prefix(b"pfx:", 10).await.unwrap();
        assert_eq!(results.len(), 2);

        let stats = metered.stats().await;
        assert_eq!(stats.scan_count, 1);
        // Bytes read from scan: 2 * (5 + 2) = 14.
        assert_eq!(stats.total_bytes_read, 14);
    }

    #[tokio::test]
    async fn test_multi_get_increments_count() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered.put(b"a", b"1").await.unwrap();
        metered.put(b"b", b"22").await.unwrap();

        metered
            .multi_get(&[b"a" as &[u8], b"b", b"missing"])
            .await
            .unwrap();

        let stats = metered.stats().await;
        // multi_get adds keys.len() to get_count.
        assert_eq!(stats.get_count, 3);
        // Bytes read: 1 + 2 = 3 (missing key contributes 0).
        assert_eq!(stats.total_bytes_read, 3);
    }

    #[tokio::test]
    async fn test_batch_put_increments_count_and_bytes() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered
            .batch_put(&[
                (b"a" as &[u8], b"111" as &[u8]),
                (b"b", b"2222"),
            ])
            .await
            .unwrap();

        let stats = metered.stats().await;
        assert_eq!(stats.put_count, 2);
        // Bytes written: 3 + 4 = 7.
        assert_eq!(stats.total_bytes_written, 7);
    }

    #[tokio::test]
    async fn test_latency_is_recorded() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered.put(b"k", b"v").await.unwrap();
        metered.get(b"k").await.unwrap();

        let stats = metered.stats().await;
        // Latency should be non-negative (it might be very small).
        assert!(stats.get_latency_sum_ms >= 0.0);
        assert!(stats.put_latency_sum_ms >= 0.0);
    }

    #[tokio::test]
    async fn test_reset_stats() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);

        metered.put(b"a", b"1").await.unwrap();
        metered.get(b"a").await.unwrap();

        let before = metered.stats().await;
        assert_eq!(before.get_count, 1);
        assert_eq!(before.put_count, 1);

        metered.reset_stats().await;

        let after = metered.stats().await;
        assert_eq!(after.get_count, 0);
        assert_eq!(after.put_count, 0);
        assert_eq!(after.total_bytes_read, 0);
        assert_eq!(after.total_bytes_written, 0);
    }

    #[tokio::test]
    async fn test_name_delegates_to_inner() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);
        assert_eq!(metered.name(), "in-memory");
    }

    #[tokio::test]
    async fn test_flush_delegates_to_inner() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);
        metered.put(b"k", b"v").await.unwrap();
        metered.flush().await.unwrap();
        // Data should survive flush.
        assert_eq!(
            metered.get(b"k").await.unwrap(),
            Some(b"v".to_vec())
        );
    }

    #[tokio::test]
    async fn test_approximate_size_delegates() {
        let inner = InMemoryBackend::new();
        let metered = MetricsBackend::new(inner);
        metered.put(b"abc", b"defgh").await.unwrap();
        let size = metered.approximate_size().await.unwrap();
        assert_eq!(size, Some(8)); // 3 + 5
    }
}
