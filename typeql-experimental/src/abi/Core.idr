-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Core.idr — Foundation types for VQL-dt++ type system kernel
--
-- Defines the shared vocabulary used by all six extensions:
-- modalities, usage quantities, effect labels, hexad references,
-- and primitive query result types.

module Core

%default total

-- ============================================================================
-- VQL Modalities (Octad: 8 modalities)
-- ============================================================================

||| The eight VeriSimDB modalities. Each entity exists simultaneously across
||| all modalities in a HEXAD.
public export
data Modality : Type where
  Graph      : Modality
  Vector     : Modality
  Tensor     : Modality
  Semantic   : Modality
  Document   : Modality
  Temporal   : Modality
  Provenance : Modality
  Spatial    : Modality

||| Decidable equality for modalities.
public export
Eq Modality where
  Graph      == Graph      = True
  Vector     == Vector     = True
  Tensor     == Tensor     = True
  Semantic   == Semantic   = True
  Document   == Document   = True
  Temporal   == Temporal   = True
  Provenance == Provenance = True
  Spatial    == Spatial    = True
  _          == _          = False

||| Show instance for error messages and debugging.
public export
Show Modality where
  show Graph      = "GRAPH"
  show Vector     = "VECTOR"
  show Tensor     = "TENSOR"
  show Semantic   = "SEMANTIC"
  show Document   = "DOCUMENT"
  show Temporal   = "TEMPORAL"
  show Provenance = "PROVENANCE"
  show Spatial    = "SPATIAL"

||| All eight modalities as a list.
public export
allModalities : List Modality
allModalities = [Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, Spatial]

-- ============================================================================
-- HEXAD References
-- ============================================================================

||| A HEXAD reference (UUID as a string for now).
||| In a real implementation this would be a validated UUID type.
public export
record HexadRef where
  constructor MkHexadRef
  uuid : String

public export
Eq HexadRef where
  (MkHexadRef a) == (MkHexadRef b) = a == b

public export
Show HexadRef where
  show (MkHexadRef u) = "HEXAD<" ++ u ++ ">"

-- ============================================================================
-- Effect Labels
-- ============================================================================

||| Effect labels for the effect system extension. A query declares which
||| effects it performs, and the checker verifies subsumption.
public export
data EffectLabel : Type where
  Read      : EffectLabel
  Write     : EffectLabel
  Cite      : EffectLabel
  Audit     : EffectLabel
  Transform : EffectLabel
  Federate  : EffectLabel

public export
Eq EffectLabel where
  Read      == Read      = True
  Write     == Write     = True
  Cite      == Cite      = True
  Audit     == Audit     = True
  Transform == Transform = True
  Federate  == Federate  = True
  _         == _         = False

public export
Show EffectLabel where
  show Read      = "Read"
  show Write     = "Write"
  show Cite      = "Cite"
  show Audit     = "Audit"
  show Transform = "Transform"
  show Federate  = "Federate"

-- ============================================================================
-- Usage Quantities
-- ============================================================================

||| Usage quantity for resource accounting. Mirrors Idris2's QTT:
||| - Zero    = erased (type-level only)
||| - Once    = linear (used exactly once)
||| - Many    = unrestricted (used any number of times)
||| - Bounded = used at most n times
public export
data Usage : Type where
  Zero    : Usage
  Once    : Usage
  Many    : Usage
  Bounded : (n : Nat) -> Usage

public export
Show Usage where
  show Zero        = "0"
  show Once        = "1"
  show Many        = "ω"
  show (Bounded n) = show n

-- ============================================================================
-- Primitive Value Types
-- ============================================================================

||| Primitive types that appear in query results.
public export
data PrimType : Type where
  TInt       : PrimType
  TFloat     : PrimType
  TString    : PrimType
  TBool      : PrimType
  TVector    : (dim : Nat) -> PrimType
  TTensor    : (shape : List Nat) -> PrimType
  TUuid      : PrimType
  TTimestamp : PrimType

public export
Show PrimType where
  show TInt          = "Int"
  show TFloat        = "Float"
  show TString       = "String"
  show TBool         = "Bool"
  show (TVector d)   = "Vector<" ++ show d ++ ">"
  show (TTensor s)   = "Tensor<" ++ show s ++ ">"
  show TUuid         = "UUID"
  show TTimestamp    = "Timestamp"

-- ============================================================================
-- Query Result Types
-- ============================================================================

||| A query result carries data from specific modalities.
public export
record QueryResult where
  constructor MkQueryResult
  modalities : List Modality
  rowCount   : Nat

||| Proof type identifiers from VQL's PROOF clause.
public export
data ProofKind : Type where
  Existence  : ProofKind
  Citation   : ProofKind
  Access     : ProofKind
  Integrity  : ProofKind
  ProvenancePK : ProofKind
  Custom     : ProofKind

public export
Show ProofKind where
  show Existence    = "EXISTENCE"
  show Citation     = "CITATION"
  show Access       = "ACCESS"
  show Integrity    = "INTEGRITY"
  show ProvenancePK = "PROVENANCE"
  show Custom       = "CUSTOM"

-- ============================================================================
-- Error Types
-- ============================================================================

||| Errors that can arise during type checking of VQL-dt++ queries.
public export
data TQLError : Type where
  LinearityViolation  : String -> TQLError
  SessionViolation    : String -> TQLError
  EffectViolation     : String -> TQLError
  ModalViolation      : String -> TQLError
  ProofViolation      : String -> TQLError
  UsageViolation      : String -> TQLError
  TypeError           : String -> TQLError

public export
Show TQLError where
  show (LinearityViolation msg) = "Linearity violation: " ++ msg
  show (SessionViolation msg)   = "Session violation: " ++ msg
  show (EffectViolation msg)    = "Effect violation: " ++ msg
  show (ModalViolation msg)     = "Modal violation: " ++ msg
  show (ProofViolation msg)     = "Proof violation: " ++ msg
  show (UsageViolation msg)     = "Usage violation: " ++ msg
  show (TypeError msg)          = "Type error: " ++ msg

-- ============================================================================
-- List Membership (used by multiple extensions)
-- ============================================================================

||| Proof that an element is a member of a list.
public export
data Elem : a -> List a -> Type where
  Here  : Elem x (x :: xs)
  There : Elem x xs -> Elem x (y :: xs)

||| Proof that one list is a subset of another (every element of the first
||| is also in the second).
public export
data Subset : List a -> List a -> Type where
  SubNil  : Subset [] ys
  SubCons : Elem x ys -> Subset xs ys -> Subset (x :: xs) ys
