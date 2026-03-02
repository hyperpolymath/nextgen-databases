// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
//! Authentication and rate limiting for VeriSimDB API.
//!
//! Supports two authentication methods:
//! - **API Key**: Passed via `X-API-Key` header
//! - **JWT Bearer Token**: Passed via `Authorization: Bearer <token>` header
//!
//! Rate limiting is per-client (identified by API key or IP address).

use axum::{
    extract::{Request, State},
    http::{header, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tracing::{info, warn};

/// Authentication configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthConfig {
    /// Whether authentication is enabled. When disabled, all requests pass through.
    pub enabled: bool,
    /// Whether to allow unauthenticated access to health/ready/metrics endpoints.
    pub allow_public_health: bool,
    /// Maximum requests per minute per client (0 = unlimited).
    pub rate_limit_per_minute: u32,
    /// JWT secret for HMAC-SHA256 verification (if using JWT).
    #[serde(skip_serializing)]
    pub jwt_secret: Option<String>,
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            allow_public_health: true,
            rate_limit_per_minute: 0,
            jwt_secret: None,
        }
    }
}

/// Client identity extracted from an authenticated request.
#[derive(Debug, Clone)]
pub struct ClientIdentity {
    /// The client identifier (API key hash or JWT subject).
    pub id: String,
    /// Role assigned to this client.
    pub role: ClientRole,
}

/// Role-based access level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientRole {
    /// Read-only access to all endpoints.
    Reader,
    /// Read and write access to hexad CRUD and queries.
    Writer,
    /// Full access including admin operations (config, normalizer triggers).
    Admin,
}

/// Registered API key with associated metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiKeyEntry {
    /// SHA-256 hash of the API key (never store plaintext).
    pub key_hash: String,
    /// Human-readable label for this key.
    pub label: String,
    /// Role granted to holders of this key.
    pub role: ClientRole,
    /// Whether this key is currently active.
    pub active: bool,
}

/// In-memory API key registry.
///
/// In production, this would be backed by a persistent store. For now,
/// keys are registered at startup or via admin endpoints.
#[derive(Debug, Clone)]
pub struct ApiKeyRegistry {
    /// Map from key hash → entry.
    keys: Arc<Mutex<HashMap<String, ApiKeyEntry>>>,
}

impl ApiKeyRegistry {
    /// Create a new empty registry.
    pub fn new() -> Self {
        Self {
            keys: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Register a new API key. The key is hashed before storage.
    pub fn register(&self, plaintext_key: &str, label: &str, role: ClientRole) {
        let hash = hash_key(plaintext_key);
        let entry = ApiKeyEntry {
            key_hash: hash.clone(),
            label: label.to_string(),
            role,
            active: true,
        };
        let mut keys = self.keys.lock().expect("key registry lock");
        keys.insert(hash, entry);
    }

    /// Validate an API key. Returns the entry if the key is valid and active.
    pub fn validate(&self, plaintext_key: &str) -> Option<ApiKeyEntry> {
        let hash = hash_key(plaintext_key);
        let keys = self.keys.lock().expect("key registry lock");
        keys.get(&hash)
            .filter(|entry| entry.active)
            .cloned()
    }

    /// Revoke an API key by its hash.
    pub fn revoke(&self, key_hash: &str) -> bool {
        let mut keys = self.keys.lock().expect("key registry lock");
        if let Some(entry) = keys.get_mut(key_hash) {
            entry.active = false;
            true
        } else {
            false
        }
    }

    /// List all registered keys (without plaintext).
    pub fn list(&self) -> Vec<ApiKeyEntry> {
        let keys = self.keys.lock().expect("key registry lock");
        keys.values().cloned().collect()
    }
}

impl Default for ApiKeyRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Per-client rate limiter using a sliding window counter.
#[derive(Debug, Clone)]
pub struct RateLimiter {
    /// Map from client ID → (request timestamps in current window).
    windows: Arc<Mutex<HashMap<String, Vec<Instant>>>>,
    /// Maximum requests per window.
    max_requests: u32,
    /// Window duration.
    window: Duration,
}

impl RateLimiter {
    /// Create a new rate limiter.
    pub fn new(max_requests_per_minute: u32) -> Self {
        Self {
            windows: Arc::new(Mutex::new(HashMap::new())),
            max_requests: max_requests_per_minute,
            window: Duration::from_secs(60),
        }
    }

    /// Check if a client is allowed to make a request. Returns true if allowed.
    pub fn check(&self, client_id: &str) -> bool {
        if self.max_requests == 0 {
            return true; // Unlimited.
        }

        let now = Instant::now();
        let mut windows = self.windows.lock().expect("rate limiter lock");
        let timestamps = windows.entry(client_id.to_string()).or_default();

        // Remove expired timestamps.
        timestamps.retain(|t| now.duration_since(*t) < self.window);

        if timestamps.len() as u32 >= self.max_requests {
            false
        } else {
            timestamps.push(now);
            true
        }
    }

    /// Get the number of remaining requests for a client in the current window.
    pub fn remaining(&self, client_id: &str) -> u32 {
        if self.max_requests == 0 {
            return u32::MAX;
        }

        let now = Instant::now();
        let mut windows = self.windows.lock().expect("rate limiter lock");
        let timestamps = windows.entry(client_id.to_string()).or_default();
        timestamps.retain(|t| now.duration_since(*t) < self.window);

        self.max_requests.saturating_sub(timestamps.len() as u32)
    }
}

/// Shared authentication state, added to `AppState`.
#[derive(Debug, Clone)]
pub struct AuthState {
    pub config: AuthConfig,
    pub key_registry: ApiKeyRegistry,
    pub rate_limiter: RateLimiter,
    /// RBAC state for fine-grained authorization checks.
    pub rbac: crate::rbac::RbacState,
}

impl AuthState {
    /// Create auth state from config.
    pub fn new(config: AuthConfig) -> Self {
        let rate_limiter = RateLimiter::new(config.rate_limit_per_minute);
        Self {
            config,
            key_registry: ApiKeyRegistry::new(),
            rate_limiter,
            rbac: crate::rbac::RbacState::default(),
        }
    }

    /// Create auth state from config with a custom RBAC policy.
    pub fn with_rbac(config: AuthConfig, rbac: crate::rbac::RbacState) -> Self {
        let rate_limiter = RateLimiter::new(config.rate_limit_per_minute);
        Self {
            config,
            key_registry: ApiKeyRegistry::new(),
            rate_limiter,
            rbac,
        }
    }
}

impl Default for AuthState {
    fn default() -> Self {
        Self::new(AuthConfig::default())
    }
}

/// Authentication error response.
#[derive(Debug, Serialize)]
pub struct AuthError {
    pub error: String,
    pub code: u16,
}

/// Axum middleware that performs authentication and rate limiting.
///
/// This middleware:
/// 1. Checks if auth is enabled (passes through if disabled)
/// 2. Allows public health endpoints if configured
/// 3. Extracts API key from `X-API-Key` header or JWT from `Authorization: Bearer`
/// 4. Validates the credential against the key registry
/// 5. Checks rate limits for the identified client
pub async fn auth_middleware(
    State(auth): State<AuthState>,
    request: Request,
    next: Next,
) -> Response {
    // If auth is disabled, pass through.
    if !auth.config.enabled {
        return next.run(request).await;
    }

    let path = request.uri().path().to_string();

    // Allow public health endpoints without auth.
    if auth.config.allow_public_health
        && (path == "/health" || path == "/ready" || path == "/metrics")
    {
        return next.run(request).await;
    }

    // Extract credential.
    let identity = match extract_identity(&request, &auth) {
        Ok(id) => id,
        Err(response) => return response,
    };

    // Rate limit check.
    if !auth.rate_limiter.check(&identity.id) {
        warn!(client = %identity.id, "Rate limit exceeded");
        let remaining = auth.rate_limiter.remaining(&identity.id);
        return (
            StatusCode::TOO_MANY_REQUESTS,
            [
                (header::HeaderName::from_static("x-ratelimit-remaining"),
                 remaining.to_string()),
                (header::RETRY_AFTER, "60".to_string()),
            ],
            Json(AuthError {
                error: "Rate limit exceeded".to_string(),
                code: 429,
            }),
        )
            .into_response();
    }

    // RBAC authorization check.
    let method = request.method().clone();
    if let Err(authz_err) = crate::rbac::check_authorization(
        &identity,
        &path,
        &method,
        &auth.rbac,
    ) {
        warn!(
            client = %identity.id,
            role = ?identity.role,
            path = %path,
            "Authorization denied: {}",
            authz_err.error
        );
        return authz_err.into_response();
    }

    next.run(request).await
}

/// Extract client identity from request headers.
fn extract_identity(request: &Request, auth: &AuthState) -> Result<ClientIdentity, Response> {
    // Try X-API-Key header first.
    if let Some(api_key) = request
        .headers()
        .get("x-api-key")
        .and_then(|v| v.to_str().ok())
    {
        if let Some(entry) = auth.key_registry.validate(api_key) {
            info!(label = %entry.label, role = ?entry.role, "API key authenticated");
            return Ok(ClientIdentity {
                id: entry.key_hash.clone(),
                role: entry.role,
            });
        }
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(AuthError {
                error: "Invalid API key".to_string(),
                code: 401,
            }),
        )
            .into_response());
    }

    // Try Authorization: Bearer header.
    if let Some(auth_header) = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
    {
        if let Some(token) = auth_header.strip_prefix("Bearer ") {
            match validate_jwt(token, &auth.config) {
                Ok(identity) => {
                    info!(subject = %identity.id, role = ?identity.role, "JWT authenticated");
                    return Ok(identity);
                }
                Err(msg) => {
                    return Err((
                        StatusCode::UNAUTHORIZED,
                        Json(AuthError {
                            error: msg,
                            code: 401,
                        }),
                    )
                        .into_response());
                }
            }
        }
    }

    // No credentials provided.
    Err((
        StatusCode::UNAUTHORIZED,
        [(header::WWW_AUTHENTICATE, "Bearer, ApiKey")],
        Json(AuthError {
            error: "Authentication required. Provide X-API-Key header or Authorization: Bearer <token>".to_string(),
            code: 401,
        }),
    )
        .into_response())
}

/// Validate a JWT token (HMAC-SHA256).
///
/// VeriSimDB uses a minimal JWT implementation: we only verify the signature
/// and extract the `sub` (subject) and `role` claims. Expiration is checked
/// via the `exp` claim.
fn validate_jwt(token: &str, config: &AuthConfig) -> Result<ClientIdentity, String> {
    let secret = config
        .jwt_secret
        .as_deref()
        .ok_or_else(|| "JWT authentication not configured".to_string())?;

    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return Err("Invalid JWT format".to_string());
    }

    // Decode the header and payload.
    let payload_bytes = base64url_decode(parts[1])
        .map_err(|_| "Invalid JWT payload encoding".to_string())?;

    // Verify HMAC-SHA256 signature.
    let signing_input = format!("{}.{}", parts[0], parts[1]);
    let expected_sig = hmac_sha256(signing_input.as_bytes(), secret.as_bytes());
    let actual_sig = base64url_decode(parts[2])
        .map_err(|_| "Invalid JWT signature encoding".to_string())?;

    if expected_sig != actual_sig {
        return Err("Invalid JWT signature".to_string());
    }

    // Parse claims.
    let claims: serde_json::Value = serde_json::from_slice(&payload_bytes)
        .map_err(|_| "Invalid JWT payload".to_string())?;

    // Check expiration.
    if let Some(exp) = claims.get("exp").and_then(|v| v.as_i64()) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;
        if now > exp {
            return Err("JWT token expired".to_string());
        }
    }

    let subject = claims
        .get("sub")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_string();

    let role = claims
        .get("role")
        .and_then(|v| v.as_str())
        .map(|r| match r {
            "admin" => ClientRole::Admin,
            "writer" => ClientRole::Writer,
            _ => ClientRole::Reader,
        })
        .unwrap_or(ClientRole::Reader);

    Ok(ClientIdentity {
        id: subject,
        role,
    })
}

/// Hash an API key with SHA-256 for storage.
fn hash_key(key: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(key.as_bytes());
    let hash = hasher.finalize();
    hex::encode(hash)
}

/// Compute HMAC-SHA256.
fn hmac_sha256(data: &[u8], key: &[u8]) -> Vec<u8> {
    // HMAC: H((key XOR opad) || H((key XOR ipad) || message))
    let block_size = 64;
    let mut key_block = vec![0u8; block_size];

    if key.len() > block_size {
        let mut hasher = Sha256::new();
        hasher.update(key);
        let hashed = hasher.finalize();
        key_block[..hashed.len()].copy_from_slice(&hashed);
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }

    let mut ipad = vec![0x36u8; block_size];
    let mut opad = vec![0x5cu8; block_size];
    for i in 0..block_size {
        ipad[i] ^= key_block[i];
        opad[i] ^= key_block[i];
    }

    // Inner hash.
    let mut inner_hasher = Sha256::new();
    inner_hasher.update(&ipad);
    inner_hasher.update(data);
    let inner_hash = inner_hasher.finalize();

    // Outer hash.
    let mut outer_hasher = Sha256::new();
    outer_hasher.update(&opad);
    outer_hasher.update(&inner_hash);
    outer_hasher.finalize().to_vec()
}

/// Base64url decode (RFC 4648 without padding).
fn base64url_decode(input: &str) -> Result<Vec<u8>, &'static str> {
    // Add padding if needed.
    let padded = match input.len() % 4 {
        2 => format!("{input}=="),
        3 => format!("{input}="),
        0 => input.to_string(),
        _ => return Err("invalid base64url length"),
    };

    // Replace URL-safe characters with standard base64.
    let standard = padded.replace('-', "+").replace('_', "/");

    // Decode using a simple base64 decoder.
    base64_decode(&standard)
}

/// Simple base64 decoder.
fn base64_decode(input: &str) -> Result<Vec<u8>, &'static str> {
    const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    fn char_to_val(c: u8) -> Result<u8, &'static str> {
        if c == b'=' {
            return Ok(0);
        }
        CHARSET
            .iter()
            .position(|&x| x == c)
            .map(|p| p as u8)
            .ok_or("invalid base64 character")
    }

    let bytes = input.as_bytes();
    if bytes.len() % 4 != 0 {
        return Err("invalid base64 length");
    }

    let mut result = Vec::with_capacity(bytes.len() * 3 / 4);

    for chunk in bytes.chunks(4) {
        let a = char_to_val(chunk[0])?;
        let b = char_to_val(chunk[1])?;
        let c = char_to_val(chunk[2])?;
        let d = char_to_val(chunk[3])?;

        result.push((a << 2) | (b >> 4));
        if chunk[2] != b'=' {
            result.push((b << 4) | (c >> 2));
        }
        if chunk[3] != b'=' {
            result.push((c << 6) | d);
        }
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_key_deterministic() {
        let hash1 = hash_key("test-key-123");
        let hash2 = hash_key("test-key-123");
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_hash_key_different_keys() {
        let hash1 = hash_key("key-a");
        let hash2 = hash_key("key-b");
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_api_key_registry_register_and_validate() {
        let registry = ApiKeyRegistry::new();
        registry.register("my-secret-key", "Test Key", ClientRole::Writer);

        let entry = registry.validate("my-secret-key");
        assert!(entry.is_some());
        let entry = entry.unwrap();
        assert_eq!(entry.label, "Test Key");
        assert_eq!(entry.role, ClientRole::Writer);
        assert!(entry.active);
    }

    #[test]
    fn test_api_key_registry_invalid_key() {
        let registry = ApiKeyRegistry::new();
        registry.register("correct-key", "Valid", ClientRole::Reader);

        let result = registry.validate("wrong-key");
        assert!(result.is_none());
    }

    #[test]
    fn test_api_key_registry_revoke() {
        let registry = ApiKeyRegistry::new();
        registry.register("revokable-key", "Temp", ClientRole::Admin);

        let hash = hash_key("revokable-key");
        assert!(registry.revoke(&hash));

        let result = registry.validate("revokable-key");
        assert!(result.is_none());
    }

    #[test]
    fn test_rate_limiter_allows_within_limit() {
        let limiter = RateLimiter::new(10);
        for _ in 0..10 {
            assert!(limiter.check("client-1"));
        }
    }

    #[test]
    fn test_rate_limiter_blocks_over_limit() {
        let limiter = RateLimiter::new(3);
        assert!(limiter.check("client-x"));
        assert!(limiter.check("client-x"));
        assert!(limiter.check("client-x"));
        assert!(!limiter.check("client-x")); // 4th should be blocked
    }

    #[test]
    fn test_rate_limiter_unlimited() {
        let limiter = RateLimiter::new(0);
        for _ in 0..1000 {
            assert!(limiter.check("anyone"));
        }
    }

    #[test]
    fn test_rate_limiter_per_client() {
        let limiter = RateLimiter::new(2);
        assert!(limiter.check("alice"));
        assert!(limiter.check("alice"));
        assert!(!limiter.check("alice")); // Alice blocked

        // Bob should still have quota
        assert!(limiter.check("bob"));
        assert!(limiter.check("bob"));
    }

    #[test]
    fn test_rate_limiter_remaining() {
        let limiter = RateLimiter::new(5);
        assert_eq!(limiter.remaining("test"), 5);
        limiter.check("test");
        assert_eq!(limiter.remaining("test"), 4);
    }

    #[test]
    fn test_hmac_sha256_known_vector() {
        // RFC 4231 Test Case 2
        let key = b"Jefe";
        let data = b"what do ya want for nothing?";
        let mac = hmac_sha256(data, key);
        let hex = hex::encode(&mac);
        assert_eq!(
            hex,
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
    }

    #[test]
    fn test_base64url_decode() {
        // "hello" in base64url is "aGVsbG8"
        let decoded = base64url_decode("aGVsbG8").unwrap();
        assert_eq!(decoded, b"hello");
    }

    #[test]
    fn test_auth_config_default() {
        let config = AuthConfig::default();
        assert!(!config.enabled);
        assert!(config.allow_public_health);
        assert_eq!(config.rate_limit_per_minute, 0);
    }

    #[test]
    fn test_jwt_validation() {
        // Create a minimal JWT for testing.
        let config = AuthConfig {
            enabled: true,
            allow_public_health: true,
            rate_limit_per_minute: 0,
            jwt_secret: Some("test-secret".to_string()),
        };

        // Create JWT: header.payload.signature
        let header = base64url_encode(b"{\"alg\":\"HS256\",\"typ\":\"JWT\"}");
        // Set exp far in the future.
        let payload = base64url_encode(
            b"{\"sub\":\"test-user\",\"role\":\"admin\",\"exp\":9999999999}",
        );
        let signing_input = format!("{header}.{payload}");
        let sig = hmac_sha256(signing_input.as_bytes(), b"test-secret");
        let sig_encoded = base64url_encode(&sig);
        let token = format!("{header}.{payload}.{sig_encoded}");

        let result = validate_jwt(&token, &config);
        assert!(result.is_ok());
        let identity = result.unwrap();
        assert_eq!(identity.id, "test-user");
        assert_eq!(identity.role, ClientRole::Admin);
    }

    #[test]
    fn test_jwt_expired() {
        let config = AuthConfig {
            enabled: true,
            allow_public_health: true,
            rate_limit_per_minute: 0,
            jwt_secret: Some("test-secret".to_string()),
        };

        let header = base64url_encode(b"{\"alg\":\"HS256\",\"typ\":\"JWT\"}");
        let payload = base64url_encode(b"{\"sub\":\"expired-user\",\"exp\":1}");
        let signing_input = format!("{header}.{payload}");
        let sig = hmac_sha256(signing_input.as_bytes(), b"test-secret");
        let sig_encoded = base64url_encode(&sig);
        let token = format!("{header}.{payload}.{sig_encoded}");

        let result = validate_jwt(&token, &config);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("expired"));
    }

    #[test]
    fn test_jwt_invalid_signature() {
        let config = AuthConfig {
            enabled: true,
            allow_public_health: true,
            rate_limit_per_minute: 0,
            jwt_secret: Some("correct-secret".to_string()),
        };

        let header = base64url_encode(b"{\"alg\":\"HS256\",\"typ\":\"JWT\"}");
        let payload = base64url_encode(b"{\"sub\":\"hacker\",\"exp\":9999999999}");
        let signing_input = format!("{header}.{payload}");
        // Sign with WRONG secret.
        let sig = hmac_sha256(signing_input.as_bytes(), b"wrong-secret");
        let sig_encoded = base64url_encode(&sig);
        let token = format!("{header}.{payload}.{sig_encoded}");

        let result = validate_jwt(&token, &config);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("signature"));
    }

    /// Base64url encode for test helpers.
    fn base64url_encode(input: &[u8]) -> String {
        const CHARSET: &[u8] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        let mut result = String::new();
        let mut i = 0;
        while i < input.len() {
            let a = input[i];
            let b = if i + 1 < input.len() { input[i + 1] } else { 0 };
            let c = if i + 2 < input.len() { input[i + 2] } else { 0 };

            result.push(CHARSET[(a >> 2) as usize] as char);
            result.push(CHARSET[((a & 0x03) << 4 | b >> 4) as usize] as char);

            if i + 1 < input.len() {
                result.push(CHARSET[((b & 0x0f) << 2 | c >> 6) as usize] as char);
            }
            if i + 2 < input.len() {
                result.push(CHARSET[(c & 0x3f) as usize] as char);
            }
            i += 3;
        }

        // Convert to URL-safe base64 (no padding).
        result.replace('+', "-").replace('/', "_")
    }
}
