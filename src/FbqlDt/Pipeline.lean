-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Complete Parsing Pipeline: Source → IR
-- Orchestrates lexer, parser, type checker, IR generation

import FbqlDt.Lexer
import FbqlDt.Parser
import FbqlDt.TypeChecker
import FbqlDt.TypeInference
import FbqlDt.IR
import FbqlDt.Serialization

namespace FbqlDt.Pipeline

-- Mark entire namespace as noncomputable due to axiomatized parser functions
noncomputable section

open Lexer Parser TypeChecker TypeInference IR Serialization AST

/-!
# GQL-DT/GQL Complete Parsing Pipeline

Provides end-to-end processing from source text to executable IR.

**Pipeline Stages:**

```
Source Text (GQL or GQL-DT)
    ↓ 1. Lexer
Tokens
    ↓ 2. Parser
Typed AST (with or without explicit types)
    ↓ 3. Type Checker
Validated AST (proofs verified)
    ↓ 4. IR Generation
Typed IR (with proof blobs, permissions)
    ↓ 5. Serialization (optional)
CBOR bytes / JSON
    ↓ 6. Execution
Lithoglyph Native or SQL Backend
```

**Two Modes:**
- **GQL-DT**: Explicit types + proofs → Compile-time verification
- **GQL**: Type inference + auto-proofs → Runtime validation fallback
-/

-- ============================================================================
-- Pipeline Configuration
-- ============================================================================

/-- Parsing mode -/
inductive ParsingMode where
  | gqld : ParsingMode   -- Explicit types, compile-time proofs
  | gql : ParsingMode    -- Type inference, runtime validation
  deriving Repr, BEq

/-- Pipeline configuration -/
structure PipelineConfig where
  mode : ParsingMode
  schema : Schema
  permissions : PermissionMetadata
  validationLevel : ValidationLevel
  serializationFormat : SerializationFormat
  deriving Repr

/-- Default configuration for GQL (user tier) -/
def defaultGQLConfig (userId roleId : String) : PipelineConfig := {
  mode := .gql,
  schema := evidenceSchema,  -- TODO: Schema registry lookup
  permissions := {
    userId := userId,
    roleId := roleId,
    validationLevel := .runtime,
    allowedTypes := [],  -- Empty = all types allowed
    timestamp := 0  -- TODO: Get current timestamp
  },
  validationLevel := .runtime,
  serializationFormat := .cbor
}

/-- Default configuration for GQL-DT (admin tier) -/
def defaultGQLdtConfig (userId roleId : String) : PipelineConfig := {
  mode := .gqld,
  schema := evidenceSchema,
  permissions := {
    userId := userId,
    roleId := roleId,
    validationLevel := .compile,
    allowedTypes := [],  -- Admin: all types allowed
    timestamp := 0
  },
  validationLevel := .compile,
  serializationFormat := .cbor
}

-- ============================================================================
-- Pipeline Stages
-- ============================================================================

/-- Stage 1: Tokenize source -/
def tokenizeSource (source : String) : Except String (List Token) :=
  tokenize source

/-- Stage 2: Parse tokens to AST -/
noncomputable def parseTokens (tokens : List Token) (config : PipelineConfig) : Except String (List Statement) := do
  let initialState : ParserState := {
    tokens := tokens,
    position := 0
  }

  match parseStatement initialState with
  | .ok stmt _ => .ok [stmt]
  | .error msg _ => .error msg

/-- Stage 3: Type check AST -/
def typeCheckAST (stmt : Statement) (config : PipelineConfig) : Except String Statement :=
  -- For GQL, type inference already happened in parser
  -- For GQL-DT, verify explicit types and proofs
  match config.mode with
  | .gql => .ok stmt  -- Type inference done, runtime validation will catch errors
  | .gqld =>
      -- TODO: Verify proofs
      .ok stmt

/-- Stage 4: Generate IR from AST -/
def generateIRFromAST (stmt : Statement) (config : PipelineConfig) : Except String IR := do
  match stmt with
  | .insertGQL inferred =>
      -- TODO: Convert InferredInsert to IR.Insert (needs schema lookup)
      .error "InferredInsert → IR conversion not yet implemented"
  | .insertGQLdt inferred =>
      -- TODO: Convert InferredInsert to IR.Insert (needs schema lookup)
      .error "InferredInsert → IR conversion not yet implemented"
  | .select selectStmt =>
      .ok (generateIR_Select selectStmt config.permissions)
  | .update updateStmt =>
      -- TODO: Generate IR.Update (needs schema lookup)
      .error "UPDATE → IR conversion not yet implemented"
  | .delete deleteStmt =>
      -- TODO: Generate IR.Delete (needs schema lookup)
      .error "DELETE → IR conversion not yet implemented"

/-- Stage 5: Validate permissions -/
def validateIRPermissions (ir : IR) (config : PipelineConfig) : Except String Unit :=
  validatePermissions ir

/-- Stage 6: Serialize IR -/
noncomputable def serializeIRToBytes (ir : IR) (config : PipelineConfig) : ByteArray :=
  serializeIR ir  -- TODO: Use config.serializationFormat

-- ============================================================================
-- Complete Pipeline
-- ============================================================================

/-- Run complete pipeline: Source → IR -/
noncomputable def runPipeline (source : String) (config : PipelineConfig) : Except String IR := do
  -- Stage 1: Tokenize
  let tokens ← tokenizeSource source

  -- Stage 2: Parse
  let stmts ← parseTokens tokens config

  -- Get first statement (TODO: Handle multiple statements)
  let stmt ← match stmts.head? with
    | some s => .ok s
    | none => .error "No statements parsed"

  -- Stage 3: Type check
  let checkedStmt ← typeCheckAST stmt config

  -- Stage 4: Generate IR
  let ir ← generateIRFromAST checkedStmt config

  -- Stage 5: Validate permissions
  validateIRPermissions ir config

  -- Return validated IR
  .ok ir

/-- Run pipeline and serialize to bytes -/
noncomputable def runPipelineAndSerialize (source : String) (config : PipelineConfig) : Except String ByteArray := do
  let ir ← runPipeline source config
  .ok (serializeIRToBytes ir config)

-- ============================================================================
-- Convenience Functions
-- ============================================================================

/-- Parse GQL query (user tier) -/
noncomputable def parseGQL (source : String) (userId roleId : String) : Except String IR :=
  runPipeline source (defaultGQLConfig userId roleId)

/-- Parse GQL-DT query (admin tier) -/
noncomputable def parseGQLdt (source : String) (userId roleId : String) : Except String IR :=
  runPipeline source (defaultGQLdtConfig userId roleId)

/-- Parse and execute query -/
def parseAndExecute (source : String) (config : PipelineConfig) : IO (Except String Unit) := do
  match runPipeline source config with
  | .ok ir =>
      -- TODO: Execute IR on Lithoglyph
      IO.println s!"✓ Parsed successfully: {describeIR ir}"
      .ok (.ok ())
  | .error msg =>
      IO.println s!"✗ Parse error: {msg}"
      .ok (.error msg)

-- ============================================================================
-- Error Reporting
-- ============================================================================

/-- Pipeline error with context -/
structure PipelineError where
  stage : String  -- Which stage failed
  message : String
  source : String  -- Original source (for error highlighting)
  line : Nat
  column : Nat
  deriving Repr

/-- Format error for display -/
def formatError (err : PipelineError) : String :=
  s!"{err.stage} error at line {err.line}, column {err.column}:\n{err.message}\n\nSource:\n{err.source}"

-- ============================================================================
-- Examples
-- ============================================================================

/-- Example: Parse GQL INSERT -/
def exampleParseGQL : Except String IR :=
  parseGQL
    "INSERT INTO evidence (title, score) VALUES ('ONS Data', 95) RATIONALE 'Official statistics';"
    "user123" "journalist"

-- #eval! exampleParseGQL

/-- Example: Parse GQL-DT INSERT -/
def exampleParseGQLdt : Except String IR :=
  parseGQLdt
    "INSERT INTO evidence (title : NonEmptyString, score : BoundedNat 0 100) VALUES ('ONS Data', 95) RATIONALE 'Official statistics';"
    "admin456" "admin"

-- #eval! exampleParseGQLdt

/-- Example: Parse SELECT -/
def exampleParseSelect : Except String IR :=
  parseGQL
    "SELECT * FROM evidence;"
    "user123" "journalist"

-- #eval! exampleParseSelect

/-- Example: Complete pipeline with serialization -/
noncomputable def examplePipelineWithSerialization : IO Unit := do
  let config := defaultGQLConfig "user123" "journalist"

  match runPipelineAndSerialize
    "INSERT INTO evidence (title, score) VALUES ('ONS Data', 95) RATIONALE 'Official statistics';"
    config with
  | .ok bytes =>
      IO.println s!"✓ Parsed and serialized: {bytes.size} bytes (CBOR)"
  | .error msg =>
      IO.println s!"✗ Error: {msg}"

-- ============================================================================
-- Testing & Validation
-- ============================================================================

/-- Test: Valid GQL query should parse -/
def testValidGQL : IO Bool := do
  match parseGQL "INSERT INTO evidence (title) VALUES ('Test') RATIONALE 'Test';" "test" "user" with
  | .ok _ =>
      IO.println "✓ Valid GQL query parsed"
      return true
  | .error msg =>
      IO.println s!"✗ Valid GQL query failed: {msg}"
      return false

/-- Test: Invalid query should error -/
def testInvalidQuery : IO Bool := do
  match parseGQL "INVALID SYNTAX HERE" "test" "user" with
  | .ok _ =>
      IO.println "✗ Invalid query should not parse"
      return false
  | .error _ =>
      IO.println "✓ Invalid query correctly rejected"
      return true

/-- Run all tests -/
def runTests : IO Unit := do
  IO.println "=== GQL-DT Pipeline Tests ==="
  let _ ← testValidGQL
  let _ ← testInvalidQuery
  IO.println "=== Tests Complete ==="

end -- noncomputable section

end FbqlDt.Pipeline
