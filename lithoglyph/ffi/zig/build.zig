// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// build.zig - Lith FFI Build Configuration (Zig 0.15.2+)
//
// This build links the FFI layer (ffi/zig/) against the core storage engine
// (core-zig/) so that bridge.zig can delegate to the real implementation.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ================================================================
    // Core-zig module (the real storage engine)
    // ================================================================

    // Create a module from core-zig/src/bridge.zig so the FFI bridge
    // can import it as "core_bridge"
    const core_bridge_mod = b.createModule(.{
        .root_source_file = b.path("../../core-zig/src/bridge.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ================================================================
    // FFI shared library
    // ================================================================

    const lib = b.addLibrary(.{
        .name = "lith",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bridge.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core_bridge", .module = core_bridge_mod },
            },
        }),
        .linkage = .dynamic,
        .version = .{ .major = 0, .minor = 6, .patch = 5 },
    });

    // Export C symbols for FFI
    lib.linkLibC();

    b.installArtifact(lib);

    // ================================================================
    // FFI static library (for embedding)
    // ================================================================

    const static_lib = b.addLibrary(.{
        .name = "lith",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bridge.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core_bridge", .module = core_bridge_mod },
            },
        }),
        .linkage = .static,
    });

    b.installArtifact(static_lib);

    // ================================================================
    // Unit tests for bridge.zig (with core-zig module available)
    // ================================================================

    const bridge_tests = b.addTest(.{
        .name = "bridge-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bridge.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core_bridge", .module = core_bridge_mod },
            },
        }),
    });

    const run_bridge_tests = b.addRunArtifact(bridge_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_bridge_tests.step);

    // ================================================================
    // Seam tests (test integration boundaries)
    // ================================================================

    const seam_step = b.step("seam", "Run seam tests (integration boundaries)");
    seam_step.dependOn(&run_bridge_tests.step);
}
