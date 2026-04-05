<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# PROOF-NEEDS — QuandleDB

Mathematical and systems obligations for the quandle semantic layer.

## Mathematical obligations

### M1. Quandle axioms preserved
Statement: For every `QuandlePresentation` produced by `extract_presentation`,
the derived action satisfies the three quandle axioms:

1. `a ▷ a = a` (idempotence)
2. For every `a`, the map `x ↦ x ▷ a` is a bijection (right-invertibility)
3. `(a ▷ b) ▷ c = (a ▷ c) ▷ (b ▷ c)` (right self-distributivity)

Current status: not proved; not tested. Essential — if presentations don't
satisfy quandle axioms, the fingerprint is meaningless.

### M2. Reidemeister invariance
Statement: If diagrams D₁ and D₂ differ by a single Reidemeister move,
their extracted presentations produce the same fingerprint.

Current status: not proved; not tested on arbitrary R-move pairs.

### M3. Canonicalisation is idempotent
Statement: `canonicalize_presentation(canonicalize_presentation(p)) ==
canonicalize_presentation(p)`.

Current status: expected by construction; not proved. Should be provable
by the canonical-relabelling sort being a total order.

### M4. Colouring count well-definedness
Statement: For a finite quandle Q and a presentation p, the number of
quandle homomorphisms from `fundamental(p)` to Q depends only on the
isomorphism class of `fundamental(p)` — not on the particular presentation.

Current status: this is a standard result; need to verify the
implementation actually respects it.

## Systems obligations

### S1. Fingerprint determinism across platforms
Statement: Given identical input bytes, `quandle_fingerprint` produces
identical output bytes on Linux x86_64, Linux aarch64, macOS, and WebAssembly.

Current status: single-platform tested only.

### S2. Idris2 ABI ↔ Zig FFI layout agreement
Statement: Every record type defined in `src/abi/Types.idr` has a
byte-for-byte identical memory layout in the corresponding Zig struct
in `src/ffi/semantic_ffi.zig`.

Current status: declared, not proved. Idris2's dependent types could
encode the layout directly — this is exactly what the ABI/FFI boundary
discipline is for.

### S3. NIF safety
Statement: BEAM NIFs in `beam/native/quandle_db_nif.zig` never crash the
BEAM VM, even on malformed input from the Elixir side.

Current status: tested on well-formed inputs only. No fuzz on the NIF boundary.

## Proof stack (intended)

- **Idris2** for ABI layout / type-level invariants
- **Property-based tests (Julia)** for mathematical invariants M1-M4 as
  empirical evidence
- **Zig's comptime** for layout assertions at the FFI boundary
- **BEAM Dialyzer** for NIF typespec discipline

## How to propose a new obligation

1. State claim precisely.
2. Classify: mathematical, systems, or contract.
3. Either add property-based test as empirical evidence, OR write formal
   proof under `verification/` (create that dir if needed).
4. Move to "Currently verified" section (to be created) when discharged.
