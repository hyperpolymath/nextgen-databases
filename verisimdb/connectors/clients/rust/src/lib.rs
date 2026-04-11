// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! # VeriSimDB Client SDK
//!
//! A Rust client library for interacting with VeriSimDB — a multi-modal database
//! supporting octad entity management, drift detection, provenance tracking,
//! VCL query execution, and federation across distributed instances.
//!
//! ## Quick Start
//!
//! ```rust,no_run
//! use verisimdb_client::client::VeriSimClient;
//! use verisimdb_client::types::OctadInput;
//!
//! #[tokio::main]
//! async fn main() -> verisimdb_client::error::Result<()> {
//!     let client = VeriSimClient::new("http://localhost:8080")?;
//!     let healthy = client.health().await?;
//!     println!("VeriSimDB healthy: {healthy}");
//!     Ok(())
//! }
//! ```
//!
//! ## Modules
//!
//! - [`client`] — Connection configuration, authentication, and HTTP transport.
//! - [`types`] — Data types mirroring the VeriSimDB JSON Schema (Octad, Modality, etc.).
//! - [`octad`] — CRUD operations for octad entities.
//! - [`search`] — Text, vector, graph-relational, and spatial search operations.
//! - [`drift`] — Drift score retrieval and normalization triggers.
//! - [`provenance`] — Immutable provenance chain management.
//! - [`vcl`] — VeriSim Consonance Language execution and explain plans.
//! - [`federation`] — Peer registration and federated cross-instance queries.
//! - [`error`] — Error types and the crate-level `Result` alias.

#![forbid(unsafe_code)]
pub mod client;
pub mod types;
pub mod octad;
pub mod search;
pub mod drift;
pub mod provenance;
pub mod vcl;
pub mod federation;
pub mod error;
