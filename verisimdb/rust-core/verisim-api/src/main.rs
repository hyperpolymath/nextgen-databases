// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSimDB API server binary
//!
//! Starts the HTTP API server for VeriSimDB.
//! Defaults to IPv6-only ([::]). Set VERISIM_ENABLE_IPV4=true for dual-stack.
//! Set VERISIM_TLS_CERT and VERISIM_TLS_KEY for HTTPS mode.

use verisim_api::ApiConfig;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Install ring as the default crypto provider (pure Rust, no OpenSSL/aws-lc-sys)
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("failed to install ring crypto provider");

    // Initialize tracing with structured JSON output
    let json_logging = std::env::var("VERISIM_LOG_FORMAT")
        .map(|v| v == "json")
        .unwrap_or(true); // JSON by default in production

    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));

    if json_logging {
        tracing_subscriber::fmt()
            .json()
            .with_env_filter(env_filter)
            .init();
    } else {
        tracing_subscriber::fmt()
            .with_env_filter(env_filter)
            .init();
    }

    // IPv6-only by default; VERISIM_ENABLE_IPV4=true for dual-stack (0.0.0.0)
    let default_host = if std::env::var("VERISIM_ENABLE_IPV4")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false)
    {
        "0.0.0.0".to_string()
    } else {
        "[::]".to_string()
    };

    let persist_dir = std::env::var("VERISIM_PERSISTENCE_DIR").ok();

    let config = ApiConfig {
        host: std::env::var("VERISIM_HOST").unwrap_or(default_host),
        port: std::env::var("VERISIM_PORT")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(8080),
        enable_cors: std::env::var("VERISIM_ENABLE_CORS")
            .map(|v| v != "false" && v != "0")
            .unwrap_or(true),
        version_prefix: std::env::var("VERISIM_API_PREFIX")
            .unwrap_or_else(|_| "/api/v1".to_string()),
        vector_dimension: std::env::var("VERISIM_VECTOR_DIM")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(384),
        persistence_dir: persist_dir.clone(),
    };

    let storage_mode = if cfg!(feature = "persistent") { "persistent" } else { "in-memory" };

    tracing::info!(
        host = %config.host,
        port = %config.port,
        storage = %storage_mode,
        persistence_dir = ?persist_dir,
        "Starting VeriSimDB API server"
    );

    // Check for TLS configuration
    let tls_cert = std::env::var("VERISIM_TLS_CERT").ok();
    let tls_key = std::env::var("VERISIM_TLS_KEY").ok();

    match (tls_cert, tls_key) {
        (Some(cert_path), Some(key_path)) => {
            tracing::info!(cert = %cert_path, "Starting with TLS enabled");
            verisim_api::serve_tls(config, &cert_path, &key_path).await?;
        }
        (Some(_), None) | (None, Some(_)) => {
            return Err("Both VERISIM_TLS_CERT and VERISIM_TLS_KEY must be set for TLS".into());
        }
        (None, None) => {
            verisim_api::serve(config).await?;
        }
    }

    Ok(())
}
