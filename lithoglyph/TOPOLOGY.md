<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# TOPOLOGY.md — Lithoglyph

## System Architecture

```
                    ┌─────────────────────────────────────┐
                    │        svalinn (TLS gateway)        │
                    │    ML-DSA-87 · policy: strict       │
                    └────────────────┬────────────────────┘
                                     │ :8443
            ┌────────────────────────┼────────────────────────┐
            │                        │                        │
            ▼                        ▼                        ▼
  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
  │    lith-http     │   │    api (Zig)     │   │   studio (Tauri) │
  │  Elixir/Phoenix  │   │  REST + gRPC    │   │   Desktop GUI    │
  │  :4000           │   │  :8080 (BROKEN) │   │                  │
  └────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘
           │                      │                       │
           └──────────────────────┼───────────────────────┘
                                  │
    ┌─────────────────────────────▼─────────────────────────────┐
    │                  Elixir/OTP Control Plane                 │
    │  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │
    │  │  Supervision │  │  Clustering  │  │  BEAM NIFs     │  │
    │  │  Trees       │  │  (planned)   │  │  Zig + Rust    │  │
    │  └──────────────┘  └──────────────┘  └───────┬────────┘  │
    └──────────────────────────────────────────────┼────────────┘
                                                   │ C ABI
    ┌──────────────────────────────────────────────▼────────────┐
    │                    core-zig (Bridge)                       │
    │  19 functions · WAL commit · block allocator · compaction  │
    │  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐    │
    │  │ bridge   │  │ blocks   │  │ schema introspection │    │
    │  │ .zig     │  │ .zig     │  │ + proof verifier     │    │
    │  └──────────┘  └──────────┘  └──────────────────────┘    │
    └──────────────────────────────┬────────────────────────────┘
                                   │
    ┌──────────────────────────────▼────────────────────────────┐
    │                   core-forth (Kernel)                      │
    │          Block storage · Journal · Data model              │
    │                  17/17 tests pass                          │
    └──────────────────────────────────────────────────────────-─┘

    ┌─────────────────────────────────────────────────────────┐
    │  Verification Layers                                    │
    │                                                         │
    │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
    │  │  Idris2 ABI  │  │  Lean 4      │  │  GQL-DT      │  │
    │  │  src/Lith/   │  │  normalizer/ │  │  gql-dt/     │  │
    │  │  3 files     │  │  52 proofs   │  │  Lean 4      │  │
    │  │  0 believe_me│  │  FD discovery│  │  type-safe   │  │
    │  └──────────────┘  └──────────────┘  │  queries     │  │
    │                                       └──────────────┘  │
    │  ┌──────────────┐  ┌──────────────┐                     │
    │  │  Factor      │  │  Glyphbase   │                     │
    │  │  core-factor/│  │  glyphbase/  │                     │
    │  │  GQL runtime │  │  graph store │                     │
    │  └──────────────┘  └──────────────┘                     │
    └─────────────────────────────────────────────────────────┘

    Data flow:
    mutation → core-forth blocks → core-zig bridge (lith_*) → BEAM NIF → lith-http API
    query   → GQL-DT (Lean verify) → Factor GQL → core-zig → core-forth → result
    glyphbase NIF → core-zig bridge (19 functions, LgBlob/LgStatus types) → core-forth

    Naming: fdb_* → lith_*, FQL/FBQL/FDQL → GQL (Glyph Query Language), FormBD → Lithoglyph
```

## Completion Dashboard

| Component              | Progress                     | Status         |
|------------------------|------------------------------|----------------|
| core-forth (kernel)    | `██████████` 100%            | Complete       |
| core-zig (bridge)      | `██████████` 100%            | Complete       |
| ffi/zig (delegation)   | `██████████` 100%            | Complete       |
| Idris2 ABI (proofs)    | `██████████` 100%            | Complete       |
| Lean 4 normalizer      | `██████████` 100%            | Complete       |
| core-factor (GQL)      | `██████████` 100%            | Complete       |
| BEAM NIF (Zig)         | `████████░░` 80%             | Builds         |
| BEAM NIF (Rust)        | `████████░░` 80%             | Builds         |
| glyphbase NIF          | `██████░░░░` 60%             | Linked to core |
| lith-http (Elixir)     | `█████████░` 90%             | M15 complete   |
| gql-dt (Lean 4)        | `████████░░` 80%             | Needs audit    |
| glyphbase              | `████████░░` 80%             | Needs audit    |
| api (Zig HTTP)         | `██████████` 100%            | L1 complete    |
| studio (Tauri)         | `██░░░░░░░░` 20%             | Mock data      |
| Containerfile          | `██████████` 100%            | Complete       |
| selur-compose          | `██████████` 100%            | Complete       |
| IP rename              | `████████░░` 80%             | fdb→lith done  |
| **Overall**            | `████████░░` **80%**         |                |

## Key Dependencies

```
lithoglyph
├── gforth (Forth kernel — block storage)
├── zig 0.15.2 (C ABI bridge, BEAM NIF)
├── idris2 (dependent-type ABI proofs)
├── lean 4 v4.15.0 (normalization, GQL-DT)
├── mathlib v4.15.0 (GQL-DT proofs)
├── factor (GQL runtime — parser, planner, executor)
├── rustler 0.35 (Rust BEAM NIF)
├── elixir 1.18 / OTP 27 (lith-http, control plane)
├── phoenix (HTTP API framework)
├── tauri 2.0+ (studio desktop GUI)
├── nickel (configuration)
│
├── Container ecosystem:
│   ├── svalinn (TLS gateway + policy enforcement)
│   ├── vordr (runtime verification)
│   ├── cerro-torre (image signing, ML-DSA-87)
│   ├── rokur (secret rotation, argon2id)
│   └── selur-compose (deployment orchestration)
│
├── Sibling databases:
│   ├── verisimdb (octad database — shared GQL patterns)
│   ├── quandledb (knot-theoretic database)
│   └── nqc (normal-form query compiler)
│
└── Safety:
    └── proven (formally verified SafeString, SafeJson, etc.)
```
