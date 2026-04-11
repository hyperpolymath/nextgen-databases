// SPDX-License-Identifier: PMPL-1.0-or-later
// verisim_cli.zig — Verisim VCL query CLI (Zig 0.15).
//
// Contract (Abi.VCLProtocol):
//   stdin  : one VCL query per line
//   stdout : one A2ML [vcl-verdict] block per query, blank-line delimited
//
// Architecture:
//   This binary spawns a Julia child process running src/vcl_server.jl and
//   pipes queries to it, forwarding verdicts back to its own stdout.
//   The OS process boundary provides dependability isolation: a crash or
//   hang in the Julia layer cannot corrupt this process.
//
// Environment:
//   VERISIM_PACKAGE_PATH   Path to the verisim-modular-experiment package.
//                          Default: four dirname levels up from the binary
//                          (ffi/zig/zig-out/bin/verisim → package root).
//
// Usage:
//   echo "PROOF INTEGRITY FOR abababababababababababababababababab" | verisim
//   printf 'PROOF INTEGRITY FOR %s\n' abababababababababababababababababab | verisim

const std = @import("std");

// -------------------------------------------------------------------------
// § 1  Package path resolution
// -------------------------------------------------------------------------

/// Resolve the package path from the environment variable or the binary's
/// location. The caller owns the returned slice.
fn resolve_package_path(allocator: std.mem.Allocator) ![]const u8 {
    // Prefer the explicit environment variable.
    if (std.process.getEnvVarOwned(allocator, "VERISIM_PACKAGE_PATH")) |p| {
        return p;
    } else |_| {}

    // Fall back: binary at <pkg>/ffi/zig/zig-out/bin/verisim.
    // Strip four path components to reach the package root.
    const self_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(self_path);

    var current: []const u8 = self_path;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        current = std.fs.path.dirname(current) orelse
            return error.CannotResolvePackagePath;
    }
    return allocator.dupe(u8, current);
}

// -------------------------------------------------------------------------
// § 2  A2ML verdict parser
// -------------------------------------------------------------------------

/// Verdict as parsed from one [vcl-verdict] A2ML block.
const Verdict = struct {
    /// Owned by the caller's allocator.
    result: []const u8,
    /// Present for ParseError / RuntimeError; owned by the caller.
    err: ?[]const u8,

    fn deinit(self: Verdict, allocator: std.mem.Allocator) void {
        allocator.free(self.result);
        if (self.err) |e| allocator.free(e);
    }
};

/// Parse one A2ML [vcl-verdict] block from `reader` (a GenericReader).
/// Returns null when EOF is reached before any verdict content.
/// `result` and `err` are allocated with `allocator`.
fn read_verdict(
    reader: anytype,
    allocator: std.mem.Allocator,
) !?Verdict {
    var result_val: ?[]const u8 = null;
    var error_val:  ?[]const u8 = null;
    var saw_header  = false;
    var saw_content = false;

    errdefer {
        if (result_val) |r| allocator.free(r);
        if (error_val)  |e| allocator.free(e);
    }

    while (true) {
        const line = reader.readUntilDelimiterAlloc(allocator, '\n', 65536) catch |e| switch (e) {
            error.EndOfStream => {
                if (!saw_content) return null;
                break;
            },
            else => return e,
        };
        defer allocator.free(line);

        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0) {
            if (saw_content) break;   // blank line = record separator
            continue;
        }

        saw_content = true;

        if (std.mem.eql(u8, trimmed, "[vcl-verdict]")) {
            saw_header = true;
            continue;
        }
        if (!saw_header) continue;

        // Parse:  key = "value"
        const eq_needle = " = \"";
        if (std.mem.indexOf(u8, trimmed, eq_needle)) |eq| {
            const key       = trimmed[0..eq];
            const val_start = eq + eq_needle.len;
            // Strip the trailing " if present.
            const val_end   = if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '"')
                                  trimmed.len - 1
                              else
                                  trimmed.len;

            if (val_start > val_end) continue;   // malformed — skip
            const raw_val = trimmed[val_start..val_end];

            if (std.mem.eql(u8, key, "result")) {
                if (result_val) |old| allocator.free(old);
                result_val = try allocator.dupe(u8, raw_val);
            } else if (std.mem.eql(u8, key, "error")) {
                if (error_val) |old| allocator.free(old);
                error_val = try allocator.dupe(u8, raw_val);
            }
            // "query" key is echoed in output but not stored here.
        }
    }

    const result = result_val orelse return error.MissingResultField;
    return Verdict{ .result = result, .err = error_val };
}

// -------------------------------------------------------------------------
// § 3  Main loop
// -------------------------------------------------------------------------

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stderr = std.fs.File.stderr().deprecatedWriter();

    // Locate the Julia package.
    const pkg_path = resolve_package_path(allocator) catch |e| {
        try stderr.print("verisim: cannot resolve package path: {}\n", .{e});
        std.process.exit(1);
    };
    defer allocator.free(pkg_path);

    // Build argv: julia --project=<pkg> <pkg>/src/vcl_server.jl
    const server_script = try std.fs.path.join(allocator, &.{ pkg_path, "src", "vcl_server.jl" });
    defer allocator.free(server_script);

    const project_flag = try std.fmt.allocPrint(allocator, "--project={s}", .{pkg_path});
    defer allocator.free(project_flag);

    const argv = [_][]const u8{ "julia", project_flag, server_script };

    // Spawn Julia.
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior  = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;   // Julia startup messages + tracebacks visible

    child.spawn() catch |e| {
        try stderr.print("verisim: failed to spawn julia: {}\n", .{e});
        std.process.exit(1);
    };

    const child_stdin  = child.stdin  orelse {
        try stderr.print("verisim: child stdin not available\n", .{});
        std.process.exit(1);
    };
    const child_stdout = child.stdout orelse {
        try stderr.print("verisim: child stdout not available\n", .{});
        std.process.exit(1);
    };

    // Wire up IO using the GenericReader/Writer (deprecated API, still correct).
    const our_stdin_r  = std.fs.File.stdin().deprecatedReader();
    const our_stdout_w = std.fs.File.stdout().deprecatedWriter();
    const child_in_w   = child_stdin.deprecatedWriter();
    const child_out_r  = child_stdout.deprecatedReader();

    // One-at-a-time query → verdict loop.
    while (true) {
        const raw = our_stdin_r.readUntilDelimiterAlloc(allocator, '\n', 65536) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        defer allocator.free(raw);

        const query = std.mem.trim(u8, raw, " \t\r");
        if (query.len == 0) continue;

        // Forward query to Julia.
        child_in_w.writeAll(query) catch break;
        child_in_w.writeByte('\n')  catch break;

        // Read verdict block.
        const maybe_verdict = read_verdict(child_out_r, allocator) catch |e| {
            try stderr.print("verisim: verdict read error: {}\n", .{e});
            break;
        };
        const verdict = maybe_verdict orelse break;
        defer verdict.deinit(allocator);

        // Emit A2ML to our stdout.
        try our_stdout_w.print("[vcl-verdict]\n", .{});
        try our_stdout_w.print("query = \"{s}\"\n", .{query});
        try our_stdout_w.print("result = \"{s}\"\n", .{verdict.result});
        if (verdict.err) |e| try our_stdout_w.print("error = \"{s}\"\n", .{e});
        try our_stdout_w.print("\n", .{});
    }

    // Shut down Julia.
    child_stdin.close();
    _ = child.wait() catch {};
}

// -------------------------------------------------------------------------
// § 4  Unit tests
// -------------------------------------------------------------------------

test "read_verdict: Pass" {
    const allocator = std.testing.allocator;
    const input =
        "[vcl-verdict]\n" ++
        "query = \"PROOF INTEGRITY FOR abcd\"\n" ++
        "result = \"Pass\"\n" ++
        "\n";

    var stream = std.io.fixedBufferStream(input);
    const maybe = try read_verdict(stream.reader(), allocator);
    const v = maybe orelse return error.ExpectedVerdict;
    defer v.deinit(allocator);

    try std.testing.expectEqualStrings("Pass", v.result);
    try std.testing.expect(v.err == null);
}

test "read_verdict: ParseError with error field" {
    const allocator = std.testing.allocator;
    const input =
        "[vcl-verdict]\n" ++
        "query = \"GARBAGE\"\n" ++
        "result = \"ParseError\"\n" ++
        "error = \"unexpected token\"\n" ++
        "\n";

    var stream = std.io.fixedBufferStream(input);
    const maybe = try read_verdict(stream.reader(), allocator);
    const v = maybe orelse return error.ExpectedVerdict;
    defer v.deinit(allocator);

    try std.testing.expectEqualStrings("ParseError", v.result);
    try std.testing.expectEqualStrings("unexpected token", v.err.?);
}

test "read_verdict: empty input returns null" {
    const allocator = std.testing.allocator;
    var stream = std.io.fixedBufferStream("");
    const maybe = try read_verdict(stream.reader(), allocator);
    try std.testing.expect(maybe == null);
}

test "read_verdict: multiple verdicts parsed sequentially" {
    const allocator = std.testing.allocator;
    const input =
        "[vcl-verdict]\n" ++
        "query = \"Q1\"\n" ++
        "result = \"Pass\"\n" ++
        "\n" ++
        "[vcl-verdict]\n" ++
        "query = \"Q2\"\n" ++
        "result = \"Fail\"\n" ++
        "\n";

    var stream = std.io.fixedBufferStream(input);
    const r = stream.reader();

    const v1 = (try read_verdict(r, allocator)).?;
    defer v1.deinit(allocator);
    try std.testing.expectEqualStrings("Pass", v1.result);

    const v2 = (try read_verdict(r, allocator)).?;
    defer v2.deinit(allocator);
    try std.testing.expectEqualStrings("Fail", v2.result);

    const v3 = try read_verdict(r, allocator);
    try std.testing.expect(v3 == null);
}
