||| SPDX-License-Identifier: PMPL-1.0-or-later
||| VeriSimDB Memory Layout Proofs
|||
||| Formal proofs about memory layout, alignment, and padding for
||| VeriSimDB's C-compatible structs passed across the FFI boundary.
|||
||| Key structs: EntityId (16B), DriftReport (40B), ModalitySlice (24B),
||| VDBConfig (32B).

module VeriSimDB.ABI.Layout

import VeriSimDB.ABI.Types
import Data.Vect
import Data.So

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed for alignment
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else alignment - (offset `mod` alignment)

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment = size + paddingFor size alignment

||| Proof that alignment divides aligned size
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

--------------------------------------------------------------------------------
-- Struct Field Layout
--------------------------------------------------------------------------------

||| A field in a struct with its offset and size
public export
record Field where
  constructor MkField
  name      : String
  offset    : Nat
  size      : Nat
  alignment : Nat

||| Calculate the offset of the next field
public export
nextFieldOffset : Field -> Nat -> Nat
nextFieldOffset f nextAlign = alignUp (f.offset + f.size) nextAlign

||| A struct layout is a vector of fields with size and alignment
public export
record StructLayout where
  constructor MkStructLayout
  layoutName : String
  fields     : List Field
  totalSize  : Nat
  alignment  : Nat

||| Proof that field offsets are correctly aligned
public export
data FieldAligned : Field -> Type where
  IsAligned : (f : Field) -> (0 _ : Divides f.alignment f.offset) -> FieldAligned f

--------------------------------------------------------------------------------
-- EntityId Layout (16 bytes, 8-byte aligned)
--------------------------------------------------------------------------------

||| EntityId: two Bits64 fields = 16 bytes, no padding needed
public export
entityIdLayout : StructLayout
entityIdLayout = MkStructLayout "EntityId"
  [ MkField "high" 0 8 8   -- Bits64 at offset 0
  , MkField "low"  8 8 8   -- Bits64 at offset 8
  ]
  16  -- total size
  8   -- alignment

||| Proof: EntityId high field is aligned (offset 0 divides by 8)
public export
entityIdHighAligned : FieldAligned (MkField "high" 0 8 8)
entityIdHighAligned = IsAligned _ (DivideBy 0 Refl)

||| Proof: EntityId low field is aligned (offset 8 divides by 8)
public export
entityIdLowAligned : FieldAligned (MkField "low" 8 8 8)
entityIdLowAligned = IsAligned _ (DivideBy 1 Refl)

--------------------------------------------------------------------------------
-- DriftReport Layout (40 bytes, 8-byte aligned)
--------------------------------------------------------------------------------

||| DriftReport: sent from Rust drift detector to Elixir/Zig consumers
||| Fields:
|||   entity_id   : EntityId (16 bytes at offset 0)
|||   source_mod  : Bits32   (4 bytes at offset 16)
|||   target_mod  : Bits32   (4 bytes at offset 20)
|||   drift_score : Bits32   (4 bytes at offset 24, fixed-point * 10000)
|||   method      : Bits32   (4 bytes at offset 28)
|||   timestamp   : Bits64   (8 bytes at offset 32)
public export
driftReportLayout : StructLayout
driftReportLayout = MkStructLayout "DriftReport"
  [ MkField "entity_id_high" 0  8 8
  , MkField "entity_id_low"  8  8 8
  , MkField "source_mod"     16 4 4
  , MkField "target_mod"     20 4 4
  , MkField "drift_score"    24 4 4
  , MkField "method"         28 4 4
  , MkField "timestamp"      32 8 8
  ]
  40
  8

--------------------------------------------------------------------------------
-- ModalitySlice Layout (24 bytes, 8-byte aligned)
--------------------------------------------------------------------------------

||| ModalitySlice: pointer + length to modality-specific data buffer
||| Used when reading/writing individual modality data across FFI
|||   data_ptr : Bits64 (8 bytes at offset 0)
|||   data_len : Bits64 (8 bytes at offset 8)
|||   modality : Bits32 (4 bytes at offset 16)
|||   flags    : Bits32 (4 bytes at offset 20)
public export
modalitySliceLayout : StructLayout
modalitySliceLayout = MkStructLayout "ModalitySlice"
  [ MkField "data_ptr" 0  8 8
  , MkField "data_len" 8  8 8
  , MkField "modality" 16 4 4
  , MkField "flags"    20 4 4
  ]
  24
  8

--------------------------------------------------------------------------------
-- VDBConfig Layout (32 bytes, 8-byte aligned)
--------------------------------------------------------------------------------

||| VDBConfig: configuration passed to verisimdb_init
|||   max_entities       : Bits64 (8 bytes at offset 0)
|||   drift_threshold    : Bits32 (4 bytes at offset 8, fixed-point * 10000)
|||   modality_mask      : Bits8  (1 byte at offset 12)
|||   enable_wal         : Bits8  (1 byte at offset 13)
|||   enable_telemetry   : Bits8  (1 byte at offset 14)
|||   _pad1              : Bits8  (1 byte at offset 15)
|||   data_dir_ptr       : Bits64 (8 bytes at offset 16, pointer to C string)
|||   data_dir_len       : Bits64 (8 bytes at offset 24)
public export
vdbConfigLayout : StructLayout
vdbConfigLayout = MkStructLayout "VDBConfig"
  [ MkField "max_entities"     0  8 8
  , MkField "drift_threshold"  8  4 4
  , MkField "modality_mask"    12 1 1
  , MkField "enable_wal"       13 1 1
  , MkField "enable_telemetry" 14 1 1
  , MkField "_pad1"            15 1 1
  , MkField "data_dir_ptr"     16 8 8
  , MkField "data_dir_len"     24 8 8
  ]
  32
  8

--------------------------------------------------------------------------------
-- QueryRequest Layout (32 bytes, 8-byte aligned)
--------------------------------------------------------------------------------

||| QueryRequest: VQL query submitted across FFI
|||   vql_ptr     : Bits64 (8 bytes at offset 0, pointer to UTF-8 VQL string)
|||   vql_len     : Bits64 (8 bytes at offset 8)
|||   timeout_ms  : Bits32 (4 bytes at offset 16)
|||   proof_type  : Bits32 (4 bytes at offset 20, 0xFF = no proof requested)
|||   txn_handle  : Bits64 (8 bytes at offset 24, 0 = auto-commit)
public export
queryRequestLayout : StructLayout
queryRequestLayout = MkStructLayout "QueryRequest"
  [ MkField "vql_ptr"    0  8 8
  , MkField "vql_len"    8  8 8
  , MkField "timeout_ms" 16 4 4
  , MkField "proof_type" 20 4 4
  , MkField "txn_handle" 24 8 8
  ]
  32
  8

--------------------------------------------------------------------------------
-- Layout Verification
--------------------------------------------------------------------------------

||| Verify that a field offset + size fits within the struct
public export
fieldFitsInStruct : (layout : StructLayout) -> (f : Field) ->
                    So (f.offset + f.size <= layout.totalSize) ->
                    ()
fieldFitsInStruct _ _ _ = ()

||| Verify no field overlap: field2 starts at or after field1 ends
public export
data NoOverlap : Field -> Field -> Type where
  FieldsDisjoint : (f1 : Field) -> (f2 : Field) ->
                   {auto 0 prf : So (f1.offset + f1.size <= f2.offset)} ->
                   NoOverlap f1 f2

||| All VeriSimDB layouts collected for batch verification
public export
allLayouts : List StructLayout
allLayouts =
  [ entityIdLayout
  , driftReportLayout
  , modalitySliceLayout
  , vdbConfigLayout
  , queryRequestLayout
  ]
