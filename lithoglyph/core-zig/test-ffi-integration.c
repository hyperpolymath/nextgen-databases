/* SPDX-License-Identifier: PMPL-1.0-or-later */
/* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk> */
/*
 * FFI Integration Tests — Tests the Zig bridge from C
 *
 * Exercises the complete FFI surface defined in generated/abi/bridge.h,
 * simulating what Factor/Forth/BEAM runtimes do when calling the bridge.
 *
 * Compile:
 *   cc -I../generated/abi -o test-ffi test-ffi-integration.c -L. -lbridge
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bridge.h"

/* ============================================================
 * Test Helpers
 * ============================================================ */

static int test_count = 0;
static int pass_count = 0;
static int fail_count = 0;

#define RUN_TEST(fn) do { \
    test_count++; \
    printf("=== Test %d: %s ===\n", test_count, #fn); \
    if (fn() == 0) { \
        pass_count++; \
        printf("PASS: %s\n\n", #fn); \
    } else { \
        fail_count++; \
        printf("FAIL: %s\n\n", #fn); \
    } \
} while(0)

static void print_blob(const char* label, const LgBlob* blob) {
    printf("  %s: ", label);
    if (blob->ptr && blob->len > 0) {
        printf("%.*s\n", (int)blob->len, (const char*)blob->ptr);
    } else {
        printf("(empty)\n");
    }
}

static void free_blob(LgBlob* blob) {
    if (blob->ptr) {
        fdb_blob_free(blob);
    }
}

/* Open a test database, return 0 on success */
static int open_test_db(const char* name, FdbDb** db, LgBlob* err) {
    FdbStatus s = fdb_db_open(
        (const uint8_t*)name, strlen(name),
        NULL, 0,
        db, err
    );
    if (s != FDB_OK) {
        print_blob("open error", err);
        free_blob(err);
        return 1;
    }
    return 0;
}

/* ============================================================
 * Test 1: Version
 * ============================================================ */
static int test_version(void) {
    uint32_t v = fdb_version();
    printf("  version = %u (expected 100 = 0.1.0)\n", v);
    return (v == 100) ? 0 : 1;
}

/* ============================================================
 * Test 2: Database Lifecycle (open + close)
 * ============================================================ */
static int test_database_lifecycle(void) {
    FdbDb* db = NULL;
    LgBlob err = {0};

    if (open_test_db("test-ffi.lgh", &db, &err)) return 1;
    printf("  db handle: %p\n", (void*)db);

    FdbStatus s = fdb_db_close(db);
    return (s == FDB_OK) ? 0 : 1;
}

/* ============================================================
 * Test 3: Transaction begin + commit (empty)
 * ============================================================ */
static int test_transactions(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-txn.lgh", &db, &err)) return 1;

    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { print_blob("begin error", &err); free_blob(&err); fdb_db_close(db); return 1; }
    printf("  txn handle: %p\n", (void*)txn);

    s = fdb_txn_commit(txn, &err);
    if (s != FDB_OK) { print_blob("commit error", &err); free_blob(&err); fdb_db_close(db); return 1; }

    fdb_db_close(db);
    return 0;
}

/* ============================================================
 * Test 4: Transaction abort
 * ============================================================ */
static int test_txn_abort(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-abort.lgh", &db, &err)) return 1;

    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    /* Apply something then abort — should not persist */
    const char* op = "{\"op\":\"insert\",\"doc\":{\"tmp\":true}}";
    LgResult r = fdb_apply(txn, (const uint8_t*)op, strlen(op));
    printf("  apply status before abort: %d\n", r.status);
    free_blob(&r.data);
    free_blob(&r.error_blob);

    s = fdb_txn_abort(txn);
    printf("  abort status: %d\n", s);

    fdb_db_close(db);
    return (s == FDB_OK) ? 0 : 1;
}

/* ============================================================
 * Test 5: Apply operation (read-write, buffered)
 * ============================================================ */
static int test_apply_readwrite(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-apply-rw.lgh", &db, &err)) return 1;

    /* Must use read-write mode for apply */
    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* op = "{\"op\":\"insert\",\"collection\":\"users\",\"doc\":{\"name\":\"Alice\"}}";
    LgResult result = fdb_apply(txn, (const uint8_t*)op, strlen(op));

    printf("  result status: %d (expected 0 = OK)\n", result.status);
    print_blob("result data", &result.data);

    int ok = (result.status == FDB_OK);
    free_blob(&result.data);
    free_blob(&result.error_blob);

    s = fdb_txn_commit(txn, &err);
    free_blob(&err);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Test 6: Apply + commit + read_blocks (round-trip)
 * ============================================================ */
static int test_apply_commit_readback(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-roundtrip.lgh", &db, &err)) return 1;

    /* Insert a document */
    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* doc = "{\"name\":\"Bob\",\"age\":30}";
    LgResult r = fdb_apply(txn, (const uint8_t*)doc, strlen(doc));
    free_blob(&r.data);
    free_blob(&r.error_blob);

    s = fdb_txn_commit(txn, &err);
    free_blob(&err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    /* Read back all document blocks */
    LgBlob data = {0};
    LgBlob read_err = {0};
    s = fdb_read_blocks(db, LG_BLOCK_TYPE_DOCUMENT, &data, &read_err);
    printf("  read_blocks status: %d\n", s);
    print_blob("blocks", &data);

    int ok = (s == FDB_OK && data.ptr != NULL && data.len > 2); /* more than "[]" */
    free_blob(&data);
    free_blob(&read_err);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Test 7: Update block
 * ============================================================ */
static int test_update_block(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-update.lgh", &db, &err)) return 1;

    /* Insert first */
    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* doc1 = "{\"version\":1}";
    LgResult r = fdb_apply(txn, (const uint8_t*)doc1, strlen(doc1));
    /* Parse block_id from result — for simplicity, use block_id=1 (first allocation) */
    free_blob(&r.data);
    free_blob(&r.error_blob);

    s = fdb_txn_commit(txn, &err);
    free_blob(&err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    /* Update the block */
    s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* doc2 = "{\"version\":2}";
    LgBlob update_err = {0};
    s = fdb_update_block(txn, 1, (const uint8_t*)doc2, strlen(doc2), &update_err);
    printf("  update_block status: %d\n", s);

    int ok = (s == FDB_OK);
    free_blob(&update_err);

    LgBlob commit_err = {0};
    fdb_txn_commit(txn, &commit_err);
    free_blob(&commit_err);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Test 8: Delete block
 * ============================================================ */
static int test_delete_block(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-delete.lgh", &db, &err)) return 1;

    /* Insert a block */
    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* doc = "{\"delete_me\":true}";
    LgResult r = fdb_apply(txn, (const uint8_t*)doc, strlen(doc));
    free_blob(&r.data);
    free_blob(&r.error_blob);
    fdb_txn_commit(txn, &err);
    free_blob(&err);

    /* Delete the block */
    s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    LgBlob del_err = {0};
    s = fdb_delete_block(txn, 1, &del_err);
    printf("  delete_block status: %d\n", s);

    int ok = (s == FDB_OK);
    free_blob(&del_err);

    LgBlob commit_err = {0};
    fdb_txn_commit(txn, &commit_err);
    free_blob(&commit_err);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Test 9: Read blocks by type
 * ============================================================ */
static int test_read_blocks_by_type(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-read-type.lgh", &db, &err)) return 1;

    /* Insert some documents */
    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* docs[] = {
        "{\"item\":\"alpha\"}",
        "{\"item\":\"beta\"}",
        "{\"item\":\"gamma\"}",
    };
    for (int i = 0; i < 3; i++) {
        LgResult r = fdb_apply(txn, (const uint8_t*)docs[i], strlen(docs[i]));
        free_blob(&r.data);
        free_blob(&r.error_blob);
    }
    fdb_txn_commit(txn, &err);
    free_blob(&err);

    /* Read by document type */
    LgBlob data = {0};
    LgBlob read_err = {0};
    s = fdb_read_blocks(db, LG_BLOCK_TYPE_DOCUMENT, &data, &read_err);
    printf("  read_blocks (type 0x0011) status: %d\n", s);
    print_blob("blocks", &data);

    int ok = (s == FDB_OK && data.ptr != NULL);
    free_blob(&data);
    free_blob(&read_err);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Test 10: Render block
 * ============================================================ */
static int test_render_block(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-render-block.lgh", &db, &err)) return 1;

    /* Insert a document */
    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* doc = "{\"rendered\":true}";
    LgResult r = fdb_apply(txn, (const uint8_t*)doc, strlen(doc));
    free_blob(&r.data);
    free_blob(&r.error_blob);
    fdb_txn_commit(txn, &err);
    free_blob(&err);

    /* Render block 1 */
    LgBlob text = {0};
    LgBlob render_err = {0};
    LgRenderOpts opts = { .format = 0, .include_metadata = false };
    s = fdb_render_block(db, 1, opts, &text, &render_err);
    printf("  render_block status: %d\n", s);
    print_blob("rendered", &text);

    int ok = (s == FDB_OK && text.ptr != NULL);
    free_blob(&text);
    free_blob(&render_err);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Test 11: Render journal
 * ============================================================ */
static int test_render_journal(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-render-journal.lgh", &db, &err)) return 1;

    /* Insert something to generate journal entries */
    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_WRITE, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* doc = "{\"journaled\":true}";
    LgResult r = fdb_apply(txn, (const uint8_t*)doc, strlen(doc));
    free_blob(&r.data);
    free_blob(&r.error_blob);
    fdb_txn_commit(txn, &err);
    free_blob(&err);

    /* Render journal since sequence 0 */
    LgBlob text = {0};
    LgBlob journal_err = {0};
    LgRenderOpts opts = { .format = 0, .include_metadata = false };
    s = fdb_render_journal(db, 0, opts, &text, &journal_err);
    printf("  render_journal status: %d\n", s);
    print_blob("journal", &text);

    int ok = (s == FDB_OK && text.ptr != NULL);
    free_blob(&text);
    free_blob(&journal_err);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Test 12: Introspection (schema + constraints)
 * ============================================================ */
static int test_introspection(void) {
    FdbDb* db = NULL;
    LgBlob err = {0};

    if (open_test_db("test-intro.lgh", &db, &err)) return 1;

    /* Schema */
    LgBlob schema = {0};
    FdbStatus s = fdb_introspect_schema(db, &schema, &err);
    printf("  schema status: %d\n", s);
    print_blob("schema", &schema);
    free_blob(&schema);
    free_blob(&err);

    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    /* Constraints */
    LgBlob constraints = {0};
    LgBlob c_err = {0};
    s = fdb_introspect_constraints(db, &constraints, &c_err);
    printf("  constraints status: %d\n", s);
    print_blob("constraints", &constraints);
    free_blob(&constraints);
    free_blob(&c_err);

    fdb_db_close(db);
    return (s == FDB_OK) ? 0 : 1;
}

/* ============================================================
 * Test 13: Proof init builtins
 * ============================================================ */
static int test_proof_init_builtins(void) {
    FdbStatus s = fdb_proof_init_builtins();
    printf("  init_builtins status: %d\n", s);
    return (s == FDB_OK) ? 0 : 1;
}

/* ============================================================
 * Test 14: Proof register + unregister verifier
 * ============================================================ */
static FdbStatus dummy_verifier(const uint8_t* proof, size_t len, void* ctx) {
    (void)proof; (void)len; (void)ctx;
    return FDB_OK;
}

static int test_proof_register_unregister(void) {
    const char* type_name = "test-verifier";
    FdbStatus s = fdb_proof_register_verifier(
        (const uint8_t*)type_name, strlen(type_name),
        dummy_verifier, NULL
    );
    printf("  register status: %d\n", s);
    if (s != FDB_OK) return 1;

    s = fdb_proof_unregister_verifier(
        (const uint8_t*)type_name, strlen(type_name)
    );
    printf("  unregister status: %d\n", s);
    if (s != FDB_OK) return 1;

    /* Unregister again should fail with NOT_FOUND */
    s = fdb_proof_unregister_verifier(
        (const uint8_t*)type_name, strlen(type_name)
    );
    printf("  double-unregister status: %d (expected %d = NOT_FOUND)\n", s, FDB_ERR_NOT_FOUND);
    return (s == FDB_ERR_NOT_FOUND) ? 0 : 1;
}

/* ============================================================
 * Test 15: Proof verify
 * ============================================================ */
static int test_proof_verify(void) {
    /* Ensure builtins are registered */
    fdb_proof_init_builtins();

    const char* proof_json = "{\"type\":\"fd-holds\",\"data\":\"dGVzdA==\"}";
    bool valid = false;
    LgBlob err = {0};

    FdbStatus s = fdb_proof_verify(
        (const uint8_t*)proof_json, strlen(proof_json),
        &valid, &err
    );
    printf("  verify status: %d, valid: %s\n", s, valid ? "true" : "false");
    free_blob(&err);

    return (s == FDB_OK && valid) ? 0 : 1;
}

/* ============================================================
 * Test 16: Blob free on NULL (null safety)
 * ============================================================ */
static int test_blob_free_null(void) {
    LgBlob empty = { .ptr = NULL, .len = 0 };
    /* Should not crash */
    fdb_blob_free(&empty);
    printf("  blob_free(NULL) did not crash\n");
    return 0;
}

/* ============================================================
 * Test 17: Apply on read-only transaction (should fail)
 * ============================================================ */
static int test_apply_readonly_rejected(void) {
    FdbDb* db = NULL;
    FdbTxn* txn = NULL;
    LgBlob err = {0};

    if (open_test_db("test-ro.lgh", &db, &err)) return 1;

    FdbStatus s = fdb_txn_begin(db, LG_TXN_READ_ONLY, &txn, &err);
    if (s != FDB_OK) { fdb_db_close(db); return 1; }

    const char* op = "{\"op\":\"insert\",\"doc\":{\"x\":1}}";
    LgResult result = fdb_apply(txn, (const uint8_t*)op, strlen(op));

    printf("  apply on read-only status: %d (expected non-zero)\n", result.status);
    int ok = (result.status != FDB_OK); /* should be rejected */

    free_blob(&result.data);
    free_blob(&result.error_blob);
    fdb_txn_abort(txn);
    fdb_db_close(db);

    return ok ? 0 : 1;
}

/* ============================================================
 * Main
 * ============================================================ */
int main(void) {
    printf("======================================\n");
    printf("Lithoglyph FFI Integration Tests\n");
    printf("(using generated/abi/bridge.h)\n");
    printf("======================================\n\n");

    RUN_TEST(test_version);
    RUN_TEST(test_database_lifecycle);
    RUN_TEST(test_transactions);
    RUN_TEST(test_txn_abort);
    RUN_TEST(test_apply_readwrite);
    RUN_TEST(test_apply_commit_readback);
    RUN_TEST(test_update_block);
    RUN_TEST(test_delete_block);
    RUN_TEST(test_read_blocks_by_type);
    RUN_TEST(test_render_block);
    RUN_TEST(test_render_journal);
    RUN_TEST(test_introspection);
    RUN_TEST(test_proof_init_builtins);
    RUN_TEST(test_proof_register_unregister);
    RUN_TEST(test_proof_verify);
    RUN_TEST(test_blob_free_null);
    RUN_TEST(test_apply_readonly_rejected);

    printf("======================================\n");
    printf("Results: %d/%d passed", pass_count, test_count);
    if (fail_count > 0) {
        printf(" (%d FAILED)", fail_count);
    }
    printf("\n======================================\n");

    return fail_count;
}
