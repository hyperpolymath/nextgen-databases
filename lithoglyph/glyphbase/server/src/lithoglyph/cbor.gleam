// SPDX-License-Identifier: PMPL-1.0-or-later
// Simple CBOR encoder for Lithoglyph operations

import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}

/// CBOR major types
const major_unsigned = 0

const major_negative = 1

const major_bytes = 2

const major_text = 3

const major_array = 4

const major_map = 5

const major_simple = 7

/// Encode an unsigned integer
pub fn encode_unsigned(n: Int) -> BitArray {
  case n {
    _ if n < 24 -> <<{ major_unsigned * 32 + n }>>
    _ if n < 256 -> <<{ major_unsigned * 32 + 24 }, n:8>>
    _ if n < 65_536 -> <<{ major_unsigned * 32 + 25 }, n:16>>
    _ if n < 4_294_967_296 -> <<{ major_unsigned * 32 + 26 }, n:32>>
    _ -> <<{ major_unsigned * 32 + 27 }, n:64>>
  }
}

/// Encode a negative integer
pub fn encode_negative(n: Int) -> BitArray {
  let m = -1 - n
  case m {
    _ if m < 24 -> <<{ major_negative * 32 + m }>>
    _ if m < 256 -> <<{ major_negative * 32 + 24 }, m:8>>
    _ if m < 65_536 -> <<{ major_negative * 32 + 25 }, m:16>>
    _ if m < 4_294_967_296 -> <<{ major_negative * 32 + 26 }, m:32>>
    _ -> <<{ major_negative * 32 + 27 }, m:64>>
  }
}

/// Encode an integer (positive or negative)
pub fn encode_int(n: Int) -> BitArray {
  case n >= 0 {
    True -> encode_unsigned(n)
    False -> encode_negative(n)
  }
}

/// Encode a float (64-bit double precision)
pub fn encode_float(f: Float) -> BitArray {
  <<{ major_simple * 32 + 27 }, f:64-float>>
}

/// Encode a byte string
pub fn encode_bytes(data: BitArray) -> BitArray {
  let len = bit_array.byte_size(data)
  let header = encode_length(major_bytes, len)
  bit_array.concat([header, data])
}

/// Encode a UTF-8 text string
pub fn encode_text(text: String) -> BitArray {
  let bytes = <<text:utf8>>
  let len = bit_array.byte_size(bytes)
  let header = encode_length(major_text, len)
  bit_array.concat([header, bytes])
}

/// Encode an array header (call this, then encode each element)
pub fn encode_array_header(len: Int) -> BitArray {
  encode_length(major_array, len)
}

/// Encode an array with pre-encoded elements
pub fn encode_array(elements: List(BitArray)) -> BitArray {
  let header = encode_array_header(list.length(elements))
  bit_array.concat([header, ..elements])
}

/// Encode a map header (call this, then encode key-value pairs)
pub fn encode_map_header(len: Int) -> BitArray {
  encode_length(major_map, len)
}

/// Encode a map with pre-encoded key-value pairs
pub fn encode_map(pairs: List(#(BitArray, BitArray))) -> BitArray {
  let header = encode_map_header(list.length(pairs))
  let pairs_encoded =
    pairs
    |> list.flat_map(fn(pair) { [pair.0, pair.1] })
  bit_array.concat([header, ..pairs_encoded])
}

/// Encode a boolean
pub fn encode_bool(b: Bool) -> BitArray {
  case b {
    False -> <<{ major_simple * 32 + 20 }>>
    True -> <<{ major_simple * 32 + 21 }>>
  }
}

/// Encode null
pub fn encode_null() -> BitArray {
  <<{ major_simple * 32 + 22 }>>
}

/// Encode an optional value
pub fn encode_optional(opt: Option(a), encoder: fn(a) -> BitArray) -> BitArray {
  case opt {
    None -> encode_null()
    Some(value) -> encoder(value)
  }
}

/// Helper to encode length for a major type
fn encode_length(major: Int, len: Int) -> BitArray {
  case len {
    _ if len < 24 -> <<{ major * 32 + len }>>
    _ if len < 256 -> <<{ major * 32 + 24 }, len:8>>
    _ if len < 65_536 -> <<{ major * 32 + 25 }, len:16>>
    _ if len < 4_294_967_296 -> <<{ major * 32 + 26 }, len:32>>
    _ -> <<{ major * 32 + 27 }, len:64>>
  }
}
