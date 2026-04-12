# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# QuandleDB/KRL System Specification

## Overview

QuandleDB is a knot-theoretic database for storing, querying, and
classifying knots via algebraic invariants. The stack comprises Julia
(server and engine via Skein.jl) and ReScript (frontend). Knot Resolution
Language (KRL) provides the query interface.

## Memory Model

### Julia Runtime

All knot records, quandle structures, and invariant results are managed
by Julia's generational garbage collector. Knot records are immutable
structs (`struct KnotRecord ... end`). Short-lived intermediates benefit
from young-generation collection. Long-lived catalog data is pinned in
a global `KnotCatalog` dictionary that survives GC cycles.

### E-Graph Representation

Equivalence classes of knots under Reidemeister moves are stored as an
in-memory e-graph (equality saturation). Each e-class contains a set of
equivalent knot representations. The e-graph grows monotonically: new
equivalences are discovered but never retracted. Backed by a union-find
with path compression, stored as a flat `Vector{Int}` for cache locality.

### Memory Budget

The e-graph enforces a configurable node limit (default: 10M e-nodes).
When reached, saturation halts and returns best-known equivalence
classes. Adjustable per query via `SATURATE ... LIMIT n` KRL clause.

### ReScript Frontend

The frontend maintains a local LRU cache (default: 500 entries) of
recently queried knot records as ReScript immutable records. No knot
computation occurs on the frontend; it is purely a presentation and
query-composition layer.

## Concurrency Model

### Julia Task Parallelism

KRL evaluation proceeds in strata: stratum 0 computes base invariants
(crossing number, writhe), stratum 1 computes polynomial invariants
(Jones, HOMFLY-PT via Skein.jl), stratum 2 computes homological
invariants (Khovanov homology). Strata evaluate sequentially, but
within each stratum independent knot records are processed in parallel
via `Threads.@spawn`.

### Query Isolation

Each KRL query runs in its own Julia `Task` with a private e-graph
instance. Queries share read access to the global `KnotCatalog`.
Catalog mutations are serialized through a `ReentrantLock`-protected
append operation, eliminating write contention.

### Frontend Concurrency

The ReScript frontend uses async/await for non-blocking server
communication. Stale cache entries are invalidated by a version counter
returned with each response.

## Effect System

### Provenance Effect

Every equivalence result carries derivation evidence: the sequence of
Reidemeister moves or skein relations that established it. Evidence is
stored as proof steps attached to each e-class merge. Queryable via
`EXPLAIN EQUIVALENCE k1 k2`. Provenance is append-only.

### Computation Cost Effect

Each computed invariant carries a cost annotation (wall-clock
microseconds and allocation bytes). Exposed via `EXPLAIN COST` KRL
clause. Queries exceeding a cost budget (configurable via `BUDGET`
clause) are terminated early with a partial result and cost report.

### Effect Composition

Provenance and cost compose: the cost of producing a provenance chain
is itself tracked. Expensive derivations are flagged in the cost report.

## Module System

### Julia Modules

Organized as `QuandleDB.jl` with submodules: `Catalog` (storage),
`Engine` (evaluation), `EGraph` (equality saturation), `Invariants`
(computations), `Server` (HTTP/WebSocket). `Skein.jl` is declared as
a dependency in `Project.toml`.

### ReScript Modules

One module per concern: `KnotViewer.res`, `QueryEditor.res`,
`ServerClient.res`, `Cache.res`, `KnotTypes.res`. Interface files
(`.resi`) define public APIs.

### KRL Query Modules

User-defined modules via `MODULE name { ... }` blocks encapsulate
named queries and invariant definitions, imported with `USE`. Module
resolution is flat. Modules are stored server-side in the catalog.

### Cross-Language Boundary

Julia and ReScript communicate via JSON over HTTP or WebSocket. The
wire format is defined by `schema/krl-wire.json`. ReScript types are
generated from this schema for cross-boundary type safety.
