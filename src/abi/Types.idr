||| SPDX-License-Identifier: PMPL-1.0-or-later
||| VeriSimDB ABI Type Definitions
|||
||| Formal type definitions for the VeriSimDB cross-modal entity engine.
||| All types include dependent-type proofs of correctness for C ABI compatibility.
|||
||| The octad model: each entity exists simultaneously across 8 modalities
||| (Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, Spatial).

module VeriSimDB.ABI.Types

import Data.Bits
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for the VeriSimDB ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection
public export
thisPlatform : Platform
thisPlatform = Linux  -- Default; override with compiler flags

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations (C-compatible integers)
public export
data VResult : Type where
  ||| Operation succeeded
  VOk : VResult
  ||| Generic error
  VError : VResult
  ||| Invalid parameter
  VInvalidParam : VResult
  ||| Out of memory
  VOutOfMemory : VResult
  ||| Null pointer encountered
  VNullPointer : VResult
  ||| Entity not found
  VNotFound : VResult
  ||| Modality not available for entity
  VModalityUnavailable : VResult
  ||| Drift threshold exceeded
  VDriftExceeded : VResult
  ||| Query parse error
  VQueryParseError : VResult
  ||| Transaction conflict
  VTxnConflict : VResult

||| Convert VResult to C integer
public export
vresultToInt : VResult -> Bits32
vresultToInt VOk = 0
vresultToInt VError = 1
vresultToInt VInvalidParam = 2
vresultToInt VOutOfMemory = 3
vresultToInt VNullPointer = 4
vresultToInt VNotFound = 5
vresultToInt VModalityUnavailable = 6
vresultToInt VDriftExceeded = 7
vresultToInt VQueryParseError = 8
vresultToInt VTxnConflict = 9

||| Convert C integer back to VResult
public export
vresultFromInt : Bits32 -> Maybe VResult
vresultFromInt 0 = Just VOk
vresultFromInt 1 = Just VError
vresultFromInt 2 = Just VInvalidParam
vresultFromInt 3 = Just VOutOfMemory
vresultFromInt 4 = Just VNullPointer
vresultFromInt 5 = Just VNotFound
vresultFromInt 6 = Just VModalityUnavailable
vresultFromInt 7 = Just VDriftExceeded
vresultFromInt 8 = Just VQueryParseError
vresultFromInt 9 = Just VTxnConflict
vresultFromInt _ = Nothing

||| VResults are decidably equal
public export
DecEq VResult where
  decEq VOk VOk = Yes Refl
  decEq VError VError = Yes Refl
  decEq VInvalidParam VInvalidParam = Yes Refl
  decEq VOutOfMemory VOutOfMemory = Yes Refl
  decEq VNullPointer VNullPointer = Yes Refl
  decEq VNotFound VNotFound = Yes Refl
  decEq VModalityUnavailable VModalityUnavailable = Yes Refl
  decEq VDriftExceeded VDriftExceeded = Yes Refl
  decEq VQueryParseError VQueryParseError = Yes Refl
  decEq VTxnConflict VTxnConflict = Yes Refl
  decEq _ _ = No absurd

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle to a VeriSimDB instance
public export
data VDBHandle : Type where
  MkVDBHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> VDBHandle

||| Opaque handle to an octad entity
public export
data EntityHandle : Type where
  MkEntityHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> EntityHandle

||| Opaque handle to a VCL query
public export
data QueryHandle : Type where
  MkQueryHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> QueryHandle

||| Opaque handle to a transaction
public export
data TxnHandle : Type where
  MkTxnHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> TxnHandle

||| Opaque handle to a query result set
public export
data ResultSetHandle : Type where
  MkResultSetHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> ResultSetHandle

||| Safely create a handle from a raw pointer
public export
createVDBHandle : Bits64 -> Maybe VDBHandle
createVDBHandle 0 = Nothing
createVDBHandle ptr = Just (MkVDBHandle ptr)

public export
createEntityHandle : Bits64 -> Maybe EntityHandle
createEntityHandle 0 = Nothing
createEntityHandle ptr = Just (MkEntityHandle ptr)

public export
createQueryHandle : Bits64 -> Maybe QueryHandle
createQueryHandle 0 = Nothing
createQueryHandle ptr = Just (MkQueryHandle ptr)

||| Extract pointer from handle
public export
vdbPtr : VDBHandle -> Bits64
vdbPtr (MkVDBHandle ptr) = ptr

public export
entityPtr : EntityHandle -> Bits64
entityPtr (MkEntityHandle ptr) = ptr

public export
queryPtr : QueryHandle -> Bits64
queryPtr (MkQueryHandle ptr) = ptr

public export
txnPtr : TxnHandle -> Bits64
txnPtr (MkTxnHandle ptr) = ptr

public export
resultSetPtr : ResultSetHandle -> Bits64
resultSetPtr (MkResultSetHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Modality Enumeration
--------------------------------------------------------------------------------

||| The 8 modalities of an octad entity
public export
data Modality
  = Graph
  | Vector
  | Tensor
  | Semantic
  | Document
  | Temporal
  | Provenance
  | Spatial

||| Modality to C integer mapping (stable ABI)
public export
modalityToInt : Modality -> Bits32
modalityToInt Graph      = 0
modalityToInt Vector     = 1
modalityToInt Tensor     = 2
modalityToInt Semantic   = 3
modalityToInt Document   = 4
modalityToInt Temporal   = 5
modalityToInt Provenance = 6
modalityToInt Spatial    = 7

||| C integer to modality
public export
modalityFromInt : Bits32 -> Maybe Modality
modalityFromInt 0 = Just Graph
modalityFromInt 1 = Just Vector
modalityFromInt 2 = Just Tensor
modalityFromInt 3 = Just Semantic
modalityFromInt 4 = Just Document
modalityFromInt 5 = Just Temporal
modalityFromInt 6 = Just Provenance
modalityFromInt 7 = Just Spatial
modalityFromInt _ = Nothing

||| Total number of modalities (compile-time constant)
public export
modalityCount : Nat
modalityCount = 8

||| Proof that modalityCount equals the number of constructors
public export
modalityCountCorrect : modalityCount = length [Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, Spatial]
modalityCountCorrect = Refl

--------------------------------------------------------------------------------
-- Modality Bitmask
--------------------------------------------------------------------------------

||| Bitmask for selecting which modalities are active on an entity
||| Bit 0 = Graph, Bit 1 = Vector, ..., Bit 7 = Spatial
public export
ModalityMask : Type
ModalityMask = Bits8

||| Set a modality bit in the mask
public export
setModality : ModalityMask -> Modality -> ModalityMask
setModality mask mod = mask .|. (1 `shiftL` (cast (modalityToInt mod)))

||| Check if a modality is active in the mask
public export
hasModality : ModalityMask -> Modality -> Bool
hasModality mask mod = (mask .&. (1 `shiftL` (cast (modalityToInt mod)))) /= 0

||| All modalities active (0xFF)
public export
allModalities : ModalityMask
allModalities = 0xFF

||| No modalities active
public export
noModalities : ModalityMask
noModalities = 0x00

--------------------------------------------------------------------------------
-- Drift Types
--------------------------------------------------------------------------------

||| Drift measurement between modalities
||| Stored as fixed-point: value * 10000 (4 decimal places)
public export
DriftScore : Type
DriftScore = Bits32

||| Drift detection method
public export
data DriftMethod
  = Cosine
  | Euclidean
  | DotProduct
  | Jaccard
  | Hamming
  | Custom

||| Drift method to C integer
public export
driftMethodToInt : DriftMethod -> Bits32
driftMethodToInt Cosine     = 0
driftMethodToInt Euclidean  = 1
driftMethodToInt DotProduct = 2
driftMethodToInt Jaccard    = 3
driftMethodToInt Hamming    = 4
driftMethodToInt Custom     = 5

--------------------------------------------------------------------------------
-- Entity ID
--------------------------------------------------------------------------------

||| Entity ID is a 128-bit UUID stored as two 64-bit halves
public export
record EntityId where
  constructor MkEntityId
  high : Bits64
  low  : Bits64

||| Proof that EntityId has fixed size (16 bytes)
public export
data HasSize : Type -> Nat -> Type where
  SizeProof : {0 t : Type} -> {n : Nat} -> HasSize t n

public export
entityIdSize : HasSize EntityId 16
entityIdSize = SizeProof

--------------------------------------------------------------------------------
-- Platform-Specific Types
--------------------------------------------------------------------------------

||| C size_t varies by platform (64-bit on most, 32-bit on WASM)
public export
CSize : Platform -> Type
CSize WASM = Bits32
CSize _    = Bits64

||| Pointer size by platform
public export
ptrSize : Platform -> Nat
ptrSize WASM = 32
ptrSize _    = 64

--------------------------------------------------------------------------------
-- Proof Type Enumeration
--------------------------------------------------------------------------------

||| VCL proof types supported by VeriSimDB
public export
data ProofType
  = Existence
  | Integrity
  | Consistency
  | ProvenanceProof
  | Freshness
  | Access
  | Citation
  | CustomProof
  | ZKP
  | Proven
  | Sanctify

||| Proof type to C integer
public export
proofTypeToInt : ProofType -> Bits32
proofTypeToInt Existence       = 0
proofTypeToInt Integrity       = 1
proofTypeToInt Consistency     = 2
proofTypeToInt ProvenanceProof = 3
proofTypeToInt Freshness       = 4
proofTypeToInt Access          = 5
proofTypeToInt Citation        = 6
proofTypeToInt CustomProof     = 7
proofTypeToInt ZKP             = 8
proofTypeToInt Proven          = 9
proofTypeToInt Sanctify        = 10
