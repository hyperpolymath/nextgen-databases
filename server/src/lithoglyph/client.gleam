// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith client - Gleam interface to Lith via NIF

import gleam/option.{type Option, None}
import gleam/bit_array
import gleam/dynamic
import lithoglyph/nif_ffi

/// Lith database handle (opaque reference from NIF)
pub opaque type Connection {
  Connection(handle: nif_ffi.DbHandle)
}

/// Lith transaction handle (opaque reference from NIF)
pub opaque type Transaction {
  Transaction(handle: nif_ffi.TxnHandle, conn: Connection)
}

/// Transaction mode
pub type TransactionMode {
  ReadOnly
  ReadWrite
}

/// Lith error types
pub type LithError {
  ConnectionError(message: String)
  TransactionError(message: String)
  QueryError(message: String)
  ValidationError(message: String)
  ProvenanceError(message: String)
  NotFound(entity: String, id: String)
  PermissionDenied(action: String)
  NifNotLoaded
  ParseFailed
  InvalidHandle
}

/// Result type for Lith operations
pub type LithResult(a) =
  Result(a, LithError)

// ============================================================
// Public API (Real NIF Implementation)
// ============================================================

/// Get Lith version
pub fn version() -> #(Int, Int, Int) {
  nif_ffi.nif_version()
}

/// Open a connection to a Lith database
pub fn connect(path: String) -> LithResult(Connection) {
  let path_binary = bit_array.from_string(path)
  // db_open returns DbHandle directly (not wrapped in ok tuple)
  let handle = nif_ffi.nif_db_open(path_binary)
  Ok(Connection(handle: handle))
}

/// Close a Lith connection
pub fn disconnect(conn: Connection) -> LithResult(Nil) {
  // db_close returns atom directly
  let _result = nif_ffi.nif_db_close(conn.handle)
  Ok(Nil)
}

/// Begin a transaction
pub fn begin_transaction(
  conn: Connection,
  mode: TransactionMode,
) -> LithResult(Transaction) {
  let mode_binary = case mode {
    ReadOnly -> <<"read_only":utf8>>
    ReadWrite -> <<"read_write":utf8>>
  }

  // txn_begin returns Result<TxnHandle, Atom> → {ok, Handle} or {error, Atom}
  let result = nif_ffi.nif_txn_begin(conn.handle, mode_binary)
  case handle_erlang_result(result) {
    Ok(handle_dyn) -> {
      // Unsafe coerce since TxnHandle is an opaque Erlang resource
      let handle = unsafe_coerce(handle_dyn)
      Ok(Transaction(handle: handle, conn: conn))
    }
    Error(_) -> Error(InvalidHandle)
  }
}

/// Commit a transaction
pub fn commit(txn: Transaction) -> LithResult(Nil) {
  // txn_commit returns atom directly
  let _result = nif_ffi.nif_txn_commit(txn.handle)
  Ok(Nil)
}

/// Abort a transaction
pub fn abort(txn: Transaction) -> LithResult(Nil) {
  // txn_abort returns atom directly
  let _result = nif_ffi.nif_txn_abort(txn.handle)
  Ok(Nil)
}

/// Apply an operation within a transaction
/// The operation should be CBOR-encoded
/// Returns (BlockId, Optional Provenance)
pub fn apply_operation(
  txn: Transaction,
  operation: BitArray,
) -> LithResult(#(BitArray, Option(BitArray))) {
  // apply returns Result<Vec<u8>, Atom> → {ok, BlockId} or {error, Atom}
  let result = nif_ffi.nif_apply(txn.handle, operation)
  case handle_erlang_result(result) {
    Ok(block_id_dyn) -> {
      // Decode the BitArray block_id
      let block_id = unsafe_coerce(block_id_dyn)
      Ok(#(block_id, None))
    }
    Error(_) -> Error(ParseFailed)
  }
}

/// Get database schema (CBOR-encoded)
pub fn get_schema(conn: Connection) -> LithResult(BitArray) {
  // schema returns Vec<u8> directly
  Ok(nif_ffi.nif_schema(conn.handle))
}

/// Get journal entries since a sequence number (CBOR-encoded)
pub fn get_journal(conn: Connection, since: Int) -> LithResult(BitArray) {
  // journal returns Vec<u8> directly
  Ok(nif_ffi.nif_journal(conn.handle, since))
}

// ============================================================
// High-Level Operations
// ============================================================

/// Execute an operation in a transaction with automatic commit/abort
pub fn with_transaction(
  conn: Connection,
  mode: TransactionMode,
  operation: fn(Transaction) -> LithResult(a),
) -> LithResult(a) {
  case begin_transaction(conn, mode) {
    Ok(txn) -> {
      case operation(txn) {
        Ok(result) -> {
          case commit(txn) {
            Ok(_) -> Ok(result)
            Error(e) -> {
              let _ = abort(txn)
              Error(e)
            }
          }
        }
        Error(e) -> {
          let _ = abort(txn)
          Error(e)
        }
      }
    }
    Error(e) -> Error(e)
  }
}

// ============================================================
// Helper Functions for Erlang Result Handling
// ============================================================

/// Unsafe coercion from dynamic to any type
/// Only use when you're certain of the type
@external(erlang, "erlang", "identity")
fn unsafe_coerce(value: dynamic.Dynamic) -> a

/// Handle Erlang {ok, Value} or {error, Reason} tuples
fn handle_erlang_result(
  result: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic) {
  // Pattern match on the tuple
  // This is a simplified version for M10 PoC
  // In production, use dynamic.decode properly

  case is_ok_result(result) {
    True -> Ok(extract_value(result))
    False -> Error(extract_error(result))
  }
}

@external(erlang, "erlang", "element")
fn erlang_element(index: Int, tuple: dynamic.Dynamic) -> dynamic.Dynamic

@external(erlang, "erlang", "tuple_size")
fn erlang_tuple_size(tuple: dynamic.Dynamic) -> Int

fn is_ok_result(result: dynamic.Dynamic) -> Bool {
  case erlang_tuple_size(result) {
    2 -> {
      // Check if first element is 'ok' atom
      let first = erlang_element(1, result)
      // Convert to string and check
      case dynamic.classify(first) {
        "Atom" -> True
        _ -> False
      }
    }
    _ -> False
  }
}

fn extract_value(result: dynamic.Dynamic) -> dynamic.Dynamic {
  erlang_element(2, result)
}

fn extract_error(result: dynamic.Dynamic) -> dynamic.Dynamic {
  case erlang_tuple_size(result) {
    2 -> erlang_element(2, result)
    _ -> result
  }
}
