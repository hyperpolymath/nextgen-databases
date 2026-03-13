-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Types.BoundedInt - Integers bounded by min and max

-- omega is built-in to Lean 4

namespace FbqlDt.Types

/-- An integer bounded between min and max (inclusive).

Similar to BoundedNat but for integers, allowing negative bounds. -/
structure BoundedInt (min max : Int) where
  /-- The underlying integer value -/
  val : Int
  /-- Proof that val is at least min -/
  min_le : min ≤ val
  /-- Proof that val is at most max -/
  le_max : val ≤ max
  deriving Repr

namespace BoundedInt

/-- Create a BoundedInt with automatic proof via omega tactic -/
def mk' (min max n : Int) (h1 : min ≤ n := by omega) (h2 : n ≤ max := by omega)
    : BoundedInt min max :=
  ⟨n, h1, h2⟩

/-- Get the underlying value -/
def toInt {min max : Int} (b : BoundedInt min max) : Int := b.val

/-- Try to construct a BoundedInt, returning none if out of bounds -/
def ofInt? (min max n : Int) : Option (BoundedInt min max) :=
  if h1 : min ≤ n then
    if h2 : n ≤ max then
      some ⟨n, h1, h2⟩
    else
      none
  else
    none

/-- The value is always within bounds -/
theorem val_in_bounds {min max : Int} (b : BoundedInt min max) :
    min ≤ b.val ∧ b.val ≤ max :=
  ⟨b.min_le, b.le_max⟩

end BoundedInt

end FbqlDt.Types
