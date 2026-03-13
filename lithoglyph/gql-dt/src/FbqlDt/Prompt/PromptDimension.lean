-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Prompt.PromptDimension - PROMPT score dimension [0, 100]
--
-- Each PROMPT dimension (Provenance, Replicability, Objective,
-- Methodology, Publication, Transparency) is scored 0-100.

import FbqlDt.Types.BoundedNat

namespace FbqlDt.Prompt

/-- A PROMPT dimension score, bounded 0-100.

This is the fundamental unit for PROMPT scoring in GQLdt.
Each of the six dimensions uses this type. -/
abbrev PromptDimension := FbqlDt.Types.BoundedNat 0 100

namespace PromptDimension

open FbqlDt.Types.BoundedNat

/-- Create a PROMPT dimension score with automatic proof -/
def mk (n : Nat) (h1 : 0 ≤ n := by omega) (h2 : n ≤ 100 := by omega)
    : PromptDimension :=
  ⟨n, h1, h2⟩

/-- Minimum score (0) -/
def min : PromptDimension := ⟨0, by omega, by omega⟩

/-- Maximum score (100) -/
def max : PromptDimension := ⟨100, by omega, by omega⟩

/-- Common threshold: low quality (below 30) -/
def lowThreshold : Nat := 30

/-- Common threshold: medium quality (30-70) -/
def mediumThreshold : Nat := 70

/-- Common threshold: high quality (above 70) -/
def highThreshold : Nat := 70

/-- Check if score is low quality -/
def isLow (d : PromptDimension) : Bool := d.val < lowThreshold

/-- Check if score is high quality -/
def isHigh (d : PromptDimension) : Bool := d.val > highThreshold

/-- Quality rating as a string -/
def qualityRating (d : PromptDimension) : String :=
  if d.val < 30 then "Low"
  else if d.val < 70 then "Medium"
  else "High"

end PromptDimension

end FbqlDt.Prompt
