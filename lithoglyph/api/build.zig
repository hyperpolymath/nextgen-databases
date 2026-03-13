// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - Build Configuration

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main server executable
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "lithoglyph-server",
        .root_module = exe_mod,
    });

    // Link libc for networking
    exe.linkLibC();

    // Link bridge library (from core-zig build output)
    exe.addLibraryPath(b.path("../core-zig/zig-out/lib"));
    exe.linkSystemLibrary("lith_bridge");

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Lith API server");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Module tests
    const modules = [_][]const u8{
        "src/config.zig",
        "src/router.zig",
        "src/rest.zig",
        "src/grpc.zig",
        "src/graphql.zig",
        "src/metrics.zig",
        "src/auth.zig",
        "src/bridge_client.zig",
        "src/websocket.zig",
        "src/integration_tests.zig",
    };

    for (modules) |mod| {
        const mod_mod = b.createModule(.{
            .root_source_file = b.path(mod),
            .target = target,
            .optimize = optimize,
        });
        const mod_test = b.addTest(.{
            .root_module = mod_mod,
        });
        const run_mod_test = b.addRunArtifact(mod_test);
        test_step.dependOn(&run_mod_test.step);
    }
}
