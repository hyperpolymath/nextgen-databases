-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Prompt.PromptScores - Complete PROMPT score with computed overall
--
-- The PROMPT framework scores evidence on 6 dimensions:
-- - Provenance: Where does this come from?
-- - Replicability: Can it be reproduced?
-- - Objective: Is it free from bias?
-- - Methodology: Is the method sound?
-- - Publication: Is it properly published/peer-reviewed?
-- - Transparency: Is the process open?
--
-- The overall score is the average of all 6, computed with proof.

import FbqlDt.Prompt.PromptDimension
-- omega is built-in to Lean 4

namespace FbqlDt.Prompt

open FbqlDt.Types

/-- Complete PROMPT scores with all 6 dimensions plus computed overall.

The `overall` field is constrained to equal the average of the 6 dimensions.
This is enforced at the type level via `overall_correct`. -/
structure PromptScores where
  /-- Provenance score: origin and chain of custody -/
  provenance : PromptDimension
  /-- Replicability score: can results be reproduced -/
  replicability : PromptDimension
  /-- Objective score: freedom from bias -/
  objective : PromptDimension
  /-- Methodology score: soundness of methods -/
  methodology : PromptDimension
  /-- Publication score: peer review and publication status -/
  publication : PromptDimension
  /-- Transparency score: openness of process -/
  transparency : PromptDimension
  /-- Overall score: average of all dimensions -/
  overall : PromptDimension
  /-- Proof that overall equals the computed average -/
  overall_correct : overall.val =
    (provenance.val + replicability.val + objective.val +
     methodology.val + publication.val + transparency.val) / 6
  deriving Repr

namespace PromptScores

/-- Compute the sum of all 6 dimension values -/
def dimensionSum (p r o m pub t : PromptDimension) : Nat :=
  p.val + r.val + o.val + m.val + pub.val + t.val

/-- Compute the average of all 6 dimension values -/
def computeOverall (p r o m pub t : PromptDimension) : Nat :=
  dimensionSum p r o m pub t / 6

/-- Proof that the computed average is in bounds [0, 100] -/
theorem overall_in_bounds (p r o m pub t : PromptDimension) :
    computeOverall p r o m pub t ≤ 100 := by
  unfold computeOverall dimensionSum
  have hp := p.le_max
  have hr := r.le_max
  have ho := o.le_max
  have hm := m.le_max
  have hpub := pub.le_max
  have ht := t.le_max
  omega

/-- Smart constructor: create PromptScores from 6 dimensions.
    The overall score is computed automatically with proof. -/
def create (p r o m pub t : PromptDimension) : PromptScores :=
  let sum := dimensionSum p r o m pub t
  let avg := sum / 6
  have h_avg_le : avg ≤ 100 := overall_in_bounds p r o m pub t
  {
    provenance := p
    replicability := r
    objective := o
    methodology := m
    publication := pub
    transparency := t
    overall := ⟨avg, by omega, h_avg_le⟩
    overall_correct := rfl
  }

/-- Example: Official statistics (high quality) -/
def officialStats : PromptScores :=
  create ⟨100, by omega, by omega⟩  -- provenance: official source
         ⟨100, by omega, by omega⟩  -- replicability: public data
         ⟨95, by omega, by omega⟩   -- objective: minor methodological choices
         ⟨95, by omega, by omega⟩   -- methodology: standard statistical methods
         ⟨100, by omega, by omega⟩  -- publication: official government release
         ⟨95, by omega, by omega⟩   -- transparency: methods documented

/-- Example: Anonymous blog post (low quality) -/
def anonymousBlog : PromptScores :=
  create ⟨10, by omega, by omega⟩   -- provenance: unknown author
         ⟨5, by omega, by omega⟩    -- replicability: no sources cited
         ⟨20, by omega, by omega⟩   -- objective: opinion piece
         ⟨15, by omega, by omega⟩   -- methodology: anecdotal
         ⟨5, by omega, by omega⟩    -- publication: self-published
         ⟨10, by omega, by omega⟩   -- transparency: no disclosure

/-- Get the quality tier based on overall score -/
def qualityTier (s : PromptScores) : String :=
  if s.overall.val ≥ 80 then "Gold"
  else if s.overall.val ≥ 60 then "Silver"
  else if s.overall.val ≥ 40 then "Bronze"
  else "Unverified"

/-- Check if all dimensions meet a minimum threshold -/
def meetsMinimum (s : PromptScores) (threshold : Nat) : Bool :=
  s.provenance.val ≥ threshold &&
  s.replicability.val ≥ threshold &&
  s.objective.val ≥ threshold &&
  s.methodology.val ≥ threshold &&
  s.publication.val ≥ threshold &&
  s.transparency.val ≥ threshold

/-- Get the weakest dimension -/
def weakestDimension (s : PromptScores) : String × Nat :=
  let dims := [
    ("provenance", s.provenance.val),
    ("replicability", s.replicability.val),
    ("objective", s.objective.val),
    ("methodology", s.methodology.val),
    ("publication", s.publication.val),
    ("transparency", s.transparency.val)
  ]
  dims.foldl (fun acc d => if d.2 < acc.2 then d else acc) ("none", 101)

end PromptScores

end FbqlDt.Prompt
