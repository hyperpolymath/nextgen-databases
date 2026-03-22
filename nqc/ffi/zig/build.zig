// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// build.zig — Build configuration for the NQC Zig FFI library (Zig 0.15.2).

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Library module for import ---
    const nqc_mod = b.addModule("nqc_ffi", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Unit tests ---
    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addTest(.{
        .root_module = unit_test_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    // --- Integration tests ---
    const integration_test_mod = b.createModule(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_test_mod.addImport("nqc_ffi", nqc_mod);
    const integration_tests = b.addTest(.{
        .root_module = integration_test_mod,
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    // --- Test step ---
    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
}
