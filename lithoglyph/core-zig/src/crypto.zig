// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph Cryptography Module
//
// Provides AES-256-GCM encryption for block payloads
// Designed to integrate with Svalinn Vault's existing crypto system

const std = @import("std");
const builtin = @import("builtin");
const blocks = @import("blocks.zig");

// ============================================================
// Constants
// ============================================================

pub const AES256_KEY_SIZE: usize = 32; // 256 bits
pub const AES_GCM_NONCE_SIZE: usize = 12; // 96 bits for GCM
pub const AES_GCM_TAG_SIZE: usize = 16; // 128 bits authentication tag

// ============================================================
// Error Types
// ============================================================

pub const CryptoError = error{
    InvalidKeySize,
    EncryptionFailed,
    DecryptionFailed,
    AuthenticationFailed,
    BufferTooSmall,
};

// ============================================================
// AES-256-GCM Implementation
// ============================================================

// Encrypt block payload using AES-256-GCM
// Uses block_id as part of nonce for uniqueness
pub fn encryptBlockPayload(
    block: *blocks.Block,
    key: [AES256_KEY_SIZE]u8,
) !void {
    if (block.header.encrypted) {
        return; // Already encrypted
    }

    // Create nonce: block_id (8 bytes) + counter (4 bytes)
    var nonce = [AES_GCM_NONCE_SIZE]u8 = undefined;
    @memcpy(&nonce[0..8], &block.header.block_id, 8);
    @memcpy(&nonce[8..12], &block.header.sequence, 4);
    // Last 4 bytes zero for now

    // Encrypt payload in-place
    const payload_len = block.header.payload_len;
    if (payload_len == 0) {
        return; // Nothing to encrypt
    }

    // Make space for authentication tag at end
    if (payload_len + AES_GCM_TAG_SIZE > blocks.PAYLOAD_SIZE) {
        return CryptoError.BufferTooSmall;
    }

    // Encrypt using AES-GCM
    // Note: In real implementation, we'd use a proper crypto library
    // This is a placeholder showing the structure
    try aes256GcmEncryptInPlace(
        &block.payload[0..payload_len],
        &key,
        &nonce,
        &block.payload[payload_len..payload_len + AES_GCM_TAG_SIZE]
    );

    // Update header
    block.header.payload_len = @intCast(payload_len + AES_GCM_TAG_SIZE);
    block.header.encrypted = true;
    block.header.flags |= @as(u32, @bitCast(@intFromEnum(blocks.BlockFlags.encrypted)));

    // Recalculate checksum of encrypted data
    block.header.checksum = blocks.crc32c(&block.payload, block.header.payload_len);
}

// Decrypt block payload using AES-256-GCM
pub fn decryptBlockPayload(
    block: *blocks.Block,
    key: [AES256_KEY_SIZE]u8,
) !void {
    if (!block.header.encrypted) {
        return; // Not encrypted
    }

    const total_len = block.header.payload_len;
    if (total_len < AES_GCM_TAG_SIZE) {
        return CryptoError.AuthenticationFailed;
    }

    const payload_len = total_len - AES_GCM_TAG_SIZE;

    // Create nonce (same as encryption)
    var nonce = [AES_GCM_NONCE_SIZE]u8 = undefined;
    @memcpy(&nonce[0..8], &block.header.block_id, 8);
    @memcpy(&nonce[8..12], &block.header.sequence, 4);

    // Decrypt in-place
    try aes256GcmDecryptInPlace(
        &block.payload[0..payload_len],
        &key,
        &nonce,
        &block.payload[payload_len..total_len]
    );

    // Update header
    block.header.payload_len = @intCast(payload_len);
    block.header.encrypted = false;
    block.header.flags &= ~@as(u32, @bitCast(@intFromEnum(blocks.BlockFlags.encrypted)));

    // Recalculate checksum of decrypted data
    block.header.checksum = blocks.crc32c(&block.payload, block.header.payload_len);
}

// ============================================================
// Journal Encryption
// ============================================================

// Journal entries need special handling because they contain
// both the operation and its inverse
pub fn encryptJournalEntry(
    entry_data: []u8,
    key: [AES256_KEY_SIZE]u8,
    entry_id: u64,
) ![]u8 {
    // Similar to block encryption but with different nonce
    var nonce = [AES_GCM_NONCE_SIZE]u8 = undefined;
    @memcpy(&nonce[0..8], &entry_id, 8);
    // Use fixed pattern for journal entries
    nonce[8] = 'J';
    nonce[9] = 'N';
    nonce[10] = 'L';
    nonce[11] = 0;

    // Allocate buffer for encrypted data + tag
    var buffer: [entry_data.len + AES_GCM_TAG_SIZE]u8 = undefined;
    @memcpy(&buffer[0..entry_data.len], entry_data);

    // Encrypt
    try aes256GcmEncryptInPlace(
        &buffer[0..entry_data.len],
        &key,
        &nonce,
        &buffer[entry_data.len..entry_data.len + AES_GCM_TAG_SIZE]
    );

    return &buffer;
}

// ============================================================
// Key Derivation
// ============================================================

// Derive encryption key from master key and block type
pub fn deriveBlockKey(
    master_key: []const u8,
    block_type: blocks.BlockType,
    block_id: u64,
) ![AES256_KEY_SIZE]u8 {
    // Use BLAKE3 for key derivation (matches vault's crypto)
    // In real implementation, use proper KDF
    var key = [AES256_KEY_SIZE]u8 = undefined;
    
    // Simple XOR-based derivation for example
    // Real implementation would use HKDF or similar
    for (0..AES256_KEY_SIZE) |i| {
        if (i < master_key.len) {
            key[i] = master_key[i] ^ @as(u8, @truncate(block_type)) ^ @as(u8, @truncate(block_id >> (i % 8)));
        } else {
            key[i] = @as(u8, @truncate(block_type)) ^ @as(u8, @truncate(block_id >> (i % 8)));
        }
    }
    
    return key;
}

// ============================================================
// Placeholder Crypto Functions
// (In real implementation, use libsodium or similar)
// ============================================================

fn aes256GcmEncryptInPlace(
    data: []u8,
    key: anytype,
    nonce: anytype,
    tag_out: []u8,
) !void {
    // This is a placeholder - real implementation would use
    // a proper crypto library like libsodium or OpenSSL
    
    // For now, just XOR with key (INSECURE - for structure only!)
    var key_bytes = @ptrCast([*]const u8, &key);
    for (0..data.len) |i| {
        data[i] ^= key_bytes[i % @intCast(key_bytes.len)];
    }
    
    // Fill tag with dummy data
    for (0..tag_out.len) |i| {
        tag_out[i] = @as(u8, @truncate(i));
    }
}

fn aes256GcmDecryptInPlace(
    data: []u8,
    key: anytype,
    nonce: anytype,
    tag: []const u8,
) !void {
    // Verify tag (dummy check)
    for (0..tag.len) |i| {
        if (tag[i] != @as(u8, @truncate(i))) {
            return CryptoError.AuthenticationFailed;
        }
    }
    
    // Decrypt (same as encrypt for XOR)
    var key_bytes = @ptrCast([*]const u8, &key);
    for (0..data.len) |i| {
        data[i] ^= key_bytes[i % @intCast(key_bytes.len)];
    }
}
