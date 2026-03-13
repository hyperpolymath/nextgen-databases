# Glyphbase Zig FFI - Lithoglyph Integration

This directory contains the Zig FFI implementation that integrates Glyphbase with the Lithoglyph database.

## Architecture

Following the **hyperpolymath ABI/FFI Universal Standard**:

- **ABI Layer**: `../../../src/abi/*.idr` (Idris2 with formal proofs)
- **FFI Layer**: This directory (Zig with C-compatible exports)
- **Database Engine**: Lithoglyph core-zig (imported as dependency)

## Building

### Prerequisites

1. **Zig** (0.13.0 or later)
2. **Lithoglyph repository** cloned at `~/Documents/hyperpolymath-repos/lithoglyph`
3. **Erlang/OTP** (for NIF headers)

### Environment Variables

```bash
# Optional: Override Lithoglyph path
export LITHOGLYPH_PATH=~/Documents/hyperpolymath-repos/lithoglyph/lith/database/core-zig

# Optional: Override ERTS include directory
export ERTS_INCLUDE_DIR=/usr/lib/erlang/usr/include
```

### Build Commands

```bash
# Build the NIF shared library
zig build

# Output: ../../priv/liblith_nif.so (Linux)
#         ../../priv/liblith_nif.dylib (macOS)
#         ../../priv/lith_nif.dll (Windows)

# Run unit tests
zig build test

# Run integration tests
zig build test-integration
```

## Integration with Gleam

The compiled NIF library is loaded by the Gleam server via `src/lith/nif_ffi.gleam`:

```gleam
@external(erlang, "lith_nif", "db_open")
pub fn nif_db_open(path: BitArray) -> DbHandle
```

## API Functions

All functions are exported with C calling convention:

| Function | Description |
|----------|-------------|
| `lith_nif_version` | Get NIF version (0.1.0) |
| `lith_nif_db_open` | Open database connection |
| `lith_nif_db_close` | Close database connection |
| `lith_nif_txn_begin` | Begin transaction (read-only or read-write) |
| `lith_nif_txn_commit` | Commit transaction |
| `lith_nif_txn_abort` | Abort transaction |
| `lith_nif_apply` | Apply CBOR-encoded operation |
| `lith_nif_schema` | Get database schema (CBOR-encoded) |
| `lith_nif_journal` | Get journal entries since timestamp |

## Lithoglyph Core Integration

This FFI wraps the Lithoglyph core-zig library (`lithoglyph/lith/database/core-zig`):

```zig
const lithoglyph = @import("lithoglyph");

// Use Lithoglyph types
const FdbDb = lithoglyph.FdbDb;
const FdbTxn = lithoglyph.FdbTxn;
const FdbStatus = lithoglyph.types.FdbStatus;

// Call Lithoglyph functions
const status = lithoglyph.fdb_db_open(
    path.ptr,
    path.len,
    null, // options
    0,    // options_len
    &out_db,
    &out_err,
);
```

## Memory Management

- **Allocator**: Uses `std.heap.GeneralPurposeAllocator` for all allocations
- **Handle Management**: Lithoglyph core-zig maintains handle registries
- **Error Blobs**: CBOR-encoded error messages allocated by Lithoglyph
- **Provenance Data**: Returned as CBOR blobs from operations

## Error Handling

All functions return status codes or NULL pointers on error:

```zig
// Success: returns non-null pointer
const db = lith_nif_db_open("/path/to/database.ldb");

// Error: returns null
if (db == null) {
    // Error logged via std.log.err
}
```

## CBOR Encoding

Operations, results, and provenance use CBOR encoding:

- **Operations**: `{"op": "insert", "collection": "docs", "data": {...}}`
- **Results**: `{"status": "ok", "doc_id": 123}`
- **Provenance**: `{"actor": "user", "timestamp": "...", "rationale": "..."}`

## TODO

- [ ] Implement schema retrieval (currently returns empty map)
- [ ] Implement journal retrieval (currently returns empty array)
- [ ] Add CBOR parsing for extracting block IDs from results
- [ ] Add comprehensive error handling with detailed error messages
- [ ] Add performance benchmarks
- [ ] Add fuzzing tests

## See Also

- [ABI Documentation](../../../src/abi/README.md) - Idris2 ABI with proofs
- [Lithoglyph Core](~/Documents/hyperpolymath-repos/lithoglyph/lith/database/core-zig) - Database engine
- [Server Integration](../../README.md) - Gleam server using this NIF
