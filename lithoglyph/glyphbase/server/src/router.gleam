// SPDX-License-Identifier: PMPL-1.0-or-later
// HTTP router for Glyphbase API

import lithoglyph/client.{type Connection}
import lithoglyph/database
import lithoglyph/operations
import gleam/dynamic/decode
import gleam/http.{Delete, Get, Patch, Post}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import types.{TextValue}
import wisp.{type Request, type Response}

/// Context passed to handlers
pub type Context {
  Context(db: Connection)
}

/// Main router for all API endpoints
pub fn handle_request(req: Request, ctx: Context) -> Response {
  case wisp.path_segments(req) {
    // Health check
    [] -> home(req)
    ["health"] -> health_check(req)

    // Base CRUD
    ["api", "bases"] -> bases_handler(req, ctx)
    ["api", "bases", base_id] -> base_handler(req, ctx, base_id)

    // Table CRUD
    ["api", "bases", base_id, "tables"] -> tables_handler(req, ctx, base_id)
    ["api", "bases", base_id, "tables", table_id] ->
      table_handler(req, ctx, base_id, table_id)

    // Row CRUD
    ["api", "bases", base_id, "tables", table_id, "rows"] ->
      rows_handler(req, ctx, base_id, table_id)
    ["api", "bases", base_id, "tables", table_id, "rows", row_id] ->
      row_handler(req, ctx, base_id, table_id, row_id)

    // Cell operations
    ["api", "bases", base_id, "tables", table_id, "rows", row_id, "cells", field_id] ->
      cell_handler(req, ctx, base_id, table_id, row_id, field_id)

    // Provenance
    ["api", "bases", base_id, "tables", table_id, "rows", row_id, "cells", field_id, "provenance"] ->
      provenance_handler(req, ctx, base_id, table_id, row_id, field_id)

    // Views
    ["api", "bases", base_id, "tables", table_id, "views"] ->
      views_handler(req, ctx, base_id, table_id)
    ["api", "bases", base_id, "tables", table_id, "views", view_id] ->
      view_handler(req, ctx, base_id, table_id, view_id)

    _ -> wisp.not_found()
  }
}

fn json_response(body: json.Json, status: Int) -> Response {
  let json_string = json.to_string(body)
  wisp.json_response(json_string, status)
}

fn home(_req: Request) -> Response {
  json_response(
    json.object([
      #("name", json.string("Glyphbase")),
      #("version", json.string("0.1.0")),
    ]),
    200,
  )
}

fn health_check(_req: Request) -> Response {
  json_response(json.object([#("status", json.string("ok"))]), 200)
}

// ============================================================
// Base handlers
// ============================================================

fn bases_handler(req: Request, ctx: Context) -> Response {
  case req.method {
    Get -> list_bases(ctx)
    Post -> create_base(req, ctx)
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

fn base_handler(req: Request, ctx: Context, base_id: String) -> Response {
  case req.method {
    Get -> get_base(ctx, base_id)
    Patch -> update_base(req, ctx, base_id)
    Delete -> delete_base(ctx, base_id)
    _ -> wisp.method_not_allowed([Get, Patch, Delete])
  }
}

fn list_bases(ctx: Context) -> Response {
  let op = operations.ListBases
  case database.read(ctx.db, op) {
    Ok(_) -> json_response(json.object([#("bases", json.array([], json.string))]), 200)
    Error(e) -> error_response(e)
  }
}

fn create_base(req: Request, ctx: Context) -> Response {
  use body <- wisp.require_json(req)

  let decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use desc <- decode.optional_field("description", None, decode.optional(decode.string))
    decode.success(#(id, name, desc))
  }

  case decode.run(body, decoder) {
    Ok(#(id, name, description)) -> {
      let op = operations.CreateBase(id, name, description)
      case database.write(ctx.db, op) {
        Ok(_) ->
          json_response(
            json.object([#("id", json.string(id)), #("name", json.string(name))]),
            201,
          )
        Error(e) -> error_response(e)
      }
    }
    Error(_) -> json_response(json.object([#("error", json.string("Invalid request body"))]), 400)
  }
}

fn get_base(ctx: Context, base_id: String) -> Response {
  let op = operations.GetBase(base_id)
  case database.read(ctx.db, op) {
    Ok(_) ->
      json_response(
        json.object([
          #("id", json.string(base_id)),
          #("name", json.string("Demo Base")),
          #("tables", json.array([], json.string)),
        ]),
        200,
      )
    Error(e) -> error_response(e)
  }
}

fn update_base(req: Request, ctx: Context, base_id: String) -> Response {
  use body <- wisp.require_json(req)

  let decoder = {
    use name <- decode.optional_field("name", None, decode.optional(decode.string))
    use desc <- decode.optional_field("description", None, decode.optional(decode.string))
    decode.success(#(name, desc))
  }

  case decode.run(body, decoder) {
    Ok(#(name, description)) -> {
      let op = operations.UpdateBase(base_id, name, description)
      case database.write(ctx.db, op) {
        Ok(_) -> json_response(json.object([#("updated", json.bool(True))]), 200)
        Error(e) -> error_response(e)
      }
    }
    Error(_) -> json_response(json.object([#("error", json.string("Invalid request body"))]), 400)
  }
}

fn delete_base(ctx: Context, base_id: String) -> Response {
  let op = operations.DeleteBase(base_id)
  case database.write(ctx.db, op) {
    Ok(_) -> wisp.no_content()
    Error(e) -> error_response(e)
  }
}

// ============================================================
// Table handlers
// ============================================================

fn tables_handler(req: Request, ctx: Context, base_id: String) -> Response {
  case req.method {
    Get -> list_tables(ctx, base_id)
    Post -> create_table(req, ctx, base_id)
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

fn table_handler(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
) -> Response {
  case req.method {
    Get -> get_table(ctx, base_id, table_id)
    Patch -> update_table(req, ctx, base_id, table_id)
    Delete -> delete_table(ctx, base_id, table_id)
    _ -> wisp.method_not_allowed([Get, Patch, Delete])
  }
}

fn list_tables(ctx: Context, base_id: String) -> Response {
  let op = operations.ListTables(base_id)
  case database.read(ctx.db, op) {
    Ok(_) -> json_response(json.object([#("tables", json.array([], json.string))]), 200)
    Error(e) -> error_response(e)
  }
}

fn create_table(req: Request, ctx: Context, base_id: String) -> Response {
  use body <- wisp.require_json(req)

  let decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use primary <- decode.field("primaryFieldId", decode.string)
    decode.success(#(id, name, primary))
  }

  case decode.run(body, decoder) {
    Ok(#(id, name, primary_field_id)) -> {
      let op = operations.CreateTable(base_id, id, name, [], primary_field_id)
      case database.write(ctx.db, op) {
        Ok(_) ->
          json_response(
            json.object([#("id", json.string(id)), #("name", json.string(name))]),
            201,
          )
        Error(e) -> error_response(e)
      }
    }
    Error(_) -> json_response(json.object([#("error", json.string("Invalid request body"))]), 400)
  }
}

fn get_table(ctx: Context, base_id: String, table_id: String) -> Response {
  let op = operations.GetTable(base_id, table_id)
  case database.read(ctx.db, op) {
    Ok(_) ->
      json_response(
        json.object([
          #("id", json.string(table_id)),
          #("name", json.string("Demo Table")),
          #("fields", json.array([], json.string)),
        ]),
        200,
      )
    Error(e) -> error_response(e)
  }
}

fn update_table(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
) -> Response {
  use body <- wisp.require_json(req)

  let decoder = {
    use name <- decode.optional_field("name", None, decode.optional(decode.string))
    decode.success(name)
  }

  case decode.run(body, decoder) {
    Ok(name) -> {
      let op = operations.UpdateTable(base_id, table_id, name)
      case database.write(ctx.db, op) {
        Ok(_) -> json_response(json.object([#("updated", json.bool(True))]), 200)
        Error(e) -> error_response(e)
      }
    }
    Error(_) -> json_response(json.object([#("error", json.string("Invalid request body"))]), 400)
  }
}

fn delete_table(ctx: Context, base_id: String, table_id: String) -> Response {
  let op = operations.DeleteTable(base_id, table_id)
  case database.write(ctx.db, op) {
    Ok(_) -> wisp.no_content()
    Error(e) -> error_response(e)
  }
}

// ============================================================
// Row handlers
// ============================================================

fn rows_handler(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
) -> Response {
  case req.method {
    Get -> list_rows(ctx, base_id, table_id, req)
    Post -> create_row(req, ctx, base_id, table_id)
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

fn row_handler(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
) -> Response {
  case req.method {
    Get -> get_row(ctx, base_id, table_id, row_id)
    Patch -> update_row(req, ctx, base_id, table_id, row_id)
    Delete -> delete_row(ctx, base_id, table_id, row_id)
    _ -> wisp.method_not_allowed([Get, Patch, Delete])
  }
}

fn list_rows(
  ctx: Context,
  base_id: String,
  table_id: String,
  req: Request,
) -> Response {
  // Parse query params for pagination
  let limit = get_query_int(req, "limit")
  let offset = get_query_int(req, "offset")
  let filter = get_query_string(req, "filter")

  let op = operations.ListRows(base_id, table_id, limit, offset, filter)
  case database.read(ctx.db, op) {
    Ok(_) -> json_response(json.object([#("rows", json.array([], json.string))]), 200)
    Error(e) -> error_response(e)
  }
}

fn create_row(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
) -> Response {
  use body <- wisp.require_json(req)

  let decoder = {
    use id <- decode.field("id", decode.string)
    decode.success(id)
  }

  case decode.run(body, decoder) {
    Ok(id) -> {
      let op = operations.CreateRow(base_id, table_id, id, [])
      case database.write(ctx.db, op) {
        Ok(_) -> json_response(json.object([#("id", json.string(id))]), 201)
        Error(e) -> error_response(e)
      }
    }
    Error(_) -> json_response(json.object([#("error", json.string("Invalid request body"))]), 400)
  }
}

fn get_row(
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
) -> Response {
  let op = operations.GetRow(base_id, table_id, row_id)
  case database.read(ctx.db, op) {
    Ok(_) ->
      json_response(
        json.object([#("id", json.string(row_id)), #("cells", json.object([]))]),
        200,
      )
    Error(e) -> error_response(e)
  }
}

fn update_row(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
) -> Response {
  use body <- wisp.require_json(req)

  let decoder = {
    use rationale <- decode.optional_field("rationale", None, decode.optional(decode.string))
    decode.success(rationale)
  }

  case decode.run(body, decoder) {
    Ok(rationale) -> {
      let op = operations.UpdateRow(base_id, table_id, row_id, [], rationale)
      case database.write(ctx.db, op) {
        Ok(_) -> json_response(json.object([#("updated", json.bool(True))]), 200)
        Error(e) -> error_response(e)
      }
    }
    Error(_) -> json_response(json.object([#("error", json.string("Invalid request body"))]), 400)
  }
}

fn delete_row(
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
) -> Response {
  let op = operations.DeleteRow(base_id, table_id, row_id)
  case database.write(ctx.db, op) {
    Ok(_) -> wisp.no_content()
    Error(e) -> error_response(e)
  }
}

// ============================================================
// Cell handlers
// ============================================================

fn cell_handler(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
  field_id: String,
) -> Response {
  case req.method {
    Get -> get_cell(ctx, base_id, table_id, row_id, field_id)
    Patch -> update_cell(req, ctx, base_id, table_id, row_id, field_id)
    _ -> wisp.method_not_allowed([Get, Patch])
  }
}

fn get_cell(
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
  field_id: String,
) -> Response {
  let op = operations.GetCell(base_id, table_id, row_id, field_id)
  case database.read(ctx.db, op) {
    Ok(_) -> json_response(json.object([#("value", json.null())]), 200)
    Error(e) -> error_response(e)
  }
}

fn update_cell(
  req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
  field_id: String,
) -> Response {
  use body <- wisp.require_json(req)

  // Simple decoder - just get the rationale
  let decoder = {
    use rationale <- decode.optional_field("rationale", None, decode.optional(decode.string))
    decode.success(rationale)
  }

  case decode.run(body, decoder) {
    Ok(rationale) -> {
      // For now, use a default text value - proper parsing would need more work
      let value = TextValue("")
      let op =
        operations.UpdateCell(base_id, table_id, row_id, field_id, value, rationale)
      case database.write(ctx.db, op) {
        Ok(_) -> json_response(json.object([#("updated", json.bool(True))]), 200)
        Error(e) -> error_response(e)
      }
    }
    Error(_) -> json_response(json.object([#("error", json.string("Invalid request body"))]), 400)
  }
}

// ============================================================
// Provenance handler
// ============================================================

fn provenance_handler(
  _req: Request,
  ctx: Context,
  base_id: String,
  table_id: String,
  row_id: String,
  field_id: String,
) -> Response {
  let op = operations.GetProvenance(base_id, table_id, row_id, field_id)
  case database.read(ctx.db, op) {
    Ok(_) -> json_response(json.object([#("entries", json.array([], json.string))]), 200)
    Error(e) -> error_response(e)
  }
}

// ============================================================
// View handlers (placeholder - views are complex)
// ============================================================

fn views_handler(
  req: Request,
  _ctx: Context,
  _base_id: String,
  _table_id: String,
) -> Response {
  case req.method {
    Get -> json_response(json.object([#("views", json.array([], json.string))]), 200)
    Post -> json_response(json.object([#("id", json.string("view_new"))]), 201)
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

fn view_handler(
  req: Request,
  _ctx: Context,
  _base_id: String,
  _table_id: String,
  view_id: String,
) -> Response {
  case req.method {
    Get ->
      json_response(
        json.object([
          #("id", json.string(view_id)),
          #("type", json.string("grid")),
        ]),
        200,
      )
    Patch -> json_response(json.object([#("updated", json.bool(True))]), 200)
    Delete -> wisp.no_content()
    _ -> wisp.method_not_allowed([Get, Patch, Delete])
  }
}

// ============================================================
// Helpers
// ============================================================

fn error_response(error: client.LithError) -> Response {
  let message = case error {
    client.ConnectionError(msg) -> "Connection error: " <> msg
    client.TransactionError(msg) -> "Transaction error: " <> msg
    client.QueryError(msg) -> "Query error: " <> msg
    client.ValidationError(msg) -> "Validation error: " <> msg
    client.ProvenanceError(msg) -> "Provenance error: " <> msg
    client.NotFound(entity, id) -> entity <> " not found: " <> id
    client.PermissionDenied(action) -> "Permission denied: " <> action
    client.NifNotLoaded -> "Database NIF not loaded"
    client.NifError(reason) -> "NIF error: " <> reason
    client.ParseFailed -> "Failed to parse CBOR data"
    client.InvalidHandle -> "Invalid database or transaction handle"
    client.PathTraversal(path) -> "Path traversal rejected: " <> path
  }
  let status = case error {
    client.PathTraversal(_) -> 400
    client.NotFound(_, _) -> 404
    client.PermissionDenied(_) -> 403
    client.ValidationError(_) -> 400
    _ -> 500
  }
  json_response(json.object([#("error", json.string(message))]), status)
}

fn get_query_int(req: Request, key: String) -> Option(Int) {
  case wisp.get_query(req) {
    [] -> None
    params -> {
      params
      |> list.find(fn(p) { p.0 == key })
      |> result.map(fn(p) { p.1 })
      |> result.try(int.parse)
      |> option.from_result
    }
  }
}

fn get_query_string(req: Request, key: String) -> Option(String) {
  case wisp.get_query(req) {
    [] -> None
    params -> {
      params
      |> list.find(fn(p) { p.0 == key })
      |> result.map(fn(p) { p.1 })
      |> option.from_result
    }
  }
}
