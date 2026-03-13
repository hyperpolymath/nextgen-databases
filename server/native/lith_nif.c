// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
//
// lith_nif.c - Erlang NIF wrapper for Lith Zig FFI
//
// This bridges Gleam (BEAM) to Lith's liblith.so

#include <erl_nif.h>
#include <string.h>
#include <stdint.h>

// Forward declarations for Lith FFI functions
// These will be linked from liblith.so

extern int32_t lith_init(void);
extern void lith_cleanup(void);
extern int32_t lith_open(const char* path, uint64_t path_len, void** db_out);
extern int32_t lith_close(void* db);
extern int32_t lith_create(const char* path, uint64_t path_len, uint64_t block_count, void** db_out);

extern int32_t lith_txn_begin(void* db, void** txn_out);
extern int32_t lith_txn_commit(void* txn);
extern int32_t lith_txn_rollback(void* txn);

extern int32_t lith_query_execute(
    void* db,
    const char* query_str,
    uint64_t query_len,
    const char* provenance_json,
    uint64_t provenance_len,
    void** cursor_out
);

extern int32_t lith_cursor_next(
    void* cursor,
    char* document_json_out,
    uint64_t buffer_len,
    uint64_t* written_out
);

extern void lith_cursor_close(void* cursor);

// Status codes (matches Lith ABI)
#define STATUS_OK 0
#define STATUS_INVALID_ARG 1
#define STATUS_NOT_FOUND 2
#define STATUS_PERMISSION_DENIED 3
#define STATUS_ALREADY_EXISTS 4
#define STATUS_CONSTRAINT_VIOLATION 5
#define STATUS_TYPE_MISMATCH 6
#define STATUS_OUT_OF_MEMORY 7
#define STATUS_IO_ERROR 8
#define STATUS_CORRUPTION 9
#define STATUS_CONFLICT 10
#define STATUS_INTERNAL_ERROR 11

// Resource types for Erlang resource management
static ErlNifResourceType *LITH_DB_RESOURCE;
static ErlNifResourceType *LITH_TXN_RESOURCE;
static ErlNifResourceType *LITH_CURSOR_RESOURCE;

// Resource wrapper structures
typedef struct {
    void* handle;
} LithDbResource;

typedef struct {
    void* handle;
} LithTxnResource;

typedef struct {
    void* handle;
} LithCursorResource;

// Resource destructor for database
static void lith_db_resource_dtor(ErlNifEnv* env, void* obj) {
    LithDbResource* res = (LithDbResource*)obj;
    if (res->handle != NULL) {
        lith_close(res->handle);
        res->handle = NULL;
    }
}

// Resource destructor for transaction
static void lith_txn_resource_dtor(ErlNifEnv* env, void* obj) {
    LithTxnResource* res = (LithTxnResource*)obj;
    if (res->handle != NULL) {
        lith_txn_rollback(res->handle);  // Auto-rollback on GC
        res->handle = NULL;
    }
}

// Resource destructor for cursor
static void lith_cursor_resource_dtor(ErlNifEnv* env, void* obj) {
    LithCursorResource* res = (LithCursorResource*)obj;
    if (res->handle != NULL) {
        lith_cursor_close(res->handle);
        res->handle = NULL;
    }
}

// Helper: Convert status code to Erlang atom
// Convert status code to Gleam LithError atom
static ERL_NIF_TERM status_to_error_atom(ErlNifEnv* env, int32_t status) {
    switch (status) {
        case STATUS_INVALID_ARG: return enif_make_atom(env, "InvalidArg");
        case STATUS_NOT_FOUND: return enif_make_atom(env, "NotFound");
        case STATUS_PERMISSION_DENIED: return enif_make_atom(env, "PermissionDenied");
        case STATUS_ALREADY_EXISTS: return enif_make_atom(env, "AlreadyExists");
        case STATUS_CONSTRAINT_VIOLATION: return enif_make_atom(env, "ConstraintViolation");
        case STATUS_TYPE_MISMATCH: return enif_make_atom(env, "TypeMismatch");
        case STATUS_OUT_OF_MEMORY: return enif_make_atom(env, "OutOfMemory");
        case STATUS_IO_ERROR: return enif_make_atom(env, "IoError");
        case STATUS_CORRUPTION: return enif_make_atom(env, "Corruption");
        case STATUS_CONFLICT: return enif_make_atom(env, "Conflict");
        case STATUS_INTERNAL_ERROR:
        default: return enif_make_atom(env, "InternalError");
    }
}

// Convert status code to Gleam Result(Nil, LithError)
static ERL_NIF_TERM status_to_result(ErlNifEnv* env, int32_t status) {
    if (status == STATUS_OK) {
        // Return {ok, nil} for Gleam Result type
        return enif_make_tuple2(env,
            enif_make_atom(env, "ok"),
            enif_make_atom(env, "nil"));
    } else {
        // Return {error, ErrorAtom} for Gleam Result type
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            status_to_error_atom(env, status));
    }
}

////////////////////////////////////////////////////////////////////////////////
// NIF Functions
////////////////////////////////////////////////////////////////////////////////

// Initialize Lith
static ERL_NIF_TERM nif_lith_init(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    int32_t status = lith_init();
    return status_to_result(env, status);
}

// Open database: open(Path) -> {ok, DbRef} | {error, Reason}
static ERL_NIF_TERM nif_open(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary path_bin;

    if (!enif_inspect_binary(env, argv[0], &path_bin)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "badarg"));
    }

    LithDbResource* db_res = enif_alloc_resource(LITH_DB_RESOURCE, sizeof(LithDbResource));
    db_res->handle = NULL;

    int32_t status = lith_open((const char*)path_bin.data, path_bin.size, &db_res->handle);

    if (status == STATUS_OK && db_res->handle != NULL) {
        ERL_NIF_TERM db_term = enif_make_resource(env, db_res);
        enif_release_resource(db_res);
        return enif_make_tuple2(env, enif_make_atom(env, "ok"), db_term);
    } else {
        enif_release_resource(db_res);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            status_to_error_atom(env, status));
    }
}

// Create database: create(Path, BlockCount) -> {ok, DbRef} | {error, Reason}
static ERL_NIF_TERM nif_create(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary path_bin;
    uint64_t block_count;

    if (!enif_inspect_binary(env, argv[0], &path_bin) ||
        !enif_get_uint64(env, argv[1], &block_count)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "badarg"));
    }

    LithDbResource* db_res = enif_alloc_resource(LITH_DB_RESOURCE, sizeof(LithDbResource));
    db_res->handle = NULL;

    int32_t status = lith_create((const char*)path_bin.data, path_bin.size, block_count, &db_res->handle);

    if (status == STATUS_OK && db_res->handle != NULL) {
        ERL_NIF_TERM db_term = enif_make_resource(env, db_res);
        enif_release_resource(db_res);
        return enif_make_tuple2(env, enif_make_atom(env, "ok"), db_term);
    } else {
        enif_release_resource(db_res);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            status_to_error_atom(env, status));
    }
}

// Begin transaction: txn_begin(DbRef) -> {ok, TxnRef} | {error, Reason}
static ERL_NIF_TERM nif_txn_begin(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    LithDbResource* db_res;

    if (!enif_get_resource(env, argv[0], LITH_DB_RESOURCE, (void**)&db_res)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "badarg"));
    }

    LithTxnResource* txn_res = enif_alloc_resource(LITH_TXN_RESOURCE, sizeof(LithTxnResource));
    txn_res->handle = NULL;

    int32_t status = lith_txn_begin(db_res->handle, &txn_res->handle);

    if (status == STATUS_OK && txn_res->handle != NULL) {
        ERL_NIF_TERM txn_term = enif_make_resource(env, txn_res);
        enif_release_resource(txn_res);
        return enif_make_tuple2(env, enif_make_atom(env, "ok"), txn_term);
    } else {
        enif_release_resource(txn_res);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            status_to_error_atom(env, status));
    }
}

// Commit transaction: txn_commit(TxnRef) -> ok | {error, Reason}
static ERL_NIF_TERM nif_txn_commit(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    LithTxnResource* txn_res;

    if (!enif_get_resource(env, argv[0], LITH_TXN_RESOURCE, (void**)&txn_res)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "badarg"));
    }

    int32_t status = lith_txn_commit(txn_res->handle);

    if (status == STATUS_OK) {
        return enif_make_atom(env, "ok");
    } else {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            status_to_error_atom(env, status));
    }
}

// Execute query: query_execute(DbRef, QueryStr, ProvenanceJson) -> {ok, CursorRef} | {error, Reason}
static ERL_NIF_TERM nif_query_execute(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    LithDbResource* db_res;
    ErlNifBinary query_bin, prov_bin;

    if (!enif_get_resource(env, argv[0], LITH_DB_RESOURCE, (void**)&db_res) ||
        !enif_inspect_binary(env, argv[1], &query_bin) ||
        !enif_inspect_binary(env, argv[2], &prov_bin)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "badarg"));
    }

    LithCursorResource* cursor_res = enif_alloc_resource(LITH_CURSOR_RESOURCE, sizeof(LithCursorResource));
    cursor_res->handle = NULL;

    int32_t status = lith_query_execute(
        db_res->handle,
        (const char*)query_bin.data,
        query_bin.size,
        (const char*)prov_bin.data,
        prov_bin.size,
        &cursor_res->handle
    );

    if (status == STATUS_OK && cursor_res->handle != NULL) {
        ERL_NIF_TERM cursor_term = enif_make_resource(env, cursor_res);
        enif_release_resource(cursor_res);
        return enif_make_tuple2(env, enif_make_atom(env, "ok"), cursor_term);
    } else {
        enif_release_resource(cursor_res);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            status_to_error_atom(env, status));
    }
}

// Fetch next from cursor: cursor_next(CursorRef) -> {ok, JsonDoc} | done | {error, Reason}
static ERL_NIF_TERM nif_cursor_next(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    LithCursorResource* cursor_res;

    if (!enif_get_resource(env, argv[0], LITH_CURSOR_RESOURCE, (void**)&cursor_res)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "badarg"));
    }

    // Allocate buffer for JSON result (64KB should be enough for most documents)
    char buffer[65536];
    uint64_t written = 0;

    int32_t status = lith_cursor_next(cursor_res->handle, buffer, sizeof(buffer), &written);

    if (status == STATUS_OK) {
        ERL_NIF_TERM json_bin;
        unsigned char* bin_data = enif_make_new_binary(env, written, &json_bin);
        memcpy(bin_data, buffer, written);
        return enif_make_tuple2(env, enif_make_atom(env, "ok"), json_bin);
    } else if (status == STATUS_NOT_FOUND) {
        return enif_make_atom(env, "done");
    } else {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            status_to_error_atom(env, status));
    }
}

////////////////////////////////////////////////////////////////////////////////
// NIF Module Setup
////////////////////////////////////////////////////////////////////////////////

static ErlNifFunc nif_funcs[] = {
    {"init", 0, nif_lith_init},
    {"open", 1, nif_open},
    {"create", 2, nif_create},
    {"txn_begin", 1, nif_txn_begin},
    {"txn_commit", 1, nif_txn_commit},
    {"query_execute", 3, nif_query_execute},
    {"cursor_next", 1, nif_cursor_next}
};

static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    // Create resource types
    LITH_DB_RESOURCE = enif_open_resource_type(
        env, NULL, "lith_db", lith_db_resource_dtor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER, NULL);

    LITH_TXN_RESOURCE = enif_open_resource_type(
        env, NULL, "lith_txn", lith_txn_resource_dtor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER, NULL);

    LITH_CURSOR_RESOURCE = enif_open_resource_type(
        env, NULL, "lith_cursor", lith_cursor_resource_dtor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER, NULL);

    if (LITH_DB_RESOURCE == NULL || LITH_TXN_RESOURCE == NULL || LITH_CURSOR_RESOURCE == NULL) {
        return -1;
    }

    return 0;
}

ERL_NIF_INIT(lith_nif, nif_funcs, load, NULL, NULL, NULL)
