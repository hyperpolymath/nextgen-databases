# Lith ABI/FFI Architecture

This document describes the **Idris2 ABI + Zig FFI** architecture used for Lith/Lithoglyph database integration.

## Architecture Overview

Following the **hyperpolymath ABI/FFI Universal Standard**, this codebase uses:

| Layer | Language | Purpose | Location |
|-------|----------|---------|----------|
| **ABI** | **Idris2** | Interface definitions with formal proofs | `src/abi/*.idr` |
| **FFI** | **Zig** | C-compatible implementation | `ffi/zig/src/*.zig` |
| **Headers** | C (generated) | Bridge between ABI and FFI | `generated/abi/*.h` |

## Why This Architecture?

### Idris2 for ABI

- **Dependent types** prove interface correctness at compile-time
- **Formal verification** of memory layout (alignment, padding, size)
- **Platform-specific ABIs** with compile-time selection
- **Provable backward compatibility** between versions
- **Type-level guarantees** impossible in C/Zig/Rust
- **Self-documenting** with mathematical proofs

### Zig for FFI

- **Native C ABI compatibility** without overhead
- **Memory-safe by default**
- **Cross-compilation built-in** (any platform, any architecture)
- **No runtime dependencies**
- **Zero-cost abstractions**
- **Better error handling** than C, simpler than Rust FFI

## Directory Structure

```
server/
├── src/
│   ├── abi/                  # Idris2 ABI definitions
│   │   ├── Types.idr         # Type definitions with proofs
│   │   ├── Layout.idr        # Memory layout verification
│   │   └── Foreign.idr       # FFI declarations
│   └── lith/               # Gleam client wrapper
│       ├── client.gleam      # High-level API
│       └── nif_ffi.gleam     # Low-level NIF bindings
│
├── ffi/
│   └── zig/                  # Zig FFI implementation
│       ├── build.zig         # Build script
│       ├── src/
│       │   └── main.zig      # C-compatible implementation
│       └── test/
│           └── integration_test.zig
│
└── priv/                     # Compiled NIF libraries
    └── lith_nif.so         # Built from Zig
```

## API Surface

### Core Types

```idris
-- Non-null database handle (proven at type level)
data DbHandle : Type where
  MkDbHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> DbHandle

-- Non-null transaction handle (proven at type level)
data TxnHandle : Type where
  MkTxnHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> TxnHandle

-- Transaction mode
data TxnMode = ReadOnly | ReadWrite

-- Result type (matches Erlang {ok, Value} | {error, Reason})
data FFIResult a = Ok a | Error String
```

### Core Functions

```idris
-- Get NIF version
nifVersion : IO Version

-- Database operations
dbOpen : DbPath -> IO (FFIResult DbHandle)
dbClose : DbHandle -> IO (FFIResult ())

-- Transaction operations
txnBegin : DbHandle -> TxnMode -> IO (FFIResult TxnHandle)
txnCommit : TxnHandle -> IO (FFIResult ())
txnAbort : TxnHandle -> IO (FFIResult ())

-- Database operations
applyOperation : TxnHandle -> OperationData -> IO (FFIResult (BlockId, Maybe (List Bits8)))
getSchema : DbHandle -> IO (FFIResult SchemaData)
getJournal : DbHandle -> Timestamp -> IO (FFIResult JournalData)
```

## Memory Layout Guarantees

The `Layout.idr` module provides compile-time proofs:

1. **Pointer sizes** are 8 bytes on all supported platforms
2. **Pointer alignment** matches size (8-byte aligned)
3. **Handle types** are always pointer-sized (stable ABI)
4. **No padding** in Version struct (3 bytes total)
5. **Cross-platform compatibility** (Linux, macOS, Windows on x86_64/ARM64)

## Building

### Build Zig NIF

```bash
cd ffi/zig
zig build
# Output: ../../priv/liblith_nif.so
```

### Run Tests

```bash
cd ffi/zig
zig build test                # Unit tests
zig build test-integration    # Integration tests
```

### Verify Idris2 ABI

```bash
cd src/abi
idris2 --check Types.idr
idris2 --check Layout.idr
idris2 --check Foreign.idr
```

## Integration with Gleam

The Gleam client (`src/lith/client.gleam`) wraps the NIF functions:

```gleam
pub fn connect(path: String) -> LithResult(Connection) {
  let path_binary = bit_array.from_string(path)
  let handle = nif_ffi.nif_db_open(path_binary)
  Ok(Connection(handle: handle))
}

pub fn begin_transaction(conn: Connection, mode: TransactionMode) -> LithResult(Transaction) {
  let mode_binary = transaction_mode_to_binary(mode)
  let result = nif_ffi.nif_txn_begin(conn.handle, mode_binary)
  // ... handle Erlang {ok, Handle} | {error, Reason} tuples
}
```

## TODO: Integration with Lithoglyph

Currently, the Zig FFI contains **placeholder implementations**. To integrate with the real Lithoglyph database:

1. **Add Lithoglyph dependency** to `ffi/zig/build.zig`
2. **Replace placeholder structs** in `main.zig` with real Lithoglyph handles
3. **Implement CBOR parsing** for operations
4. **Call Lithoglyph C API** from Zig functions
5. **Add provenance tracking** integration

## Proofs Required

Every ABI must prove (see `Types.idr` and `Layout.idr`):

1. ✅ **Type Safety**: Opaque handles prevent null pointers
2. ✅ **Layout Correctness**: Struct size and alignment match platform
3. ✅ **Platform Compatibility**: Same ABI works on all platforms
4. ⏳ **Version Compatibility**: New versions don't break old ABIs (WIP)

## See Also

- [Hyperpolymath ABI/FFI Standard](~/.claude/CLAUDE.md#abi-ffi-universal-standard)
- [RSR Template ABI/FFI](~/Documents/hyperpolymath-repos/rsr-template-repo/ABI-FFI-README.md)
- [Proven Library](~/Documents/hyperpolymath-repos/proven) - Idris2 proofs library
- [Ephapax](~/Documents/hyperpolymath-repos/ephapax) - Reference Idris2 + Zig FFI implementation
