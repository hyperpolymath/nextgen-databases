// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// build.zig - GQL-DT FFI Build Configuration (Zig 0.15.2+)
//
// Builds the libgqldt shared library (C ABI) and unit tests.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static library (libgqldt.a)
    const static_lib = b.addLibrary(.{
        .name = "gqldt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    b.installArtifact(static_lib);

    // Shared library (libgqldt.so / libgqldt.dylib)
    const shared_lib = b.addLibrary(.{
        .name = "gqldt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    b.installArtifact(shared_lib);

    // Unit tests (from main.zig internal tests)
    const unit_tests = b.addTest(.{
        .name = "gqldt-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
