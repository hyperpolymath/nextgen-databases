-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Provenance.Rationale - Non-empty justification for operations

import FbqlDt.Types.NonEmptyString

namespace FbqlDt.Provenance

open FbqlDt.Types

/-- A rationale explaining why an operation was performed.

Every data modification in GQLdt must include a rationale.
This is enforced at the type level - you cannot construct
a Tracked value without providing a non-empty rationale. -/
structure Rationale where
  /-- The underlying non-empty string explanation -/
  text : NonEmptyString
  deriving Repr

namespace Rationale

/-- Create a Rationale from a string literal -/
def fromString (s : String) (h : s.length > 0 := by decide) : Rationale :=
  ⟨⟨s, h⟩⟩

/-- Try to create a Rationale from a string -/
def ofString? (s : String) : Option Rationale :=
  match NonEmptyString.ofString? s with
  | some nes => some ⟨nes⟩
  | none => none

/-- Get the underlying string -/
def toString (r : Rationale) : String := r.text.val

/-- BEq instance -/
instance : BEq Rationale where
  beq a b := a.text.val == b.text.val

/-- Common rationales -/
def initialEntry : Rationale := fromString "Initial data entry"
def correction : Rationale := fromString "Correction of previous entry"
def userRequest : Rationale := fromString "User request"
def systemGenerated : Rationale := fromString "System generated"

end Rationale

end FbqlDt.Provenance
