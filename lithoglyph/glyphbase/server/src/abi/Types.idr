-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Lith ABI Type Definitions with Dependent Type Proofs
--
-- This module defines the ABI types for the Lith/Lithoglyph database
-- with formal verification of memory safety and layout correctness.

module Types

import Data.Bits
import Data.So

%default total

-- Non-null pointer guarantee at type level
-- The So proof ensures the pointer value cannot be zero
public export
data DbHandle : Type where
  MkDbHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> DbHandle

public export
data TxnHandle : Type where
  MkTxnHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> TxnHandle

-- Transaction mode enumeration
-- Corresponds to Gleam TransactionMode type
public export
data TxnMode : Type where
  ReadOnly  : TxnMode
  ReadWrite : TxnMode

-- Convert TxnMode to integer for FFI
public export
txnModeToInt : TxnMode -> Bits32
txnModeToInt ReadOnly  = 0
txnModeToInt ReadWrite = 1

-- Result type for operations that can fail
-- Matches Erlang {ok, Value} | {error, Reason} convention
public export
data FFIResult : Type -> Type where
  Ok    : (value : a) -> FFIResult a
  Error : (reason : String) -> FFIResult a

-- Version tuple (major, minor, patch)
public export
record Version where
  constructor MkVersion
  major : Bits8
  minor : Bits8
  patch : Bits8

-- Proof that version numbers are valid (0-255)
public export
0 validVersion : Version -> Type
validVersion v = (v.major <= 255, v.minor <= 255, v.patch <= 255)

-- Block ID returned from apply operation
-- Stone-carved database block identifier
public export
data BlockId : Type where
  MkBlockId : (id : Bits64) -> BlockId

-- Timestamp for journal queries (Unix epoch microseconds)
public export
data Timestamp : Type where
  MkTimestamp : (micros : Bits64) -> Timestamp

-- CBOR-encoded operation data
-- Raw bytes representing serialized Lith operation
public export
data OperationData : Type where
  MkOperationData : (bytes : List Bits8) -> (len : Nat) ->
                    {auto 0 lengthCorrect : length bytes = len} ->
                    OperationData

-- Schema data (CBOR-encoded)
public export
data SchemaData : Type where
  MkSchemaData : (bytes : List Bits8) -> (len : Nat) ->
                 {auto 0 lengthCorrect : length bytes = len} ->
                 SchemaData

-- Journal data (CBOR-encoded)
public export
data JournalData : Type where
  MkJournalData : (bytes : List Bits8) -> (len : Nat) ->
                  {auto 0 lengthCorrect : length bytes = len} ->
                  JournalData

-- Database path (null-terminated C string)
public export
record DbPath where
  constructor MkDbPath
  path : String
  {auto 0 nonEmpty : So (length path > 0)}

-- Extract raw pointer value (for FFI)
-- This is safe because the constructor proves non-null
public export
dbHandlePtr : DbHandle -> Bits64
dbHandlePtr (MkDbHandle ptr) = ptr

public export
txnHandlePtr : TxnHandle -> Bits64
txnHandlePtr (MkTxnHandle ptr) = ptr

-- Functor instance for FFIResult
public export
Functor FFIResult where
  map f (Ok x) = Ok (f x)
  map _ (Error e) = Error e

-- Monad instance for FFIResult
public export
Monad FFIResult where
  (Ok x) >>= f = f x
  (Error e) >>= _ = Error e

public export
Applicative FFIResult where
  pure = Ok
  (Ok f) <*> (Ok x) = Ok (f x)
  (Error e) <*> _ = Error e
  _ <*> (Error e) = Error e
