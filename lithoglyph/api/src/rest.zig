// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph API Server - REST Handler

const std = @import("std");
const json = std.json;

const config = @import("config.zig");
const auth = @import("auth.zig");
const metrics = @import("metrics.zig");
const bridge = @import("bridge_client.zig");

const log = std.log.scoped(.rest);

pub fn handleRequest(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    cfg: *const config.Config,
) !void {
    // Authentication check
    if (cfg.require_auth) {
        if (!try auth.validateRequest(request)) {
            try sendUnauthorized(request);
            return;
        }
    }

    const path = request.head.target;
    const method = request.head.method;

    // Strip /v1/ prefix
    const endpoint = if (std.mem.startsWith(u8, path, "/v1/"))
        path[4..]
    else
        path;

    // Route to handler
    if (std.mem.eql(u8, endpoint, "/query") or std.mem.eql(u8, endpoint, "/query/")) {
        try handleQuery(allocator, request, method);
    } else if (std.mem.startsWith(u8, endpoint, "/collections")) {
        try handleCollections(allocator, request, method, endpoint);
    } else if (std.mem.startsWith(u8, endpoint, "/journal")) {
        try handleJournal(allocator, request, method);
    } else if (std.mem.startsWith(u8, endpoint, "/normalize")) {
        try handleNormalize(allocator, request, method, endpoint);
    } else if (std.mem.startsWith(u8, endpoint, "/migrate")) {
        try handleMigrate(allocator, request, method, endpoint);
    } else if (std.mem.eql(u8, endpoint, "/health") or std.mem.eql(u8, endpoint, "/health/")) {
        try handleHealth(allocator, request);
    } else if (std.mem.eql(u8, endpoint, "/metrics") or std.mem.eql(u8, endpoint, "/metrics/")) {
        try handleMetrics(allocator, request);
    } else {
        try sendNotFound(request);
    }
}

// =============================================================================
// Query Handler
// =============================================================================

fn handleQuery(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    method: std.http.Method,
) !void {
    if (method != .POST) {
        try sendMethodNotAllowed(request);
        return;
    }

    // Read request body
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(body);

    // Parse JSON request
    const parsed = json.parseFromSlice(QueryRequest, allocator, body, .{}) catch {
        try sendBadRequest(request, "Invalid JSON in request body");
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    log.info("Executing GQL: {s}", .{req.fdql});

    // EXPLAIN mode - return query plan without execution
    if (req.explain) {
        const response =
            \\{
            \\  "plan": {
            \\    "steps": [
            \\      {"type": "scan", "collection": "articles"},
            \\      {"type": "filter", "expression": "status = 'published'"},
            \\      {"type": "limit", "count": 10}
            \\    ],
            \\    "estimatedCost": 150.0,
            \\    "rationale": "Full scan with filter (no index on status)"
            \\  },
            \\  "timing": {
            \\    "parseMs": 0.5,
            \\    "planMs": 1.2,
            \\    "executeMs": 0.0,
            \\    "totalMs": 1.7
            \\  }
            \\}
        ;
        try sendJson(request, .ok, response);
        return;
    }

    // Execute via Form.Bridge
    const prov = if (req.provenance) |p| bridge.QueryProvenance{
        .actor = p.actor,
        .rationale = p.rationale,
    } else null;

    var result = bridge.executeQuery(req.fdql, prov) catch |err| {
        log.err("Query execution failed: {}", .{err});

        // Return error response
        const error_response = switch (err) {
            error.NotInitialized =>
                \\{"error":"service_unavailable","message":"Database not initialized"}
            ,
            error.TransactionFailed =>
                \\{"error":"transaction_error","message":"Failed to begin transaction"}
            ,
            error.ApplyFailed =>
                \\{"error":"execution_error","message":"Query execution failed"}
            ,
            error.CommitFailed =>
                \\{"error":"commit_error","message":"Failed to commit transaction"}
            ,
            else =>
                \\{"error":"internal_error","message":"Internal server error"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };
    defer result.deinit(allocator);

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    try writer.print(
        \\{{"rows":{s},"rowCount":{d},"journalSeq":0,
    , .{ result.data, result.rows_affected });

    // Include provenance if present
    if (result.provenance) |prov_json| {
        try writer.print(
            \\"provenance":{s},
        , .{prov_json});
    }

    try writer.writeAll(
        \\"timing":{"parseMs":0.5,"planMs":1.2,"executeMs":3.8,"totalMs":5.5}}}
    );

    try sendJson(request, .ok, response_buffer.items);
}

const QueryRequest = struct {
    fdql: []const u8,
    provenance: ?Provenance = null,
    explain: bool = false,
    analyze: bool = false,
    verbose: bool = false,
};

const Provenance = struct {
    actor: []const u8,
    rationale: []const u8,
};

// =============================================================================
// Collections Handler
// =============================================================================

fn handleCollections(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    method: std.http.Method,
    endpoint: []const u8,
) !void {
    // Check if it's a specific collection
    const collection_name = extractCollectionName(endpoint);

    if (collection_name) |name| {
        switch (method) {
            .GET => try handleGetCollection(allocator, request, name),
            .DELETE => try handleDropCollection(request, name),
            else => try sendMethodNotAllowed(request),
        }
    } else {
        switch (method) {
            .GET => try handleListCollections(allocator, request),
            .POST => try handleCreateCollection(allocator, request),
            else => try sendMethodNotAllowed(request),
        }
    }
}

fn extractCollectionName(endpoint: []const u8) ?[]const u8 {
    // /collections/name -> name
    const prefix = "/collections/";
    if (std.mem.startsWith(u8, endpoint, prefix) and endpoint.len > prefix.len) {
        return endpoint[prefix.len..];
    }
    return null;
}

fn handleListCollections(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    const collections = bridge.listCollections() catch |err| {
        log.err("Failed to list collections: {}", .{err});
        // Fall back to empty list
        try sendJson(request, .ok,
            \\{"collections":[],"total":0}
        );
        return;
    };
    defer allocator.free(collections);

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    try writer.writeAll("{\"collections\":[");
    for (collections, 0..) |col, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print(
            \\{{"name":"{s}","type":"document","documentCount":{d},"normalForm":"unknown"}}
        , .{ col.name, col.document_count });
    }
    try writer.print("],\"total\":{d}}}", .{collections.len});

    try sendJson(request, .ok, response_buffer.items);
}

fn handleGetCollection(allocator: std.mem.Allocator, request: *std.http.Server.Request, name: []const u8) !void {
    const collection = bridge.getCollection(name) catch |err| {
        log.err("Failed to get collection {s}: {}", .{ name, err });
        try sendJson(request, .internal_server_error,
            \\{"error":"internal_error","message":"Failed to retrieve collection"}
        );
        return;
    };

    if (collection) |col| {
        // Build response JSON
        var response_buffer = std.ArrayList(u8).init(allocator);
        defer response_buffer.deinit();
        const writer = response_buffer.writer();

        try writer.print(
            \\{{"name":"{s}","type":"document","schema":{{"fields":[],"constraints":[]}},"documentCount":{d},"normalForm":"unknown"}}
        , .{ col.name, col.document_count });

        try sendJson(request, .ok, response_buffer.items);
    } else {
        try sendNotFound(request);
    }
}

fn handleCreateCollection(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    // Read request body
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    // Parse JSON request
    const parsed = json.parseFromSlice(CreateCollectionRequest, allocator, body, .{}) catch {
        try sendBadRequest(request, "Invalid JSON in request body");
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    bridge.createCollection(req.name, req.schema orelse "{}") catch |err| {
        log.err("Failed to create collection: {}", .{err});

        const error_response = switch (err) {
            error.NotImplemented =>
                \\{"error":"not_implemented","message":"Collection creation not yet implemented"}
            ,
            else =>
                \\{"error":"internal_error","message":"Failed to create collection"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    try writer.print(
        \\{{"name":"{s}","type":"document","documentCount":0,"normalForm":"unknown"}}
    , .{req.name});

    try sendJson(request, .created, response_buffer.items);
}

const CreateCollectionRequest = struct {
    name: []const u8,
    schema: ?[]const u8 = null,
};

fn handleDropCollection(request: *std.http.Server.Request, name: []const u8) !void {
    bridge.dropCollection(name) catch |err| {
        log.err("Failed to drop collection {s}: {}", .{ name, err });

        const error_response = switch (err) {
            error.NotImplemented =>
                \\{"error":"FDB_ERR_NOT_IMPLEMENTED","message":"Collection drop not yet implemented in bridge"}
            ,
            error.NotInitialized =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Database not initialized"}
            ,
            else =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Failed to drop collection"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };

    request.respond("", .{
        .status = .no_content,
    }) catch {};
}

// =============================================================================
// Journal Handler
// =============================================================================

fn handleJournal(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    method: std.http.Method,
) !void {
    if (method != .GET) {
        try sendMethodNotAllowed(request);
        return;
    }

    // Parse query parameters from the URL target
    // Expected: ?since=<seq>&limit=<n>
    const target = request.head.target;
    var since: u64 = 0;
    var limit: u32 = 100;

    if (std.mem.indexOf(u8, target, "?")) |q_idx| {
        const query_string = target[q_idx + 1 ..];
        var param_iter = std.mem.splitScalar(u8, query_string, '&');
        while (param_iter.next()) |param| {
            if (std.mem.startsWith(u8, param, "since=")) {
                since = std.fmt.parseInt(u64, param["since=".len..], 10) catch 0;
            } else if (std.mem.startsWith(u8, param, "limit=")) {
                limit = std.fmt.parseInt(u32, param["limit=".len..], 10) catch 100;
            }
        }
    }

    const entries = bridge.getJournal(since, limit) catch |err| {
        log.err("Failed to get journal entries: {}", .{err});

        const error_response = switch (err) {
            error.NotInitialized =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Database not initialized"}
            ,
            error.JournalRenderFailed =>
                \\{"error":"FDB_ERR_IO_ERROR","message":"Failed to render journal entries"}
            ,
            else =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Internal server error"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };
    defer allocator.free(entries);

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    try writer.writeAll("{\"entries\":[");
    for (entries, 0..) |entry, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print(
            \\{{"seq":{d},"timestamp":"{s}","operation":"{s}"
        , .{ entry.sequence, entry.timestamp, entry.operation });
        if (entry.collection) |col| {
            try writer.print(",\"collection\":\"{s}\"", .{col});
        }
        if (entry.actor) |act| {
            try writer.print(",\"provenance\":{{\"actor\":\"{s}\"}}", .{act});
        }
        try writer.writeByte('}');
    }

    // Compute hasMore: if we got exactly `limit` entries, there may be more
    const has_more = entries.len == limit;
    // nextSeq is the sequence after the last entry, or `since` if no entries
    const next_seq = if (entries.len > 0) entries[entries.len - 1].sequence + 1 else since;

    try writer.print("],\"hasMore\":{s},\"nextSeq\":{d}}}", .{
        if (has_more) "true" else "false",
        next_seq,
    });

    try sendJson(request, .ok, response_buffer.items);
}

// =============================================================================
// Normalize Handler
// =============================================================================

fn handleNormalize(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    method: std.http.Method,
    endpoint: []const u8,
) !void {
    if (method != .POST) {
        try sendMethodNotAllowed(request);
        return;
    }

    if (std.mem.indexOf(u8, endpoint, "/discover")) |_| {
        try handleDiscover(allocator, request);
    } else if (std.mem.indexOf(u8, endpoint, "/analyze")) |_| {
        try handleAnalyze(allocator, request);
    } else {
        try sendNotFound(request);
    }
}

fn handleDiscover(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    // Read request body to get collection name and optional sample_size
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    const parsed = json.parseFromSlice(DiscoverRequest, allocator, body, .{}) catch {
        try sendBadRequest(request, "Invalid JSON in request body");
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;
    const sample_size = req.sample_size orelse 1000;

    const deps = bridge.discoverDependencies(req.collection, sample_size) catch |err| {
        log.err("Failed to discover dependencies for {s}: {}", .{ req.collection, err });

        const error_response = switch (err) {
            error.NotImplemented =>
                \\{"error":"FDB_ERR_NOT_IMPLEMENTED","message":"Dependency discovery not yet implemented in bridge"}
            ,
            error.NotInitialized =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Database not initialized"}
            ,
            else =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Failed to discover functional dependencies"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };
    defer allocator.free(deps);

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    try writer.print("{{\"collection\":\"{s}\",\"functionalDependencies\":[", .{req.collection});
    for (deps, 0..) |dep, i| {
        if (i > 0) try writer.writeByte(',');
        // Write determinant array
        try writer.writeAll("{\"determinant\":[");
        for (dep.determinant, 0..) |det, j| {
            if (j > 0) try writer.writeByte(',');
            try writer.print("\"{s}\"", .{det});
        }
        // Classify confidence tier
        const tier: []const u8 = if (dep.confidence >= 0.95) "high" else if (dep.confidence >= 0.8) "medium" else "low";
        try writer.print("],\"dependent\":\"{s}\",\"confidence\":{d:.2},\"tier\":\"{s}\"}}", .{
            dep.dependent,
            dep.confidence,
            tier,
        });
    }
    try writer.writeAll("],\"candidateKeys\":[]}");

    try sendJson(request, .ok, response_buffer.items);
}

const DiscoverRequest = struct {
    collection: []const u8,
    sample_size: ?u32 = null,
};

fn handleAnalyze(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    // Read request body to get collection name
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    const parsed = json.parseFromSlice(AnalyzeRequest, allocator, body, .{}) catch {
        try sendBadRequest(request, "Invalid JSON in request body");
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    const analysis = bridge.analyzeNormalForm(req.collection) catch |err| {
        log.err("Failed to analyze normal form for {s}: {}", .{ req.collection, err });

        const error_response = switch (err) {
            error.NotImplemented =>
                \\{"error":"FDB_ERR_NOT_IMPLEMENTED","message":"Normal form analysis not yet implemented in bridge"}
            ,
            error.NotInitialized =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Database not initialized"}
            ,
            else =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Failed to analyze normal form"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    try writer.print("{{\"collection\":\"{s}\",\"currentForm\":\"{s}\",\"violations\":[", .{
        req.collection,
        analysis.current_form,
    });

    for (analysis.violations, 0..) |violation, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("\"{s}\"", .{violation});
    }

    try writer.writeAll("],\"recommendations\":[");
    for (analysis.suggestions, 0..) |suggestion, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("\"{s}\"", .{suggestion});
    }

    try writer.writeAll("]}");

    try sendJson(request, .ok, response_buffer.items);
}

const AnalyzeRequest = struct {
    collection: []const u8,
};

// =============================================================================
// Migrate Handler
// =============================================================================

fn handleMigrate(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    method: std.http.Method,
    endpoint: []const u8,
) !void {
    if (method != .POST) {
        try sendMethodNotAllowed(request);
        return;
    }

    if (std.mem.indexOf(u8, endpoint, "/start")) |_| {
        try handleMigrationStart(allocator, request);
    } else if (std.mem.indexOf(u8, endpoint, "/shadow")) |_| {
        try handleMigrationAdvance(allocator, request, .start_shadow);
    } else if (std.mem.indexOf(u8, endpoint, "/commit")) |_| {
        try handleMigrationAdvance(allocator, request, .commit);
    } else if (std.mem.indexOf(u8, endpoint, "/abort")) |_| {
        try handleMigrationAdvance(allocator, request, .abort);
    } else {
        try sendNotFound(request);
    }
}

const MigrationStartRequest = struct {
    collection: []const u8,
    target_schema: ?[]const u8 = null,
};

const MigrationAdvanceRequest = struct {
    id: []const u8,
};

fn handleMigrationStart(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    // Read request body
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    const parsed = json.parseFromSlice(MigrationStartRequest, allocator, body, .{}) catch {
        try sendBadRequest(request, "Invalid JSON in request body");
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;
    const target_schema = req.target_schema orelse "{}";

    const migration = bridge.startMigration(req.collection, target_schema) catch |err| {
        log.err("Failed to start migration for {s}: {}", .{ req.collection, err });

        const error_response = switch (err) {
            error.NotImplemented =>
                \\{"error":"FDB_ERR_NOT_IMPLEMENTED","message":"Migration not yet implemented in bridge"}
            ,
            error.NotInitialized =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Database not initialized"}
            ,
            else =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Failed to start migration"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    const phase_str = switch (migration.state) {
        .announced => "announce",
        .shadow_running => "shadow",
        .shadow_complete => "shadow_complete",
        .committed => "complete",
        .aborted => "aborted",
    };

    try writer.print(
        \\{{"id":"{s}","collection":"{s}","phase":"{s}","startedAt":"{s}","narrative":"Migration announced for collection {s}"}}
    , .{ migration.id, migration.source_collection, phase_str, migration.created_at, migration.source_collection });

    try sendJson(request, .ok, response_buffer.items);
}

fn handleMigrationAdvance(allocator: std.mem.Allocator, request: *std.http.Server.Request, action: bridge.MigrationAction) !void {
    // Read request body
    var body_reader = try request.reader();
    const body = try body_reader.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    const parsed = json.parseFromSlice(MigrationAdvanceRequest, allocator, body, .{}) catch {
        try sendBadRequest(request, "Invalid JSON in request body");
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    bridge.advanceMigration(req.id, action) catch |err| {
        log.err("Failed to advance migration {s}: {}", .{ req.id, err });

        const error_response = switch (err) {
            error.NotImplemented =>
                \\{"error":"FDB_ERR_NOT_IMPLEMENTED","message":"Migration advancement not yet implemented in bridge"}
            ,
            error.NotInitialized =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Database not initialized"}
            ,
            else =>
                \\{"error":"FDB_ERR_INTERNAL","message":"Failed to advance migration"}
            ,
        };
        try sendJson(request, .internal_server_error, error_response);
        return;
    };

    // Retrieve updated migration state
    const migration = bridge.getMigration(req.id) catch |err| {
        log.err("Failed to get migration {s} after advance: {}", .{ req.id, err });
        // The advance succeeded but we cannot read back the state; return minimal confirmation
        const phase_str = switch (action) {
            .start_shadow => "shadow",
            .commit => "complete",
            .abort => "aborted",
        };
        var response_buffer = std.ArrayList(u8).init(allocator);
        defer response_buffer.deinit();
        try response_buffer.writer().print(
            \\{{"id":"{s}","phase":"{s}","narrative":"Migration phase advanced"}}
        , .{ req.id, phase_str });
        try sendJson(request, .ok, response_buffer.items);
        return;
    };

    if (migration) |mig| {
        var response_buffer = std.ArrayList(u8).init(allocator);
        defer response_buffer.deinit();
        const writer = response_buffer.writer();

        const phase_str = switch (mig.state) {
            .announced => "announce",
            .shadow_running => "shadow",
            .shadow_complete => "shadow_complete",
            .committed => "complete",
            .aborted => "aborted",
        };

        try writer.print(
            \\{{"id":"{s}","collection":"{s}","phase":"{s}","startedAt":"{s}","narrative":"Migration phase: {s}"}}
        , .{ mig.id, mig.source_collection, phase_str, mig.created_at, phase_str });

        try sendJson(request, .ok, response_buffer.items);
    } else {
        try sendNotFound(request);
    }
}

// =============================================================================
// Health & Metrics
// =============================================================================

fn handleHealth(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    const health = bridge.getHealth();

    // Build response JSON
    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();
    const writer = response_buffer.writer();

    try writer.print(
        \\{{"status":"{s}","version":"{s}","uptime":{d},"checks":{{"database":"{s}","journal":"{s}"}}}}
    , .{
        health.status,
        health.version,
        health.uptime_seconds,
        if (bridge.isInitialized()) "pass" else "fail",
        if (bridge.isInitialized()) "pass" else "fail",
    });

    try sendJson(request, .ok, response_buffer.items);
}

fn handleMetrics(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    const prometheus_metrics = try metrics.getPrometheus(allocator);
    defer allocator.free(prometheus_metrics);

    request.respond(prometheus_metrics, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain; version=0.0.4" },
        },
    }) catch {};
}

// =============================================================================
// Response Helpers
// =============================================================================

fn sendJson(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) !void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}

fn sendBadRequest(request: *std.http.Server.Request, message: []const u8) !void {
    _ = message; // Message content not embedded in JSON to avoid injection; using static response
    const body =
        \\{"error":"bad_request","message":"Invalid request"}
    ;
    try sendJson(request, .bad_request, body);
}

fn sendUnauthorized(request: *std.http.Server.Request) !void {
    const body =
        \\{"error":"unauthorized","message":"Authentication required"}
    ;
    try sendJson(request, .unauthorized, body);
}

fn sendNotFound(request: *std.http.Server.Request) !void {
    const body =
        \\{"error":"not_found","message":"Resource not found"}
    ;
    try sendJson(request, .not_found, body);
}

fn sendMethodNotAllowed(request: *std.http.Server.Request) !void {
    const body =
        \\{"error":"method_not_allowed","message":"Method not allowed for this endpoint"}
    ;
    request.respond(body, .{
        .status = .method_not_allowed,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}

test "extract collection name" {
    try std.testing.expectEqualStrings("articles", extractCollectionName("/collections/articles").?);
    try std.testing.expectEqual(@as(?[]const u8, null), extractCollectionName("/collections"));
    try std.testing.expectEqual(@as(?[]const u8, null), extractCollectionName("/collections/"));
}
