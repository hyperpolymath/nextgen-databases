-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Types.idr - Type definitions with proofs for FBQLdt ABI
-- Media-Type: text/x-idris

module FBQLdt.ABI.Types

import Data.So
import Data.Bits
-- import Proven.Core
-- import Proven.SafeMath
-- import Proven.SafeString

%default total

--------------------------------------------------------------------------------
-- Core Handle Types (Opaque, Non-Null)
--------------------------------------------------------------------------------

||| Non-null database handle
||| @ ptr The pointer value (guaranteed non-zero)
public export
data FbqldtDb : Type where
  MkFbqldtDb : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FbqldtDb

||| Non-null query handle
public export
data FbqldtQuery : Type where
  MkFbqldtQuery : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FbqldtQuery

||| Non-null schema handle
public export
data FbqldtSchema : Type where
  MkFbqldtSchema : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FbqldtSchema

||| Non-null type handle (for BoundedNat, NonEmptyString, etc.)
public export
data FbqldtType : Type where
  MkFbqldtType : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FbqldtType

--------------------------------------------------------------------------------
-- Status Codes
--------------------------------------------------------------------------------

||| Result status codes for FFI operations
public export
data FbqldtStatus : Type where
  ||| Operation succeeded
  StatusOk : FbqldtStatus
  ||| Invalid argument provided
  StatusInvalidArg : FbqldtStatus
  ||| Type mismatch in query
  StatusTypeMismatch : FbqldtStatus
  ||| Proof verification failed
  StatusProofFailed : FbqldtStatus
  ||| Permission denied
  StatusPermissionDenied : FbqldtStatus
  ||| Out of memory
  StatusOutOfMemory : FbqldtStatus
  ||| Internal error
  StatusInternalError : FbqldtStatus

||| Convert status to integer for FFI
public export
statusToInt : FbqldtStatus -> Int32
statusToInt StatusOk = 0
statusToInt StatusInvalidArg = 1
statusToInt StatusTypeMismatch = 2
statusToInt StatusProofFailed = 3
statusToInt StatusPermissionDenied = 4
statusToInt StatusOutOfMemory = 5
statusToInt StatusInternalError = 6

--------------------------------------------------------------------------------
-- Bounded Types (with proofs)
--------------------------------------------------------------------------------

||| BoundedNat with compile-time bounds checking
||| @ min Lower bound (inclusive)
||| @ max Upper bound (inclusive)
||| @ value The actual value
public export
record BoundedNat (min : Nat) (max : Nat) where
  constructor MkBoundedNat
  value : Nat
  {auto 0 lowerBound : So (value >= min)}
  {auto 0 upperBound : So (value <= max)}
  {auto 0 boundsValid : So (min <= max)}

||| BoundedInt with compile-time bounds checking
public export
record BoundedInt (min : Int) (max : Int) where
  constructor MkBoundedInt
  value : Int
  {auto 0 lowerBound : So (value >= min)}
  {auto 0 upperBound : So (value <= max)}
  {auto 0 boundsValid : So (min <= max)}

||| NonEmptyString with non-emptiness proof
public export
record NonEmptyString where
  constructor MkNonEmptyString
  value : String
  {auto 0 nonEmpty : So (length value > 0)}

||| Confidence score [0.0, 1.0] with bounds proof
public export
record Confidence where
  constructor MkConfidence
  value : Double
  {auto 0 lowerBound : So (value >= 0.0)}
  {auto 0 upperBound : So (value <= 1.0)}

--------------------------------------------------------------------------------
-- PROMPT Scores (Research-Grade Data Quality)
--------------------------------------------------------------------------------

||| PROMPT dimension score [0, 100]
public export
PromptDimension : Type
PromptDimension = BoundedNat 0 100

||| PROMPT scores for data quality assessment
||| Six dimensions: Provenance, Replicability, Objectivity, Methodology, Publication, Transparency
public export
record PromptScores where
  constructor MkPromptScores
  provenance : PromptDimension
  replicability : PromptDimension
  objectivity : PromptDimension
  methodology : PromptDimension
  publication : PromptDimension
  transparency : PromptDimension
  overall : PromptDimension
  {auto 0 overallCorrect : overall.value = (provenance.value + replicability.value + objectivity.value + methodology.value + publication.value + transparency.value) `div` 6}

--------------------------------------------------------------------------------
-- Provenance Tracking
--------------------------------------------------------------------------------

||| Actor identifier (non-empty)
public export
ActorId : Type
ActorId = NonEmptyString

||| Rationale for change (non-empty)
public export
Rationale : Type
Rationale = NonEmptyString

||| Unix timestamp (milliseconds since epoch)
public export
Timestamp : Type
Timestamp = Bits64

||| Tracked value with provenance
public export
record Tracked (a : Type) where
  constructor MkTracked
  value : a
  actor : ActorId
  rationale : Rationale
  timestamp : Timestamp

||| Proof that a tracked value has complete provenance
public export
0 hasProvenance : Tracked a -> Type
hasProvenance t = (So (length t.actor.value > 0), So (length t.rationale.value > 0), So (t.timestamp /= 0))

--------------------------------------------------------------------------------
-- Type Tags for CBOR Serialization
--------------------------------------------------------------------------------

||| Semantic tags for CBOR encoding (RFC 8949)
public export
data CborTag : Type where
  TagBoundedNat : CborTag
  TagBoundedInt : CborTag
  TagNonEmptyString : CborTag
  TagConfidence : CborTag
  TagPromptScores : CborTag
  TagProofBlob : CborTag
  TagTracked : CborTag

||| Convert tag to integer
public export
tagToInt : CborTag -> Bits32
tagToInt TagBoundedNat = 1000
tagToInt TagBoundedInt = 1001
tagToInt TagNonEmptyString = 1002
tagToInt TagConfidence = 1003
tagToInt TagPromptScores = 1004
tagToInt TagProofBlob = 1005
tagToInt TagTracked = 1006

--------------------------------------------------------------------------------
-- Memory Layout Proofs
--------------------------------------------------------------------------------

||| Proof that a type has the expected size in bytes
public export
0 HasSize : Type -> Nat -> Type
HasSize t n = () -- Placeholder for actual size proof

||| Proof that a field is aligned to the specified boundary
public export
0 Aligned : Nat -> Type
Aligned n = () -- Placeholder for actual alignment proof

||| Struct alignment and size proofs
public export
0 StructLayout : Type -> Type
StructLayout t = (HasSize t 8, Aligned 8)  -- 8-byte alignment for all types

--------------------------------------------------------------------------------
-- FFI Result Type
--------------------------------------------------------------------------------

||| Result type for FFI operations
public export
record FbqldtResult (a : Type) where
  constructor MkFbqldtResult
  status : FbqldtStatus
  value : Maybe a
  errorMessage : Maybe NonEmptyString

||| Smart constructor for success result
public export
ok : a -> FbqldtResult a
ok v = MkFbqldtResult StatusOk (Just v) Nothing

||| Smart constructor for error result
public export
err : FbqldtStatus -> NonEmptyString -> FbqldtResult a
err s msg = MkFbqldtResult s Nothing (Just msg)

--------------------------------------------------------------------------------
-- Integration with Proven Library
--------------------------------------------------------------------------------

||| Use SafeMath from proven library for bounded arithmetic
||| TODO: Implement using Proven.SafeMath when proven library is integrated
public export
safeBoundedAdd : BoundedNat min max -> BoundedNat min max -> Maybe (BoundedNat min max)
safeBoundedAdd a b = Nothing  -- Stub: implement with Proven.SafeMath later

||| Use SafeString from proven library for string validation
||| TODO: Implement using Proven.SafeString when proven library is integrated
public export
safeNonEmptyString : String -> Maybe NonEmptyString
safeNonEmptyString s = Nothing  -- Stub: implement with Proven.SafeString later
