// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
//
// lith.gleam - Gleam wrapper for Lith NIF
//
// This provides type-safe Gleam functions that call the Erlang NIF

import gleam/dynamic.{type Dynamic}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/list

/// Opaque handle to a Lith database
pub opaque type Db {
  Db(resource: Dynamic)
}

/// Opaque handle to a transaction
pub opaque type Transaction {
  Transaction(resource: Dynamic)
}

/// Opaque handle to a query cursor
pub opaque type Cursor {
  Cursor(resource: Dynamic)
}

/// Lith status/error codes
pub type FdbError {
  InvalidArg
  NotFound
  PermissionDenied
  AlreadyExists
  ConstraintViolation
  TypeMismatch
  OutOfMemory
  IoError
  Corruption
  Conflict
  InternalError
}

////////////////////////////////////////////////////////////////////////////////
// NIF Function Declarations
////////////////////////////////////////////////////////////////////////////////

/// Initialize Lith (must be called once at startup)
@external(erlang, "lith_nif", "init")
fn nif_init() -> Result(Nil, FdbError)

/// Open an existing database
@external(erlang, "lith_nif", "open")
fn nif_open(path: String) -> Result(Dynamic, FdbError)

/// Create a new database
@external(erlang, "lith_nif", "create")
fn nif_create(path: String, block_count: Int) -> Result(Dynamic, FdbError)

/// Begin a transaction
@external(erlang, "lith_nif", "txn_begin")
fn nif_txn_begin(db: Dynamic) -> Result(Dynamic, FdbError)

/// Commit a transaction
@external(erlang, "lith_nif", "txn_commit")
fn nif_txn_commit(txn: Dynamic) -> Result(Nil, FdbError)

/// Execute an FQL query with provenance
@external(erlang, "lith_nif", "query_execute")
fn nif_query_execute(
  db: Dynamic,
  query: String,
  provenance: String,
) -> Result(Dynamic, FdbError)

/// Fetch next result from cursor
@external(erlang, "lith_nif", "cursor_next")
fn nif_cursor_next(cursor: Dynamic) -> Result(String, FdbError)

////////////////////////////////////////////////////////////////////////////////
// Public API
////////////////////////////////////////////////////////////////////////////////

/// Initialize Lith library
pub fn init() -> Result(Nil, FdbError) {
  nif_init()
}

/// Open an existing Lith database
pub fn open(path: String) -> Result(Db, FdbError) {
  case nif_open(path) {
    Ok(resource) -> Ok(Db(resource))
    Error(e) -> Error(e)
  }
}

/// Create a new Lith database
///
/// block_count: Initial number of 4KiB blocks to allocate
pub fn create(path: String, block_count: Int) -> Result(Db, FdbError) {
  case nif_create(path, block_count) {
    Ok(resource) -> Ok(Db(resource))
    Error(e) -> Error(e)
  }
}

/// Begin a new ACID transaction
pub fn begin_transaction(db: Db) -> Result(Transaction, FdbError) {
  let Db(db_resource) = db
  case nif_txn_begin(db_resource) {
    Ok(resource) -> Ok(Transaction(resource))
    Error(e) -> Error(e)
  }
}

/// Commit a transaction
pub fn commit_transaction(txn: Transaction) -> Result(Nil, FdbError) {
  let Transaction(txn_resource) = txn
  nif_txn_commit(txn_resource)
}

/// Execute an FQL query
///
/// Example provenance JSON:
/// ```json
/// {
///   "actor": "user@example.com",
///   "rationale": "Monthly report generation",
///   "timestamp": 1706745600000
/// }
/// ```
pub fn execute_query(
  db: Db,
  query: String,
  actor: String,
  rationale: String,
) -> Result(Cursor, FdbError) {
  let Db(db_resource) = db

  // Build provenance JSON
  let provenance = json.object([
    #("actor", json.string(actor)),
    #("rationale", json.string(rationale)),
    #("timestamp", json.int(timestamp_now())),
  ])
  |> json.to_string

  case nif_query_execute(db_resource, query, provenance) {
    Ok(resource) -> Ok(Cursor(resource))
    Error(e) -> Error(e)
  }
}

/// Fetch the next result from a cursor
///
/// Returns Ok(Some(json_doc)) if a row was fetched,
/// Ok(None) if the cursor is exhausted,
/// Error(e) on error
pub fn cursor_next(cursor: Cursor) -> Result(Option(String), FdbError) {
  let Cursor(cursor_resource) = cursor
  case nif_cursor_next(cursor_resource) {
    Ok(json_doc) -> Ok(Some(json_doc))
    Error(NotFound) -> Ok(None)  // Cursor exhausted
    Error(e) -> Error(e)
  }
}

/// Collect all results from a cursor into a list
pub fn cursor_to_list(cursor: Cursor) -> Result(List(String), FdbError) {
  cursor_to_list_helper(cursor, [])
}

fn cursor_to_list_helper(
  cursor: Cursor,
  acc: List(String),
) -> Result(List(String), FdbError) {
  case cursor_next(cursor) {
    Ok(Some(doc)) -> cursor_to_list_helper(cursor, [doc, ..acc])
    Ok(None) -> Ok(list.reverse(acc))
    Error(e) -> Error(e)
  }
}

/// Get current timestamp in milliseconds
@external(erlang, "erlang", "system_time")
fn erlang_system_time_native() -> Int

fn timestamp_now() -> Int {
  // Get native time and convert to milliseconds
  // Native time is typically nanoseconds on modern systems
  erlang_system_time_native() / 1_000_000
}
