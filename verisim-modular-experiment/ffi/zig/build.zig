// SPDX-License-Identifier: PMPL-1.0-or-later
// build.zig — Zig build script for the verisim CLI (Zig 0.15 API).
//
// Produces a single binary: zig-out/bin/verisim
// The binary spawns a Julia child process running src/vcl_server.jl and
// communicates with it over stdio using the A2ML protocol defined in
// src/Abi/VCLProtocol.idr.
//
// Build:
//   zig build                          # debug build
//   zig build -Doptimize=ReleaseSafe   # release with safety checks
//
// Test:
//   zig build test                     # unit tests embedded in verisim_cli.zig

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "verisim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/verisim_cli.zig"),
            .target           = target,
            .optimize         = optimize,
        }),
    });

    b.installArtifact(exe);

    // `zig build run -- <args>` passes args through to the binary.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the verisim CLI");
    run_step.dependOn(&run_cmd.step);

    // `zig build test` runs the unit tests embedded in verisim_cli.zig.
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/verisim_cli.zig"),
            .target           = target,
            .optimize         = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
