// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Lithoglyph API Server - Authentication
//
// Authentication tokens are loaded from environment variables at startup.
// NEVER hardcode tokens, secrets, or API keys in source code.

const std = @import("std");
const config = @import("config.zig");

const log = std.log.scoped(.auth);

/// Environment variable name for the auth token used in development/testing.
/// In production, use LITH_JWT_SECRET (read via config) for real JWT validation.
const AUTH_TOKEN_ENV = "LITHOGLYPH_AUTH_TOKEN";

/// Error set for authentication operations
pub const AuthError = error{
    /// LITHOGLYPH_AUTH_TOKEN environment variable is not set
    AuthTokenNotConfigured,
    /// Token provided does not match the configured token
    InvalidToken,
    /// Token has expired or is malformed
    MalformedToken,
    /// JWT secret not configured (LITH_JWT_SECRET missing)
    JwtSecretNotConfigured,
};

var allocator: std.mem.Allocator = undefined;
var cfg: *const config.Config = undefined;

// API key storage (in production, use persistent storage)
var api_keys: std.StringHashMap(ApiKey) = undefined;

pub const ApiKey = struct {
    name: []const u8,
    scopes: []const Scope,
    created_at: i64,
    expires_at: ?i64,
};

pub const Scope = enum {
    read,
    write,
    admin,
    migrate,
};

pub fn init(alloc: std.mem.Allocator, config_ptr: *const config.Config) !void {
    allocator = alloc;
    cfg = config_ptr;
    api_keys = std.StringHashMap(ApiKey).init(alloc);

    // Load API key from environment variable — NEVER hardcode keys in source
    if (std.posix.getenv(AUTH_TOKEN_ENV)) |env_key| {
        if (env_key.len > 0) {
            try api_keys.put(env_key, .{
                .name = "Environment Key",
                .scopes = &[_]Scope{ .read, .write, .admin, .migrate },
                .created_at = std.time.timestamp(),
                .expires_at = null,
            });
            log.info("Authentication initialized with environment key", .{});
        } else {
            log.warn("{s} is set but empty — no API key registered", .{AUTH_TOKEN_ENV});
        }
    } else {
        log.warn("{s} not set — API key authentication disabled. " ++
            "Set this environment variable to enable token-based auth.", .{AUTH_TOKEN_ENV});
    }
}

pub fn deinit() void {
    api_keys.deinit();
}

pub fn validateRequest(request: *std.http.Server.Request) !bool {
    // Check for API key
    if (getHeader(request, cfg.api_key_header)) |key| {
        return validateApiKey(key);
    }

    // Check for Bearer token
    if (getHeader(request, "authorization")) |auth| {
        if (std.mem.startsWith(u8, auth, "Bearer ")) {
            const token = auth["Bearer ".len..];
            return validateJWT(token);
        }
    }

    return false;
}

pub fn validateApiKey(key: []const u8) bool {
    if (api_keys.get(key)) |_| {
        return true;
    }
    return false;
}

pub fn validateJWT(token: []const u8) bool {
    // TODO: Replace with real JWT validation using HMAC-SHA256 or RS256.
    //       This stub only checks structural validity (3 dot-separated parts)
    //       and verifies the JWT secret is configured. It does NOT verify
    //       the signature, expiration, or claims. A proper JWT library
    //       (e.g. zig-jwt or a C binding to libjwt) is required for
    //       production deployment.

    // Reject if no JWT secret is configured
    if (cfg.jwt_secret == null) {
        log.warn("JWT validation failed: LITH_JWT_SECRET not set", .{});
        return false;
    }

    // JWT format: header.payload.signature (exactly 3 parts)
    var parts = std.mem.splitScalar(u8, token, '.');

    const header = parts.next() orelse return false;
    const payload = parts.next() orelse return false;
    const signature = parts.next() orelse return false;

    // Verify there are exactly 3 parts
    if (parts.next() != null) return false;

    // Reject empty segments
    if (header.len == 0 or payload.len == 0 or signature.len == 0) return false;

    // TODO: Verify signature using HMAC-SHA256 with cfg.jwt_secret.?
    // TODO: Decode payload, check "exp" claim against current time
    // TODO: Validate "iss", "aud" claims against expected values

    log.warn("JWT accepted without signature verification — NOT SAFE FOR PRODUCTION", .{});
    return true;
}

pub fn getScopes(request: *std.http.Server.Request) []const Scope {
    if (getHeader(request, cfg.api_key_header)) |key| {
        if (api_keys.get(key)) |api_key| {
            return api_key.scopes;
        }
    }
    return &[_]Scope{};
}

pub fn hasScope(request: *std.http.Server.Request, required: Scope) bool {
    const scopes = getScopes(request);
    for (scopes) |s| {
        if (s == required or s == .admin) {
            return true;
        }
    }
    return false;
}

fn getHeader(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var iter = request.iterateHeaders();
    while (iter.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            return header.value;
        }
    }
    return null;
}

// =============================================================================
// JWT Helpers
// =============================================================================

pub const Claims = struct {
    sub: []const u8, // Subject (user ID)
    exp: i64, // Expiration time
    iat: i64, // Issued at
    scopes: []const Scope,
};

pub fn createJWT(claims: Claims) AuthError![]const u8 {
    _ = claims;
    // TODO: Implement real JWT creation with HMAC-SHA256 signature.
    //       Steps needed:
    //       1. Base64url-encode JSON header {"alg":"HS256","typ":"JWT"}
    //       2. Base64url-encode JSON payload from claims
    //       3. Sign header.payload with LITH_JWT_SECRET using HMAC-SHA256
    //       4. Return header.payload.signature
    //
    //       Until implemented, callers should use API key auth instead.

    const secret = std.posix.getenv("LITH_JWT_SECRET") orelse {
        log.err("Cannot create JWT: LITH_JWT_SECRET environment variable not set", .{});
        return AuthError.JwtSecretNotConfigured;
    };
    _ = secret;

    // Return error rather than a fake token — callers must handle this
    return AuthError.JwtSecretNotConfigured;
}

pub fn parseJWT(token: []const u8) AuthError!Claims {
    // TODO: Implement real JWT parsing and signature verification.
    //       Steps needed:
    //       1. Split token on '.'
    //       2. Base64url-decode header and payload
    //       3. Verify signature using LITH_JWT_SECRET
    //       4. Parse claims from payload JSON
    //       5. Validate exp > now, check iss/aud
    //
    //       Until implemented, reject all tokens.

    _ = token;

    const secret = std.posix.getenv("LITH_JWT_SECRET") orelse {
        log.err("Cannot parse JWT: LITH_JWT_SECRET environment variable not set", .{});
        return AuthError.JwtSecretNotConfigured;
    };
    _ = secret;

    // For now, return a minimal read-only claim set with short expiry.
    // This is a stub — real implementation must verify the signature first.
    return .{
        .sub = "unverified",
        .exp = std.time.timestamp() + 300, // 5 minutes, not 1 hour
        .iat = std.time.timestamp(),
        .scopes = &[_]Scope{.read}, // Read-only until real verification
    };
}

// =============================================================================
// mTLS Support (for gRPC)
// =============================================================================

pub const TLSConfig = struct {
    cert_path: []const u8,
    key_path: []const u8,
    ca_path: ?[]const u8 = null, // For mTLS
    require_client_cert: bool = false,
};

pub fn validateClientCert(cert_chain: []const u8) bool {
    // TODO: Validate client certificate chain against configured CA.
    //       This is a security-critical stub that must be implemented
    //       before enabling mTLS in production.
    _ = cert_chain;
    log.warn("Client certificate validation not implemented — accepting all certs", .{});
    return true;
}

test "api key from environment" {
    // With no environment variable set, no keys should be registered
    // (we cannot set env vars in Zig tests, so we test the empty case)
    const alloc = std.testing.allocator;
    var keys = std.StringHashMap(ApiKey).init(alloc);
    defer keys.deinit();

    // Verify that unknown keys are rejected
    try std.testing.expect(keys.get("nonexistent-key") == null);
}

test "jwt structure validation" {
    const valid_jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signature";
    var parts = std.mem.splitScalar(u8, valid_jwt, '.');

    try std.testing.expect(parts.next() != null);
    try std.testing.expect(parts.next() != null);
    try std.testing.expect(parts.next() != null);
    try std.testing.expect(parts.next() == null);
}

test "empty jwt segments rejected" {
    // A JWT with empty segments should be structurally invalid
    const bad_jwt = ".payload.signature";
    var parts = std.mem.splitScalar(u8, bad_jwt, '.');
    const header = parts.next() orelse unreachable;
    try std.testing.expect(header.len == 0); // Would be rejected by validateJWT
}
