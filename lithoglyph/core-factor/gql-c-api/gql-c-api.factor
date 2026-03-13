! SPDX-License-Identifier: PMPL-1.0-or-later
! gql-c-api - C API for GQL Runtime
!
! Exports C-callable functions for integration with Zig FFI

USING: accessors alien alien.c-types alien.data alien.strings arrays
assocs byte-arrays classes.struct combinators continuations gql
formatting hashtables io io.encodings.utf8 json json.writer kernel
locals math namespaces sequences splitting storage-backend strings ;

IN: gql-c-api

! ============================================================
! C API Structures
! ============================================================

STRUCT: c-string-result
    { data char* }
    { length size_t }
    { status int32_t } ;

! Status codes matching LithStatus in bridge.zig
CONSTANT: STATUS_OK 0
CONSTANT: STATUS_INVALID_ARG 1
CONSTANT: STATUS_NOT_FOUND 2
CONSTANT: STATUS_PERMISSION_DENIED 3
CONSTANT: STATUS_ALREADY_EXISTS 4
CONSTANT: STATUS_CONSTRAINT_VIOLATION 5
CONSTANT: STATUS_TYPE_MISMATCH 6
CONSTANT: STATUS_OUT_OF_MEMORY 7
CONSTANT: STATUS_IO_ERROR 8
CONSTANT: STATUS_CORRUPTION 9
CONSTANT: STATUS_CONFLICT 10
CONSTANT: STATUS_INTERNAL_ERROR 11

! ============================================================
! Utilities
! ============================================================

: factor>json-string ( obj -- str )
    >json utf8 encode >string ;

: hashtable>json ( hash -- str )
    >json ;

:: make-c-result ( str status -- result )
    c-string-result malloc-struct
        str utf8 string>alien >>data
        str length >>length
        status >>status ;

: make-error-result ( status msg -- result )
    swap
    H{
        { "status" "error" }
    } clone
    [ "message" ] dip [ set-at ] keep
    hashtable>json
    swap make-c-result ;

! ============================================================
! C API Functions
! ============================================================

! Initialize GQL runtime
:: c_gql_init ( -- status )
    [
        use-memory-storage
        STATUS_OK
    ] [
        drop STATUS_INTERNAL_ERROR
    ] recover ;

! Initialize with persistent storage path
:: c_gql_init_with_path ( path -- status )
    [
        path utf8 alien>string use-bridge-storage
        STATUS_OK
    ] [
        drop STATUS_INTERNAL_ERROR
    ] recover ;

! Execute GQL query and return JSON result
:: c_gql_execute ( query_str -- result )
    [
        ! Convert C string to Factor string
        query_str utf8 alien>string :> query

        ! Parse and execute
        query run-gql :> result-hash

        ! Convert result to JSON
        result-hash hashtable>json STATUS_OK make-c-result
    ] [
        | err |
        ! Error handling
        STATUS_INTERNAL_ERROR
        err error-summary
        make-error-result
    ] recover ;

! Free C result
:: c_gql_free_result ( result -- )
    result data>> [ free ] when*
    result free ;

! Close GQL runtime
:: c_gql_close ( -- status )
    [
        close-backend
        STATUS_OK
    ] [
        drop STATUS_INTERNAL_ERROR
    ] recover ;

! ============================================================
! Query Plan API
! ============================================================

! Get query plan without executing
:: c_gql_explain ( query_str -- result )
    [
        query_str utf8 alien>string :> query
        query explain-gql :> plan-hash
        plan-hash hashtable>json STATUS_OK make-c-result
    ] [
        | err |
        STATUS_INTERNAL_ERROR
        err error-summary
        make-error-result
    ] recover ;

! Get query plan with execution timing
:: c_gql_explain_analyze ( query_str -- result )
    [
        query_str utf8 alien>string :> query
        query explain-analyze-gql :> plan-hash
        plan-hash hashtable>json STATUS_OK make-c-result
    ] [
        | err |
        STATUS_INTERNAL_ERROR
        err error-summary
        make-error-result
    ] recover ;

! ============================================================
! Collection Management API
! ============================================================

! List all collections
:: c_gql_list_collections ( -- result )
    [
        storage-list-collections >array :> collections
        H{
            { "status" "ok" }
            { "collections" collections }
        } hashtable>json STATUS_OK make-c-result
    ] [
        | err |
        STATUS_INTERNAL_ERROR
        err error-summary
        make-error-result
    ] recover ;

! Get collection schema
:: c_gql_get_schema ( collection_name -- result )
    [
        collection_name utf8 alien>string :> coll
        coll storage-get-collection :> docs
        docs first [ keys >array ] [ { } ] if* :> fields
        H{
            { "status" "ok" }
            { "collection" coll }
            { "fields" fields }
        } hashtable>json STATUS_OK make-c-result
    ] [
        | err |
        STATUS_NOT_FOUND
        err error-summary
        make-error-result
    ] recover ;
