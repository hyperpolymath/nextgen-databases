// SPDX-License-Identifier: PMPL-1.0-or-later
// Test database open

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef struct {
    const uint8_t* ptr;
    size_t len;
} LgBlob;

extern int fdb_version(void);
extern int fdb_db_open(const uint8_t* path, size_t path_len, const uint8_t* opts, size_t opts_len, void** out_db, LgBlob* out_err);
extern void fdb_db_close(void* db);

int main() {
    printf("Version: %d\n", fdb_version());

    const char* path = "test-simple.lgh";
    void* db = NULL;
    LgBlob err = {.ptr = NULL, .len = 0};

    printf("Opening database: %s\n", path);
    printf("  path ptr: %p\n", (void*)path);
    printf("  path len: %zu\n", strlen(path));
    printf("  db ptr address: %p\n", (void*)&db);
    printf("  err ptr address: %p\n", (void*)&err);

    int status = fdb_db_open((const uint8_t*)path, strlen(path), NULL, 0, &db, &err);

    printf("Status: %d\n", status);
    printf("DB handle: %p\n", db);
    printf("Error ptr: %p, len: %zu\n", (void*)err.ptr, err.len);

    if (err.ptr && err.len > 0) {
        printf("Error: %.*s\n", (int)err.len, err.ptr);
    }

    if (db) {
        printf("Closing database\n");
        fdb_db_close(db);
    }

    return status;
}
