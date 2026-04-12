# KRL Design: SQL Landscape Research — 2026-02-22
## Comprehensive Survey for QuandleDB Query Language Design

**Date:** 2026-02-22
**For:** nextgen-databases/quandledb
**Agent:** Claude Opus 4.6
**Status:** Research complete — design phase next

---

## EXECUTIVE SUMMARY

**SQL is the wrong paradigm for QuandleDB.** The right foundation is a synthesis of:

1. **egglog** — equality saturation over Datalog (handles equivalence classes natively)
2. **Spivak's categorical data model** — functorial data migration, schema as category
3. **HoTT identity types** — paths = equivalences (from HoTTSQL paper)
4. **Surfaced through:** PRQL-style pipeline syntax + Cypher-style graph pattern matching

The closest existing system is **egglog** (PLDI 2023). The theoretical foundation is **HoTTSQL's univalent semantics**. KRL should build on both.

---

## Part 1: What's Legitimately Wrong with SQL

### NULL Handling (Three-Valued Logic)
- NULL conflates "unknown," "inapplicable," "missing," "not yet entered" into one marker
- `NULL = NULL` evaluates to UNKNOWN, not TRUE
- `NOT IN` with NULLs produces surprising empty results
- Codd himself proposed two kinds of null (A-marks/I-marks) — SQL never adopted this
- Forces optimizers to be conservative (Guagliardo & Libkin showed real DBs return incorrect results due to NULL bugs)

### Bag Semantics vs Set Semantics
- SQL operates on bags (multisets), not sets — departure from Codd's relational model
- Union is no longer idempotent; DISTINCT is an expensive band-aid
- HoTTSQL proved bags can be modeled cleanly via univalent types (700+ lines Coq reduced to 40)

### Composability (SQL's Most Damning Flaw)
- Neumann & Leis (CIDR 2024): SQL is "a functional programming language that lacks parameters for functions"
- Cannot pass a relation as an argument to a view definition
- Cannot parameterize a query fragment
- CTEs help readability but are just named subqueries — can't be parameterized
- **QUEL was more composable** but lost to SQL because IBM shipped DB2 and Stonebraker didn't show up to the ANSI committee

### Impedance Mismatch
- SQL types don't map cleanly to programming language types
- ORM-induced slowdowns of 2.6x-5x confirmed by research
- The real problem: SQL forces a different paradigm from the host language

### Type System Weakness
- No sum types, no product types beyond rows, no generics, no type inference
- CAST is explicit and lossy; implicit coercions vary by vendor
- No standard way to define custom types with invariants

### String-Based Injection by Design
- Queries are strings where structure and data are concatenated
- The "default, most obvious way" to use SQL is vulnerable
- Prepared statements fix it in practice but the design is fundamentally flawed

### Other Issues
- ORDER BY only at outer query
- WITH RECURSIVE is ugly and limited
- Temporal data support abysmal (SQL:2011 exists, few implement it)
- Window functions powerful but syntax baroque
- GROUP BY / HAVING distinction is weird
- Date/time handling is a mess across implementations
- No built-in version/provenance tracking
- Vendor fragmentation despite "standard"

---

## Part 2: Every Notable Alternative and What's Wrong with THEM

### QUEL (Ingres, 1976)
- **Good:** More composable, based on tuple relational calculus
- **Dead:** SQL won on market power (IBM), not technical merit. Stonebraker agreed SQL was worse.
- **Lesson:** Technical superiority doesn't guarantee adoption. But niche domains CAN sustain better languages.

### Datalog
- **Good:** Declarative, naturally recursive, composable, clean formal semantics
- **Bad:** No standard for aggregation/negation/updates, limited ordered data support
- **Key:** egglog (PLDI 2023) unifies Datalog with equality saturation — directly relevant to QuandleDB

### SPARQL
- **Good:** Powerful pattern matching over graphs
- **Bad:** Extremely verbose, schema-less means typos return empty results silently

### Cypher (Neo4j) / GQL (ISO 39075:2024)
- **Good:** ASCII-art pattern matching `(a)-[:KNOWS]->(b)` is genuinely intuitive
- **Bad:** Limited analytics, performance degrades on large traversals
- **GQL** is first new ISO DB language since SQL (1987). Adds quantified path patterns.
- **Relevant:** Knot diagrams ARE graphs. Reidemeister moves ARE graph rewrites.

### PRQL (Pipelined Relational Query Language)
- **Good:** Pipeline syntax dramatically more readable. Compiles to SQL. Written in Rust.
- **Bad:** Still relational — no equivalence classes
- **Lesson:** Pipeline syntax is strictly superior to SQL's inside-out evaluation order

### Malloy (Google / Lloyd Tabb)
- **Good:** Semantic modeling. Created by Looker founder from frustration with SQL.
- **Bad:** Not an official Google product. No support commitment. Limited adoption.

### EdgeQL (EdgeDB, now "Gel")
- **Good:** Modern SQL done right, object-relational model, unified typing
- **Bad:** Hard to get started (TLS plumbing), doc gaps at complexity, write contention

### FQL (Fauna) — DEAD
- **SHUT DOWN May 2025.** Steep learning curve, proprietary, couldn't raise capital.
- **Lesson:** Proprietary query languages die with their companies. Design for openness.

### SurrealQL (SurrealDB)
- **Good:** Multi-model with SQL-like syntax
- **Bad:** Lack of type safety, SDK limitations, limited maturity

### KQL (Kusto / Azure) — NAME COLLISION [Resolved]
- **Good:** Pipeline syntax for log analytics
- **Bad:** Read-only, can't INSERT/UPDATE, Azure lock-in
- **Note:** Previously shared acronym with our language. Resolved by renaming our language to KRL (Knot Resolution Language).

### DuckDB SQL Extensions
- **Right:** Community extensions (6M downloads/week), SQL-only extensions, SQL/PGQ graph queries outperform Neo4j 10-100x
- **Lesson:** SQL's extensibility CAN work if done right

### Others
- **Gremlin:** Imperative graph traversal. Verbose. Less optimizer freedom.
- **MQL (MongoDB):** Schema-free = no compile-time safety. Aggregation pipeline unreadable.
- **AQL (ArangoDB):** Multi-model but small community. BSL 1.1 license change (2024).
- **PartiQL (AWS):** SQL over everything. Tightly coupled to AWS.
- **CQL (Cassandra):** No JOINs, no ad hoc aggregations. Looks like SQL, can't do SQL.
- **PromQL/InfluxQL/Flux:** Time-series specific. Flux was deprecated — language churn cautionary tale.

---

## Part 3: Academic/Theoretical Criticisms

### Codd vs SQL
SQL departs from Codd's relational model: bags not sets, NULLs, ordering, duplicate column names, non-1NF data (JSON/arrays).

### Third Manifesto (Date & Darwen)
- SQL's problems are NOT the relational model's problems — they're SQL's
- **Tutorial D** shows "SQL done right": proper types, no NULLs, set semantics, composability
- Remains academic/pedagogical, no production implementation

### Category Theory Approaches (Spivak)
- Schema = small category. Instance = set-valued functor. Query = natural transformation.
- **CQL** (Categorical Query Language) — open-source IDE, active development
- Functorial data migration handles projections/unions/joins over ALL tables simultaneously
- **Directly applicable:** Quandles are algebraic structures. Category theory IS the language for algebraic structure relationships.

### HoTTSQL (Chu et al., PLDI 2017)
- SQL semantics formalized via homotopy type theory
- Relations as functions from tuples to univalent types
- Bag equality proved via univalence axiom (700+ lines Coq → 40 lines)
- **Critical insight for KRL:** Equality is not binary. Multiple distinct paths (proofs of equality) between objects. The space of equivalences has structure. THIS IS EXACTLY KNOT EQUIVALENCE.

### egglog (PLDI 2023)
- Merges Datalog with equality saturation
- E-graph compactly represents exponentially many equivalent terms
- Systems reimplemented in egglog are faster, simpler, fix bugs
- PLDI 2025 tutorial scheduled (growing adoption)
- **THIS MAY BE THE SINGLE MOST RELEVANT PARADIGM FOR QUANDLEDB**
- An e-graph IS a database of equivalence classes = a knot database

### Deductive Databases
- Souffle (static analysis), Google Mangle (AI reasoning), Datalevin (general-purpose Datalog)
- Revival driven by static analysis, AI reasoning, program optimization

---

## Part 4: What SQL Gets RIGHT (Don't Throw Away)

1. **Declarative semantics** — say what, not how. Enables optimizer freedom.
2. **50 years of optimizer research** — join reordering, predicate pushdown, index selection
3. **Ecosystem** — tools, tutorials, books, Stack Overflow, monitoring, migration tools
4. **ACID transactions** — atomic, consistent, isolated, durable
5. **The standard** — imperfect but exists; multiple vendors implement it
6. **Window functions** — running totals, rankings, moving averages in single pass
7. **CTEs** — break complex queries into named stages

---

## Part 5: The QuandleDB Domain Problem

### The Core Challenge
QuandleDB stores mathematical structures where the fundamental operation is *equivalence under transformation*. Two knots may look completely different but be the same (related by Reidemeister moves). SQL's `WHERE x = y` is syntactic/value equality. QuandleDB needs *semantic* equality.

### Scale
- KnotInfo: 350 million prime knots up to 19 crossings, 1.9 billion at 20
- 17,528 unresolved 20-crossing knots that resist all known invariants
- Multiple invariants per knot (Alexander, Jones, Khovanov, etc.)

### Relevant Query Paradigms

| Paradigm | Relevance | How |
|----------|-----------|-----|
| **Pattern matching** (FP) | High | Decompose knot diagrams by structure |
| **Unification** (Prolog) | High | Find structural constraints, variable binding |
| **Term rewriting** | Critical | Reidemeister moves ARE rewrite rules |
| **Category theory** (Spivak) | Critical | Quandles are algebraic structures in categories |
| **HoTT paths** | Critical | Paths = equivalences, space of equivalences has structure |
| **Equality saturation** (egglog) | Critical | E-graphs ARE databases of equivalence classes |
| **Provenance semirings** | High | Track which invariants led to equivalence determination |

---

## Part 6: What KRL Should Borrow vs Avoid

### Borrow
| Source | What |
|--------|------|
| SQL | Declarative semantics, optimizer freedom, transactions |
| PRQL | Pipeline syntax (`from ... | filter ... | aggregate ...`) |
| Cypher/GQL | ASCII-art pattern matching for graph structures |
| Datalog | Recursive queries, rule-based reasoning |
| egglog | Equality saturation, e-graph equivalence classes |
| CQL (Spivak) | Functorial data model, schema-as-category |
| HoTT | Identity types as equality primitive, paths between objects |
| Tutorial D | No NULLs, proper types, set semantics by default |

### Avoid
| Anti-Pattern | Source | Why |
|-------------|--------|-----|
| String-based queries | SQL | Injection by design |
| NULLs / three-valued logic | SQL | Use Option types |
| Bag semantics by default | SQL | Sets, with explicit multiset |
| Pseudo-English syntax | SQL | Consistent algebraic syntax |
| Vendor lock-in / proprietary | FQL | Fauna died, proving the risk |
| Language churn | Flux | Deprecating your own language burns users |
| Schemaless by default | MongoDB/SPARQL | Silent failures on typos |

---

## Part 7: Proposed KRL Architecture

1. **Foundation:** Category-theoretic data model (Spivak). Schema = category, instance = functor.
2. **Equality model:** HoTT identity types. `x == y` returns a *type* (possibly empty, possibly inhabited, possibly multiply inhabited). "These knots are equivalent, and here are the equivalences."
3. **Query syntax:** Pipeline-based (PRQL) + pattern matching (FP) + ASCII-art graph patterns (Cypher)
4. **Recursion:** Datalog-style fixed-point with equality saturation (egglog). Database maintains e-graphs.
5. **Type system:** Dependent types for invariants. Leverage Lean's mathlib quandle formalization.
6. **No NULLs:** Option types.
7. **Provenance:** Built-in semiring annotations. Every result carries derivation metadata.
8. **Composability:** First-class. Queries are values. Named, parameterized, composed.

### Honest Risk Assessment
- Building a new query language is enormous
- Technical superiority doesn't guarantee adoption (the QUEL problem)
- **Mitigations:** Compile to SQL where possible, specialize where necessary, target the niche (mathematicians value correctness), leverage existing infrastructure (egglog/Rust, CQL/Java, DuckDB/C++)

---

## Sources

### SQL Criticisms
- Guagliardo & Libkin — Formal Semantics of SQL Queries
- Ricciotti et al. — Formalization of SQL with Nulls
- Neumann & Leis — A Critique of Modern SQL (CIDR 2024)
- Jeff Atwood — ORM: Vietnam of Computer Science

### Key Papers
- HoTTSQL (Chu et al., PLDI 2017) — https://arxiv.org/abs/1607.04822
- egglog (PLDI 2023) — https://arxiv.org/abs/2304.04332
- Spivak — Functorial Data Migration — https://arxiv.org/abs/1009.1166
- CQL — https://categoricaldata.net/CQL/
- GQL ISO Standard — https://www.iso.org/standard/76120.html

### Domain (Knot Theory)
- KnotInfo — https://knots.dartmouth.edu/
- Knot Atlas — https://katlas.org/wiki/The_Take_Home_Database
- Lean mathlib quandles — https://leanprover-community.github.io/mathlib4_docs/Mathlib/Algebra/Quandle.html
- Data-Driven Knot Invariants (2025) — https://arxiv.org/html/2503.15103v1

---

*Preserved to ~/Desktop/ and nextgen-databases/quandledb/docs/design/*
