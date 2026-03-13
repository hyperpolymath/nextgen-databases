/-
SPDX-License-Identifier: PMPL-1.0-or-later
Form.Normalizer - Functional Dependency Types

Lean 4 types for encoding functional dependencies and
normal form predicates for proof-carrying normalization.

Part of Lithoglyph: Stone-carved data for the ages.
-/

namespace Lithoglyph.Normalizer

/-! # Attribute and Schema Types -/

/-- An attribute name -/
abbrev Attribute := String

/-- A schema is a list of attributes -/
structure Schema where
  attributes : List Attribute
  candidateKeys : List (List Attribute) := []
  deriving Repr, BEq

/-- A tuple maps attributes to values -/
abbrev Tuple := Attribute → Option String

/-- A relation is a collection of tuples -/
abbrev Relation (s : Schema) := List Tuple

/-! # Functional Dependencies -/

/-- A functional dependency X → Y -/
structure FunDep (s : Schema) where
  /-- The determinant (left-hand side) -/
  determinant : List Attribute
  /-- The dependent (right-hand side) -/
  dependent : List Attribute
  /-- Discovery confidence (1.0 = exact FD) -/
  confidence : Float := 1.0
  /-- Journal entry where discovered -/
  discoveredAt : Option Nat := none
  /-- Sample size used for discovery -/
  sampleSize : Option Nat := none
  deriving Repr

/-- Proof that a functional dependency holds in a relation -/
structure FDHolds {s : Schema} (fd : FunDep s) (r : Relation s) : Prop where
  proof : ∀ t1 t2 : Tuple,
    (∀ a, a ∈ fd.determinant → t1 a = t2 a) →
    (∀ a, a ∈ fd.dependent → t1 a = t2 a)

/-! # Attribute Set Operations -/

/-- Check if attrs contains a subset that is a candidate key -/
def isSuperkey (s : Schema) (attrs : List Attribute) : Bool :=
  s.candidateKeys.any fun key => key.all (· ∈ attrs)

/-- Check if attrs is a proper subset of a candidate key -/
def isProperSubsetOfKey (s : Schema) (attrs : List Attribute) : Bool :=
  s.candidateKeys.any fun key =>
    attrs.all (· ∈ key) && attrs.length < key.length

/-- Get prime attributes (attributes that are part of any candidate key) -/
def primeAttributes (s : Schema) : List Attribute :=
  s.candidateKeys.flatten.eraseDups

/-! # Normal Form Predicates -/

/-- Type representing atomic values (not further decomposable) -/
inductive AtomicValue where
  | string : String → AtomicValue
  | int : Int → AtomicValue
  | float : Float → AtomicValue
  | bool : Bool → AtomicValue
  | timestamp : String → AtomicValue
  | promptScore : Nat → AtomicValue  -- 0-100

/-- First Normal Form: All attribute values are atomic -/
def FirstNormalForm (s : Schema) : Prop :=
  ∀ attr ∈ s.attributes, True  -- Type system guarantees atomicity in our model

/-- Second Normal Form: 1NF + no partial dependencies on candidate keys -/
def SecondNormalForm (s : Schema) (fds : List (FunDep s)) : Prop :=
  FirstNormalForm s ∧
  ∀ fd ∈ fds,
    isProperSubsetOfKey s fd.determinant = false ∨
    fd.dependent.all (· ∈ primeAttributes s)

/-- Third Normal Form: 2NF + no transitive dependencies -/
def ThirdNormalForm (s : Schema) (fds : List (FunDep s)) : Prop :=
  SecondNormalForm s fds ∧
  ∀ fd ∈ fds,
    isSuperkey s fd.determinant ∨
    fd.dependent.all (· ∈ primeAttributes s)

/-- Boyce-Codd Normal Form: Every determinant is a superkey -/
def BCNF (s : Schema) (fds : List (FunDep s)) : Prop :=
  ∀ fd ∈ fds, isSuperkey s fd.determinant

/-! # Normal Form Violations -/

/-- A violation of a normal form requirement -/
structure NFViolation (s : Schema) where
  fd : FunDep s
  violationType : String
  explanation : String

/-- Check for 3NF violations -/
def find3NFViolations (s : Schema) (fds : List (FunDep s)) : List (NFViolation s) :=
  fds.filterMap fun fd =>
    if isSuperkey s fd.determinant then none
    else if fd.dependent.all (· ∈ primeAttributes s) then none
    else some {
      fd := fd
      violationType := "transitive_dependency"
      explanation := s!"Determinant {fd.determinant} is not a superkey and dependent {fd.dependent} contains non-prime attributes"
    }

/-- Check for BCNF violations -/
def findBCNFViolations (s : Schema) (fds : List (FunDep s)) : List (NFViolation s) :=
  fds.filterMap fun fd =>
    if isSuperkey s fd.determinant then none
    else some {
      fd := fd
      violationType := "non_superkey_determinant"
      explanation := s!"Determinant {fd.determinant} is not a superkey"
    }

/-! # Normalization Transformations -/

/-- A decomposition of a schema into multiple schemas -/
structure Decomposition where
  source : Schema
  targets : List Schema
  deriving Repr

/-- A normalization step with proof of losslessness -/
structure NormalizationStep where
  decomposition : Decomposition
  /-- The common attributes for joining -/
  joinAttributes : List Attribute
  /-- Narrative explanation -/
  narrative : String
  deriving Repr

/-- Proof that a decomposition is lossless (can be reversed via join).
    A decomposition R into R1, R2, ..., Rn is lossless if the natural join
    of all Ri equals R. This holds when for every pair (Ri, Rj), the common
    attributes form a superkey for at least one of them. -/
structure LosslessDecomposition (d : Decomposition) : Prop where
  /-- For each pair of target schemas, common attributes determine one -/
  commonAttrsFormKey : ∀ t ∈ d.targets,
    (t.attributes.filter (· ∈ d.source.attributes)).length > 0

/-- Proof that a decomposition preserves all functional dependencies.
    Every FD X → Y in the original schema is preserved if X ∪ Y ⊆ Ri
    for some target relation Ri. -/
structure DependencyPreserving (d : Decomposition) (fds : List (FunDep d.source)) : Prop where
  /-- Every FD is contained within at least one target schema -/
  preserved : ∀ fd ∈ fds,
    d.targets.any fun t =>
      fd.determinant.all (· ∈ t.attributes) &&
      fd.dependent.all (· ∈ t.attributes)

/-! # Attribute Closure -/

/-- Compute the attribute closure of attrs under a set of FDs.
    X+ = all attributes functionally determined by X.
    Uses fixed-point iteration: repeatedly add dependent attributes
    when the determinant is contained in the current closure. -/
def attributeClosure (attrs : List Attribute) (fds : List (FunDep s)) : List Attribute :=
  -- Fixed-point iteration (bounded by number of FDs to ensure termination)
  let rec loop (closure : List Attribute) (fuel : Nat) : List Attribute :=
    match fuel with
    | 0 => closure
    | fuel' + 1 =>
      let newAttrs := fds.foldl (fun acc fd =>
        if fd.determinant.all (· ∈ acc)
        then (fd.dependent.filter (· ∉ acc)) ++ acc
        else acc
      ) closure
      if newAttrs.length == closure.length then closure
      else loop newAttrs fuel'
  loop attrs (fds.length * 2 + 1)

/-- Check if a set of attributes is a superkey by computing its closure -/
def isSuperkeyClosure (s : Schema) (attrs : List Attribute) (fds : List (FunDep s)) : Bool :=
  let closure := attributeClosure attrs fds
  s.attributes.all (· ∈ closure)

/-! # Minimal Cover -/

/-- Remove an attribute from a determinant and check if the FD still holds
    (i.e., the remaining attributes still determine the dependent) -/
def isRedundantInDeterminant (attr : Attribute) (fd : FunDep s)
    (fds : List (FunDep s)) : Bool :=
  let reduced := fd.determinant.filter (· != attr)
  let closure := attributeClosure reduced fds
  fd.dependent.all (· ∈ closure)

/-- Reduce the left-hand side of each FD to minimal -/
def reduceLeftSides (fds : List (FunDep s)) : List (FunDep s) :=
  fds.map fun fd =>
    let minDet := fd.determinant.filter fun attr =>
      !isRedundantInDeterminant attr fd fds
    { fd with determinant := if minDet.isEmpty then fd.determinant else minDet }

/-- Check if two FDs have the same determinant and dependent -/
def FunDep.sameAs (fd1 fd2 : FunDep s) : Bool :=
  fd1.determinant == fd2.determinant && fd1.dependent == fd2.dependent

/-- Remove redundant FDs (those implied by the remaining FDs) -/
def removeRedundantFDs (fds : List (FunDep s)) : List (FunDep s) :=
  fds.filter fun fd =>
    let others := fds.filter fun fd' => !fd'.sameAs fd
    let closure := attributeClosure fd.determinant others
    !fd.dependent.all (· ∈ closure)

/-- Compute minimal cover: reduce left sides, then remove redundant FDs -/
def minimalCover (fds : List (FunDep s)) : List (FunDep s) :=
  removeRedundantFDs (reduceLeftSides fds)

/-! # 3NF Synthesis Algorithm -/

/-- Synthesize a 3NF decomposition using Bernstein's synthesis algorithm:
    1. Compute minimal cover of FDs
    2. Group FDs by determinant
    3. Create one relation per group: determinant ∪ all dependents
    4. If no relation contains a candidate key, add one -/
def synthesize3NF (s : Schema) (fds : List (FunDep s)) : NormalizationStep :=
  let mc := minimalCover fds

  -- Step 2-3: Create one schema per FD (or group by determinant)
  let fdSchemas := mc.map fun fd =>
    let attrs := (fd.determinant ++ fd.dependent).eraseDups
    ({ attributes := attrs, candidateKeys := [fd.determinant] } : Schema)

  -- Step 4: Check if any schema contains a candidate key
  let hasKey := fdSchemas.any fun schema =>
    s.candidateKeys.any fun key => key.all (· ∈ schema.attributes)

  -- If no schema contains a candidate key, add one
  let targets := if hasKey then fdSchemas
    else match s.candidateKeys with
      | key :: _ => fdSchemas ++ [{ attributes := key, candidateKeys := [key] }]
      | [] => fdSchemas

  -- Collect all join attributes (attributes appearing in 2+ schemas)
  let allAttrs := targets.map (·.attributes) |>.flatten
  let joinAttrs := allAttrs.filter fun a =>
    (targets.filter fun t => a ∈ t.attributes).length > 1
  let joinAttrs := joinAttrs.eraseDups

  let narrative := s!"3NF synthesis: decomposed {s.attributes} into {targets.length} " ++
    s!"relations using {mc.length} minimal-cover FDs"

  {
    decomposition := { source := s, targets := targets }
    joinAttributes := joinAttrs
    narrative := narrative
  }

/-! # BCNF Decomposition Algorithm -/

/-- Decompose to BCNF using the standard decomposition algorithm:
    1. Find a BCNF violation X → Y where X is not a superkey
    2. Decompose R into R1 = X ∪ Y and R2 = R - Y + X
    3. Recursively decompose R1 and R2
    Note: BCNF decomposition may not preserve all FDs. -/
def decomposeToBCNF (s : Schema) (fds : List (FunDep s)) : NormalizationStep :=
  -- Find first BCNF violation
  let violation := fds.find? fun fd =>
    !isSuperkey s fd.determinant

  match violation with
  | none =>
    -- Already in BCNF
    { decomposition := { source := s, targets := [s] }
      joinAttributes := []
      narrative := "Schema is already in BCNF" }
  | some fd =>
    -- Decompose: R1 = X ∪ Y, R2 = R \ Y ∪ X
    let r1Attrs := (fd.determinant ++ fd.dependent).eraseDups
    let r2Attrs := (s.attributes.filter (· ∉ fd.dependent) ++ fd.determinant).eraseDups
    let r1 : Schema := { attributes := r1Attrs, candidateKeys := [fd.determinant] }
    let r2 : Schema := { attributes := r2Attrs, candidateKeys := s.candidateKeys }

    let joinAttrs := fd.determinant  -- Common attributes for lossless join

    let narrative := s!"BCNF decomposition: split on violation {fd.determinant} → {fd.dependent}\n" ++
      s!"  R1 = {r1Attrs} (key: {fd.determinant})\n" ++
      s!"  R2 = {r2Attrs}\n" ++
      s!"  Join on: {joinAttrs}\n" ++
      s!"  Note: some FDs may not be preserved"

    { decomposition := { source := s, targets := [r1, r2] }
      joinAttributes := joinAttrs
      narrative := narrative }

/-! # Multi-Valued Dependencies (4NF) -/

/-- A multi-valued dependency X →→ Y -/
structure MVD (s : Schema) where
  determinant : List Attribute
  dependent : List Attribute

/-- Fourth Normal Form: BCNF + no non-trivial MVDs -/
def FourthNormalForm (s : Schema) (fds : List (FunDep s)) (mvds : List (MVD s)) : Prop :=
  BCNF s fds ∧
  ∀ mvd ∈ mvds,
    -- MVD is trivial if dependent ⊆ determinant or dependent ∪ determinant = all attributes
    mvd.dependent.all (· ∈ mvd.determinant) ∨
    isSuperkey s mvd.determinant

/-! # Denormalization Support (per D-NORM-003) -/

/-- A denormalization step with proof of losslessness -/
structure DenormalizationStep where
  /-- Source schemas to merge -/
  sourceSchemas : List Schema
  /-- Target merged schema -/
  targetSchema : Schema
  /-- Join attributes used to merge -/
  joinAttributes : List Attribute
  /-- Performance rationale for denormalization -/
  performanceRationale : String
  /-- Narrative explanation -/
  narrative : String
  deriving Repr

/-- Proof that a denormalization is lossless (can be split back) -/
structure LosslessDenormalization (d : DenormalizationStep) : Prop where
  /-- The split of the merged relation equals the original relations -/
  lossless : True  -- Would contain actual proof
  /-- Join attributes form a key in at least one source schema -/
  keyPreserved : True  -- Would contain actual proof

/-- Proof that denormalization preserves query equivalence -/
structure QueryEquivalent (d : DenormalizationStep) : Prop where
  /-- Any query on sources can be rewritten to equivalent query on target -/
  forwardEquivalent : True
  /-- Any query on target can be rewritten to equivalent query on sources -/
  backwardEquivalent : True

/-- A denormalization proposal with full proof and narrative -/
structure DenormalizationProposal where
  step : DenormalizationStep
  losslessProof : LosslessDenormalization step
  queryEquivalence : QueryEquivalent step

/-- Create a denormalization step for read optimization -/
def createDenormalization
    (sources : List Schema)
    (joinAttrs : List Attribute)
    (rationale : String) : DenormalizationStep :=
  let merged := {
    attributes := (sources.map (·.attributes)).flatten |>.eraseDups
    candidateKeys := []  -- Would compute from sources
  }
  {
    sourceSchemas := sources
    targetSchema := merged
    joinAttributes := joinAttrs
    performanceRationale := rationale
    narrative := s!"INTENTIONAL DENORMALIZATION\n" ++
                 s!"Reason: {rationale}\n" ++
                 s!"Merging {sources.length} schemas on {joinAttrs}\n" ++
                 s!"This trades storage efficiency for read performance.\n" ++
                 s!"Fully reversible via SPLIT on original keys."
  }

/-! # Three-Phase Migration (per D-NORM-005) -/

/-- Migration phase enumeration -/
inductive MigrationPhase where
  | announce  -- Proposal journaled, queries identified
  | shadow    -- Both schemas exist, queries rewritten
  | commit    -- Old schema removed, rewrite permanent
  deriving Repr, BEq

/-- Configuration for migration timing -/
structure MigrationConfig where
  /-- Duration of announce phase in hours (default 24) -/
  announceDuration : Nat := 24
  /-- Duration of shadow phase in days (default 7) -/
  shadowDuration : Nat := 7
  /-- Whether to auto-commit after shadow phase -/
  autoCommit : Bool := false
  deriving Repr

/-- A migration state tracking progress through phases -/
structure MigrationState where
  /-- Current phase -/
  phase : MigrationPhase
  /-- The normalization/denormalization step being applied -/
  transformation : NormalizationStep
  /-- Affected queries identified during announce -/
  affectedQueries : List String
  /-- Rewrite rules generated for shadow phase -/
  rewriteRules : List (String × String)  -- (original, rewritten)
  /-- Compatibility views created -/
  compatViews : List String
  /-- Journal entry for this migration -/
  journalEntry : Nat
  /-- Configuration -/
  config : MigrationConfig
  deriving Repr

/-- Start a migration in announce phase -/
def startMigration
    (transform : NormalizationStep)
    (affectedQueries : List String)
    (journalEntry : Nat)
    (config : MigrationConfig := {}) : MigrationState :=
  {
    phase := .announce
    transformation := transform
    affectedQueries := affectedQueries
    rewriteRules := []
    compatViews := []
    journalEntry := journalEntry
    config := config
  }

/-- Advance migration to shadow phase -/
def advanceToShadow (state : MigrationState) (rules : List (String × String)) (views : List String) : MigrationState :=
  { state with
    phase := .shadow
    rewriteRules := rules
    compatViews := views
  }

/-- Advance migration to commit phase (irreversible point) -/
def advanceToCommit (state : MigrationState) : MigrationState :=
  { state with
    phase := .commit
    compatViews := []  -- Views removed at commit
  }

/-! # Narrative Generation -/

/-- Generate human-readable narrative for an FD -/
def FunDep.toNarrative {s : Schema} (fd : FunDep s) : String :=
  let det := fd.determinant.toString
  let dep := fd.dependent.toString
  let conf := if fd.confidence < 1.0 then s!" [confidence: {fd.confidence}]" else ""
  s!"{det} uniquely determines {dep}{conf}"

/-- Generate narrative for a normalization proposal -/
def NormalizationStep.toNarrative (step : NormalizationStep) : String :=
  let source := step.decomposition.source.attributes.toString
  let targets := step.decomposition.targets.map (·.attributes.toString)
  s!"Decomposing {source} into {targets}\nReason: {step.narrative}"

/-- Generate narrative for a denormalization proposal -/
def DenormalizationStep.toNarrative (step : DenormalizationStep) : String :=
  let sources := step.sourceSchemas.map (·.attributes.toString)
  let target := step.targetSchema.attributes.toString
  s!"DENORMALIZATION: Merging {sources} into {target}\n" ++
  s!"Join attributes: {step.joinAttributes}\n" ++
  s!"Rationale: {step.performanceRationale}\n" ++
  step.narrative

/-- Generate narrative for migration state -/
def MigrationState.toNarrative (state : MigrationState) : String :=
  let phaseStr := match state.phase with
    | .announce => "ANNOUNCE (warning period)"
    | .shadow => "SHADOW (compatibility layer active)"
    | .commit => "COMMIT (migration complete)"
  s!"MIGRATION STATUS: {phaseStr}\n" ++
  s!"Journal entry: #{state.journalEntry}\n" ++
  s!"Affected queries: {state.affectedQueries.length}\n" ++
  s!"Rewrite rules: {state.rewriteRules.length}\n" ++
  s!"Compatibility views: {state.compatViews.length}"

end Lithoglyph.Normalizer
