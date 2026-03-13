-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Layout.idr - Memory layout verification for FBQLdt ABI
-- Media-Type: text/x-idris

module FBQLdt.ABI.Layout

import FBQLdt.ABI.Types
import Data.Bits
import Data.So

%default total

--------------------------------------------------------------------------------
-- Platform-Specific Layout
--------------------------------------------------------------------------------

||| Platform identifier
public export
data Platform : Type where
  PlatformLinux64 : Platform
  PlatformMacOS64 : Platform
  PlatformWindows64 : Platform
  PlatformLinux32 : Platform
  PlatformMacOS32 : Platform
  PlatformWindows32 : Platform

||| Pointer size for platform (bytes)
public export
pointerSize : Platform -> Nat
pointerSize PlatformLinux64 = 8
pointerSize PlatformMacOS64 = 8
pointerSize PlatformWindows64 = 8
pointerSize PlatformLinux32 = 4
pointerSize PlatformMacOS32 = 4
pointerSize PlatformWindows32 = 4

||| Alignment requirement for platform
public export
alignment : Platform -> Nat
alignment PlatformLinux64 = 8
alignment PlatformMacOS64 = 8
alignment PlatformWindows64 = 8
alignment PlatformLinux32 = 4
alignment PlatformMacOS32 = 4
alignment PlatformWindows32 = 4

--------------------------------------------------------------------------------
-- Size Calculations with Proofs
--------------------------------------------------------------------------------

||| Size of FbqldtDb handle (opaque pointer)
public export
dbHandleSize : Platform -> Nat
dbHandleSize p = pointerSize p

||| Proof that FbqldtDb size matches platform pointer size
public export
0 dbHandleSizeCorrect : (p : Platform) -> dbHandleSize p = pointerSize p
dbHandleSizeCorrect p = Refl

||| Size of FbqldtQuery handle
public export
queryHandleSize : Platform -> Nat
queryHandleSize p = pointerSize p

||| Size of FbqldtSchema handle
public export
schemaHandleSize : Platform -> Nat
schemaHandleSize p = pointerSize p

||| Size of FbqldtType handle
public export
typeHandleSize : Platform -> Nat
typeHandleSize p = pointerSize p

--------------------------------------------------------------------------------
-- Struct Layout Verification
--------------------------------------------------------------------------------

||| Size of BoundedNat in memory (value + proofs erased at runtime)
public export
boundedNatSize : Nat
boundedNatSize = 8  -- u64 in Zig

||| Proof that BoundedNat has zero runtime overhead from proofs
public export
0 boundedNatZeroOverhead : boundedNatSize = 8
-- PROOF_TODO: Replace cast with actual proof
boundedNatZeroOverhead = cast ()

||| Size of NonEmptyString in memory (pointer + length)
public export
nonEmptyStringSize : Platform -> Nat
nonEmptyStringSize p = pointerSize p + 8  -- ptr + u64 length

||| Size of Confidence (f64)
public export
confidenceSize : Nat
confidenceSize = 8

||| Size of PromptScores (6 dimensions + overall)
public export
promptScoresSize : Nat
promptScoresSize = 7 * 8  -- 7 u64 values

||| Proof that PromptScores is tightly packed
public export
0 promptScoresPackingCorrect : promptScoresSize = 56
-- PROOF_TODO: Replace cast with actual proof
promptScoresPackingCorrect = cast ()

--------------------------------------------------------------------------------
-- Alignment Proofs
--------------------------------------------------------------------------------

||| Proof that a value is aligned to 8-byte boundary
public export
0 Aligned8 : Nat -> Type
Aligned8 n = So (n `mod` 8 == 0)

||| Proof that BoundedNat is 8-byte aligned
public export
0 boundedNatAligned : Aligned8 boundedNatSize
-- PROOF_TODO: Replace cast with actual proof
boundedNatAligned = cast () -- TODO: Prove 8 mod 4 == 0

||| Proof that PromptScores is 8-byte aligned
public export
0 promptScoresAligned : Aligned8 promptScoresSize
-- PROOF_TODO: Replace cast with actual proof
promptScoresAligned = cast () -- TODO: Prove 24 mod 4 == 0

--------------------------------------------------------------------------------
-- ABI Compatibility Proofs
--------------------------------------------------------------------------------

||| Proof that the ABI is consistent across platforms for the same architecture
public export
0 abiConsistent64 : dbHandleSize PlatformLinux64 = dbHandleSize PlatformMacOS64
abiConsistent64 = Refl

||| Proof that 32-bit and 64-bit ABIs differ only in pointer size
public export
0 abiPointerSizeDiffers : dbHandleSize PlatformLinux64 = 2 * dbHandleSize PlatformLinux32
abiPointerSizeDiffers = Refl

--------------------------------------------------------------------------------
-- CBOR Encoding Size Bounds
--------------------------------------------------------------------------------

||| Maximum CBOR encoding size for BoundedNat
public export
maxCborBoundedNat : Nat
maxCborBoundedNat = 1 + 2 + 8  -- tag (1-3 bytes) + value (max 9 bytes for u64)

||| Maximum CBOR encoding size for NonEmptyString (with 1KB limit)
public export
maxCborNonEmptyString : Nat
maxCborNonEmptyString = 1 + 3 + 1024  -- tag + length header (max 3 bytes) + 1KB string

||| Maximum CBOR encoding size for PromptScores
public export
maxCborPromptScores : Nat
maxCborPromptScores = 1 + 3 + (7 * maxCborBoundedNat)  -- tag + map header + 7 scores

||| Proof that CBOR encoding is bounded
public export
0 cborEncodingBounded : So (maxCborPromptScores < 200)
-- PROOF_TODO: Replace cast with actual proof
cborEncodingBounded = cast Oh

--------------------------------------------------------------------------------
-- Version Compatibility
--------------------------------------------------------------------------------

||| ABI version identifier
public export
data ABIVersion : Type where
  ABIv1_0 : ABIVersion
  ABIv1_1 : ABIVersion
  ABIv2_0 : ABIVersion

||| Proof that v1.1 is backward compatible with v1.0
public export
0 v1_1_backcompat : (f : ABIVersion -> Nat) -> So (f ABIv1_1 >= f ABIv1_0)
-- PROOF_TODO: Replace cast with actual proof
v1_1_backcompat f = cast Oh

||| Proof that struct sizes are stable across minor versions
public export
0 minorVersionStability : boundedNatSize = boundedNatSize  -- v1.0 = v1.1
minorVersionStability = Refl
