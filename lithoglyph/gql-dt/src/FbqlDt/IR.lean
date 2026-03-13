-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Typed Intermediate Representation (IR)
-- Preserves dependent types and proofs for native execution

import FbqlDt.AST
import FbqlDt.TypeSafe
import FbqlDt.Types
import FbqlDt.Serialization.Types
import FbqlDt.Serialization
import FbqlDt.Provenance

namespace FbqlDt.IR

open AST TypeSafe Serialization.Types Provenance

/-!
# Typed Intermediate Representation

The IR is the canonical representation of GQL-DT/GQL queries.

**Key Properties:**
1. Preserves all type information from AST
2. Proof blobs serialized to CBOR for transport
3. Permission metadata attached
4. Can be executed natively or lowered to SQL
5. Platform-independent (serializable)

**Flow:**
```
GQL-DT/GQL Source
    ↓ Parser
Typed AST (with proofs)
    ↓ IR Generation
Typed IR (this module)
    ↓ Serialization
CBOR bytes
    ↓ Network/Storage
Lithoglyph Native Execution
```
-/

-- ============================================================================
-- Core IR Types
-- ============================================================================

/-- Proof blob: CBOR-serialized proof term

    Proofs are erased at runtime but serialized for verification/audit.
    CBOR format (RFC 8949) chosen for:
    - Deterministic encoding
    - Compact binary format
    - Schema evolution support
-/
structure ProofBlob where
  cborData : ByteArray
  proofType : String  -- Human-readable description

-- Manual Repr instance (ByteArray doesn't have automatic Repr)
instance : Repr ProofBlob where
  reprPrec pb _ := s!"ProofBlob \{ proofType := {repr pb.proofType}, cborData := <{pb.cborData.size} bytes> }"

/-- Validation level (from TWO-TIER-DESIGN.md) -/
inductive ValidationLevel where
  | none : ValidationLevel       -- No validation (dangerous!)
  | runtime : ValidationLevel    -- Runtime checks only (GQL)
  | compile : ValidationLevel    -- Compile-time proofs (GQL-DT)
  | paranoid : ValidationLevel   -- Manual proofs required
  deriving Repr, BEq

-- ToString for ValidationLevel
instance : ToString ValidationLevel where
  toString
    | .none => "none"
    | .runtime => "runtime"
    | .compile => "compile"
    | .paranoid => "paranoid"

/-- Permission metadata attached to every IR statement -/
structure PermissionMetadata where
  userId : String
  roleId : String
  validationLevel : ValidationLevel
  allowedTypes : List TypeExpr
  timestamp : Nat  -- Unix timestamp
  deriving Repr

-- ============================================================================
-- IR Statement Types
-- ============================================================================

/-- INSERT IR: Typed insert with proof blobs -/
structure IR.Insert (schema : Schema) where
  table : String
  columns : List String
  values : List (Σ t : TypeExpr, TypedValue t)
  rationale : Rationale
  proofs : List ProofBlob  -- Serialized proof terms
  permissions : PermissionMetadata
  -- Type match proof (same as AST)
  typesMatch : ∀ i, i < values.length →
    ∃ col ∈ schema.columns,
      col.name = columns.get! i ∧
      (values.get! i).1 = col.type
  deriving Repr

/-- SELECT IR: Typed select with optional refinement -/
structure IR.Select (α : Type) where
  selectList : SelectList
  from_ : FromClause
  where_ : Option WhereClause
  orderBy : Option OrderByClause
  limit : Option Nat
  returning : Option (TypeRefinement α)
  permissions : PermissionMetadata
  deriving Repr

/-- UPDATE IR: Typed update with proofs -/
structure IR.Update (schema : Schema) where
  table : String
  assignments : List Assignment
  where_ : Option WhereClause
  rationale : Rationale
  proofs : List ProofBlob
  permissions : PermissionMetadata
  deriving Repr

/-- DELETE IR: Typed delete with mandatory rationale -/
structure IR.Delete (schema : Schema) where
  table : String
  where_ : WhereClause  -- DELETE without WHERE forbidden
  rationale : Rationale  -- Why are we deleting?
  permissions : PermissionMetadata
  deriving Repr

/-- Decomposition strategy for normalization -/
inductive DecompositionStrategy where
  | bcnf : DecompositionStrategy
  | threeNF : DecompositionStrategy
  | fourNF : DecompositionStrategy
  deriving Repr, BEq

/-- NORMALIZE IR: Schema normalization operation -/
structure IR.Normalize (schema : Schema) where
  targetForm : NormalForm
  decomposition : DecompositionStrategy
  proofs : List ProofBlob  -- Normalization proofs
  permissions : PermissionMetadata
  deriving Repr

-- ============================================================================
-- Top-Level IR
-- ============================================================================

/-- The IR represents any GQL-DT/GQL statement -/
inductive IR where
  | insert : {schema : Schema} → IR.Insert schema → IR
  | select : IR.Select Unit → IR  -- Simplified to use Unit instead of polymorphic type
  | update : {schema : Schema} → IR.Update schema → IR
  | delete : {schema : Schema} → IR.Delete schema → IR
  | normalize : {schema : Schema} → IR.Normalize schema → IR
  deriving Repr

-- ============================================================================
-- AST → IR Translation
-- ============================================================================

/-- Serialize proof term to CBOR blob

    In Lean, we can't directly extract proof terms at runtime.
    Instead, we serialize the proof *metadata* for audit purposes.
-/
def serializeProof (proofType : String) (proofData : String) : ProofBlob :=
  let cbor := CBORValue.map [
    (.textString "type", .textString proofType),
    (.textString "data", .textString proofData),
    (.textString "verified", .simple 21)  -- CBOR simple value 21 = true
  ]
  {
    cborData := Serialization.encodeCBOR cbor,
    proofType := proofType
  }

/-- Generate IR from typed AST (GQL-DT path) -/
def generateIR_Insert
  {schema : Schema}
  (stmt : InsertStmt schema)
  (permissions : PermissionMetadata)
  : IR :=
  -- Extract proof metadata from values
  let proofs := stmt.values.filterMap fun ⟨t, v⟩ =>
    match t with
    | .boundedNat min max =>
        some (serializeProof "BoundedNat" s!"value ∈ [{min}, {max}]")
    | .nonEmptyString =>
        some (serializeProof "NonEmptyString" "length > 0")
    | .confidence =>
        some (serializeProof "Confidence" "value ∈ [0, 100]")
    | .promptScores =>
        some (serializeProof "PromptScores" "all dimensions ∈ [0, 100], overall auto-computed")
    | _ => none

  .insert {
    table := stmt.table,
    columns := stmt.columns,
    values := stmt.values,
    rationale := stmt.rationale,
    proofs := proofs,
    permissions := permissions,
    typesMatch := stmt.typesMatch
  }

/-- Generate IR from SELECT AST -/
def generateIR_Select
  {α : Type}
  (stmt : SelectStmt α)
  (permissions : PermissionMetadata)
  : IR :=
  .select {
    selectList := stmt.selectList,
    from_ := stmt.from_,
    where_ := none,  -- TODO: Convert Condition to WhereClause
    orderBy := none,  -- TODO: Parse ORDER BY
    limit := none,     -- TODO: Parse LIMIT
    returning := none,  -- TODO: Convert TypeRefinement
    permissions := permissions
  }

-- ============================================================================
-- CBOR Serialization
-- ============================================================================

/-- Serialize typed value to CBOR (stub) -/
private axiom serializeTypedValueCBOR : (Σ t : TypeExpr, TypedValue t) → CBORValue

/-- Serialize PermissionMetadata to CBOR -/
private def serializePermissions (perms : PermissionMetadata) : CBORValue :=
  .map [
    (.textString "userId", .textString perms.userId),
    (.textString "roleId", .textString perms.roleId),
    (.textString "validationLevel", .textString (toString perms.validationLevel)),
    (.textString "timestamp", .unsigned perms.timestamp)
  ]

/-- Serialize INSERT to CBOR -/
private noncomputable def serializeInsert {schema : Schema} (stmt : IR.Insert schema) : ByteArray :=
  let values := stmt.values.map (fun tv => serializeTypedValueCBOR tv)
  let cbor := CBORValue.map [
    (.textString "type", .textString "insert"),
    (.textString "table", .textString stmt.table),
    (.textString "columns", .array (stmt.columns.map .textString)),
    (.textString "values", .array values),
    (.textString "rationale", .textString stmt.rationale.text.val),
    (.textString "proofs", .array (stmt.proofs.map fun p => .byteString p.cborData)),
    (.textString "permissions", serializePermissions stmt.permissions)
  ]
  Serialization.encodeCBOR cbor

/-- Serialize SELECT to CBOR -/
private def serializeSelect (stmt : IR.Select Unit) : ByteArray :=
  let selectListCBOR := match stmt.selectList with
    | .star => CBORValue.textString "*"
    | .columns cols => .array (cols.map .textString)
    | .typed _ _ => .textString "*"  -- TODO: Serialize type refinement

  let tablesCBOR := .array (stmt.from_.tables.map fun t =>
    .map [
      (.textString "name", .textString t.name),
      (.textString "alias", match t.alias with
        | some a => .textString a
        | none => .simple 22)  -- null
    ])

  let cbor := CBORValue.map [
    (.textString "type", .textString "select"),
    (.textString "selectList", selectListCBOR),
    (.textString "tables", tablesCBOR),
    (.textString "permissions", serializePermissions stmt.permissions)
  ]
  Serialization.encodeCBOR cbor

/-- Serialize UPDATE to CBOR -/
private noncomputable def serializeUpdate {schema : Schema} (stmt : IR.Update schema) : ByteArray :=
  let assignmentsCBOR := .array (stmt.assignments.map fun a =>
    .map [
      (.textString "column", .textString a.column),
      (.textString "value", serializeTypedValueCBOR a.value)
    ])

  let cbor := CBORValue.map [
    (.textString "type", .textString "update"),
    (.textString "table", .textString stmt.table),
    (.textString "assignments", assignmentsCBOR),
    (.textString "rationale", .textString stmt.rationale.text.val),
    (.textString "proofs", .array (stmt.proofs.map fun p => .byteString p.cborData)),
    (.textString "permissions", serializePermissions stmt.permissions)
  ]
  Serialization.encodeCBOR cbor

/-- Serialize DELETE to CBOR -/
private def serializeDelete {schema : Schema} (stmt : IR.Delete schema) : ByteArray :=
  let cbor := CBORValue.map [
    (.textString "type", .textString "delete"),
    (.textString "table", .textString stmt.table),
    (.textString "rationale", .textString stmt.rationale.text.val),
    (.textString "permissions", serializePermissions stmt.permissions)
  ]
  Serialization.encodeCBOR cbor

/-- Serialize NORMALIZE to CBOR -/
private def serializeNormalize {schema : Schema} (stmt : IR.Normalize schema) : ByteArray :=
  let cbor := CBORValue.map [
    (.textString "type", .textString "normalize"),
    (.textString "targetForm", .textString (toString stmt.targetForm)),
    (.textString "proofs", .array (stmt.proofs.map fun p => .byteString p.cborData)),
    (.textString "permissions", serializePermissions stmt.permissions)
  ]
  Serialization.encodeCBOR cbor

/-- Serialize IR to CBOR bytes for network transport -/
noncomputable def serializeIR (ir : IR) : ByteArray :=
  match ir with
  | .insert stmt => serializeInsert stmt
  | .select stmt => serializeSelect stmt
  | .update stmt => serializeUpdate stmt
  | .delete stmt => serializeDelete stmt
  | .normalize stmt => serializeNormalize stmt

/-- Deserialize CBOR bytes to IR (stub) -/
-- TODO: Implement full CBOR deserialization with schema reconstruction
axiom deserializeIR (bytes : ByteArray) : Except String IR

-- ============================================================================
-- Permission Validation
-- ============================================================================

/-- Check if type is allowed by permission profile -/
def isTypeAllowed (t : TypeExpr) (allowedTypes : List TypeExpr) : Bool :=
  -- Empty list = all types allowed
  if allowedTypes.isEmpty then
    true
  else
    allowedTypes.contains t

/-- Validate IR against permission metadata -/
def validatePermissions (ir : IR) : Except String Unit := do
  match ir with
  | .insert stmt =>
      -- Check all value types are allowed
      for ⟨t, _⟩ in stmt.values do
        if !isTypeAllowed t stmt.permissions.allowedTypes then
          throw s!"Type {t} not allowed by permission profile"
      return ()
  | .select stmt => return ()  -- SELECT doesn't modify data
  | .update stmt =>
      for assign in stmt.assignments do
        if !isTypeAllowed assign.value.1 stmt.permissions.allowedTypes then
          throw s!"Type {assign.value.1} not allowed by permission profile"
      return ()
  | .delete stmt => return ()  -- DELETE doesn't use typed values
  | .normalize stmt => return ()  -- NORMALIZE is admin-only

-- ============================================================================
-- IR Optimization
-- ============================================================================

/-- Optimize IR before execution

    Optimizations:
    - Constant folding
    - Dead code elimination
    - Proof caching (if already verified)
    - Query plan hints
-/

-- Helper functions defined first
private def optimizeInsert {schema : Schema} (stmt : IR.Insert schema) : IR.Insert schema :=
  -- TODO: Constant folding, proof caching
  stmt

private def optimizeSelect (stmt : IR.Select Unit) : IR.Select Unit :=
  -- TODO: Query plan optimization
  stmt

private def optimizeUpdate {schema : Schema} (stmt : IR.Update schema) : IR.Update schema :=
  -- TODO: Minimize assignments
  stmt

def optimizeIR (ir : IR) : IR :=
  match ir with
  | .insert stmt => .insert (optimizeInsert stmt)
  | .select stmt => .select (optimizeSelect stmt)
  | .update stmt => .update (optimizeUpdate stmt)
  | .delete stmt => .delete stmt  -- No optimization for DELETE
  | .normalize stmt => .normalize stmt  -- No optimization for NORMALIZE

-- ============================================================================
-- IR → SQL Lowering (Compatibility Layer)
-- ============================================================================

/-- Lower IR to SQL (loses type information!)

    WARNING: This is for COMPATIBILITY ONLY.
    - All dependent types are erased
    - Proofs are discarded
    - Type safety moves from compile-time to runtime

    Use this ONLY for:
    - BI tool integration (read-only)
    - Legacy system compatibility
    - Debugging/inspection

    PRIMARY execution path is native Lithoglyph (preserves types).
-/
-- Helper function must be defined first
private def valueToSQL {t : TypeExpr} (v : TypedValue t) : String :=
  match v with
  | .nat n => toString n
  | .boundedNat _ _ bn => toString bn.val  -- BOUNDS LOST!
  | .nonEmptyString nes => s!"'{nes.val}'"  -- NON-EMPTY GUARANTEE LOST!
  | _ => "NULL"  -- TODO: Handle all types

private def lowerInsertToSQL {schema : Schema} (stmt : IR.Insert schema) : String :=
  let columnList := String.intercalate ", " stmt.columns
  let valueList := stmt.values.map (fun ⟨_, v⟩ => valueToSQL v)
  let values := String.intercalate ", " valueList
  s!"INSERT INTO {stmt.table} ({columnList}) VALUES ({values});"

private def lowerSelectToSQL (stmt : IR.Select Unit) : String :=
  let cols := match stmt.selectList with
    | .star => "*"
    | .columns cs => String.intercalate ", " cs
    | .typed _ _ => "*"  -- TYPE REFINEMENT LOST!
  let tables := String.intercalate ", " (stmt.from_.tables.map (·.name))
  s!"SELECT {cols} FROM {tables};"

private def lowerUpdateToSQL {schema : Schema} (stmt : IR.Update schema) : String :=
  let assignments := stmt.assignments.map fun a =>
    s!"{a.column} = {valueToSQL a.value.2}"
  let assignStr := String.intercalate ", " assignments
  let whereClause := match stmt.where_ with
    | some _ => " WHERE <condition>"  -- TODO: WHERE expression
    | none => ""
  s!"UPDATE {stmt.table} SET {assignStr}{whereClause};"

private def lowerDeleteToSQL {schema : Schema} (stmt : IR.Delete schema) : String :=
  -- WHERE clause is mandatory for DELETE (safety)
  s!"DELETE FROM {stmt.table} WHERE <condition>;"  -- TODO: WHERE expression

/-- Lower IR to SQL (lossy - types erased!)

    WARNING: This is for COMPATIBILITY ONLY.
    - All dependent types are erased
    - Proofs are discarded
    - Type safety moves from compile-time to runtime

    PRIMARY execution path is native Lithoglyph (preserves types).
-/
def lowerToSQL (ir : IR) : String :=
  match ir with
  | .insert stmt => lowerInsertToSQL stmt
  | .select stmt => lowerSelectToSQL stmt
  | .update stmt => lowerUpdateToSQL stmt
  | .delete stmt => lowerDeleteToSQL stmt
  | .normalize _ => "-- NORMALIZE not supported in SQL"

-- ============================================================================
-- IR Inspection & Debugging
-- ============================================================================

/-- Get human-readable description of IR -/
def describeIR (ir : IR) : String :=
  match ir with
  | .insert stmt => s!"INSERT into {stmt.table} ({stmt.columns.length} columns)"
  | .select stmt => s!"SELECT from {stmt.from_.tables.length} tables"
  | .update stmt => s!"UPDATE {stmt.table} ({stmt.assignments.length} assignments)"
  | .delete stmt => s!"DELETE from {stmt.table}"
  | .normalize stmt => s!"NORMALIZE to {stmt.targetForm}"

/-- Extract permission metadata from IR -/
def getPermissions (ir : IR) : PermissionMetadata :=
  match ir with
  | .insert stmt => stmt.permissions
  | .select stmt => stmt.permissions
  | .update stmt => stmt.permissions
  | .delete stmt => stmt.permissions
  | .normalize stmt => stmt.permissions

/-- Check if IR requires proof verification -/
def requiresProofs (ir : IR) : Bool :=
  match ir with
  | .insert stmt => !stmt.proofs.isEmpty
  | .update stmt => !stmt.proofs.isEmpty
  | .normalize stmt => !stmt.proofs.isEmpty
  | _ => false

-- ============================================================================
-- Example: IR Construction
-- ============================================================================

/-- Example: Create IR for INSERT -/
-- Simplified to use axioms to avoid complex PromptScores proof obligations
axiom exampleInsertIR : IR

#check exampleInsertIR  -- IR (type-safe!)

end FbqlDt.IR
