# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# Lithoglyph/GQL System Specification

## Overview

Lithoglyph is a graph query language database built on a polyglot stack:
Forth (storage), Factor (query runtime), Zig (bridge), Elixir (control
plane), and Lean 4 (normalizer).

## Memory Model

### Forth Storage Layer

The storage engine uses fixed-size blocks (4 KiB default, configurable at
init). All writes are append-only: mutations produce new journal entries
rather than overwriting existing blocks. Block addresses are immutable
once allocated. Freed blocks are reclaimed only during explicit compaction.

### Zig Block Allocator

Zig manages the physical block pool via a slab allocator. Each slab
corresponds to a memory-mapped region of the journal file. The allocator
maintains a free-list of reclaimed blocks after compaction. A write-ahead
log (WAL) in Zig ensures crash recovery: every block write is first
recorded in the WAL, then flushed to the journal. WAL entries are
checksummed (xxHash64) and trimmed after journal sync.

### Factor Query Execution

Factor executes queries using stack-based evaluation with no heap garbage
collector. Intermediate query results live on the data stack or in
explicitly allocated retain stacks. Large result sets spill to Zig-managed
temporary blocks rather than growing unbounded in-process memory. Stack
frames are released deterministically when a query completes.

### Lean 4 Normalizer

The Lean 4 normalizer operates on an in-memory graph representation
received via serialized messages from the Elixir control plane. It
performs graph rewriting in pure Lean (no IO monad) and returns the
normalized form. Memory is managed by Lean's reference-counted runtime;
the normalizer process is short-lived per invocation.

## Concurrency Model

### Elixir/OTP Session Management

Each client connection is supervised by an OTP GenServer. The supervisor
tree uses `one_for_one` strategy: a crashed session does not affect
others. Sessions hold no shared mutable state; all coordination happens
through message passing to the storage coordinator (a singleton GenServer
that serializes journal writes).

### Factor Cooperative Multitasking

Query execution within Factor uses cooperative multitasking via explicit
yield points. Long-running traversals yield after processing each batch
of edges (default batch size: 1024). This prevents any single query from
starving the runtime. Factor threads are M:1 (multiplexed onto the OTP
scheduler thread that owns the Factor NIF).

### Write Serialization

All journal mutations are serialized through the Elixir storage
coordinator. Reads are lock-free against the append-only journal:
readers see a consistent snapshot defined by the journal offset at
query start (snapshot isolation via offset bookmarking).

## Effect System

### Provenance Effect (Mandatory)

Every mutation carries a provenance record as a mandatory effect. The
provenance includes: actor identity (session ID + authenticated principal),
timestamp (monotonic + wall-clock), rationale (client-supplied text or
`"implicit"` default), and causal predecessor (previous journal offset
for the affected subgraph). Provenance records are stored inline in the
journal block, not in a side table. Queries may filter or project on
provenance fields.

### Reversibility Effect

Every mutation also stores its inverse operation in the journal. For
node insertion, the inverse is a tombstone marker. For edge creation,
the inverse is edge removal. For property updates, the inverse stores
the prior value. Reversal is triggered by issuing a `REVERT` command
referencing a journal offset range. The reversal itself produces new
journal entries (with their own provenance), preserving the append-only
invariant.

### Effect Composition

Provenance and reversibility compose: reverting a mutation produces a
new provenance record attributing the revert to the requesting actor,
and the revert entry itself is reversible (enabling undo-of-undo).

## Module System

### Forth Word Definitions

Storage operations are defined as Forth words in `.4th` files loaded at
engine startup. Custom words extend the storage vocabulary (e.g.,
`BLOCK-ALLOC`, `WAL-APPEND`, `JOURNAL-SYNC`). Words are organized into
wordlists by functional area.

### Factor Vocabularies

Query operations are organized as Factor vocabularies: `gql.parser`,
`gql.planner`, `gql.executor`, `gql.results`. Each vocabulary declares
its imports explicitly. Vocabularies are loaded on demand by the runtime.

### Elixir OTP Applications

The control plane is structured as an OTP umbrella application with
child apps: `lithoglyph_session`, `lithoglyph_storage`,
`lithoglyph_normalizer` (Lean 4 port wrapper), and `lithoglyph_api`
(external interface). Dependencies between apps are declared in
`mix.exs` and enforced by the release build.

### Cross-Language Boundaries

Zig serves as the bridge between Forth, Factor, and Elixir via NIF
bindings. The Zig bridge exposes a C ABI consumed by Erlang NIFs and
Factor FFI. Message formats crossing the bridge are length-prefixed
binary with a 1-byte tag discriminator.
