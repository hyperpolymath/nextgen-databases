# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# KRL Type System Specification

**Version:** 0.1.0
**Date:** 2026-03-14

---

## 1. Type Language

```
τ ::= Int | Float | String | Bool                   scalars
    | Knot                                          knot record
    | Diagram                                       knot diagram
    | Polynomial                                    Laurent polynomial
    | GaussCode                                     Gauss code encoding
    | Quandle                                       algebraic quandle
    | Option[τ]                                     nullable
    | List[τ]                                       ordered collection
    | Set[τ]                                        unordered unique collection
    | Map[τ₁, τ₂]                                   key-value mapping
    | (τ₁, …, τₙ)                                   tuple
    | {f₁: τ₁, …, fₙ: τₙ}                          record
    | Equivalence[τ]                                space of equivalences
    | Provenance                                    provenance annotation
    | ResultSet[τ]                                  query result (ordered set of records)
    | α                                             type variable
```

---

## 2. Knot Record Type

The `Knot` type is a fixed record:

```
Knot = {
  name             : String,
  gauss_code       : GaussCode,
  crossing_number  : Int,
  writhe           : Int,
  genus            : Option[Int],
  seifert_circles  : Option[Int],
  jones_polynomial : Option[Polynomial],
  metadata         : Map[String, String]
}
```

Fields with `Option[τ]` may not be computed for all knots.

---

## 3. Equivalence Types (HoTT-Inspired)

### 3.1 Identity Type

KRL's distinguishing feature is that equivalence queries return *types*, not
booleans. The identity type `Equivalence[τ]` represents the space of paths
between two values of type `τ`:

```
Equivalence[Knot] = {
  source    : Knot,
  target    : Knot,
  paths     : List[EquivalencePath],
  provenance: Provenance
}

EquivalencePath = {
  method      : InvariantName,
  confidence  : Confidence,
  evidence    : Value
}

Confidence = Exact | Necessary | Sufficient | Heuristic
```

### 3.2 Typing Rules for Equivalence

```
    Γ ⊢ e₁ : Knot     Γ ⊢ e₂ : Knot
    ───────────────────────────────────────────────  [T-Equiv-Query]
    Γ ⊢ find_equivalent e₁ via [invs] : ResultSet[Equivalence[Knot]]

    Γ ⊢ e₁ : Diagram     Γ ⊢ e₂ : Diagram
    ──────────────────────────────────────────────────────  [T-Path-Query]
    Γ ⊢ find_path e₁ ~> e₂ via reidemeister : ResultSet[{path: List[Move], move_count: Int}]
```

---

## 4. Pipeline Type System

Each pipeline stage transforms the type of the result set:

```
    Γ ⊢ from knots : ResultSet[Knot]

    Γ ⊢ R : ResultSet[τ]     Γ, x: τ ⊢ expr : Bool
    ─────────────────────────────────────────────────────  [T-Filter]
    Γ ⊢ R | filter expr : ResultSet[τ]

    Γ ⊢ R : ResultSet[τ]     Γ, x: τ ⊢ expr : Ord
    ─────────────────────────────────────────────────────  [T-Sort]
    Γ ⊢ R | sort expr : ResultSet[τ]

    Γ ⊢ R : ResultSet[τ]
    ─────────────────────────────────────  [T-Take]
    Γ ⊢ R | take n : ResultSet[τ]

    Γ ⊢ R : ResultSet[τ]     fields ⊆ fields(τ)
    project(τ, fields) = τ'
    ──────────────────────────────────────────────  [T-Return]
    Γ ⊢ R | return fields : ResultSet[τ']

    Γ ⊢ R : ResultSet[τ]
    ──────────────────────────────────────────────────────  [T-Return-Provenance]
    Γ ⊢ R | return fields with provenance : ResultSet[τ' ∪ {_provenance: Provenance}]

    Γ ⊢ R : ResultSet[τ]     Γ ⊢ expr : τ₂
    ──────────────────────────────────────────  [T-Let]
    Γ ⊢ R | let x = expr : ResultSet[τ]     (x: τ₂ added to Γ)

    Γ ⊢ R : ResultSet[τ]     Γ, x: τ ⊢ key : κ
    Γ, x: τ ⊢ agg(expr) : τ_agg
    ──────────────────────────────────────────────────────  [T-GroupAgg]
    Γ ⊢ R | group_by key | aggregate agg(expr) : ResultSet[{key: κ, agg: τ_agg}]
```

---

## 5. Expression Types

```
    ──────────────────  [T-IntLit]       ──────────────────  [T-FloatLit]
    Γ ⊢ n : Int                         Γ ⊢ f : Float

    ──────────────────  [T-StringLit]    ──────────────────  [T-BoolLit]
    Γ ⊢ s : String                      Γ ⊢ b : Bool

    (x : τ) ∈ Γ
    ──────────────────  [T-Var]
    Γ ⊢ x : τ

    Γ ⊢ e : {…, f: τ, …}
    ──────────────────────  [T-Field]
    Γ ⊢ e.f : τ

    Γ ⊢ e₁ : Int     Γ ⊢ e₂ : Int
    ────────────────────────────────  [T-Arith-Int]
    Γ ⊢ e₁ ⊕ e₂ : Int               (for ⊕ ∈ {+, -, *, /, %})

    Γ ⊢ e₁ : τ     Γ ⊢ e₂ : τ     τ ∈ {Int, Float, String}
    ──────────────────────────────────────────────────────────  [T-Compare]
    Γ ⊢ e₁ ⊕ e₂ : Bool             (for ⊕ ∈ {==, !=, <, <=, >, >=})

    Γ ⊢ e₁ : Bool     Γ ⊢ e₂ : Bool
    ──────────────────────────────────  [T-Logic]
    Γ ⊢ e₁ ⊕ e₂ : Bool             (for ⊕ ∈ {and, or})

    Γ ⊢ e : Bool
    ──────────────────  [T-Not]
    Γ ⊢ not e : Bool

    ∀i. Γ ⊢ eᵢ : τ
    ────────────────────────────  [T-Array]
    Γ ⊢ [e₁, …, eₙ] : List[τ]

    ∀i. Γ ⊢ eᵢ : Int
    ────────────────────────────────────────  [T-Gauss]
    Γ ⊢ gauss(e₁, …, eₙ) : GaussCode
```

---

## 6. Rule Types

```
    ∀param ∈ params: param : Knot
    ∀clause ∈ body: well-typed predicate or guard
    ────────────────────────────────────────────  [T-Rule]
    Γ ⊢ rule name(params) :- body : Rule
```

Rules extend the e-graph. Type checking ensures all predicate arguments
are of the correct type (e.g., `jones_polynomial(K, J)` requires `K: Knot`
and `J: Polynomial`).

---

## 7. Axiom Types

```
    Γ, params ⊢ premise : Bool     Γ, params ⊢ conclusion : Bool
    ──────────────────────────────────────────────────────────────  [T-Axiom]
    Γ ⊢ axiom name : forall params, premise -> conclusion
```

Axioms are trusted declarations used by the equivalence engine. They are
not verified by the type checker but are type-checked for well-formedness.

---

## 8. Properties

1. **Pipeline type preservation:** Each stage produces a well-typed ResultSet.
2. **Field access safety:** Projecting fields not in the record is a type error.
3. **Equivalence type richness:** Equivalence results carry structured evidence,
   not just boolean matches.
4. **Provenance compositionality:** Combining results preserves provenance
   (semiring structure).
5. **Invariant type safety:** Each invariant function has a declared return type;
   comparisons are type-checked.
