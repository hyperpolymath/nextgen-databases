// SPDX-License-Identifier: PMPL-1.0-or-later
// Form.Bridge - Build Configuration (Zig 0.15.2+)

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main static library
    const lib = b.addLibrary(.{
        .name = "lith_bridge",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bridge.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    // Also build shared library for FFI
    const shared_lib = b.addLibrary(.{
        .name = "lith_bridge",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bridge.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    // Install artifacts
    b.installArtifact(lib);
    b.installArtifact(shared_lib);

    // Unit tests for bridge
    const bridge_tests = b.addTest(.{
        .name = "bridge-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bridge.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_bridge_tests = b.addRunArtifact(bridge_tests);

    // Unit tests for blocks
    const blocks_tests = b.addTest(.{
        .name = "blocks-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/blocks.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Unit tests for crypto
    const crypto_tests = b.addTest(.{
        .name = "crypto-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/crypto_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_blocks_tests = b.addRunArtifact(blocks_tests);
    const run_crypto_tests = b.addRunArtifact(crypto_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_bridge_tests.step);
    test_step.dependOn(&run_blocks_tests.step);
    test_step.dependOn(&run_crypto_tests.step);
}
