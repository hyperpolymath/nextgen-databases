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

## Status

Empty. No obligations discharged yet — this is a research scaffold.
