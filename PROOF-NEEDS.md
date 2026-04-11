# PROOF-NEEDS.md — nextgen-databases

## Current State (Updated 2026-04-11 — V3/V4 L4 DONE)

- **VeriSimDB ABI**: `verisimdb/src/abi/` — `Types.idr`, `Layout.idr`, `Foreign.idr` (873 LOC, genuine domain ABI)
- **Lithoglyph ABI**: `lithoglyph/` — `BofigEntities.idr`, `GQLdt/ABI/Foreign.idr`
- **Dangerous patterns**: 0 (4 references are documentation asserting "no believe_me" invariant)
- **LOC**: ~202,000 (Rust + Idris2)
- **Connector Obj.magic casts**: ELIMINATED 2026-04-10 — 5 ReScript connectors now use typed externals

## What Needs Proving

### P0 — Critical (require Lean4/TLA+/Coq — not I2)

| # | Component | Prover | Notes |
|---|-----------|--------|-------|
| V1 | Octad coherence invariant | I2 | 8 modalities mutually consistent post-operation |
| V2 | VQL type inference soundness | Cq/L4 | Bidirectional inference correct |
| **V3** | **VQL subtyping transitivity + decidability** | **L4** | **DONE 2026-04-11** — `verisimdb/verification/proofs/lean4/VCLSubtyping.lean` |
| **V4** | **Raft consensus safety** | **L4** | **DONE 2026-04-11** — `verisimdb/verification/proofs/lean4/RaftSafety.lean` (single-node; distributed in TLA+) |
| V5 | Transaction atomicity | TLA | All-or-nothing across 8 modalities |

### P1 — High

| # | Component | Prover | Notes |
|---|-----------|--------|-------|
| V6 | WAL integrity | L4 | CRC, replay idempotence, segment ordering |
| **V7** | **Provenance chain immutability** | **Ag** | **DONE 2026-04-11** — `verisimdb/verification/proofs/agda/ProvenanceChain.agda` |
| V8 | Drift metric correctness | Iz | Detection algorithm numerical bounds |

### P2 — Standard (I2 actionable)

| # | Component | Prover | Notes |
|---|-----------|--------|-------|
| V11 | Connector type safety | I2 | Obj.magic eliminated; Idris2 proof of typed external shapes |
| V12 | FFI pointer validity + memory ownership | I2 | `verisimdb/src/abi/Foreign.idr` lifetime model |

Note: V9/V10 require TLA+ (not I2).

## Recommended Prover

**Idris2** for V11/V12 (P2, I2-actionable). V0-V8 require Lean4/Agda/Isabelle/TLA+ specialists.

## Priority

**MEDIUM** (was HIGH) — V1-V8 require non-Idris2 provers. V11/V12 (I2/P2) are the remaining I2-actionable items; Obj.magic already eliminated from connectors. WAL/transaction/consensus remain open for L4/TLA+ sessions.
