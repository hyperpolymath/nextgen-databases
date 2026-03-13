// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// Lith NIF FFI - Raw Erlang NIF bindings
//
// All functions that return {ok, Value} or {error, Reason} from the Zig NIF
// are declared as returning Dynamic. The client module decodes these safely.
// NEVER call these directly — use lithoglyph/client instead.

import gleam/dynamic

/// NIF version function — returns {Major, Minor, Patch} tuple directly
@external(erlang, "lith_nif", "version")
pub fn nif_version() -> #(Int, Int, Int)

/// NIF db_open — returns {ok, DbResource} or {error, Atom} or {error, Atom, Binary}
@external(erlang, "lith_nif", "db_open")
pub fn nif_db_open(path: BitArray) -> dynamic.Dynamic

/// NIF db_close — returns atom 'ok' or {error, Atom}
@external(erlang, "lith_nif", "db_close")
pub fn nif_db_close(db: DbHandle) -> dynamic.Dynamic

/// NIF txn_begin — returns {ok, TxnResource} or {error, Atom}
@external(erlang, "lith_nif", "txn_begin")
pub fn nif_txn_begin(db: DbHandle, mode: BitArray) -> dynamic.Dynamic

/// NIF txn_commit — returns atom 'ok' or {error, Atom}
@external(erlang, "lith_nif", "txn_commit")
pub fn nif_txn_commit(txn: TxnHandle) -> dynamic.Dynamic

/// NIF txn_abort — returns atom 'ok'
@external(erlang, "lith_nif", "txn_abort")
pub fn nif_txn_abort(txn: TxnHandle) -> dynamic.Dynamic

/// NIF apply — returns {ok, Binary} or {error, Atom}
@external(erlang, "lith_nif", "apply")
pub fn nif_apply(txn: TxnHandle, op_cbor: BitArray) -> dynamic.Dynamic

/// NIF schema — returns {ok, Binary} or {error, Atom}
@external(erlang, "lith_nif", "schema")
pub fn nif_schema(db: DbHandle) -> dynamic.Dynamic

/// NIF journal — returns {ok, Binary} or {error, Atom}
@external(erlang, "lith_nif", "journal")
pub fn nif_journal(db: DbHandle, since: Int) -> dynamic.Dynamic

// Opaque types for NIF resource handles (Erlang NIF resources)
pub type DbHandle

pub type TxnHandle
