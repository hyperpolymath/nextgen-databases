# White Paper 06: Dependently-Typed Lithoglyph

**Status**: Research Proposal  
**Version**: 0.1.0  
**Date**: 2025-01-11  
**Authors**: Jonathan D.A. Jewell, Claude (Anthropic)  
**License**: MPL-2.0

## Abstract

Lithoglyph's narrative-first architecture demands stronger correctness guarantees than traditional databases can provide. We propose extending Lithoglyph with dependent types—types that depend on values—enabling compile-time verification of epistemic properties. This transforms Lithoglyph from a database that *records* provenance to one that *proves* provenance. We demonstrate how dependent types naturally express PROMPT score constraints, provenance tracking, reversibility proofs, and belief fusion in the My-Newsroom multi-agent system. Our approach is incremental: refinement types first (simple, high ROI), then full dependent types (research frontier). This positions Lithoglyph as the first database with **provable epistemology**, uniquely suited for journalism, scientific reproducibility, and AI agent collaboration where correctness is non-negotiable.

## 1. Introduction

### 1.1 The Problem: Runtime Correctness Is Insufficient

Traditional databases enforce correctness at **runtime**:

```sql
-- SQL: Runtime constraint
CREATE TABLE evidence (
  prompt_provenance INT CHECK (prompt_provenance BETWEEN 0 AND 100)
);

-- Valid at compile time, error at insert
INSERT INTO evidence (prompt_provenance) VALUES (150);
-- ERROR: Check constraint "prompt_provenance_range" violated
```

**Problems**:
1. **Late detection**: Errors caught during execution, not development
2. **Incomplete coverage**: Can't express "every UPDATE must have REASON"
3. **No proofs**: Can't prove invariants hold across all operations
4. **Agent confusion**: LLM agents struggle with runtime-only validation

### 1.2 The Solution: Dependent Types

**Dependent types** are types that depend on values:

```idris
-- Idris: Compile-time proof
data PromptScore : Type where
  MkPromptScore : (n : Nat) -> 
                  {auto prf : LTE n 100} ->  -- Proof obligation
                  PromptScore

-- Invalid score is a TYPE ERROR, caught immediately
badScore : PromptScore
badScore = MkPromptScore 150  -- TYPE ERROR: Can't prove LTE 150 100
```

**Benefits**:
1. **Early detection**: Type errors at compile time (or before)
2. **Complete coverage**: Type system enforces ALL invariants
3. **Machine-checkable proofs**: Types ARE proofs (Curry-Howard correspondence)
4. **Agent-friendly**: LLM agents can check types before generating code

### 1.3 Why Lithoglyph Needs This

Lithoglyph has **unique epistemic requirements**:

| Requirement | Current (Runtime) | With Dependent Types |
|-------------|-------------------|---------------------|
| PROMPT scores in [0, 100] | Runtime CHECK | Compile-time proof |
| Every INSERT needs RATIONALE | Parser check | Type system enforces |
| Provenance tracked | Application code | Baked into types |
| Operations reversible | Runtime verification | Proof of inverse exists |
| Confidence levels valid | Runtime CHECK | Type-level bounds |
| Navigation paths ordered | Runtime sort | Type proves ordering |

**Thesis**: Dependent types transform Lithoglyph from a database that *records* epistemology to one that *proves* epistemology.

## 2. Background: Dependent Types

### 2.1 What Are Dependent Types?

**Simple types** (SQL, most PLs):
```
Int, String, Boolean
Array<Int>, Maybe<String>
```

**Dependent types** (Idris, Agda, Lean):
```
Vector n Int           -- Array of EXACTLY n integers
Bounded 0 100 Int      -- Integer between 0 and 100
{x : Int | x > 0}      -- Refinement: positive integers
```

Key insight: **Types can mention values**, enabling precise specifications.

### 2.2 Refinement Types (Subset of Dependent Types)

**Refinement types** restrict existing types with predicates:

```idris
-- Base type + predicate
type PositiveInt = {n : Int | n > 0}
type Email = {s : String | matches s emailRegex}
type PromptScore = {n : Nat | 0 <= n && n <= 100}
```

**Why start here?**
- Easier to understand than full dependent types
- High ROI: catches most errors
- Libraries exist (Liquid Haskell, F*, Dafny)

### 2.3 Full Dependent Types

**Full dependent types** allow arbitrary value dependencies:

```idris
-- Length-indexed vectors
data Vect : Nat -> Type -> Type where
  Nil  : Vect 0 a
  (::) : a -> Vect n a -> Vect (S n) a

-- Type proves operation succeeds
head : Vect (S n) a -> a  -- Can't call on empty vector
head (x :: xs) = x

-- Concatenation preserves length
(++) : Vect n a -> Vect m a -> Vect (n + m) a
```

**Why eventually move here?**
- Express complex invariants (navigation path ordering)
- Prove operations correct (reversibility)
- Enable advanced reasoning (belief fusion proofs)

### 2.4 Curry-Howard Correspondence

**Key insight**: Types = Propositions, Programs = Proofs

```
Mathematical Logic      Programming
--------------------    ---------------------
Proposition             Type
Proof                   Program/Value
Theorem                 Type inhabited by program
Implication (A → B)     Function type (A -> B)
Conjunction (A ∧ B)     Product type (A, B)
Disjunction (A ∨ B)     Sum type (Either A B)
Universal (∀x. P(x))    Dependent function (x : A) -> P x
```

**Example**:
```idris
-- Proposition: "For all n, n + 0 = n"
plusZeroRightNeutral : (n : Nat) -> n + 0 = n
plusZeroRightNeutral Z = Refl      -- Proof for zero
plusZeroRightNeutral (S k) =       -- Proof for successor
  rewrite plusZeroRightNeutral k in Refl
```

**For Lithoglyph**: Type-checking = Proof-checking. If it compiles, the proof is valid!

## 3. Motivation: Lithoglyph's Epistemic Requirements

### 3.1 PROMPT Score Invariants

**Current** (runtime):
```gql
CREATE COLLECTION evidence (
  prompt_scores STRUCT {
    provenance INT CHECK (provenance BETWEEN 0 AND 100),
    replicability INT CHECK (replicability BETWEEN 0 AND 100),
    objective INT CHECK (objective BETWEEN 0 AND 100),
    methodology INT CHECK (methodology BETWEEN 0 AND 100),
    publication INT CHECK (publication BETWEEN 0 AND 100),
    transparency INT CHECK (transparency BETWEEN 0 AND 100),
    overall COMPUTED AS (provenance + replicability + objective +
                         methodology + publication + transparency) / 6.0
  }
);
```

**Problems**:
1. Can construct invalid struct: `{provenance: 150, ...}`
2. Runtime error only on INSERT
3. No proof that `overall` is in [0, 100]
4. Agents might hallucinate invalid scores

**With Dependent Types**:
```idris
-- Refinement type: scores in [0, 100]
PromptDimension : Type
PromptDimension = BoundedNat 0 100

-- Struct with proof that overall is computed correctly
data PromptScores : Type where
  MkPromptScores :
    (provenance : PromptDimension) ->
    (replicability : PromptDimension) ->
    (objective : PromptDimension) ->
    (methodology : PromptDimension) ->
    (publication : PromptDimension) ->
    (transparency : PromptDimension) ->
    (overall : PromptDimension) ->
    {auto prf : overall = computeOverall provenance replicability 
                                         objective methodology 
                                         publication transparency} ->
    PromptScores

-- Proof that average of bounded values is bounded
computeOverall : PromptDimension -> PromptDimension -> PromptDimension ->
                 PromptDimension -> PromptDimension -> PromptDimension ->
                 PromptDimension
computeOverall p r o m pub t = 
  MkBounded ((p + r + o + m + pub + t) `div` 6)
    {prf = averageInBounds p r o m pub t}
```

**Benefits**:
- Invalid scores are TYPE ERRORS (caught at compile time)
- Proof that `overall` is always in range
- Agents can type-check before execution

### 3.2 Mandatory Rationale

**Current** (parser):
```gql
INSERT INTO claims (text) VALUES ('Some claim');
-- Parser error: "Missing RATIONALE clause"
```

**Problem**: Easy to forget in generated code. Parser can be bypassed.

**With Dependent Types**:
```idris
-- Operations MUST carry provenance
data ProvenanceTracked : Type -> Type where
  MkTracked : 
    (value : a) ->
    (added_by : String) ->
    (added_at : Timestamp) ->
    (rationale : NonEmptyString) ->  -- Can't be empty!
    ProvenanceTracked a

-- Type signature FORCES provenance
insertClaim : (text : String) -> 
              (rationale : NonEmptyString) ->  -- Required argument!
              (actor : String) ->
              ProvenanceTracked Claim
```

**Benefits**:
- Impossible to forget RATIONALE (type error)
- Type system enforces ALL insertions have provenance
- LLM agents see type signature, know what's required

### 3.3 Reversibility Proofs

**Current** (runtime verification):
```gql
-- Claim operation is reversible
INSERT INTO claims (text) VALUES ('X') RATIONALE "...";
-- Lithoglyph generates inverse: DELETE FROM claims WHERE id = 'uuid'
-- Tests at runtime that inverse works
```

**Problem**: 
- Inverse might be wrong (subtle bugs)
- Only tested on specific data
- No guarantee for ALL possible inputs

**With Dependent Types**:
```idris
-- Operations carry proof of inverse
data Reversible : Type -> Type where
  Insert : (data : a) ->
           (inverse : Delete a) ->
           {auto prf : roundTrip data inverse = data} ->  -- Proof!
           Reversible a
  
  Update : (old : a) ->
           (new : a) ->
           (inverse : Update a) ->
           {auto prf : roundTrip (old, new) inverse = (new, old)} ->
           Reversible a
  
  Irreversible : (data : a) ->
                 (reason : NonEmptyString) ->
                 (justification : Why reason) ->  -- Proof of why!
                 Reversible a

-- Proof that round-trip preserves data
roundTrip : a -> (a -> a) -> a
roundTripPreservesIdentity : (x : a) -> (f : a -> a) -> 
                              roundTrip x f = x
```

**Benefits**:
- **Mathematical proof** that inverse is correct
- Proof holds for ALL inputs, not just tested cases
- Can't mark something irreversible without proving why

### 3.4 Confidence Levels

**Current**:
```gql
confidence_level FLOAT CHECK (confidence_level BETWEEN 0.0 AND 1.0)
```

**With Dependent Types**:
```idris
-- Confidence in [0.0, 1.0]
Confidence : Type
Confidence = BoundedFloat 0.0 1.0

-- Claims indexed by confidence
data Claim : Confidence -> Type where
  MkClaim : (text : String) ->
            (evidence : List Evidence) ->
            {auto prf : confidenceJustified text evidence c} ->
            Claim c

-- Type system ensures confidence matches evidence
combineClaims : Claim c1 -> Claim c2 -> 
                {auto prf : Compatible c1 c2} ->
                Claim (fuseConfidence c1 c2)
```

**Benefits**:
- Confidence can't exceed 1.0 (type error)
- Type proves confidence matches evidence
- Combining claims requires proof of compatibility

### 3.5 Navigation Path Ordering

**Current**:
```gql
-- Navigation path (runtime sorting)
CREATE NAVIGATION_PATH 'skeptic_path'
BEGIN
  NODE evidence WHERE prompt_objective < 70 ORDER BY prompt_objective ASC;
  NODE claims WHERE claim_type = 'COUNTER';
  -- ... etc
END;
```

**Problem**: Ordering is application logic, not proven.

**With Dependent Types**:
```idris
-- Paths indexed by ordering predicate
data NavigationPath : (ordering : Evidence -> Evidence -> Bool) -> Type where
  MkPath : (nodes : List Evidence) ->
           {auto prf : IsSorted ordering nodes} ->
           NavigationPath ordering

-- Type proves path is ordered
createSkepticPath : List Evidence -> NavigationPath (orderByObjective)
createSkepticPath evs = MkPath (sort orderByObjective evs) 
                               {prf = sortProducesSorted _ _}
```

**Benefits**:
- Type proves path satisfies ordering invariant
- Can't create invalid path (type error)
- Different audiences get different ordering proofs

## 4. Type System Design

### 4.1 Three-Tier Approach

**Tier 1: Refinement Types** (Month 1-6)
- Bounded integers: `BoundedNat 0 100`
- Non-null strings: `NonEmptyString`
- Bounded floats: `BoundedFloat 0.0 1.0`
- Pattern-matched enums

**Tier 2: Simple Dependent Types** (Month 7-12)
- Length-indexed arrays: `Vect n a`
- Computed fields with proofs
- Provenance-tracked values: `Tracked a`
- Type-safe edges: `Edge from to`

**Tier 3: Full Dependent Types** (Month 13-18)
- Reversibility proofs
- Belief fusion proofs
- Path ordering proofs
- Complex invariants

### 4.2 Core Type Definitions

#### **4.2.1 Bounded Types**

```idris
-- Bounded natural numbers
data BoundedNat : (min : Nat) -> (max : Nat) -> Type where
  MkBounded : (n : Nat) ->
              {auto prf : And (GTE n min) (LTE n max)} ->
              BoundedNat min max

-- Bounded floats
data BoundedFloat : (min : Double) -> (max : Double) -> Type where
  MkBoundedF : (f : Double) ->
               {auto prf : And (GTE f min) (LTE f max)} ->
               BoundedFloat min max

-- Type aliases for common ranges
PromptDimension : Type
PromptDimension = BoundedNat 0 100

Confidence : Type
Confidence = BoundedFloat 0.0 1.0

Percentage : Type
Percentage = BoundedFloat 0.0 100.0
```

#### **4.2.2 Non-Empty Strings**

```idris
-- Strings that can't be empty
data NonEmptyString : Type where
  MkNonEmpty : (s : String) ->
               {auto prf : GT (length s) 0} ->
               NonEmptyString

-- Use for rationale, actor names, etc.
Rationale : Type
Rationale = NonEmptyString

ActorId : Type
ActorId = NonEmptyString
```

#### **4.2.3 Provenance-Tracked Values**

```idris
-- Every value carries its provenance
data Tracked : Type -> Type where
  MkTracked :
    (value : a) ->
    (added_by : ActorId) ->
    (added_at : Timestamp) ->
    (rationale : Rationale) ->
    Tracked a

-- Extract value (provenance always available)
getValue : Tracked a -> a
getValue (MkTracked v _ _ _) = v

getProvenance : Tracked a -> (ActorId, Timestamp, Rationale)
getProvenance (MkTracked _ actor ts rat) = (actor, ts, rat)
```

#### **4.2.4 PROMPT Scores**

```idris
data PromptScores : Type where
  MkPromptScores :
    (provenance : PromptDimension) ->
    (replicability : PromptDimension) ->
    (objective : PromptDimension) ->
    (methodology : PromptDimension) ->
    (publication : PromptDimension) ->
    (transparency : PromptDimension) ->
    (overall : PromptDimension) ->
    {auto prf : overall = computeOverall provenance replicability 
                                         objective methodology 
                                         publication transparency} ->
    PromptScores

-- Proof that average is in bounds
computeOverall : PromptDimension -> PromptDimension -> PromptDimension ->
                 PromptDimension -> PromptDimension -> PromptDimension ->
                 PromptDimension
computeOverall (MkBounded p) (MkBounded r) (MkBounded o) 
               (MkBounded m) (MkBounded pub) (MkBounded t) =
  MkBounded ((p + r + o + m + pub + t) `div` 6)
    {prf = averagePreservesBounds p r o m pub t}

-- Theorem: Average of bounded values is bounded
averagePreservesBounds : (p, r, o, m, pub, t : Nat) ->
                         LTE p 100 -> LTE r 100 -> LTE o 100 ->
                         LTE m 100 -> LTE pub 100 -> LTE t 100 ->
                         LTE ((p + r + o + m + pub + t) `div` 6) 100
```

#### **4.2.5 Collections (Tables)**

```idris
-- Collection indexed by row type
data Collection : Type -> Type where
  MkCollection : (name : String) ->
                 (rows : List (Tracked a)) ->  -- All rows have provenance
                 Collection a

-- Type-safe insertion
insert : Collection a -> a -> ActorId -> Timestamp -> Rationale -> Collection a
insert (MkCollection name rows) value actor ts rat =
  MkCollection name (MkTracked value actor ts rat :: rows)

-- Type-safe query
query : Collection a -> (a -> Bool) -> List (Tracked a)
query (MkCollection _ rows) predicate = filter (predicate . getValue) rows
```

#### **4.2.6 Edge Collections**

```idris
-- Edges between specific types
data Edge : Type -> Type -> Type where
  MkEdge :
    (from : Tracked a) ->
    (to : Tracked b) ->
    (relationship_type : RelType) ->
    (weight : BoundedFloat 0.0 1.0) ->
    (reasoning : Rationale) ->
    Edge a b

-- Type-safe graph traversal
traverse : List (Edge a b) -> a -> List b
traverse edges start = 
  [getValue to | MkEdge from to _ _ _ <- edges, getValue from == start]
```

#### **4.2.7 Reversible Operations**

```idris
-- Operations with proven inverses
data ReversibleOp : Type -> Type where
  Insert : (data : Tracked a) ->
           (inverse : Delete a) ->
           {auto prf : composeInverses (insert data) (delete inverse) = id} ->
           ReversibleOp a
  
  Update : (old : Tracked a) ->
           (new : Tracked a) ->
           (inverse : Update a) ->
           {auto prf : composeInverses (update old new) inverse = 
                       update new old} ->
           ReversibleOp a
  
  Delete : (data : Tracked a) ->
           (inverse : Insert a) ->
           {auto prf : composeInverses (delete data) (insert inverse) = id} ->
           ReversibleOp a
  
  Irreversible : (data : Tracked a) ->
                 (reason : Rationale) ->
                 (justification : Why reason) ->  -- Proof of necessity
                 ReversibleOp a

-- Journal entry carries operation + proof
data JournalEntry : Type where
  MkEntry : (timestamp : Timestamp) ->
            (actor : ActorId) ->
            (operation : ReversibleOp a) ->
            JournalEntry
```

### 4.3 GQL Syntax Extensions

#### **4.3.1 Type Annotations**

```gql
-- Current GQL
CREATE COLLECTION evidence (
  prompt_scores STRUCT {
    provenance INT CHECK (provenance BETWEEN 0 AND 100)
  }
);

-- Extended GQL with dependent types
CREATE COLLECTION evidence (
  id : UUID,
  title : NonEmptyString,
  prompt_scores : PromptScores,  -- Type carries proofs!
  added : Tracked ()  -- Provenance automatically tracked
) WITH DEPENDENT_TYPES;
```

#### **4.3.2 Insertion with Proof Obligations**

```gql
-- Type checker generates proof obligations
INSERT INTO evidence (title, prompt_scores)
VALUES (
  'ONS CPI Data',
  {provenance: 100, replicability: 100, objective: 95,
   methodology: 95, publication: 100, transparency: 95}
)
RATIONALE "Official UK statistics";

-- Behind the scenes, type checker proves:
-- 1. All dimensions in [0, 100] ✓
-- 2. Overall computed correctly ✓
-- 3. Rationale non-empty ✓
-- 4. Operation reversible ✓
```

#### **4.3.3 Queries with Refinements**

```gql
-- Query with type refinement
SELECT * FROM evidence
WHERE prompt_scores.overall > 90
RETURNING (e : Evidence | e.prompt_scores.overall > 90);

-- Return type PROVES all results satisfy predicate
```

#### **4.3.4 Verified Updates**

```gql
-- Update with proof of correctness
UPDATE claims
SET text = 'New text',
    confidence = 0.95
WHERE id = 'claim_123'
REASON "ONS revised figures"
WITH_PROOF {
  new_confidence_justified: Proof,  -- Confidence matches evidence
  correction_documented: Proof,     -- Reason is non-empty
  reversible: Proof                 -- Inverse operation exists
};
```

## 5. Implementation Strategy

### 5.1 Architecture

```
┌──────────────────────────────────────────────────┐
│  GQL Source Code (with dependent type syntax)   │
└────────────────┬─────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────┐
│  Type Checker (Idris 2 or Lean 4)               │
│  • Infers types                                  │
│  • Checks proof obligations                      │
│  • Generates proofs (with tactics/automation)    │
│  • Emits errors if proofs fail                   │
└────────────────┬─────────────────────────────────┘
                 │ (if type-checks)
                 ▼
┌──────────────────────────────────────────────────┐
│  Code Generator                                  │
│  • Erases types (proof-erasure semantics)       │
│  • Generates GQL for Lithoglyph runtime              │
│  • Attaches proof objects to journal entries     │
└────────────────┬─────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────┐
│  Lithoglyph Runtime (Unchanged!)                     │
│  • Forth (Blocks)                                │
│  • Zig (Bridge)                                  │
│  • Factor (Runtime)                              │
│  • Elixir (ControlPlane)                         │
└──────────────────────────────────────────────────┘
```

### 5.2 Phase 1: External Type Checker (Month 1-6)

**Goal**: Opt-in type checking without changing Lithoglyph runtime.

**Implementation**:
1. **GQL Parser Extension**:
   ```elixir
   # Parse dependent type annotations
   defmodule GQL.Parser.DependentTypes do
     def parse_type_annotation(tokens) do
       # Parse: "x : BoundedNat 0 100"
       # Returns: {:bounded_nat, 0, 100}
     end
   end
   ```

2. **Type Checker (Idris 2)**:
   ```idris
   -- Lithoglyph.idr
   module Lithoglyph.TypeChecker
   
   import Lithoglyph.Core  -- Core type definitions
   
   -- Check GQL program
   checkProgram : String -> Either TypeError (Program, List Proof)
   checkProgram source = do
     ast <- parseGQL source
     (typedAST, proofs) <- inferTypes ast
     checkProofs proofs
     pure (typedAST, proofs)
   ```

3. **Integration Script**:
   ```bash
   #!/bin/bash
   # check_fql.sh
   
   # 1. Type check with Idris
   idris2 --check Lithoglyph.idr $1
   if [ $? -ne 0 ]; then
     echo "Type checking failed!"
     exit 1
   fi
   
   # 2. Generate runtime GQL
   idris2 --codegen gql Lithoglyph.idr $1 > output.gql
   
   # 3. Execute on Lithoglyph
   lithoglyph execute output.gql
   ```

**Usage**:
```bash
# Write GQL with types
cat > example.gql.idr
CREATE COLLECTION evidence (
  id : UUID,
  prompt_scores : PromptScores
);

INSERT INTO evidence VALUES (...);
^D

# Type check + execute
./check_fql.sh example.gql.idr
```

### 5.3 Phase 2: Proof-Carrying Code (Month 7-12)

**Goal**: Store proofs alongside data in journal.

**Journal Format**:
```forth
\ Forth journal entry with proof
: JOURNAL-ENTRY ( timestamp operation data rationale proof -- )
  CREATE-ENTRY
    , timestamp
    , operation-type
    , data-blob
    , rationale-string
    , proof-blob  \ NEW: Serialized Idris proof object
  ;
```

**Serialized Proof**:
```json
{
  "proof_type": "BoundedNatProof",
  "theorem": "LTE 95 100",
  "proof_term": "lteAddLeft 95 5 LTEZero",
  "verified_by": "Idris 2.0",
  "timestamp": "2024-01-15T10:00:00Z"
}
```

**Verification**:
```gql
-- Query with proof verification
SELECT * FROM evidence
WHERE prompt_scores.provenance = 100
[VERIFY_PROOFS];

-- Returns data + proof verification results
```

### 5.4 Phase 3: Verified Runtime (Month 13-24)

**Goal**: Replace critical paths with verified code.

**Approach**: Rewrite Zig bridge in Dafny or Lean:

```dafny
// Dafny: Verified bridge layer
method InsertWithProvenance(
  data: Data,
  actor: string,
  timestamp: int,
  rationale: string
) returns (result: Result<Entry>)
  requires |rationale| > 0  // Non-empty rationale
  requires timestamp > 0     // Valid timestamp
  ensures result.Success? ==> result.value.rationale == rationale
  ensures result.Success? ==> result.value.actor == actor
{
  // Implementation verified by Dafny
  var entry := Entry(data, actor, timestamp, rationale);
  return Success(entry);
}
```

**Compile to C** → Link with Forth/Zig → Verified bridge!

### 5.5 Tooling

#### **5.5.1 IDE Support**

**Lean 4 LSP** (best IDE support):
```
$ lean4 --server
# Provides:
# - Type checking on save
# - Proof assistance (tactics)
# - Error highlighting
# - Type-on-hover
```

**VSCode Extension**:
```json
{
  "name": "lithoglyph-dependent-types",
  "displayName": "Lithoglyph Dependent Types",
  "description": "Type checking for GQL with dependent types",
  "version": "0.1.0",
  "engines": { "vscode": "^1.80.0" },
  "contributes": {
    "languages": [
      { "id": "gql-dt", "extensions": [".gql.lean"] }
    ],
    "grammars": [
      { "language": "gql-dt", "scopeName": "source.gql.lean" }
    ]
  }
}
```

#### **5.5.2 Proof Tactics**

**Auto-solving Simple Proofs**:
```lean
-- Lean 4 tactics for Lithoglyph
def lithoglyph_bounds : Tactic :=
  -- Auto-solve bounded integer proofs
  try { norm_num } <|>
  try { omega } <|>
  sorry  -- User must provide proof

example : 95 ≤ 100 := by lithoglyph_bounds
-- Proven automatically!
```

#### **5.5.3 Error Messages**

**Current**:
```
ERROR: Check constraint "prompt_provenance_range" violated
DETAIL: Failing row contains (150).
```

**With Dependent Types**:
```
TYPE ERROR at line 5, column 12:

  INSERT INTO evidence (prompt_scores) VALUES ({provenance: 150, ...})
                                                            ^^^
Cannot construct PromptScores with provenance = 150

Expected: BoundedNat 0 100
Got: 150 (out of bounds)

Proof obligation: LTE 150 100
Failed: 150 > 100

Suggestion: Use a value between 0 and 100
```

Much clearer!

## 6. Synergy with My-Newsroom

### 6.1 Me Dialect Already Has Epistemic Types

**From My-Newsroom**:
```me
// Me dialect: Belief types
belief x: Float where confidence(0.75)
maybe y: Int where uncertainty(0.3)
```

**Map to Dependent Types**:
```idris
-- Lithoglyph dependent types for beliefs
data Belief : (confidence : BoundedFloat 0.0 1.0) -> Type -> Type where
  MkBelief : (value : a) ->
             (confidence : BoundedFloat 0.0 1.0) ->
             Belief confidence a

-- Extract value
getBelief : Belief c a -> a
getBelief (MkBelief v _) = v

-- Extract confidence
getConfidence : Belief c a -> BoundedFloat 0.0 1.0
getConfidence (MkBelief _ c) = c
```

### 6.2 Type-Safe Dempster-Shafer Fusion

**Current** (Julia, runtime):
```julia
# Julia: Runtime fusion
source_a = BeliefMass(Dict(Set(["true"]) => 0.85, θ => 0.15))
source_b = BeliefMass(Dict(Set(["true"]) => 0.60, θ => 0.40))
result = fuse_beliefs(source_a, source_b, Dempster)
```

**With Dependent Types**:
```idris
-- Type-safe belief fusion
fuseBeliefsDS : Belief c1 a -> Belief c2 a -> Belief (fuse c1 c2) a
fuseBeliefsDS (MkBelief v1 c1) (MkBelief v2 c2) =
  MkBelief (combineValues v1 v2) (dempsterFusion c1 c2)
    {prf = fusionPreservesBounds c1 c2}

-- Proof that fusion preserves confidence bounds
fusionPreservesBounds : (c1, c2 : BoundedFloat 0.0 1.0) ->
                        BoundedFloat 0.0 1.0 (dempsterFusion c1 c2)
```

**Benefits**:
- Type system ensures fusion is valid
- Proof that result confidence is in [0.0, 1.0]
- Agent can check types before executing

### 6.3 Agent Introspection with Proofs

**Current**:
```gql
-- Agent queries its reasoning
INTROSPECT belief_fusions
WHERE agent = 'agent_alpha'
RETURN reasoning;
```

**With Dependent Types**:
```gql
-- Agent verifies its reasoning
INTROSPECT belief_fusions
WHERE agent = 'agent_alpha'
RETURN (reasoning, proof)
[VERIFY_PROOFS];

-- Returns:
-- [
--   {
--     reasoning: "Fused Reuters (0.85) + AP (0.78) → 0.82",
--     proof: DempsterFusionProof {
--       inputs: [(0.85, Reuters), (0.78, AP)],
--       output: 0.82,
--       theorem: "fusionValid 0.85 0.78 = 0.82",
--       verified: true
--     }
--   }
-- ]
```

**Agent Beta** can now **verify Agent Alpha's proofs** before trusting them!

### 6.4 Byzantine Fault Tolerance with Proofs

**Current**: 33% malicious agents tolerated (voting)

**With Dependent Types**: Agents provide **proofs** of their reasoning

```idris
-- Agent claim with proof
data VerifiedClaim : Type where
  MkVerifiedClaim :
    (claim : String) ->
    (confidence : Confidence) ->
    (evidence : List Evidence) ->
    {auto prf : confidenceMatchesEvidence claim evidence confidence} ->
    VerifiedClaim

-- Orchestrator verifies all proofs
verifyAgentClaims : List (Agent, VerifiedClaim) -> 
                    Either ProofError (List VerifiedClaim)
verifyAgentClaims claims = do
  -- Check each proof
  for claims $ \(agent, claim) -> do
    verify claim.prf
  pure (map snd claims)
```

**Benefits**:
- Malicious agents can't fake proofs (type system enforces)
- Honest agents' proofs always verify
- Higher fault tolerance (50%+ malicious if proofs required)

## 7. Research Contributions

### 7.1 Novel Contributions

1. **First dependently-typed database**
   - Databases: None have dependent types (to our knowledge)
   - Programming languages: Many (Idris, Agda, Lean, Coq, F*)
   - **Gap**: Database + dependent types = novel!

2. **Provable epistemology**
   - Traditional: "This claim has confidence 0.9" (no proof)
   - Lithoglyph: "This claim has confidence 0.9 AND here's a proof it's justified"
   - **Impact**: Trust is verifiable, not just asserted

3. **Type-safe multi-agent systems**
   - Traditional: Agents share unverified beliefs
   - Lithoglyph: Agents share beliefs + proofs
   - **Impact**: Byzantine resilience via proof verification

4. **Proof-carrying provenance**
   - Traditional: Provenance is metadata (can be forged)
   - Lithoglyph: Provenance is part of type (can't be forged)
   - **Impact**: Cryptographic-strength audit trails

### 7.2 Publications

#### **Paper 1: POPL 2027 (Programming Languages)**
**Title**: "Lithoglyph: A Dependently-Typed Database for Verified Epistemology"
- Core type system
- Proof-erasure semantics
- Idris/Lean integration
- **Venue**: Symposium on Principles of Programming Languages (top-tier PL)

#### **Paper 2: VLDB 2027 (Databases)**
**Title**: "Dependent Types for Database Constraints: A Case Study in Journalism"
- BoFIG case study (UK Inflation 2023 dataset)
- PROMPT score verification
- Performance evaluation (type-checking overhead)
- **Venue**: Very Large Data Bases (top-tier DB)

#### **Paper 3: ICFP 2027 (Functional Programming)**
**Title**: "Proof-Carrying Provenance: Dependent Types for Audit Trails"
- Reversibility proofs
- Journal encoding with proof objects
- Verification strategies
- **Venue**: International Conference on Functional Programming

#### **Paper 4: AAMAS 2027 (Multi-Agent Systems)**
**Title**: "Verified Belief Fusion: Dependent Types for Multi-Agent Epistemology"
- My-Newsroom integration
- Type-safe Dempster-Shafer fusion
- Byzantine resilience with proofs
- **Venue**: Autonomous Agents and Multiagent Systems

### 7.3 Comparison to Related Work

| System | Types | Proofs | Provenance | Domain |
|--------|-------|--------|------------|--------|
| Lithoglyph (ours) | ✓ Dependent | ✓ Machine-checkable | ✓ Type-level | Journalism/i-docs |
| Datomic | Simple | ✗ | ✓ Time-based | General |
| XTDB | Simple | ✗ | ✓ Bitemporal | General |
| Prisma | Simple | ✗ | ✗ | General |
| Liquid Haskell | ✓ Refinement | ✓ SMT-based | ✗ | Programming |
| F* | ✓ Dependent | ✓ SMT + Tactics | ✗ | Programming |
| Agda | ✓ Dependent | ✓ Interactive | ✗ | Mathematics |

**Key Insight**: Lithoglyph combines database + dependent types + provenance = **unique position**.

## 8. Evaluation

### 8.1 Type-Checking Performance

**Benchmark**: UK Inflation 2023 dataset (BoFIG)
- 7 claims
- 10 evidence items
- 10 relationships
- 3 navigation paths

**Metrics**:
- Type-checking time per operation
- Proof generation time
- Memory overhead
- Journal size increase (with proofs)

**Expected Results**:
- Type-checking: <100ms per operation (acceptable for development)
- Proof generation: <500ms (one-time cost)
- Memory: +10-20% (proof objects)
- Journal size: +5-10% (serialized proofs)

### 8.2 Error Detection

**Compare**:
- Runtime errors caught with traditional GQL
- Type errors caught with dependent types

**Hypothesis**: Dependent types catch 80%+ of errors at compile time.

**Methodology**:
- Seed dataset with 100 intentional errors:
  - Invalid PROMPT scores (20)
  - Missing rationale (20)
  - Invalid confidence levels (20)
  - Incorrect computed fields (20)
  - Invalid reversibility claims (20)
- Measure: How many caught at type-check vs. runtime?

### 8.3 Developer Experience

**User Study**:
- 20 developers (10 Lithoglyph users, 10 control)
- Task: Implement evidence import from Zotero
- Measure:
  - Time to completion
  - Number of bugs
  - User satisfaction (Likert scale)

**Hypothesis**: Dependent types reduce bugs by 50%, with 20% time overhead.

### 8.4 Agent Integration

**Experiment**:
- 10-agent My-Newsroom system
- Task: Verify 50 claims from UK Inflation investigation
- Compare:
  - Without proofs: Agents vote (Byzantine voting)
  - With proofs: Agents verify proofs (proof-checking)

**Metrics**:
- Consensus time
- Accuracy (vs. ground truth)
- Byzantine resilience (% malicious agents tolerated)

**Hypothesis**: Proof-checking enables 50% malicious tolerance (vs. 33% with voting).

## 9. Challenges and Mitigations

### 9.1 Challenge: Learning Curve

**Problem**: Dependent types are hard for most developers.

**Mitigations**:
1. **Gradual adoption**: Start with refinement types (easier)
2. **IDE support**: Lean 4 LSP provides excellent autocomplete
3. **Proof tactics**: Automate 80% of proofs
4. **Documentation**: Extensive examples, tutorials
5. **Opt-in**: Can use simple types if needed

### 9.2 Challenge: Compilation Time

**Problem**: Proof checking is slow (can be minutes for complex proofs).

**Mitigations**:
1. **Caching**: Store proofs, don't recheck
2. **Incremental checking**: Only check changed proofs
3. **Proof parallelization**: Check proofs in parallel
4. **Development mode**: Skip proofs during dev, check on commit
5. **Proof complexity budgets**: Warn if proof too complex

### 9.3 Challenge: Proof Obligation Failures

**Problem**: Users write code, type checker demands proof, user stuck.

**Mitigations**:
1. **Proof search**: Auto-generate simple proofs (e.g., `omega` tactic)
2. **Partial proofs**: Allow `admit` during development
3. **Proof assistants**: Provide tactics for common patterns
4. **Error messages**: Suggest fixes (e.g., "Try reducing value from 150 to 100")
5. **Proof libraries**: Pre-proved theorems for common cases

### 9.4 Challenge: Runtime Performance

**Problem**: Proof objects increase journal size.

**Mitigations**:
1. **Proof erasure**: Erase proofs at runtime (Idris/Lean support this)
2. **Optional proofs**: Only store proofs for critical operations
3. **Proof compression**: Serialize proofs efficiently
4. **Proof summaries**: Store hash instead of full proof
5. **Proof generation on demand**: Regenerate proofs from code if needed

## 10. Future Work

### 10.1 Full Verification Stack

**Goal**: End-to-end verified database.

```
┌──────────────────────────────┐
│  GQL (Lean 4)                │  ← Application code (verified)
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│  Factor Runtime (Lean)       │  ← Runtime (verified)
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│  Zig Bridge (Dafny)          │  ← Bridge (verified)
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│  Forth Model (Coq)           │  ← Query engine (verified)
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│  Forth Blocks (Coq)          │  ← Storage (verified)
└──────────────────────────────┘
```

**Impact**: **Fully verified database** from top to bottom!

### 10.2 Proof-Checked Journalism

**Vision**: Journalists publish **proofs** alongside articles.

**Example**:
> **Claim**: "UK rent inflation exceeded overall inflation by 4.7 percentage points in 2023"
>
> **Evidence**: ONS CPI data (provenance: 100, replicability: 100)
>
> **Proof**: [Download machine-checkable proof]
>
> Readers can verify the proof in Lean 4 or Idris 2. The claim is **mathematically guaranteed** to follow from the evidence.

**Impact**: **Verifiable journalism** - trust is provable, not asserted!

### 10.3 LLM Agents with Proof Obligations

**Current**: LLM agents hallucinate, make mistakes.

**With Dependent Types**: LLM generates code + proofs.

```
User: "Add evidence with PROMPT score 95/100"

LLM generates:
INSERT INTO evidence (prompt_scores)
VALUES ({provenance: 95, replicability: 95, ..., overall: 95})
RATIONALE "User requested"
WITH_PROOF {
  scores_in_range: ✓ (auto-generated)
  overall_correct: ✓ (auto-generated)
  rationale_nonempty: ✓ (auto-generated)
};

Type checker: ✓ All proofs valid
Lithoglyph: Execute
```

**If LLM hallucinates invalid score**:
```
LLM generates:
INSERT INTO evidence (prompt_scores)
VALUES ({provenance: 150, ...})  -- Invalid!

Type checker: ✗ TYPE ERROR
Cannot prove LTE 150 100

LLM: "Sorry, 150 is out of range. Let me fix that..."
```

**Impact**: **Hallucination-proof LLMs** via type checking!

### 10.4 Proof-Carrying Smart Contracts

**Blockchain + Dependent Types**:
```idris
-- Smart contract with proofs
contract TransferFunds : Contract where
  transfer : (from : Address) -> (to : Address) -> (amount : Nat) ->
             {auto prf : HasBalance from amount} ->
             {auto prf : IsValid to} ->
             Transaction

-- Blockchain verifies proofs before executing
```

**Impact**: **Mathematically verified smart contracts** - no exploits!

## 11. Conclusion

Dependent types transform Lithoglyph from a database that **records** epistemology to one that **proves** epistemology. This enables:

1. **Compile-time correctness**: Invalid data is a type error, caught immediately
2. **Provable provenance**: Can't forge provenance (it's in the type)
3. **Verified multi-agent systems**: Agents provide proofs, not just assertions
4. **Hallucination-proof LLMs**: Type checker catches LLM mistakes
5. **Verifiable journalism**: Readers can verify claims mathematically

Our approach is incremental (refinement types → full dependent types → verified stack), making it practical for real-world adoption.

Lithoglyph becomes the **first dependently-typed database**, uniquely positioned for journalism, scientific reproducibility, and AI agent collaboration where **correctness is non-negotiable**.

---

## Appendix A: Idris 2 Primer

### A.1 Basic Syntax

```idris
-- Data types
data Nat : Type where
  Z : Nat              -- Zero
  S : Nat -> Nat       -- Successor

-- Functions
plus : Nat -> Nat -> Nat
plus Z     m = m
plus (S k) m = S (plus k m)

-- Dependent types
data Vect : Nat -> Type -> Type where
  Nil  : Vect Z a
  (::) : a -> Vect n a -> Vect (S n) a

-- Proofs
plusZeroRightNeutral : (n : Nat) -> n + 0 = n
plusZeroRightNeutral Z     = Refl
plusZeroRightNeutral (S k) = cong S (plusZeroRightNeutral k)
```

### A.2 Tactics

```idris
-- Proof with tactics
example : (x : Nat) -> (y : Nat) -> x + y = y + x
example x y = ?proof

-- Fill ?proof with tactics
?proof = rewrite plusCommutative x y in Refl
```

### A.3 Auto-Implicit Arguments

```idris
-- Auto-solve proofs
data BoundedNat : Nat -> Nat -> Type where
  MkBounded : (n : Nat) -> {auto prf : LTE n max} -> BoundedNat min max

-- Usage: compiler finds proof automatically
x : BoundedNat 0 100
x = MkBounded 50  -- {prf = ...} filled in by compiler
```

---

## Appendix B: Lean 4 Primer

### B.1 Basic Syntax

```lean
-- Inductive types
inductive Nat where
  | zero : Nat
  | succ : Nat → Nat

-- Functions
def plus : Nat → Nat → Nat
  | .zero,   m => m
  | .succ k, m => .succ (plus k m)

-- Dependent types
inductive Vector (α : Type u) : Nat → Type u where
  | nil  : Vector α 0
  | cons : α → Vector α n → Vector α (n + 1)

-- Theorems
theorem plus_zero : ∀ n : Nat, n + 0 = n := by
  intro n
  induction n with
  | zero => rfl
  | succ k ih => simp [plus]; exact ih
```

### B.2 Tactics

```lean
-- Proof by tactics
theorem example : ∀ x y : Nat, x + y = y + x := by
  intro x y
  rw [Nat.add_comm]
```

### B.3 Type Classes

```lean
-- Type class for bounded values
class Bounded (α : Type u) where
  min : α
  max : α
  inBounds : α → Bool

instance : Bounded Nat where
  min := 0
  max := 100
  inBounds n := n ≤ 100
```

---

## Appendix C: Comparison Matrix

| Feature | Idris 2 | Lean 4 | Dafny | Coq |
|---------|---------|--------|-------|-----|
| Dependent types | ✓ Full | ✓ Full | ✓ Refinement | ✓ Full |
| Proof automation | ✓ Good | ✓ Excellent | ✓ SMT | ✓ Tactics |
| LSP support | ✓ | ✓ Excellent | ✓ | ✓ |
| Compilation to C | ✓ | ✓ (LLVM) | ✗ | ✓ (via Extraction) |
| Learning curve | Medium | Medium | Low | High |
| IDE integration | Good | Excellent | Good | Good |
| Proof libraries | Medium | Large | Large | Very Large |

**Recommendation**: **Lean 4** for best IDE support and automation. **Idris 2** for simplicity. **Dafny** for C interop.

---

**Document Status**: Research proposal. Implementation timeline: 18-24 months.

**See Also**:
- GQL Dependent Types Specification (companion document)
- Lithoglyph arXiv paper (Section 14: Future Work)
- My-Newsroom Me dialect specification
