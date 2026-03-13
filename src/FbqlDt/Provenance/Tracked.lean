-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Provenance.Tracked - Values with provenance tracking
--
-- A Tracked value wraps any type with mandatory provenance:
-- who added it, when, and why. This is the core of GQLdt's
-- type-enforced provenance tracking.

import FbqlDt.Provenance.ActorId
import FbqlDt.Provenance.Rationale

namespace FbqlDt.Provenance

/-- A Unix timestamp (milliseconds since epoch) -/
structure Timestamp where
  /-- Milliseconds since Unix epoch (1970-01-01) -/
  millis : Nat
  deriving Repr, BEq, Ord

namespace Timestamp

/-- Create a timestamp from milliseconds -/
def fromMillis (ms : Nat) : Timestamp := ⟨ms⟩

/-- Create a timestamp from seconds -/
def fromSeconds (s : Nat) : Timestamp := ⟨s * 1000⟩

/-- Epoch (1970-01-01 00:00:00 UTC) -/
def epoch : Timestamp := ⟨0⟩

/-- Check if one timestamp is before another -/
def isBefore (t1 t2 : Timestamp) : Bool := t1.millis < t2.millis

/-- Check if one timestamp is after another -/
def isAfter (t1 t2 : Timestamp) : Bool := t1.millis > t2.millis

end Timestamp

/-- A value wrapped with full provenance information.

Every value in a provenance-tracked GQLdt collection is wrapped
in this structure. The type system ensures that:
1. Every value has an associated actor (who created it)
2. Every value has a timestamp (when it was created)
3. Every value has a rationale (why it was created)

You cannot construct a Tracked value without all three. -/
structure Tracked (α : Type) where
  /-- The underlying value -/
  value : α
  /-- Who added this value -/
  addedBy : ActorId
  /-- When this value was added -/
  addedAt : Timestamp
  /-- Why this value was added -/
  rationale : Rationale
  deriving Repr

namespace Tracked

variable {α : Type}

/-- Create a tracked value -/
def create (v : α) (actor : ActorId) (ts : Timestamp) (rat : Rationale)
    : Tracked α :=
  ⟨v, actor, ts, rat⟩

/-- Map a function over the tracked value, preserving provenance -/
def map {β : Type} (f : α → β) (t : Tracked α) : Tracked β :=
  ⟨f t.value, t.addedBy, t.addedAt, t.rationale⟩

/-- Coercion to underlying value -/
instance : Coe (Tracked α) α where
  coe t := t.value

/-- Get the age of a tracked value relative to a timestamp -/
def ageMillis (t : Tracked α) (now : Timestamp) : Nat :=
  now.millis - t.addedAt.millis

-- ============================================================================
-- Theorems
-- ============================================================================

/-- A Tracked value always has a non-empty actor ID -/
theorem has_actor (t : Tracked α) : t.addedBy.id.val.length > 0 :=
  t.addedBy.id.nonempty

/-- A Tracked value always has a non-empty rationale -/
theorem has_rationale (t : Tracked α) : t.rationale.text.val.length > 0 :=
  t.rationale.text.nonempty

/-- Combined provenance proof -/
theorem has_provenance (t : Tracked α) :
    t.addedBy.id.val.length > 0 ∧ t.rationale.text.val.length > 0 :=
  ⟨has_actor t, has_rationale t⟩

end Tracked

-- ============================================================================
-- TrackedList: Lists where every element has provenance
-- ============================================================================

/-- A list where every element is tracked with provenance -/
abbrev TrackedList (α : Type) := List (Tracked α)

namespace TrackedList

/-- All elements in a TrackedList have provenance -/
theorem all_have_provenance {α : Type} (ts : TrackedList α) :
    ∀ t ∈ ts, t.addedBy.id.val.length > 0 ∧ t.rationale.text.val.length > 0 := by
  intro t _
  exact Tracked.has_provenance t

/-- Extract just the values from a TrackedList -/
def values {α : Type} (ts : TrackedList α) : List α :=
  ts.map (·.value)

/-- Filter by actor -/
def byActor {α : Type} (ts : TrackedList α) (actor : ActorId) : TrackedList α :=
  ts.filter (·.addedBy == actor)

/-- Filter by time range -/
def inTimeRange {α : Type} (ts : TrackedList α)
    (start finish : Timestamp) : TrackedList α :=
  ts.filter (fun t => t.addedAt.millis ≥ start.millis &&
                      t.addedAt.millis ≤ finish.millis)

end TrackedList

end FbqlDt.Provenance
