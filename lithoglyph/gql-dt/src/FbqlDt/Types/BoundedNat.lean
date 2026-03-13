-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Types.BoundedNat - Natural numbers bounded by min and max
--
-- This is the foundational refinement type for GQLdt. A BoundedNat min max
-- is a natural number n with proofs that min ≤ n and n ≤ max.
--
-- Example usage:
--   def score : BoundedNat 0 100 := ⟨95, by omega, by omega⟩

-- omega is built-in to Lean 4

namespace FbqlDt.Types

/-- A natural number bounded between min and max (inclusive).

This is a refinement type that carries proofs of the bounds at the type level.
Invalid values simply cannot be constructed - the type system rejects them. -/
structure BoundedNat (min max : Nat) where
  /-- The underlying natural number value -/
  val : Nat
  /-- Proof that val is at least min -/
  min_le : min ≤ val
  /-- Proof that val is at most max -/
  le_max : val ≤ max
  deriving Repr

namespace BoundedNat

/-- Create a BoundedNat with automatic proof via omega tactic.
    Only succeeds if n is provably in [min, max]. -/
def mk' (min max n : Nat) (h1 : min ≤ n := by omega) (h2 : n ≤ max := by omega)
    : BoundedNat min max :=
  ⟨n, h1, h2⟩

/-- Get the underlying value -/
def toNat {min max : Nat} (b : BoundedNat min max) : Nat := b.val

/-- Decidable equality based on underlying value -/
instance {min max : Nat} : DecidableEq (BoundedNat min max) :=
  fun a b => decidable_of_iff (a.val = b.val)
    ⟨fun h => by cases a; cases b; simp_all, fun h => by simp_all⟩

/-- BEq instance for runtime comparison -/
instance {min max : Nat} : BEq (BoundedNat min max) where
  beq a b := a.val == b.val

/-- Ordering based on underlying value -/
instance {min max : Nat} : Ord (BoundedNat min max) where
  compare a b := compare a.val b.val

-- ============================================================================
-- Theorems
-- ============================================================================

/-- The value is always within bounds -/
theorem val_in_bounds {min max : Nat} (b : BoundedNat min max) :
    min ≤ b.val ∧ b.val ≤ max :=
  ⟨b.min_le, b.le_max⟩

/-- Two BoundedNats are equal iff their values are equal -/
theorem eq_iff_val_eq {min max : Nat} (a b : BoundedNat min max) :
    a = b ↔ a.val = b.val := by
  constructor
  · intro h; rw [h]
  · intro h; cases a; cases b; simp_all

/-- If min ≤ max, then min itself is a valid BoundedNat -/
theorem min_valid {min max : Nat} (h : min ≤ max) :
    ∃ b : BoundedNat min max, b.val = min :=
  ⟨⟨min, Nat.le_refl min, h⟩, rfl⟩

/-- If min ≤ max, then max itself is a valid BoundedNat -/
theorem max_valid {min max : Nat} (h : min ≤ max) :
    ∃ b : BoundedNat min max, b.val = max :=
  ⟨⟨max, h, Nat.le_refl max⟩, rfl⟩

-- ============================================================================
-- Smart Constructors
-- ============================================================================

/-- Try to construct a BoundedNat, returning none if out of bounds -/
def ofNat? (min max n : Nat) : Option (BoundedNat min max) :=
  if h1 : min ≤ n then
    if h2 : n ≤ max then
      some ⟨n, h1, h2⟩
    else
      none
  else
    none

/-- Construct a BoundedNat, clamping to bounds if necessary -/
def clamp (min max n : Nat) (h : min ≤ max) : BoundedNat min max :=
  if h1 : n < min then
    ⟨min, Nat.le_refl min, h⟩
  else if h2 : n > max then
    ⟨max, h, Nat.le_refl max⟩
  else
    ⟨n, Nat.not_lt.mp h1, Nat.not_lt.mp h2⟩

-- ============================================================================
-- Arithmetic Operations (preserving bounds where possible)
-- ============================================================================

/-- Add two BoundedNats. Result bounds are [min1+min2, max1+max2] -/
def add {min1 max1 min2 max2 : Nat}
    (a : BoundedNat min1 max1) (b : BoundedNat min2 max2)
    : BoundedNat (min1 + min2) (max1 + max2) :=
  ⟨a.val + b.val,
   Nat.add_le_add a.min_le b.min_le,
   Nat.add_le_add a.le_max b.le_max⟩

end BoundedNat

end FbqlDt.Types
