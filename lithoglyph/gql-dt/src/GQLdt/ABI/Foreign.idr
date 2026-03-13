-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Foreign.idr - FFI declarations for GQLdt ABI
-- Media-Type: text/x-idris

module GQLdt.ABI.Foreign

import GQLdt.ABI.Types
import GQLdt.ABI.Layout
import Data.Bits
import Data.Buffer

%default total

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

||| Safe database open
export
dbOpen : (path : String) -> IO (GqldtResult GqldtDb)
dbOpen path = do
  -- TODO: Allocate pointer for db_out, call prim__db_open, wrap in GqldtDb
  ?dbOpen_impl

||| Safe database close
export
dbClose : GqldtDb -> IO (GqldtResult ())
dbClose db = do
  -- TODO: Extract pointer, call prim__db_close
  ?dbClose_impl

||| Safe parse (GQLdt - explicit types)
export
parse : String -> IO (GqldtResult GqldtQuery)
parse queryStr = do
  -- TODO: Call prim__parse, wrap result in GqldtQuery
  ?parse_impl

||| Safe parse with type inference (GQL - user tier)
export
parseInferred : String -> GqldtSchema -> IO (GqldtResult GqldtQuery)
parseInferred queryStr schema = do
  -- TODO: Call prim__parse_inferred
  ?parseInferred_impl

||| Safe type checking
export
typecheck : GqldtQuery -> GqldtSchema -> IO (GqldtResult ())
typecheck query schema = do
  -- TODO: Call prim__typecheck
  ?typecheck_impl

||| Safe query execution
export
execute : GqldtDb -> GqldtQuery -> IO (GqldtResult ())  -- TODO: Add proper result type
execute db query = do
  -- TODO: Call prim__execute
  ?execute_impl

--------------------------------------------------------------------------------
-- Proven Library Integration
--------------------------------------------------------------------------------

||| Use proven library's SafePath for database path validation
export
dbOpenSafe : String -> IO (GqldtResult GqldtDb)
dbOpenSafe path = do
  -- TODO: Use Proven.SafePath to validate path before opening
  ?dbOpenSafe_impl

||| Use proven library's SafeString for query validation
export
parseSafe : String -> IO (GqldtResult GqldtQuery)
parseSafe queryStr = do
  -- TODO: Use Proven.SafeString to validate query string
  ?parseSafe_impl

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
