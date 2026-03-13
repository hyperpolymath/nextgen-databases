# GQL-DT Integration: ReScript, WASM, ABI, FFI

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

**Date:** 2026-02-01
**Status:** Integration Requirements
**Priority:** HIGH - Required for M7+ (Post-Parser)

---

## Integration Requirements

### 1. ReScript Bindings

**Purpose:** Seamless integration with existing hyperpolymath projects (TypeScript/JavaScript replacement)

**Architecture:**
```
GQL-DT (Lean 4)
    ↓
Typed IR (CBOR)
    ↓
Zig FFI Bridge
    ↓
C ABI (extern "C")
    ↓
ReScript Bindings (@rescript/core)
    ↓
JavaScript/Web/Deno
```

**ReScript Bindings Location:**
```
bindings/
├── rescript/
│   ├── rescript.json
│   ├── src/
│   │   ├── FbqlDt.res              # Main API
│   │   ├── FbqlDt_AST.res          # AST bindings
│   │   ├── FbqlDt_TypeChecker.res  # Type checker bindings
│   │   ├── FbqlDt_IR.res           # IR bindings
│   │   └── FbqlDt_FFI.res          # Low-level FFI
│   └── package.json                # For npm compatibility if needed
```

**Example ReScript API:**
```rescript
// bindings/rescript/src/FbqlDt.res
module Insert = {
  type t

  // Create type-safe INSERT
  @module("@gqldt/core") @scope("Insert")
  external create: (
    ~table: string,
    ~columns: array<string>,
    ~values: array<TypedValue.t>,
    ~rationale: string,
  ) => result<t, string> = "create"

  // Execute INSERT on Lithoglyph
  @module("@gqldt/core") @scope("Insert")
  external execute: (t, ~db: Database.t) => promise<result<unit, string>> = "execute"
}

module TypedValue = {
  type t =
    | Nat(int)
    | BoundedNat({min: int, max: int, value: int})
    | NonEmptyString(string)
    | PromptScores(PromptScores.t)

  // Convert to C-compatible representation
  @module("@gqldt/core") @scope("TypedValue")
  external toCBOR: t => Js.TypedArray2.Uint8Array.t = "toCBOR"
}

// Usage in ReScript project:
let insertEvidence = async () => {
  let insert = Insert.create(
    ~table="evidence",
    ~columns=["title", "prompt_provenance"],
    ~values=[
      NonEmptyString("ONS Data"),
      BoundedNat({min: 0, max: 100, value: 95}),
    ],
    ~rationale="Official statistics",
  )

  switch insert {
  | Ok(stmt) => await Insert.execute(stmt, ~db=myDatabase)
  | Error(msg) => Console.error(msg)
  }
}
```

---

### 2. WASM Compatibility

**Purpose:** Public-facing deployments, browser-based Lithoglyph Studio, edge computing

**WASM Compilation Strategy:**
```
Lean 4 → C (via Lean's C backend)
    ↓
Emscripten/wasm32-unknown-unknown
    ↓
WebAssembly Module (.wasm)
    ↓
JavaScript/ReScript Glue Code
    ↓
Browser/Deno/Cloudflare Workers
```

**Alternative (Preferred): Zig WASM**
```
GQL-DT Parser (Lean 4)
    ↓
Typed IR (CBOR)
    ↓
Zig FFI Bridge (compiled to WASM)
    ↓
wasm32-wasi / wasm32-unknown-unknown
    ↓
WebAssembly Module
    ↓
ReScript Bindings (Web)
```

**WASM Build Configuration:**
```zig
// bridge/zig/build.zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,  // or .freestanding
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "gqldt",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Export C ABI for WASM
    lib.rdynamic = true;
    b.installArtifact(lib);
}
```

**WASM Features:**
- ✅ Type checking in browser
- ✅ Query validation before server round-trip
- ✅ Proof verification client-side (for GQL-DT tier)
- ✅ Offline Lithoglyph Studio (IndexedDB storage)
- ✅ Edge computing (Cloudflare Workers, Deno Deploy)

**Example WASM Usage:**
```rescript
// Web browser or Deno
module FbqlDtWasm = {
  @module("@gqldt/wasm")
  external initialize: unit => promise<unit> = "initialize"

  @module("@gqldt/wasm")
  external parseQuery: string => promise<result<IR.t, ParseError.t>> = "parseQuery"

  @module("@gqldt/wasm")
  external typeCheck: IR.t => promise<result<unit, TypeError.t>> = "typeCheck"
}

// Client-side validation before sending to server
let validateQuery = async (queryString: string) => {
  await FbqlDtWasm.initialize()

  let parsed = await FbqlDtWasm.parseQuery(queryString)
  switch parsed {
  | Ok(ir) =>
      let checked = await FbqlDtWasm.typeCheck(ir)
      switch checked {
      | Ok() => sendToServer(ir)  // Type-safe, send to Lithoglyph
      | Error(typeError) => showError(typeError)  // Caught client-side!
      }
  | Error(parseError) => showError(parseError)
  }
}
```

---

### 3. ABI in Idris2

**Purpose:** Formally verified Application Binary Interface with dependent type proofs

**Why Idris2 for ABI:**
- ✅ Dependent types prove interface correctness
- ✅ Verify memory layout (alignment, padding, size)
- ✅ Platform-specific ABIs with compile-time selection
- ✅ Backward compatibility proofs
- ✅ Type-level guarantees impossible in C/Zig/Rust

**ABI Architecture:**
```
src/abi/                          # Idris2 ABI definitions
├── Types.idr                     # Type definitions with proofs
├── Layout.idr                    # Memory layout verification
├── Foreign.idr                   # FFI declarations
├── Platform/
│   ├── Linux.idr                 # Linux-specific ABI
│   ├── Darwin.idr                # macOS ABI
│   └── Windows.idr               # Windows ABI
└── Proofs/
    ├── Compatibility.idr         # Backward compatibility proofs
    └── Alignment.idr             # Memory alignment proofs

generated/abi/                    # Auto-generated from Idris2
└── *.h                           # C headers for Zig FFI
```

**Example: Idris2 ABI with Proofs**
```idris
-- src/abi/Types.idr
module FbqlDt.ABI.Types

import Data.So
import Data.Bits

-- Non-null opaque handle (provably safe)
export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

-- Typed value with size proof
export
record TypedValue where
  constructor MkTypedValue
  tag : Bits8           -- Type discriminator
  data : Bits64         -- Value or pointer
  {auto 0 sizeCorrect : sizeof TypedValue = 16}
  {auto 0 aligned : Divides 8 (alignof TypedValue)}

-- INSERT statement ABI
export
record InsertStmt where
  constructor MkInsertStmt
  handle : Handle                    -- Non-null by construction
  table : Ptr String                 -- Table name
  columns : Ptr (List String)        -- Column names
  values : Ptr (List TypedValue)     -- Typed values
  proofBlob : Ptr Bytes              -- CBOR proof blob
  {auto 0 layoutCorrect : sizeof InsertStmt = 40}
  {auto 0 aligned8 : Divides 8 (alignof InsertStmt)}

-- Platform-specific ABI selection
export
PlatformABI : Type
PlatformABI = case target of
  Linux   => LinuxABI
  Darwin  => DarwinABI
  Windows => WindowsABI

-- Proof: ABI is backward compatible across versions
export
0 backwardCompatible : (v1 v2 : Version) -> v1 < v2 ->
  ABILayout v1 `isSubsetOf` ABILayout v2
backwardCompatible = ?proof_backward_compat
```

**Generated C Header (from Idris2):**
```c
// generated/abi/gqldt.h
// Auto-generated from src/abi/Types.idr - DO NOT EDIT

#ifndef GQLDT_ABI_H
#define GQLDT_ABI_H

#include <stdint.h>
#include <stdbool.h>

// Opaque handle (non-null guaranteed by Idris2 proof)
typedef struct FbqlDt_Handle {
    uint64_t ptr;  // Always non-zero
} FbqlDt_Handle;

// Typed value (size=16, alignment=8, proven correct)
typedef struct FbqlDt_TypedValue {
    uint8_t tag;
    uint8_t _padding[7];
    uint64_t data;
} FbqlDt_TypedValue;

_Static_assert(sizeof(FbqlDt_TypedValue) == 16, "TypedValue size");
_Static_assert(_Alignof(FbqlDt_TypedValue) == 8, "TypedValue alignment");

// INSERT statement (size=40, alignment=8, proven correct)
typedef struct FbqlDt_InsertStmt {
    FbqlDt_Handle handle;
    const char *table;
    const char **columns;
    FbqlDt_TypedValue *values;
    const uint8_t *proof_blob;
} FbqlDt_InsertStmt;

_Static_assert(sizeof(FbqlDt_InsertStmt) == 40, "InsertStmt size");
_Static_assert(_Alignof(FbqlDt_InsertStmt) == 8, "InsertStmt alignment");

#endif // GQLDT_ABI_H
```

**Benefits of Idris2 ABI:**
- ✅ **Compile-time verification** - Memory layout proven correct
- ✅ **Platform portability** - Same ABI works Linux/macOS/Windows
- ✅ **Backward compatibility** - Proven mathematically, not tested
- ✅ **No undefined behavior** - Type system prevents null pointers, alignment issues
- ✅ **Self-documenting** - Proofs explain why layout is correct

---

### 4. FFI in Zig

**Purpose:** C-compatible foreign function interface, cross-platform, memory-safe

**Why Zig for FFI:**
- ✅ Native C ABI compatibility without overhead
- ✅ Memory safety by default
- ✅ Cross-compilation built-in (any platform, any architecture)
- ✅ No runtime dependencies
- ✅ Simpler than Rust FFI, safer than C
- ✅ Works with WASM (wasm32-wasi)

**FFI Architecture:**
```
ffi/zig/                          # Zig FFI implementation
├── build.zig                     # Build configuration
├── src/
│   ├── main.zig                  # Main FFI exports
│   ├── insert.zig                # INSERT implementation
│   ├── select.zig                # SELECT implementation
│   ├── typecheck.zig             # Type checker FFI
│   ├── ir.zig                    # IR serialization/deserialization
│   └── cbor.zig                  # CBOR proof blob handling
├── test/
│   └── integration_test.zig     # FFI integration tests
└── include/
    └── gqldt.h                  # Public C API (from Idris2 ABI)
```

**Example: Zig FFI Implementation**
```zig
// ffi/zig/src/main.zig
const std = @import("std");
const c = @cImport({
    @cInclude("gqldt.h");  // Generated from Idris2 ABI
});

// FFI: Create INSERT statement
export fn gqldt_insert_create(
    table: [*:0]const u8,
    columns: [*]const [*:0]const u8,
    column_count: usize,
    values: [*]const c.FbqlDt_TypedValue,
    value_count: usize,
    rationale: [*:0]const u8,
) callconv(.C) ?*c.FbqlDt_InsertStmt {
    const allocator = std.heap.c_allocator;

    // Validate non-null (redundant with Idris2 proof, but defensive)
    if (table[0] == 0) return null;
    if (rationale[0] == 0) return null;

    const stmt = allocator.create(c.FbqlDt_InsertStmt) catch return null;

    stmt.* = .{
        .handle = .{ .ptr = @intFromPtr(stmt) },  // Non-null by construction
        .table = table,
        .columns = columns,
        .values = values,
        .proof_blob = null,  // Generated by type checker
    };

    return stmt;
}

// FFI: Execute INSERT on Lithoglyph
export fn gqldt_insert_execute(
    stmt: *c.FbqlDt_InsertStmt,
    db: *c.FbqlDt_Database,
) callconv(.C) c_int {
    // Type checker already verified this at parse time
    // Just execute on storage layer

    const collection = db.getCollection(stmt.table) catch return -1;

    for (stmt.values[0..stmt.value_count], 0..) |val, i| {
        const col = collection.columns[i];

        // Type already matches (proven by Idris2 ABI)
        collection.writeValue(col.name, val) catch return -1;
    }

    return 0;  // Success
}

// FFI: Free INSERT statement
export fn gqldt_insert_free(stmt: *c.FbqlDt_InsertStmt) callconv(.C) void {
    const allocator = std.heap.c_allocator;
    allocator.destroy(stmt);
}

// FFI: Type check query
export fn gqldt_typecheck(
    query: [*:0]const u8,
    schema: *const c.FbqlDt_Schema,
    error_buffer: [*]u8,
    buffer_size: usize,
) callconv(.C) c_int {
    // Call Lean 4 type checker via C FFI
    // (Lean 4 compiles to C, provides extern symbols)

    const result = lean_gqldt_typecheck(query, schema);

    if (result.ok) {
        return 0;  // Type check passed
    } else {
        // Copy error message to buffer
        const msg = std.mem.span(result.error_msg);
        const copy_len = @min(msg.len, buffer_size - 1);
        @memcpy(error_buffer[0..copy_len], msg[0..copy_len]);
        error_buffer[copy_len] = 0;  // Null terminate
        return -1;
    }
}

// Lean 4 extern declaration (from Lean's C backend)
extern fn lean_gqldt_typecheck(
    query: [*:0]const u8,
    schema: *const c.FbqlDt_Schema,
) callconv(.C) struct {
    ok: bool,
    error_msg: [*:0]const u8,
};
```

**Cross-Compilation (Zig's Superpower):**
```bash
# Build for Linux x86_64
zig build -Dtarget=x86_64-linux

# Build for macOS ARM64
zig build -Dtarget=aarch64-macos

# Build for Windows x86_64
zig build -Dtarget=x86_64-windows

# Build for WASM
zig build -Dtarget=wasm32-wasi

# All from same codebase, no Docker/VMs needed!
```

---

## Integration Flow: Complete Picture

```
┌─────────────────────────────────────────────────────────┐
│ GQL-DT/GQL Source (User Input)                         │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ Lean 4 Parser (src/FbqlDt/)                             │
│ - Lexer, parser, type checker                            │
│ - Generates typed AST with proofs                        │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ Typed IR (CBOR Serialization)                           │
│ - Preserves dependent types and proof blobs              │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ Idris2 ABI (src/abi/)                                   │
│ - Formal interface specification with proofs             │
│ - Generates C headers for FFI                            │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ Zig FFI Bridge (ffi/zig/)                               │
│ - C ABI compatible exports                               │
│ - Memory-safe implementation                             │
│ - Cross-platform (Linux/macOS/Windows/WASM)             │
└────┬────────────────────────────────────┬───────────────┘
     ↓                                    ↓
┌─────────────────┐              ┌──────────────────────┐
│ ReScript        │              │ Lithoglyph Native        │
│ Bindings        │              │ Execution (Rust/Zig) │
│ (Web/Node/Deno) │              │                      │
└─────────────────┘              └──────────────────────┘
     ↓
┌─────────────────────────────────────────────────────────┐
│ JavaScript/TypeScript/Deno/Browser/WASM                 │
└─────────────────────────────────────────────────────────┘
```

---

## Implementation Milestones

### M7: Idris2 ABI (Post-Parser)
- [ ] Create `src/abi/` directory structure
- [ ] Define core types with dependent type proofs
- [ ] Verify memory layouts (size, alignment)
- [ ] Platform-specific ABI selection
- [ ] Generate C headers from Idris2
- [ ] Prove backward compatibility
- [ ] Test on Linux/macOS/Windows

### M8: Zig FFI Bridge
- [ ] Implement C-compatible FFI exports
- [ ] Integrate with Idris2-generated headers
- [ ] CBOR proof blob serialization
- [ ] Type checker FFI
- [ ] IR serialization/deserialization
- [ ] Cross-compilation tests
- [ ] Integration tests with Lean 4

### M9: ReScript Bindings
- [ ] Create `bindings/rescript/` directory
- [ ] Define type-safe ReScript API
- [ ] External bindings to Zig FFI
- [ ] Promise-based async API
- [ ] Error handling with Result types
- [ ] Example projects
- [ ] Documentation

### M10: WASM Support
- [ ] Compile Zig FFI to wasm32-wasi
- [ ] Browser-compatible WASM module
- [ ] JavaScript/ReScript glue code
- [ ] Client-side type checking
- [ ] Offline Lithoglyph Studio (IndexedDB)
- [ ] Edge computing examples (Cloudflare Workers)

---

## Benefits of This Architecture

| Layer | Technology | Benefits |
|-------|------------|----------|
| **Parser** | Lean 4 | Dependent types, theorem proving, compile-time verification |
| **ABI** | Idris2 | Formal interface proofs, memory layout verification, platform portability |
| **FFI** | Zig | C ABI compat, memory safety, cross-compilation, WASM support |
| **Bindings** | ReScript | Type-safe JS, seamless integration, modern syntax |
| **Deployment** | WASM | Browser, edge, serverless, offline-first |

**Result:**
- ✅ Type safety from source to execution
- ✅ Mathematically proven interface correctness
- ✅ Memory safety without garbage collection
- ✅ Cross-platform (Linux/macOS/Windows/Web)
- ✅ Seamless ReScript integration
- ✅ WASM for public deployments
- ✅ Zero-cost abstractions (proof erasure)

---

**Document Status:** Complete integration architecture

**Next Steps:**
1. Complete M6 Parser (generate typed IR)
2. Start M7: Idris2 ABI implementation
3. Start M8: Zig FFI bridge (parallel with M7)
4. Create ReScript bindings after FFI stable
5. WASM compilation after ReScript bindings work

**See Also:**
- `docs/EXECUTION-STRATEGY.md` - Why native IR execution
- `docs/TWO-TIER-DESIGN.md` - GQL-DT vs GQL architecture
- `~/abi-migration-guide.md` - ABI/FFI universal standard (per CLAUDE.md)
- `~/Documents/hyperpolymath-repos/rsr-template-repo/ABI-FFI-README.md` - Template
