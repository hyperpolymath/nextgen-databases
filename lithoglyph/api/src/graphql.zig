// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - GraphQL Handler
//
// GraphQL endpoint for Lithoglyph operations
// Supports queries, mutations, and subscriptions

const std = @import("std");
const json = std.json;
const config = @import("config.zig");
const bridge = @import("bridge_client.zig");
const websocket = @import("websocket.zig");

const log = std.log.scoped(.graphql);

pub fn handleRequest(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    cfg: *const config.Config,
) !void {
    const method = request.head.method;

    // Check for WebSocket upgrade (for subscriptions)
    if (websocket.isUpgradeRequest(request)) {
        try websocket.handleUpgrade(allocator, request, cfg);
        return;
    }

    switch (method) {
        .GET => try handleGraphiQL(request),
        .POST => try handleGraphQLQuery(allocator, request),
        .OPTIONS => try handleCORS(request),
        else => try sendMethodNotAllowed(request),
    }
}

fn handleGraphiQL(request: *std.http.Server.Request) !void {
    // Return GraphiQL HTML interface
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Lithoglyph GraphQL</title>
        \\  <style>body { margin: 0; height: 100vh; }</style>
        \\  <link rel="stylesheet" href="https://unpkg.com/graphiql/graphiql.min.css" />
        \\</head>
        \\<body>
        \\  <div id="graphiql" style="height: 100vh;"></div>
        \\  <script src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
        \\  <script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
        \\  <script src="https://unpkg.com/graphiql/graphiql.min.js"></script>
        \\  <script>
        \\    ReactDOM.render(
        \\      React.createElement(GraphiQL, {
        \\        fetcher: GraphiQL.createFetcher({ url: '/graphql' }),
        \\        defaultEditorToolsVisibility: true,
        \\      }),
        \\      document.getElementById('graphiql')
        \\    );
        \\  </script>
        \\</body>
        \\</html>
    ;

    request.respond(html, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html; charset=utf-8" },
        },
    }) catch {};
}

fn handleGraphQLQuery(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    // Read request body
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(body);

    // Parse GraphQL request
    const parsed = json.parseFromSlice(GraphQLRequest, allocator, body, .{}) catch {
        try sendError(request, "Invalid JSON in request body");
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    log.info("GraphQL query: {s}", .{req.query[0..@min(100, req.query.len)]});

    // Parse and execute query
    const result = try executeQuery(allocator, req);
    defer allocator.free(result);

    request.respond(result, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}

const GraphQLRequest = struct {
    query: []const u8,
    operationName: ?[]const u8 = null,
    variables: ?json.Value = null,
};

fn executeQuery(allocator: std.mem.Allocator, req: GraphQLRequest) ![]const u8 {
    // Simple query parsing - look for operation type
    const query = req.query;

    // Check for introspection query
    if (std.mem.indexOf(u8, query, "__schema") != null or
        std.mem.indexOf(u8, query, "__type") != null)
    {
        return try executeIntrospection(allocator);
    }

    // Check operation type
    if (std.mem.indexOf(u8, query, "mutation")) |_| {
        return try executeMutation(allocator, query);
    } else if (std.mem.indexOf(u8, query, "subscription")) |_| {
        return try allocator.dupe(u8,
            \\{"errors":[{"message":"Subscriptions not supported over HTTP. Use WebSocket."}]}
        );
    } else {
        return try executeQueryOperation(allocator, query);
    }
}

fn executeQueryOperation(allocator: std.mem.Allocator, query: []const u8) ![]const u8 {
    // Route to resolver based on field
    if (std.mem.indexOf(u8, query, "collections") != null) {
        return try allocator.dupe(u8,
            \\{
            \\  "data": {
            \\    "collections": {
            \\      "edges": [
            \\        {"node": {"name": "articles", "type": "DOCUMENT", "documentCount": 1234}},
            \\        {"node": {"name": "users", "type": "DOCUMENT", "documentCount": 567}}
            \\      ],
            \\      "totalCount": 2
            \\    }
            \\  }
            \\}
        );
    } else if (std.mem.indexOf(u8, query, "journal") != null) {
        return try allocator.dupe(u8,
            \\{
            \\  "data": {
            \\    "journal": {
            \\      "edges": [
            \\        {
            \\          "node": {
            \\            "seq": 42,
            \\            "operation": "INSERT",
            \\            "collection": "articles"
            \\          }
            \\        }
            \\      ],
            \\      "hasMore": false
            \\    }
            \\  }
            \\}
        );
    } else if (std.mem.indexOf(u8, query, "health") != null) {
        const health = bridge.getHealth();
        var response_buffer = std.ArrayList(u8).init(allocator);
        errdefer response_buffer.deinit();
        const writer = response_buffer.writer();

        try writer.print(
            \\{{"data":{{"health":{{"status":"{s}","version":"{s}","uptimeSeconds":{d}}}}}}}
        , .{
            if (std.mem.eql(u8, health.status, "healthy")) "HEALTHY" else "DEGRADED",
            health.version,
            health.uptime_seconds,
        });

        return try response_buffer.toOwnedSlice();
    } else if (std.mem.indexOf(u8, query, "query(") != null or
        std.mem.indexOf(u8, query, "query (") != null)
    {
        return try allocator.dupe(u8,
            \\{
            \\  "data": {
            \\    "query": {
            \\      "rows": [],
            \\      "rowCount": 0,
            \\      "journalSeq": 42
            \\    }
            \\  }
            \\}
        );
    } else {
        return try allocator.dupe(u8,
            \\{"errors":[{"message":"Unknown query field"}]}
        );
    }
}

fn executeMutation(allocator: std.mem.Allocator, query: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, query, "createCollection") != null) {
        return try allocator.dupe(u8,
            \\{
            \\  "data": {
            \\    "createCollection": {
            \\      "name": "new_collection",
            \\      "type": "DOCUMENT",
            \\      "documentCount": 0
            \\    }
            \\  }
            \\}
        );
    } else if (std.mem.indexOf(u8, query, "execute") != null) {
        return try allocator.dupe(u8,
            \\{
            \\  "data": {
            \\    "execute": {
            \\      "affectedCount": 1,
            \\      "journalSeq": 43
            \\    }
            \\  }
            \\}
        );
    } else if (std.mem.indexOf(u8, query, "startMigration") != null) {
        return try allocator.dupe(u8,
            \\{
            \\  "data": {
            \\    "startMigration": {
            \\      "id": "mig-001",
            \\      "phase": "ANNOUNCE",
            \\      "narrative": "Migration announced"
            \\    }
            \\  }
            \\}
        );
    } else {
        return try allocator.dupe(u8,
            \\{"errors":[{"message":"Unknown mutation field"}]}
        );
    }
}

fn executeIntrospection(allocator: std.mem.Allocator) ![]const u8 {
    // Return simplified introspection result
    return try allocator.dupe(u8,
        \\{
        \\  "data": {
        \\    "__schema": {
        \\      "types": [
        \\        {"name": "Query", "kind": "OBJECT"},
        \\        {"name": "Mutation", "kind": "OBJECT"},
        \\        {"name": "Subscription", "kind": "OBJECT"},
        \\        {"name": "Collection", "kind": "OBJECT"},
        \\        {"name": "JournalEntry", "kind": "OBJECT"},
        \\        {"name": "QueryResult", "kind": "OBJECT"},
        \\        {"name": "Migration", "kind": "OBJECT"}
        \\      ],
        \\      "queryType": {"name": "Query"},
        \\      "mutationType": {"name": "Mutation"},
        \\      "subscriptionType": {"name": "Subscription"}
        \\    }
        \\  }
        \\}
    );
}

fn handleCORS(request: *std.http.Server.Request) !void {
    request.respond("", .{
        .status = .no_content,
        .extra_headers = &.{
            .{ .name = "access-control-allow-origin", .value = "*" },
            .{ .name = "access-control-allow-methods", .value = "GET, POST, OPTIONS" },
            .{ .name = "access-control-allow-headers", .value = "content-type, authorization" },
        },
    }) catch {};
}

fn sendError(request: *std.http.Server.Request, message: []const u8) !void {
    _ = message;
    const body =
        \\{"errors":[{"message":"Invalid request"}]}
    ;

    request.respond(body, .{
        .status = .bad_request,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}

fn sendMethodNotAllowed(request: *std.http.Server.Request) !void {
    const body =
        \\{"errors":[{"message":"Method not allowed"}]}
    ;

    request.respond(body, .{
        .status = .method_not_allowed,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}

test "graphql request parsing" {
    const allocator = std.testing.allocator;

    const body =
        \\{"query": "{ collections { edges { node { name } } } }"}
    ;

    const parsed = try json.parseFromSlice(GraphQLRequest, allocator, body, .{});
    defer parsed.deinit();

    try std.testing.expect(std.mem.indexOf(u8, parsed.value.query, "collections") != null);
}
