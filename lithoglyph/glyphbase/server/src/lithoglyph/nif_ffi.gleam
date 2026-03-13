// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith NIF FFI - Gleam wrapper for Erlang NIF

import gleam/dynamic

/// NIF version function
@external(erlang, "lith_nif", "version")
pub fn nif_version() -> #(Int, Int, Int)

/// NIF db_open function
/// Returns opaque database handle resource
@external(erlang, "lith_nif", "db_open")
pub fn nif_db_open(path: BitArray) -> DbHandle

/// NIF db_close function
@external(erlang, "lith_nif", "db_close")
pub fn nif_db_close(db: DbHandle) -> dynamic.Dynamic

/// NIF txn_begin function
/// Returns Result as Erlang {ok, Handle} or {error, Reason}
@external(erlang, "lith_nif", "txn_begin")
pub fn nif_txn_begin(db: DbHandle, mode: BitArray) -> dynamic.Dynamic

/// NIF txn_commit function
@external(erlang, "lith_nif", "txn_commit")
pub fn nif_txn_commit(txn: TxnHandle) -> dynamic.Dynamic

/// NIF txn_abort function
@external(erlang, "lith_nif", "txn_abort")
pub fn nif_txn_abort(txn: TxnHandle) -> dynamic.Dynamic

/// NIF apply function
/// Returns Result as Erlang {ok, BlockId} or {error, Reason}
@external(erlang, "lith_nif", "apply")
pub fn nif_apply(txn: TxnHandle, op_cbor: BitArray) -> dynamic.Dynamic

/// NIF schema function
@external(erlang, "lith_nif", "schema")
pub fn nif_schema(db: DbHandle) -> BitArray

/// NIF journal function
@external(erlang, "lith_nif", "journal")
pub fn nif_journal(db: DbHandle, since: Int) -> BitArray

// Opaque types for NIF resources
pub type DbHandle

pub type TxnHandle
