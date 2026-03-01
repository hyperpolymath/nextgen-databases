-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Effects.idr — Effect tracking (EFFECTS { Read, Write, ... })
--
-- A query declares its effects and the checker verifies that actual
-- operations are a subset of declared effects. This prevents, e.g.,
-- a query declared as read-only from performing writes.

module Effects

import Core

%default total

-- ============================================================================
-- Effect Sets (as sorted lists)
-- ============================================================================

||| An effect set is a list of effect labels.
||| In practice these would be deduplicated, but for proof purposes a list
||| with a subset relation is sufficient.
public export
EffectSet : Type
EffectSet = List EffectLabel

||| The empty effect set — a pure query with no side effects.
public export
noEffects : EffectSet
noEffects = []

||| Read-only effect set.
public export
readOnly : EffectSet
readOnly = [Read]

||| Read-write effect set.
public export
readWrite : EffectSet
readWrite = [Read, Write]

||| Full effect set — all effects permitted.
public export
allEffects : EffectSet
allEffects = [Read, Write, Cite, Audit, Transform, Federate]

-- ============================================================================
-- Effect Membership
-- ============================================================================

||| Proof that an effect label is a member of an effect set.
||| Re-exports Core.Elem specialised to EffectLabel.
public export
HasEffect : EffectLabel -> EffectSet -> Type
HasEffect = Core.Elem

-- ============================================================================
-- Effect Subsumption
-- ============================================================================

||| Proof that one effect set is a subset of another.
||| `Subsumes declared actual` means every effect in `actual` is also in
||| `declared`. This is the core judgement: a query is well-typed if its
||| actual effects are subsumed by its declared effects.
|||
||| Implementation: `Subset actual declared` (note argument flip — Subset xs ys
||| means xs ⊆ ys, i.e. every element of xs is in ys).
public export
Subsumes : EffectSet -> EffectSet -> Type
Subsumes declared actual = Core.Subset actual declared

||| The empty set is subsumed by any set.
public export
subNil : Subsumes declared []
subNil = SubNil

||| If `e` is in `declared` and `rest` is subsumed by `declared`,
||| then `e :: rest` is subsumed by `declared`.
public export
subCons : Core.Elem e declared -> Subsumes declared rest -> Subsumes declared (e :: rest)
subCons = SubCons

-- ============================================================================
-- Effect Checker
-- ============================================================================

||| An effectful operation parameterised by its effect requirements.
||| The type-level effect set ensures the operation can only be used
||| in a context that declares those effects.
public export
data EffectfulOp : (required : EffectSet) -> Type -> Type where
  ||| An operation that requires certain effects and produces a value.
  MkOp : (effects : EffectSet) -> a -> EffectfulOp effects a

||| Run an effectful operation in a context that declares sufficient effects.
||| The subsumption proof ensures the context's declared effects cover
||| the operation's required effects.
public export
runOp : EffectfulOp required a -> {auto prf : Subsumes declared required} -> a
runOp (MkOp _ val) = val

-- ============================================================================
-- Standard Operations with Effect Requirements
-- ============================================================================

||| A read operation requires the Read effect.
public export
readOp : a -> EffectfulOp [Read] a
readOp val = MkOp [Read] val

||| A write operation requires the Write effect.
public export
writeOp : a -> EffectfulOp [Write] a
writeOp val = MkOp [Write] val

||| A cite operation requires the Cite effect.
public export
citeOp : a -> EffectfulOp [Cite] a
citeOp val = MkOp [Cite] val

||| An audit operation requires the Audit effect.
public export
auditOp : a -> EffectfulOp [Audit] a
auditOp val = MkOp [Audit] val

-- ============================================================================
-- Effect Combination
-- ============================================================================

||| Combine two effect sets by appending.
public export
combine : EffectSet -> EffectSet -> EffectSet
combine [] ys = ys
combine (x :: xs) ys = x :: combine xs ys

||| Proof that combining two subsets of `declared` is still a subset.
||| Subsumes declared xs = Subset xs declared, so we pattern match on the
||| Subset structure (which decomposes xs).
public export
combineSub : Subsumes declared xs -> Subsumes declared ys -> Subsumes declared (combine xs ys)
combineSub {xs = []} SubNil subYs = subYs
combineSub {xs = _ :: _} (SubCons elem subRest) subYs = SubCons elem (combineSub subRest subYs)

-- ============================================================================
-- Query with Declared Effects
-- ============================================================================

||| A VQL-dt++ query with declared effects. The declared effect set is
||| part of the type, enabling static verification of effect compliance.
public export
record EffectfulQuery (declared : EffectSet) where
  constructor MkEffectfulQuery
  queryText   : String
  resultType  : Core.PrimType
