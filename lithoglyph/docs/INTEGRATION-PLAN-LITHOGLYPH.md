# Lithoglyph Integration Plan — Pipeline Role
#
# SPDX-License-Identifier: PMPL-1.0-or-later
# Author: Jonathan D.A. Jewell
# Created: 2026-03-13
#
# Extracted from the master integration plan: bofig/docs/INTEGRATION-PLAN.md

## Lithoglyph's Role in the Pipeline

Lithoglyph is the **provenance layer**. It stores all evidence with full audit
trail, reversibility, and PROMPT scoring. It sits between Docudactyl (extraction)
and Bofig (evidence graph navigation).

```
Raw Documents (200K+ files)
  → Docudactyl   (HPC extraction: OCR, NER, metadata, classification)
    → Lithoglyph (audit-grade storage: provenance, reversibility, PROMPT)
      → Bofig    (evidence graph: claims, relationships, navigation)
```

## Lithoglyph Tasks (from Integration Plan)

| # | Task | Priority | Effort | Notes |
|---|------|----------|--------|-------|
| L1 | Zig 0.15.2 HTTP API migration (83 call sites) | Critical | Medium | **COMPLETE** — Reader/Writer pattern applied |
| L2 | Lith → Lithoglyph rename (Google trademark) | Critical | Small | **COMPLETE** — formdb-http/ → lith-http/ |
| L3 | Evidence collection schema for bofig | High | Small | **COMPLETE** — 5 collections + 5 GQL test vectors |
| L4 | Financial transaction collection | High | Small | source, destination, amount, date, instrument, intermediary |
| L5 | Entity collection + co-reference resolution | High | Medium | Person/org/location entities with alias tracking |
| L6 | Ingest bridge: Docudactyl Cap'n Proto → GQL INSERT | High | Medium | Batch import with auto-PROMPT scoring from extraction metadata |
| L7 | Temporal credibility model | Medium | Medium | Source reputation updates over time (retractions, discrediting) |
| L8 | Cross-investigation linking | Medium | Small | Shared evidence collections, automatic surfacing |
| L9 | ControlPlane clustering (Elixir/OTP) | Low | Large | Multi-node Lithoglyph for scale |

## Key Guarantees Lithoglyph Provides

- Every mutation has actor + rationale (accountability)
- Reversible operations (retractions with explanation)
- Time-travel queries ("what did we know on date X?")
- PROMPT scores as first-class citizens
- Constraints-as-ethics (invalid evidence relationships rejected with explanation)
- Dependent-type proofs (GQL-DT) for score bounds

## Integration Points Involving Lithoglyph

### Integration 1: Docudactyl → Lithoglyph (D2 + L6)

```
Docudactyl Cap'n Proto output
  → Adapter (D2) serializes to GQL INSERT statements
    → Lithoglyph ingest bridge (L6) batch-imports with:
      - Auto-PROMPT scoring from extraction confidence
      - SHA-256 dedup against existing evidence
      - Actor="docudactyl-pipeline", Rationale="Batch extraction run {id}"
      - Provenance: source file path, extraction timestamp, OCR confidence
```

### Integration 2: Lithoglyph → Bofig (L3 + B5)

```
Lithoglyph evidence/entity/transaction collections
  → Bofig GenServer (B5) queries Lithoglyph via GQL
    → Maps to ArangoDB graph (Phase 2) or direct Lithoglyph queries (Phase 3)
    → PROMPT scores flow from Lithoglyph → bofig UI
    → Provenance metadata available on hover/click in UI
```

### Integration 3: Entity Resolution Loop (D3/D4/D5 → L5 → B1)

```
Docudactyl NER extracts raw entities
  → Lithoglyph stores with alias tracking (L5)
    → Bofig entity resolution (B1) merges aliases
    → Merge decision logged in Lithoglyph journal with rationale
    → Reversible if co-reference was incorrect
```

### Integration 4: Financial Flow Analysis (D4 → L4 → B2)

```
Docudactyl extracts transactions from bank records (D4)
  → Lithoglyph financial_transactions collection (L4)
    → Bofig GraphQL: transactionChain(entityId, depth) (B2)
```

### Integration 5: Temporal Reconstruction (D3 → L7 → B3)

```
Docudactyl extracts dates from all documents
  → Lithoglyph stores with temporal metadata
    → Bofig timeline view (B3):
      - What happened when / what was known when
      - Source credibility at each point in time (L7)
```

## Phase Assignment

Lithoglyph work spans **Phase A (Foundation)** through **Phase D (Scale & Trust)**:

- **Phase A (Weeks 1-4):** L1 (Zig migration), L2 (rename), L3 (evidence schema)
- **Phase B (Weeks 5-8):** L4 (financial collection), L5 (entity collection), L6 (ingest bridge)
- **Phase C (Weeks 9-14):** (no Lithoglyph-primary tasks)
- **Phase D (Weeks 15-20):** L7 (temporal credibility), L8 (cross-investigation linking)

## Cross-References

- **Master plan:** `bofig/docs/INTEGRATION-PLAN.md`
- **Epstein worked example:** `bofig/docs/EPSTEIN-FILES-WORK-PATHWAY.md`
- **Epstein Lithoglyph phases:** `docs/EPSTEIN-INGEST-TESTS.md` (this repo)
- **GQL dependent types spec:** `spec/gql-dependent-types.md` (this repo)
