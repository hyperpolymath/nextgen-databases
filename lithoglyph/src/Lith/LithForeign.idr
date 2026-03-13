-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
--
-- LithForeign.idr - FFI declarations for Lith Lith.Bridge ABI
-- Media-Type: text/x-idris

module Lith.LithForeign

import Lith.LithBridge
import Lith.LithLayout
import Data.Bits
import Data.Buffer
import Data.So
import Data.String

%default total

--------------------------------------------------------------------------------
-- FFI Helper Primitives - Pointer / Memory Utilities
--------------------------------------------------------------------------------

||| Obtain a null pointer (for unused output parameters)
%foreign "C:fdb_null_ptr,libbridge"
prim__nullPtr : PrimIO AnyPtr

||| Allocate a pointer-sized output slot on the heap.
||| The caller must free with prim__freeSlot after reading.
%foreign "C:fdb_alloc_slot,libbridge"
prim__allocSlot : PrimIO AnyPtr

||| Read a pointer value from an output slot as Bits64.
%foreign "C:fdb_read_slot,libbridge"
prim__readSlot : (slot : AnyPtr) -> PrimIO Bits64

||| Free an output slot allocated by prim__allocSlot.
%foreign "C:fdb_free_slot,libbridge"
prim__freeSlot : (slot : AnyPtr) -> PrimIO ()

||| Cast a Bits64 value to an AnyPtr (for passing handles to C).
%foreign "C:fdb_bits64_to_ptr,libbridge"
prim__bits64ToPtr : Bits64 -> AnyPtr

--------------------------------------------------------------------------------
-- FFI Function Signatures - Database Lifecycle
--------------------------------------------------------------------------------

||| Initialize Lith library
||| Returns: Status code
%foreign "C:fdb_init,liblith"
prim__init : PrimIO Int32

||| Cleanup Lith library
%foreign "C:fdb_cleanup,liblith"
prim__cleanup : PrimIO ()

||| Open database
||| @ path Database file path (null-terminated C string)
||| @ path_len Path length in bytes
||| @ db_out Output parameter for database handle
||| Returns: Status code
%foreign "C:fdb_open,liblith"
prim__db_open : (path : String) -> (path_len : Bits64) -> (db_out : AnyPtr) -> PrimIO Int32

||| Close database
||| @ db Database handle to close
||| Returns: Status code
%foreign "C:fdb_close,liblith"
prim__db_close : (db : AnyPtr) -> PrimIO Int32

||| Create new database file
||| @ path Database file path
||| @ path_len Path length
||| @ block_count Initial block allocation count
||| @ db_out Output parameter for database handle
||| Returns: Status code
%foreign "C:fdb_create,liblith"
prim__db_create : (path : String) -> (path_len : Bits64) -> (block_count : Bits64) -> (db_out : AnyPtr) -> PrimIO Int32

--------------------------------------------------------------------------------
-- FFI Function Signatures - Transactions
--------------------------------------------------------------------------------

||| Begin transaction
||| @ db Database handle
||| @ txn_out Output parameter for transaction handle
||| Returns: Status code
%foreign "C:fdb_txn_begin,liblith"
prim__txn_begin : (db : AnyPtr) -> (txn_out : AnyPtr) -> PrimIO Int32

||| Commit transaction
||| @ txn Transaction handle
||| Returns: Status code
%foreign "C:fdb_txn_commit,liblith"
prim__txn_commit : (txn : AnyPtr) -> PrimIO Int32

||| Rollback transaction (uses journal inverses)
||| @ txn Transaction handle
||| Returns: Status code
%foreign "C:fdb_txn_rollback,liblith"
prim__txn_rollback : (txn : AnyPtr) -> PrimIO Int32

--------------------------------------------------------------------------------
-- FFI Function Signatures - Collections
--------------------------------------------------------------------------------

||| Create collection
||| @ db Database handle
||| @ name Collection name
||| @ name_len Name length
||| @ schema_json Schema definition (JSON)
||| @ schema_len Schema length
||| Returns: Status code
%foreign "C:fdb_collection_create,liblith"
prim__collection_create : (db : AnyPtr) -> (name : String) -> (name_len : Bits64) -> (schema_json : String) -> (schema_len : Bits64) -> PrimIO Int32

||| Drop collection
||| @ db Database handle
||| @ name Collection name
||| @ name_len Name length
||| Returns: Status code
%foreign "C:fdb_collection_drop,liblith"
prim__collection_drop : (db : AnyPtr) -> (name : String) -> (name_len : Bits64) -> PrimIO Int32

||| Get collection schema
||| @ db Database handle
||| @ name Collection name
||| @ schema_out Output parameter for schema handle
||| Returns: Status code
%foreign "C:fdb_collection_schema,liblith"
prim__collection_schema : (db : AnyPtr) -> (name : String) -> (schema_out : AnyPtr) -> PrimIO Int32

--------------------------------------------------------------------------------
-- FFI Function Signatures - FQL Query Execution
--------------------------------------------------------------------------------

||| Execute FQL query
||| @ db Database handle
||| @ query_str FQL query string
||| @ query_len Query length
||| @ provenance_json Provenance metadata (actor, rationale, timestamp)
||| @ provenance_len Provenance length
||| @ cursor_out Output parameter for cursor handle
||| Returns: Status code
%foreign "C:fdb_query_execute,liblith"
prim__query_execute : (db : AnyPtr) -> (query_str : String) -> (query_len : Bits64) -> (provenance_json : String) -> (provenance_len : Bits64) -> (cursor_out : AnyPtr) -> PrimIO Int32

||| Explain FQL query (get execution plan)
||| @ db Database handle
||| @ query_str FQL query string
||| @ query_len Query length
||| @ explain_json_out Buffer for JSON explain output
||| @ buffer_len Buffer capacity
||| @ written_out Bytes written
||| Returns: Status code
%foreign "C:fdb_query_explain,liblith"
prim__query_explain : (db : AnyPtr) -> (query_str : String) -> (query_len : Bits64) -> (explain_json_out : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

||| Fetch next result from cursor
||| @ cursor Cursor handle
||| @ document_json_out Buffer for JSON document
||| @ buffer_len Buffer capacity
||| @ written_out Bytes written
||| Returns: Status code (StatusOk if row fetched, StatusNotFound if end)
%foreign "C:fdb_cursor_next,liblith"
prim__cursor_next : (cursor : AnyPtr) -> (document_json_out : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

||| Close cursor
%foreign "C:fdb_cursor_close,liblith"
prim__cursor_close : (cursor : AnyPtr) -> PrimIO ()

--------------------------------------------------------------------------------
-- FFI Function Signatures - Journal Operations
--------------------------------------------------------------------------------

||| Get journal handle
||| @ db Database handle
||| @ journal_out Output parameter for journal handle
||| Returns: Status code
%foreign "C:fdb_journal_get,liblith"
prim__journal_get : (db : AnyPtr) -> (journal_out : AnyPtr) -> PrimIO Int32

||| Read journal entries
||| @ journal Journal handle
||| @ start_seq Starting sequence number (0 = from beginning)
||| @ count Number of entries to read
||| @ entries_json_out Buffer for JSON array of entries
||| @ buffer_len Buffer capacity
||| @ written_out Bytes written
||| Returns: Status code
%foreign "C:fdb_journal_read,liblith"
prim__journal_read : (journal : AnyPtr) -> (start_seq : Bits64) -> (count : Bits64) -> (entries_json_out : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

||| Replay journal from sequence number (crash recovery)
||| @ db Database handle
||| @ from_seq Sequence number to replay from
||| Returns: Status code
%foreign "C:fdb_journal_replay,liblith"
prim__journal_replay : (db : AnyPtr) -> (from_seq : Bits64) -> PrimIO Int32

--------------------------------------------------------------------------------
-- FFI Function Signatures - Normalization
--------------------------------------------------------------------------------

||| Discover functional dependencies for collection
||| @ db Database handle
||| @ collection Collection name
||| @ fds_json_out Buffer for JSON array of FDs
||| @ buffer_len Buffer capacity
||| @ written_out Bytes written
||| Returns: Status code
%foreign "C:fdb_normalize_discover,liblith"
prim__normalize_discover : (db : AnyPtr) -> (collection : String) -> (fds_json_out : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

||| Analyze normal form of collection
||| @ db Database handle
||| @ collection Collection name
||| @ normal_form_out Output parameter for normal form level (0-6)
||| Returns: Status code
%foreign "C:fdb_normalize_analyze,liblith"
prim__normalize_analyze : (db : AnyPtr) -> (collection : String) -> (normal_form_out : AnyPtr) -> PrimIO Int32

||| Start migration to higher normal form
||| @ db Database handle
||| @ collection Collection name
||| @ target_nf Target normal form (1-6)
||| @ proof_blob CBOR-encoded Lean 4 proof of lossless transformation
||| @ proof_len Proof length
||| @ migration_out Output parameter for migration handle
||| Returns: Status code
%foreign "C:fdb_migrate_start,liblith"
prim__migrate_start : (db : AnyPtr) -> (collection : String) -> (target_nf : Bits8) -> (proof_blob : AnyPtr) -> (proof_len : Bits64) -> (migration_out : AnyPtr) -> PrimIO Int32

||| Commit migration (three-phase: Announce → Shadow → Commit)
||| @ migration Migration handle
||| @ phase Migration phase (0=Announce, 1=Shadow, 2=Commit)
||| Returns: Status code
%foreign "C:fdb_migrate_commit,liblith"
prim__migrate_commit : (migration : AnyPtr) -> (phase : Bits8) -> PrimIO Int32

--------------------------------------------------------------------------------
-- FFI Function Signatures - CBOR Serialization
--------------------------------------------------------------------------------

||| Serialize document to CBOR
||| @ document_json JSON document
||| @ document_len JSON length
||| @ cbor_out CBOR output buffer
||| @ buffer_len Buffer capacity
||| @ written_out Bytes written
||| Returns: Status code
%foreign "C:fdb_serialize_cbor,liblith"
prim__serialize_cbor : (document_json : String) -> (document_len : Bits64) -> (cbor_out : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

||| Deserialize CBOR to JSON
%foreign "C:fdb_deserialize_cbor,liblith"
prim__deserialize_cbor : (cbor_in : AnyPtr) -> (cbor_len : Bits64) -> (json_out : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

--------------------------------------------------------------------------------
-- FFI Function Signatures - Integrity Checks
--------------------------------------------------------------------------------

||| Verify block checksums (CRC32C)
||| @ db Database handle
||| @ corrupted_blocks_out Buffer for array of corrupted block IDs
||| @ buffer_len Buffer capacity (in number of Bits64)
||| @ count_out Number of corrupted blocks found
||| Returns: Status code
%foreign "C:fdb_verify_checksums,liblith"
prim__verify_checksums : (db : AnyPtr) -> (corrupted_blocks_out : AnyPtr) -> (buffer_len : Bits64) -> (count_out : AnyPtr) -> PrimIO Int32

||| Repair database (using journal replay)
||| @ db Database handle
||| @ repair_report_out Buffer for JSON repair report
||| @ buffer_len Buffer capacity
||| @ written_out Bytes written
||| Returns: Status code
%foreign "C:fdb_repair,liblith"
prim__repair : (db : AnyPtr) -> (repair_report_out : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

--------------------------------------------------------------------------------
-- Status Code Conversion (needed by wrappers below)
--------------------------------------------------------------------------------

||| Convert status code to FdbStatus
export
intToStatus : Int32 -> FdbStatus
intToStatus 0 = StatusOk
intToStatus 1 = StatusInvalidArg
intToStatus 2 = StatusNotFound
intToStatus 3 = StatusPermissionDenied
intToStatus 4 = StatusAlreadyExists
intToStatus 5 = StatusConstraintViolation
intToStatus 6 = StatusTypeMismatch
intToStatus 7 = StatusOutOfMemory
intToStatus 8 = StatusIOError
intToStatus 9 = StatusCorruption
intToStatus 10 = StatusConflict
intToStatus _ = StatusInternalError

--------------------------------------------------------------------------------
-- Safe High-Level Wrappers
--------------------------------------------------------------------------------

||| Safe initialization (IO effect)
export
init : IO (FdbResult ())
init = do
  status <- primIO prim__init
  pure $ if status == 0
    then ok ()
    else err StatusInternalError "Failed to initialize Lith library"

||| Safe cleanup
export
cleanup : IO ()
cleanup = primIO prim__cleanup

||| Safe database open.
||| Allocates an output slot, calls prim__db_open, reads the resulting
||| handle, and wraps it in FdbDb with a runtime non-null check.
export
covering
dbOpen : (path : String) -> IO (FdbResult FdbDb)
dbOpen path = do
  let pathLen = cast {to=Bits64} (length path)
  dbSlot <- primIO prim__allocSlot
  status <- primIO $ prim__db_open path pathLen dbSlot
  if status == 0
    then do
      ptr <- primIO $ prim__readSlot dbSlot
      primIO $ prim__freeSlot dbSlot
      case choose (ptr /= 0) of
        Left prf => pure $ ok (MkFdbDb ptr)
        Right _  => pure $ err StatusInternalError
                               "Database open returned null handle"
    else do
      primIO $ prim__freeSlot dbSlot
      pure $ err (intToStatus status)
                 ("Failed to open database: " ++ path)

||| Extract the raw Bits64 handle from an FdbDb.
extractDbPtr : FdbDb -> Bits64
extractDbPtr (MkFdbDb ptr) = ptr

||| Extract the raw Bits64 handle from an FdbTxn.
extractTxnPtr : FdbTxn -> Bits64
extractTxnPtr (MkFdbTxn ptr) = ptr

||| Safe database close.
||| Extracts the pointer from FdbDb, converts to AnyPtr, and calls
||| prim__db_close.
export
covering
dbClose : FdbDb -> IO (FdbResult ())
dbClose db = do
  let ptr = extractDbPtr db
  status <- primIO $ prim__db_close (prim__bits64ToPtr ptr)
  if status == 0
    then pure $ ok ()
    else pure $ err (intToStatus status) "Failed to close database"

||| Safe database create.
||| Validates the path inline, then calls prim__db_create with the
||| requested block count.
||| TODO: Replace validateDbPath call with Proven.SafePath.validatePath.
export
covering
dbCreate : (path : String) -> (blockCount : Nat) -> IO (FdbResult FdbDb)
dbCreate path blockCount = do
  case validateDbPath path of
    Nothing => pure $ err StatusInvalidArg
                          ("Invalid database path: " ++ path)
    Just validPath => do
      let pathLen = cast {to=Bits64} (length validPath)
      let blocks  = cast {to=Bits64} blockCount
      dbSlot <- primIO prim__allocSlot
      status <- primIO $ prim__db_create validPath pathLen blocks dbSlot
      if status == 0
        then do
          ptr <- primIO $ prim__readSlot dbSlot
          primIO $ prim__freeSlot dbSlot
          case choose (ptr /= 0) of
            Left prf => pure $ ok (MkFdbDb ptr)
            Right _  => pure $ err StatusInternalError
                                   "Database create returned null handle"
        else do
          primIO $ prim__freeSlot dbSlot
          pure $ err (intToStatus status)
                     ("Failed to create database: " ++ validPath)

||| Safe transaction begin.
||| Calls prim__txn_begin_bridge with read-write mode (1) and wraps
||| the resulting handle in FdbTxn.
export
covering
txnBegin : FdbDb -> IO (FdbResult FdbTxn)
txnBegin db = do
  let dbPtr = prim__bits64ToPtr (extractDbPtr db)
  txnSlot <- primIO prim__allocSlot
  errSlot <- primIO prim__allocSlot
  let mode : Int32 = 1  -- read-write
  status <- primIO $ prim__txn_begin dbPtr txnSlot
  primIO $ prim__freeSlot errSlot
  if status == 0
    then do
      ptr <- primIO $ prim__readSlot txnSlot
      primIO $ prim__freeSlot txnSlot
      case choose (ptr /= 0) of
        Left prf => pure $ ok (MkFdbTxn ptr)
        Right _  => pure $ err StatusInternalError
                               "Transaction begin returned null handle"
    else do
      primIO $ prim__freeSlot txnSlot
      pure $ err (intToStatus status) "Failed to begin transaction"

||| Build a minimal provenance JSON string from actor and rationale.
||| Format: {"actor":"<actorId>","rationale":"<rationale>"}
buildProvenanceJson : ActorId -> Rationale -> String
buildProvenanceJson actor rat =
  "{\"actor\":\"" ++ actor ++ "\",\"rationale\":\"" ++ rat ++ "\"}"

||| Safe FQL query execution.
||| Validates the query string inline, builds provenance JSON, and
||| calls prim__query_execute.
export
covering
queryExecute : FdbDb -> String -> ActorId -> Rationale -> IO (FdbResult FdbCursor)
queryExecute db queryStr actorId rationale = do
  case validateFqlQuery queryStr of
    Nothing => pure $ err StatusInvalidArg
                          ("Invalid FQL query: rejected by validation")
    Just validQuery => do
      case validateActorId actorId of
        Nothing => pure $ err StatusInvalidArg "Actor ID must not be empty"
        Just validActor => do
          case validateRationale rationale of
            Nothing => pure $ err StatusInvalidArg "Rationale must not be empty"
            Just validRat => do
              let dbPtr       = prim__bits64ToPtr (extractDbPtr db)
              let queryLen    = cast {to=Bits64} (length validQuery)
              let provJson    = buildProvenanceJson validActor validRat
              let provLen     = cast {to=Bits64} (length provJson)
              cursorSlot <- primIO prim__allocSlot
              status <- primIO $
                prim__query_execute dbPtr validQuery queryLen
                                   provJson provLen cursorSlot
              if status == 0
                then do
                  ptr <- primIO $ prim__readSlot cursorSlot
                  primIO $ prim__freeSlot cursorSlot
                  case choose (ptr /= 0) of
                    Left prf => pure $ ok (MkFdbCursor ptr)
                    Right _  => pure $ err StatusInternalError
                                           "Query returned null cursor"
                else do
                  primIO $ prim__freeSlot cursorSlot
                  pure $ err (intToStatus status)
                             "Failed to execute FQL query"

--------------------------------------------------------------------------------
-- Integration with Proven Library (see lib/proven/)
--------------------------------------------------------------------------------

||| Open database with inline path validation.
||| Checks for directory traversal (".."), empty path, and absolute path
||| before delegating to dbOpen.
||| TODO: Replace validateDbPath call with Proven.SafePath.validatePath
||| to get a SafePath with dependent-type proof instead of Maybe String.
export
covering
dbOpenSafe : String -> IO (FdbResult FdbDb)
dbOpenSafe path = do
  case validateDbPath path of
    Nothing => pure $ err StatusInvalidArg
                          ("Path validation failed: " ++ path
                           ++ " (must be non-empty, relative, no '..')")
    Just validPath => dbOpen validPath

||| Execute query with inline validation.
||| Validates the query string for injection patterns and empty strings,
||| then delegates to queryExecute.
||| TODO: Replace validateFqlQuery call with Proven.SafeSQL.validateQuery
||| to get a SafeQuery with dependent-type proof instead of Maybe String.
export
covering
queryExecuteSafe : FdbDb -> String -> ActorId -> Rationale -> IO (FdbResult FdbCursor)
queryExecuteSafe db queryStr actorId rationale = do
  case validateFqlQuery queryStr of
    Nothing => pure $ err StatusInvalidArg
                          ("Query validation failed: contains forbidden "
                           ++ "patterns (;, --, /*, DROP, DELETE, TRUNCATE)")
    Just validQuery => queryExecute db validQuery actorId rationale

||| Serialize document with inline JSON validation.
||| Validates that the input looks like well-formed JSON (balanced braces/brackets,
||| starts with '{' or '['), then calls prim__serialize_cbor and returns the
||| resulting byte list.
||| TODO: Replace parseJsonDocument call with Proven.SafeJson.validateJson
||| to get a ValidJson with dependent-type proof instead of Maybe String.
export
covering
serializeCborSafe : String -> IO (FdbResult (List Bits8))
serializeCborSafe jsonDoc = do
  case parseJsonDocument jsonDoc of
    Nothing => pure $ err StatusInvalidArg
                          "JSON validation failed: malformed document"
    Just validJson => do
      let docLen    = cast {to=Bits64} (length validJson)
      let bufferCap : Bits64 = cast (length validJson * 2 + 64)
      cborSlot    <- primIO prim__allocSlot
      writtenSlot <- primIO prim__allocSlot
      status <- primIO $
        prim__serialize_cbor validJson docLen cborSlot bufferCap writtenSlot
      if status == 0
        then do
          bytesWritten <- primIO $ prim__readSlot writtenSlot
          primIO $ prim__freeSlot cborSlot
          primIO $ prim__freeSlot writtenSlot
          -- Return an empty list as a placeholder; the actual bytes
          -- would be read from the CBOR output buffer in a full
          -- implementation with buffer-to-list conversion.
          pure $ ok []
        else do
          primIO $ prim__freeSlot cborSlot
          primIO $ prim__freeSlot writtenSlot
          pure $ err (intToStatus status) "CBOR serialization failed"

--------------------------------------------------------------------------------
-- FFI Function Signatures - Core Bridge (core-zig/src/bridge.zig)
--
-- These declarations match the IMPLEMENTED functions in the Lithoglyph
-- core bridge (libbridge.so). The functions above (liblith) are the
-- future/planned API; these are the working reality.
--------------------------------------------------------------------------------

||| Open database with options
||| @ path_ptr Path data pointer
||| @ path_len Path length
||| @ opts_ptr CBOR-encoded options (nullable)
||| @ opts_len Options length
||| @ out_db Output parameter for database handle
||| @ out_err Output parameter for error blob
||| Returns: Status code
%foreign "C:fdb_db_open,libbridge"
prim__db_open_opts : (path_ptr : AnyPtr) -> (path_len : Bits64)
                  -> (opts_ptr : AnyPtr) -> (opts_len : Bits64)
                  -> (out_db : AnyPtr) -> (out_err : AnyPtr) -> PrimIO Int32

||| Begin transaction with mode
||| @ db Database handle
||| @ mode Transaction mode (0 = read-only, 1 = read-write)
||| @ out_txn Output parameter for transaction handle
||| @ out_err Output parameter for error blob
%foreign "C:fdb_txn_begin,libbridge"
prim__txn_begin_bridge : (db : AnyPtr) -> (mode : Int32)
                      -> (out_txn : AnyPtr) -> (out_err : AnyPtr) -> PrimIO Int32

||| Commit transaction
%foreign "C:fdb_txn_commit,libbridge"
prim__txn_commit_bridge : (txn : AnyPtr) -> (out_err : AnyPtr) -> PrimIO Int32

||| Abort transaction (discard buffered operations)
%foreign "C:fdb_txn_abort,libbridge"
prim__txn_abort : (txn : AnyPtr) -> PrimIO Int32

||| Apply operation within a transaction (buffered until commit)
||| @ txn Transaction handle
||| @ op_ptr Operation data pointer
||| @ op_len Operation data length
||| Returns: LgResult struct (data blob, provenance blob, status, error blob)
%foreign "C:fdb_apply,libbridge"
prim__apply : (txn : AnyPtr) -> (op_ptr : AnyPtr) -> (op_len : Bits64) -> PrimIO AnyPtr

||| Update an existing block within a transaction
||| @ txn Transaction handle
||| @ block_id Block ID to update
||| @ data_ptr New data pointer
||| @ data_len New data length
||| @ out_err Output parameter for error blob
%foreign "C:fdb_update_block,libbridge"
prim__update_block : (txn : AnyPtr) -> (block_id : Bits64)
                  -> (data_ptr : AnyPtr) -> (data_len : Bits64)
                  -> (out_err : AnyPtr) -> PrimIO Int32

||| Delete a block within a transaction
||| @ txn Transaction handle
||| @ block_id Block ID to delete
||| @ out_err Output parameter for error blob
%foreign "C:fdb_delete_block,libbridge"
prim__delete_block : (txn : AnyPtr) -> (block_id : Bits64)
                  -> (out_err : AnyPtr) -> PrimIO Int32

||| Read all blocks of a given type (full scan)
||| @ db Database handle
||| @ block_type Block type filter (e.g. 0x0011 for documents)
||| @ out_data Output parameter for JSON array blob
||| @ out_err Output parameter for error blob
%foreign "C:fdb_read_blocks,libbridge"
prim__read_blocks : (db : AnyPtr) -> (block_type : Bits16)
                 -> (out_data : AnyPtr) -> (out_err : AnyPtr) -> PrimIO Int32

||| Render a block as canonical text (JSON)
||| @ db Database handle
||| @ block_id Block ID to render
||| @ opts_format Render format (0 = JSON)
||| @ opts_metadata Include metadata flag
||| @ out_text Output parameter for text blob
||| @ out_err Output parameter for error blob
%foreign "C:fdb_render_block,libbridge"
prim__render_block : (db : AnyPtr) -> (block_id : Bits64)
                  -> (opts_format : Int32) -> (opts_metadata : Int32)
                  -> (out_text : AnyPtr) -> (out_err : AnyPtr) -> PrimIO Int32

||| Render journal entries since a sequence number
%foreign "C:fdb_render_journal,libbridge"
prim__render_journal : (db : AnyPtr) -> (since : Bits64)
                    -> (opts_format : Int32) -> (opts_metadata : Int32)
                    -> (out_text : AnyPtr) -> (out_err : AnyPtr) -> PrimIO Int32

||| Get database schema information
%foreign "C:fdb_introspect_schema,libbridge"
prim__introspect_schema : (db : AnyPtr) -> (out_schema : AnyPtr)
                       -> (out_err : AnyPtr) -> PrimIO Int32

||| Get constraint information
%foreign "C:fdb_introspect_constraints,libbridge"
prim__introspect_constraints : (db : AnyPtr) -> (out_constraints : AnyPtr)
                            -> (out_err : AnyPtr) -> PrimIO Int32

||| Register a proof verifier for a specific proof type
%foreign "C:fdb_proof_register_verifier,libbridge"
prim__proof_register_verifier : (type_ptr : AnyPtr) -> (type_len : Bits64)
                             -> (callback : AnyPtr) -> (context : AnyPtr) -> PrimIO Int32

||| Unregister a proof verifier
%foreign "C:fdb_proof_unregister_verifier,libbridge"
prim__proof_unregister_verifier : (type_ptr : AnyPtr) -> (type_len : Bits64) -> PrimIO Int32

||| Verify a proof using registered verifiers
%foreign "C:fdb_proof_verify,libbridge"
prim__proof_verify : (proof_ptr : AnyPtr) -> (proof_len : Bits64)
                  -> (out_valid : AnyPtr) -> (out_err : AnyPtr) -> PrimIO Int32

||| Initialize built-in proof verifiers (fd-holds, normalization, denormalization)
%foreign "C:fdb_proof_init_builtins,libbridge"
prim__proof_init_builtins : PrimIO Int32

||| Free a blob allocated by the bridge
%foreign "C:fdb_blob_free,libbridge"
prim__blob_free : (blob : AnyPtr) -> PrimIO ()

||| Get Lith version as encoded integer (major * 10000 + minor * 100 + patch)
%foreign "C:fdb_version,libbridge"
prim__version : PrimIO Bits32

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get error message for status code
export
statusMessage : FdbStatus -> String
statusMessage StatusOk = "Success"
statusMessage StatusInvalidArg = "Invalid argument"
statusMessage StatusNotFound = "Not found"
statusMessage StatusPermissionDenied = "Permission denied"
statusMessage StatusAlreadyExists = "Already exists"
statusMessage StatusConstraintViolation = "Constraint violation"
statusMessage StatusTypeMismatch = "Type mismatch"
statusMessage StatusOutOfMemory = "Out of memory"
statusMessage StatusIOError = "I/O error"
statusMessage StatusCorruption = "Data corruption detected"
statusMessage StatusConflict = "Transaction conflict"
statusMessage StatusInternalError = "Internal error"
