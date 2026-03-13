# Epstein Files — Lithoglyph Ingest Tests & Benchmarks
#
# SPDX-License-Identifier: PMPL-1.0-or-later
# Author: Jonathan D.A. Jewell
# Created: 2026-03-13
#
# Extracted from the master pathway: bofig/docs/EPSTEIN-FILES-WORK-PATHWAY.md
# This file contains only the Lithoglyph-specific phases (2.1–2.5, 4.4, 5.2).

## Phase 2: Lithoglyph Ingest & Storage (Weeks 4–10)

### Step 2.1: Zig 0.15.2 HTTP API Migration (L1)

83 call sites need updating for the new Zig HTTP API.

**Tests:**
- [ ] T-ZIG-1: All 83 call sites compile with zig 0.15.2
- [ ] T-ZIG-2: HTTP server starts and responds to GET /health
- [ ] T-ZIG-3: GQL INSERT via HTTP returns 200 + created record ID
- [ ] T-ZIG-4: Concurrent 100-request stress test — no crashes

**Benchmarks:**
- [ ] B-ZIG-1: GQL INSERT latency — target: <5ms p99
- [ ] B-ZIG-2: Batch INSERT (1000 records) — target: <500ms total

### Step 2.2: Evidence Collection Schema (L3)

Collections: `bofig_evidence`, `bofig_claims`, `bofig_relationships`

**Tests:**
- [ ] T-EVD-1: CREATE bofig_evidence collection succeeds
- [ ] T-EVD-2: INSERT evidence record with all PROMPT dimensions
- [ ] T-EVD-3: QUERY evidence by SHA-256 hash (dedup lookup)
- [ ] T-EVD-4: QUERY evidence by entity name (cross-reference)
- [ ] T-EVD-5: All mutations have actor + rationale (Lithoglyph invariant)

### Step 2.3: Financial Transaction Collection (L4)

Schema: source, destination, amount, currency, date, instrument, intermediary

**Tests:**
- [ ] T-FTX-1: INSERT transaction record with full fields
- [ ] T-FTX-2: QUERY transaction chain (A→B→C) via GQL path traversal
- [ ] T-FTX-3: Aggregate: total flow between two entities
- [ ] T-FTX-4: Temporal: transactions within date range
- [ ] T-FTX-5: Anomaly: detect round-number patterns (e.g., exactly $10,000)

**Benchmarks:**
- [ ] B-FTX-1: 16,000 transaction inserts — target: <10 seconds
- [ ] B-FTX-2: Transaction chain query (depth 5) — target: <100ms

### Step 2.4: Entity Collection + Co-Reference Resolution (L5)

Alias tracking: "Jeffrey Epstein" = "J. Epstein" = "Epstein, Jeffrey"

**Tests:**
- [ ] T-ENT-1: CREATE entity with primary name
- [ ] T-ENT-2: ADD alias to existing entity
- [ ] T-ENT-3: MERGE two entities (logged in journal with rationale)
- [ ] T-ENT-4: REVERSE merge (undo co-reference error)
- [ ] T-ENT-5: QUERY all documents mentioning entity (across aliases)
- [ ] T-ENT-6: No orphaned aliases after merge/unmerge cycle

**Benchmarks:**
- [ ] B-ENT-1: 23,000 entity inserts with alias resolution — target: <60 seconds
- [ ] B-ENT-2: Entity lookup by any alias — target: <10ms

### Step 2.5: Docudactyl → Lithoglyph Ingest Bridge (D2 + L6)

Cap'n Proto → GQL INSERT with auto-PROMPT scoring.

**Tests:**
- [ ] T-BRG-1: Single Cap'n Proto StageResults → Lithoglyph evidence record
- [ ] T-BRG-2: PROMPT auto-scoring from extraction metadata:
  - OCR confidence 90+ → Provenance score 0.8+
  - Multiple corroborating documents → Replicability score increases
  - Court filing (official source) → Publication score 0.9+
- [ ] T-BRG-3: SHA-256 dedup: duplicate document skipped with log
- [ ] T-BRG-4: Batch import 1000 records — all arrive with provenance
- [ ] T-BRG-5: Actor="docudactyl-pipeline", Rationale includes run ID

**Benchmarks:**
- [ ] B-BRG-1: 10,000 records batch import — target: <30 seconds
- [ ] B-BRG-2: 3.2M records full import — target: <6 hours

---

## Phase 4: Temporal Credibility Model (L7) (Weeks 12–18)

Source reputation evolving over time.

**Tests:**
- [ ] T-TCR-1: New source starts at neutral credibility
- [ ] T-TCR-2: Source's claim independently verified → credibility increases
- [ ] T-TCR-3: Source caught in contradiction → credibility decreases
- [ ] T-TCR-4: Source retraction → credibility impact + retraction logged
- [ ] T-TCR-5: Time-travel: "What was this source's credibility on 2023-01-15?"
- [ ] T-TCR-6: Credibility affects PROMPT scores of all evidence from that source

---

## Phase 5: Cross-Investigation Linking (L8) (Weeks 16–22)

Shared evidence across investigations (Epstein ↔ Maxwell ↔ related cases).

**Tests:**
- [ ] T-XIL-1: Evidence in investigation A also relevant to investigation B → linked
- [ ] T-XIL-2: Entity appearing in both investigations → surfaced automatically
- [ ] T-XIL-3: New investigation inherits relevant evidence from existing investigations
- [ ] T-XIL-4: Access controls per investigation

---

## Completion Tracker (Lithoglyph Phases Only)

| # | Step | Status | Tests | Benchmarks |
|---|------|--------|-------|------------|
| 2.1 | Zig API Migration | **DONE** | 0/4 | 0/2 |
| 2.2 | Evidence Schema | **DONE** | 0/5 | — |
| 2.3 | Financial Txn Collection | TODO | 0/5 | 0/2 |
| 2.4 | Entity + Co-Ref | TODO | 0/6 | 0/2 |
| 2.5 | Ingest Bridge | TODO | 0/5 | 0/2 |
| 4.4 | Temporal Credibility | TODO | 0/6 | — |
| 5.2 | Cross-Investigation | TODO | 0/4 | — |

**Totals: 35 tests, 8 benchmarks | Current: 0 tests written, 0 benchmarks run**

## Cross-References

- **Full pipeline pathway:** `bofig/docs/EPSTEIN-FILES-WORK-PATHWAY.md`
- **Master integration plan:** `bofig/docs/INTEGRATION-PLAN.md`
- **Lithoglyph integration role:** `docs/INTEGRATION-PLAN-LITHOGLYPH.md` (this repo)
- **GQL dependent types spec:** `spec/gql-dependent-types.md` (this repo)
