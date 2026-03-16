// SPDX-License-Identifier: PMPL-1.0-or-later
//! Lith-Geo library
//!
//! Geospatial extension for Lith providing spatial indexing
//! and queries while preserving auditability guarantees.

#![forbid(unsafe_code)]
pub mod api;
pub mod config;
pub mod lithoglyph;
pub mod index;

pub use config::Config;
pub use index::SpatialIndex;
