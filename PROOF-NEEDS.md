# PROOF-NEEDS.md — nextgen-databases

## Current State

- **src/abi/*.idr**: YES (in lithoglyph) — `BofigEntities.idr`, `GQLdt/ABI/Foreign.idr`
- **Dangerous patterns**: 0 (4 references are documentation asserting "no believe_me" invariant)
- **LOC**: ~202,000 (Rust + Idris2)
- **ABI layer**: Lithoglyph has Idris2 ABI with constructive proofs, explicit no-believe_me policy

## What Needs Proving

| Component | What | Why |
|-----------|------|-----|
| VeriSimDB WAL correctness | Write-ahead log guarantees durability and ordering | WAL bugs cause data loss — the worst database bug |
| VeriSimDB transaction isolation | ACID properties hold under concurrent access | Isolation violations corrupt data silently |
| VeriSimDB ZKP bridge | Zero-knowledge proof generation is sound | Unsound ZKP breaks semantic verification |
| VeriSimDB HNSW index | Vector similarity search returns correct nearest neighbours | Wrong results from vector search corrupt ML pipelines |
| VeriSimDB query planner | Query optimization preserves result equivalence | Optimized query must return same results as unoptimized |
| VeriSimDB drift detection | Drift detector correctly identifies schema changes | Missed drift causes silent data corruption |
| Lithoglyph entity proofs | Extend BofigEntities constructive proofs | Current proofs cover basic entities; need full coverage |
| QuandleDB algebraic laws | Quandle operations satisfy rack/quandle axioms | Mathematical structure must be correct by construction |

## Recommended Prover

**Idris2** — Lithoglyph already has constructive Idris2 proofs. VeriSimDB WAL and transaction proofs fit naturally. ZKP soundness may need **Coq** for deeper cryptographic proofs.

## Priority

**HIGH** — VeriSimDB is the standard database across the ecosystem. WAL correctness and transaction isolation are critical — bugs here corrupt data in every downstream project. The ZKP bridge is security-critical.

## Template ABI Cleanup (2026-03-29)

Template ABI removed -- was creating false impression of formal verification.
The removed files (Types.idr, Layout.idr, Foreign.idr) contained only RSR template
scaffolding with unresolved {{PROJECT}}/{{AUTHOR}} placeholders and no domain-specific proofs.
