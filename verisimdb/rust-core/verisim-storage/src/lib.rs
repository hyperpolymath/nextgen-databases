// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// VeriSimDB Storage Backend Abstraction
//
// This crate provides a pluggable key-value storage interface for VeriSimDB.
// The core `StorageBackend` trait defines the contract that all backends must
// implement, enabling the database engine to swap storage implementations
// without changing application logic.
//
// # Modules
//
// - [`backend`] -- The `StorageBackend` trait defining the key-value interface.
// - [`error`] -- The `StorageError` enum covering all backend failure modes.
// - [`memory`] -- An in-memory `BTreeMap`-based backend for testing and
//   ephemeral workloads.
// - [`typed`] -- A serde-based typed wrapper with namespace prefixing.
// - [`metrics`] -- A transparent wrapper that collects operation statistics.
//
// # Example
//
// ```rust
// use verisim_storage::backend::StorageBackend;
// use verisim_storage::memory::InMemoryBackend;
// use verisim_storage::typed::TypedStore;
// use verisim_storage::metrics::MetricsBackend;
//
// # tokio_test::block_on(async {
// // Create an in-memory backend with metrics collection.
// let raw = InMemoryBackend::new();
// let metered = MetricsBackend::new(raw);
//
// // Use a typed store for structured data.
// let store = TypedStore::new(metered, "entities");
// store.put("e1", &serde_json::json!({"name": "test"})).await.unwrap();
//
// let val: serde_json::Value = store.get("e1").await.unwrap().unwrap();
// assert_eq!(val["name"], "test");
// # });
// ```

pub mod backend;
pub mod error;
pub mod memory;
pub mod metrics;
pub mod typed;

// Optional persistent backends — feature-gated to keep the default build lean.
#[cfg(feature = "redb-backend")]
pub mod redb_backend;

// Re-export the most commonly used types at the crate root for convenience.
pub use backend::StorageBackend;
pub use error::StorageError;
pub use memory::InMemoryBackend;
pub use metrics::{BackendStats, MetricsBackend};
pub use typed::TypedStore;

#[cfg(feature = "redb-backend")]
pub use redb_backend::RedbBackend;
