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
    const root_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/lith_nif.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "lith_nif",
        .root_module = root_module,
        .linkage = .dynamic,
    });

    // Add Erlang NIF headers
    lib.root_module.addIncludePath(.{ .cwd_relative = erl_include });

    // Add C helper file for NIF inline functions
    lib.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/nif_helpers.c" },
        .flags = &.{"-std=c11"},
    });

    // Link against Lith
    // In production, this would link against liblith.so
    // For now, we'll add a stub or expect Lith to be linked separately
    if (b.option([]const u8, "lith-path", "Path to Lith library")) |lith_path| {
        lib.root_module.addLibraryPath(.{ .cwd_relative = lith_path });
        lib.root_module.linkSystemLibrary("lith", .{});
    }

    // Install to priv directory
    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "../priv" } },
    });

    b.getInstallStep().dependOn(&install.step);

    // Tests
    const test_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/lith_nif.zig" },
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    unit_tests.root_module.addIncludePath(.{ .cwd_relative = erl_include });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
