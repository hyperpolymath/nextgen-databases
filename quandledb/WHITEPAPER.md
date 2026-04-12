# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# KRL: A Knot-Theoretic Resolution Language for Topological Data

**Author:** Jonathan D.A. Jewell
**Version:** 1.0
**Date:** 2026-03-14
**Status:** Design (v0.2.0 target)

---

## Abstract

We present KRL (Knot Resolution Language), a domain-specific resolution language for
QuandleDB that treats mathematical equivalence as a first-class query primitive.
Traditional database query languages (SQL, GraphQL, Cypher) model equality as a
binary predicate: two values are either equal or not. This model is fundamentally
inadequate for topological data, where two objects (e.g., knot diagrams) may be
equivalent via multiple distinct paths (Reidemeister moves), and the space of
equivalences itself has mathematical structure. KRL addresses this by grounding
its semantics in Homotopy Type Theory (HoTT), where equality is not a boolean
but a *type*—the type of paths between two objects. The result is a query language
where equivalence queries return not just matching objects but the *derivations*
that establish equivalence, with provenance tracking that records which invariants
contributed to each proof.

---

## 1. Introduction

### 1.1 Knots and Databases

A *knot* is a closed curve embedded in three-dimensional space, considered up to
ambient isotopy (continuous deformation without cutting or passing through itself).
The classification of knots is a central problem in topology, with the KnotInfo
database currently cataloguing over 350 million prime knots up to 19 crossings
and 1.9 billion at 20 crossings (Livingston & Moore, 2024).

Querying knot databases presents a challenge unlike any in relational, document,
or graph databases: **equality is hard**. Two knot diagrams may look completely
different yet represent the same knot, distinguishable only through a sequence
of Reidemeister moves (local diagrammatic transformations) or through the
computation of algebraic invariants (Jones polynomial, knot group, etc.).
No single invariant is complete—there exist distinct knots with identical Jones
polynomials—so equivalence often requires combining multiple invariants and
sometimes remains unresolvable.

### 1.2 Why Not SQL?

SQL's relational model fails for knot data in several fundamental ways:

1. **Binary equality:** SQL's `WHERE a = b` returns a boolean. For knots,
   `a ≅ b` should return the *space of equivalences*—a potentially non-trivial
   mathematical object.

2. **No compositional equivalence:** Two knots may be equivalent via different
   paths. SQL has no mechanism to distinguish or compose these paths.

3. **No invariant provenance:** When a query determines that two knots are
   equivalent, SQL cannot record *which invariants* established the equivalence
   and with what confidence.

4. **Three-valued logic:** SQL's NULL handling (three-valued logic) conflates
   "unknown" with "inapplicable." For knot invariants, the distinction between
   "genus not yet computed" and "genus undefined for this object" is
   mathematically significant.

5. **Type poverty:** SQL lacks sum types, dependent types, and generics—all
   necessary for representing the rich algebraic structures in knot theory.

### 1.3 Contributions

This paper presents:

1. **KRL's semantic model** grounded in HoTT identity types, where equivalence
   queries return types, not booleans (Section 3).
2. **E-graph-backed execution** using equality saturation (egglog) to compactly
   represent equivalence classes (Section 4).
3. **Provenance-carrying results** that track which invariants contributed to
   each equivalence proof (Section 5).
4. **Category-theoretic schema** following Spivak's CQL, where schema is a
   category and queries are functors (Section 6).
5. **Pipeline syntax** inspired by PRQL, with ASCII-art graph patterns from
   Cypher/GQL (Section 7).

---

## 2. Mathematical Background

### 2.1 Knots and Invariants

A *knot invariant* is a function from knots to some algebraic structure that
assigns the same value to equivalent knots. Key invariants include:

| Invariant | Type | Completeness |
|-----------|------|-------------|
| Crossing number | ℕ | Very weak |
| Writhe | ℤ | Weak (diagram-dependent) |
| Genus | ℕ | Moderate |
| Jones polynomial | ℤ[t^±½] | Strong but not complete |
| Alexander polynomial | ℤ[t^±1] | Moderate |
| HOMFLY-PT polynomial | ℤ[a^±1, z^±1] | Strong |
| Knot group | Group presentation | Complete (but undecidable) |

No single computable invariant is known to be complete. In practice, equivalence
is established by matching multiple invariants and, when necessary, finding an
explicit isotopy.

### 2.2 Quandles

A *quandle* (Q, ▷) is a set Q with a binary operation ▷ satisfying:

1. **Idempotence:** a ▷ a = a for all a ∈ Q.
2. **Right-invertibility:** For all a, b ∈ Q, there exists a unique c such that c ▷ a = b.
3. **Self-distributivity:** (a ▷ b) ▷ c = (a ▷ c) ▷ (b ▷ c) for all a, b, c ∈ Q.

The *fundamental quandle* of a knot is a complete invariant—two knots are
equivalent if and only if their fundamental quandles are isomorphic. However,
quandle isomorphism is computationally expensive and not always practical.

### 2.3 Homotopy Type Theory

In HoTT (Univalent Foundations Program, 2013), the identity type `a =_A b` is
not a proposition (boolean) but a *type*—the type of paths from a to b.
This type may be:

- **Empty:** a and b are not equal (no path exists).
- **Contractible:** a and b are *uniquely* equal (exactly one path, up to homotopy).
- **Non-trivial:** Multiple distinct paths exist, and the space of paths has
  mathematical structure.

For knots, `K₁ =_Knot K₂` is the type of isotopies from K₁ to K₂. This type
may contain multiple distinct isotopies (different sequences of Reidemeister
moves), and these isotopies can themselves be compared—forming higher-dimensional
structure.

---

## 3. KRL Semantic Model

### 3.1 Equivalence as a Type

KRL's fundamental departure from SQL is that equivalence queries return *types*,
not booleans:

```krl
from knots
| where equivalent_to("3_1")
| return equivalences
```

This query does not return a flat list of knot names. It returns, for each
matching knot K, the *equivalence evidence*:

```
{
  knot: K,
  equivalence_type: [
    { path: "jones_match", invariant: "jones_polynomial", confidence: "exact" },
    { path: "genus_match", invariant: "genus", confidence: "exact" },
    { path: "crossing_number_bound", invariant: "crossing_number", confidence: "necessary" }
  ]
}
```

### 3.2 Identity Types in KRL

KRL models three levels of identity:

1. **Definitional equality** (`==`): Identical representations (same Gauss code).
   Decidable, trivial.

2. **Propositional equality** (`≅`): Equivalent via invariants. Returns a
   *proof term* recording which invariants matched.

3. **Path equality** (`~`): Equivalent via explicit isotopy (sequence of
   Reidemeister moves). Returns the path itself.

```krl
from knots
| where K ≅ "3_1" via [jones, genus, crossing_number]
| return K, proof
```

### 3.3 Quotient Types

KRL represents equivalence classes as quotient types:

```
Knot / ≅ = { [K] | K ∈ Knot }
```

Queries on quotient types operate on equivalence classes rather than individual
representatives, which is the mathematically natural operation for topological
data.

---

## 4. E-Graph Execution Engine

### 4.1 Equality Saturation

KRL queries are executed against an *e-graph* (equivalence graph), a data
structure that compactly represents equivalence classes. Following the egglog
paradigm (Willsey et al., PLDI 2023), KRL combines Datalog-style recursive
queries with equality saturation:

```krl
# Define equivalence rules
rule jones_equivalent(K1, K2) :-
  knot(K1), knot(K2),
  jones_polynomial(K1, J), jones_polynomial(K2, J),
  K1 != K2.

rule genus_equivalent(K1, K2) :-
  knot(K1), knot(K2),
  genus(K1, G), genus(K2, G).

# Query: find equivalence class of trefoil
from knots
| where jones_equivalent(K, "3_1")
| where genus_equivalent(K, "3_1")
| return K, equivalence_class
```

### 4.2 Stratified Invariant Evaluation

Not all invariants are equally expensive to compute. KRL's query planner
evaluates invariants in order of increasing cost:

| Stratum | Invariants | Cost |
|---------|-----------|------|
| 0 | Crossing number, writhe | O(1) lookup |
| 1 | Genus, Seifert circles | O(n) computation |
| 2 | Jones polynomial | O(2^n) in crossing number |
| 3 | Alexander polynomial | O(n³) matrix determinant |
| 4 | HOMFLY-PT polynomial | O(2^n) or worse |
| 5 | Fundamental quandle | Undecidable in general |

Early strata can *refute* equivalence quickly (different crossing numbers
immediately prove non-equivalence), while later strata provide stronger
evidence for equivalence.

---

## 5. Provenance-Carrying Results

### 5.1 Semiring Annotations

Following the provenance semiring framework (Green et al., 2007), KRL annotates
every result with provenance information recording how the result was derived:

```
Result = (data, provenance)

Provenance = Semiring(
  invariant_used: Set[Invariant],
  confidence: {exact, necessary, sufficient, heuristic},
  computation_path: List[Step],
  time_cost: Duration
)
```

### 5.2 Confidence Levels

| Level | Meaning | Example |
|-------|---------|---------|
| `exact` | Invariant matched exactly | Jones polynomials are identical |
| `necessary` | Matching is necessary but not sufficient | Same crossing number |
| `sufficient` | Matching is sufficient for equivalence | Quandle isomorphism |
| `heuristic` | Statistical or approximate | Tabulated classification |

---

## 6. Category-Theoretic Schema

### 6.1 Schema as Category

Following Spivak (2014), KRL models the database schema as a category C:

- **Objects:** Entity types (Knot, Invariant, Isotopy, Diagram).
- **Morphisms:** Relationships (has_invariant, has_diagram, isotopy_between).
- **Functors:** Data instances (I : C → Set) mapping schema to data.

### 6.2 Queries as Functors

A KRL query is a functor Q : C → C' between schema categories. This provides:

- **Compositionality:** Queries compose as functors compose.
- **Type safety:** Functors preserve categorical structure, preventing ill-typed
  queries at the schema level.
- **Data migration:** Schema changes are functors, with automatic data migration.

---

## 7. Surface Syntax

### 7.1 Pipeline Syntax

KRL adopts PRQL's pipeline approach for readability:

```krl
from knots
| filter crossing_number <= 10
| filter genus == 1
| sort jones_polynomial
| take 20
| return name, crossing_number, jones_polynomial
```

### 7.2 Equivalence Queries

```krl
from knots
| find_equivalent "3_1" via [jones, genus]
| return equivalences with provenance
```

### 7.3 Graph Patterns

For navigating relationships between knots (e.g., knots related by specific
operations like connected sum):

```krl
from knots as K1
| match (K1)-[:CONNECTED_SUM]->(K2)
| where K2.crossing_number < K1.crossing_number
| return K1.name, K2.name
```

### 7.4 Reidemeister Move Queries

```krl
from diagrams as D1
| find_path D1 ~> "3_1" via reidemeister
| return path, move_count
```

---

## 8. Implementation

### 8.1 Architecture

| Layer | Language | Purpose |
|-------|----------|---------|
| Engine | Julia (Skein.jl) | Knot storage, invariant computation |
| Query Parser | Julia | KRL parsing and AST construction |
| E-graph Engine | Julia | Equality saturation, equivalence classes |
| API | Julia (HTTP.jl) | REST API for queries |
| Frontend | ReScript + React | Interactive query interface |
| ABI | Idris2 | Formal verification of query semantics |
| FFI | Zig | C-ABI bridge for external consumers |

### 8.2 Data Model

QuandleDB stores knots as records with extensible invariant fields:

```julia
struct KnotRecord
    name::String
    gauss_code::Vector{Int}
    crossing_number::Int
    writhe::Int
    genus::Union{Int, Nothing}
    jones_polynomial::Union{String, Nothing}
    metadata::Dict{String, String}
end
```

---

## 9. Related Work

### 9.1 Database Query Languages

- **SQL** (Codd, 1970): Relational algebra with binary equality. No support for
  structured equivalences.
- **Cypher** (Robinson et al., 2015): Graph pattern matching. Useful for
  navigating knot relationships but no equivalence semantics.
- **PRQL** (PRQL Project, 2022): Pipeline syntax for SQL. KRL adopts its
  ergonomics but not its relational semantics.
- **HoTTSQL** (Chu et al., PLDI 2017): SQL semantics via HoTT. Proves
  equivalence of SQL queries, not of data. KRL adapts HoTT for data equivalence.
- **egglog** (Willsey et al., PLDI 2023): Equality saturation + Datalog.
  KRL's execution engine.
- **CQL** (Spivak, 2014): Categorical Query Language. KRL's schema model.

### 9.2 Knot Theory Software

- **SnapPy** (Culler et al.): 3-manifold topology. Computations, not queries.
- **KnotInfo** (Livingston & Moore): Web database. SQL backend, no KRL.
- **Knot Atlas**: Wiki-based. No structured query language.
- **Skein.jl** (hyperpolymath): Julia knot engine. KRL's computation backend.

### 9.3 Type Theory and Equality

- **HoTT** (Univalent Foundations, 2013): Identity types as paths. KRL's
  semantic foundation.
- **Cubical Agda** (Vezzosi et al., 2019): Computational HoTT. Potential
  future implementation target.
- **Lean 4 mathlib** (mathlib Community): Formal quandle definitions. KRL's
  proof library.

---

## 10. Conclusion

KRL demonstrates that domain-specific query languages can and should respect
the mathematical structure of their data. For topological data, binary equality
is the wrong abstraction. By grounding query semantics in HoTT identity types,
executing queries via equality saturation, and carrying provenance through
results, KRL provides a resolution language that is mathematically honest about
what it means for two knots to be "the same."

The broader lesson is that the choice of equality model is a fundamental design
decision for any query language, and different domains may require different
models. SQL's binary equality is appropriate for business data where two customer
IDs are either the same or different. But for scientific data—knots, molecular
structures, geometric objects—equality is richer, and our query languages should
reflect that richness.

---

## References

1. Chu, S. et al. (2017). "HoTTSQL: Proving Query Rewrites with Univalent SQL
   Semantics." *PLDI 2017*, 510–524.
2. Codd, E. F. (1970). "A Relational Model of Data for Large Shared Data Banks."
   *Communications of the ACM*, 13(6), 377–387.
3. Green, T. J. et al. (2007). "Provenance Semirings." *PODS 2007*, 31–40.
4. Livingston, C. & Moore, A. H. (2024). *KnotInfo: Table of Knot Invariants*.
   https://www.indiana.edu/~knotinfo
5. Spivak, D. I. (2014). *Category Theory for the Sciences*. MIT Press.
6. The Univalent Foundations Program. (2013). *Homotopy Type Theory: Univalent
   Foundations of Mathematics*.
7. Willsey, M. et al. (2023). "Better Together: Unifying Datalog and Equality
   Saturation." *PLDI 2023*, 468–486.
