-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Provenance.ActorId - Non-empty identifier for actors

import FbqlDt.Types.NonEmptyString

namespace FbqlDt.Provenance

open FbqlDt.Types

/-- An actor identifier, guaranteed to be non-empty.

Actors are entities that perform operations on data:
users, automated agents, systems, etc. -/
structure ActorId where
  /-- The underlying non-empty string identifier -/
  id : NonEmptyString
  deriving Repr

namespace ActorId

/-- Create an ActorId from a string literal -/
def fromString (s : String) (h : s.length > 0 := by decide) : ActorId :=
  ⟨⟨s, h⟩⟩

/-- Try to create an ActorId from a string -/
def ofString? (s : String) : Option ActorId :=
  match NonEmptyString.ofString? s with
  | some nes => some ⟨nes⟩
  | none => none

/-- Get the underlying string -/
def toString (a : ActorId) : String := a.id.val

/-- BEq instance -/
instance : BEq ActorId where
  beq a b := a.id.val == b.id.val

/-- Example actors -/
def systemActor : ActorId := fromString "system"
def anonymousActor : ActorId := fromString "anonymous"

end ActorId

end FbqlDt.Provenance
