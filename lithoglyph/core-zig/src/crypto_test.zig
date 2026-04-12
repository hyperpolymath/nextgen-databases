// SPDX-License-Identifier: PMPL-1.0-or-later
// Test suite for Lithoglyph cryptography module

const std = @import("std");
const crypto = @import("crypto.zig");
const blocks = @import("blocks.zig");

test "block encryption/decryption roundtrip" {
    // Create a test block
    var block = blocks.Block.init(blocks.BlockType.document, 12345, 1);
    
    // Set some test data
    const test_data = "Hello, Svalinn Vault! This is a secret credential.";
    try block.setPayload(test_data);
    
    // Verify not encrypted initially
    try std.testing.expect(!block.isEncrypted());
    
    // Create encryption key
    const key = [crypto.AES256_KEY_SIZE]u8{
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
    };
    
    // Encrypt the block
    try block.encrypt(key);
    
    // Verify encrypted
    try std.testing.expect(block.isEncrypted());
    
    // Verify payload changed (encrypted)
    const encrypted_payload = block.getPayload();
    try std.testing.expect(!std.mem.eql(u8, test_data, encrypted_payload));
    
    // Decrypt the block
    try block.decrypt(key);
    
    // Verify decrypted
    try std.testing.expect(!block.isEncrypted());
    
    // Verify payload restored
    const decrypted_payload = block.getPayload();
    try std.testing.expect(std.mem.eql(u8, test_data, decrypted_payload));
}

test "key derivation" {
    const master_key = "master-secret-key-1234567890";
    const key1 = try blocks.Block.deriveKey(master_key, blocks.BlockType.document, 123);
    const key2 = try blocks.Block.deriveKey(master_key, blocks.BlockType.document, 123);
    
    // Same parameters should give same key
    try std.testing.expect(std.mem.eql(u8, &key1, &key2));
    
    const key3 = try blocks.Block.deriveKey(master_key, blocks.BlockType.document, 456);
    
    // Different block ID should give different key
    try std.testing.expect(!std.mem.eql(u8, &key1, &key3));
}

test "double encryption detection" {
    var block = blocks.Block.init(blocks.BlockType.document, 999, 1);
    const test_data = "test";
    try block.setPayload(test_data);
    
    const key = std.mem.zeroes([crypto.AES256_KEY_SIZE]u8);
    
    // First encryption
    try block.encrypt(key);
    try std.testing.expect(block.isEncrypted());
    
    // Second encryption should be no-op
    try block.encrypt(key);
    try std.testing.expect(block.isEncrypted());
    
    // Should still decrypt correctly
    try block.decrypt(key);
    try std.testing.expect(std.mem.eql(u8, test_data, block.getPayload()));
}
