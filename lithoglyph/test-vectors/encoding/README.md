# Encoding Test Vectors

SPDX-License-Identifier: PMPL-1.0-or-later

Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

Test vectors for Lithoglyph's binary encoding formats. These vectors validate
implementations in Zig (`core-zig/src/blocks.zig`, `core-zig/src/cbor.zig`),
Forth (`core-forth/src/lithoglyph-blocks.fs`), and BEAM NIFs
(`beam/native/src/lith_nif.zig`).

## Files

| File | Description |
|------|-------------|
| `block-header.json` | Block header format (64 bytes, little-endian) |
| `block-payload.json` | Block payload formats (documents, edges, schemas, superblock) |
| `journal-entry.json` | WAL journal entry format (48-byte header + variable payloads) |
| `cbor-roundtrip.json` | CBOR serialization/deserialization per RFC 8949 |

## Test Vector Format

Each JSON file follows this structure:

```json
{
  "description": "What these test vectors cover",
  "constants": { "...relevant constants from the codebase..." },
  "vectors": [
    {
      "name": "valid_example",
      "description": "Human-readable explanation",
      "input": "...",
      "expected": "...",
      "valid": true
    },
    {
      "name": "invalid_example",
      "description": "Human-readable explanation",
      "input": "...",
      "expected_error": "ErrorType",
      "valid": false
    }
  ]
}
```

Every vector has a `valid` boolean indicating whether the input should be
accepted (`true`) or rejected (`false`). Invalid vectors include an
`expected_error` field.

## Constants Reference

These constants are defined in the codebase and used throughout the test
vectors:

### Block Format (`core-zig/src/blocks.zig`)

| Constant | Value | Description |
|----------|-------|-------------|
| `BLOCK_SIZE` | 4096 | Block size in bytes (4 KiB) |
| `HEADER_SIZE` | 64 | Block header size in bytes |
| `PAYLOAD_SIZE` | 4032 | Block payload size (4096 - 64) |
| `BLOCK_MAGIC` | `0x4C474800` | Magic bytes "LGH\0" |
| `BLOCK_VERSION` | 1 | Current block format version |

### Journal Format (`spec/journal.adoc`)

| Constant | Value | Description |
|----------|-------|-------------|
| `JOURNAL_MAGIC` | `0x4644424A` | Magic bytes (legacy "FDBJ", retained for format compatibility) |
| `ENTRY_HEADER_SIZE` | 48 | Journal entry header size |
| `MIN_JOURNAL_ENTRY_SIZE` | 21 | Minimum entry (header fields only) |
| `MAX_JOURNAL_ENTRY_SIZE` | 10485760 | Maximum entry (10 MB) |

### CBOR Tags (`core-zig/src/types.zig`)

| Tag | Name | Description |
|-----|------|-------------|
| 0 | datetime | RFC 3339 datetime (standard) |
| 32 | uri | URI (standard) |
| 55799 | self_described | Self-described CBOR (standard) |
| 39001 | block_reference | Lithoglyph block reference |
| 39002 | document_id | Lithoglyph document ID |
| 39003 | collection_name | Lithoglyph collection name |
| 39004 | provenance | Lithoglyph provenance payload |
| 39005 | actor | Lithoglyph actor information |
| 39006 | prompt_score | Lithoglyph PROMPT evidence score |
| 39007 | functional_dependency | Lithoglyph FD for normalizer |
| 39008 | proof | Lithoglyph GQLdt proof blob |

## Byte Order

All multi-byte integer fields in block headers and journal entries are
**little-endian** (matching the Zig `extern struct` layout on x86_64/ARM64).

CBOR uses **big-endian** (network byte order) per RFC 8949.

## Checksum Algorithm

Block and journal checksums use **CRC32C** (Castagnoli polynomial
`0x82F63B78`), as implemented in `core-zig/src/blocks.zig`. The CRC32C is
computed over the payload region (for blocks) or the entire entry (for journal
entries).

## How to Use

### Zig Tests

The `core-zig/src/blocks.zig` test suite validates block operations. These
test vectors extend coverage to edge cases and cross-language compatibility:

```zig
// Parse a test vector and validate
const vector = parseJsonVector("test-vectors/encoding/block-header.json");
for (vector.vectors) |v| {
    if (v.valid) {
        const header = parseHeader(v.input_fields);
        try header.validate();
    } else {
        const header = parseHeader(v.input_fields);
        try std.testing.expectError(header.validate(), v.expected_error);
    }
}
```

### BEAM/Elixir Tests

The test vectors can be loaded via Jason in ExUnit tests:

```elixir
test "block header validation" do
  {:ok, json} = File.read("test-vectors/encoding/block-header.json")
  {:ok, data} = Jason.decode(json)

  for vector <- data["vectors"] do
    if vector["valid"] do
      assert {:ok, _} = Lith.validate_header(vector["input_fields"])
    else
      assert {:error, _reason} = Lith.validate_header(vector["input_fields"])
    end
  end
end
```

### Forth Tests

The test vectors document the expected binary layout that the Forth block
implementation (`core-forth/src/lithoglyph-blocks.fs`) must produce.

## Relationship to Specifications

- Block format: `spec/blocks.adoc` (referenced from `core-zig/src/blocks.zig`)
- Journal format: `spec/journal.adoc`
- CBOR encoding: `spec/encoding.adoc`
- ABI types: `src/Lith/LithBridge.idr`, `src/Lith/LithLayout.idr`
- C bridge: `generated/abi/bridge.h`
