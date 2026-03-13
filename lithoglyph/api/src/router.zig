// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - HTTP Router

const std = @import("std");

pub const Route = struct {
    method: std.http.Method,
    path: []const u8,
    handler: *const fn (
        allocator: std.mem.Allocator,
        request: *std.http.Server.Request,
        params: std.StringHashMap([]const u8),
    ) anyerror!void,
};

pub const Router = struct {
    routes: std.ArrayList(Route),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .routes = std.ArrayList(Route).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

    pub fn addRoute(self: *Router, method: std.http.Method, path: []const u8, handler: anytype) !void {
        try self.routes.append(.{
            .method = method,
            .path = path,
            .handler = handler,
        });
    }

    pub fn get(self: *Router, path: []const u8, handler: anytype) !void {
        try self.addRoute(.GET, path, handler);
    }

    pub fn post(self: *Router, path: []const u8, handler: anytype) !void {
        try self.addRoute(.POST, path, handler);
    }

    pub fn delete(self: *Router, path: []const u8, handler: anytype) !void {
        try self.addRoute(.DELETE, path, handler);
    }

    pub fn match(self: *const Router, method: std.http.Method, path: []const u8) ?MatchResult {
        for (self.routes.items) |route| {
            if (route.method == method) {
                if (matchPath(route.path, path)) |params| {
                    return .{
                        .handler = route.handler,
                        .params = params,
                    };
                }
            }
        }
        return null;
    }
};

pub const MatchResult = struct {
    handler: *const fn (
        allocator: std.mem.Allocator,
        request: *std.http.Server.Request,
        params: std.StringHashMap([]const u8),
    ) anyerror!void,
    params: std.StringHashMap([]const u8),
};

fn matchPath(pattern: []const u8, path: []const u8) ?std.StringHashMap([]const u8) {
    var params = std.StringHashMap([]const u8).init(std.heap.page_allocator);

    var pattern_iter = std.mem.splitScalar(u8, pattern, '/');
    var path_iter = std.mem.splitScalar(u8, path, '/');

    while (true) {
        const pattern_part = pattern_iter.next();
        const path_part = path_iter.next();

        if (pattern_part == null and path_part == null) {
            return params;
        }

        if (pattern_part == null or path_part == null) {
            params.deinit();
            return null;
        }

        const p = pattern_part.?;
        const v = path_part.?;

        if (p.len > 0 and p[0] == ':') {
            // Parameter
            params.put(p[1..], v) catch {
                params.deinit();
                return null;
            };
        } else if (!std.mem.eql(u8, p, v)) {
            params.deinit();
            return null;
        }
    }
}

test "path matching" {
    const router = Router.init(std.testing.allocator);
    _ = router;

    // Basic path matching
    if (matchPath("/v1/collections", "/v1/collections")) |params| {
        defer params.deinit();
        try std.testing.expectEqual(@as(usize, 0), params.count());
    } else {
        return error.TestFailed;
    }

    // Parameter extraction
    if (matchPath("/v1/collections/:name", "/v1/collections/articles")) |params| {
        defer params.deinit();
        try std.testing.expectEqualStrings("articles", params.get("name").?);
    } else {
        return error.TestFailed;
    }
}
