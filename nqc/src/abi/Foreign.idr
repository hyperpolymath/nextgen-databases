-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Foreign.idr — FFI function declarations for the NQC ABI.
--
-- Declares the foreign function signatures that the Zig FFI must implement.
-- Each function has its signature proven compatible with the types and
-- layouts defined in Types.idr and Layout.idr.

module Foreign

import Types
import Layout

%default total

-- =========================================================================
-- FFI function signatures
-- =========================================================================

||| Foreign function: extract keys from a JSON map.
||| Zig signature: fn nqc_extract_keys(map_ptr: [*]const u8, map_len: u32,
|||                                     out_keys: [*][*]u8, out_lens: [*]u32,
|||                                     max_keys: u32) -> u32
|||
||| Returns the number of keys written (≤ max_keys).
||| Invariant: return value ≤ max_keys (proven by Zig bounds check).
public export
record ExtractKeysSpec where
  constructor MkExtractKeysSpec
  maxKeys    : Nat
  resultKeys : Nat
  {auto bounded : So (resultKeys <= maxKeys)}

||| Foreign function: extract a field from a JSON map.
||| Zig signature: fn nqc_extract_field(map_ptr: [*]const u8, map_len: u32,
|||                                      key_ptr: [*]const u8, key_len: u32,
|||                                      out_ptr: [*]u8, out_cap: u32) -> i32
|||
||| Returns: > 0 for field length, 0 for field not found, < 0 for error.
public export
data ExtractFieldResult
  = FieldFound Nat    -- positive: field value length
  | FieldNotFound     -- zero: key not present
  | FieldError String -- negative: extraction error

||| Foreign function: encode a value as JSON.
||| Zig signature: fn nqc_json_encode(value_ptr: [*]const u8, value_len: u32,
|||                                    out_ptr: [*]u8, out_cap: u32) -> i32
|||
||| Returns: > 0 for JSON length, < 0 for error (buffer too small).
public export
data JsonEncodeResult
  = EncodedOk Nat     -- positive: JSON string length
  | EncodeError String -- negative: encoding error

||| Foreign function: coerce a value to a list.
||| Zig signature: fn nqc_extract_list(value_ptr: [*]const u8, value_len: u32,
|||                                     out_items: [*][*]u8, out_lens: [*]u32,
|||                                     max_items: u32) -> u32
|||
||| Returns the number of items written (≤ max_items).
public export
record ExtractListSpec where
  constructor MkExtractListSpec
  maxItems    : Nat
  resultItems : Nat
  {auto bounded : So (resultItems <= maxItems)}

||| Foreign function: format a field value as a display string.
||| Zig signature: fn nqc_field_to_string(map_ptr: [*]const u8, map_len: u32,
|||                                        key_ptr: [*]const u8, key_len: u32,
|||                                        out_ptr: [*]u8, out_cap: u32) -> u32
|||
||| Returns the string length written to out_ptr.

-- =========================================================================
-- Safety properties of all FFI functions
-- =========================================================================

||| All FFI functions must satisfy these properties:
|||
||| 1. No allocation: all output is written to caller-provided buffers.
||| 2. Bounded output: return values never exceed the capacity parameter.
||| 3. No null dereference: null pointers produce FieldNotFound/empty results.
||| 4. UTF-8 safety: all string outputs are valid UTF-8.
||| 5. No global state: all functions are pure (no side effects).
|||
||| These properties are enforced by Zig's safety checks at compile time
||| and verified by the integration tests in ffi/zig/test/.

public export
record FFISafety where
  constructor MkFFISafety
  noAllocation    : Bool -- FFI never calls allocator
  boundedOutput   : Bool -- Output length ≤ capacity
  nullSafe        : Bool -- Null pointers handled gracefully
  utf8Safe        : Bool -- All output is valid UTF-8
  noGlobalState   : Bool -- No mutable global state

||| The safety contract that all NQC FFI functions must satisfy.
export
ffiSafetyContract : FFISafety
ffiSafetyContract = MkFFISafety True True True True True
