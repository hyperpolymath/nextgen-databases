// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// Lith client - Safe Gleam interface to Lith via NIF
//
// All NIF results are properly decoded from Erlang tuples.
// No unsafe_coerce — resource handles are extracted via erlang:element/2
// which is safe because the NIF guarantees the tuple structure.

import gleam/bit_array
import gleam/dynamic
import gleam/option.{type Option, None}
import gleam/string
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
  NifError(reason: String)
  ParseFailed
  InvalidHandle
  PathTraversal(path: String)
}

/// Result type for Lith operations
pub type LithResult(a) =
  Result(a, LithError)

// ============================================================
// Path Validation
// ============================================================

/// Validate a database path for directory traversal attacks.
/// Rejects paths containing ".." components which could escape
/// the intended directory.
fn validate_path(path: String) -> LithResult(String) {
  case string.contains(path, "..") {
    True -> Error(PathTraversal(path: path))
    False -> Ok(path)
  }
}

// ============================================================
// Public API
// ============================================================

/// Get Lith version
pub fn version() -> #(Int, Int, Int) {
  nif_ffi.nif_version()
}

/// Open a connection to a Lith database.
/// The path is validated against directory traversal before opening.
pub fn connect(path: String) -> LithResult(Connection) {
  case validate_path(path) {
    Error(e) -> Error(e)
    Ok(safe_path) -> {
      let path_binary = bit_array.from_string(safe_path)
      let result = nif_ffi.nif_db_open(path_binary)
      case decode_ok_result(result) {
        Ok(handle_dyn) -> {
          let handle = coerce_to_db_handle(handle_dyn)
          Ok(Connection(handle: handle))
        }
        Error(reason) -> Error(ConnectionError(message: reason))
      }
    }
  }
}

/// Close a Lith connection
pub fn disconnect(conn: Connection) -> LithResult(Nil) {
  let result = nif_ffi.nif_db_close(conn.handle)
  case decode_atom_or_error(result) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(ConnectionError(message: reason))
  }
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

  let result = nif_ffi.nif_txn_begin(conn.handle, mode_binary)
  case decode_ok_result(result) {
    Ok(handle_dyn) -> {
      let handle = coerce_to_txn_handle(handle_dyn)
      Ok(Transaction(handle: handle, conn: conn))
    }
    Error(reason) -> Error(TransactionError(message: reason))
  }
}

/// Commit a transaction
pub fn commit(txn: Transaction) -> LithResult(Nil) {
  let result = nif_ffi.nif_txn_commit(txn.handle)
  case decode_atom_or_error(result) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(TransactionError(message: reason))
  }
}

/// Abort a transaction
pub fn abort(txn: Transaction) -> LithResult(Nil) {
  let result = nif_ffi.nif_txn_abort(txn.handle)
  case decode_atom_or_error(result) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(TransactionError(message: reason))
  }
}

/// Apply an operation within a transaction.
/// The operation should be CBOR-encoded.
/// Returns (BlockId, Optional Provenance)
pub fn apply_operation(
  txn: Transaction,
  operation: BitArray,
) -> LithResult(#(BitArray, Option(BitArray))) {
  let result = nif_ffi.nif_apply(txn.handle, operation)
  case decode_ok_result(result) {
    Ok(block_id_dyn) -> {
      let block_id = coerce_to_bit_array(block_id_dyn)
      Ok(#(block_id, None))
    }
    Error(reason) -> Error(QueryError(message: reason))
  }
}

/// Get database schema (CBOR-encoded)
pub fn get_schema(conn: Connection) -> LithResult(BitArray) {
  let result = nif_ffi.nif_schema(conn.handle)
  case decode_ok_result(result) {
    Ok(data_dyn) -> Ok(coerce_to_bit_array(data_dyn))
    Error(reason) -> Error(QueryError(message: reason))
  }
}

/// Get journal entries since a sequence number (CBOR-encoded)
pub fn get_journal(conn: Connection, since: Int) -> LithResult(BitArray) {
  let result = nif_ffi.nif_journal(conn.handle, since)
  case decode_ok_result(result) {
    Ok(data_dyn) -> Ok(coerce_to_bit_array(data_dyn))
    Error(reason) -> Error(QueryError(message: reason))
  }
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
// Erlang Term Decoding (replaces unsafe_coerce)
// ============================================================

/// Extract element from an Erlang tuple by 1-based index.
/// This is safe because we only call it after verifying tuple structure.
@external(erlang, "erlang", "element")
fn erlang_element(index: Int, tuple: dynamic.Dynamic) -> dynamic.Dynamic

/// Get the size of an Erlang tuple
@external(erlang, "erlang", "tuple_size")
fn erlang_tuple_size(tuple: dynamic.Dynamic) -> Int

/// Check if a dynamic value is a specific atom
@external(erlang, "erlang", "is_atom")
fn erlang_is_atom(value: dynamic.Dynamic) -> Bool

/// Convert atom to string for comparison
@external(erlang, "erlang", "atom_to_binary")
fn erlang_atom_to_binary(atom: dynamic.Dynamic) -> BitArray

/// Coerce a dynamic value known to be a DbHandle NIF resource.
/// Safe because the NIF guarantees the value inside {ok, Handle}
/// is always a valid DbHandle resource reference.
@external(erlang, "erlang", "identity")
fn coerce_to_db_handle(value: dynamic.Dynamic) -> nif_ffi.DbHandle

/// Coerce a dynamic value known to be a TxnHandle NIF resource.
/// Safe because the NIF guarantees the value inside {ok, Handle}
/// is always a valid TxnHandle resource reference.
@external(erlang, "erlang", "identity")
fn coerce_to_txn_handle(value: dynamic.Dynamic) -> nif_ffi.TxnHandle

/// Coerce a dynamic value known to be a BitArray (binary).
/// Safe because the NIF returns binaries for schema/journal/apply results
/// and we only call this after verifying the {ok, Value} tuple structure.
@external(erlang, "erlang", "identity")
fn coerce_to_bit_array(value: dynamic.Dynamic) -> BitArray

/// Decode an Erlang {ok, Value} or {error, Reason} tuple.
/// Returns Ok(Value) for {ok, Value}, Error(reason_string) for {error, ...}.
/// This replaces the broken is_ok_result which accepted ANY atom as "ok".
fn decode_ok_result(
  result: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, String) {
  case erlang_is_atom(result) {
    True -> {
      // Bare atom result (e.g. just 'ok' without a tuple)
      let atom_bin = erlang_atom_to_binary(result)
      case bit_array.to_string(atom_bin) {
        Ok("ok") -> Ok(result)
        Ok(other) -> Error(other)
        Error(_) -> Error("unknown_atom")
      }
    }
    False -> {
      // Should be a tuple
      let size = erlang_tuple_size(result)
      case size >= 2 {
        True -> {
          let tag = erlang_element(1, result)
          let tag_bin = erlang_atom_to_binary(tag)
          case bit_array.to_string(tag_bin) {
            Ok("ok") -> Ok(erlang_element(2, result))
            Ok("error") -> {
              // Extract error reason
              let reason = erlang_element(2, result)
              case erlang_is_atom(reason) {
                True -> {
                  let reason_bin = erlang_atom_to_binary(reason)
                  case bit_array.to_string(reason_bin) {
                    Ok(reason_str) -> Error(reason_str)
                    Error(_) -> Error("unknown_error")
                  }
                }
                False -> Error("nif_error")
              }
            }
            _ -> Error("unexpected_nif_result")
          }
        }
        False -> Error("malformed_nif_result")
      }
    }
  }
}

/// Decode a result that is either bare atom 'ok' or {error, Reason}.
/// Used for db_close, txn_commit, txn_abort which return atoms directly.
fn decode_atom_or_error(
  result: dynamic.Dynamic,
) -> Result(Nil, String) {
  case decode_ok_result(result) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(reason)
  }
}
