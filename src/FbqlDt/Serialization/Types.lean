-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Serialization Type Definitions (Shared)
-- Breaks circular dependency between IR and Serialization

namespace FbqlDt.Serialization.Types

/-!
# Serialization Type Definitions

Shared types used by both IR and Serialization modules to break circular dependency.

**CBOR Types:**
- CBORValue - In-memory representation of CBOR data
- CBORMajorType - CBOR major type discriminator

**Other Formats:**
- JsonValue - In-memory representation of JSON data
- SerializationFormat - Format selection enum
-/

-- ============================================================================
-- JSON Types
-- ============================================================================

/-- JSON value representation -/
inductive JsonValue where
  | object : List (String × JsonValue) → JsonValue
  | array : List JsonValue → JsonValue
  | string : String → JsonValue
  | number : Float → JsonValue
  | bool : Bool → JsonValue
  | null : JsonValue
  deriving Repr

-- ============================================================================
-- CBOR Types (RFC 8949)
-- ============================================================================

/-- CBOR major types (3-bit discriminator) -/
inductive CBORMajorType where
  | unsigned : CBORMajorType      -- 0: Unsigned integer
  | negative : CBORMajorType      -- 1: Negative integer
  | byteString : CBORMajorType    -- 2: Byte string
  | textString : CBORMajorType    -- 3: Text string
  | array : CBORMajorType         -- 4: Array
  | map : CBORMajorType           -- 5: Map
  | tag : CBORMajorType           -- 6: Tagged value
  | simple : CBORMajorType        -- 7: Simple/float
  deriving Repr, BEq

/-- CBOR value representation -/
inductive CBORValue where
  | unsigned : Nat → CBORValue
  | negative : Int → CBORValue
  | byteString : ByteArray → CBORValue
  | textString : String → CBORValue
  | array : List CBORValue → CBORValue
  | map : List (CBORValue × CBORValue) → CBORValue
  | tag : Nat → CBORValue → CBORValue  -- Semantic tag + tagged value
  | simple : Nat → CBORValue
  | float : Float → CBORValue

-- Manual Repr instance (ByteArray doesn't have automatic Repr)
-- Recursive for nested structures
partial def reprCBOR : CBORValue → Nat → Std.Format
  | .unsigned n, _ => Std.Format.text ("CBORValue.unsigned " ++ toString n)
  | .negative i, _ => Std.Format.text ("CBORValue.negative " ++ toString i)
  | .byteString bs, _ => Std.Format.text ("CBORValue.byteString #[" ++ toString bs.size ++ " bytes]")
  | .textString s, _ => Std.Format.text ("CBORValue.textString " ++ toString s)
  | .array items, _ => Std.Format.text ("CBORValue.array [" ++ String.intercalate ", " (items.map fun item => toString (reprCBOR item 0)) ++ "]")
  | .map pairs, _ => Std.Format.text ("CBORValue.map [" ++ String.intercalate ", " (pairs.map fun (k, v) => "(" ++ toString (reprCBOR k 0) ++ ", " ++ toString (reprCBOR v 0) ++ ")") ++ "]")
  | .tag t v, _ => Std.Format.text ("CBORValue.tag " ++ toString t ++ " (" ++ toString (reprCBOR v 0) ++ ")")
  | .simple n, _ => Std.Format.text ("CBORValue.simple " ++ toString n)
  | .float f, _ => Std.Format.text ("CBORValue.float " ++ toString f)

instance : Repr CBORValue where
  reprPrec v _ := reprCBOR v 0

-- BEq instance for CBORValue
partial def cborValueBeq : CBORValue → CBORValue → Bool
  | .unsigned n1, .unsigned n2 => n1 == n2
  | .negative i1, .negative i2 => i1 == i2
  | .byteString bs1, .byteString bs2 => bs1.data == bs2.data  -- Compare underlying arrays
  | .textString s1, .textString s2 => s1 == s2
  | .array items1, .array items2 =>
      items1.length == items2.length &&
      (items1.zip items2).all (fun (a, b) => cborValueBeq a b)
  | .map pairs1, .map pairs2 =>
      pairs1.length == pairs2.length &&
      (pairs1.zip pairs2).all (fun ((k1, v1), (k2, v2)) =>
        cborValueBeq k1 k2 && cborValueBeq v1 v2)
  | .tag t1 v1, .tag t2 v2 => t1 == t2 && cborValueBeq v1 v2
  | .simple n1, .simple n2 => n1 == n2
  | .float f1, .float f2 => f1 == f2
  | _, _ => false

instance : BEq CBORValue where
  beq := cborValueBeq

-- ============================================================================
-- CBOR Semantic Tags for GQL-DT
-- ============================================================================

/-- CBOR Tag 55800: BoundedNat

    Vendor-specific range (55799-55899) to avoid IANA tag collisions.

    Structure: map {
      "min": unsigned,
      "max": unsigned,
      "value": unsigned,
      "proof": map { "verified_at_compile_time": bool, ... }
    }
-/
def cborTagBoundedNat : Nat := 55800

/-- CBOR Tag 55801: NonEmptyString

    Structure: map {
      "value": textString,
      "proof": map { "verified_at_compile_time": bool, ... }
    }
-/
def cborTagNonEmptyString : Nat := 55801

/-- CBOR Tag 55802: Confidence (BoundedNat 0 100)

    Structure: map {
      "value": unsigned,
      "proof": map { "verified_at_compile_time": bool, ... }
    }
-/
def cborTagConfidence : Nat := 55802

/-- CBOR Tag 55803: PromptScores

    Structure: map {
      "provenance": unsigned,
      "replicability": unsigned,
      "objective": unsigned,
      "methodology": unsigned,
      "publication": unsigned,
      "transparency": unsigned,
      "overall": unsigned,
      "proof": map { ... }
    }
-/
def cborTagPromptScores : Nat := 55803

/-- CBOR Tag 55804: ProofBlob

    Structure: map {
      "type": textString,
      "data": textString,
      "verified": bool
    }
-/
def cborTagProofBlob : Nat := 55804

-- ============================================================================
-- Format Selection
-- ============================================================================

/-- Serialization format selection -/
inductive SerializationFormat where
  | json : SerializationFormat      -- Web APIs, debugging
  | cbor : SerializationFormat      -- Proof blobs, IR transport
  | binary : SerializationFormat    -- Lithoglyph native storage
  | sql : SerializationFormat       -- SQL compatibility (WARNING: type info lost)
  deriving Repr, BEq

end FbqlDt.Serialization.Types
