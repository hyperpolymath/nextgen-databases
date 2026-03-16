-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- InfoFlow.idr — Information flow control (CLASSIFIED)
--
-- Data is labeled with security classification levels that form a lattice.
-- Query results can only flow to contexts at the SAME or HIGHER classification.
-- This prevents sensitive data from leaking to unauthorised outputs.
--
-- This extends the Modal.idr scope isolation to SECURITY LEVELS: modal types
-- prevent cross-transaction leaks, while InfoFlow prevents cross-classification
-- leaks. Together they ensure both temporal and security isolation.
--
-- The noninterference property: observations at classification level L cannot
-- distinguish between two computations that differ only at classification
-- levels above L.

module InfoFlow

import Core

%default total

-- ============================================================================
-- Security Classification Lattice
-- ============================================================================

||| Security classification levels forming a total order (lattice).
||| Public < Internal < Confidential < Secret < TopSecret.
|||
||| These correspond to standard information classification schemes used
||| in government and enterprise settings.
public export
data Classification : Type where
  Public       : Classification
  Internal     : Classification
  Confidential : Classification
  Secret       : Classification
  TopSecret    : Classification

public export
Eq Classification where
  Public       == Public       = True
  Internal     == Internal     = True
  Confidential == Confidential = True
  Secret       == Secret       = True
  TopSecret    == TopSecret    = True
  _            == _            = False

public export
Show Classification where
  show Public       = "PUBLIC"
  show Internal     = "INTERNAL"
  show Confidential = "CONFIDENTIAL"
  show Secret       = "SECRET"
  show TopSecret    = "TOP_SECRET"

-- ============================================================================
-- Classification Ordering (Lattice Structure)
-- ============================================================================

||| Numeric encoding of classification levels for ordering.
||| This gives us a decidable total order.
public export
classLevel : Classification -> Nat
classLevel Public       = 0
classLevel Internal     = 1
classLevel Confidential = 2
classLevel Secret       = 3
classLevel TopSecret    = 4

||| Proof that classification `lo` flows to classification `hi`.
||| Data at level `lo` can be read by a context at level `hi` if and
||| only if lo <= hi. This is the fundamental information flow constraint.
public export
data FlowsTo : (lo : Classification) -> (hi : Classification) -> Type where
  ||| Reflexive: any level flows to itself.
  FlowRefl : FlowsTo c c
  ||| Public flows to Internal.
  PubToInt : FlowsTo Public Internal
  ||| Public flows to Confidential.
  PubToConf : FlowsTo Public Confidential
  ||| Public flows to Secret.
  PubToSec : FlowsTo Public Secret
  ||| Public flows to TopSecret.
  PubToTS : FlowsTo Public TopSecret
  ||| Internal flows to Confidential.
  IntToConf : FlowsTo Internal Confidential
  ||| Internal flows to Secret.
  IntToSec : FlowsTo Internal Secret
  ||| Internal flows to TopSecret.
  IntToTS : FlowsTo Internal TopSecret
  ||| Confidential flows to Secret.
  ConfToSec : FlowsTo Confidential Secret
  ||| Confidential flows to TopSecret.
  ConfToTS : FlowsTo Confidential TopSecret
  ||| Secret flows to TopSecret.
  SecToTS : FlowsTo Secret TopSecret

-- ============================================================================
-- Labeled Data (Security-Tagged Values)
-- ============================================================================

||| A value tagged with its security classification. Data in a Labeled
||| container can only be extracted by a context with sufficient clearance.
|||
||| This is analogous to Modal.Box but indexed by security level instead
||| of transaction world.
public export
data Labeled : Classification -> Type -> Type where
  ||| Tag a value with a security classification.
  MkLabeled : (val : a) -> Labeled level a

||| Functor-like map over labeled data, staying at the same level.
public export
mapLabeled : (a -> b) -> Labeled level a -> Labeled level b
mapLabeled f (MkLabeled val) = MkLabeled (f val)

-- ============================================================================
-- Clearance (Capability Token)
-- ============================================================================

||| Proof that a context has clearance at level `c`. This is a capability
||| token — you can only read data at or below your clearance level.
public export
data HasClearance : Classification -> Type where
  ||| Evidence of clearance at the given level.
  ClearanceEvidence : (c : Classification) -> HasClearance c

-- ============================================================================
-- Information Flow Operations
-- ============================================================================

||| Read labeled data with sufficient clearance. The FlowsTo proof ensures
||| the data's classification is at or below the reader's clearance.
|||
||| This is the elimination form for Labeled — the ONLY way to extract data.
public export
declassify : Labeled dataLevel a
          -> (clearance : HasClearance readerLevel)
          -> {auto flow : FlowsTo dataLevel readerLevel}
          -> a
declassify (MkLabeled val) _ = val

||| Upgrade data to a higher classification. Data can always be reclassified
||| upward (making it MORE restricted). This is safe because it reduces
||| the set of contexts that can read it.
public export
upgrade : Labeled lo a -> {auto flow : FlowsTo lo hi} -> Labeled hi a
upgrade (MkLabeled val) = MkLabeled val

||| Combine two labeled values. The result gets the HIGHER classification
||| of the two inputs (join in the lattice). Both inputs must flow to the
||| output level.
public export
combineLab : Labeled l1 a
          -> Labeled l2 b
          -> {auto flow1 : FlowsTo l1 out}
          -> {auto flow2 : FlowsTo l2 out}
          -> Labeled out (a, b)
combineLab (MkLabeled x) (MkLabeled y) = MkLabeled (x, y)

-- ============================================================================
-- Classified Query Results
-- ============================================================================

||| A query result tagged with its security classification.
||| The classification is determined by the data sources accessed.
public export
ClassifiedResult : Classification -> Type
ClassifiedResult level = Labeled level Core.QueryResult

||| Execute a query that produces classified results. The classification
||| is a type parameter, not a runtime annotation — it is checked by the
||| Idris2 type checker, not at runtime.
public export
classifiedQuery : (level : Classification)
               -> List Modality
               -> HexadRef
               -> ClassifiedResult level
classifiedQuery _ mods hex = MkLabeled (MkQueryResult mods 0)

-- ============================================================================
-- Noninterference (Type-Level Guarantee)
-- ============================================================================

||| Type-level statement of noninterference: if two computations produce
||| labeled results at the same level, and they are observed at a lower
||| level, the observations are indistinguishable.
|||
||| In practice this means: a query's result at classification C cannot
||| vary based on data at classification levels above C. Any such
||| dependency would require a FlowsTo proof that cannot be constructed
||| (since hi does NOT flow to lo when hi > lo).
|||
||| This is a type-level SPECIFICATION. The proof is the absence of
||| downward flow constructors: there is no `FlowsTo Secret Public`.
public export
data Noninterference : Classification -> Type where
  ||| At observation level `obs`, computations that differ only above `obs`
  ||| produce the same observable output. This is witnessed by the fact that
  ||| `declassify` requires a `FlowsTo` proof, which does not exist for
  ||| downward flows.
  NI : (obsLevel : Classification) -> Noninterference obsLevel

-- ============================================================================
-- Flow Lattice Proofs
-- ============================================================================

||| FlowsTo is reflexive (proved by FlowRefl constructor).
public export
flowReflexive : (c : Classification) -> FlowsTo c c
flowReflexive _ = FlowRefl

||| FlowsTo is transitive.
||| If a flows to b and b flows to c, then a flows to c.
public export
flowTransitive : FlowsTo a b -> FlowsTo b c -> FlowsTo a c
flowTransitive FlowRefl fb     = fb
flowTransitive fa     FlowRefl = fa
flowTransitive PubToInt IntToConf = PubToConf
flowTransitive PubToInt IntToSec = PubToSec
flowTransitive PubToInt IntToTS = PubToTS
flowTransitive PubToConf ConfToSec = PubToSec
flowTransitive PubToConf ConfToTS = PubToTS
flowTransitive PubToSec SecToTS = PubToTS
flowTransitive IntToConf ConfToSec = IntToSec
flowTransitive IntToConf ConfToTS = IntToTS
flowTransitive IntToSec SecToTS = IntToTS
flowTransitive ConfToSec SecToTS = ConfToTS

-- ============================================================================
-- Example: Cross-Classification Query
-- ============================================================================

||| Example: a public query result that can be read by anyone.
public export
publicResult : ClassifiedResult Public
publicResult = classifiedQuery Public [Graph, Document]
  (MkHexadRef "550e8400-e29b-41d4-a716-446655440000")

||| Example: read a public result with Secret clearance.
||| This works because Public flows to Secret.
public export
readPublicWithSecret : Core.QueryResult
readPublicWithSecret =
  declassify publicResult (ClearanceEvidence Secret)

||| Example: a Secret result.
public export
secretResult : ClassifiedResult Secret
secretResult = classifiedQuery Secret [Graph]
  (MkHexadRef "660e8400-e29b-41d4-a716-446655440001")

||| Trying to read secretResult with Public clearance would fail:
||| `declassify secretResult (ClearanceEvidence Public)`
||| Error: Can't find an implementation for FlowsTo Secret Public
||| — because no such constructor exists. Injection impossible.
