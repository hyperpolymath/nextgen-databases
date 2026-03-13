/* SPDX-License-Identifier: PMPL-1.0-or-later */
/* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk> */
/*
 * Lithoglyph Bridge C Header
 * Generated from Idris2 ABI definitions (src/Lith/)
 *
 * DO NOT EDIT — regenerate from ABI
 *
 * This header defines the stable C ABI for all runtimes (Factor, Forth,
 * Erlang/BEAM) to interact with the Lithoglyph storage engine via Zig.
 */

#ifndef LITHOGLYPH_BRIDGE_H
#define LITHOGLYPH_BRIDGE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Status Codes (Lith.LithBridge.FdbStatus)
 *
 * Unified superset of core-zig LgStatus (0-7) and
 * ffi/zig Status (0-11). Values 0-7 are implemented;
 * values 8-11 are reserved for future use.
 * ============================================================ */
typedef enum {
    FDB_OK                      = 0,
    FDB_ERR_INTERNAL            = 1,
    FDB_ERR_NOT_FOUND           = 2,
    FDB_ERR_INVALID_ARGUMENT    = 3,
    FDB_ERR_OUT_OF_MEMORY       = 4,
    FDB_ERR_NOT_IMPLEMENTED     = 5,
    FDB_ERR_TXN_NOT_ACTIVE      = 6,
    FDB_ERR_TXN_ALREADY_COMMITTED = 7,
    /* Reserved (ffi/zig extended codes) */
    FDB_ERR_IO_ERROR            = 8,
    FDB_ERR_CORRUPTION          = 9,
    FDB_ERR_CONFLICT            = 10,
    FDB_ERR_ALREADY_EXISTS      = 11,
} FdbStatus;

/* ============================================================
 * Opaque Handles
 * ============================================================ */
typedef struct FdbDb  FdbDb;
typedef struct FdbTxn FdbTxn;

/* ============================================================
 * Blob Types (Lith.LithBridge + core-zig)
 * ============================================================ */

/** Owned byte buffer passed across the FFI boundary */
typedef struct {
    const uint8_t* ptr;
    size_t         len;
} LgBlob;

/** Result type for operations returning data + provenance */
typedef struct {
    LgBlob  data;
    LgBlob  provenance;
    int     status;       /* FdbStatus */
    LgBlob  error_blob;
} LgResult;

/** Transaction mode */
typedef enum {
    LG_TXN_READ_ONLY  = 0,
    LG_TXN_READ_WRITE = 1,
} LgTxnMode;

/** Render options for introspection functions */
typedef struct {
    int  format;            /* 0 = JSON */
    bool include_metadata;
} LgRenderOpts;

/** Proof verifier callback type */
typedef FdbStatus (*LgProofVerifier)(
    const uint8_t* proof_ptr,
    size_t         proof_len,
    void*          context
);

/* ============================================================
 * Constants (Lith.LithBridge + LithLayout)
 * ============================================================ */

/** Block size in bytes (4 KiB) */
#define LG_BLOCK_SIZE          4096
/** Block header size in bytes */
#define LG_BLOCK_HEADER_SIZE   64
/** Block payload size in bytes */
#define LG_BLOCK_PAYLOAD_SIZE  4032
/** Block type: document */
#define LG_BLOCK_TYPE_DOCUMENT 0x0011

/* ============================================================
 * Implemented Functions (core-zig/src/bridge.zig)
 *
 * These are the working bridge functions. Signatures match
 * the Idris2 ABI declarations in LithForeign.idr.
 * ============================================================ */

/* --- Database Lifecycle --- */

/**
 * Open a Lith database.
 *
 * @param path_ptr  Path to database file
 * @param path_len  Length of path
 * @param opts_ptr  CBOR-encoded options (may be NULL)
 * @param opts_len  Length of options (0 if opts_ptr is NULL)
 * @param out_db    Output: database handle
 * @param out_err   Output: error blob (empty on success)
 * @return FdbStatus
 */
FdbStatus fdb_db_open(
    const uint8_t* path_ptr, size_t path_len,
    const uint8_t* opts_ptr, size_t opts_len,
    FdbDb** out_db, LgBlob* out_err
);

/**
 * Close a Lith database and release resources.
 *
 * @param db  Database handle (may be NULL — returns INVALID_ARGUMENT)
 * @return FdbStatus
 */
FdbStatus fdb_db_close(FdbDb* db);

/* --- Transaction Management --- */

/**
 * Begin a new transaction.
 *
 * @param db       Database handle
 * @param mode     Transaction mode (read-only or read-write)
 * @param out_txn  Output: transaction handle
 * @param out_err  Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_txn_begin(
    FdbDb* db, LgTxnMode mode,
    FdbTxn** out_txn, LgBlob* out_err
);

/**
 * Commit a transaction (6-phase WAL: journal → sync → blocks → deletes → superblock → sync).
 *
 * @param txn      Transaction handle
 * @param out_err  Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_txn_commit(FdbTxn* txn, LgBlob* out_err);

/**
 * Abort a transaction, discarding all buffered operations.
 *
 * @param txn  Transaction handle
 * @return FdbStatus
 */
FdbStatus fdb_txn_abort(FdbTxn* txn);

/* --- Operations (buffered until commit) --- */

/**
 * Apply an insert operation within a transaction.
 * Data is buffered and not written to disk until commit.
 *
 * @param txn     Transaction handle
 * @param op_ptr  Operation data (JSON document)
 * @param op_len  Length of operation data
 * @return LgResult with block_id in data blob on success
 */
LgResult fdb_apply(FdbTxn* txn, const uint8_t* op_ptr, size_t op_len);

/**
 * Update an existing block within a transaction.
 *
 * @param txn       Transaction handle
 * @param block_id  Block ID to update
 * @param data_ptr  New data
 * @param data_len  Length of new data
 * @param out_err   Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_update_block(
    FdbTxn* txn, uint64_t block_id,
    const uint8_t* data_ptr, size_t data_len,
    LgBlob* out_err
);

/**
 * Delete a block within a transaction.
 *
 * @param txn       Transaction handle
 * @param block_id  Block ID to delete
 * @param out_err   Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_delete_block(FdbTxn* txn, uint64_t block_id, LgBlob* out_err);

/* --- Query --- */

/**
 * Read all blocks of a given type (full scan).
 * Returns a JSON array of objects with block_id, size, and data fields.
 *
 * @param db          Database handle
 * @param block_type  Block type filter (e.g. LG_BLOCK_TYPE_DOCUMENT)
 * @param out_data    Output: JSON array blob
 * @param out_err     Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_read_blocks(
    FdbDb* db, uint16_t block_type,
    LgBlob* out_data, LgBlob* out_err
);

/* --- Introspection --- */

/**
 * Render a block as canonical text (JSON).
 *
 * @param db        Database handle
 * @param block_id  Block ID to render
 * @param opts      Render options
 * @param out_text  Output: text blob
 * @param out_err   Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_render_block(
    FdbDb* db, uint64_t block_id,
    LgRenderOpts opts,
    LgBlob* out_text, LgBlob* out_err
);

/**
 * Render journal entries since a sequence number.
 *
 * @param db        Database handle
 * @param since     Starting sequence number
 * @param opts      Render options
 * @param out_text  Output: text blob
 * @param out_err   Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_render_journal(
    FdbDb* db, uint64_t since,
    LgRenderOpts opts,
    LgBlob* out_text, LgBlob* out_err
);

/**
 * Get database schema information as JSON.
 *
 * @param db          Database handle
 * @param out_schema  Output: schema blob
 * @param out_err     Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_introspect_schema(
    FdbDb* db, LgBlob* out_schema, LgBlob* out_err
);

/**
 * Get constraint information as JSON.
 *
 * @param db               Database handle
 * @param out_constraints  Output: constraints blob
 * @param out_err          Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_introspect_constraints(
    FdbDb* db, LgBlob* out_constraints, LgBlob* out_err
);

/* --- Proof Verification --- */

/**
 * Register a proof verifier for a specific proof type.
 *
 * @param type_ptr  Proof type identifier (e.g. "fd-holds", "normalization")
 * @param type_len  Length of type identifier
 * @param callback  Verification callback function
 * @param context   Optional context passed to callback (may be NULL)
 * @return FdbStatus
 */
FdbStatus fdb_proof_register_verifier(
    const uint8_t* type_ptr, size_t type_len,
    LgProofVerifier callback, void* context
);

/**
 * Unregister a proof verifier.
 *
 * @param type_ptr  Proof type identifier
 * @param type_len  Length of type identifier
 * @return FdbStatus (NOT_FOUND if not registered)
 */
FdbStatus fdb_proof_unregister_verifier(
    const uint8_t* type_ptr, size_t type_len
);

/**
 * Verify a proof using registered verifiers.
 * Expects JSON: {"type":"proof_type","data":"base64_data"}
 *
 * @param proof_ptr  JSON-encoded proof blob
 * @param proof_len  Length of proof
 * @param out_valid  Output: true if proof is valid
 * @param out_err    Output: error blob
 * @return FdbStatus
 */
FdbStatus fdb_proof_verify(
    const uint8_t* proof_ptr, size_t proof_len,
    bool* out_valid, LgBlob* out_err
);

/**
 * Initialize built-in proof verifiers (fd-holds, normalization, denormalization).
 *
 * @return FdbStatus
 */
FdbStatus fdb_proof_init_builtins(void);

/* --- Utilities --- */

/**
 * Free a blob allocated by the bridge.
 *
 * @param blob  Blob to free (ptr set to NULL after free)
 */
void fdb_blob_free(LgBlob* blob);

/**
 * Get Lith version as encoded integer.
 * Format: major * 10000 + minor * 100 + patch
 * Example: 0.1.0 = 100
 *
 * @return Version number
 */
uint32_t fdb_version(void);

/* ============================================================
 * Planned Functions (not yet implemented in core-zig)
 *
 * These are declared in LithForeign.idr (liblith) but
 * not yet available in the core bridge. Uncomment as
 * implementations land.
 * ============================================================ */

/* FdbStatus fdb_init(void); */
/* void      fdb_cleanup(void); */
/* FdbStatus fdb_create(const char* path, size_t path_len, uint64_t block_count, FdbDb** out_db); */
/* FdbStatus fdb_collection_create(FdbDb* db, const char* name, size_t name_len, const char* schema_json, size_t schema_len); */
/* FdbStatus fdb_collection_drop(FdbDb* db, const char* name, size_t name_len); */
/* FdbStatus fdb_collection_schema(FdbDb* db, const char* name, void** schema_out); */
/* FdbStatus fdb_query_execute(FdbDb* db, const char* query, size_t query_len, const char* provenance, size_t prov_len, void** cursor_out); */
/* FdbStatus fdb_query_explain(FdbDb* db, const char* query, size_t query_len, void* buf, size_t buf_len, size_t* written); */
/* FdbStatus fdb_cursor_next(void* cursor, void* buf, size_t buf_len, size_t* written); */
/* void      fdb_cursor_close(void* cursor); */
/* FdbStatus fdb_journal_get(FdbDb* db, void** journal_out); */
/* FdbStatus fdb_journal_read(void* journal, uint64_t start_seq, uint64_t count, void* buf, size_t buf_len, size_t* written); */
/* FdbStatus fdb_journal_replay(FdbDb* db, uint64_t from_seq); */
/* FdbStatus fdb_normalize_discover(FdbDb* db, const char* collection, void* buf, size_t buf_len, size_t* written); */
/* FdbStatus fdb_normalize_analyze(FdbDb* db, const char* collection, void* nf_out); */
/* FdbStatus fdb_migrate_start(FdbDb* db, const char* collection, uint8_t target_nf, void* proof, size_t proof_len, void** migration_out); */
/* FdbStatus fdb_migrate_commit(void* migration, uint8_t phase); */
/* FdbStatus fdb_serialize_cbor(const char* json, size_t json_len, void* buf, size_t buf_len, size_t* written); */
/* FdbStatus fdb_deserialize_cbor(void* cbor, size_t cbor_len, void* buf, size_t buf_len, size_t* written); */
/* FdbStatus fdb_verify_checksums(FdbDb* db, void* corrupted_out, size_t buf_len, size_t* count_out); */
/* FdbStatus fdb_repair(FdbDb* db, void* report_buf, size_t buf_len, size_t* written); */

#ifdef __cplusplus
}
#endif

#endif /* LITHOGLYPH_BRIDGE_H */
