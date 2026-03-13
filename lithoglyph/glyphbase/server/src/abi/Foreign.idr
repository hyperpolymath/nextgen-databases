-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Lithoglyph ABI Foreign Function Interface Declarations
--
-- This module declares the C-compatible FFI functions that will be
-- implemented in Zig. All functions use the C calling convention and
-- follow the ABI layout guarantees from Layout.idr.

module Foreign

import Types
import Layout
import Data.Bits
import Data.Buffer

%default total

-- Foreign function declarations
-- These will be implemented in ffi/zig/src/main.zig

-- Get NIF version (major, minor, patch)
%foreign "C:lithoglyph_nif_version, liblithoglyph_nif"
prim__nif_version : PrimIO (Bits8, Bits8, Bits8)

export
nifVersion : IO Version
nifVersion = do
  (maj, min, pat) <- primIO prim__nif_version
  pure $ MkVersion maj min pat

-- Open database connection
-- Returns NULL on error (checked by constructor proof)
%foreign "C:lithoglyph_nif_db_open, liblithoglyph_nif"
prim__db_open : String -> PrimIO Bits64

export
dbOpen : (path : DbPath) -> IO (FFIResult DbHandle)
dbOpen (MkDbPath pathStr) = do
  ptr <- primIO (prim__db_open pathStr)
  if ptr == 0
    then pure $ Error "Failed to open database"
    else case decSo (ptr /= 0) of
           Yes prf => pure $ Ok (MkDbHandle ptr @{prf})
           No _ => pure $ Error "Null pointer returned"

-- Close database connection
%foreign "C:lithoglyph_nif_db_close, liblithoglyph_nif"
prim__db_close : Bits64 -> PrimIO Int

export
dbClose : DbHandle -> IO (FFIResult ())
dbClose handle = do
  result <- primIO (prim__db_close (dbHandlePtr handle))
  if result == 0
    then pure $ Ok ()
    else pure $ Error "Failed to close database"

-- Begin transaction
-- mode: 0 = ReadOnly, 1 = ReadWrite
%foreign "C:lithoglyph_nif_txn_begin, liblithoglyph_nif"
prim__txn_begin : Bits64 -> Bits32 -> PrimIO Bits64

export
txnBegin : DbHandle -> TxnMode -> IO (FFIResult TxnHandle)
txnBegin db mode = do
  let modeInt = txnModeToInt mode
  ptr <- primIO (prim__txn_begin (dbHandlePtr db) modeInt)
  if ptr == 0
    then pure $ Error "Failed to begin transaction"
    else case decSo (ptr /= 0) of
           Yes prf => pure $ Ok (MkTxnHandle ptr @{prf})
           No _ => pure $ Error "Null pointer returned"

-- Commit transaction
%foreign "C:lithoglyph_nif_txn_commit, liblithoglyph_nif"
prim__txn_commit : Bits64 -> PrimIO Int

export
txnCommit : TxnHandle -> IO (FFIResult ())
txnCommit txn = do
  result <- primIO (prim__txn_commit (txnHandlePtr txn))
  if result == 0
    then pure $ Ok ()
    else pure $ Error "Failed to commit transaction"

-- Abort transaction
%foreign "C:lithoglyph_nif_txn_abort, liblithoglyph_nif"
prim__txn_abort : Bits64 -> PrimIO Int

export
txnAbort : TxnHandle -> IO (FFIResult ())
txnAbort txn = do
  result <- primIO (prim__txn_abort (txnHandlePtr txn))
  if result == 0
    then pure $ Ok ()
    else pure $ Error "Failed to abort transaction"

-- Apply operation to transaction
-- Returns block ID and optional provenance hash
-- Input: transaction handle, operation CBOR bytes, operation length
-- Output: block_id (u64), has_provenance (bool), provenance_hash (32 bytes if present)
%foreign "C:lithoglyph_nif_apply, liblithoglyph_nif"
prim__apply : Bits64 -> Buffer -> Bits32 -> Bits64 -> Bits32 -> Buffer -> PrimIO Int

export
applyOperation : TxnHandle -> OperationData -> IO (FFIResult (BlockId, Maybe (List Bits8)))
applyOperation txn (MkOperationData bytes len) = do
  -- Allocate buffers for input and output
  opBuf <- newBuffer (cast len)
  -- Copy operation bytes to buffer
  let _ = writeBufferBytes opBuf 0 bytes len

  -- Allocate output buffer for provenance hash (32 bytes)
  provBuf <- newBuffer 32
  blockIdRef <- newBuffer 8  -- u64 output
  hasProvRef <- newBuffer 4  -- bool output (u32)

  result <- primIO (prim__apply
                     (txnHandlePtr txn)
                     opBuf
                     (cast len)
                     blockIdRef
                     hasProvRef
                     provBuf)

  if result /= 0
    then pure $ Error "Failed to apply operation"
    else do
      -- Read block ID
      blockId <- readBufferBits64 blockIdRef 0
      -- Check if provenance present
      hasProv <- readBufferBits32 hasProvRef 0

      if hasProv == 0
        then pure $ Ok (MkBlockId blockId, Nothing)
        else do
          -- Read provenance hash (32 bytes)
          provBytes <- readBufferBytes provBuf 0 32
          pure $ Ok (MkBlockId blockId, Just provBytes)

-- Get database schema (CBOR-encoded)
-- Returns: length (u32), data buffer
%foreign "C:lithoglyph_nif_schema, liblithoglyph_nif"
prim__schema : Bits64 -> Buffer -> Bits32 -> PrimIO Bits32

export
getSchema : DbHandle -> IO (FFIResult SchemaData)
getSchema db = do
  -- Allocate output buffer (max 1MB for schema)
  schemaBuf <- newBuffer (1024 * 1024)

  len <- primIO (prim__schema (dbHandlePtr db) schemaBuf (1024 * 1024))

  if len == 0
    then pure $ Error "Failed to get schema"
    else do
      schemaBytes <- readBufferBytes schemaBuf 0 (cast len)
      case decEq (length schemaBytes) (cast len) of
        Yes prf => pure $ Ok (MkSchemaData schemaBytes (cast len) @{prf})
        No _ => pure $ Error "Schema length mismatch"

-- Get journal entries since timestamp
-- Returns: length (u32), data buffer (CBOR-encoded array)
%foreign "C:lithoglyph_nif_journal, liblithoglyph_nif"
prim__journal : Bits64 -> Bits64 -> Buffer -> Bits32 -> PrimIO Bits32

export
getJournal : DbHandle -> Timestamp -> IO (FFIResult JournalData)
getJournal db (MkTimestamp since) = do
  -- Allocate output buffer (max 10MB for journal)
  journalBuf <- newBuffer (10 * 1024 * 1024)

  len <- primIO (prim__journal (dbHandlePtr db) since journalBuf (10 * 1024 * 1024))

  if len == 0
    then pure $ Error "Failed to get journal"
    else do
      journalBytes <- readBufferBytes journalBuf 0 (cast len)
      case decEq (length journalBytes) (cast len) of
        Yes prf => pure $ Ok (MkJournalData journalBytes (cast len) @{prf})
        No _ => pure $ Error "Journal length mismatch"

-- Helper: read bytes from buffer
readBufferBytes : Buffer -> (offset : Int) -> (len : Nat) -> IO (List Bits8)
readBufferBytes buf offset Z = pure []
readBufferBytes buf offset (S k) = do
  byte <- getBits8 buf offset
  rest <- readBufferBytes buf (offset + 1) k
  pure (byte :: rest)

-- Helper: write bytes to buffer
writeBufferBytes : Buffer -> (offset : Int) -> (bytes : List Bits8) -> (len : Nat) -> IO ()
writeBufferBytes buf offset [] Z = pure ()
writeBufferBytes buf offset (b :: bs) (S k) = do
  setBits8 buf offset b
  writeBufferBytes buf (offset + 1) bs k
writeBufferBytes _ _ _ _ = pure ()  -- length mismatch, ignore

-- Helper: read u64 from buffer (little-endian)
readBufferBits64 : Buffer -> (offset : Int) -> IO Bits64
readBufferBits64 buf offset = do
  b0 <- getBits8 buf (offset + 0)
  b1 <- getBits8 buf (offset + 1)
  b2 <- getBits8 buf (offset + 2)
  b3 <- getBits8 buf (offset + 3)
  b4 <- getBits8 buf (offset + 4)
  b5 <- getBits8 buf (offset + 5)
  b6 <- getBits8 buf (offset + 6)
  b7 <- getBits8 buf (offset + 7)
  pure $ (cast b0) + (cast b1 `shiftL` 8) + (cast b2 `shiftL` 16) + (cast b3 `shiftL` 24) +
         (cast b4 `shiftL` 32) + (cast b5 `shiftL` 40) + (cast b6 `shiftL` 48) + (cast b7 `shiftL` 56)

-- Helper: read u32 from buffer (little-endian)
readBufferBits32 : Buffer -> (offset : Int) -> IO Bits32
readBufferBits32 buf offset = do
  b0 <- getBits8 buf (offset + 0)
  b1 <- getBits8 buf (offset + 1)
  b2 <- getBits8 buf (offset + 2)
  b3 <- getBits8 buf (offset + 3)
  pure $ (cast b0) + (cast b1 `shiftL` 8) + (cast b2 `shiftL` 16) + (cast b3 `shiftL` 24)
