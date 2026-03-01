// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// build.zig — Zig build configuration for typeql-experimental FFI bridge
//
// This is a skeletal build file for the ABI/FFI standard. The bridge
// will eventually expose the Idris2 type checker to non-Idris2 consumers
// via C-compatible FFI (Zig implementing the C ABI defined by Idris2).

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module — the FFI bridge
    const mod = b.addModule("typeql_bridge", .{
        .root_source_file = b.path("src/bridge.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
