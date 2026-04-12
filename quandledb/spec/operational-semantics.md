# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# KRL Operational Semantics

**Version:** 0.1.0
**Date:** 2026-03-14

---

## 1. Notation

- `D` — Database state (knot store, invariant cache, e-graph)
- `ρ` — Query environment (bound variables)
- `D, ρ ⊢ q ⇓ R` — Query `q` evaluates to result set `R`
- `⊥` — Error

---

## 2. Values

```
v ∈ Value ::=
    n ∈ ℤ                                    integer
  | f ∈ ℝ                                    float
  | s ∈ String                               string
  | b ∈ {true, false}                        boolean
  | K ∈ Knot                                 knot record
  | D ∈ Diagram                              knot diagram
  | P ∈ Polynomial                           Laurent polynomial
  | G ∈ GaussCode                            Gauss code
  | Q ∈ Quandle                              algebraic quandle
  | [v₁, …, vₙ]                              array
  | {f₁: v₁, …, fₙ: vₙ}                     record
  | Equiv(K₁, K₂, paths)                     equivalence evidence
  | Provenance(invariants, confidence, cost)  provenance annotation
```

### 2.1 Knot Record

```
Knot = ⟨ name             : String,
         gauss_code       : GaussCode,
         crossing_number  : ℕ,
         writhe           : ℤ,
         genus            : Option<ℕ>,
         seifert_circles  : Option<ℕ>,
         jones_polynomial : Option<Polynomial>,
         metadata         : Map<String, String> ⟩
```

---

## 3. Database State

```
D = ⟨ knots      : Set<Knot>,
      invariants : Knot → InvariantName → Option<Value>,
      egraph     : EGraph,
      rules      : List<Rule> ⟩

EGraph = equivalence classes over Knot, saturated by rules
```

---

## 4. Pipeline Semantics

KRL queries are pipelines: each stage transforms a result set.

```
    D, ρ ⊢ from_clause ⇓ R₀
    D, ρ ⊢ stage₁(R₀) ⇓ R₁
    …
    D, ρ ⊢ stageₙ(Rₙ₋₁) ⇓ Rₙ
    ──────────────────────────────────────────────  [Pipeline]
    D, ρ ⊢ from … | stage₁ | … | stageₙ ⇓ Rₙ
```

### 4.1 From

```
    ────────────────────────────────  [From-Knots]
    D, ρ ⊢ from knots ⇓ D.knots

    ────────────────────────────────  [From-Diagrams]
    D, ρ ⊢ from diagrams ⇓ D.diagrams

    D, ρ ⊢ q ⇓ R
    ────────────────────────────────  [From-Subquery]
    D, ρ ⊢ from (q) ⇓ R
```

### 4.2 Filter

```
    ∀k ∈ R: ρ[k], D ⊢ expr ⇓ bₖ
    R' = { k ∈ R | truthy(bₖ) }
    ──────────────────────────────────  [Filter]
    D, ρ ⊢ filter expr (R) ⇓ R'
```

### 4.3 Sort

```
    R' = sort R by (λk. ρ[k], D ⊢ expr ⇓ vₖ) [asc|desc]
    ──────────────────────────────────────────────────────  [Sort]
    D, ρ ⊢ sort expr [asc|desc] (R) ⇓ R'
```

### 4.4 Take / Skip

```
    R' = R[0..n]
    ────────────────────────  [Take]
    D, ρ ⊢ take n (R) ⇓ R'

    R' = R[n..]
    ────────────────────────  [Skip]
    D, ρ ⊢ skip n (R) ⇓ R'
```

### 4.5 Return

```
    ∀k ∈ R: project fields from k
    R' = [{ f₁: k.f₁, …, fₘ: k.fₘ } | k ∈ R]
    ──────────────────────────────────────────  [Return]
    D, ρ ⊢ return f₁, …, fₘ (R) ⇓ R'

    ∀k ∈ R: attach provenance from D.egraph
    R' = [{ …k, _provenance: prov(k) } | k ∈ R]
    ──────────────────────────────────────────────  [Return-Provenance]
    D, ρ ⊢ return … with provenance (R) ⇓ R'
```

### 4.6 Group / Aggregate

```
    groups = partition R by (λk. ρ[k] ⊢ key_expr ⇓ gₖ)
    ∀g: agg_result(g) = apply aggregate_fn to g
    ────────────────────────────────────────────────  [Aggregate]
    D, ρ ⊢ group_by key | aggregate fn(expr) (R) ⇓ [agg_result(g) | g ∈ groups]
```

### 4.7 Let (inline binding)

```
    D, ρ ⊢ expr ⇓ v     ρ' = ρ[x ↦ v]
    ─────────────────────────────────────  [Let]
    D, ρ ⊢ let x = expr (R) ⇓ R  (with ρ' for subsequent stages)
```

---

## 5. Equivalence Queries

### 5.1 Find Equivalent (Propositional Equality ≅)

```
    D.invariants(target, inv_name) = v_target     for each inv in invariant_list
    candidates = { k ∈ R | ∀inv ∈ invariant_list:
                     D.invariants(k, inv) = D.invariants(target, inv) }
    ∀k ∈ candidates:
      evidence(k) = [(inv, D.invariants(k, inv), confidence(inv)) | inv ∈ matched]
    ─────────────────────────────────────────────────────────────────────  [FindEquiv]
    D, ρ ⊢ find_equivalent target via [inv₁, …, invₘ] (R)
      ⇓ [{ knot: k, equivalence_evidence: evidence(k) } | k ∈ candidates]
```

### 5.2 Confidence Levels

```
confidence : InvariantName → ConfidenceLevel

confidence(crossing_number)  = necessary        (matching is necessary but not sufficient)
confidence(writhe)           = necessary
confidence(genus)            = necessary
confidence(jones_polynomial) = exact             (matching is strong evidence)
confidence(alexander)        = exact
confidence(homfly)           = exact
confidence(quandle)          = sufficient        (isomorphism implies equivalence)
```

### 5.3 Stratified Evaluation

Invariants are evaluated in order of increasing cost. Early strata can refute
equivalence quickly (short-circuit):

```
    stratum(crossing_number) = 0     (O(1) lookup)
    stratum(genus)           = 1     (O(n) computation)
    stratum(jones)           = 2     (O(2^n) in crossing number)
    stratum(quandle)         = 5     (undecidable in general)

    ∀s = 0, 1, 2, …:
      check invariants at stratum s
      if any invariant DIFFERS → refute equivalence (prune candidate)
      if all match → proceed to next stratum
    ───────────────────────────────────────────────────  [Stratified]
    Evaluation terminates at first refutation or exhaustion of strata
```

---

## 6. Path Queries

### 6.1 Find Path (Path Equality ~>)

```
    D ⊢ search_reidemeister(source_diagram, target_diagram) = path
    path = [move₁, move₂, …, moveₖ]     each moveᵢ ∈ {R1, R2, R3}
    ─────────────────────────────────────────────────────────────────  [FindPath]
    D, ρ ⊢ find_path source ~> target via reidemeister (R)
      ⇓ [{ path: path, move_count: k }]

    no path found within search limit
    ──────────────────────────────────────────────  [FindPath-NotFound]
    D, ρ ⊢ find_path … ⇓ []
```

---

## 7. Graph Pattern Matching

```
    ∀(K₁, K₂) ∈ R × R:
      edge_exists(K₁, label, K₂) = D.edges(K₁, label, K₂)
      properties_match(K₁, K₂, constraints)
    R' = [(K₁, K₂) | (K₁, K₂) matching pattern]
    ────────────────────────────────────────────────  [Match]
    D, ρ ⊢ match (K1)-[:LABEL]->(K2) (R) ⇓ R'
```

---

## 8. Rule Definitions (Datalog)

```
    D' = D ∪ { rule(name, params, body) }
    D' ⊢ saturate(egraph)     (fixed-point equality saturation)
    ──────────────────────────────────────────────────────────  [Rule-Def]
    D, ρ ⊢ rule name(params) :- body ⇒ D'
```

### 8.1 Equality Saturation

```
    egraph₀ = initial e-graph from D.knots
    repeat:
      ∀rule ∈ D.rules:
        ∀match of rule.body in egraph:
          merge rule.head into equivalence class
    until fixed point (no new merges)
    ──────────────────────────────────────────  [Saturate]
    saturate(D) ⇓ D[egraph ↦ egraph_saturated]
```

---

## 9. Expressions

```
    ρ ⊢ x ⇓ ρ(x)                              [Var]
    ρ ⊢ lit ⇓ lit                              [Lit]
    ρ ⊢ e₁ ⊕ e₂ ⇓ eval(e₁) ⊕ eval(e₂)        [BinOp]
    ρ ⊢ e.f ⇓ (eval(e)).f                      [FieldAccess]
    ρ ⊢ f(args) ⇓ apply(f, eval(args))         [Call]
    ρ ⊢ [e₁, …, eₙ] ⇓ [eval(e₁), …, eval(eₙ)] [Array]
    ρ ⊢ {f₁: e₁, …} ⇓ {f₁: eval(e₁), …}      [Record]
```

---

## 10. Provenance Semantics

Every result carries provenance as a semiring annotation (Green et al., 2007):

```
Provenance = ⟨ invariants_used : Set<InvariantName>,
               confidence      : ConfidenceLevel,
               computation_path: List<Step>,
               time_cost       : Duration ⟩

combine(p₁, p₂) = ⟨ p₁.invariants ∪ p₂.invariants,
                     min(p₁.confidence, p₂.confidence),
                     p₁.path ++ p₂.path,
                     p₁.time + p₂.time ⟩
```

---

## 11. Invariants

1. **Pipeline compositionality:** Each stage is a pure function on result sets.
2. **Stratified termination:** Invariant evaluation terminates because strata are finite and evaluation at each stratum terminates (except quandle, which has a search limit).
3. **Provenance completeness:** Every equivalence result carries evidence of which invariants matched.
4. **Short-circuit correctness:** If any necessary invariant differs, the knots are provably non-equivalent.
5. **E-graph confluence:** Equality saturation reaches a unique fixed point regardless of rule application order.
6. **Deterministic collapse:** Given the same database state and query, results are deterministic.
