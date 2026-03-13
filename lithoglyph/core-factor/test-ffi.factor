! SPDX-License-Identifier: PMPL-1.0-or-later
! Test FFI bindings to Lithoglyph bridge

USING: io io.encodings.utf8 io.files kernel sequences storage-backend ;

IN: test-ffi

! Test 1: Initialize in-memory backend (should work)
: test-memory-backend ( -- )
    "=== Test 1: Memory Backend ===" print
    use-memory-storage
    "users" V{ } clone storage-set-collection
    "users" storage-get-collection length .
    "✅ Memory backend works\n" print ;

! Test 2: Initialize bridge backend
: test-bridge-backend ( -- )
    "=== Test 2: Bridge Backend (FFI) ===" print
    "test-ffi.lgh" use-bridge-storage
    storage-list-collections .
    "✅ Bridge backend initialized\n" print ;

! Test 3: Insert document
: test-insert ( -- )
    "=== Test 3: Insert Document ===" print
    H{
        { "name" "Alice" }
        { "email" "alice@example.com" }
    } "users" storage-insert .
    "✅ Document inserted\n" print ;

! Run all tests
: run-ffi-tests ( -- )
    [
        test-memory-backend
        test-bridge-backend
        test-insert
        close-backend
        "All tests completed!\n" print
    ] [
        "Test failed: " write print
    ] recover ;
