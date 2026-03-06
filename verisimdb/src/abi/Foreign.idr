||| SPDX-License-Identifier: PMPL-1.0-or-later
||| VeriSimDB Foreign Function Interface Declarations
|||
||| All C-compatible functions implemented in ffi/zig/.
||| These are the canonical FFI entry points for VeriSimDB.
|||
||| Naming convention: verisimdb_<operation>
||| All functions return VResult codes (Bits32).

module VeriSimDB.ABI.Foreign

import VeriSimDB.ABI.Types
import VeriSimDB.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize a VeriSimDB instance with configuration
||| config_ptr: pointer to VDBConfig struct
||| Returns: handle to VeriSimDB instance (0 on failure)
export
%foreign "C:verisimdb_init, libverisimdb"
prim__init : Bits64 -> PrimIO Bits64

||| Safe wrapper for initialization
export
init : Bits64 -> IO (Maybe VDBHandle)
init configPtr = do
  ptr <- primIO (prim__init configPtr)
  pure (createVDBHandle ptr)

||| Shut down and free all resources
export
%foreign "C:verisimdb_free, libverisimdb"
prim__free : Bits64 -> PrimIO ()

||| Safe shutdown
export
free : VDBHandle -> IO ()
free h = primIO (prim__free (vdbPtr h))

--------------------------------------------------------------------------------
-- Entity Operations
--------------------------------------------------------------------------------

||| Create a new octad entity
||| db: VDBHandle, id_high/id_low: EntityId parts, mask: active modalities
||| Returns: EntityHandle (0 on failure)
export
%foreign "C:verisimdb_entity_create, libverisimdb"
prim__entityCreate : Bits64 -> Bits64 -> Bits64 -> Bits8 -> PrimIO Bits64

||| Safe entity creation
export
entityCreate : VDBHandle -> EntityId -> ModalityMask -> IO (Maybe EntityHandle)
entityCreate db eid mask = do
  ptr <- primIO (prim__entityCreate (vdbPtr db) eid.high eid.low mask)
  pure (createEntityHandle ptr)

||| Look up an entity by ID
export
%foreign "C:verisimdb_entity_get, libverisimdb"
prim__entityGet : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits64

||| Safe entity lookup
export
entityGet : VDBHandle -> EntityId -> IO (Maybe EntityHandle)
entityGet db eid = do
  ptr <- primIO (prim__entityGet (vdbPtr db) eid.high eid.low)
  pure (createEntityHandle ptr)

||| Delete an entity and all its modality data
export
%foreign "C:verisimdb_entity_delete, libverisimdb"
prim__entityDelete : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe entity deletion
export
entityDelete : VDBHandle -> EntityId -> IO VResult
entityDelete db eid = do
  code <- primIO (prim__entityDelete (vdbPtr db) eid.high eid.low)
  pure $ case vresultFromInt code of
    Just r  => r
    Nothing => VError

||| Release an entity handle (does NOT delete the entity)
export
%foreign "C:verisimdb_entity_handle_free, libverisimdb"
prim__entityHandleFree : Bits64 -> PrimIO ()

export
entityHandleFree : EntityHandle -> IO ()
entityHandleFree h = primIO (prim__entityHandleFree (entityPtr h))

--------------------------------------------------------------------------------
-- Modality Data Operations
--------------------------------------------------------------------------------

||| Write modality data for an entity
||| entity: EntityHandle, slice_ptr: pointer to ModalitySlice struct
||| Returns: VResult code
export
%foreign "C:verisimdb_modality_write, libverisimdb"
prim__modalityWrite : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe modality write
export
modalityWrite : EntityHandle -> Bits64 -> IO VResult
modalityWrite entity slicePtr = do
  code <- primIO (prim__modalityWrite (entityPtr entity) slicePtr)
  pure $ case vresultFromInt code of
    Just r  => r
    Nothing => VError

||| Read modality data for an entity
||| entity: EntityHandle, modality: Bits32, out_ptr/out_len: output buffer
||| Returns: bytes written (0 on error)
export
%foreign "C:verisimdb_modality_read, libverisimdb"
prim__modalityRead : Bits64 -> Bits32 -> Bits64 -> Bits64 -> PrimIO Bits64

||| Safe modality read
export
modalityRead : EntityHandle -> Modality -> Bits64 -> Bits64 -> IO Bits64
modalityRead entity mod outPtr outLen =
  primIO (prim__modalityRead (entityPtr entity) (modalityToInt mod) outPtr outLen)

||| Get active modality mask for an entity
export
%foreign "C:verisimdb_entity_modalities, libverisimdb"
prim__entityModalities : Bits64 -> PrimIO Bits8

export
entityModalities : EntityHandle -> IO ModalityMask
entityModalities entity = primIO (prim__entityModalities (entityPtr entity))

--------------------------------------------------------------------------------
-- Drift Detection
--------------------------------------------------------------------------------

||| Check drift between two modalities of an entity
||| Returns: DriftScore (fixed-point * 10000), or 0xFFFFFFFF on error
export
%foreign "C:verisimdb_drift_check, libverisimdb"
prim__driftCheck : Bits64 -> Bits32 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe drift check
export
driftCheck : EntityHandle -> Modality -> Modality -> DriftMethod -> IO (Maybe DriftScore)
driftCheck entity src tgt method = do
  score <- primIO (prim__driftCheck (entityPtr entity)
                    (modalityToInt src) (modalityToInt tgt) (driftMethodToInt method))
  pure $ if score == 0xFFFFFFFF then Nothing else Just score

||| Run drift detection sweep on all entities
||| db: VDBHandle, report_buf: pointer to array of DriftReport structs
||| report_max: max reports to write
||| Returns: number of drift reports written
export
%foreign "C:verisimdb_drift_sweep, libverisimdb"
prim__driftSweep : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

export
driftSweep : VDBHandle -> Bits64 -> Bits32 -> IO Bits32
driftSweep db reportBuf maxReports =
  primIO (prim__driftSweep (vdbPtr db) reportBuf maxReports)

||| Trigger normalization for a drifted entity
export
%foreign "C:verisimdb_normalize, libverisimdb"
prim__normalize : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

export
normalize : VDBHandle -> EntityId -> IO VResult
normalize db eid = do
  code <- primIO (prim__normalize (vdbPtr db) eid.high eid.low)
  pure $ case vresultFromInt code of
    Just r  => r
    Nothing => VError

--------------------------------------------------------------------------------
-- VQL Query Execution
--------------------------------------------------------------------------------

||| Parse and execute a VQL query
||| db: VDBHandle, req_ptr: pointer to QueryRequest struct
||| Returns: ResultSetHandle (0 on failure)
export
%foreign "C:verisimdb_query, libverisimdb"
prim__query : Bits64 -> Bits64 -> PrimIO Bits64

||| Safe query execution
export
query : VDBHandle -> Bits64 -> IO (Maybe ResultSetHandle)
query db reqPtr = do
  ptr <- primIO (prim__query (vdbPtr db) reqPtr)
  if ptr == 0
    then pure Nothing
    else pure (Just (MkResultSetHandle ptr))

||| Get number of results in a result set
export
%foreign "C:verisimdb_resultset_count, libverisimdb"
prim__resultSetCount : Bits64 -> PrimIO Bits64

export
resultSetCount : ResultSetHandle -> IO Bits64
resultSetCount rs = primIO (prim__resultSetCount (resultSetPtr rs))

||| Read result at index as JSON bytes into buffer
||| Returns: bytes written (0 on error or out of bounds)
export
%foreign "C:verisimdb_resultset_get, libverisimdb"
prim__resultSetGet : Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits64

export
resultSetGet : ResultSetHandle -> Bits64 -> Bits64 -> Bits64 -> IO Bits64
resultSetGet rs idx outPtr outLen =
  primIO (prim__resultSetGet (resultSetPtr rs) idx outPtr outLen)

||| Free a result set
export
%foreign "C:verisimdb_resultset_free, libverisimdb"
prim__resultSetFree : Bits64 -> PrimIO ()

export
resultSetFree : ResultSetHandle -> IO ()
resultSetFree rs = primIO (prim__resultSetFree (resultSetPtr rs))

--------------------------------------------------------------------------------
-- Transaction Support
--------------------------------------------------------------------------------

||| Begin a transaction
export
%foreign "C:verisimdb_txn_begin, libverisimdb"
prim__txnBegin : Bits64 -> PrimIO Bits64

export
txnBegin : VDBHandle -> IO (Maybe TxnHandle)
txnBegin db = do
  ptr <- primIO (prim__txnBegin (vdbPtr db))
  if ptr == 0
    then pure Nothing
    else pure (Just (MkTxnHandle ptr))

||| Commit a transaction
export
%foreign "C:verisimdb_txn_commit, libverisimdb"
prim__txnCommit : Bits64 -> PrimIO Bits32

export
txnCommit : TxnHandle -> IO VResult
txnCommit txn = do
  code <- primIO (prim__txnCommit (txnPtr txn))
  pure $ case vresultFromInt code of
    Just r  => r
    Nothing => VError

||| Rollback a transaction
export
%foreign "C:verisimdb_txn_rollback, libverisimdb"
prim__txnRollback : Bits64 -> PrimIO Bits32

export
txnRollback : TxnHandle -> IO VResult
txnRollback txn = do
  code <- primIO (prim__txnRollback (txnPtr txn))
  pure $ case vresultFromInt code of
    Just r  => r
    Nothing => VError

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get VeriSimDB version string
export
%foreign "C:verisimdb_version, libverisimdb"
prim__version : PrimIO Bits64

||| Get version as string (caller must not free)
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get build info (features, platform)
export
%foreign "C:verisimdb_build_info, libverisimdb"
prim__buildInfo : PrimIO Bits64

export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)
