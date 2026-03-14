# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# TypeQL-Experimental System Specification

## Overview

TypeQL-Experimental is a research-stage type-theoretic query language
that enforces resource safety, session protocols, and proof obligations
at compile time. The stack comprises Idris2 (type kernel and effect
enforcement), ReScript (parser), and Zig (FFI bridge).

## Memory Model

### Idris2 Type Kernel

Through Quantitative Type Theory (QTT), types with quantity `0` are
erased at compile time and occupy no runtime memory. Proof terms exist
only during type checking. Runtime values use Idris2's reference-counted
backend (Chez Scheme or RefC). The kernel is invoked as a compile-time
tool, so memory pressure is bounded by program size.

### ReScript Parser

The parser runs on the JS heap (Deno runtime). Source text is tokenized
into an immutable AST (ReScript variant types), serialized to JSON for
handoff to Idris2. Parser memory is short-lived: each invocation
allocates, serializes, and releases. No persistent state between calls.

### Zig FFI Bridge

The bridge uses per-invocation arena allocators, freed in bulk on call
completion. This eliminates fragmentation and ensures deterministic
cleanup. Linear types in Idris2 guarantee that connection handles
crossing the bridge are consumed exactly once.

### Linear Resource Guarantee

Connection handles, file descriptors, and transaction tokens are typed
as `Linear a` (quantity `1`). The type checker verifies each linear
resource is used exactly once. The Zig bridge asserts linearity at
runtime via one-shot flags as defense-in-depth.

## Concurrency Model

TypeQL-Experimental is a compile-time research tool, not a runtime
engine. There is no runtime concurrency model. The Idris2 checker is
single-threaded, the ReScript parser synchronous, and the Zig bridge
processes one invocation at a time. Build-time parallelism is delegated
to `idris2 --threads` and `build.zig` parallel compilation.

## Effect System

Six typed effects, all enforced at compile time by Idris2 QTT.

### 1. Linear Consumption

Resources at quantity `1` must be consumed exactly once. Covers database
connections, prepared statements, and result cursors. No resource leaks
or double-frees are expressible in well-typed programs.

### 2. Session Protocol

Client-server interaction follows a session type (Idris2 indexed type)
specifying the legal operation sequence: connect, authenticate, query,
commit/rollback, disconnect. Deviating from the protocol is a type
error. Parameterized by authentication state.

### 3. Effect Subsumption

Effects form a lattice. Computations requiring fewer effects embed into
contexts permitting more (covariant). Pure computations compose into
effectful contexts without annotation. Lattice ordering checked during
elaboration.

### 4. Modal Scoping

Computations carry a modality: `Compile` or `Runtime`. Compile-time
proofs cannot reference runtime values. Erased terms (quantity `0`) are
never demanded at runtime.

### 5. Proof Attachment

Query results carry proof witnesses (e.g., `NoInjection`) of statically
verified properties. Proofs are erased at runtime (quantity `0`) but
available during type checking for downstream composition.

### 6. Resource Budgeting

Effectful computations declare resource budgets (max allocations, max
recursion depth). Checked statically via dependent types on naturals;
enforced dynamically for data-dependent bounds. Violations produce a
`BudgetExceeded` type-level error requiring explicit handling.

## Module System

### Idris2 Packages

Organized as `.ipkg` packages: `typeql-kernel` (type rules),
`typeql-effects` (effect lattice), `typeql-session` (session protocol),
`typeql-proofs` (proof combinators). Dependencies declared in `depends`.

### ReScript Modules

`Lexer.res` (tokenization), `Parser.res` (recursive descent), `Ast.res`
(types), `Serializer.res` (AST to JSON). Interface files (`.resi`)
define public APIs.

### Zig Build System

Built with `build.zig`: `bridge.zig` (entry points), `arena.zig`
(allocator), `protocol.zig` (serialization), `linear_check.zig`
(runtime linearity). Produces a shared library consumed by Idris2
(`%foreign`) and ReScript (Deno FFI).

### Cross-Language Integration

Idris2 calls Zig via `%foreign "C:function_name,libbridge"`. ReScript
calls Zig via `Deno.dlopen`. The shared library exposes a flat C ABI
with no global state; all functions take explicit context pointers.
