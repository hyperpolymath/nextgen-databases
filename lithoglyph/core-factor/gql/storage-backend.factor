! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Runtime - Storage Backend Abstraction
!
! Pluggable storage layer for GQL executor.
! - memory: In-memory storage (default, for testing)
! - bridge: Persistent storage via Form.Bridge (production)

USING: accessors alien alien.c-types alien.data alien.libraries alien.strings
arrays assocs byte-arrays classes.struct combinators formatting hashtables
io io.encodings.utf8 json.reader json.writer kernel locals math namespaces
sequences strings vectors ;

IN: storage-backend

! ============================================================
! Lithoglyph Bridge FFI Library
! ============================================================

<< "lithoglyph-bridge" {
    { [ os linux? ] [ "libbridge.so" ] }
    { [ os macosx? ] [ "libbridge.dylib" ] }
    { [ os windows? ] [ "bridge.dll" ] }
} cond cdecl add-library >>

! ============================================================
! Storage Backend Protocol
! ============================================================

MIXIN: storage-backend

GENERIC: backend-init ( backend -- )
GENERIC: backend-close ( backend -- )
GENERIC: backend-get-collection ( name backend -- data )
GENERIC: backend-set-collection ( data name backend -- )
GENERIC: backend-list-collections ( backend -- names )
GENERIC: backend-delete-collection ( name backend -- )
GENERIC: backend-insert ( doc collection backend -- id )
GENERIC: backend-update ( doc id collection backend -- success? )
GENERIC: backend-delete ( id collection backend -- success? )
GENERIC: backend-query ( collection backend -- rows )

! ============================================================
! In-Memory Backend (Default)
! ============================================================

TUPLE: memory-backend
    collections
    next-id ;

: <memory-backend> ( -- backend )
    memory-backend new
        H{ } clone >>collections
        1 >>next-id ;

INSTANCE: memory-backend storage-backend

M: memory-backend backend-init
    drop ;

M: memory-backend backend-close
    drop ;

M: memory-backend backend-get-collection
    collections>> at [ V{ } clone ] unless* ;

M: memory-backend backend-set-collection
    collections>> set-at ;

M: memory-backend backend-list-collections
    collections>> keys ;

M: memory-backend backend-delete-collection
    collections>> delete-at ;

M:: memory-backend backend-insert ( doc collection backend -- id )
    backend next-id>> :> id
    id 1 + backend next-id<<
    ! Add id to document
    id number>string "_id" doc set-at
    ! Get or create collection
    collection backend backend-get-collection :> coll
    doc coll push
    coll collection backend backend-set-collection
    id ;

M:: memory-backend backend-update ( doc id collection backend -- success? )
    collection backend backend-get-collection :> coll
    f :> found!
    coll [
        dup "_id" swap at id number>string = [
            drop doc t found!
        ] when
    ] map collection backend backend-set-collection
    found ;

M:: memory-backend backend-delete ( id collection backend -- success? )
    collection backend backend-get-collection :> coll
    coll [
        "_id" swap at id number>string = not
    ] filter :> new-coll
    new-coll length coll length < :> deleted?
    new-coll collection backend backend-set-collection
    deleted? ;

M: memory-backend backend-query
    backend-get-collection ;

! ============================================================
! Bridge Backend (Persistent Storage)
! ============================================================

! FFI type definitions matching generated/abi/bridge.h
STRUCT: lith-blob
    { ptr void* }
    { len size_t } ;

! LgResult — matches bridge.h LgResult struct layout
STRUCT: lith-result
    { data lith-blob }
    { provenance lith-blob }
    { status int }
    { error_blob lith-blob } ;

! LgRenderOpts — matches bridge.h
STRUCT: lg-render-opts
    { format int }
    { include_metadata bool } ;

! Status codes matching bridge.h LithStatus enum
CONSTANT: LITH_OK 0
CONSTANT: LITH_ERR_INTERNAL 1
CONSTANT: LITH_ERR_NOT_FOUND 2
CONSTANT: LITH_ERR_INVALID_ARGUMENT 3
CONSTANT: LITH_ERR_OUT_OF_MEMORY 4
CONSTANT: LITH_ERR_NOT_IMPLEMENTED 5
CONSTANT: LITH_ERR_TXN_NOT_ACTIVE 6
CONSTANT: LITH_ERR_TXN_ALREADY_COMMITTED 7
CONSTANT: LITH_ERR_IO_ERROR 8
CONSTANT: LITH_ERR_CORRUPTION 9
CONSTANT: LITH_ERR_CONFLICT 10
CONSTANT: LITH_ERR_ALREADY_EXISTS 11

! Transaction mode constants matching bridge.h LgTxnMode
CONSTANT: LG_TXN_READ_ONLY 0
CONSTANT: LG_TXN_READ_WRITE 1

! ============================================================
! FFI Function Declarations (from generated/abi/bridge.h)
! ============================================================

LIBRARY: lithoglyph-bridge

! Database lifecycle
FUNCTION: int lith_db_open ( void* path ulong path_len void* opts ulong opts_len void** out_db lith-blob* out_err )
FUNCTION: int lith_db_close ( void* db )
FUNCTION: uint lith_version ( )

! Transaction management
FUNCTION: int lith_txn_begin ( void* db int mode void** out_txn lith-blob* out_err )
FUNCTION: int lith_txn_commit ( void* txn lith-blob* out_err )
FUNCTION: int lith_txn_abort ( void* txn )

! Operations (buffered until commit)
FUNCTION: lith-result lith_apply ( void* txn void* op ulong op_len )
FUNCTION: int lith_update_block ( void* txn ulong block_id void* data ulong data_len lith-blob* out_err )
FUNCTION: int lith_delete_block ( void* txn ulong block_id lith-blob* out_err )

! Query (full block scan)
FUNCTION: int lith_read_blocks ( void* db ushort block_type lith-blob* out_data lith-blob* out_err )

! Introspection
FUNCTION: int lith_introspect_schema ( void* db lith-blob* out_schema lith-blob* out_err )
FUNCTION: int lith_introspect_constraints ( void* db lith-blob* out_constraints lith-blob* out_err )
FUNCTION: int lith_render_journal ( void* db ulong since lg-render-opts opts lith-blob* out_text lith-blob* out_err )
FUNCTION: int lith_render_block ( void* db ulong block_id lg-render-opts opts lith-blob* out_text lith-blob* out_err )

! Proof verification
FUNCTION: int lith_proof_register_verifier ( void* type_ptr ulong type_len void* callback void* context )
FUNCTION: int lith_proof_unregister_verifier ( void* type_ptr ulong type_len )
FUNCTION: int lith_proof_verify ( void* proof_ptr ulong proof_len bool* out_valid lith-blob* out_err )
FUNCTION: int lith_proof_init_builtins ( )

! Resource cleanup
FUNCTION: void lith_blob_free ( lith-blob* blob )

! ============================================================
! FFI Helper Functions
! ============================================================

: make-lith-blob ( -- blob )
    lith-blob malloc-struct
        f >>ptr
        0 >>len ;

: blob>string ( blob -- str/f )
    dup [ ptr>> ] [ len>> ] bi over [
        memory>byte-array utf8 decode
    ] [ 2drop f ] if ;

: string>lith-input ( str -- ptr len )
    utf8 encode [ underlying>> ] [ length ] bi ;

: check-lith-status ( status err-blob -- )
    swap LITH_OK = [
        drop
    ] [
        blob>string "FFI Error: %s\n" sprintf throw
    ] if ;

! Block type constant for documents (0x0011)
CONSTANT: BLOCK_TYPE_DOCUMENT 0x0011

! Parse JSON array of block results into Factor vector of hashtables.
! Input: JSON string like [{"block_id":1,"size":42,"data":"..."},...]
! Output: Vector of hashtables (the "data" field is parsed as JSON if possible)
: parse-block-results ( json-str -- vec )
    json> dup array? [
        >vector
        [
            dup hashtable? [
                ! Try to parse the "data" field as JSON
                dup "data" swap at [
                    [ json> ] [ drop f ] recover
                    dup hashtable? [
                        ! Successfully parsed document JSON
                        swap "data" pick set-at
                    ] [ drop ] if
                ] when*
            ] when
        ] map
    ] [ drop V{ } clone ] if ;

! ============================================================
! Bridge Transaction Helper
! ============================================================

! Execute a single-operation transaction: begin → apply → commit
! Returns the block ID from lith_apply result, or 0 on failure.
: with-bridge-txn ( doc-json backend -- block-id )
    db-handle>> :> db
    f :> txn-handle!
    make-lith-blob :> err-blob

    ! Begin read-write transaction (mode 1 = read-write)
    db LG_TXN_READ_WRITE txn-handle! err-blob lith_txn_begin
    err-blob check-lith-status

    ! Apply the operation (buffered, not written until commit)
    swap string>lith-input [
        txn-handle lith_apply
    ] 2keep 2drop :> result

    ! Commit transaction (WAL: journal → sync → blocks → sync)
    txn-handle err-blob lith_txn_commit
    err-blob check-lith-status

    ! Extract block_id from result (JSON: {"block_id":N,"status":"pending"})
    result data>> blob>string [
        json> dup hashtable? [
            "block_id" swap at [ 0 ] unless*
        ] [ drop 0 ] if
    ] [ 0 ] if* ;

! ============================================================
! Bridge Backend Tuple
! ============================================================

TUPLE: bridge-backend
    db-handle
    db-path
    is-open ;

: <bridge-backend> ( path -- backend )
    bridge-backend new
        swap >>db-path
        f >>db-handle
        f >>is-open ;

INSTANCE: bridge-backend storage-backend

! Bridge backend methods - FFI implementations

M:: backend-init ( backend -- ) bridge-backend
    backend db-path>> :> path
    f :> db-handle!
    make-lith-blob :> err-blob

    path string>lith-input f 0 { void* } [
        db-handle! err-blob lith_db_open
    ] with-out-parameters

    err-blob check-lith-status
    db-handle backend db-handle<<
    t backend is-open<<
    "Database opened: %s\n" path sprintf print ;

M:: bridge-backend backend-close ( backend -- )
    backend is-open>> backend db-handle>> and [
        backend db-handle>> lith_db_close
        f backend db-handle<<
        f backend is-open<<
        "Database closed\n" print
    ] when ;

M:: bridge-backend backend-get-collection ( name backend -- data )
    backend db-handle>> [
        make-lith-blob :> data-blob
        make-lith-blob :> err-blob

        ! Read all document blocks via lith_read_blocks (type = 0x0011)
        backend db-handle>> BLOCK_TYPE_DOCUMENT data-blob err-blob lith_read_blocks
        err-blob check-lith-status

        ! Parse JSON result into vector of documents
        data-blob blob>string [ "[]" ] unless*
        parse-block-results

        ! Free the blob
        data-blob lith_blob_free
    ] [ V{ } clone ] if ;

M:: bridge-backend backend-set-collection ( data name backend -- )
    backend db-handle>> [
        ! Insert each document via individual transactions
        data [
            >json backend with-bridge-txn drop
        ] each
    ] when ;

M:: bridge-backend backend-list-collections ( backend -- names )
    backend db-handle>> [
        make-lith-blob :> schema-blob
        make-lith-blob :> err-blob

        backend db-handle>> schema-blob err-blob lith_introspect_schema
        err-blob check-lith-status

        ! Parse JSON schema and extract collection names
        schema-blob blob>string [ "{\"version\":0,\"collections\":[]}" ] unless*
        json> dup hashtable? [
            "collections" swap at [ { } ] unless*
        ] [ drop { } ] if

        schema-blob lith_blob_free
    ] [ { } ] if ;

M:: bridge-backend backend-delete-collection ( name backend -- )
    backend db-handle>> [
        ! Read all blocks and delete those matching the collection
        ! (For PoC, collection filtering is not yet implemented at block level)
        "Bridge backend: delete-collection %s (requires collection metadata)\n"
        name sprintf print
    ] when ;

M:: bridge-backend backend-insert ( doc collection backend -- id )
    backend db-handle>> [
        ! Serialize document to JSON for storage
        doc >json :> doc-json

        ! Execute insert through bridge transaction
        doc-json backend with-bridge-txn
    ] [ 0 ] if ;

M:: bridge-backend backend-update ( doc id collection backend -- success? )
    backend db-handle>> [
        f :> txn-handle!
        make-lith-blob :> err-blob

        ! Begin read-write transaction
        backend db-handle>> LG_TXN_READ_WRITE txn-handle! err-blob lith_txn_begin
        err-blob check-lith-status

        ! Serialize new document data
        doc >json :> doc-json
        doc-json string>lith-input :> ( data-ptr data-len )

        ! Update the block
        txn-handle id data-ptr data-len err-blob lith_update_block
        err-blob check-lith-status

        ! Commit
        txn-handle err-blob lith_txn_commit
        err-blob check-lith-status
        t
    ] [ f ] if ;

M:: bridge-backend backend-delete ( id collection backend -- success? )
    backend db-handle>> [
        f :> txn-handle!
        make-lith-blob :> err-blob

        ! Begin read-write transaction
        backend db-handle>> LG_TXN_READ_WRITE txn-handle! err-blob lith_txn_begin
        err-blob check-lith-status

        ! Delete the block
        txn-handle id err-blob lith_delete_block
        err-blob check-lith-status

        ! Commit
        txn-handle err-blob lith_txn_commit
        err-blob check-lith-status
        t
    ] [ f ] if ;

M: bridge-backend backend-query
    backend-get-collection ;

! ============================================================
! Global Backend Selection
! ============================================================

SYMBOL: current-backend

: init-memory-backend ( -- )
    <memory-backend> dup backend-init current-backend set ;

: init-bridge-backend ( path -- )
    <bridge-backend> dup backend-init current-backend set ;

: get-backend ( -- backend )
    current-backend get [ init-memory-backend current-backend get ] unless* ;

: close-backend ( -- )
    current-backend get [ backend-close ] when*
    f current-backend set ;

! ============================================================
! Convenience API (used by executor)
! ============================================================

: storage-get-collection ( name -- data )
    get-backend backend-get-collection ;

: storage-set-collection ( data name -- )
    get-backend backend-set-collection ;

: storage-list-collections ( -- names )
    get-backend backend-list-collections ;

: storage-delete-collection ( name -- )
    get-backend backend-delete-collection ;

: storage-insert ( doc collection -- id )
    get-backend backend-insert ;

: storage-update ( doc id collection -- success? )
    get-backend backend-update ;

: storage-delete ( id collection -- success? )
    get-backend backend-delete ;

: storage-query ( collection -- rows )
    get-backend backend-query ;

! ============================================================
! Backend Selection at Startup
! ============================================================

: use-memory-storage ( -- )
    close-backend
    init-memory-backend
    "Using in-memory storage backend\n" print ;

: use-bridge-storage ( path -- )
    close-backend
    init-bridge-backend
    "Using bridge storage backend\n" print ;

! Default to memory backend
init-memory-backend
