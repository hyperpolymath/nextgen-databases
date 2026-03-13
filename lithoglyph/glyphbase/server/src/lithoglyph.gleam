// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// lithoglyph.gleam - Public API for Lithoglyph database
//
// This module re-exports the client API for convenient access.
// The real NIF FFI layer is in lithoglyph/nif_ffi.gleam,
// and the typed client wrapper is in lithoglyph/client.gleam.

import gleam/option.{type Option}
import lithoglyph/client.{
  type Connection, type LithError, type LithResult, type Transaction,
  type TransactionMode, ReadOnly, ReadWrite,
}

/// Re-export core types
pub type Db =
  Connection

pub type Txn =
  Transaction

pub type Mode =
  TransactionMode

/// Re-export error type
pub type Error =
  LithError

/// Get Lithoglyph version tuple
pub fn version() -> #(Int, Int, Int) {
  client.version()
}

/// Open a connection to a Lithoglyph database
pub fn open(path: String) -> LithResult(Connection) {
  client.connect(path)
}

/// Close a connection
pub fn close(conn: Connection) -> LithResult(Nil) {
  client.disconnect(conn)
}

/// Begin a read-only transaction
pub fn begin_read(conn: Connection) -> LithResult(Transaction) {
  client.begin_transaction(conn, ReadOnly)
}

/// Begin a read-write transaction
pub fn begin_write(conn: Connection) -> LithResult(Transaction) {
  client.begin_transaction(conn, ReadWrite)
}

/// Commit a transaction
pub fn commit(txn: Transaction) -> LithResult(Nil) {
  client.commit(txn)
}

/// Abort a transaction
pub fn abort(txn: Transaction) -> LithResult(Nil) {
  client.abort(txn)
}

/// Apply a CBOR-encoded operation within a transaction
pub fn apply(
  txn: Transaction,
  operation: BitArray,
) -> LithResult(#(BitArray, Option(BitArray))) {
  client.apply_operation(txn, operation)
}

/// Get database schema (CBOR-encoded)
pub fn schema(conn: Connection) -> LithResult(BitArray) {
  client.get_schema(conn)
}

/// Get journal entries since a sequence number (CBOR-encoded)
pub fn journal(conn: Connection, since: Int) -> LithResult(BitArray) {
  client.get_journal(conn, since)
}

/// Execute an operation in a transaction with automatic commit/abort
pub fn with_transaction(
  conn: Connection,
  mode: TransactionMode,
  operation: fn(Transaction) -> LithResult(a),
) -> LithResult(a) {
  client.with_transaction(conn, mode, operation)
}
