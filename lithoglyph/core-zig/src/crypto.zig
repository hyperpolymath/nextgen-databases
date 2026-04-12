// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph Cryptography Module
//
// Provides AES-256-GCM encryption for block payloads
// Designed to integrate with Svalinn Vault's existing crypto system
//
// NOTE: All crypto functions below are PLACEHOLDERS for structure only.
// Real implementation must use libsodium or std.crypto.aead.aes_gcm.

const std = @import("std");
const builtin = @import("builtin");
const blocks = @import("blocks.zig");

// ============================================================
// Constants
// ============================================================

pub const AES256_KEY_SIZE: usize = 32; // 256 bits
pub const AES_GCM_NONCE_SIZE: usize = 12; // 96 bits for GCM
pub const AES_GCM_TAG_SIZE: usize = 16; // 128 bits authentication tag

// Encrypted flag bit in BlockHeader.flags
const ENCRYPTED_FLAG: u32 = 0x02; // bit 1 of BlockFlags

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
    if ((block.header.flags & ENCRYPTED_FLAG) != 0) {
        return; // Already encrypted
    }

    // Create nonce: block_id (8 bytes) + lower 4 bytes of sequence
    var nonce: [AES_GCM_NONCE_SIZE]u8 = undefined;
    std.mem.writeInt(u64, nonce[0..8], block.header.block_id, .little);
    std.mem.writeInt(u32, nonce[8..12], @truncate(block.header.sequence), .little);

    // Encrypt payload in-place
    const payload_len = block.header.payload_len;
    if (payload_len == 0) {
        return; // Nothing to encrypt
    }

    // Make space for authentication tag at end
    if (payload_len + AES_GCM_TAG_SIZE > blocks.PAYLOAD_SIZE) {
        return CryptoError.BufferTooSmall;
    }

    try aes256GcmEncryptInPlace(
        block.payload[0..payload_len],
        &key,
        &nonce,
        block.payload[payload_len .. payload_len + AES_GCM_TAG_SIZE],
    );

    // Update header
    block.header.payload_len = @intCast(payload_len + AES_GCM_TAG_SIZE);
    block.header.flags |= ENCRYPTED_FLAG;

    // Recalculate checksum of encrypted data
    block.header.checksum = blocks.crc32c(&block.payload, block.header.payload_len);
}

// Decrypt block payload using AES-256-GCM
pub fn decryptBlockPayload(
    block: *blocks.Block,
    key: [AES256_KEY_SIZE]u8,
) !void {
    if ((block.header.flags & ENCRYPTED_FLAG) == 0) {
        return; // Not encrypted
    }

    const total_len = block.header.payload_len;
    if (total_len < AES_GCM_TAG_SIZE) {
        return CryptoError.AuthenticationFailed;
    }

    const payload_len = total_len - AES_GCM_TAG_SIZE;

    // Create nonce (same as encryption)
    var nonce: [AES_GCM_NONCE_SIZE]u8 = undefined;
    std.mem.writeInt(u64, nonce[0..8], block.header.block_id, .little);
    std.mem.writeInt(u32, nonce[8..12], @truncate(block.header.sequence), .little);

    try aes256GcmDecryptInPlace(
        block.payload[0..payload_len],
        &key,
        &nonce,
        block.payload[payload_len..total_len],
    );

    // Update header
    block.header.payload_len = @intCast(payload_len);
    block.header.flags &= ~ENCRYPTED_FLAG;

    // Recalculate checksum of decrypted data
    block.header.checksum = blocks.crc32c(&block.payload, block.header.payload_len);
}

// ============================================================
// Journal Encryption
// ============================================================

// Journal entries need special handling because they contain
// both the operation and its inverse.
// NOTE: caller owns `out_buf` and must ensure it is at least
// `entry_data.len + AES_GCM_TAG_SIZE` bytes long.
pub fn encryptJournalEntry(
    entry_data: []const u8,
    key: [AES256_KEY_SIZE]u8,
    entry_id: u64,
    out_buf: []u8,
) !usize {
    const needed = entry_data.len + AES_GCM_TAG_SIZE;
    if (out_buf.len < needed) return CryptoError.BufferTooSmall;

    // Build nonce: entry_id (8 bytes) + "JNL\0" marker
    var nonce: [AES_GCM_NONCE_SIZE]u8 = undefined;
    std.mem.writeInt(u64, nonce[0..8], entry_id, .little);
    nonce[8] = 'J';
    nonce[9] = 'N';
    nonce[10] = 'L';
    nonce[11] = 0;

    @memcpy(out_buf[0..entry_data.len], entry_data);

    try aes256GcmEncryptInPlace(
        out_buf[0..entry_data.len],
        &key,
        &nonce,
        out_buf[entry_data.len..needed],
    );

    return needed;
}

// ============================================================
// Key Derivation
// ============================================================

// Derive encryption key from master key and block type.
// PLACEHOLDER — real implementation must use HKDF or BLAKE3-KDF.
pub fn deriveBlockKey(
    master_key: []const u8,
    block_type: blocks.BlockType,
    block_id: u64,
) ![AES256_KEY_SIZE]u8 {
    var key: [AES256_KEY_SIZE]u8 = undefined;
    const bt: u8 = @truncate(@intFromEnum(block_type));
    for (0..AES256_KEY_SIZE) |i| {
        const shift: u6 = @intCast(i % 8);
        const id_byte: u8 = @truncate(block_id >> shift);
        key[i] = if (i < master_key.len) master_key[i] ^ bt ^ id_byte else bt ^ id_byte;
    }
    return key;
}

// ============================================================
// Placeholder Crypto Primitives
// (Replace with libsodium / std.crypto.aead.aes_gcm in production)
// ============================================================

fn aes256GcmEncryptInPlace(
    data: []u8,
    key: *const [AES256_KEY_SIZE]u8,
    nonce: *const [AES_GCM_NONCE_SIZE]u8,
    tag_out: []u8,
) !void {
    _ = nonce; // placeholder — nonce not used in XOR stub
    // INSECURE placeholder: XOR with key bytes only
    for (data, 0..) |*byte, i| {
        byte.* ^= key[i % AES256_KEY_SIZE];
    }
    // Fill tag with dummy pattern
    for (tag_out, 0..) |*b, i| {
        b.* = @truncate(i);
    }
}

fn aes256GcmDecryptInPlace(
    data: []u8,
    key: *const [AES256_KEY_SIZE]u8,
    nonce: *const [AES_GCM_NONCE_SIZE]u8,
    tag: []const u8,
) !void {
    _ = nonce; // placeholder
    // Verify dummy tag
    for (tag, 0..) |b, i| {
        if (b != @as(u8, @truncate(i))) return CryptoError.AuthenticationFailed;
    }
    // INSECURE placeholder: XOR is its own inverse
    for (data, 0..) |*byte, i| {
        byte.* ^= key[i % AES256_KEY_SIZE];
    }
}
