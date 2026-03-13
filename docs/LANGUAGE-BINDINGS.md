# GQL-DT Language Bindings: Multi-Language Support

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

**Date:** 2026-02-01
**Status:** Language Binding Specifications
**Priority:** MEDIUM - Post-Core Implementation

---

## Overview

GQL-DT provides language bindings for all **allowed languages** in the hyperpolymath ecosystem (per `CLAUDE.md` language policy).

### Binding Architecture

```
GQL-DT Core (Lean 4)
    ↓
Typed IR (CBOR)
    ↓
Idris2 ABI (formally verified interface)
    ↓
Zig FFI (C-compatible bridge)
    ↓
    ├─ ReScript (primary for web/app development)
    ├─ Rust (systems programming, CLI tools, WASM)
    ├─ Julia (batch scripts, data processing)
    ├─ Gleam (backend services on BEAM)
    ├─ Elixir (distributed systems on BEAM)
    ├─ Haskell (type-heavy tools, Scaffoldia)
    ├─ Deno/JavaScript (runtime, glue code)
    └─ Ada (safety-critical systems, where required)
```

---

## 1. ReScript Bindings (PRIMARY)

**Status:** ✅ Specified in `docs/INTEGRATION.md`

**Priority:** CRITICAL - Primary language for application development

**Location:** `bindings/rescript/`

**Use Cases:**
- Lithoglyph Studio (web UI)
- Client-side query validation
- Browser-based type checking
- Deno backend services

**See:** `docs/INTEGRATION.md` for complete ReScript binding specification

---

## 2. Rust Bindings

**Priority:** HIGH - Systems programming, CLI tools, performance-critical code

**Location:** `bindings/rust/`

**Directory Structure:**
```
bindings/rust/
├── Cargo.toml
├── build.rs                    # Build script for Zig FFI linking
├── src/
│   ├── lib.rs                  # Main Rust API
│   ├── ffi.rs                  # Low-level FFI bindings
│   ├── insert.rs               # INSERT API
│   ├── select.rs               # SELECT API
│   ├── typed_value.rs          # TypedValue Rust types
│   ├── ir.rs                   # IR representation
│   └── error.rs                # Error types
├── examples/
│   ├── basic_insert.rs
│   └── type_safe_query.rs
└── tests/
    └── integration_test.rs
```

**Example: Rust API**
```rust
// bindings/rust/src/lib.rs
use serde::{Deserialize, Serialize};

/// Type-safe value with Rust enum
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TypedValue {
    Nat(u64),
    BoundedNat { min: u64, max: u64, value: u64 },
    NonEmptyString(String),
    PromptScores(PromptScores),
}

/// INSERT statement builder (Rust-idiomatic API)
pub struct InsertBuilder {
    table: String,
    columns: Vec<String>,
    values: Vec<TypedValue>,
    rationale: String,
}

impl InsertBuilder {
    pub fn new(table: impl Into<String>) -> Self {
        Self {
            table: table.into(),
            columns: Vec::new(),
            values: Vec::new(),
            rationale: String::new(),
        }
    }

    pub fn column(mut self, name: impl Into<String>, value: TypedValue) -> Self {
        self.columns.push(name.into());
        self.values.push(value);
        self
    }

    pub fn rationale(mut self, text: impl Into<String>) -> Self {
        self.rationale = text.into();
        self
    }

    pub fn build(self) -> Result<InsertStmt, Error> {
        // Validate via Zig FFI
        unsafe {
            let stmt = gqldt_sys::gqldt_insert_create(
                self.table.as_ptr() as *const i8,
                self.columns.as_ptr() as *const *const i8,
                self.columns.len(),
                self.values.as_ptr() as *const gqldt_sys::FbqlDt_TypedValue,
                self.values.len(),
                self.rationale.as_ptr() as *const i8,
            );

            if stmt.is_null() {
                return Err(Error::InvalidInsert);
            }

            Ok(InsertStmt { inner: stmt })
        }
    }
}

// Usage example
fn main() -> Result<(), Error> {
    let insert = InsertBuilder::new("evidence")
        .column("title", TypedValue::NonEmptyString("ONS Data".to_string()))
        .column("prompt_provenance", TypedValue::BoundedNat {
            min: 0,
            max: 100,
            value: 95,
        })
        .rationale("Official statistics")
        .build()?;

    // Execute on Lithoglyph
    insert.execute(&database)?;
    Ok(())
}
```

**FFI Integration (Rust ↔ Zig):**
```rust
// bindings/rust/src/ffi.rs
#[link(name = "gqldt", kind = "static")]
extern "C" {
    fn gqldt_insert_create(
        table: *const i8,
        columns: *const *const i8,
        column_count: usize,
        values: *const TypedValue,
        value_count: usize,
        rationale: *const i8,
    ) -> *mut InsertStmt;

    fn gqldt_insert_execute(
        stmt: *const InsertStmt,
        db: *mut Database,
    ) -> i32;

    fn gqldt_insert_free(stmt: *mut InsertStmt);
}
```

**Build Script (build.rs):**
```rust
// bindings/rust/build.rs
use std::env;
use std::path::PathBuf;

fn main() {
    // Tell cargo to link with Zig FFI library
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    // Build Zig FFI
    let status = std::process::Command::new("zig")
        .args(&["build", "-Drelease-safe"])
        .current_dir("../../ffi/zig")
        .status()
        .expect("Failed to build Zig FFI");

    if !status.success() {
        panic!("Zig build failed");
    }

    // Link with Zig library
    println!("cargo:rustc-link-search=../../ffi/zig/zig-out/lib");
    println!("cargo:rustc-link-lib=static=gqldt");

    // Re-run if Zig sources change
    println!("cargo:rerun-if-changed=../../ffi/zig/src");
}
```

**Cargo.toml:**
```toml
[package]
name = "gqldt"
version = "0.1.0"
authors = ["Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>"]
edition = "2021"
license = "PMPL-1.0-or-later"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_cbor = "0.11"  # For CBOR proof blobs

[build-dependencies]
# Zig FFI built via build.rs

[dev-dependencies]
criterion = "0.5"  # For benchmarks
```

---

## 3. Julia Bindings

**Priority:** MEDIUM - Batch scripts, data processing (per RSR)

**Location:** `bindings/julia/`

**Directory Structure:**
```
bindings/julia/
├── Project.toml
├── src/
│   ├── FbqlDt.jl              # Main module
│   ├── ffi.jl                 # ccall bindings
│   ├── insert.jl              # INSERT API
│   ├── select.jl              # SELECT API
│   └── types.jl               # Julia type definitions
├── examples/
│   └── basic_usage.jl
└── test/
    └── runtests.jl
```

**Example: Julia API**
```julia
# bindings/julia/src/FbqlDt.jl
module FbqlDt

# Low-level FFI (ccall to Zig)
module FFI
    const libgqldt = "/path/to/libgqldt.so"

    function insert_create(table::String, columns::Vector{String},
                           values::Vector{TypedValue}, rationale::String)
        ccall(
            (:gqldt_insert_create, libgqldt),
            Ptr{Cvoid},
            (Cstring, Ptr{Cstring}, Csize_t, Ptr{Cvoid}, Csize_t, Cstring),
            table, columns, length(columns), values, length(values), rationale
        )
    end

    function insert_execute(stmt::Ptr{Cvoid}, db::Ptr{Cvoid})
        ccall(
            (:gqldt_insert_execute, libgqldt),
            Cint,
            (Ptr{Cvoid}, Ptr{Cvoid}),
            stmt, db
        )
    end
end

# High-level Julia API
abstract type TypedValue end

struct Nat <: TypedValue
    value::UInt64
end

struct BoundedNat <: TypedValue
    min::UInt64
    max::UInt64
    value::UInt64

    function BoundedNat(min, max, value)
        if !(min <= value <= max)
            throw(DomainError(value, "Value $value not in [$min, $max]"))
        end
        new(min, max, value)
    end
end

struct NonEmptyString <: TypedValue
    value::String

    function NonEmptyString(s::String)
        if isempty(s)
            throw(ArgumentError("String cannot be empty"))
        end
        new(s)
    end
end

# INSERT builder (Julia-idiomatic)
mutable struct InsertBuilder
    table::String
    columns::Vector{String}
    values::Vector{TypedValue}
    rationale::String

    InsertBuilder(table::String) = new(table, String[], TypedValue[], "")
end

function column!(builder::InsertBuilder, name::String, value::TypedValue)
    push!(builder.columns, name)
    push!(builder.values, value)
    builder
end

rationale!(builder::InsertBuilder, text::String) = (builder.rationale = text; builder)

function execute!(builder::InsertBuilder, db)
    stmt = FFI.insert_create(builder.table, builder.columns,
                             builder.values, builder.rationale)
    if stmt == C_NULL
        error("Failed to create INSERT statement")
    end

    result = FFI.insert_execute(stmt, db)
    if result != 0
        error("INSERT execution failed")
    end

    nothing
end

export TypedValue, Nat, BoundedNat, NonEmptyString
export InsertBuilder, column!, rationale!, execute!

end # module FbqlDt

# Usage example
using FbqlDt

insert = InsertBuilder("evidence")
column!(insert, "title", NonEmptyString("ONS Data"))
column!(insert, "prompt_provenance", BoundedNat(0, 100, 95))
rationale!(insert, "Official statistics")
execute!(insert, database)
```

**Project.toml:**
```toml
name = "FbqlDt"
uuid = "..." # Generate with UUIDs.uuid4()
authors = ["Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>"]
version = "0.1.0"

[compat]
julia = "1.9"
```

---

## 4. Gleam Bindings

**Priority:** MEDIUM - Backend services on BEAM

**Location:** `bindings/gleam/`

**Directory Structure:**
```
bindings/gleam/
├── gleam.toml
├── src/
│   ├── gqldt.gleam           # Main module
│   ├── gqldt/
│   │   ├── ffi.gleam          # FFI to Zig (via NIF)
│   │   ├── insert.gleam       # INSERT API
│   │   ├── select.gleam       # SELECT API
│   │   └── types.gleam        # Gleam type definitions
└── test/
    └── gqldt_test.gleam
```

**Example: Gleam API**
```gleam
// bindings/gleam/src/gqldt/types.gleam
pub type TypedValue {
  Nat(Int)
  BoundedNat(min: Int, max: Int, value: Int)
  NonEmptyString(String)
  PromptScores(PromptScores)
}

pub type PromptScores {
  PromptScores(
    provenance: Int,
    replicability: Int,
    objective: Int,
    methodology: Int,
    publication: Int,
    transparency: Int,
    overall: Int,
  )
}

// bindings/gleam/src/gqldt/insert.gleam
pub type InsertBuilder {
  InsertBuilder(
    table: String,
    columns: List(String),
    values: List(TypedValue),
    rationale: String,
  )
}

pub fn new(table: String) -> InsertBuilder {
  InsertBuilder(table: table, columns: [], values: [], rationale: "")
}

pub fn column(
  builder: InsertBuilder,
  name: String,
  value: TypedValue,
) -> InsertBuilder {
  InsertBuilder(
    ..builder,
    columns: [name, ..builder.columns],
    values: [value, ..builder.values],
  )
}

pub fn rationale(builder: InsertBuilder, text: String) -> InsertBuilder {
  InsertBuilder(..builder, rationale: text)
}

pub fn execute(
  builder: InsertBuilder,
  db: Database,
) -> Result(Nil, String) {
  // Call Zig FFI via Erlang NIF
  case ffi.insert_create(
    builder.table,
    builder.columns,
    builder.values,
    builder.rationale,
  ) {
    Ok(stmt) -> ffi.insert_execute(stmt, db)
    Error(msg) -> Error(msg)
  }
}

// Usage example
import gqldt/insert
import gqldt/types.{BoundedNat, NonEmptyString}

pub fn main() {
  insert.new("evidence")
  |> insert.column("title", NonEmptyString("ONS Data"))
  |> insert.column("prompt_provenance", BoundedNat(0, 100, 95))
  |> insert.rationale("Official statistics")
  |> insert.execute(database)
}
```

**FFI via Erlang NIF:**
```gleam
// bindings/gleam/src/gqldt/ffi.gleam
@external(erlang, "gqldt_nif", "insert_create")
pub fn insert_create(
  table: String,
  columns: List(String),
  values: List(TypedValue),
  rationale: String,
) -> Result(InsertStmt, String)

@external(erlang, "gqldt_nif", "insert_execute")
pub fn insert_execute(stmt: InsertStmt, db: Database) -> Result(Nil, String)
```

**Erlang NIF (C/Zig bridge):**
```c
// bindings/gleam/c_src/gqldt_nif.c
#include <erl_nif.h>
#include "gqldt.h"  // From Idris2 ABI

static ERL_NIF_TERM insert_create(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    // Extract Erlang terms → C types
    // Call Zig FFI gqldt_insert_create()
    // Return Erlang term
}

static ERL_NIF_TERM insert_execute(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    // Call Zig FFI gqldt_insert_execute()
    // Return ok/error tuple
}

static ErlNifFunc nif_funcs[] = {
    {"insert_create", 4, insert_create},
    {"insert_execute", 2, insert_execute},
};

ERL_NIF_INIT(gqldt_nif, nif_funcs, NULL, NULL, NULL, NULL)
```

---

## 5. Elixir Bindings

**Priority:** MEDIUM - Distributed systems, Phoenix backend

**Location:** `bindings/elixir/`

**Directory Structure:**
```
bindings/elixir/
├── mix.exs
├── lib/
│   ├── gql_dt.ex             # Main module
│   ├── gql_dt/
│   │   ├── insert.ex          # INSERT API
│   │   ├── select.ex          # SELECT API
│   │   ├── types.ex           # Elixir type specs
│   │   └── nif.ex             # NIF wrapper
└── test/
    └── gql_dt_test.exs
```

**Example: Elixir API**
```elixir
# bindings/elixir/lib/gql_dt/types.ex
defmodule FbqlDt.Types do
  @type typed_value ::
          {:nat, non_neg_integer()}
          | {:bounded_nat, non_neg_integer(), non_neg_integer(), non_neg_integer()}
          | {:non_empty_string, String.t()}
          | {:prompt_scores, prompt_scores()}

  @type prompt_scores :: %{
          provenance: non_neg_integer(),
          replicability: non_neg_integer(),
          objective: non_neg_integer(),
          methodology: non_neg_integer(),
          publication: non_neg_integer(),
          transparency: non_neg_integer(),
          overall: non_neg_integer()
        }
end

# bindings/elixir/lib/gql_dt/insert.ex
defmodule FbqlDt.Insert do
  alias FbqlDt.Types

  defstruct table: "", columns: [], values: [], rationale: ""

  @type t :: %__MODULE__{
          table: String.t(),
          columns: [String.t()],
          values: [Types.typed_value()],
          rationale: String.t()
        }

  @spec new(String.t()) :: t()
  def new(table), do: %__MODULE__{table: table}

  @spec column(t(), String.t(), Types.typed_value()) :: t()
  def column(%__MODULE__{} = insert, name, value) do
    %{insert | columns: [name | insert.columns], values: [value | insert.values]}
  end

  @spec rationale(t(), String.t()) :: t()
  def rationale(%__MODULE__{} = insert, text) do
    %{insert | rationale: text}
  end

  @spec execute(t(), pid()) :: :ok | {:error, String.t()}
  def execute(%__MODULE__{} = insert, database) do
    case FbqlDt.NIF.insert_create(
           insert.table,
           insert.columns,
           insert.values,
           insert.rationale
         ) do
      {:ok, stmt} -> FbqlDt.NIF.insert_execute(stmt, database)
      {:error, msg} -> {:error, msg}
    end
  end
end

# Usage example
alias FbqlDt.Insert

Insert.new("evidence")
|> Insert.column("title", {:non_empty_string, "ONS Data"})
|> Insert.column("prompt_provenance", {:bounded_nat, 0, 100, 95})
|> Insert.rationale("Official statistics")
|> Insert.execute(database)
```

**mix.exs:**
```elixir
defmodule FbqlDt.MixProject do
  use Mix.Project

  def project do
    [
      app: :gql_dt,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.6", runtime: false}
    ]
  end
end
```

---

## 6. Haskell Bindings

**Priority:** LOW-MEDIUM - Scaffoldia CLI, type-heavy tools

**Location:** `bindings/haskell/`

**Directory Structure:**
```
bindings/haskell/
├── gqldt.cabal
├── src/
│   ├── FbqlDt.hs              # Main module
│   ├── FbqlDt/
│   │   ├── FFI.hs             # Low-level FFI
│   │   ├── Insert.hs          # INSERT API
│   │   ├── Select.hs          # SELECT API
│   │   └── Types.hs           # Haskell type definitions
└── test/
    └── Spec.hs
```

**Example: Haskell API**
```haskell
-- bindings/haskell/src/FbqlDt/Types.hs
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}

module FbqlDt.Types where

import Data.Word (Word64)
import GHC.TypeLits (Nat, KnownNat)

-- Type-indexed values (similar to GQL-DT!)
data TypedValue :: Type -> Type where
  Nat :: Word64 -> TypedValue Word64
  BoundedNat ::
    (KnownNat min, KnownNat max) =>
    Word64 ->
    TypedValue (BoundedNat min max)
  NonEmptyString :: String -> TypedValue NonEmptyString

-- Phantom type for bounded natural
data BoundedNat (min :: Nat) (max :: Nat)

data NonEmptyString

-- bindings/haskell/src/FbqlDt/Insert.hs
module FbqlDt.Insert where

import FbqlDt.Types
import qualified FbqlDt.FFI as FFI

data InsertBuilder = InsertBuilder
  { table :: String,
    columns :: [String],
    values :: [SomeTypedValue],  -- Existential wrapper
    rationale :: String
  }

-- Existential wrapper for TypedValue
data SomeTypedValue where
  SomeTypedValue :: TypedValue a -> SomeTypedValue

new :: String -> InsertBuilder
new tbl = InsertBuilder tbl [] [] ""

column :: String -> TypedValue a -> InsertBuilder -> InsertBuilder
column name val builder =
  builder
    { columns = name : columns builder,
      values = SomeTypedValue val : values builder
    }

setRationale :: String -> InsertBuilder -> InsertBuilder
setRationale text builder = builder {rationale = text}

execute :: InsertBuilder -> IO (Either String ())
execute builder = do
  result <- FFI.insertCreate (table builder) (columns builder) (values builder) (rationale builder)
  case result of
    Left err -> return $ Left err
    Right stmt -> FFI.insertExecute stmt

-- Usage example (with type-level safety!)
example :: IO ()
example = do
  result <-
    execute $
      setRationale "Official statistics" $
        column "prompt_provenance" (BoundedNat @0 @100 95) $
          column "title" (NonEmptyString "ONS Data") $
            new "evidence"
  case result of
    Left err -> putStrLn $ "Error: " ++ err
    Right () -> putStrLn "Success!"
```

**FFI (Haskell ↔ Zig):**
```haskell
-- bindings/haskell/src/FbqlDt/FFI.hs
{-# LANGUAGE ForeignFunctionInterface #-}

module FbqlDt.FFI where

import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr)

foreign import ccall "gqldt_insert_create"
  c_insert_create ::
    CString ->        -- table
    Ptr CString ->    -- columns
    CSize ->          -- column_count
    Ptr () ->         -- values
    CSize ->          -- value_count
    CString ->        -- rationale
    IO (Ptr ())

insertCreate :: String -> [String] -> [SomeTypedValue] -> String -> IO (Either String (Ptr ()))
insertCreate table columns values rationale = do
  -- Marshal Haskell types to C
  -- Call c_insert_create
  -- Handle errors
  undefined -- Implementation details
```

---

## 7. Deno/JavaScript Bindings

**Priority:** MEDIUM - Runtime, glue code, MCP protocol

**Location:** `bindings/deno/`

**Directory Structure:**
```
bindings/deno/
├── deno.json
├── mod.ts                     # Main Deno module
├── src/
│   ├── ffi.ts                 # Deno FFI (dlopen)
│   ├── insert.ts              # INSERT API
│   ├── select.ts              # SELECT API
│   └── types.ts               # TypeScript type definitions
└── examples/
    └── basic_usage.ts
```

**Example: Deno API**
```typescript
// bindings/deno/src/types.ts
export type TypedValue =
  | { type: "nat"; value: number }
  | { type: "bounded_nat"; min: number; max: number; value: number }
  | { type: "non_empty_string"; value: string }
  | { type: "prompt_scores"; value: PromptScores };

export interface PromptScores {
  provenance: number;
  replicability: number;
  objective: number;
  methodology: number;
  publication: number;
  transparency: number;
  overall: number;
}

// bindings/deno/src/ffi.ts
import { dlopen } from "https://deno.land/x/plug/mod.ts";

const lib = await dlopen("./libgqldt.so", {
  gqldt_insert_create: {
    parameters: ["buffer", "buffer", "usize", "buffer", "usize", "buffer"],
    result: "pointer",
  },
  gqldt_insert_execute: {
    parameters: ["pointer", "pointer"],
    result: "i32",
  },
});

export const FFI = {
  insertCreate: lib.symbols.gqldt_insert_create,
  insertExecute: lib.symbols.gqldt_insert_execute,
};

// bindings/deno/src/insert.ts
import { FFI } from "./ffi.ts";
import type { TypedValue } from "./types.ts";

export class InsertBuilder {
  constructor(
    private table: string,
    private columns: string[] = [],
    private values: TypedValue[] = [],
    private rationale: string = "",
  ) {}

  column(name: string, value: TypedValue): this {
    this.columns.push(name);
    this.values.push(value);
    return this;
  }

  setRationale(text: string): this {
    this.rationale = text;
    return this;
  }

  async execute(database: unknown): Promise<void> {
    // Marshall to C FFI
    // Call FFI.insertCreate()
    // Call FFI.insertExecute()
  }
}

// Usage example
import { InsertBuilder } from "./mod.ts";

await new InsertBuilder("evidence")
  .column("title", { type: "non_empty_string", value: "ONS Data" })
  .column("prompt_provenance", { type: "bounded_nat", min: 0, max: 100, value: 95 })
  .setRationale("Official statistics")
  .execute(database);
```

---

## 8. Ada Bindings

**Priority:** LOW - Safety-critical systems (where required per ecosystem)

**Location:** `bindings/ada/`

**Note:** Ada bindings follow same pattern as other languages but use Ada's package system and GNAT FFI (Interfaces.C).

---

## Language Priority Summary

| Language | Priority | Use Case | Status |
|----------|----------|----------|--------|
| **ReScript** | ✅ CRITICAL | Web, apps, primary development | ✅ Specified |
| **Rust** | 🔥 HIGH | Systems, CLI, performance | ⏳ Spec ready |
| **Zig** | ✅ CRITICAL | FFI layer (universal) | ✅ Core |
| **Julia** | ⚠️ MEDIUM | Batch, data processing | ⏳ Spec ready |
| **Gleam** | ⚠️ MEDIUM | BEAM backend services | ⏳ Spec ready |
| **Elixir** | ⚠️ MEDIUM | Distributed systems | ⏳ Spec ready |
| **Haskell** | ⚠️ LOW-MEDIUM | Scaffoldia, type-heavy tools | ⏳ Spec ready |
| **Deno/JS** | ⚠️ MEDIUM | Runtime, glue, MCP | ⏳ Spec ready |
| **Ada** | ⚠️ LOW | Safety-critical (if needed) | 📝 Noted |

---

## Common Patterns Across All Bindings

### 1. Builder Pattern
All languages use ergonomic builder APIs:
```
new(table) → column(name, value) → rationale(text) → execute()
```

### 2. Type Safety
Type systems leveraged where possible:
- Rust: Enums + Result types
- Haskell: GADTs + phantom types
- ReScript: Variants + polymorphic variants
- Gleam: Custom types + Result
- Elixir: Type specs + structs

### 3. Error Handling
All bindings return `Result`/`Either`/tuple types:
- Rust: `Result<T, Error>`
- ReScript: `result<'a, 'e>`
- Gleam: `Result(a, String)`
- Elixir: `{:ok, value} | {:error, msg}`
- Haskell: `Either String a`

### 4. FFI Safety
All bindings validate inputs before calling Zig FFI:
- Non-null strings
- Array bounds
- Type tags

---

## Implementation Timeline

### M9: ReScript Bindings (PRIORITY)
- [ ] Create `bindings/rescript/` structure
- [ ] Implement FFI bindings to Zig
- [ ] Builder API with type safety
- [ ] Examples and documentation
- [ ] WASM compatibility

### M10: Rust Bindings
- [ ] Create `bindings/rust/` structure
- [ ] Cargo.toml + build.rs
- [ ] FFI bindings via unsafe blocks
- [ ] Safe Rust API wrapper
- [ ] Examples and tests

### M11: Julia + Deno Bindings
- [ ] Julia: `bindings/julia/` with ccall
- [ ] Deno: `bindings/deno/` with dlopen
- [ ] Examples for both

### M12: BEAM Bindings (Gleam + Elixir)
- [ ] Erlang NIF (C bridge to Zig)
- [ ] Gleam bindings
- [ ] Elixir bindings
- [ ] Phoenix integration example

### M13: Haskell Bindings (Low Priority)
- [ ] Haskell FFI via Foreign.C
- [ ] GADT-based type-safe API
- [ ] Scaffoldia integration

---

**Document Status:** Complete language binding specifications

**Next Steps:**
1. Complete M6 Parser (typed IR generation)
2. Complete M7 Idris2 ABI + M8 Zig FFI (foundation for all bindings)
3. Implement M9 ReScript bindings (highest priority)
4. Implement remaining bindings based on ecosystem needs

**See Also:**
- `docs/INTEGRATION.md` - ReScript, WASM, ABI/FFI architecture
- `docs/EXECUTION-STRATEGY.md` - Why native IR execution
- `~/abi-migration-guide.md` - Idris2 ABI + Zig FFI universal standard
