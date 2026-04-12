# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# KRL–SQL Compatibility Layer

**Version:** 0.1.0
**Date:** 2026-03-20

---

## 1. Purpose

This document defines how standard SQL (ISO 9075) concepts map to KRL's
pipeline syntax. The goal is twofold:

1. **Accessibility:** Users familiar with SQL can write queries against
   QuandleDB without learning KRL's pipeline syntax from scratch.
2. **Interoperability:** External tools (BI dashboards, ODBC/JDBC drivers)
   can issue SQL queries that are mechanically translated to KRL pipelines.

KRL is *not* a SQL dialect — it is a superset with fundamentally richer
semantics (equivalence types, provenance, dependent types). The SQL
compatibility layer covers the relational subset of KRL.

---

## 2. Translation Rules

### 2.1 SELECT … FROM … WHERE

```sql
-- SQL
SELECT name, crossing_number, jones_polynomial
FROM knots
WHERE crossing_number <= 10
  AND genus = 1
ORDER BY crossing_number ASC
LIMIT 20;
```

```krl
-- KRL translation
from knots
| filter crossing_number <= 10
| filter genus == 1
| sort crossing_number asc
| take 20
| return name, crossing_number, jones_polynomial
```

**Translation rules:**
- `SELECT fields` → `| return fields`
- `FROM source` → `from source`
- `WHERE pred` → `| filter pred`
- `AND` chains → multiple `| filter` stages (short-circuit semantics preserved)
- `ORDER BY expr [ASC|DESC]` → `| sort expr [asc|desc]`
- `LIMIT n` → `| take n`
- `OFFSET n` → `| skip n`
- `SELECT *` → `| return *`

### 2.2 Aggregation

```sql
-- SQL
SELECT crossing_number, COUNT(*) AS cnt
FROM knots
GROUP BY crossing_number
HAVING cnt > 5;
```

```krl
-- KRL
from knots
| group_by crossing_number
| aggregate count(*) as cnt
| filter cnt > 5
| return crossing_number, cnt
```

**Rules:**
- `GROUP BY expr` → `| group_by expr`
- `COUNT/MIN/MAX/AVG/SUM(expr)` → `| aggregate fn(expr)`
- `HAVING pred` → `| filter pred` (after aggregate)

### 2.3 Subqueries

```sql
-- SQL
SELECT * FROM knots
WHERE crossing_number IN (
    SELECT crossing_number FROM knots WHERE genus = 1
);
```

```krl
-- KRL
let genus_1_crossings = from knots
  | filter genus == 1
  | return crossing_number

from knots
| filter crossing_number in genus_1_crossings
```

**Rules:**
- `IN (SELECT …)` → `let` binding + `in` predicate
- Correlated subqueries → `let` with captured variables

### 2.4 Joins

KRL does not have explicit JOIN syntax — knot relationships are modelled
as equivalence queries and graph patterns instead. For SQL compatibility:

```sql
-- SQL join (relating knots by shared invariants)
SELECT K1.name, K2.name
FROM knots K1, knots K2
WHERE K1.jones_polynomial = K2.jones_polynomial
  AND K1.name != K2.name;
```

```krl
-- KRL (natural expression of the same query)
from knots
| find_equivalent via [jones]
| return source.name, target.name
```

**Rules:**
- Self-joins on invariant equality → `find_equivalent via [invariant]`
- Cross-joins → not directly supported (use `match` patterns for relationships)
- Foreign-key joins → `match (A)-[:REL]->(B)` graph pattern

### 2.5 SQL Functions → KRL Equivalents

| SQL | KRL | Notes |
|-----|-----|-------|
| `COUNT(*)` | `count(*)` | Identical |
| `MIN(expr)` | `min(expr)` | Identical |
| `MAX(expr)` | `max(expr)` | Identical |
| `AVG(expr)` | `avg(expr)` | Identical |
| `SUM(expr)` | `sum(expr)` | Identical |
| `COALESCE(a, b)` | `a ?? b` | Option unwrap with default |
| `CASE WHEN … THEN … END` | `match` expression | Pattern matching |
| `IS NULL` | `== none` | Option check |
| `IS NOT NULL` | `!= none` | Option check |
| `LIKE '%pat%'` | `contains(field, "pat")` | String matching |
| `CAST(x AS T)` | `x : T` | Type annotation |
| `DISTINCT` | `unique` | Deduplication |

---

## 3. SQL Features NOT Supported

These SQL features have no KRL equivalent because they conflict with
KRL's type-safe, provenance-carrying semantics:

| SQL Feature | Why Not in KRL | KRL Alternative |
|-------------|----------------|-----------------|
| `NULL` (three-valued logic) | KRL uses `Option[τ]` — explicit absence | `Option[τ]` with `none` |
| `UNION ALL` | Untyped bag union loses provenance | `merge` with provenance tracking |
| `INSERT/UPDATE/DELETE` | QuandleDB is read-only (invariants are computed) | Skein.jl REPL |
| `CREATE TABLE` | Schema is fixed (knots + invariants) | — |
| `ALTER TABLE` | Schema is fixed | — |
| `GRANT/REVOKE` | No access control model yet | — |
| Implicit type coercion | KRL is strongly typed | Explicit `x : T` |

---

## 4. Extensions Beyond SQL

KRL provides capabilities that have NO SQL equivalent:

### 4.1 Equivalence Queries (unique to KRL)

```krl
from knots
| find_equivalent "3_1" via [jones, genus]
| return equivalences with provenance
```

Returns structured `Equivalence[Knot]` records with proof derivations
and invariant provenance. SQL can only return boolean equality.

### 4.2 Path Queries (unique to KRL)

```krl
from diagrams as D
| find_path D ~> "3_1" via reidemeister
| return path, move_count
```

Finds explicit Reidemeister move sequences between diagram representations.

### 4.3 Dependent Type Annotations (unique to KRL)

```krl
-- Query result type depends on which invariants are requested
from knots
| filter crossing_number <= 10
| return name, crossing_number
  -- Result type: ResultSet[{name: String, crossing_number: Int}]
  -- The return clause DETERMINES the record type (dependent projection)
```

### 4.4 Provenance Tracking (unique to KRL)

Every query result can carry provenance metadata showing which
invariants were computed and at what confidence level.

---

## 5. Implementation Strategy

The SQL compatibility layer is implemented as a **syntactic frontend**
that parses SQL and emits a KRL AST. The KRL type checker and
evaluator then process the AST normally.

```
SQL input → SQL parser → KRL AST → Type checker → Evaluator → Result
                                         ↑
KRL input → KRL parser ─────────────────┘
```

The SQL parser is a **subset parser** — it accepts only the SQL features
that have KRL translations (§2). Unsupported features produce a clear
error message pointing the user to the KRL syntax for the equivalent
operation.

### 5.1 Type Safety

SQL queries are translated to **typed** KRL AST nodes. The type checker
runs on the KRL AST regardless of whether the query was written in SQL
or KRL. This means SQL queries get the same type-safety guarantees as
native KRL queries — including pipeline type preservation (§4 of
type-system.md).

### 5.2 Provenance

SQL queries automatically get provenance tracking. Even `SELECT *` queries
carry an implicit provenance annotation recording which columns were
accessed and from which invariant computations.
