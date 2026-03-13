#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Lithoglyph Execution Test
#
# Verifies that the block storage layer works correctly end-to-end.
# Tests database creation, block allocation, writes, reads, and journal.

set -euo pipefail

echo "=== Lithoglyph Execution Test ==="
echo ""

# Create test program
cat > test_execution.zig << 'EOF'
const std = @import("std");
const blocks = @import("src/blocks.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path = "execution_test.lgh";
    defer std.fs.cwd().deleteFile(path) catch {};

    std.debug.print("Creating database: {s}\n", .{path});
    const storage = try blocks.BlockStorage.open(allocator, path);
    defer storage.deinit();

    std.debug.print("✅ Database created\n", .{});
    std.debug.print("   Superblock version: {d}\n", .{storage.superblock.version});
    std.debug.print("   Block count: {d}\n", .{storage.superblock.block_count});

    // Allocate document blocks
    std.debug.print("\nAllocating 5 document blocks...\n", .{});
    var i: usize = 0;
    var block_ids: [5]u64 = undefined;
    while (i < 5) : (i += 1) {
        const block_id = try storage.allocateBlock(.document);
        block_ids[i] = block_id;

        var block = try storage.readBlock(block_id);

        var buf: [100]u8 = undefined;
        const content = try std.fmt.bufPrint(&buf, "Document {d} content", .{i + 1});
        try block.setPayload(content);

        try storage.writeBlock(block_id, &block);
        std.debug.print("   Block {d}: {s}\n", .{block_id, content});
    }

    std.debug.print("✅ Documents written\n", .{});

    // Read blocks back
    std.debug.print("\nReading blocks back...\n", .{});
    i = 0;
    while (i < 5) : (i += 1) {
        const block = try storage.readBlock(block_ids[i]);
        const payload = block.getPayload();
        std.debug.print("   Block {d}: {s}\n", .{block_ids[i], payload});
    }

    std.debug.print("✅ Documents read\n", .{});

    // Append journal entries
    std.debug.print("\nAppending journal entries...\n", .{});
    const j1 = try storage.appendJournal("Operation: created documents");
    const j2 = try storage.appendJournal("Operation: verified reads");
    std.debug.print("   Journal entry 1: block {d}\n", .{j1});
    std.debug.print("   Journal entry 2: block {d}\n", .{j2});

    // Verify journal linkage
    const j2_block = try storage.readBlock(j2);
    if (j2_block.header.prev_block_id == j1) {
        std.debug.print("✅ Journal entries linked correctly\n", .{});
    } else {
        std.debug.print("❌ Journal linkage broken\n", .{});
        return error.JournalLinkageError;
    }

    // Final stats
    std.debug.print("\nFinal database state:\n", .{});
    std.debug.print("   Total blocks: {d}\n", .{storage.superblock.block_count});
    std.debug.print("   Journal head: {d}\n", .{storage.superblock.journal_head});
    std.debug.print("   Journal tail: {d}\n", .{storage.superblock.journal_tail});

    std.debug.print("\n✅ All execution tests passed!\n", .{});
}
EOF

echo "=== Compiling test program ==="
zig build-exe test_execution.zig -O ReleaseSafe
if [ ! -f "test_execution" ] && [ ! -f "test_execution.exe" ]; then
    echo "❌ Compilation failed"
    exit 1
fi
echo "✅ Test program compiled"
echo ""

echo "=== Running execution test ==="
if [ -f "test_execution" ]; then
    ./test_execution
    EXIT_CODE=$?
elif [ -f "test_execution.exe" ]; then
    ./test_execution.exe
    EXIT_CODE=$?
else
    echo "❌ Test executable not found"
    exit 1
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "✅ Execution test passed!"
    echo "========================================="
else
    echo ""
    echo "❌ Execution test failed with code $EXIT_CODE"
    exit 1
fi

# Cleanup
echo ""
echo "=== Cleanup ==="
rm -f test_execution test_execution.exe test_execution.zig
rm -f test_execution.o test_execution.obj
rm -f execution_test.lgh
rm -f *.lgh
echo "✅ Cleanup complete"
