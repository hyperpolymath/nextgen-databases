// SPDX-License-Identifier: PMPL-1.0-or-later
// Build script for Lithoglyph Zig FFI NIF library (Zig 0.15.2+)

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Find Erlang NIF headers
    const erts_include = std.process.getEnvVarOwned(
        b.allocator,
        "ERTS_INCLUDE_DIR"
    ) catch blk: {
        // Try to find via asdf
        const home = std.process.getEnvVarOwned(b.allocator, "HOME") catch "/home/hyper";
        break :blk b.pathJoin(&.{home, ".asdf/installs/erlang/28.3.1/erts-16.2/include"});
    };

    // Build shared library for Erlang NIF
    const lib = b.addLibrary(.{
        .name = "lithoglyph_nif",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    lib.addIncludePath(.{ .cwd_relative = erts_include });

    // Note: Lithoglyph functions are declared as extern in main.zig
    // They will be resolved at runtime when the NIF loads
    // To link statically, uncomment:
    // const lithoglyph_path = ...;
    // lib.addLibraryPath(.{ .cwd_relative = lithoglyph_path ++ "/zig-out/lib" });
    // lib.linkSystemLibrary("lithoglyph");

    // Install to priv directory for Erlang to find
    const install_artifact = b.addInstallArtifact(lib, .{
        .dest_dir = .{
            .override = .{
                .custom = "../../priv",
            },
        },
    });
    b.getInstallStep().dependOn(&install_artifact.step);

    // Unit tests
    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
