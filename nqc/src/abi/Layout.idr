-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Layout.idr — Memory layout definitions for the NQC ABI.
--
-- Defines C-compatible struct layouts for FFI boundary crossing. These
-- layouts are used by the Zig FFI to construct and destructure values
-- that cross the Gleam/Erlang ↔ Zig boundary.

module Layout

import Types

%default total

-- =========================================================================
-- C-compatible struct sizes
-- =========================================================================

||| Size in bytes of a C-compatible query request struct.
||| Layout: [ptr query_data (8)] [u32 query_len (4)] [u32 padding (4)] = 16
public export
QueryRequestSize : Nat
QueryRequestSize = 16

||| Size in bytes of a C-compatible output format enum.
||| Layout: [u8 format_tag (1)] = 1
public export
OutputFormatSize : Nat
OutputFormatSize = 1

||| Tag values for OutputFormat enum.
public export
formatTag : Types.OutputFormat -> Bits8
formatTag Types.Table = 0
formatTag Types.Json  = 1
formatTag Types.Csv   = 2

||| Proof: all format tags are distinct.
export
formatTagsDistinct : (a, b : Types.OutputFormat) -> Not (a = b)
                   -> Not (formatTag a = formatTag b)
formatTagsDistinct Table Json  neq Refl impossible
formatTagsDistinct Table Csv   neq Refl impossible
formatTagsDistinct Json  Table neq Refl impossible
formatTagsDistinct Json  Csv   neq Refl impossible
formatTagsDistinct Csv   Table neq Refl impossible
formatTagsDistinct Csv   Json  neq Refl impossible
formatTagsDistinct Table Table neq _ = neq Refl
formatTagsDistinct Json  Json  neq _ = neq Refl
formatTagsDistinct Csv   Csv   neq _ = neq Refl

||| Tag values for DatabaseId enum.
public export
databaseIdTag : Types.DatabaseId -> Bits8
databaseIdTag Types.VQL = 0
databaseIdTag Types.GQL = 1
databaseIdTag Types.KQL = 2

||| Size in bytes of a C-compatible client error struct.
||| Layout: [u8 error_tag (1)] [u8 padding (3)] [u32 status_or_zero (4)]
|||         [ptr message_data (8)] [u32 message_len (4)] [u32 padding (4)] = 24
public export
ClientErrorSize : Nat
ClientErrorSize = 24

||| Error tag values for ClientErr variants.
public export
clientErrTag : Types.ClientErr -> Bits8
clientErrTag (Types.RequestErr _)   = 0
clientErrTag (Types.TransportErr _) = 1
clientErrTag (Types.ServerErr _ _)  = 2
clientErrTag (Types.ParseErr _)     = 3

-- =========================================================================
-- Alignment constraints
-- =========================================================================

||| All struct sizes are multiples of 8 (64-bit aligned).
export
queryRequestAligned : mod QueryRequestSize 8 = 0
queryRequestAligned = Refl

export
clientErrorAligned : mod ClientErrorSize 8 = 0
clientErrorAligned = Refl

-- =========================================================================
-- Field offset proofs
-- =========================================================================

||| Query request field offsets.
public export
record QueryRequestLayout where
  constructor MkQueryRequestLayout
  queryDataOffset : Nat  -- 0
  queryLenOffset  : Nat  -- 8

export
queryRequestLayout : QueryRequestLayout
queryRequestLayout = MkQueryRequestLayout 0 8

||| Proof: query data comes before query length.
export
queryFieldOrder : queryRequestLayout.queryDataOffset < queryRequestLayout.queryLenOffset = True
queryFieldOrder = Refl
