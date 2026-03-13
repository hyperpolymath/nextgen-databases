-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Types.NonEmptyString - Strings with proof of non-emptiness
--
-- This refinement type ensures strings are never empty at the type level.
-- Used for rationales, actor IDs, and any field that must have content.

-- omega is built-in to Lean 4

namespace FbqlDt.Types

/-- A string guaranteed to be non-empty.

The proof `nonempty` ensures the string has at least one character.
This is enforced at construction time - empty strings cannot be wrapped. -/
structure NonEmptyString where
  /-- The underlying string value -/
  val : String
  /-- Proof that the string is not empty -/
  nonempty : val.length > 0
  deriving Repr

namespace NonEmptyString

/-- Create a NonEmptyString with automatic proof via decide tactic.
    Only succeeds for string literals that are provably non-empty. -/
def mk' (s : String) (h : s.length > 0 := by decide) : NonEmptyString :=
  ⟨s, h⟩

/-- Get the underlying string -/
def toString (s : NonEmptyString) : String := s.val

/-- Try to construct a NonEmptyString, returning none if empty -/
def ofString? (s : String) : Option NonEmptyString :=
  if h : s.length > 0 then
    some ⟨s, h⟩
  else
    none

/-- BEq instance -/
instance : BEq NonEmptyString where
  beq a b := a.val == b.val

/-- Decidable equality -/
instance : DecidableEq NonEmptyString :=
  fun a b => decidable_of_iff (a.val = b.val)
    ⟨fun h => by cases a; cases b; simp_all, fun h => by simp_all⟩

/-- ToString instance -/
instance : ToString NonEmptyString where
  toString s := s.val

-- ============================================================================
-- Theorems
-- ============================================================================

/-- A NonEmptyString is never the empty string -/
theorem ne_empty (s : NonEmptyString) : s.val ≠ "" := by
  intro h
  have := s.nonempty
  simp [h] at this

/-- Two NonEmptyStrings are equal iff their values are equal -/
theorem eq_iff_val_eq (a b : NonEmptyString) : a = b ↔ a.val = b.val := by
  constructor
  · intro h; rw [h]
  · intro h; cases a; cases b; simp_all

/-- Get the first character (always exists for non-empty string) -/
def head (s : NonEmptyString) : Char :=
  -- Safe because string is non-empty
  s.val.get (String.Pos.mk 0)

end NonEmptyString

end FbqlDt.Types
