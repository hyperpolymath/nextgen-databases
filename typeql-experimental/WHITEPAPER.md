# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# TypeQL-Experimental: Dependent Types for Query Language Safety

**Author:** Jonathan D.A. Jewell
**Version:** 1.0
**Date:** 2026-03-14
**Status:** Research (85% complete)

---

## Abstract

TypeQL-Experimental (VQL-dt++) explores the application of Quantitative Type
Theory (QTT) to database query languages, demonstrating that six categories of
runtime database errors—connection leaks, protocol violations, effect misuse,
scope leakage, missing postcondition guarantees, and resource over-consumption—
can be eliminated entirely at compile time through dependent types. Using Idris2's
native QTT, we implement linear types for connection safety, indexed types for
session protocol compliance, effect subsumption for side-effect tracking, modal
types for transaction isolation, proof-carrying results for postcondition
guarantees, and bounded resource accounting for query budgets. All nine Idris2
modules type-check with `%default total` and zero uses of axiom-bypassing
constructs (`believe_me`, `assert_total`, `assert_smaller`), meaning every
safety guarantee is backed by a machine-checked proof.

---

## 1. Introduction

### 1.1 The State of Database Safety

Modern databases offer sophisticated query languages, transaction protocols,
and access control mechanisms. Yet six categories of bugs persist across every
major database system:

1. **Connection leaks:** Connections opened but never closed, or used after
   closing, eventually exhausting the connection pool.

2. **Protocol violations:** Querying before authenticating, committing outside
   a transaction, or using a connection in an invalid state.

3. **Effect misuse:** Write operations executed in read-only contexts, or
   queries that silently perform side effects not declared in their interface.

4. **Scope leakage:** Data from one transaction scope leaking into another,
   violating isolation guarantees.

5. **Missing postconditions:** Query results lacking guarantees about integrity,
   freshness, or provenance that downstream consumers require.

6. **Resource over-consumption:** Queries that exceed their allocated budget
   (connections, API calls, federation requests).

These bugs are not caused by careless programming. They arise because the
*type systems* of existing query languages and host language bindings cannot
express the relevant invariants. Connection safety requires linear types.
Protocol compliance requires indexed types. Effect tracking requires effect
systems. Transaction isolation requires modal types. These are all features
of dependent type theory that SQL and its derivatives lack.

### 1.2 Dependent Types for Databases

Dependent types (Martin-Löf, 1984) allow types to depend on values, enabling
the expression of precise invariants at the type level. A dependent type system
can express:

- "This connection has exactly 3 uses remaining" (indexed type).
- "This session is in the Authenticated state" (indexed type).
- "This query performs only Read effects" (effect system via dependent pairs).
- "This data was produced in transaction scope W₁" (modal type).

Idris2 (Brady, 2021) implements Quantitative Type Theory (Atkey, 2018), which
adds *usage quantities* to every binding: `0` (erased at runtime), `1` (used
exactly once, i.e., linear), or `ω` (unrestricted). This makes linear types
a native feature of the language, not an encoding.

### 1.3 Contributions

1. **Six type-theoretic extensions** to VQL (VeriSim Query Language) that
   eliminate the six bug categories above at compile time (Section 3).

2. **A dual-language architecture** where Idris2 proves properties and ReScript
   parses queries, connected by a Zig FFI bridge (Section 4).

3. **Zero-axiom proofs**: All guarantees are machine-checked with no escape
   hatches (Section 5).

4. **Backwards-compatible grammar**: All extensions are optional clauses appended
   to standard VQL queries, requiring no changes to existing queries (Section 6).

---

## 2. Background

### 2.1 VQL v3.0

VeriSim Query Language (VQL) is the query language for VeriSimDB, a multi-modal
database with eight query modalities (GRAPH, DOCUMENT, VECTOR, TIME_SERIES,
SPATIAL, STATISTICAL, SEMANTIC, RELATIONAL). VQL supports cross-modal queries
via HEXAD references (content-addressed UUIDs).

### 2.2 Quantitative Type Theory

QTT (Atkey, 2018; McBride, 2016) extends dependent type theory with a semiring
of quantities on each variable binding. In Idris2:

```idris
-- Unrestricted: can use 'x' any number of times
f : (x : Nat) -> Nat

-- Linear: must use 'conn' exactly once
g : (1 conn : Connection) -> IO Result

-- Erased: 'prf' exists only at compile time
h : (0 prf : IsValid x) -> Result
```

The quantity `1` enforces linearity: the compiler rejects any code that uses
a linear variable zero times or more than once. This is not an annotation—it
is a *proof obligation* that the compiler verifies.

### 2.3 Prior Work

- **HoTTSQL** (Chu et al., PLDI 2017): Uses HoTT to prove SQL query rewrite
  equivalence. Does not extend SQL's type system.
- **Links** (Cooper et al., 2006): Language-integrated query with row types.
  No linear types or session types.
- **Ur/Web** (Chlipala, 2015): Dependent types for web programming with SQL.
  Closest predecessor, but no QTT, no session types, no effect tracking.

TypeQL-Experimental differs from all prior work in applying QTT *natively* to
database queries, making linear types and resource accounting first-class
rather than encoded.

---

## 3. The Six Extensions

### 3.1 Linear Types: CONSUME AFTER N USE

**Problem:** Connection leaks and use-after-close bugs.

**Solution:** Connections carry a type-level usage counter:

```vql
SELECT GRAPH, DOCUMENT
FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
CONSUME AFTER 1 USE
```

**Type-level encoding:**

```idris
data LinConn : (remaining : Nat) -> Type where
  MkLinConn : (handle : Bits64) -> LinConn remaining

useConn : (1 _ : LinConn (S n)) -> (QueryResult, LinConn n)
closeConn : (1 _ : LinConn 0) -> IO ()
```

The type `LinConn (S n)` can be used (producing `LinConn n`), and `LinConn 0`
can only be closed. The `1` quantity on the argument ensures exactly-once
consumption. Attempting to use a connection twice is a *compile error*, not a
runtime exception.

### 3.2 Session Types: WITH SESSION

**Problem:** Protocol violations (querying before auth, committing twice).

**Solution:** Sessions are indexed by their protocol state:

```vql
SELECT GRAPH FROM HEXAD ...
WITH SESSION ReadOnlyProtocol
```

**Type-level encoding:**

```idris
data SessionState = Fresh | Authenticated | InTransaction | Committed | Closed

data Session : SessionState -> Type where
  MkFresh : Session Fresh

authenticate : (1 _ : Session Fresh) -> Either AuthError (Session Authenticated)
beginTx : (1 _ : Session Authenticated) -> Session InTransaction
query : (1 _ : Session InTransaction) -> QueryPlan -> (QueryResult, Session InTransaction)
commit : (1 _ : Session InTransaction) -> Either TxError (Session Committed)
close : (1 _ : Session s) -> {auto prf : CanClose s} -> IO ()
```

Each operation consumes the session linearly and produces the next state.
`query` requires `Session InTransaction`—calling it with `Session Fresh` is
a type error. The state machine is enforced by the compiler.

### 3.3 Effect Systems: EFFECTS { Read, Write, ... }

**Problem:** Undeclared side effects in queries.

**Solution:** Queries declare their effects; the type checker verifies actual
effects are a subset of declared effects:

```vql
SELECT GRAPH FROM HEXAD ...
EFFECTS { Read }
```

**Type-level encoding:**

```idris
data Effect = Read | Write | Cite | Audit | Transform | Federate

Subsumes : (declared : List Effect) -> (actual : List Effect) -> Type
Subsumes declared actual = Subset actual declared
```

If a query declared as `EFFECTS { Read }` attempts a Write, the type checker
cannot construct `Subsumes [Read] [Write]` (because Write ∉ [Read]), and the
query is rejected.

### 3.4 Modal Types: IN TRANSACTION

**Problem:** Data leaking between transaction scopes.

**Solution:** Data is tagged with its transaction scope at the type level:

```vql
SELECT GRAPH FROM HEXAD ...
IN TRANSACTION Committed
```

**Type-level encoding:**

```idris
data World = Fresh | Active | Committed | RolledBack | ReadSnapshot

data Box : World -> Type -> Type where
  MkBox : a -> Box w a

extract : Box w a -> {auto prf : InScope w} -> a
marshal : Box w1 a -> (a -> b) -> Box w2 b
```

Data in `Box w1 a` can only be extracted with evidence that we are `InScope w1`.
Moving data between worlds requires explicit `marshal`, making cross-scope
data flow visible in types.

### 3.5 Proof-Carrying Code: PROOF ATTACHED

**Problem:** Results lack formal guarantees for downstream consumers.

**Solution:** Results are bundled with proofs of postconditions:

```vql
SELECT GRAPH FROM HEXAD ...
PROOF ATTACHED IntegrityTheorem
```

**Type-level encoding:**

```idris
data Theorem = IntegrityThm | FreshnessThm | ProvenanceThm | ConsistencyThm

ProvedResult : Type -> Theorem -> Type
ProvedResult a thm = (result : a ** ProofOf thm result)
```

The result type is a dependent pair: the data *and* a proof that the data
satisfies the stated theorem. Downstream consumers can verify the proof
independently.

### 3.6 Quantitative Type Theory: USAGE LIMIT

**Problem:** Resource over-consumption in federation or API-limited contexts.

**Solution:** Resources carry a type-level budget:

```vql
SELECT GRAPH FROM FEDERATION /universities/*
USAGE LIMIT 100
```

**Type-level encoding:**

```idris
data BoundedResource : (limit : Nat) -> Type where
  MkBounded : a -> BoundedResource limit

consume : BoundedResource (S n) a -> (a, BoundedResource n a)
-- BoundedResource 0 has no consume operation: it's depleted
```

This generalises linear types: `BoundedResource 1` is equivalent to a linear
resource, while `BoundedResource 100` allows exactly 100 uses.

---

## 4. Architecture

### 4.1 Dual-Language Split

| Layer | Language | Purpose |
|-------|----------|---------|
| **Type kernel** | Idris2 (9 modules) | Formal specification, proof checking |
| **Parser** | ReScript (2 files) | Surface syntax parsing |
| **FFI bridge** | Zig (3 files) | C-ABI bridge for external consumers |

**Design rationale:** In the research phase, Idris2 and ReScript operate
independently. Idris2 proves type properties; ReScript parses queries. Future
integration would wire parsed ASTs to Idris2 proofs. This separation allows
rapid iteration on both fronts.

### 4.2 Module Structure

```
src/abi/
├── Core.idr          -- Foundation: modalities, effects, quantities
├── Linear.idr        -- LinConn indexed by remaining uses
├── Session.idr       -- Session state machine
├── Effects.idr       -- Effect subsumption
├── Modal.idr         -- World-indexed boxes
├── ProofCarrying.idr -- Theorem attachment
├── Quantitative.idr  -- Bounded resources
├── Checker.idr       -- Unified validation (composes all 6)
└── Proofs.idr        -- Cross-cutting proofs
```

### 4.3 Verification Status

All 9 modules compile under `%default total` with zero banned patterns:

- Zero `believe_me` (axiom assertion)
- Zero `assert_total` (totality override)
- Zero `assert_smaller` (termination override)

Every proof is real. The type system enforces soundness.

---

## 5. Cross-Extension Proofs

### 5.1 Key Theorems

The `Proofs.idr` module proves cross-cutting properties:

1. **Linear exact use:** Using a `LinConn n` exactly n times produces
   `LinConn 0`. This ensures connection pools are never exhausted by
   "stranded" connections.

2. **Effect subsumption reflexivity:** `Subsumes es es` is always provable.
   A query's declared effects always permit themselves.

3. **Effect subsumption transitivity:** If `Subsumes a b` and `Subsumes b c`,
   then `Subsumes a c`. Effect permissions compose.

4. **Budget fits:** A `BoundedResource n` can perform at most n operations
   before depletion. The type system prevents over-consumption.

### 5.2 Composability

The six extensions compose without interference:

```vql
SELECT GRAPH, DOCUMENT
FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
CONSUME AFTER 1 USE
WITH SESSION ReadOnlyProtocol
EFFECTS { Read, Cite }
IN TRANSACTION Committed
PROOF ATTACHED IntegrityTheorem
USAGE LIMIT 100
```

The type checker validates all six constraints simultaneously. The `Checker.idr`
module composes individual checks, and their independence is guaranteed by the
fact that each extension operates on a different dimension of the type.

---

## 6. Grammar

### 6.1 Backwards Compatibility

All extensions are optional clauses appended after standard VQL queries:

```ebnf
extended_query = query,
                 [consume_clause],
                 [session_clause],
                 [effects_clause],
                 [modal_clause],
                 [proof_attached_clause],
                 [usage_clause] ;

consume_clause        = 'CONSUME', 'AFTER', positive_integer, 'USE' ;
session_clause        = 'WITH', 'SESSION', protocol_name ;
effects_clause        = 'EFFECTS', '{', effect_list, '}' ;
modal_clause          = 'IN', 'TRANSACTION', transaction_state ;
proof_attached_clause = 'PROOF', 'ATTACHED', theorem_name ;
usage_clause          = 'USAGE', 'LIMIT', positive_integer ;
```

No existing VQL keywords are reused. All new keywords (CONSUME, AFTER, USE,
SESSION, EFFECTS, TRANSACTION, ATTACHED, USAGE) are disjoint from VQL's 60+
existing keywords.

### 6.2 File Extension

TypeQL-Experimental queries use the `.vqlut` extension (VQL Ultimate Type-Safe),
distinguishing them from standard `.vql` files. (Previously `.vqlpp` — renamed to align with VQL-UT canonical naming.)

---

## 7. Related Work

| System | Linear | Session | Effect | Modal | Proof | Quantitative |
|--------|--------|---------|--------|-------|-------|-------------|
| SQL | No | No | No | No | No | No |
| HoTTSQL | No | No | No | No | Yes* | No |
| Ur/Web | No | No | No | No | Partial | No |
| Links | No | No | No | No | No | No |
| **TypeQL-Exp** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** |

*HoTTSQL proves query rewrite equivalence, not result properties.

---

## 8. Conclusion

TypeQL-Experimental demonstrates that dependent types—specifically Quantitative
Type Theory as implemented in Idris2—can eliminate six entire categories of
database errors at compile time. The key insight is that QTT's native linear
types make connection safety and resource budgeting *free*: the language already
tracks usage quantities on every binding, so `CONSUME AFTER 1 USE` maps directly
to `(1 conn : Connection)`.

The six extensions compose independently, require no changes to existing VQL
queries, and are backed by machine-checked proofs with no axiom escape hatches.
This work suggests that the next generation of query languages should integrate
dependent type systems not as an academic exercise but as a practical tool for
eliminating entire bug categories.

---

## References

1. Atkey, R. (2018). "Syntax and Semantics of Quantitative Type Theory."
   *LICS 2018*, 56–65.
2. Brady, E. (2021). "Idris 2: Quantitative Type Theory in Practice."
   *ECOOP 2021*, 9:1–9:26.
3. Chlipala, A. (2015). "Ur/Web: A Simple Model for Programming the Web."
   *POPL 2015*, 153–165.
4. Chu, S. et al. (2017). "HoTTSQL: Proving Query Rewrites with Univalent
   SQL Semantics." *PLDI 2017*, 510–524.
5. Cooper, E. et al. (2006). "Links: Web Programming Without Tiers."
   *FMCO 2006*, 266–296.
6. Martin-Löf, P. (1984). *Intuitionistic Type Theory*. Bibliopolis.
7. McBride, C. (2016). "I Got Plenty o' Nuttin'." *A List of Successes That
   Can Change the World*, 207–233.
