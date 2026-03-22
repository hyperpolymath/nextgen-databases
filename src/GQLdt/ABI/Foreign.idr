-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Foreign.idr - FFI declarations for GQLdt ABI
-- Media-Type: text/x-idris
--
-- All safe wrappers delegate to the Zig FFI (libgqldt) via prim__* bindings.
-- Pointer handling uses allocSlot/readSlot/freeSlot + Data.So.choose to
-- avoid believe_me.  This is a HARD invariant — no exceptions.

module GQLdt.ABI.Foreign

import GQLdt.ABI.Types
import GQLdt.ABI.Layout
import Data.Bits
import Data.Buffer
import Data.So
import Data.String

%default total

--------------------------------------------------------------------------------
-- FFI Helper Primitives - Pointer / Memory Utilities
--------------------------------------------------------------------------------

||| Allocate a pointer-sized output slot on the heap.
||| The caller must free with prim__freeSlot after reading.
%foreign "C:gqldt_alloc_slot,libgqldt"
prim__allocSlot : PrimIO AnyPtr

||| Read a pointer value from an output slot as Bits64.
%foreign "C:gqldt_read_slot,libgqldt"
prim__readSlot : (slot : AnyPtr) -> PrimIO Bits64

||| Free an output slot allocated by prim__allocSlot.
%foreign "C:gqldt_free_slot,libgqldt"
prim__freeSlot : (slot : AnyPtr) -> PrimIO ()

||| Cast a Bits64 value to an AnyPtr (for passing handles to C).
%foreign "C:gqldt_bits64_to_ptr,libgqldt"
prim__bits64ToPtr : Bits64 -> AnyPtr

--------------------------------------------------------------------------------
-- FFI Function Signatures
--------------------------------------------------------------------------------

||| Initialize GQLdt library
||| Returns: Status code
%foreign "C:gqldt_init,libgqldt"
prim__init : PrimIO Int32

||| Cleanup GQLdt library
%foreign "C:gqldt_cleanup,libgqldt"
prim__cleanup : PrimIO ()

||| Create database handle
||| @ path Database file path (null-terminated C string)
||| @ path_len Path length in bytes
||| @ db_out Output parameter for database handle
||| Returns: Status code
%foreign "C:gqldt_db_open,libgqldt"
prim__db_open : (path : String) -> (path_len : Bits64) -> (db_out : AnyPtr) -> PrimIO Int32

||| Close database handle
||| @ db Database handle to close
||| Returns: Status code
%foreign "C:gqldt_db_close,libgqldt"
prim__db_close : (db : AnyPtr) -> PrimIO Int32

||| Parse GQLdt query string
||| @ query_str Query string (null-terminated)
||| @ query_len Query length
||| @ query_out Output parameter for query handle
||| Returns: Status code
%foreign "C:gqldt_parse,libgqldt"
prim__parse : (query_str : String) -> (query_len : Bits64) -> (query_out : AnyPtr) -> PrimIO Int32

||| Parse GQL query string (with type inference)
||| @ query_str Query string
||| @ query_len Query length
||| @ schema Schema handle for type inference
||| @ query_out Output parameter for query handle
||| Returns: Status code
%foreign "C:gqldt_parse_inferred,libgqldt"
prim__parse_inferred : (query_str : String) -> (query_len : Bits64) -> (schema : AnyPtr) -> (query_out : AnyPtr) -> PrimIO Int32

||| Type-check query
||| @ query Query handle
||| @ schema Schema handle
||| Returns: Status code (StatusOk if types match, StatusTypeMismatch otherwise)
%foreign "C:gqldt_typecheck,libgqldt"
prim__typecheck : (query : AnyPtr) -> (schema : AnyPtr) -> PrimIO Int32

||| Execute query
||| @ db Database handle
||| @ query Query handle
||| @ result_out Output parameter for result set
||| Returns: Status code
%foreign "C:gqldt_execute,libgqldt"
prim__execute : (db : AnyPtr) -> (query : AnyPtr) -> (result_out : AnyPtr) -> PrimIO Int32

||| Serialize query to CBOR
||| @ query Query handle
||| @ buffer Output buffer
||| @ buffer_len Buffer capacity
||| @ written_out Bytes written
||| Returns: Status code
%foreign "C:gqldt_serialize_cbor,libgqldt"
prim__serialize_cbor : (query : AnyPtr) -> (buffer : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

||| Serialize query to JSON
%foreign "C:gqldt_serialize_json,libgqldt"
prim__serialize_json : (query : AnyPtr) -> (buffer : AnyPtr) -> (buffer_len : Bits64) -> (written_out : AnyPtr) -> PrimIO Int32

||| Deserialize query from CBOR
%foreign "C:gqldt_deserialize_cbor,libgqldt"
prim__deserialize_cbor : (buffer : AnyPtr) -> (buffer_len : Bits64) -> (query_out : AnyPtr) -> PrimIO Int32

||| Get schema from database
%foreign "C:gqldt_get_schema,libgqldt"
prim__get_schema : (db : AnyPtr) -> (collection_name : String) -> (schema_out : AnyPtr) -> PrimIO Int32

||| Validate permissions
||| @ query Query handle
||| @ user_id User identifier
||| @ permissions Permission whitelist
||| Returns: Status code (StatusOk if allowed, StatusPermissionDenied otherwise)
%foreign "C:gqldt_validate_permissions,libgqldt"
prim__validate_permissions : (query : AnyPtr) -> (user_id : String) -> (permissions : AnyPtr) -> PrimIO Int32

||| Free query handle
%foreign "C:gqldt_query_free,libgqldt"
prim__query_free : (query : AnyPtr) -> PrimIO ()

||| Free schema handle
%foreign "C:gqldt_schema_free,libgqldt"
prim__schema_free : (schema : AnyPtr) -> PrimIO ()

--------------------------------------------------------------------------------
-- Handle Pointer Extraction
--------------------------------------------------------------------------------

||| Extract the raw Bits64 handle from a GqldtDb.
extractDbPtr : GqldtDb -> Bits64
extractDbPtr (MkGqldtDb ptr) = ptr

||| Extract the raw Bits64 handle from a GqldtQuery.
extractQueryPtr : GqldtQuery -> Bits64
extractQueryPtr (MkGqldtQuery ptr) = ptr

||| Extract the raw Bits64 handle from a GqldtSchema.
extractSchemaPtr : GqldtSchema -> Bits64
extractSchemaPtr (MkGqldtSchema ptr) = ptr

--------------------------------------------------------------------------------
-- Safe High-Level Wrappers
--------------------------------------------------------------------------------

||| Safe initialization (IO effect)
export
init : IO (GqldtResult ())
init = do
  status <- primIO prim__init
  pure $ if status == 0
    then ok ()
    else err StatusInternalError (MkNonEmptyString "Failed to initialize GQLdt library")

||| Safe cleanup
export
cleanup : IO ()
cleanup = primIO prim__cleanup

||| Safe database open.
||| Allocates an output slot, calls prim__db_open, reads the resulting
||| handle, and wraps it in GqldtDb with a runtime non-null check via
||| Data.So.choose.  No believe_me.
export
covering
dbOpen : (path : String) -> IO (GqldtResult GqldtDb)
dbOpen path = do
  let pathLen = cast {to=Bits64} (length path)
  dbSlot <- primIO prim__allocSlot
  status <- primIO $ prim__db_open path pathLen dbSlot
  if status == 0
    then do
      ptr <- primIO $ prim__readSlot dbSlot
      primIO $ prim__freeSlot dbSlot
      case choose (ptr /= 0) of
        Left prf => pure $ ok (MkGqldtDb ptr)
        Right _  => pure $ err StatusInternalError
                               (MkNonEmptyString "Database open returned null handle")
    else do
      primIO $ prim__freeSlot dbSlot
      pure $ err (intToStatus status)
                 (MkNonEmptyString "Failed to open database")

||| Safe database close.
||| Extracts the pointer from GqldtDb, converts to AnyPtr via
||| prim__bits64ToPtr, and calls prim__db_close.
export
covering
dbClose : GqldtDb -> IO (GqldtResult ())
dbClose db = do
  let ptr = extractDbPtr db
  status <- primIO $ prim__db_close (prim__bits64ToPtr ptr)
  if status == 0
    then pure $ ok ()
    else pure $ err (intToStatus status)
                    (MkNonEmptyString "Failed to close database")

||| Safe parse (GQLdt - explicit types).
||| Allocates an output slot, calls prim__parse, reads the resulting
||| handle, and wraps it in GqldtQuery with a runtime non-null check.
export
covering
parse : String -> IO (GqldtResult GqldtQuery)
parse queryStr = do
  let queryLen = cast {to=Bits64} (length queryStr)
  querySlot <- primIO prim__allocSlot
  status <- primIO $ prim__parse queryStr queryLen querySlot
  if status == 0
    then do
      ptr <- primIO $ prim__readSlot querySlot
      primIO $ prim__freeSlot querySlot
      case choose (ptr /= 0) of
        Left prf => pure $ ok (MkGqldtQuery ptr)
        Right _  => pure $ err StatusInternalError
                               (MkNonEmptyString "Parse returned null handle")
    else do
      primIO $ prim__freeSlot querySlot
      pure $ err (intToStatus status)
                 (MkNonEmptyString "Failed to parse query")

||| Safe parse with type inference (GQL - user tier).
||| Passes the schema handle alongside the query for inference.
export
covering
parseInferred : String -> GqldtSchema -> IO (GqldtResult GqldtQuery)
parseInferred queryStr schema = do
  let queryLen  = cast {to=Bits64} (length queryStr)
  let schemaPtr = prim__bits64ToPtr (extractSchemaPtr schema)
  querySlot <- primIO prim__allocSlot
  status <- primIO $ prim__parse_inferred queryStr queryLen schemaPtr querySlot
  if status == 0
    then do
      ptr <- primIO $ prim__readSlot querySlot
      primIO $ prim__freeSlot querySlot
      case choose (ptr /= 0) of
        Left prf => pure $ ok (MkGqldtQuery ptr)
        Right _  => pure $ err StatusInternalError
                               (MkNonEmptyString "Parse (inferred) returned null handle")
    else do
      primIO $ prim__freeSlot querySlot
      pure $ err (intToStatus status)
                 (MkNonEmptyString "Failed to parse query with inference")

||| Safe type checking.
||| Calls prim__typecheck and translates the status code.
export
covering
typecheck : GqldtQuery -> GqldtSchema -> IO (GqldtResult ())
typecheck query schema = do
  let queryPtr  = prim__bits64ToPtr (extractQueryPtr query)
  let schemaPtr = prim__bits64ToPtr (extractSchemaPtr schema)
  status <- primIO $ prim__typecheck queryPtr schemaPtr
  if status == 0
    then pure $ ok ()
    else pure $ err (intToStatus status)
                    (MkNonEmptyString "Type checking failed")

||| Safe query execution.
||| Requires the query to have been type-checked first (enforced at the
||| Zig FFI layer).  Allocates an output slot for the result handle.
export
covering
execute : GqldtDb -> GqldtQuery -> IO (GqldtResult ())
execute db query = do
  let dbPtr    = prim__bits64ToPtr (extractDbPtr db)
  let queryPtr = prim__bits64ToPtr (extractQueryPtr query)
  resultSlot <- primIO prim__allocSlot
  status <- primIO $ prim__execute dbPtr queryPtr resultSlot
  primIO $ prim__freeSlot resultSlot
  if status == 0
    then pure $ ok ()
    else pure $ err (intToStatus status)
                    (MkNonEmptyString "Query execution failed")

--------------------------------------------------------------------------------
-- Proven Library Integration
--------------------------------------------------------------------------------

||| Validate a database path inline.
||| Rejects empty strings, directory traversal (".."), and paths exceeding
||| 4096 bytes.
||| TODO: Replace with Proven.SafePath.validatePath for dependent-type proof.
validateDbPath : String -> Maybe String
validateDbPath path =
  if length path == 0 then Nothing
  else if length path > 4096 then Nothing
  else if isInfixOf ".." path then Nothing
  else Just path

||| Validate a query string inline.
||| Rejects empty strings and strings exceeding 1MB.
||| TODO: Replace with Proven.SafeString.validateString for dependent-type proof.
validateQueryStr : String -> Maybe String
validateQueryStr qs =
  if length qs == 0 then Nothing
  else if length qs > 1000000 then Nothing
  else Just qs

||| Use proven library's SafePath for database path validation.
||| Validates the path before delegating to dbOpen.
export
covering
dbOpenSafe : String -> IO (GqldtResult GqldtDb)
dbOpenSafe path = do
  case validateDbPath path of
    Nothing => pure $ err StatusInvalidArg
                          (MkNonEmptyString "Path validation failed")
    Just validPath => dbOpen validPath

||| Use proven library's SafeString for query validation.
||| Validates the query string before delegating to parse.
export
covering
parseSafe : String -> IO (GqldtResult GqldtQuery)
parseSafe queryStr = do
  case validateQueryStr queryStr of
    Nothing => pure $ err StatusInvalidArg
                          (MkNonEmptyString "Query validation failed")
    Just validQuery => parse validQuery

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Convert status code to GqldtStatus
export
intToStatus : Int32 -> GqldtStatus
intToStatus 0 = StatusOk
intToStatus 1 = StatusInvalidArg
intToStatus 2 = StatusTypeMismatch
intToStatus 3 = StatusProofFailed
intToStatus 4 = StatusPermissionDenied
intToStatus 5 = StatusOutOfMemory
intToStatus _ = StatusInternalError

||| Get error message for status code
export
statusMessage : GqldtStatus -> NonEmptyString
statusMessage StatusOk = MkNonEmptyString "Success"
statusMessage StatusInvalidArg = MkNonEmptyString "Invalid argument"
statusMessage StatusTypeMismatch = MkNonEmptyString "Type mismatch in query"
statusMessage StatusProofFailed = MkNonEmptyString "Proof verification failed"
statusMessage StatusPermissionDenied = MkNonEmptyString "Permission denied"
statusMessage StatusOutOfMemory = MkNonEmptyString "Out of memory"
statusMessage StatusInternalError = MkNonEmptyString "Internal error"
