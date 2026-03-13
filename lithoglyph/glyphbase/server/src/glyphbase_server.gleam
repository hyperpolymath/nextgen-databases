// SPDX-License-Identifier: PMPL-1.0-or-later
// Glyphbase API Server

import envoy
import lithoglyph/client
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/io
import mist
import router.{type Context, Context}
import wisp
import wisp/wisp_mist

/// Default database path
const default_db_path = "./data/glyphbase.db"

pub fn main() {
  io.println("Glyphbase Server v0.1.0")

  // Get database path from environment or use default
  let db_path = get_env_or_default("GLYPHBASE_DB_PATH", default_db_path)
  io.println("Database path: " <> db_path)

  // Open database connection
  io.println("Connecting to Lith...")
  let db = case client.connect(db_path) {
    Ok(conn) -> {
      io.println("Connected to Lith successfully")
      conn
    }
    Error(e) -> {
      io.println("Warning: Failed to connect to Lith: " <> format_error(e))
      io.println("Server will start but database operations will fail")
      io.println("Make sure Lith NIF is loaded and database exists")
      // Return a placeholder - will fail on actual DB operations
      panic as "Database connection required"
    }
  }

  // Create context for handlers
  let ctx = Context(db: db)

  // Configure secret key for wisp
  let secret_key_base = wisp.random_string(64)

  // Get port from environment or use default
  let port = get_port_or_default(8080)
  io.println("Starting on http://localhost:" <> int_to_string(port))

  // Start the HTTP server
  let assert Ok(_) =
    wisp_mist.handler(handle_request(_, secret_key_base, ctx), secret_key_base)
    |> mist.new
    |> mist.port(port)
    |> mist.start

  io.println("Server running!")
  process.sleep_forever()
}

fn handle_request(
  req: wisp.Request,
  _secret: String,
  ctx: Context,
) -> wisp.Response {
  // Handle preflight requests for CORS
  case req.method {
    http.Options -> {
      wisp.ok()
      |> wisp.set_header("Access-Control-Allow-Origin", "*")
      |> wisp.set_header(
        "Access-Control-Allow-Methods",
        "GET, POST, PATCH, DELETE, OPTIONS",
      )
      |> wisp.set_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
    }
    _ -> {
      router.handle_request(req, ctx)
      |> wisp.set_header("Access-Control-Allow-Origin", "*")
    }
  }
}

fn format_error(error: client.LithError) -> String {
  case error {
    client.ConnectionError(msg) -> "Connection error: " <> msg
    client.TransactionError(msg) -> "Transaction error: " <> msg
    client.QueryError(msg) -> "Query error: " <> msg
    client.ValidationError(msg) -> "Validation error: " <> msg
    client.ProvenanceError(msg) -> "Provenance error: " <> msg
    client.NotFound(entity, id) -> entity <> " not found: " <> id
    client.PermissionDenied(action) -> "Permission denied: " <> action
    client.NifNotLoaded -> "NIF not loaded"
    client.NifError(reason) -> "NIF error: " <> reason
    client.ParseFailed -> "CBOR parse failed"
    client.InvalidHandle -> "Invalid handle"
    client.PathTraversal(path) -> "Path traversal rejected: " <> path
  }
}

// ============================================================
// Environment helpers
// ============================================================

fn get_env_or_default(name: String, default: String) -> String {
  case envoy.get(name) {
    Ok(value) ->
      case value {
        "" -> default
        _ -> value
      }
    Error(_) -> default
  }
}

fn get_port_or_default(default: Int) -> Int {
  case envoy.get("PORT") {
    Ok(value) -> {
      case int.parse(value) {
        Ok(port) -> port
        Error(_) -> default
      }
    }
    Error(_) -> default
  }
}

fn int_to_string(n: Int) -> String {
  int.to_string(n)
}
