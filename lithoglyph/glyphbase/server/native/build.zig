// SPDX-License-Identifier: PMPL-1.0-or-later
// Build configuration for Lith NIF

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Find Erlang include directory
    const erl_include = blk: {
        // Try to get from environment
        if (std.process.getEnvVarOwned(b.allocator, "ERL_INCLUDE_PATH")) |path| {
            break :blk path;
        } else |_| {}

        // Try to find via erl command
        const result = std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ "erl", "-noshell", "-eval", "io:format(\"~s\", [code:root_dir()])", "-s", "init", "stop" },
        }) catch {
            @panic("Failed to find Erlang installation. Set ERL_INCLUDE_PATH.");
        };

        const root_dir = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
        break :blk b.fmt("{s}/usr/include", .{root_dir});
    };

    // Build the NIF shared library
    const lib = b.addSharedLibrary(.{
        .name = "lith_nif",
        .root_source_file = b.path("src/lith_nif.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add Erlang NIF headers
    lib.addIncludePath(.{ .cwd_relative = erl_include });

    // Link against Lith
    // In production, this would link against liblith.so
    // For now, we'll add a stub or expect Lith to be linked separately
    if (b.option([]const u8, "lith-path", "Path to Lith library")) |lith_path| {
        lib.addLibraryPath(.{ .cwd_relative = lith_path });
        lib.linkSystemLibrary("lith");
    }

    // Link libc for system calls
    lib.linkLibC();

    // Install to priv directory
    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "../priv" } },
    });

    b.getInstallStep().dependOn(&install.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lith_nif.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.addIncludePath(.{ .cwd_relative = erl_include });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
