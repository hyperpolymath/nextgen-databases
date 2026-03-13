// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
//
// build.zig - GQL-DT FFI Build Configuration

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //Build tests
    const tests = b.addTest(.{
        .name = "gqldt-tests",
        .target = target,
        .optimize = optimize,
    });

    tests.root_module.addAnonymousImport("main", .{
        .root_source_file = b.path("src/main.zig"),
    });
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
