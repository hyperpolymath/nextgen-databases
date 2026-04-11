# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# TypeQL-Experimental Operational Semantics

**Version:** 1.0.0
**Date:** 2026-03-14

---

## 1. Notation

- `Γ` — Type context (variable typing assumptions)
- `D` — Database state
- `Γ, D ⊢ q : τ ⇓ v` — Query `q` has type `τ` and evaluates to `v`
- `Γ ⊢ q : τ` — Query `q` type-checks to `τ` (compile-time)
- Quantities: `0` (erased), `1` (linear), `ω` (unrestricted)

---

## 2. Values

```
v ∈ Value ::=
    QueryResult(rows)                          query result set
  | LinConn(handle, remaining)                 linear connection (indexed by uses)
  | Session(state)                             session state machine
  | Box(world, v)                              modal box (scoped value)
  | ProvedResult(v, proof)                     result with attached theorem
  | BoundedResource(v, remaining)              usage-limited resource
  | EffectSet(effects)                         declared effect set
```

---

## 3. Type System (Compile-Time)

### 3.1 Linear Types (CONSUME AFTER N USE)

```
    Γ, (1 conn : LinConn (S n)) ⊢ query : τ
    ─────────────────────────────────────────────────────────  [Lin-Use]
    Γ ⊢ useConn(conn) : (QueryResult, LinConn n)

    Γ, (1 conn : LinConn 0) ⊢ close : IO ()
    ──────────────────────────────────────────────────────  [Lin-Close]
    Γ ⊢ closeConn(conn) : IO ()

    conn used twice (linear quantity violated)
    ──────────────────────────────────────────────────────  [Lin-Error]
    Γ ⊢ program ⇒ TYPE ERROR: linear variable used more than once
```

### 3.2 Session Types (WITH SESSION)

```
    Γ, (1 s : Session Fresh) ⊢ auth(s) : Either AuthError (Session Authenticated)
    ────────────────────────────────────────────────────────────────────────────  [Sess-Auth]

    Γ, (1 s : Session InTransaction) ⊢ query(s, plan) : (QueryResult, Session InTransaction)
    ─────────────────────────────────────────────────────────────────────────────────────────  [Sess-Query]

    Γ, (1 s : Session InTransaction) ⊢ commit(s) : Either TxError (Session Committed)
    ──────────────────────────────────────────────────────────────────────────────────────  [Sess-Commit]

    Γ, (1 s : Session Fresh) ⊢ query(s, plan) ⇒ TYPE ERROR
    ─────────────────────────────────────────────────────────  [Sess-Error]
    (query requires Session InTransaction, not Session Fresh)
```

### 3.3 Effect System (EFFECTS)

```
    actual_effects(q) = {Read}     declared = {Read}
    actual ⊆ declared
    ──────────────────────────────────────────────────────  [Eff-Ok]
    Γ ⊢ q EFFECTS { Read } : τ

    actual_effects(q) = {Read, Write}     declared = {Read}
    Write ∉ declared
    ──────────────────────────────────────────────────────  [Eff-Error]
    Γ ⊢ q EFFECTS { Read } ⇒ TYPE ERROR: Write not in declared effects

    Subsumes(declared, actual) = ∀e ∈ actual. e ∈ declared
    ──────────────────────────────────────────────────  [Eff-Subsumes]
    Γ ⊢ Subsumes(declared, actual) : Type
```

### 3.4 Modal Types (IN TRANSACTION)

```
    Γ ⊢ v : a     w : World
    ───────────────────────────  [Modal-Box]
    Γ ⊢ MkBox(v) : Box w a

    Γ ⊢ b : Box w a     Γ ⊢ InScope w
    ─────────────────────────────────────  [Modal-Extract]
    Γ ⊢ extract(b) : a

    Γ ⊢ b : Box w₁ a     Γ ⊢ f : a → b
    ─────────────────────────────────────────  [Modal-Marshal]
    Γ ⊢ marshal(b, f) : Box w₂ b

    Γ ⊢ b : Box w₁ a     attempt extract without InScope w₁
    ──────────────────────────────────────────────────────────  [Modal-Error]
    TYPE ERROR: cannot extract from Box w₁ without InScope w₁ evidence
```

### 3.5 Proof-Carrying Code (PROOF ATTACHED)

```
    Γ ⊢ q : QueryResult     Γ ⊢ thm : Theorem
    Γ ⊢ verify(q, thm) succeeds
    ─────────────────────────────────────────────────  [Proof-Attach]
    Γ ⊢ q PROOF ATTACHED thm : ProvedResult QueryResult Theorem

    ProvedResult(v, prf) = (result : τ ** ProofOf thm result)
    ─────────────────────────────────────────────────────────  [Proof-Type]
    (dependent pair: data bundled with its proof)
```

### 3.6 Quantitative Types (USAGE LIMIT)

```
    Γ, (r : BoundedResource (S n) a) ⊢ consume(r) : (a, BoundedResource n a)
    ─────────────────────────────────────────────────────────────────────────  [Quant-Consume]

    Γ, (r : BoundedResource 0 a) ⊢ consume(r) ⇒ TYPE ERROR
    ──────────────────────────────────────────────────────────  [Quant-Depleted]
    (no consume operation exists on BoundedResource 0)
```

---

## 4. Runtime Semantics

### 4.1 Query Evaluation (standard VCL pipeline)

```
    D ⊢ SELECT modalities FROM hexad WHERE conditions ⇓ rows
    ────────────────────────────────────────────────────────────  [Query-Base]
    Γ, D ⊢ query ⇓ QueryResult(rows)
```

### 4.2 Linear Connection Runtime

```
    handle = open_connection(db_url)     remaining = n
    ────────────────────────────────────────────────────  [LinConn-Open]
    Γ, D ⊢ openConn(n) ⇓ LinConn(handle, n)

    conn = LinConn(handle, S(k))
    result = execute(handle, plan)
    conn' = LinConn(handle, k)
    ────────────────────────────────────────────  [LinConn-Use]
    Γ, D ⊢ useConn(conn, plan) ⇓ (result, conn')

    conn = LinConn(handle, 0)
    close(handle)
    ────────────────────────────────────────  [LinConn-Close]
    Γ, D ⊢ closeConn(conn) ⇓ ()
```

### 4.3 Session State Machine Runtime

```
    s = Session Fresh
    auth_result = authenticate(credentials)
    ────────────────────────────────────────────────────  [Session-Auth]
    Γ, D ⊢ auth(s, creds) ⇓ Right(Session Authenticated)
                               | Left(AuthError)

    s = Session Authenticated
    ────────────────────────────────────────────────  [Session-Begin]
    Γ, D ⊢ beginTx(s) ⇓ Session InTransaction

    s = Session InTransaction
    result = execute(plan)
    ────────────────────────────────────────────────────  [Session-Query]
    Γ, D ⊢ query(s, plan) ⇓ (result, Session InTransaction)

    s = Session InTransaction
    commit_result = commit_transaction()
    ────────────────────────────────────────────────────  [Session-Commit]
    Γ, D ⊢ commit(s) ⇓ Right(Session Committed)
                         | Left(TxError)
```

### 4.4 Effect Checking Runtime

```
    query_plan = plan(q)
    actual = collect_effects(query_plan)
    actual ⊆ declared     (verified at compile time by Idris2)
    ────────────────────────────────────────────────────────────  [Effects-Run]
    Γ, D ⊢ q EFFECTS { declared } ⇓ execute(query_plan)
```

### 4.5 Modal Scoping Runtime

```
    v computed in transaction scope w
    ────────────────────────────────────  [Modal-Wrap]
    Γ, D ⊢ MkBox(v) ⇓ Box(w, v)

    b = Box(w, v)     current_scope = w     (scope matches)
    ────────────────────────────────────────────────────────  [Modal-Open]
    Γ, D ⊢ extract(b) ⇓ v
```

### 4.6 Proof Verification Runtime

```
    result = execute(q)
    proof = verify_theorem(thm, result)
    proof succeeds
    ─────────────────────────────────────────────  [Proof-Verify]
    Γ, D ⊢ q PROOF ATTACHED thm ⇓ ProvedResult(result, proof)

    proof fails
    ─────────────────────────────────────────────────  [Proof-Fail]
    Γ, D ⊢ q PROOF ATTACHED thm ⇓ ⊥("theorem verification failed")
```

### 4.7 Resource Budget Runtime

```
    r = BoundedResource(v, S(k))
    ────────────────────────────────────────────────────  [Resource-Use]
    Γ, D ⊢ consume(r) ⇓ (v, BoundedResource(v, k))

    budget_remaining = 0     (enforced at compile time; never reached at runtime)
```

---

## 5. Extension Composition

The six extensions compose independently because each operates on a different
dimension of the type:

```
    Γ ⊢ q : QueryResult
    Γ ⊢ q CONSUME AFTER 1 USE         (LinConn dimension)
    Γ ⊢ q WITH SESSION ReadOnly        (Session dimension)
    Γ ⊢ q EFFECTS { Read, Cite }       (Effect dimension)
    Γ ⊢ q IN TRANSACTION Committed      (World dimension)
    Γ ⊢ q PROOF ATTACHED Integrity      (Proof dimension)
    Γ ⊢ q USAGE LIMIT 100              (Budget dimension)
    ──────────────────────────────────────────────────────────────  [Compose]
    Γ ⊢ composed_query : ProvedResult (Box Committed QueryResult) IntegrityThm
    with linear connection, session protocol, effect bounds, and resource limit
```

The `Checker.idr` module validates all six constraints simultaneously by
composing individual check functions.

---

## 6. Invariants

1. **Linear safety:** A `LinConn n` is used exactly `n` times before closing. Enforced by QTT at compile time.
2. **Protocol compliance:** Session operations only succeed in valid states. Enforced by indexed types.
3. **Effect containment:** Actual effects ⊆ declared effects. Enforced by `Subsumes` proof.
4. **Scope isolation:** Data in `Box w₁` cannot be extracted without `InScope w₁` evidence.
5. **Proof integrity:** `ProvedResult` pairs are unforgeable — the proof must type-check.
6. **Budget monotonicity:** `BoundedResource n` can only decrease to `BoundedResource (n-1)`.
7. **Totality:** All Idris2 modules compile with `%default total` — no infinite loops, no partial functions.
8. **Zero axioms:** No `believe_me`, `assert_total`, or `assert_smaller` in proof code.
