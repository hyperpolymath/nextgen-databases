# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# GQL: A Narrative-First Query Language for Provenance-Aware Data

**Author:** Jonathan D.A. Jewell
**Version:** 1.0
**Date:** 2026-03-14
**Status:** Alpha (65% complete)

---

## Abstract

We present GQL (Glyph Query Language), the query language for Lithoglyph, a
multi-model database designed for domains where understanding *why* data exists
matters as much as the data itself. Traditional query languages treat data as
inert records: rows to be selected, filtered, and aggregated. GQL treats data
as *narrative artefacts*—entities with provenance (who added them), rationale
(why they were added), reversibility (how to undo them), and epistemological
metadata (how much they should be trusted). This paper presents GQL's narrative-
first design philosophy, its two-tier architecture (GQL for users, GQL-DT with
dependent types for developers), its mandatory provenance tracking, its
reversibility-by-default semantics, and its application to investigative
journalism, governance, and interactive documentary.

---

## 1. Introduction

### 1.1 The Narrative Gap in Database Systems

Every piece of data in a database has a story: who created it, why it was
created, what evidence supports it, and what would happen if it were removed.
Traditional databases discard this story at insertion time, storing only the
data itself. The narrative—the context that makes data meaningful—is relegated
to application code, external logs, or institutional memory.

This works when databases serve as accounting ledgers: the numbers speak for
themselves. But in domains where data is *contested*, *evolving*, or
*consequential*—investigative journalism, public policy, scientific research,
legal proceedings—the narrative is not ancillary. It is the primary value.

Consider an investigative journalist building a database of financial
transactions to support a story about fraud. For each entry, they need to
record:

- **Who added it?** (The journalist, a source, a scraping tool?)
- **Why?** (Primary evidence, corroboration, background context?)
- **How trustworthy is it?** (Official government record vs. anonymous tip?)
- **Can it be retracted?** (If the source recants, what happens?)
- **Who else has seen it?** (Audit trail for legal discovery.)

In SQL, all of this must be encoded as application-level conventions: extra
columns, audit tables, trigger-based logging. None of it is *required* by the
language. In GQL, all of it is *mandatory by grammar*.

### 1.2 Design Thesis

GQL's design thesis is:

> **The database is part of the story, not an opaque substrate.**

This thesis has six concrete implications, which form GQL's design pillars:

1. **Provenance by construction:** You cannot insert data without specifying
   who added it and why.
2. **Reversibility as first-class:** Every operation has a defined inverse,
   or is explicitly marked irreversible with justification.
3. **Constraints as ethics:** When constraints fail, GQL explains *why* the
   constraint exists, not just that it failed.
4. **Explain everything:** `EXPLAIN` returns not just query plans but
   constraint reasoning and provenance chains.
5. **Results carry provenance:** Query results optionally include metadata
   about who added each piece of data and when.
6. **Schema is narrative:** Schema changes are recorded events with rationale,
   not silent infrastructure updates.

### 1.3 Contributions

1. **Mandatory provenance** in query language grammar, not application
   conventions (Section 3).
2. **Reversibility-by-default** with proof-carrying inverses (Section 4).
3. **Two-tier design:** GQL (accessible) and GQL-DT (dependently typed) for
   different user populations (Section 5).
4. **PROMPT epistemological framework** for source trustworthiness assessment
   (Section 6).
5. **Interactive documentary** as a first-class database application pattern
   (Section 7).
6. **Formal verification** of schema evolution using Lean 4 and Idris2
   (Section 8).

---

## 2. Architecture

### 2.1 Lithoglyph's Multi-Model Design

Lithoglyph is a multi-model database supporting three data paradigms:

| Paradigm | GQL Syntax | Use Case |
|----------|-----------|----------|
| **Document** | `INSERT INTO collection { ... }` | Unstructured evidence, reports |
| **Edge** | `INSERT EDGE INTO relationship { ... }` | Connections between entities |
| **Relational** | `CREATE COLLECTION (...) WITH DEPENDENT_TYPES` | Structured, typed data |

GQL operates natively across all three paradigms. Unlike SQL (relational only)
or GraphQL (API layer), GQL is a *database-native* language that treats graphs,
documents, and relations as equal citizens.

### 2.2 Implementation Stack

| Layer | Language | Purpose |
|-------|----------|---------|
| Storage (Form.Blocks) | Forth | Fixed-size blocks, append-only journal |
| Data Model (Form.Model) | Forth | Collections, edges, schema, constraints |
| Bridge (Form.Bridge) | Zig | C-ABI bridge, WAL commit, block allocator |
| Runtime (Form.Runtime) | Factor | GQL parser, planner, executor |
| Normalizer | Factor + Lean 4 | FD discovery, normal forms, proof-carrying evolution |
| GQL-DT | Lean 4 | Dependent type checking for GQL-DT tier |
| Control Plane | Elixir/OTP | Sessions, supervision, clustering |

The choice of Forth for storage and Factor for the runtime reflects Lithoglyph's
design metaphor: "Forth code sculpts data onto disk, carving each operation
into permanent, auditable stone." Concatenative languages make the operation
sequence explicit—every action is a word on the stack, visible and auditable.

---

## 3. Mandatory Provenance

### 3.1 Provenance in Grammar

In SQL, provenance is optional. In GQL, it is syntactically mandatory:

```gql
-- SQL (provenance is absent)
INSERT INTO evidence (title) VALUES ('ONS Report');

-- GQL (provenance is required by grammar)
INSERT INTO evidence (title) VALUES ('ONS Report')
ADDED_BY "researcher_alice"
RATIONALE "Primary source for inflation analysis";
```

Omitting `ADDED_BY` or `RATIONALE` is a *syntax error*, not a best-practice
violation. This ensures that provenance is never accidentally omitted, even by
novice users or automated tools.

### 3.2 Provenance in Results

Query results can include provenance metadata:

```gql
SELECT title, source_url FROM evidence WITH PROVENANCE;

-- Returns:
-- { title: "ONS Report", source_url: "...",
--   _provenance: { actor: "researcher_alice",
--                  added_at: "2026-03-14T10:00:00Z",
--                  rationale: "Primary source for inflation analysis",
--                  journal_entry: 42 } }
```

### 3.3 Provenance Integrity

Provenance is stored in an append-only journal alongside the data. The journal
is the authoritative audit trail—it cannot be modified, only appended to.
Each journal entry records:

- **Actor:** Who performed the operation.
- **Timestamp:** When it was performed.
- **Operation:** What was done (INSERT, UPDATE, DELETE, SCHEMA_CHANGE).
- **Rationale:** Why it was done.
- **Inverse:** How to undo it (see Section 4).

---

## 4. Reversibility by Default

### 4.1 Every Operation Has an Inverse

GQL requires that every mutation operation has a defined inverse:

| Operation | Automatic Inverse |
|-----------|------------------|
| `INSERT` | `DELETE` with matching criteria |
| `UPDATE` | `UPDATE` with previous values |
| `DELETE` | `INSERT` with deleted data |
| Schema `ADD COLUMN` | Schema `DROP COLUMN` |
| Schema `DROP COLUMN` | Schema `ADD COLUMN` with data restoration |

Inverses are computed automatically and stored in the journal. At any point,
a user can roll back operations:

```gql
ROLLBACK JOURNAL ENTRY 42
RATIONALE "Source retracted claim";
```

### 4.2 Explicit Irreversibility

When an operation genuinely cannot be reversed (e.g., GDPR deletion, classified
material purge), GQL requires explicit acknowledgment:

```gql
DELETE FROM evidence WHERE id = "secret-doc"
IRREVERSIBLE BECAUSE "GDPR Article 17 right to erasure"
AUTHORISED_BY "data_protection_officer";
```

This creates a *tombstone* in the journal recording that data was permanently
deleted, by whom, and why—even though the data itself is gone.

---

## 5. Two-Tier Design

### 5.1 Tier 1: GQL (Accessible)

GQL's user-facing syntax is SQL-like with mandatory provenance:

```gql
INSERT INTO evidence (title, confidence)
VALUES ('ONS Data', 95)
ADDED_BY "researcher_alice"
RATIONALE "Official statistics";

SELECT claim, source, prompt_score
FROM evidence
WHERE prompt_score >= 80;
```

This tier performs runtime type checking and constraint validation. Errors
include explanations:

```
CONSTRAINT_VIOLATION:
  constraint: evidence.source_url UNIQUE
  reason: "Document with source_url already exists"
  constraint_rationale: "Each source entered once to prevent duplicate counting"
  suggestion: "Use UPDATE to modify existing document"
```

### 5.2 Tier 2: GQL-DT (Dependently Typed)

GQL-DT extends GQL with Lean 4-style dependent types for compile-time
verification:

```lean
INSERT INTO evidence (
  title : NonEmptyString,
  prompt_provenance : BoundedNat 0 100
)
VALUES (
  NonEmptyString.mk "ONS Data" (by decide),
  BoundedNat.mk 0 100 95 (by omega) (by omega)
)
RATIONALE "Official statistics"
WITH_PROOF {
  scores_in_bounds: by lithoglyph_prompt,
  provenance_tracked: by lithoglyph_prov
};
```

In GQL-DT:

- **Types carry proofs:** `BoundedNat 0 100` is a natural number with a
  *compile-time proof* that it is between 0 and 100.
- **NonEmptyString** is a string with a proof of non-emptiness.
- **WITH_PROOF** attaches formal theorems to operations.
- **Schema changes carry normalization proofs**: Adding a column can require
  proof that it preserves normal form.

### 5.3 When to Use Each Tier

| User | Tier | Reason |
|------|------|--------|
| Journalist | GQL | Intuitive SQL-like syntax, runtime safety |
| Researcher | GQL | Familiar syntax, provenance tracking |
| Database admin | GQL-DT | Schema evolution with formal guarantees |
| Application developer | GQL-DT | Compile-time query validation |
| AI agent | GQL-DT | Machine-verifiable proofs for trust |

---

## 6. PROMPT Epistemological Framework

### 6.1 Source Assessment

Lithoglyph integrates the PROMPT framework (Provenance, Relevance,
Objectivity, Method, Publication, Timeliness + Transparency) for source
quality assessment:

```gql
INSERT INTO evidence (
  title, source_url,
  prompt_provenance, prompt_relevance, prompt_objectivity,
  prompt_method, prompt_publication, prompt_timeliness
)
VALUES (
  'ONS CPI Data', 'https://ons.gov.uk/...',
  95, 90, 85, 92, 98, 88
)
ADDED_BY "researcher_alice"
RATIONALE "Primary statistical source";
```

PROMPT scores are first-class data, not application-level metadata. They can
be queried, aggregated, and used in constraint definitions:

```gql
-- Only trust highly-scored sources
SELECT * FROM evidence
WHERE prompt_overall >= 80
ORDER BY prompt_provenance DESC;

-- Constraint: minimum quality for publication
CREATE CONSTRAINT evidence_quality
  ON evidence
  CHECK (prompt_overall >= 60)
  RATIONALE "Published claims require minimum source quality";
```

---

## 7. Interactive Documentary

### 7.1 Motivation

Interactive documentary (i-doc) is a form of non-fiction storytelling that
allows audiences to navigate evidence and form their own conclusions, rather
than following a fixed linear narrative. Lithoglyph is purpose-built for i-doc
because its provenance-first design maps directly to the requirements of
transparent, navigable evidence presentation.

### 7.2 Multi-Perspective Navigation

GQL supports *navigation paths*—predefined routes through the evidence graph
tailored to different audiences:

```gql
CREATE NAVIGATION_PATH skeptic_path
  START FROM evidence WHERE prompt_method >= 90
  TRAVERSE supports OUTBOUND
  ORDER BY prompt_provenance DESC
  RATIONALE "For skeptical audiences: start with methodology";

CREATE NAVIGATION_PATH policymaker_path
  START FROM evidence WHERE prompt_publication >= 95
  TRAVERSE supports OUTBOUND
  ORDER BY prompt_timeliness DESC
  RATIONALE "For policymakers: start with authoritative, recent sources";
```

### 7.3 Boundary Objects

Following Star & Griesemer (1989), evidence items can serve as *boundary
objects*—artefacts that are shared across communities but interpreted
differently. GQL's provenance tracking naturally supports this: the same
evidence item carries multiple rationale entries from different actors,
preserving each community's interpretation without forcing consensus.

---

## 8. Formal Verification

### 8.1 Schema Normalisation

Lithoglyph's normaliser (implemented in Factor + Lean 4) provides formally
verified schema evolution:

- **Functional dependency discovery:** Automatically identifies FDs in data.
- **Normal form predicates:** Proves that schema satisfies 1NF, 2NF, 3NF,
  or BCNF.
- **Proof-carrying evolution:** Schema changes carry proofs that normalization
  is preserved (or intentionally violated with justification).

52 Lean 4 proofs verify normaliser correctness.

### 8.2 Idris2 ABI

Lithoglyph's ABI is formally specified in Idris2, following the hyperpolymath
ABI/FFI standard:

- 28 Idris2 proof files verify type safety of the ABI.
- Zig FFI bridge (19 functions) connects Forth storage to Factor runtime.
- Zero `believe_me` or `assert_total` in proof code.

---

## 9. Comparison with Existing Systems

| Feature | SQL | GraphQL | Cypher | GQL |
|---------|-----|---------|--------|-----|
| Provenance | Optional | No | No | **Mandatory** |
| Reversibility | Transactions | No | No | **Every operation** |
| Constraint explanation | Error codes | Error messages | Error messages | **Rationale + suggestion** |
| Source quality | Application-level | No | No | **PROMPT framework** |
| Dependent types | No | No | No | **GQL-DT tier** |
| Multi-model | Relational only | API layer | Graph only | **Document + Edge + Relational** |
| Schema evolution proofs | No | No | No | **Lean 4 verified** |
| Narrative navigation | No | No | No | **Navigation paths** |

---

## 10. Conclusion

GQL demonstrates that query languages can and should encode domain-specific
integrity requirements in their grammar, not delegate them to application
conventions. For domains where data provenance, source trustworthiness, and
auditability are primary concerns—journalism, governance, research, legal—
GQL's mandatory provenance and reversibility-by-default provide guarantees
that SQL-based systems cannot match without extensive application-level
engineering.

The two-tier design (GQL + GQL-DT) makes these guarantees accessible to both
non-technical users (who benefit from runtime checking and explanatory errors)
and developers (who benefit from compile-time verification and proof
attachment). The PROMPT framework and interactive documentary support
demonstrate that database systems can be active participants in knowledge
construction, not passive storage.

---

## References

1. Buneman, P. et al. (2001). "Why and Where: A Characterization of Data
   Provenance." *ICDT 2001*, 316–330.
2. Cheney, J. et al. (2009). "Provenance in Databases: Why, How, and Where."
   *Foundations and Trends in Databases*, 1(4), 379–474.
3. de Moura, L. & Ullrich, S. (2021). "The Lean 4 Theorem Prover and
   Programming Language." *CADE 2021*, 625–635.
4. Gaudenzi, S. (2013). "The Living Documentary: From Representing Reality to
   Co-creating Reality in Digital Interactive Documentary." PhD Thesis,
   Goldsmiths, University of London.
5. Star, S. L. & Griesemer, J. R. (1989). "Institutional Ecology, 'Translations'
   and Boundary Objects." *Social Studies of Science*, 19(3), 387–420.
6. ISO/IEC 39075:2024. "Information technology — Database languages — GQL."
   International Organization for Standardization.
