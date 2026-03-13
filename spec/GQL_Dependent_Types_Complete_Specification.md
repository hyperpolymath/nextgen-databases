# GQL with Dependent Types: Complete Specification

**Version**: 0.2.0 (Dependent Types Extension)  
**Status**: Research Prototype  
**Date**: 2025-01-11  
**Authors**: Jonathan D.A. Jewell, Claude (Anthropic)  
**License**: MPL-2.0

## Table of Contents

1. [Introduction](#1-introduction)
2. [Type System](#2-type-system)
3. [Refinement Types](#3-refinement-types)
4. [Dependent Types](#4-dependent-types)
5. [DDL with Types](#5-ddl-with-types)
6. [DML with Proofs](#6-dml-with-proofs)
7. [Queries with Refinements](#7-queries-with-refinements)
8. [Proof Obligations](#8-proof-obligations)
9. [Tactics and Automation](#9-tactics-and-automation)
10. [Complete Examples](#10-complete-examples)

---

## 1. Introduction

### 1.1 What This Document Covers

This specification extends GQL with **dependent types**—types that can depend on values. This enables:

- **Compile-time verification** of constraints (e.g., PROMPT scores in [0, 100])
- **Provenance in types** (can't create data without provenance)
- **Reversibility proofs** (prove operations have inverses)
- **Machine-checkable correctness** (types ARE proofs)

### 1.2 Relationship to Standard GQL

```
Standard GQL (runtime checks):
  CREATE COLLECTION evidence (
    prompt_provenance INT CHECK (prompt_provenance BETWEEN 0 AND 100)
  );

GQL with Dependent Types (compile-time proofs):
  CREATE COLLECTION evidence (
    prompt_provenance : BoundedNat 0 100  -- Proof at type level
  ) WITH DEPENDENT_TYPES;
```

**Backward Compatibility**: Standard GQL is valid in dependent-type mode (types are inferred).

### 1.3 Implementation Languages

GQL with dependent types can be implemented in:
- **Idris 2**: Good balance of practicality and power
- **Lean 4**: Excellent IDE support, strong automation
- **Agda**: Most expressive, research-oriented
- **F*** / Dafny**: Refinement types, SMT-based

**Recommendation**: Lean 4 (best LSP support, large proof library).

### 1.4 Related Specifications

- **[Normalization Types](normalization-types.md)**: Extends this specification with type-encoded functional dependencies, normal form predicates (1NF through BCNF), and proof-carrying schema evolution. Integrates with Lithoglyph's self-normalizing database feature.

---

## 2. Type System

### 2.1 Type Universe

```
Type Hierarchy (Lean 4 notation):

Type 0 (Sort 0):  Prop           -- Propositions (proofs)
Type 1 (Sort 1):  Type           -- Data types
Type 2 (Sort 2):  Type 1         -- Types of types
...
Type ω (Sort ω):  Type ω-1       -- Infinite hierarchy
```

### 2.2 Primitive Types

```lean
-- Lean 4 primitives (available in GQL-DT)
Nat       : Type      -- Natural numbers (0, 1, 2, ...)
Int       : Type      -- Integers (..., -1, 0, 1, ...)
String    : Type      -- Unicode strings
Bool      : Type      -- true, false
Float     : Type      -- IEEE 754 floats
Char      : Type      -- Unicode characters
Unit      : Type      -- Single value: ()
```

### 2.3 Type Constructors

```lean
-- Product types (tuples, structs)
α × β                 -- Pair type
(a : α) × (b : β)     -- Dependent pair (Sigma type)

-- Sum types (tagged unions)
α ⊕ β                 -- Either α or β
Option α              -- Some a | None
```

### 2.4 Dependent Function Types

```lean
-- Simple function (non-dependent)
α → β                 -- Function from α to β

-- Dependent function (Pi type)
(x : α) → β x         -- Result type depends on input value

-- Universal quantification
∀ (x : α), P x        -- For all x of type α, P x holds
```

### 2.5 Dependent Pair Types

```lean
-- Sigma type (exists with witness)
(x : α) × β x         -- Pair where second component depends on first

-- Existential quantification
∃ (x : α), P x        -- There exists x of type α such that P x holds
```

---

## 3. Refinement Types

### 3.1 Bounded Natural Numbers

```lean
-- Definition
structure BoundedNat (min max : Nat) where
  val : Nat
  min_le : min ≤ val
  val_le : max

-- Type alias for PROMPT dimensions
abbrev PromptDimension := BoundedNat 0 100

-- Construction (automatic proof search)
def prompt95 : PromptDimension := ⟨95, by omega, by omega⟩

-- Shorthand with auto-proofs
instance : OfNat PromptDimension n := ⟨n, by omega, by omega⟩

-- Usage in GQL
CREATE COLLECTION evidence (
  id : UUID,
  prompt_provenance : PromptDimension
);
```

### 3.2 Bounded Floats

```lean
-- Definition
structure BoundedFloat (min max : Float) where
  val : Float
  min_le : min ≤ val
  val_le : val ≤ max

-- Type alias for confidence
abbrev Confidence := BoundedFloat 0.0 1.0

-- Usage
CREATE COLLECTION claims (
  id : UUID,
  confidence_level : Confidence
);
```

### 3.3 Non-Empty Strings

```lean
-- Definition
structure NonEmptyString where
  val : String
  nonempty : val.length > 0

-- Type aliases
abbrev Rationale := NonEmptyString
abbrev ActorId := NonEmptyString

-- GQL usage
INSERT INTO claims (text)
VALUES ('Some claim')
RATIONALE (r : Rationale);  -- Must be non-empty!
```

### 3.4 Email Addresses

```lean
-- Definition
structure Email where
  val : String
  valid : val.matches emailRegex

-- GQL usage
CREATE COLLECTION users (
  email : Email  -- Only valid emails!
);
```

### 3.5 Validated UUIDs

```lean
-- Definition
structure ValidUUID where
  val : String
  valid : val.matches uuidRegex
  length : val.length = 36

-- GQL usage
CREATE COLLECTION entities (
  id : ValidUUID PRIMARY KEY
);
```

---

## 4. Dependent Types

### 4.1 Length-Indexed Vectors

```lean
-- Definition
inductive Vector (α : Type) : Nat → Type where
  | nil  : Vector α 0
  | cons : α → Vector α n → Vector α (n + 1)

-- Safe head (can't fail!)
def head {α : Type} {n : Nat} : Vector α (n + 1) → α
  | .cons a _ => a

-- Type guarantees non-empty vector
```

**GQL Usage**:
```gql
-- Fixed-size array (compile-time checked)
CREATE COLLECTION survey_responses (
  id : UUID,
  ratings : Vector PromptDimension 6  -- Exactly 6 PROMPT dimensions
);
```

### 4.2 Provenance-Tracked Values

```lean
-- Definition
structure Tracked (α : Type) where
  value : α
  added_by : ActorId
  added_at : Timestamp
  rationale : Rationale

-- Constructor enforces provenance
def mkTracked (a : α) (actor : ActorId) (ts : Timestamp) (rat : Rationale) 
  : Tracked α :=
  ⟨a, actor, ts, rat⟩

-- Can't construct without provenance!
```

**GQL Usage**:
```gql
-- All values automatically tracked
CREATE COLLECTION claims (
  id : UUID,
  text : String
) WITH PROVENANCE_TRACKING;

-- Insertion requires provenance
INSERT INTO claims (text)
VALUES ('Inflation claim')
ADDED_BY "alice"
RATIONALE "Based on ONS data";
-- Automatically wrapped in Tracked
```

### 4.3 PROMPT Scores with Proof

```lean
-- Definition
structure PromptScores where
  provenance : PromptDimension
  replicability : PromptDimension
  objective : PromptDimension
  methodology : PromptDimension
  publication : PromptDimension
  transparency : PromptDimension
  overall : PromptDimension
  overall_correct : overall.val = 
    (provenance.val + replicability.val + objective.val +
     methodology.val + publication.val + transparency.val) / 6

-- Smart constructor
def mkPromptScores (p r o m pub t : PromptDimension) : PromptScores :=
  let avg := (p.val + r.val + o.val + m.val + pub.val + t.val) / 6
  ⟨p, r, o, m, pub, t, ⟨avg, by omega, by omega⟩, by simp [avg]⟩
```

**GQL Usage**:
```gql
INSERT INTO evidence (prompt_scores)
VALUES ({
  provenance: 100,
  replicability: 100,
  objective: 95,
  methodology: 95,
  publication: 100,
  transparency: 95
  -- 'overall' computed automatically with proof
})
RATIONALE "Official statistics";
```

### 4.4 Reversible Operations

```lean
-- Definition
inductive ReversibleOp (α : Type) : Type where
  | insert : (data : Tracked α) → 
             (inverse : DeleteOp α) → 
             (prf : roundTrip data inverse = data) →
             ReversibleOp α
  | update : (old new : Tracked α) →
             (inverse : UpdateOp α) →
             (prf : roundTrip (old, new) inverse = (new, old)) →
             ReversibleOp α
  | delete : (data : Tracked α) →
             (inverse : InsertOp α) →
             (prf : roundTrip data inverse = data) →
             ReversibleOp α
  | irreversible : (data : Tracked α) →
                   (reason : Rationale) →
                   (justification : WhyIrreversible reason) →
                   ReversibleOp α

-- Round-trip property
axiom roundTrip {α : Type} : α → (α → α) → α
axiom roundTripPreservesIdentity {α : Type} (x : α) (f : α → α) 
  : roundTrip x f = x
```

**GQL Usage**:
```gql
-- Reversible insertion
INSERT INTO claims (text)
VALUES ('Some claim')
RATIONALE "Initial claim"
WITH_INVERSE (
  DELETE FROM claims WHERE id = $GENERATED_ID
);
-- Type checker verifies inverse is correct

-- Irreversible deletion
DELETE FROM sensitive_data WHERE user = 'xyz'
REASON "GDPR right to erasure"
IRREVERSIBLE BECAUSE "Cryptographic deletion"
JUSTIFICATION {
  gdpr_article: 17,
  user_request_id: "REQ-001",
  physical_deletion: true
};
```

### 4.5 Confidence-Indexed Claims

```lean
-- Definition
structure Claim (c : Confidence) where
  id : UUID
  text : String
  evidence : List Evidence
  prf : confidenceJustified text evidence c

-- Can only construct if confidence matches evidence
axiom confidenceJustified : String → List Evidence → Confidence → Prop

-- Type-safe combination
def combineClaims {c1 c2 : Confidence} 
  (claim1 : Claim c1) (claim2 : Claim c2)
  (prf : compatible c1 c2) 
  : Claim (fuseConfidence c1 c2) := sorry
```

**GQL Usage**:
```gql
-- Claim with confidence in type
CREATE COLLECTION claims (
  id : UUID,
  text : String,
  confidence : Confidence
) WITH DEPENDENT_TYPES;

-- Can't combine incompatible claims
SELECT combineClaims(claim1, claim2)
FROM claims claim1, claims claim2
WHERE compatible(claim1.confidence, claim2.confidence);
-- Type error if not compatible!
```

### 4.6 Ordered Navigation Paths

```lean
-- Definition
structure NavigationPath (ordering : Evidence → Evidence → Bool) where
  nodes : List Evidence
  sorted : IsSorted ordering nodes

-- Proof that list is sorted
inductive IsSorted {α : Type} (r : α → α → Bool) : List α → Prop where
  | nil : IsSorted r []
  | single : ∀ a, IsSorted r [a]
  | cons : ∀ a b l, r a b = true → IsSorted r (b :: l) → IsSorted r (a :: b :: l)

-- Smart constructor (automatically proves sorted)
def createPath {ordering : Evidence → Evidence → Bool}
  (evs : List Evidence) 
  : NavigationPath ordering :=
  let sorted := List.insertionSort ordering evs
  ⟨sorted, insertionSortIsSorted ordering evs⟩
```

**GQL Usage**:
```gql
-- Path with proven ordering
CREATE NAVIGATION_PATH 'skeptic_path'
FOR INVESTIGATION 'uk_inflation_2023'
AUDIENCE 'SKEPTIC'
ORDERED_BY (λ e₁ e₂. e₁.prompt_objective < e₂.prompt_objective)
BEGIN
  SELECT * FROM evidence
  WHERE investigation_id = 'uk_inflation_2023'
END;
-- Type checker proves path is sorted
```

---

## 5. DDL with Types

### 5.1 CREATE COLLECTION (With Dependent Types)

**Syntax**:
```gql
CREATE COLLECTION [IF NOT EXISTS] collection_name (
  column_name : type [constraints],
  ...
) [WITH options];
```

**Examples**:

**Simple Refinement Types**:
```gql
CREATE COLLECTION evidence (
  id : UUID,
  title : NonEmptyString,
  prompt_provenance : BoundedNat 0 100,
  prompt_replicability : BoundedNat 0 100,
  prompt_objective : BoundedNat 0 100,
  prompt_methodology : BoundedNat 0 100,
  prompt_publication : BoundedNat 0 100,
  prompt_transparency : BoundedNat 0 100
) WITH DEPENDENT_TYPES;
```

**Provenance Tracking**:
```gql
CREATE COLLECTION claims (
  id : UUID,
  text : NonEmptyString,
  confidence : Confidence
) WITH PROVENANCE_TRACKING;
-- All values automatically wrapped in Tracked
```

**PROMPT Scores with Proof**:
```gql
CREATE COLLECTION evidence (
  id : UUID,
  title : NonEmptyString,
  prompt_scores : PromptScores  -- Proof of correct computation!
) WITH DEPENDENT_TYPES;
```

**Length-Indexed Arrays**:
```gql
CREATE COLLECTION survey (
  id : UUID,
  responses : Vector (BoundedNat 1 5) 10  -- Exactly 10 ratings (1-5 scale)
) WITH DEPENDENT_TYPES;
```

### 5.2 CREATE EDGE_COLLECTION (With Types)

```gql
CREATE EDGE_COLLECTION relationships (
  from_id : UUID,
  to_id : UUID,
  weight : BoundedFloat 0.0 1.0,
  reasoning : Rationale  -- Non-empty!
) WITH DEPENDENT_TYPES;
```

### 5.3 CREATE CONSTRAINT (With Proofs)

```gql
CREATE CONSTRAINT chk_adult_content
ON users (age : BoundedNat 0 150)
CHECK (age.val ≥ 18)
WITH_PROOF (λ u. ageProof u.age)
RATIONALE "COPPA compliance"
APPROVERS "legal_team";
```

---

## 6. DML with Proofs

### 6.1 INSERT (With Proof Obligations)

**Syntax**:
```gql
INSERT INTO collection_name (columns : types)
VALUES (values)
RATIONALE (rationale : Rationale)
[WITH_PROOF proofs];
```

**Examples**:

**Simple Bounded Values**:
```gql
INSERT INTO evidence (title, prompt_provenance)
VALUES (
  'ONS CPI Data',
  100  -- Type checker proves: 0 ≤ 100 ≤ 100 ✓
)
RATIONALE "Official statistics";
```

**Invalid Value (Type Error)**:
```gql
INSERT INTO evidence (prompt_provenance)
VALUES (150)  -- TYPE ERROR!
RATIONALE "Test";

-- Error: Cannot prove 150 ≤ 100
-- Suggestion: Use value between 0 and 100
```

**PROMPT Scores (Auto-Computed)**:
```gql
INSERT INTO evidence (prompt_scores)
VALUES ({
  provenance: 100,
  replicability: 100,
  objective: 95,
  methodology: 95,
  publication: 100,
  transparency: 95
  -- 'overall' computed with proof automatically!
})
RATIONALE "Official statistics";
```

**With Explicit Proof**:
```gql
INSERT INTO claims (text, confidence, evidence_list)
VALUES (
  'Inflation claim',
  0.95,
  [evidence1, evidence2, evidence3]
)
RATIONALE "Synthesized from ONS data"
WITH_PROOF {
  confidence_justified: confidenceProof text evidence_list 0.95
  -- Proves confidence matches evidence
};
```

### 6.2 UPDATE (With Correction Proof)

**Syntax**:
```gql
UPDATE collection_name
SET column = value
WHERE condition
REASON (reason : Rationale)
[WITH_PROOF proofs];
```

**Examples**:

**Simple Update**:
```gql
UPDATE evidence
SET prompt_replicability = 30  -- Type checker: 0 ≤ 30 ≤ 100 ✓
WHERE id = 'study_x'
REASON "Study failed to replicate"
DISCLOSED_AT NOW();
```

**Update with Proof of Validity**:
```gql
UPDATE claims
SET text = 'Corrected text',
    confidence = 0.98
WHERE id = 'claim_123'
REASON "ONS revised figures"
WITH_PROOF {
  new_confidence_justified: confidenceProof new_text new_evidence 0.98,
  correction_documented: reasonValid "ONS revised figures"
};
```

**Reversible Update**:
```gql
UPDATE claims
SET text = 'New text'
WHERE id = 'claim_123'
REASON "Correction"
WITH_INVERSE (
  UPDATE claims
  SET text = 'Old text'
  WHERE id = 'claim_123'
  REASON "Reverting correction"
)
WITH_PROOF {
  inverse_correct: roundTripProof old_text new_text inverse_op
};
```

### 6.3 DELETE (With Justification)

**Reversible Delete**:
```gql
DELETE FROM temp_data
WHERE created_at < NOW() - INTERVAL '30 days'
REASON "Temporary data expired"
WITH_INVERSE (
  -- Restore from backup
  INSERT INTO temp_data SELECT * FROM backup_data
)
WITH_PROOF {
  inverse_restores: deleteInsertRoundTrip data inverse
};
```

**Irreversible Delete**:
```gql
DELETE FROM sensitive_data
WHERE user = 'xyz'
REASON "GDPR right to erasure"
IRREVERSIBLE BECAUSE "Physical deletion + crypto shredding"
WITH_JUSTIFICATION {
  legal_basis: GDPRArticle17,
  user_request: "REQ-2024-001",
  no_backup: true,
  crypto_deletion: true
};
```

---

## 7. Queries with Refinements

### 7.1 SELECT with Type Refinements

**Syntax**:
```gql
SELECT (columns : refined_types)
FROM collection
WHERE (condition : Prop)
RETURNING (result : ResultType);
```

**Examples**:

**Simple Refinement**:
```gql
-- Return only high-quality evidence
SELECT (e : Evidence | e.prompt_overall > 90)
FROM evidence e
WHERE investigation_id = 'uk_inflation_2023';

-- Return type proves all results satisfy predicate!
```

**Multiple Refinements**:
```gql
SELECT (
  c : Claim | c.confidence > 0.85,
  e : Evidence | e.prompt_overall > 90
)
FROM claims c
  JOIN relationships r ON c.id = r.from_id
  JOIN evidence e ON r.to_id = e.id
WHERE r.relationship_type = 'SUPPORTS';

-- Type proves all results satisfy both conditions
```

**Exists with Witness**:
```gql
-- Find claims with at least one supporting evidence
SELECT (c : Claim, ∃ e : Evidence, supports(c, e))
FROM claims c
WHERE EXISTS (
  SELECT * FROM relationships r
  WHERE r.from_id = c.id AND r.relationship_type = 'SUPPORTS'
);

-- Returns pairs (claim, evidence) with proof that e supports c
```

### 7.2 Aggregates with Proofs

```gql
-- Compute average with proof it's in bounds
SELECT (
  investigation_id,
  avg_prompt : BoundedFloat 0.0 100.0,
  prf : averageInBounds evidence_list avg_prompt
)
FROM evidence
GROUP BY investigation_id;

-- Type proves average is in [0, 100]
```

### 7.3 JOIN with Type Safety

```gql
-- Type-safe join
SELECT *
FROM claims c
  JOIN (e : Evidence | e.prompt_overall > 85) ON ...
-- Can only join with high-quality evidence
```

---

## 8. Proof Obligations

### 8.1 Automatic Proof Search

**Simple Arithmetic**:
```gql
INSERT INTO evidence (prompt_provenance)
VALUES (95);  -- Type checker auto-proves: 0 ≤ 95 ≤ 100

-- Behind the scenes (Lean 4 tactics):
-- by omega  -- Linear arithmetic solver
```

**Computed Fields**:
```gql
INSERT INTO evidence (prompt_scores)
VALUES ({provenance: 100, ...});
-- Type checker auto-computes overall and proves correctness

-- Behind the scenes:
-- overall_correct: by simp [computeOverall]; omega
```

### 8.2 Manual Proofs

**When Auto-Proof Fails**:
```gql
INSERT INTO claims (text, confidence, evidence_list)
VALUES ('Complex claim', 0.92, [e1, e2, e3])
RATIONALE "Multi-source synthesis"
WITH_PROOF {
  confidence_justified: 
    -- Manual Lean 4 proof
    by
      intro text evidence conf
      sorry  -- User must complete
};
```

### 8.3 Proof Tactics

**Available Tactics**:
```lean
-- Arithmetic
omega           -- Linear arithmetic
norm_num        -- Numeric normalization
ring            -- Ring algebra

-- Simplification
simp [rules]    -- Simplification with rules
simp_arith      -- Arithmetic simplification

-- Logic
intro           -- Introduce assumption
apply           -- Apply theorem
exact           -- Provide exact proof
constructor     -- Construct data/proof

-- Automation
trivial         -- Solve trivial goals
decide          -- Decision procedures
aesop           -- Automated search
```

**Example Usage**:
```gql
WITH_PROOF {
  score_in_bounds: by omega,
  overall_correct: by simp [computeOverall]; norm_num,
  rationale_nonempty: by decide
}
```

### 8.4 Proof Libraries

**Pre-Proved Theorems**:
```lean
-- Lithoglyph standard library
namespace Lithoglyph.Proofs

-- Bounded values
theorem averagePreservesBounds {n : Nat} (xs : Vector (BoundedNat 0 100) n)
  : let avg := (xs.sum / n)
    0 ≤ avg ∧ avg ≤ 100 := by ...

-- Confidence
theorem confidenceInBounds (c : Confidence)
  : 0.0 ≤ c.val ∧ c.val ≤ 1.0 := by ...

-- Provenance
theorem trackedHasProvenance {α : Type} (t : Tracked α)
  : t.added_by.val.length > 0 ∧ t.rationale.val.length > 0 := by ...

-- Reversibility
theorem insertDeleteRoundTrip {α : Type} (x : Tracked α)
  : roundTrip x (delete (insert x)) = x := by ...

end Lithoglyph.Proofs
```

---

## 9. Tactics and Automation

### 9.1 Lithoglyph-Specific Tactics

```lean
-- Custom tactics for Lithoglyph
namespace Lithoglyph.Tactics

-- Auto-solve bounds proofs
syntax "lithoglyph_bounds" : tactic
macro_rules
  | `(tactic| lithoglyph_bounds) => `(tactic| first | omega | norm_num | decide)

-- Auto-solve provenance proofs
syntax "lithoglyph_prov" : tactic
macro_rules
  | `(tactic| lithoglyph_prov) => `(tactic| 
      simp only [Tracked, NonEmptyString]; 
      constructor <;> decide)

-- Auto-solve PROMPT score proofs
syntax "lithoglyph_prompt" : tactic
macro_rules
  | `(tactic| lithoglyph_prompt) => `(tactic|
      simp [PromptScores, computeOverall];
      lithoglyph_bounds)

end Lithoglyph.Tactics
```

**Usage in GQL**:
```gql
WITH_PROOF {
  score_valid: by lithoglyph_prompt,
  provenance_exists: by lithoglyph_prov,
  confidence_in_range: by lithoglyph_bounds
}
```

### 9.2 IDE Integration

**Lean 4 VSCode Extension**:
```
Features:
• Type on hover (see inferred types)
• Error highlighting (red underlines for proof failures)
• Proof state view (see current goal)
• Tactic suggestions (auto-complete)
• Proof search (find relevant lemmas)
```

**Example IDE Workflow**:
1. Write GQL with `VALUES (...)`
2. IDE shows: "Missing proof of X"
3. User writes `WITH_PROOF { x: by }`
4. IDE suggests tactics: `omega, simp, decide`
5. User selects tactic, proof completes
6. IDE shows: ✓ Type checked successfully

### 9.3 Proof Caching

**Incremental Type Checking**:
```
# First type-check (slow)
$ lean4 lithoglyph_queries.lean
Type checking... 25s
✓ All proofs valid

# Second type-check (fast - cached)
$ lean4 lithoglyph_queries.lean
Type checking... 0.5s (95% cached)
✓ All proofs valid
```

**Proof Cache Format**:
```lean
-- .lithoglyph-cache/proofs.lean
theorem cached_proof_12345 : P := by <...compiled proof...>
```

---

## 10. Complete Examples

### 10.1 BoFIG UK Inflation 2023 (Fully Typed)

```gql
-- Step 1: Create evidence collection with dependent types
CREATE COLLECTION bofig_evidence (
  id : UUID,
  investigation_id : String,
  title : NonEmptyString,
  evidence_type : EvidenceType,
  url : Option String,
  prompt_scores : PromptScores
) WITH DEPENDENT_TYPES, PROVENANCE_TRACKING;

-- Step 2: Insert evidence (type-checked)
INSERT INTO bofig_evidence (
  title, evidence_type, url, prompt_scores
)
VALUES (
  'ONS Consumer Price Inflation, UK: 2023',
  'official_statistics',
  'https://www.ons.gov.uk/cpi/2023',
  {
    provenance: 100,
    replicability: 100,
    objective: 95,
    methodology: 95,
    publication: 100,
    transparency: 95
    -- overall: computed automatically to 97.5
  }
)
RATIONALE "Official UK government statistics"
ADDED_BY "journalist_alice"
WITH_PROOF {
  all_scores_in_bounds: by lithoglyph_prompt,
  overall_computed_correctly: by lithoglyph_prompt,
  rationale_nonempty: by lithoglyph_prov
};
-- Type checker: ✓ All proofs valid

-- Step 3: Create claims with confidence proofs
CREATE COLLECTION bofig_claims (
  id : UUID,
  text : NonEmptyString,
  confidence : Confidence,
  evidence_ids : List UUID
) WITH DEPENDENT_TYPES, PROVENANCE_TRACKING;

INSERT INTO bofig_claims (text, confidence, evidence_ids)
VALUES (
  'Rent inflation (12.7%) exceeded overall inflation (8.0%) in 2023',
  0.95,
  [evidence_ons_id]
)
RATIONALE "Synthesized from ONS CPI Table 3.2"
ADDED_BY "journalist_alice"
WITH_PROOF {
  confidence_justified: confidenceFromEvidence text [evidence_ons] 0.95,
  -- Proof that confidence 0.95 matches evidence quality
  evidence_exists: by apply List.mem_of_cons_mem; trivial
};

-- Step 4: Create edge with reasoning (non-empty)
CREATE EDGE_COLLECTION bofig_relationships (
  from_id : UUID,
  to_id : UUID,
  relationship_type : RelType,
  weight : BoundedFloat 0.0 1.0,
  reasoning : Rationale  -- Can't be empty!
) WITH DEPENDENT_TYPES, PROVENANCE_TRACKING;

INSERT EDGE INTO bofig_relationships (from_id, to_id, type, weight, reasoning)
VALUES (
  claim_id,
  evidence_id,
  'SUPPORTS',
  0.95,
  'ONS Table 3.2 shows rent at 12.7% vs headline 8.0%'
)
RATIONALE "Primary evidence for claim"
ADDED_BY "journalist_alice"
WITH_PROOF {
  weight_in_bounds: by lithoglyph_bounds,
  reasoning_nonempty: by lithoglyph_prov
};

-- Step 5: Query with refinement
SELECT (
  c : Claim | c.confidence > 0.85,
  e : Evidence | e.prompt_overall > 90,
  r : Relationship
)
FROM bofig_claims c
  JOIN bofig_relationships r ON c.id = r.from_id
  JOIN bofig_evidence e ON r.to_id = e.id
WHERE c.investigation_id = 'uk_inflation_2023'
  AND r.relationship_type = 'SUPPORTS'
RETURNING (List (Claim × Evidence × Relationship) | 
           ∀ (c, e, r) ∈ result, c.confidence > 0.85 ∧ e.prompt_overall > 90);
-- Return type PROVES all results satisfy conditions!
```

### 10.2 Correction Workflow (With Reversiibility Proof)

```gql
-- Original insertion
INSERT INTO bofig_claims (text, confidence)
VALUES ('Inflation reached 12% in 2023', 0.90)
RATIONALE "Based on ONS preliminary data"
ADDED_BY "journalist_alice"
WITH_INVERSE (
  DELETE FROM bofig_claims WHERE id = $GENERATED_ID
)
WITH_PROOF {
  inverse_correct: insertDeleteRoundTrip claim
};

-- Later: Correction (with reversiibility)
UPDATE bofig_claims
SET text = 'Inflation reached 12.7% in 2023',
    confidence = 0.95
WHERE text LIKE '%12%'
REASON "ONS revised figures: preliminary 12%, final 12.7%"
CORRECTION_TYPE "factual_update"
DISCLOSED_AT NOW()
DISCLOSED_BY "journalist_alice"
WITH_INVERSE (
  UPDATE bofig_claims
  SET text = 'Inflation reached 12% in 2023',
      confidence = 0.90
  WHERE id = claim_id
  REASON "Reverting to preliminary figures"
)
WITH_PROOF {
  inverse_correct: updateRoundTrip old_text new_text inverse,
  new_confidence_valid: by lithoglyph_bounds,
  correction_reason_nonempty: by lithoglyph_prov
};

-- Query correction history with proofs
INTROSPECT bofig_claims.claim_123 CORRECTION_HISTORY
RETURNING (List CorrectionEntry | 
           ∀ e ∈ result, e.inverse_correct ∧ e.reason.length > 0);
-- Type proves all corrections have valid inverses!
```

### 10.3 My-Newsroom Belief Fusion (Type-Safe)

```gql
-- Define belief type
abbrev AgentBelief := Belief Confidence String

-- Record agent beliefs
CREATE COLLECTION agent_beliefs (
  agent_id : ActorId,
  claim_text : String,
  belief : AgentBelief,
  rationale : Rationale
) WITH DEPENDENT_TYPES, PROVENANCE_TRACKING;

-- Agent A asserts belief
INSERT INTO agent_beliefs (agent_id, claim_text, belief, rationale)
VALUES (
  'agent_reporter',
  'UK rent inflation exceeded 12%',
  (MkBelief 'true' 0.85),  -- 85% confidence
  'ONS data shows 12.7%'
)
ADDED_BY "orchestrator"
WITH_PROOF {
  confidence_in_bounds: by lithoglyph_bounds
};

-- Agent B asserts belief
INSERT INTO agent_beliefs (agent_id, claim_text, belief, rationale)
VALUES (
  'agent_fact_checker',
  'UK rent inflation exceeded 12%',
  (MkBelief 'true' 0.78),  -- 78% confidence
  'Cross-checked 3 sources'
)
ADDED_BY "orchestrator"
WITH_PROOF {
  confidence_in_bounds: by lithoglyph_bounds
};

-- Fuse beliefs (type-safe)
INSERT INTO belief_fusions (claim_text, fused_belief)
SELECT 
  claim_text,
  fuseBeliefsDS(b1.belief, b2.belief)  -- Type-safe fusion!
FROM agent_beliefs b1, agent_beliefs b2
WHERE b1.agent_id = 'agent_reporter'
  AND b2.agent_id = 'agent_fact_checker'
  AND b1.claim_text = b2.claim_text
RATIONALE "Dempster-Shafer fusion of agent beliefs"
ADDED_BY "orchestrator"
WITH_PROOF {
  fusion_preserves_bounds: fusionInBounds b1.confidence b2.confidence,
  fusion_correct: fusionMatchesDempster b1 b2
};
-- Type checker proves fusion result is in [0.0, 1.0]!
```

### 10.4 Navigation Path (With Ordering Proof)

```gql
-- Create path with proven ordering
CREATE NAVIGATION_PATH 'skeptic_path_typed'
FOR INVESTIGATION 'uk_inflation_2023'
AUDIENCE 'SKEPTIC'
ORDERED_BY (λ e₁ e₂. e₁.prompt_objective < e₂.prompt_objective)
AS (
  SELECT (e : Evidence | e.investigation_id = 'uk_inflation_2023')
  FROM bofig_evidence e
  ORDER BY e.prompt_objective ASC
)
RATIONALE "Skeptics see conflicts of interest first"
CREATED_BY "journalist_jane"
WITH_PROOF {
  path_sorted: isSorted (·.prompt_objective < ·.prompt_objective) nodes
};
-- Type proves path is sorted by objective score!

-- Query path (type guarantees ordering)
SELECT * FROM NAVIGATION_PATH 'skeptic_path_typed'
RETURNING (NavigationPath (λ e₁ e₂. e₁.prompt_objective < e₂.prompt_objective));
-- Return type carries ordering proof!
```

---

## Appendix A: Type Notation Reference

### A.1 Lean 4 Notation

```lean
-- Types
α : Type              -- Type variable
α → β                 -- Function type
(x : α) → β x         -- Dependent function
α × β                 -- Product (pair)
(x : α) × β x         -- Dependent pair (Sigma)
∀ (x : α), P x        -- Universal quantification
∃ (x : α), P x        -- Existential quantification

-- Propositions
P ∧ Q                 -- Conjunction (and)
P ∨ Q                 -- Disjunction (or)
¬P                    -- Negation
P → Q                 -- Implication
P ↔ Q                 -- If and only if

-- Comparisons
a ≤ b                 -- Less than or equal
a < b                 -- Less than
a = b                 -- Equality
```

### A.2 GQL Notation Mapping

| GQL Syntax | Lean 4 Type | Meaning |
|------------|-------------|---------|
| `BoundedNat 0 100` | `{n : Nat // 0 ≤ n ∧ n ≤ 100}` | Nat in [0, 100] |
| `NonEmptyString` | `{s : String // s.length > 0}` | Non-empty string |
| `Confidence` | `BoundedFloat 0.0 1.0` | Float in [0.0, 1.0] |
| `Tracked α` | `(α × ActorId × Timestamp × Rationale)` | Provenance-tracked value |
| `Vector α n` | Dependent array of exactly n elements | Fixed-length array |
| `Claim c` | Claim indexed by confidence level c | Confidence-indexed claim |

---

## Appendix B: Error Messages

### B.1 Bound Violation

```
TYPE ERROR at line 5, column 23:

  INSERT INTO evidence (prompt_provenance) VALUES (150)
                                                   ^^^

Cannot construct BoundedNat 0 100 with value 150

Expected: n ≤ 100
Got: 150
Proof failed: 150 ≤ 100

Suggestions:
• Use a value between 0 and 100
• Check if you meant 15 (typo)?
```

### B.2 Missing Proof

```
PROOF OBLIGATION FAILED at line 12:

  INSERT INTO claims (confidence, evidence_list) VALUES (0.95, [...])

Missing proof: confidenceJustified text evidence_list 0.95

This proof is required to show that confidence level 0.95 is
justified by the provided evidence.

Suggestions:
• Provide WITH_PROOF { confidence_justified: <proof> }
• Use a tactic: by confidenceFromEvidence text evidence_list 0.95
• Lower confidence to match evidence quality
```

### B.3 Type Mismatch

```
TYPE ERROR at line 8, column 15:

  SELECT combineClaims(claim1, claim2) FROM ...

Type mismatch:
  Expected: compatible claim1.confidence claim2.confidence
  Got: incompatible (claim1.confidence = 0.5, claim2.confidence = 0.9)

Cannot combine claims with incompatible confidence levels.

Suggestion: Filter claims WHERE confidence BETWEEN 0.8 AND 1.0
```

---

## Appendix C: Proof Cookbook

### C.1 Bounded Integers

```lean
-- Prove n is in bounds
example : 95 ≤ 100 := by omega

-- Prove average preserves bounds
example (a b : BoundedNat 0 100) : let avg := (a.val + b.val) / 2; avg ≤ 100 := by
  omega
```

### C.2 Non-Empty Strings

```lean
-- Prove string is non-empty
example : "hello".length > 0 := by decide

-- Prove concatenation is non-empty if both non-empty
example (s1 s2 : NonEmptyString) : (s1.val ++ s2.val).length > 0 := by
  have h1 := s1.nonempty
  have h2 := s2.nonempty
  omega
```

### C.3 Provenance Tracking

```lean
-- Prove tracked value has provenance
example (t : Tracked α) : t.rationale.val.length > 0 := 
  t.rationale.nonempty

-- Prove all tracked values in list have provenance
example (ts : List (Tracked α)) : ∀ t ∈ ts, t.rationale.val.length > 0 := by
  intro t ht
  exact t.rationale.nonempty
```

### C.4 Reversibility

```lean
-- Prove insert-delete is identity
theorem insertDeleteRoundTrip {α : Type} (x : Tracked α)
  : delete (insert x) = x := by
  simp [insert, delete]
  -- Implementation-specific proof

-- Prove update-update is reversible
theorem updateReverses {α : Type} (old new : Tracked α)
  : update new old (update old new data) = data := by
  simp [update]
  -- Implementation-specific proof
```

---

**Document Status**: Research prototype specification.

**Implementation**: Lean 4 recommended (best IDE support).

**Timeline**: 
- Phase 1 (Month 1-6): Refinement types
- Phase 2 (Month 7-12): Simple dependent types
- Phase 3 (Month 13-18): Full verification

**See Also**:
- WP06: Dependently-Typed Lithoglyph (research proposal)
- Lithoglyph arXiv paper (Section 14: Future Work)
- My-Newsroom Me dialect (epistemic types)
