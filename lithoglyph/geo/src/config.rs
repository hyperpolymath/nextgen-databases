// SPDX-License-Identifier: PMPL-1.0-or-later
//! Configuration management for Lith-Geo

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Main configuration structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub lithoglyph: LithConfig,
    pub server: ServerConfig,
    pub index: IndexConfig,
}

/// Lith connection configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LithConfig {
    /// Lith HTTP API URL
    pub api_url: String,
    /// Collection to index for spatial data
    pub collection: String,
    /// Field name containing location coordinates
    pub location_field: String,
}

/// HTTP server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Host to bind to
    pub host: String,
    /// Port to listen on
    pub port: u16,
}

/// Spatial index configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndexConfig {
    /// Auto-rebuild interval in minutes (0 = manual only)
    pub auto_rebuild_minutes: u32,
    /// Maximum memory for R-tree index in MB
    pub max_memory_mb: usize,
}

impl Config {
    /// Load configuration from file
    pub fn load(path: &Path) -> Result<Self> {
        if path.exists() {
            let content = std::fs::read_to_string(path)
                .with_context(|| format!("Failed to read config file: {}", path.display()))?;
            toml::from_str(&content)
                .with_context(|| format!("Failed to parse config file: {}", path.display()))
        } else {
            Ok(Self::default())
        }
    }

    /// Save configuration to file
    pub fn save(&self, path: &Path) -> Result<()> {
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            lithoglyph: LithConfig {
                api_url: "http://localhost:8080".to_string(),
                collection: "evidence".to_string(),
                location_field: "location".to_string(),
            },
            server: ServerConfig {
                host: "127.0.0.1".to_string(),
                port: 8081,
            },
            index: IndexConfig {
                auto_rebuild_minutes: 0,
                max_memory_mb: 512,
            },
        }
    }
}
