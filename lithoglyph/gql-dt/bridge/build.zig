// SPDX-License-Identifier: PMPL-1.0
// SPDX-FileCopyrightText: 2025 hyperpolymath
//
// build.zig - Build configuration for Lith FFI bridge
//
// Builds a static library that can be linked with Lean 4.
// Pure Zig, exports C ABI functions.
// Compatible with Zig 0.16-dev API.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create module for the library with PIC enabled for linking with Lean
    const fdb_module = b.createModule(.{
        .root_source_file = b.path("fdb_root.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true, // Required for linking with Lean's PIE executable
    });

    // Static library for linking with Lean 4
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "fdb_bridge",
        .root_module = fdb_module,
    });

    // Install the library
    b.installArtifact(lib);

    // Create module for shared library
    const fdb_shared_module = b.createModule(.{
        .root_source_file = b.path("fdb_root.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });

    // Shared library option (for dynamic linking)
    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "fdb_bridge",
        .root_module = fdb_shared_module,
    });

    const shared_step = b.step("shared", "Build shared library");
    shared_step.dependOn(&b.addInstallArtifact(shared_lib, .{}).step);

    // Unit tests - create module first
    const test_module = b.createModule(.{
        .root_source_file = b.path("fdb_root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Type tests - create module first
    const type_test_module = b.createModule(.{
        .root_source_file = b.path("fdb_types.zig"),
        .target = target,
        .optimize = optimize,
    });

    const type_tests = b.addTest(.{
        .root_module = type_test_module,
    });

    const run_type_tests = b.addRunArtifact(type_tests);
    test_step.dependOn(&run_type_tests.step);
}
