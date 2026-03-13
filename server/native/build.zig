// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Build configuration for Lithoglyph NIF (Gleam/BEAM)
//
// Links the NIF against core-zig via Zig module import (same pattern as ffi/zig/).
// The NIF source imports core_bridge to access real Lith functions and types.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ================================================================
    // Core-zig module (the real storage engine)
    // ================================================================

    const core_bridge_mod = b.createModule(.{
        .root_source_file = b.path("../../../core-zig/src/bridge.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ================================================================
    // Erlang NIF headers
    // ================================================================

    const erl_include = blk: {
        if (std.process.getEnvVarOwned(b.allocator, "ERL_INCLUDE_PATH")) |path| {
            break :blk path;
        } else |_| {}

        const result = std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ "erl", "-noshell", "-eval", "io:format(\"~s\", [code:root_dir()])", "-s", "init", "stop" },
        }) catch {
            @panic("Failed to find Erlang installation. Set ERL_INCLUDE_PATH.");
        };

        const root_dir = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
        break :blk b.fmt("{s}/usr/include", .{root_dir});
    };

    // ================================================================
    // NIF shared library (links core-zig via module import)
    // ================================================================

    const lib = b.addLibrary(.{
        .name = "lithoglyph_nif",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lithoglyph_nif.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core_bridge", .module = core_bridge_mod },
            },
        }),
        .linkage = .dynamic,
    });

    // Erlang NIF headers
    lib.root_module.addIncludePath(.{ .cwd_relative = erl_include });

    // libc for system calls
    lib.linkLibC();

    // Install to priv/ for Gleam/BEAM to find
    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "../priv" } },
    });

    b.getInstallStep().dependOn(&install.step);

    // ================================================================
    // Tests (with core-zig module available)
    // ================================================================

    const unit_tests = b.addTest(.{
        .name = "nif-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lithoglyph_nif.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core_bridge", .module = core_bridge_mod },
            },
        }),
    });

    unit_tests.root_module.addIncludePath(.{ .cwd_relative = erl_include });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
