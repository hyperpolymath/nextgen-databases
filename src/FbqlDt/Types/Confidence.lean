-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Types.Confidence - Confidence values in [0.0, 1.0]
--
-- Represents a probability or confidence level.
-- For MVP, this uses runtime validation rather than proof-level
-- guarantees, since Float proofs are complex in Lean 4.

namespace FbqlDt.Types

/-- A confidence value between 0.0 and 1.0.

This is the standard type for expressing confidence levels,
probabilities, or certainty in GQLdt. -/
structure Confidence where
  /-- The underlying float value (guaranteed 0.0 ≤ val ≤ 1.0) -/
  val : Float
  deriving Repr, BEq

namespace Confidence

/-- Clamp a float to [0, 1] range -/
private def clampFloat (f : Float) : Float :=
  if f < 0.0 then 0.0
  else if f > 1.0 then 1.0
  else f

/-- Try to create a confidence value, returning none if out of bounds -/
def ofFloat? (f : Float) : Option Confidence :=
  if f >= 0.0 && f <= 1.0 then
    some ⟨f⟩
  else
    none

/-- Create a confidence value, clamping to [0, 1] if needed -/
def clamp (f : Float) : Confidence :=
  ⟨clampFloat f⟩

/-- Create from a float (unsafe - caller must ensure bounds) -/
def unsafeOfFloat (f : Float) : Confidence := ⟨f⟩

/-- Zero confidence -/
def zero : Confidence := ⟨0.0⟩

/-- Full confidence -/
def one : Confidence := ⟨1.0⟩

/-- Half confidence -/
def half : Confidence := ⟨0.5⟩

/-- Get the underlying float -/
def toFloat (c : Confidence) : Float := c.val

/-- Combine two confidence values (simple average) -/
def avg (c1 c2 : Confidence) : Confidence :=
  clamp ((c1.val + c2.val) / 2.0)

/-- Multiply confidence values (conjunction) -/
def mul (c1 c2 : Confidence) : Confidence :=
  ⟨c1.val * c2.val⟩  -- Product of [0,1] values is in [0,1]

/-- Complement of confidence (1 - c) -/
def complement (c : Confidence) : Confidence :=
  ⟨1.0 - c.val⟩

/-- Check if confidence is high (> 0.8) -/
def isHigh (c : Confidence) : Bool := c.val > 0.8

/-- Check if confidence is low (< 0.3) -/
def isLow (c : Confidence) : Bool := c.val < 0.3

end Confidence

end FbqlDt.Types
