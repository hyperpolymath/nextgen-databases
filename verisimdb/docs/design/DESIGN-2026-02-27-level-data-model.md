# Design Document: IDApTIK Level Architect — Canonical Level Data Model
# SPDX-License-Identifier: PMPL-1.0-or-later

**Date:** 2026-02-27
**Author:** Jonathan D.A. Jewell (hyperpolymath)
**Repo:** `idaptik/idaptik-level-architect`
**Session agent:** Claude Opus 4.6

---

## Summary

Define the canonical level data model for the IDApTIK Level Architect in Idris2
with dependent type proofs. This replaces the main game's `LevelConfig.res` as
the source of truth — ReScript types will derive from the Idris2 ABI definitions.

## Motivation

The level architect needs to:

1. Represent every aspect of a level (devices, guards, dogs, drones, wiring,
   zones, items, missions, physical grid, defence flags)
2. Prove correctness invariants at compile time (referential integrity of device
   IPs, guard zone existence, zone spatial ordering, PBX consistency)
3. Export levels to `LevelConfig.res` format for the main game (round-trip
   fidelity)
4. Store levels in VerisimDB for persistence, version history, and simulation
   result tracking

## Architectural Decisions

### AD-1: Idris2 ABI as canonical source of truth

**Decision:** All level types are defined in Idris2 with dependent type proofs.
The ReScript types in the main game and level architect derive from these.

**Rationale:** Idris2's dependent types can prove invariants (referential
integrity, spatial ordering, positive values) that ReScript cannot express. A
broken level config is caught at the ABI layer before it reaches the game.

### AD-2: VerisimDB for level architect only

**Decision:** The level architect uses VerisimDB for:
- Level persistence (save/load work-in-progress designs)
- Version history (track edits, branch level variants, diff versions)
- Simulation results (guard patrol traces, detection events, timing data)
- Validation logs (Idris2 proof outcomes per level version)

The main game does NOT use a database. It receives static exported
`LevelConfig.res` files.

**Rationale:** The game is a single-player Tauri desktop app. It needs fast,
offline, read-only access to level data. A database adds runtime complexity
with no benefit. Save games, player progress, and inventory state are all
handled with local files.

VerisimDB's federated mode provides an escape hatch: if a game-side database
is ever needed (e.g., level marketplace, multiplayer lobby), federation can
bridge to a lightweight secondary without redesigning the architect.

### AD-3: Module-per-domain architecture

**Decision:** 13 new Idris2 modules, one per game domain, plus a composition
root (`Level.idr`) and a validation module (`Validation.idr`).

**Rationale:**
- Clean compilation units (change one domain, rebuild one module)
- Independent proof development per domain
- Clear 1:1 mapping to main game ReScript source files
- No circular dependencies (types flow upward from leaves to root)

### AD-4: So-based witnesses over DecEq

**Decision:** Use `So`-based witnesses via `decSo` on `(==)` for IPv4
comparison in proofs, rather than full `DecEq` instances.

**Rationale:** Full `DecEq` for `Bits8` requires proving `Not (a = b)` for the
negative case, which is awkward without `believe_me`. `So (a == b)` is
sufficient for our `InRegistry` and referential integrity proofs, and can be
constructed safely via `decSo` (which is in `Data.So` in the standard library).

### AD-5: JSON serialization via Zig FFI

**Decision:** Levels are serialized as JSON. The Zig FFI layer handles
parsing/emitting JSON. The Idris2 layer guarantees the parsed data is
well-formed.

**Rationale:** `LevelConfig.res` is JSON-shaped (ReScript records compile to JS
objects). Round-trip verification is easiest with text format. Binary would add
complexity without benefit at this scale (levels are <100KB).

## Module Dependency Graph

```
                    Level.idr
                   /    |    \
                  /     |     \
           Mission  Validation  Physical
              |      /  |  \      |
          Inventory /   |   \   Wiring
              |    /    |    \    |
           Guards Dogs Drones Assassin
              \    |    /    /
               \   |   /   /
                Devices
                   |
               Network
                   |
              Primitives
                   |
                Types.idr (existing)
```

## Cross-Domain Proofs

| Proof | Type | Guarantees |
|-------|------|-----------|
| `InRegistry` | `IPv4 -> DeviceRegistry -> Type` | An IP address exists in the device list |
| `GuardsInZones` | `List GuardPlacement -> List ZoneTransition -> Type` | Every guard's zone appears in zone transitions |
| `DefenceTargetsValid` | `List DeviceDefenceConfig -> DeviceRegistry -> Type` | failoverTarget/cascadeTrap/mirrorTarget IPs exist |
| `ZonesOrdered` | `List ZoneTransition -> Type` | Zone x-coordinates are monotonically increasing |
| `PBXConsistent` | `Bool -> Maybe IPv4 -> Type` | PBX IP is set iff hasPBX is True |
| `ValidatedLevel` | Record | Bundles LevelData with all proof terms |

## Banned Patterns

- `believe_me` — compiles silently, hides unsoundness
- `assert_total` — bypasses totality checker
- `assert_smaller` — bypasses termination checker
- `unsafePerformIO` — side effects in pure code

## Verification Criteria

1. `idris2 --build idaptik.ipkg` compiles with zero errors, zero warnings
2. Zero instances of banned patterns
3. Every field in `LevelConfig.res` has a corresponding field in `LevelConfig`
4. `ValidatedLevel` bundles all 5 proof types
5. All functions under `%default total`
