<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
# Proof Needs — verisim-modular-experiment

## Central obligation

**Claim:** There exists a subset `Core ⊆ Octad` and a federation contract
`F` such that, for every federation `S = Core ⊎ {external shapes honouring F}`,
VCL's consonance judgements on `S` are sound — i.e. no weaker than on
`Core` alone, and equivalent to the full octad for claims that stay within
shapes present in `S`.

**Or the negation:** No such `Core` and `F` exist, and the octad is
indivisible w.r.t. VCL's consonance guarantees.

Either resolution is acceptable. The experiment succeeds by *deciding*
which holds.

## Subordinate obligations

1. **Core closure.** Consonance claims purely over `Core` are verifiable
   without appeal to federated shapes.

2. **Federation soundness.** If external shape `E` honours contract `F`,
   then VCL claims crossing the `Core`/`E` boundary are sound relative to
   `E`'s externally-verified invariants.

3. **Degradation honesty.** For every shape omitted from a federation, the
   guarantees weakened by that omission are enumerated and documented.

4. **Non-interference.** Federating shape `E1` does not silently weaken
   claims about shape `E2` or about `Core`.

## Proof stack (intended)

- Idris2 for the federation contract ABI (per hyperpolymath standard)
- VCL's existing proof apparatus for consonance claims
- Zig FFI at the external-shape boundary

## Status (updated 2026-04-05)

**Central obligation — positive direction:** runtime-discharged for the
minimal case. Core = {Semantic, Temporal, Provenance} + one Federable
peer (Vector) honouring all 5 contract clauses gives aggregate-drift
numerically equal to the monolithic full-octad computation on the same
data (24/24 parity assertions).

**Subordinate obligation 1 (Core closure):** partially discharged.
VerisimCore smoke tests (25/25) show that Core-only operation —
enrichment, attestation, verification, Identity Persistence — is
sound without any federated shapes. Consonance claims over Core-only
shapes (i.e. not crossing boundaries) are verifiable.

**Subordinate obligation 2 (Federation soundness):** runtime-discharged
for single-peer case. Federated drift equals monolithic drift. See
`docs/SEAMS.adoc` for the ABI↔impl alignment that this rests on.

**Subordinate obligation 3 (Degradation honesty):** structurally satisfied.
Two independent soundness routes documented:
  (a) Clause 1 renormalisation → threshold-preserving reduction.
  (b) Absent-pair convention `d(⊥,·)=0` → vacuous-drift reduction.
Both tested and green.

**Subordinate obligation 4 (Non-interference):** NOT YET DISCHARGED.
Phase 3 tests only one Federable peer. Multi-peer non-interference
requires ≥2 registered peers + a scenario where federating one shape
could (in principle) weaken claims about the other. Scheduled as
next Phase 3 follow-up.

## Remaining obligations

- [x] Non-interference with N ≥ 2 simultaneous Federable peers.
      **DISCHARGED runtime:** `test_noninterference.jl` (15 assertions)
      with Vector + Document peers. Independent keypairs, isolated LWW
      writes, 3-way parity over (S,V)/(S,D)/(V,D).
- [x] Byzantine-peer resistance baseline — real Ed25519 via libsodium.
      `test_seams.jl` round-trip + tamper rejection.
- [ ] Formal (Idris2 type-level) proof of non-interference at arbitrary N.
      Discharged at runtime only.
- [ ] Byzantine-peer resistance beyond Clause 3 (e.g., peers that accept
      LWW order but serve stale reads).
- [ ] Conditional-shape gating (Graph): runtime check that Graph is
      registered only when cross-entity-claim workload is in scope.

## Phase 4 + 5 closure

- [x] **Phase 4 dogfood:** `test_krladapter_integration.jl` (19 assertions).
      KRLAdapter.jl client fully satisfied by Core alone — no Federable
      shapes required. See `examples/krladapter_integration.jl` +
      `docs/FINDINGS.adoc`.
- [x] **Phase 5 findings writeup:** `docs/FINDINGS.adoc` with
      classification, contract, degradation routes, adoption guide,
      foldback log, and productisation recommendation.
