// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Lithoglyph BEAM NIF - Rust/Rustler implementation
//
// This NIF connects BEAM (Erlang/Gleam/Elixir) to Lithoglyph via the Lith C ABI.
// Uses CBOR-encoded binaries for efficient data transfer.
//
// All database operations delegate to the core bridge (generated/abi/bridge.h)
// via FFI. Error codes from the bridge are translated to Elixir-style
// {:ok, result} / {:error, reason} tuples.

use rustler::{Encoder, Env, ResourceArc, Term};
use std::ptr;
use std::sync::Mutex;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        init_failed,
        invalid_handle,
        invalid_argument,
        parse_failed,
        validation_failed,
        persist_failed,
        alloc_failed,
        resource_alloc_failed,
        result_alloc_failed,
        // Bridge status code atoms (match LithStatus enum in bridge.h)
        internal_error,
        not_found,
        out_of_memory,
        not_implemented,
        txn_not_active,
        txn_already_committed,
        io_error,
        corruption,
        conflict,
        already_exists,
        unknown_error,
    }
}

// ============================================================
// Lith C ABI declarations (from generated/abi/bridge.h)
//
// These extern functions are provided by liblith.so (the Zig FFI
// bridge implementation at ffi/zig/src/bridge.zig). The Rust NIF
// shared library links against liblith at load time.
// ============================================================

/// LithStatus codes (must match bridge.h LithStatus enum)
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
enum LithStatus {
    Ok = 0,
    ErrInternal = 1,
    ErrNotFound = 2,
    ErrInvalidArgument = 3,
    ErrOutOfMemory = 4,
    ErrNotImplemented = 5,
    ErrTxnNotActive = 6,
    ErrTxnAlreadyCommitted = 7,
    ErrIoError = 8,
    ErrCorruption = 9,
    ErrConflict = 10,
    ErrAlreadyExists = 11,
}

impl LithStatus {
    /// Convert a raw C int status code to an LithStatus enum variant.
    fn from_raw(code: i32) -> Self {
        match code {
            0 => Self::Ok,
            1 => Self::ErrInternal,
            2 => Self::ErrNotFound,
            3 => Self::ErrInvalidArgument,
            4 => Self::ErrOutOfMemory,
            5 => Self::ErrNotImplemented,
            6 => Self::ErrTxnNotActive,
            7 => Self::ErrTxnAlreadyCommitted,
            8 => Self::ErrIoError,
            9 => Self::ErrCorruption,
            10 => Self::ErrConflict,
            11 => Self::ErrAlreadyExists,
            _ => Self::ErrInternal,
        }
    }

    /// Convert an LithStatus to a Rustler atom for BEAM error tuples.
    fn to_atom(&self) -> rustler::Atom {
        match self {
            Self::Ok => atoms::ok(),
            Self::ErrInternal => atoms::internal_error(),
            Self::ErrNotFound => atoms::not_found(),
            Self::ErrInvalidArgument => atoms::invalid_argument(),
            Self::ErrOutOfMemory => atoms::out_of_memory(),
            Self::ErrNotImplemented => atoms::not_implemented(),
            Self::ErrTxnNotActive => atoms::txn_not_active(),
            Self::ErrTxnAlreadyCommitted => atoms::txn_already_committed(),
            Self::ErrIoError => atoms::io_error(),
            Self::ErrCorruption => atoms::corruption(),
            Self::ErrConflict => atoms::conflict(),
            Self::ErrAlreadyExists => atoms::already_exists(),
        }
    }
}

/// Opaque database handle from the core bridge
#[repr(C)]
struct LithDb {
    _opaque: [u8; 0],
}

/// Opaque transaction handle from the core bridge
#[repr(C)]
struct LithTxn {
    _opaque: [u8; 0],
}

/// Owned byte buffer passed across the FFI boundary
#[repr(C)]
#[derive(Debug, Clone, Copy)]
struct LgBlob {
    ptr: *const u8,
    len: usize,
}

impl Default for LgBlob {
    fn default() -> Self {
        Self {
            ptr: ptr::null(),
            len: 0,
        }
    }
}

/// Result type for operations returning data + provenance
#[repr(C)]
struct LgResult {
    data: LgBlob,
    provenance: LgBlob,
    status: i32,
    error_blob: LgBlob,
}

/// Transaction mode
#[repr(C)]
#[derive(Clone, Copy)]
enum LgTxnMode {
    ReadOnly = 0,
    ReadWrite = 1,
}

/// Render options for introspection functions
#[repr(C)]
#[derive(Clone, Copy)]
struct LgRenderOpts {
    format: i32,
    include_metadata: bool,
}

extern "C" {
    /// Open a Lith database.
    fn lith_db_open(
        path_ptr: *const u8,
        path_len: usize,
        opts_ptr: *const u8,
        opts_len: usize,
        out_db: *mut *mut LithDb,
        out_err: *mut LgBlob,
    ) -> i32;

    /// Close a Lith database and release resources.
    fn lith_db_close(db: *mut LithDb) -> i32;

    /// Begin a new transaction.
    fn lith_txn_begin(
        db: *mut LithDb,
        mode: LgTxnMode,
        out_txn: *mut *mut LithTxn,
        out_err: *mut LgBlob,
    ) -> i32;

    /// Commit a transaction (6-phase WAL).
    fn lith_txn_commit(txn: *mut LithTxn, out_err: *mut LgBlob) -> i32;

    /// Abort a transaction, discarding all buffered operations.
    fn lith_txn_abort(txn: *mut LithTxn) -> i32;

    /// Apply an insert operation within a transaction.
    fn lith_apply(txn: *mut LithTxn, op_ptr: *const u8, op_len: usize) -> LgResult;

    /// Get database schema information as JSON.
    fn lith_introspect_schema(
        db: *mut LithDb,
        out_schema: *mut LgBlob,
        out_err: *mut LgBlob,
    ) -> i32;

    /// Render journal entries since a sequence number.
    fn lith_render_journal(
        db: *mut LithDb,
        since: u64,
        opts: LgRenderOpts,
        out_text: *mut LgBlob,
        out_err: *mut LgBlob,
    ) -> i32;

    /// Free a blob allocated by the bridge.
    fn lith_blob_free(blob: *mut LgBlob);

    /// Get Lith version as encoded integer (major * 10000 + minor * 100 + patch).
    fn lith_version() -> u32;
}

/// Helper: free an LgBlob if its pointer is non-null.
fn free_blob_if_nonnull(blob: &mut LgBlob) {
    if !blob.ptr.is_null() {
        // SAFETY: blob.ptr is non-null (checked above). The bridge allocated this
        // blob and lith_blob_free is the designated deallocator for bridge-allocated
        // blobs. After this call, blob.ptr is set to null by the bridge.
        unsafe { lith_blob_free(blob) };
    }
}

/// Helper: copy an LgBlob's data into a Vec<u8>, then free the blob.
fn blob_to_vec_and_free(blob: &mut LgBlob) -> Vec<u8> {
    if blob.ptr.is_null() || blob.len == 0 {
        free_blob_if_nonnull(blob);
        return Vec::new();
    }

    // SAFETY: blob.ptr is non-null and blob.len > 0 (checked above). The bridge
    // guarantees the pointer is valid for blob.len bytes until lith_blob_free() is
    // called. We copy the data before freeing, so no use-after-free.
    let data = unsafe { std::slice::from_raw_parts(blob.ptr, blob.len) }.to_vec();
    free_blob_if_nonnull(blob);
    data
}

// ============================================================
// NIF Handle Wrappers
// ============================================================

/// Database handle wrapper — holds a raw LithDb pointer from the core bridge.
/// The pointer is protected by a Mutex because BEAM NIF resources can be accessed
/// from multiple scheduler threads. The Option allows us to close the database
/// once and set the pointer to None.
struct DbHandle {
    lith: Mutex<Option<*mut LithDb>>,
    #[allow(dead_code)] // Retained for debug logging and error messages
    path: String,
}

// SAFETY: LithDb is an opaque handle from the C bridge. The bridge implementation
// (ffi/zig/src/bridge.zig) uses thread-local state and global locks internally.
// We additionally protect the raw pointer with a Mutex to prevent concurrent
// access from multiple BEAM scheduler threads at the NIF level.
unsafe impl Send for DbHandle {}
unsafe impl Sync for DbHandle {}

/// Transaction handle wrapper — holds a raw LithTxn pointer from the core bridge.
struct TxnHandle {
    lith_txn: Mutex<Option<*mut LithTxn>>,
    #[allow(dead_code)] // Retained to prevent db from being dropped while txn is active
    db: ResourceArc<DbHandle>,
    #[allow(dead_code)] // Retained for commit/abort validation
    mode: TxnMode,
}

// SAFETY: Same rationale as DbHandle — opaque handle protected by Mutex.
unsafe impl Send for TxnHandle {}
unsafe impl Sync for TxnHandle {}

#[derive(Clone, Copy)]
enum TxnMode {
    ReadOnly,
    ReadWrite,
}

impl TxnMode {
    fn to_lg_mode(&self) -> LgTxnMode {
        match self {
            TxnMode::ReadOnly => LgTxnMode::ReadOnly,
            TxnMode::ReadWrite => LgTxnMode::ReadWrite,
        }
    }
}

// NIF functions
rustler::init!("lith_nif", load = load);

#[allow(non_local_definitions)]
fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(DbHandle, env);
    let _ = rustler::resource!(TxnHandle, env);
    true
}

/// Get Lithoglyph version from the core bridge.
/// The bridge encodes version as: major * 10000 + minor * 100 + patch.
/// Returns {Major, Minor, Patch} tuple.
#[rustler::nif]
fn version() -> (i32, i32, i32) {
    // SAFETY: lith_version is a pure function with no side effects that
    // returns a u32 version encoding. No pointers, no allocations.
    let ver = unsafe { lith_version() };
    let major = (ver / 10000) as i32;
    let minor = ((ver % 10000) / 100) as i32;
    let patch = (ver % 100) as i32;
    (major, minor, patch)
}

/// Open a Lithoglyph database via the core bridge (lith_db_open).
/// Returns {:ok, DbRef} | {:error, reason}
#[rustler::nif]
fn db_open(path: String) -> Result<ResourceArc<DbHandle>, rustler::Atom> {
    let mut out_db: *mut LithDb = ptr::null_mut();
    let mut out_err = LgBlob::default();

    // SAFETY: path.as_ptr() and path.len() provide a valid byte slice for the
    // duration of the call. opts_ptr is null with opts_len 0 (no options).
    // out_db and out_err are valid mutable pointers to stack-allocated variables.
    let status_code = unsafe {
        lith_db_open(
            path.as_ptr(),
            path.len(),
            ptr::null(),
            0,
            &mut out_db,
            &mut out_err,
        )
    };

    // Free error blob regardless of outcome
    free_blob_if_nonnull(&mut out_err);

    let status = LithStatus::from_raw(status_code);
    if status != LithStatus::Ok || out_db.is_null() {
        return Err(atoms::init_failed());
    }

    let db = DbHandle {
        lith: Mutex::new(Some(out_db)),
        path,
    };

    Ok(ResourceArc::new(db))
}

/// Close a Lithoglyph database via the core bridge (lith_db_close).
/// Returns :ok | {:error, reason}
#[rustler::nif]
fn db_close(db: ResourceArc<DbHandle>) -> Result<rustler::Atom, rustler::Atom> {
    let mut guard = db.lith.lock().map_err(|_| atoms::internal_error())?;

    match guard.take() {
        Some(lith_ptr) => {
            // SAFETY: lith_ptr was obtained from a successful lith_db_open call and
            // has not been closed yet (we take() it from the Option to ensure
            // single-close semantics). The pointer is valid for lith_db_close.
            let status_code = unsafe { lith_db_close(lith_ptr) };
            let status = LithStatus::from_raw(status_code);
            if status != LithStatus::Ok {
                return Err(status.to_atom());
            }
            Ok(atoms::ok())
        }
        None => {
            // Already closed — idempotent
            Ok(atoms::ok())
        }
    }
}

/// Begin a transaction via the core bridge (lith_txn_begin).
/// Returns {:ok, TxnRef} | {:error, reason}
#[rustler::nif]
fn txn_begin(
    db: ResourceArc<DbHandle>,
    mode: String,
) -> Result<ResourceArc<TxnHandle>, rustler::Atom> {
    let txn_mode = match mode.as_str() {
        "read_only" => TxnMode::ReadOnly,
        "read_write" => TxnMode::ReadWrite,
        _ => return Err(atoms::invalid_argument()),
    };

    let guard = db.lith.lock().map_err(|_| atoms::internal_error())?;
    let lith_ptr = guard.ok_or_else(|| atoms::invalid_handle())?;

    let mut out_txn: *mut LithTxn = ptr::null_mut();
    let mut out_err = LgBlob::default();

    // SAFETY: lith_ptr is a valid, non-null LithDb pointer obtained from a
    // successful lith_db_open (checked via Option::ok_or above). out_txn and
    // out_err are valid mutable pointers to stack-allocated variables.
    let status_code = unsafe {
        lith_txn_begin(
            lith_ptr,
            txn_mode.to_lg_mode(),
            &mut out_txn,
            &mut out_err,
        )
    };

    // Free error blob regardless of outcome
    free_blob_if_nonnull(&mut out_err);

    let status = LithStatus::from_raw(status_code);
    if status != LithStatus::Ok || out_txn.is_null() {
        return Err(status.to_atom());
    }

    // Release the lock before creating the resource to avoid holding it
    // longer than necessary.
    drop(guard);

    let txn = TxnHandle {
        lith_txn: Mutex::new(Some(out_txn)),
        db,
        mode: txn_mode,
    };

    Ok(ResourceArc::new(txn))
}

/// Commit a transaction via the core bridge (lith_txn_commit).
/// Executes the 6-phase WAL: journal -> sync -> blocks -> deletes -> superblock -> sync.
/// Returns :ok | {:error, reason}
#[rustler::nif]
fn txn_commit(txn: ResourceArc<TxnHandle>) -> Result<rustler::Atom, rustler::Atom> {
    let mut guard = txn.lith_txn.lock().map_err(|_| atoms::internal_error())?;

    match guard.take() {
        Some(txn_ptr) => {
            let mut out_err = LgBlob::default();

            // SAFETY: txn_ptr was obtained from a successful lith_txn_begin call
            // and has not been committed or aborted yet (we take() it from the
            // Option to ensure single-use semantics). out_err is a valid mutable
            // pointer to a stack-allocated LgBlob.
            let status_code = unsafe { lith_txn_commit(txn_ptr, &mut out_err) };

            free_blob_if_nonnull(&mut out_err);

            let status = LithStatus::from_raw(status_code);
            if status != LithStatus::Ok {
                return Err(status.to_atom());
            }
            Ok(atoms::ok())
        }
        None => {
            // Transaction already committed or aborted
            Err(atoms::txn_not_active())
        }
    }
}

/// Abort a transaction via the core bridge (lith_txn_abort).
/// Returns :ok | {:error, reason}
#[rustler::nif]
fn txn_abort(txn: ResourceArc<TxnHandle>) -> Result<rustler::Atom, rustler::Atom> {
    let mut guard = txn.lith_txn.lock().map_err(|_| atoms::internal_error())?;

    match guard.take() {
        Some(txn_ptr) => {
            // SAFETY: txn_ptr was obtained from a successful lith_txn_begin call
            // and has not been committed or aborted yet (we take() it from the
            // Option). The pointer is valid for lith_txn_abort.
            let status_code = unsafe { lith_txn_abort(txn_ptr) };

            let status = LithStatus::from_raw(status_code);
            if status != LithStatus::Ok {
                return Err(status.to_atom());
            }
            Ok(atoms::ok())
        }
        None => {
            // Already aborted — idempotent
            Ok(atoms::ok())
        }
    }
}

/// Apply an operation within a transaction via the core bridge (lith_apply).
/// The bridge parses the CBOR/JSON payload, validates it, and buffers the write.
///
/// Returns {:ok, result_binary} | {:ok, result_binary, provenance_binary} | {:error, reason}
///
/// NOTE: This NIF is registered as "apply" in the NIF table (see rustler::init! above
/// uses apply_op but the BEAM-facing name is "apply" via the #[rustler::nif(name = ...)]
/// attribute).
#[rustler::nif(name = "apply")]
fn apply_op<'a>(env: Env<'a>, txn: ResourceArc<TxnHandle>, op_cbor: rustler::Binary<'a>) -> Term<'a> {
    if op_cbor.is_empty() || op_cbor.len() > 1_048_576 {
        return (atoms::error(), atoms::invalid_argument()).encode(env);
    }

    let guard = match txn.lith_txn.lock() {
        Ok(g) => g,
        Err(_) => return (atoms::error(), atoms::internal_error()).encode(env),
    };

    let txn_ptr = match *guard {
        Some(ptr) => ptr,
        None => return (atoms::error(), atoms::txn_not_active()).encode(env),
    };

    // SAFETY: txn_ptr is a valid, non-null LithTxn pointer obtained from a
    // successful lith_txn_begin (checked via Option match above). op_cbor.as_ref()
    // provides a valid byte slice for the duration of the call.
    let mut result = unsafe { lith_apply(txn_ptr, op_cbor.as_ref().as_ptr(), op_cbor.len()) };

    let status = LithStatus::from_raw(result.status);
    if status != LithStatus::Ok {
        free_blob_if_nonnull(&mut result.error_blob);
        free_blob_if_nonnull(&mut result.data);
        free_blob_if_nonnull(&mut result.provenance);
        return (atoms::error(), status.to_atom()).encode(env);
    }

    // Extract result data
    let result_data = blob_to_vec_and_free(&mut result.data);

    // Include provenance token in response if the bridge provided one
    let has_provenance = !result.provenance.ptr.is_null() && result.provenance.len > 0;

    if has_provenance {
        let provenance_data = blob_to_vec_and_free(&mut result.provenance);
        // Free error blob if any
        free_blob_if_nonnull(&mut result.error_blob);
        return (atoms::ok(), result_data, provenance_data).encode(env);
    }

    // Free remaining blobs
    free_blob_if_nonnull(&mut result.provenance);
    free_blob_if_nonnull(&mut result.error_blob);

    (atoms::ok(), result_data).encode(env)
}

/// Get database schema via the core bridge (lith_introspect_schema).
/// Returns {:ok, schema_json_binary} | {:error, reason}
#[rustler::nif]
fn schema(db: ResourceArc<DbHandle>) -> Result<Vec<u8>, rustler::Atom> {
    let guard = db.lith.lock().map_err(|_| atoms::internal_error())?;
    let lith_ptr = guard.ok_or_else(|| atoms::invalid_handle())?;

    let mut out_schema = LgBlob::default();
    let mut out_err = LgBlob::default();

    // SAFETY: lith_ptr is a valid, non-null LithDb pointer (checked via Option::ok_or
    // above). out_schema and out_err are valid mutable pointers to stack-allocated
    // LgBlob structs.
    let status_code = unsafe { lith_introspect_schema(lith_ptr, &mut out_schema, &mut out_err) };

    free_blob_if_nonnull(&mut out_err);

    let status = LithStatus::from_raw(status_code);
    if status != LithStatus::Ok {
        free_blob_if_nonnull(&mut out_schema);
        return Err(status.to_atom());
    }

    let data = blob_to_vec_and_free(&mut out_schema);

    // If no schema data returned, provide an empty JSON object
    if data.is_empty() {
        return Ok(b"{}".to_vec());
    }

    Ok(data)
}

/// Get journal entries since a sequence number via the core bridge (lith_render_journal).
/// Returns {:ok, journal_json_binary} | {:error, reason}
#[rustler::nif]
fn journal(db: ResourceArc<DbHandle>, since: i64) -> Result<Vec<u8>, rustler::Atom> {
    let guard = db.lith.lock().map_err(|_| atoms::internal_error())?;
    let lith_ptr = guard.ok_or_else(|| atoms::invalid_handle())?;

    // Clamp negative values to 0 (meaning "from the beginning")
    let since_u64 = if since >= 0 { since as u64 } else { 0 };

    let opts = LgRenderOpts {
        format: 0, // JSON
        include_metadata: true,
    };

    let mut out_text = LgBlob::default();
    let mut out_err = LgBlob::default();

    // SAFETY: lith_ptr is a valid, non-null LithDb pointer (checked via Option::ok_or
    // above). opts is a valid LgRenderOpts value. out_text and out_err are valid
    // mutable pointers to stack-allocated LgBlob structs.
    let status_code = unsafe {
        lith_render_journal(lith_ptr, since_u64, opts, &mut out_text, &mut out_err)
    };

    free_blob_if_nonnull(&mut out_err);

    let status = LithStatus::from_raw(status_code);
    if status != LithStatus::Ok {
        free_blob_if_nonnull(&mut out_text);
        return Err(status.to_atom());
    }

    let data = blob_to_vec_and_free(&mut out_text);

    // If no journal data returned, provide an empty JSON array
    if data.is_empty() {
        return Ok(b"[]".to_vec());
    }

    Ok(data)
}
