# Proof Status — VeriSimDB

<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) -->

Tracking status of formal verification proofs for the VeriSimDB cross-modality octad database.

Obligations catalogued in `developer-ecosystem/standards/docs/proofs/spec-templates/T1-critical/verisimdb.md`.

## Policy

- **No** `believe_me`, `assert_total`, `postulate`, `sorry`, `Admitted` in fixable positions.
- All proofs are constructive.
- `%default total` in all Idris2 files.
- Idris2 for type-level / constructive proofs; TLA+ for concurrent + adversarial state-machine properties; Lean4 for the remaining numeric/induction-heavy obligations.

## Proof Inventory

### Idris2

| File | LOC | Properties | Obligation | Status |
|------|-----|------------|------------|--------|
| `verification/proofs/idris2/OctadCoherence.idr` | 327 | 8 modalities + 3 irredundant cross-modality invariants; `opPreservesCoherence` for all 6 Ops; `opsPreserveCoherence` for any Op sequence | **V1** | COMPLETE 2026-04-17 (`e2e5d9b`) |
| `verification/proofs/idris2/DriftMetric.idr` | ~140 | Hamming-distance drift is a metric: reflexivity, symmetry, triangle inequality; threshold-detection soundness + completeness | **V8** | COMPLETE 2026-04-17 (`182cc7c`) |
| `verification/proofs/idris2/ConnectorSafety.idr` | ~200 | Schema + ValidatedValue + total validator; every JSON → typed conversion is schema-checked by construction (Obj.magic elimination) | **V11** | COMPLETE 2026-04-17 (`95c3867`) |
| `verification/proofs/idris2/FFIOwnership.idr` | ~100 | `Owned` ownership-state token, non-null deref witness, and freeability restricted to `Alive` so double-free is uninhabited by type | **V12** | COMPLETE 2026-04-17 (Codex replay-checked) |

### Lean4

| File | LOC | Properties | Obligation | Status |
|------|-----|------------|------------|--------|
| `verification/proofs/lean4/VCLTypeSoundness.lean` | ~300 | Query-core progress + preservation + multi-step soundness + synth/check soundness for `VCLBidir`-shaped typing | **V2** | COMPLETE 2026-04-17 (Codex replay-checked with `lean` + `lake build`) |
| `verification/proofs/lean4/VCLSubtyping.lean` | ~200 | Structural subtype transitivity + decidability for core VCL types | **V3** | COMPLETE 2026-04-17 (Codex replay-checked with `lean` + `lake build`) |
| `verification/proofs/lean4/RaftSafety.lean` | ~260 | Commit monotonicity, append isolation, WF preservation, single-node log matching | **V4** | COMPLETE 2026-04-17 (Codex replay-checked with `lean` + `lake build`) |
| `verification/proofs/lean4/WALIntegrity.lean` | ~200 | Sequence monotonicity, CRC validity model, replay compositionality, checkpoint idempotence | **V6** | COMPLETE 2026-04-17 (Codex replay-checked with `lean` + `lake build`) |

### TLA+

| File | States | Depth | Properties | Obligation | Status |
|------|--------|-------|------------|------------|--------|
| `verification/proofs/tlaplus/OctadAtomicity.tla` | 134,160 | 19 | Atomicity (COMMITTED⇒all 8; ABORTED⇒none), NoObservablePartial, StatusMonotone, EveryTxnResolves (liveness) | **V5** | COMPLETE 2026-04-17 (`9d3dfd8`) |
| `verification/proofs/tlaplus/Normalizer.tla` | 84 | 2 | SourceIsMaximal, NormalizeIdempotent, PostStepNoDrift, FixedPointStable, Convergence (`<>[]~HasDrift`) | **V9** | COMPLETE 2026-04-17 (`81e1d52`) |
| `verification/proofs/tlaplus/Serializability.tla` | 33 | 7 | NoSharedLocks, LocksOnlyWhileActive, ActiveHoldsFullAccessSet, CommitLogInjective/Sound, NoConcurrentConflict, EveryTxnCommits | **V10** | COMPLETE 2026-04-17 (`94aa56f`, hardened `2390e52`) |

Model-checked via `just verify-tlaplus` (Eclipse Temurin 21 JRE via podman-ephemeral container; no host Java install needed on Fedora Atomic). Regression-gated by `.github/workflows/verify-tlaplus.yml` on every push/PR touching `verisimdb/verification/proofs/tlaplus/**`.

## Remaining Debt

None in the tracked V1-V12 set as of 2026-04-17 replay checks.

## Notes

- **Lean4 replay check**: `VCLTypeSoundness.lean`, `VCLSubtyping.lean`, `RaftSafety.lean`, and `WALIntegrity.lean` all pass direct `lean` checks and package-level `lake build` under Lean 4.16.0 on this host.
- **V10 scenario**: the committed scenario uses partial conflicts (t1/t2 disjoint, t3 shares with both) to actually exercise concurrency — TLC reaches states with multiple simultaneously-ACTIVE transactions, so `NoConcurrentConflict` is non-vacuous.
- **Podman recipe**: `just verify-tlaplus` fetches `tla2tools.jar` to `~/.local/share/` on first run and executes TLC in an `eclipse-temurin:21-jre` container. Works identically on Fedora Atomic (this host) and any machine with podman. Host Java is used if present.
