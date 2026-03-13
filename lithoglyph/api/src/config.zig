// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - Configuration

const std = @import("std");

pub const Config = struct {
    allocator: std.mem.Allocator,

    // Server settings
    host: []const u8,
    port: u16,
    version: []const u8,

    // Authentication
    jwt_secret: ?[]const u8,
    api_key_header: []const u8,
    require_auth: bool,

    // Database connection
    db_path: []const u8,

    // Logging
    log_level: std.log.Level,

    // Limits
    max_request_size: usize,
    max_response_rows: usize,
    request_timeout_ms: u64,

    // TLS (optional)
    tls_cert_path: ?[]const u8,
    tls_key_path: ?[]const u8,

    pub fn deinit(self: *const Config) void {
        // Free allocated strings if needed
        _ = self;
    }
};

pub fn load(allocator: std.mem.Allocator) !*const Config {
    const config = try allocator.create(Config);

    config.* = Config{
        .allocator = allocator,

        // Server defaults
        .host = getEnvOrDefault("LITH_HOST", "127.0.0.1"),
        .port = getEnvPort("LITH_PORT", 8080),
        .version = "0.0.4",

        // Auth defaults
        .jwt_secret = std.posix.getenv("LITH_JWT_SECRET"),
        .api_key_header = getEnvOrDefault("LITH_API_KEY_HEADER", "X-API-Key"),
        .require_auth = getEnvBool("LITH_REQUIRE_AUTH", false),

        // Database
        .db_path = getEnvOrDefault("LITH_DB_PATH", "./lithoglyph.dat"),

        // Logging
        .log_level = .info,

        // Limits
        .max_request_size = 10 * 1024 * 1024, // 10 MB
        .max_response_rows = 10000,
        .request_timeout_ms = 30000, // 30 seconds

        // TLS
        .tls_cert_path = std.posix.getenv("LITH_TLS_CERT"),
        .tls_key_path = std.posix.getenv("LITH_TLS_KEY"),
    };

    return config;
}

fn getEnvOrDefault(key: []const u8, default: []const u8) []const u8 {
    return std.posix.getenv(key) orelse default;
}

fn getEnvPort(key: []const u8, default: u16) u16 {
    const env = std.posix.getenv(key) orelse return default;
    return std.fmt.parseInt(u16, env, 10) catch default;
}

fn getEnvBool(key: []const u8, default: bool) bool {
    const env = std.posix.getenv(key) orelse return default;
    return std.mem.eql(u8, env, "true") or std.mem.eql(u8, env, "1");
}

test "config loading" {
    const allocator = std.testing.allocator;
    const cfg = try load(allocator);
    defer allocator.destroy(cfg);

    try std.testing.expectEqualStrings("127.0.0.1", cfg.host);
    try std.testing.expectEqual(@as(u16, 8080), cfg.port);
}
