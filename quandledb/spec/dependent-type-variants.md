# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# KRL Dependent Type Variants

**Version:** 0.1.0
**Date:** 2026-03-20

---

## 1. Overview

KRL's type system goes beyond conventional query language types (SQL's
scalar types, GraphQL's object types) by incorporating **dependent types**
— types that depend on values. This enables:

1. **Pipeline type safety:** The type of a query result depends on which
   stages appear in the pipeline (dependent projection).
2. **Confidence-indexed results:** The type of an equivalence result
   depends on the confidence level achieved during evaluation.
3. **Invariant-dependent records:** The fields available in a result
   depend on which invariants were requested.
4. **Stratum-bounded evaluation:** The evaluation strategy is indexed by
   the number of invariant strata, proving termination.

This document specifies how these dependent types surface in the KRL
language and how they map to Idris2 ABI proofs.

---

## 2. Dependent Projection (Pipeline Type Refinement)

### 2.1 The Problem

In SQL, `SELECT a, b FROM t` always produces a two-column result, but
the schema of the result is only checked at planning time — not at the
type level. In KRL, the `return` clause is a **dependent projection**:
the return type is computed from the fields listed.

### 2.2 Typing Rule

```
    Γ ⊢ R : ResultSet[τ]     fields ⊆ fields(τ)
    Π(τ, fields) = τ'
    ──────────────────────────────────────────────  [T-Dep-Return]
    Γ ⊢ R | return fields : ResultSet[τ']
```

Here, `Π(τ, fields)` is a **type-level function** that computes the
projected record type. This is a dependent type: the output type depends
on the value `fields`.

### 2.3 Idris2 ABI Proof

```idris
-- Pipeline type refinement: projection preserves well-formedness
data Project : (fields : List String) -> KqlTy -> KqlTy -> Type where
  ProjectNil  : Project [] (TyRecord fs) (TyRecord [])
  ProjectCons : Elem (f, t) fs -> Project rest (TyRecord fs) (TyRecord fs')
             -> Project (f :: rest) (TyRecord fs) (TyRecord ((f, t) :: fs'))
```

This proves that projecting a list of field names from a record type
produces a valid sub-record type, and each projected field must exist
in the source record (via `Elem` proof).

### 2.4 User-Facing Syntax

```krl
-- The return clause determines the result type
from knots
| return name, crossing_number
-- Type: ResultSet[{name: String, crossing_number: Int}]

from knots
| return name, jones_polynomial
-- Type: ResultSet[{name: String, jones_polynomial: Option[Polynomial]}]

-- Type error: field 'foobar' not in Knot record
from knots
| return name, foobar
-- Error: Field 'foobar' not found in record type Knot
```

---

## 3. Confidence-Indexed Equivalence Types

### 3.1 The Problem

When KRL reports that two knots are equivalent, the strength of that
claim depends on which invariants were used. Jones polynomial matching
is *necessary* but not *sufficient*; quandle isomorphism is *exact*.
The type of the result should reflect this.

### 3.2 Type Variants

```
Equivalence[τ, c] where c : Confidence

-- Four variants, indexed by confidence level:
Equivalence[Knot, Exact]      -- proven by complete invariant
Equivalence[Knot, Sufficient] -- proven by sufficient invariant combination
Equivalence[Knot, Necessary]  -- all necessary conditions met, not proven
Equivalence[Knot, Heuristic]  -- statistical match only
```

### 3.3 Typing Rules

```
    Γ ⊢ R : ResultSet[Knot]     inv ∈ exact_invariants
    ─────────────────────────────────────────────────────────────  [T-Equiv-Exact]
    Γ ⊢ R | find_equivalent K via [inv] : ResultSet[Equivalence[Knot, Exact]]

    Γ ⊢ R : ResultSet[Knot]     inv ∈ necessary_invariants
    ─────────────────────────────────────────────────────────────  [T-Equiv-Necessary]
    Γ ⊢ R | find_equivalent K via [inv] : ResultSet[Equivalence[Knot, Necessary]]

    Γ ⊢ R : ResultSet[Knot]     confidence >= c requested
    ─────────────────────────────────────────────────────────────  [T-Equiv-Threshold]
    Γ ⊢ R | find_equivalent K via [invs] confidence >= c
        : ResultSet[Equivalence[Knot, c]]
```

### 3.4 Idris2 ABI Proof

```idris
-- Confidence-indexed equivalence type
data ConfEquiv : KqlTy -> Confidence -> Type where
  MkConfEquiv : (source : Knot) -> (target : Knot)
             -> (paths : List EquivPath)
             -> (conf : Confidence)
             -> ConfLeq c conf    -- proof that achieved confidence >= requested
             -> ConfEquiv TyKnot c

-- Combining two equivalence results: confidence is the minimum
combineConf : ConfEquiv t c1 -> ConfEquiv t c2 -> ConfEquiv t (MinConf c1 c2)
```

### 3.5 User-Facing Syntax

```krl
-- Request only exact results
from knots
| find_equivalent "3_1" via [quandle] confidence >= exact
-- Type: ResultSet[Equivalence[Knot, Exact]]

-- Accept necessary-level results (faster, less certain)
from knots
| find_equivalent "3_1" via [jones, genus] confidence >= necessary
-- Type: ResultSet[Equivalence[Knot, Necessary]]

-- Default: accept any confidence
from knots
| find_equivalent "3_1" via [jones]
-- Type: ResultSet[Equivalence[Knot, Heuristic]]
```

---

## 4. Invariant-Dependent Records

### 4.1 The Problem

Different invariants produce different types:
- `crossing_number` produces `Int`
- `jones_polynomial` produces `Polynomial`
- `quandle` produces `Quandle`

When a query requests specific invariants, the result type should
reflect exactly which fields are available.

### 4.2 Type-Level Invariant Registry

```
InvariantType : InvariantName -> KqlTy

InvariantType "crossing_number"  = TyInt
InvariantType "writhe"           = TyInt
InvariantType "genus"            = TyOption TyInt
InvariantType "jones_polynomial" = TyOption TyPolynomial
InvariantType "quandle"          = TyOption TyQuandle
```

### 4.3 Dependent Via Clause

```krl
-- The 'via' clause determines which invariant fields appear in results
from knots
| find_equivalent "3_1" via [jones, genus]
| return equivalences with provenance
-- Each equivalence path carries:
--   {method: "jones", evidence: Polynomial, confidence: Necessary}
--   {method: "genus", evidence: Option[Int], confidence: Necessary}
```

### 4.4 Idris2 ABI

```idris
-- Type-level invariant registry
InvType : String -> KqlTy
InvType "crossing_number" = TyInt
InvType "writhe"          = TyInt
InvType "genus"           = TyOption (TyInt)
InvType "jones"           = TyOption TyPolynomial
InvType "quandle"         = TyOption TyQuandle

-- Dependent via clause: each invariant name determines the evidence type
data ViaClause : List String -> Type where
  ViaNil  : ViaClause []
  ViaCons : (inv : String) -> ViaClause rest
         -> ViaClause (inv :: rest)

-- Result type depends on the via clause
ViaResultType : ViaClause invs -> KqlTy
```

---

## 5. Stratum-Bounded Evaluation

### 5.1 The Problem

KRL's equivalence queries evaluate invariants in order of increasing
cost (crossing number is cheap; quandle isomorphism is expensive).
The type system must guarantee that evaluation terminates.

### 5.2 Stratified Evaluation Type

```idris
-- Evaluation indexed by stratum count
data StratEval : (n : Nat) -> Type where
  EvalDone : StratEval 0
  EvalStep : (stratum : Stratum)
          -> (result : Either ShortCircuit Provenance)
          -> StratEval n
          -> StratEval (S n)
```

This is a dependent type: the evaluation trace has type `StratEval n`
where `n` is the number of strata. Since `n : Nat` is finite and each
step strictly decreases it, evaluation is provably terminating.

### 5.3 Termination Proof

```idris
-- Stratified evaluation terminates: each step reduces the stratum count
stratTerminates : (n : Nat) -> StratEval n -> Nat
stratTerminates 0 EvalDone = 0
stratTerminates (S k) (EvalStep _ _ rest) = S (stratTerminates k rest)

-- The number of steps equals the number of strata
stratStepCount : (n : Nat) -> (eval : StratEval n) -> stratTerminates n eval = n
stratStepCount 0 EvalDone = Refl
stratStepCount (S k) (EvalStep _ _ rest) = cong S (stratStepCount k rest)
```

---

## 6. Dependent Type Variant Summary

| Variant | Depends On | Proves | User Syntax |
|---------|-----------|--------|-------------|
| **Dependent Projection** | Field names in `return` clause | Result record matches requested fields | `return name, x` |
| **Confidence-Indexed Equiv** | Confidence level in `confidence >=` | Result confidence meets threshold | `confidence >= exact` |
| **Invariant-Dependent Records** | Invariant names in `via` clause | Evidence types match invariant types | `via [jones, genus]` |
| **Stratum-Bounded Eval** | Number of invariant strata | Evaluation terminates | (implicit) |
| **Pipeline Composition** | Sequence of pipeline stages | Each stage preserves ResultSet type | `| stage1 | stage2` |

---

## 7. Relationship to Idris2 ABI

All dependent type variants have corresponding Idris2 proofs in
`src/abi/Types.idr`. The ABI layer provides:

1. **Type definitions** (`KqlTy`, `PipeStage`, `Pipeline`, `Confidence`)
2. **Proofs** (`pipeAssoc`, `combinePreservesInvariants`, `StratumBounded`)
3. **Translation** — each KRL type variant maps to an Idris2 type that
   can be type-checked at compile time

The SQL compatibility layer (§sql-compat.md) translates SQL queries into
KRL AST nodes, which are then type-checked against these dependent types.
SQL queries that would produce ill-typed results (e.g., projecting a
non-existent field) are rejected at translation time.
