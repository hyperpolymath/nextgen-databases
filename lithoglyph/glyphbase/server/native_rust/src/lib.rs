// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph BEAM NIF - Rust/Rustler implementation
//
// This NIF connects BEAM (Erlang/Gleam/Elixir) to Lithoglyph via the Lithoglyph C ABI.
// Uses CBOR-encoded binaries for efficient data transfer.

#![forbid(unsafe_code)]
use rustler::{Encoder, Env, Error, ResourceArc, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        init_failed,
        invalid_handle,
        parse_failed,
        validation_failed,
        persist_failed,
        alloc_failed,
    }
}

// Database handle wrapper
struct DbHandle {
    path: String,
    // M10 PoC: stub implementation, no actual gforth handle yet
    _dummy: u64,
}

// Transaction handle wrapper
struct TxnHandle {
    db: ResourceArc<DbHandle>,
    mode: TxnMode,
}

#[derive(Clone, Copy)]
enum TxnMode {
    ReadOnly,
    ReadWrite,
}

// NIF functions
rustler::init!(
    "lithoglyph_nif",
    [
        version,
        db_open,
        db_close,
        txn_begin,
        txn_commit,
        txn_abort,
        apply,
        schema,
        journal
    ],
    load = load
);

fn load(env: Env, _info: Term) -> bool {
    rustler::resource!(DbHandle, env);
    rustler::resource!(TxnHandle, env);
    true
}

/// Get Lithoglyph version
#[rustler::nif]
fn version() -> (i32, i32, i32) {
    (1, 0, 0) // v1.0.0 for M10
}

/// Open a Lithoglyph database
#[rustler::nif]
fn db_open(path: String) -> ResourceArc<DbHandle> {
    let db = DbHandle {
        path,
        _dummy: 0xDEADBEEF,
    };

    ResourceArc::new(db)
}

/// Close a Lithoglyph database
#[rustler::nif]
fn db_close(_db: ResourceArc<DbHandle>) -> rustler::Atom {
    // M10 PoC: no cleanup needed for stub
    atoms::ok()
}

/// Begin a transaction
#[rustler::nif]
fn txn_begin(
    db: ResourceArc<DbHandle>,
    mode: String,
) -> Result<ResourceArc<TxnHandle>, rustler::Atom> {
    let txn_mode = match mode.as_str() {
        "read_only" => TxnMode::ReadOnly,
        "read_write" => TxnMode::ReadWrite,
        _ => return Err(atoms::invalid_handle()),
    };

    let txn = TxnHandle {
        db,
        mode: txn_mode,
    };

    Ok(ResourceArc::new(txn))
}

/// Commit a transaction
#[rustler::nif]
fn txn_commit(_txn: ResourceArc<TxnHandle>) -> rustler::Atom {
    // M10 PoC: no actual commit needed for stub
    atoms::ok()
}

/// Abort a transaction
#[rustler::nif]
fn txn_abort(_txn: ResourceArc<TxnHandle>) -> rustler::Atom {
    atoms::ok()
}

/// Apply an operation within a transaction
#[rustler::nif]
fn apply(
    _txn: ResourceArc<TxnHandle>,
    op_cbor: rustler::Binary,
) -> Result<Vec<u8>, rustler::Atom> {
    // M10 PoC: Validate CBOR is a map, then return dummy block ID

    if op_cbor.is_empty() || op_cbor.len() > 1_048_576 {
        return Err(atoms::parse_failed());
    }

    // Check first byte is CBOR map (major type 5)
    let first_byte = op_cbor[0];
    let major_type = (first_byte >> 5) & 0x07;
    if major_type != 5 {
        return Err(atoms::parse_failed());
    }

    // M10 PoC: Return dummy block ID as binary (u64 = 1)
    let block_id: u64 = 1;
    let result = block_id.to_be_bytes().to_vec();

    Ok(result)
}

/// Get database schema
#[rustler::nif]
fn schema(_db: ResourceArc<DbHandle>) -> Vec<u8> {
    // M10 PoC: Return empty CBOR map
    vec![0xa0] // CBOR: {}
}

/// Get journal entries since a sequence number
#[rustler::nif]
fn journal(
    _db: ResourceArc<DbHandle>,
    _since: i64,
) -> Vec<u8> {
    // M10 PoC: Return empty CBOR array
    vec![0x80] // CBOR: []
}
