-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Parser for GQL-DT/GQL
-- Parses tokens into typed AST

import FbqlDt.Lexer
import FbqlDt.AST
import FbqlDt.TypeInference
import FbqlDt.IR
import FbqlDt.Types
import FbqlDt.Types.NonEmptyString
import FbqlDt.Types.BoundedNat
import FbqlDt.Types.Confidence
import FbqlDt.Provenance

namespace FbqlDt.Parser

open Lexer AST TypeInference IR Types

/-!
# GQL-DT/GQL Parser

Parses tokenized source into typed AST.

**Two parsing modes:**
1. **GQL-DT** - Explicit types, proofs required
2. **GQL** - Type inference, runtime validation

**Architecture:**
```
Tokens (from Lexer)
    ↓
Parser Combinators
    ↓
Typed AST (with or without explicit types)
    ↓
Type Checker (verify proofs)
    ↓
Typed IR (ready for execution)
```
-/

-- Universe declaration for polymorphic Parser
universe u

-- ============================================================================
-- Parser State
-- ============================================================================

/-- Parser state: current position in token stream -/
structure ParserState where
  tokens : List Token
  position : Nat
  deriving Repr

/-- Parser result (universe-polymorphic) -/
inductive ParseResult (α : Type u) where
  | ok : α → ParserState → ParseResult α
  | error : String → ParserState → ParseResult α

-- Manual Repr instance (deriving doesn't work with universe polymorphism)
instance {α : Type u} : Repr (ParseResult α) where
  reprPrec
    | .ok _ _, _ => "ParseResult.ok ..."
    | .error msg _, _ => s!"ParseResult.error \"{msg}\""

/-- Parser monad (supports Type 1 for dependent types) -/
def Parser (α : Type u) := ParserState → ParseResult α

instance : Monad Parser where
  pure x := fun s => .ok x s
  bind p f := fun s =>
    match p s with
    | .ok x s' => f x s'
    | .error msg s' => .error msg s'

/-- Fail with error message -/
def fail {α : Type u} (msg : String) : Parser α :=
  fun s => .error msg s

-- ============================================================================
-- Basic Parser Combinators
-- ============================================================================

/-- Get current token without consuming -/
def peek : Parser (Option Token) := fun s =>
  match s.tokens.get? s.position with
  | some tok => .ok (some tok) s
  | none => .ok none s

/-- Consume current token -/
def advance : Parser Unit := fun s =>
  .ok () { s with position := s.position + 1 }

/-- Get current token and consume -/
def next : Parser (Option Token) := fun s =>
  match s.tokens.get? s.position with
  | some tok => .ok (some tok) { s with position := s.position + 1 }
  | none => .ok none s

/-- Expect specific token type -/
def expect (tokType : TokenType) : Parser Token := fun s =>
  match s.tokens.get? s.position with
  | some tok =>
      if tok.type == tokType then
        .ok tok { s with position := s.position + 1 }
      else
        .error s!"Expected {tokType}, got {tok.type}" s
  | none =>
      .error s!"Expected {tokType}, got EOF" s

/-- Expect identifier and return its name -/
def expectIdentifier : Parser String := fun s =>
  match s.tokens.get? s.position with
  | some tok =>
      match tok.type with
      | .identifier name => .ok name { s with position := s.position + 1 }
      | _ => .error s!"Expected identifier, got {tok.type}" s
  | none => .error "Expected identifier, got EOF" s

/-- Parse optional element -/
def optional {α : Type} (p : Parser α) : Parser (Option α) := fun s =>
  match p s with
  | .ok x s' => .ok (some x) s'
  | .error _ _ => .ok none s

/-- Parse zero or more elements -/
-- TODO: Fix infinite loop in type checker
axiom many {α : Type} (p : Parser α) : Parser (List α)
-- partial def many {α : Type} (p : Parser α) : Parser (List α) := fun s =>
--   match p s with
--   | .ok x s' =>
--       match many p s' with
--       | .ok xs s'' => .ok (x :: xs) s''
--       | .error _ _ => .ok [x] s'  -- Should not happen
--   | .error _ _ => .ok [] s

/-- Parse one or more elements -/
-- TODO: Fix after many is fixed
axiom many1 {α : Type} (p : Parser α) : Parser (List α)
-- def many1 {α : Type} (p : Parser α) : Parser (List α) := do
--   let x ← p
--   let xs ← many p
--   return x :: xs

/-- Parse elements separated by delimiter -/
-- TODO: Fix infinite loop in type checker
axiom sepBy {α β : Type} (p : Parser α) (sep : Parser β) : Parser (List α)
-- partial def sepBy {α β : Type} (p : Parser α) (sep : Parser β) : Parser (List α) := fun s =>
--   match p s with
--   | .ok x s' =>
--       match sep s' with
--       | .ok _ s'' =>
--           match sepBy p sep s'' with
--           | .ok xs s''' => .ok (x :: xs) s'''
--           | .error _ _ => .ok [x] s'
--       | .error _ _ => .ok [x] s'
--   | .error _ _ => .ok [] s

-- ============================================================================
-- Expression Parsing
-- ============================================================================

/-- Parse literal value -/
def parseLiteral : Parser InferredType := fun s =>
  match s.tokens.get? s.position with
  | some tok =>
      match tok.type with
      | .litNat n => .ok (.nat n) { s with position := s.position + 1 }
      | .litInt i => .ok (.int i) { s with position := s.position + 1 }
      | .litString str => .ok (.string str) { s with position := s.position + 1 }
      | .litBool b => .ok (.bool b) { s with position := s.position + 1 }
      | .litFloat f => .ok (.float f) { s with position := s.position + 1 }
      | _ => .error s!"Expected literal, got {tok.type}" s
  | none => .error "Expected literal, got EOF" s

-- ============================================================================
-- Type Expression Parsing
-- ============================================================================

/-- Parse type expression -/
def parseTypeExpr : Parser TypeExpr := fun s =>
  match s.tokens.get? s.position with
  | some tok =>
      match tok.type with
      | .kwNat => .ok .nat { s with position := s.position + 1 }
      | .kwInt => .ok .int { s with position := s.position + 1 }
      | .kwString => .ok .string { s with position := s.position + 1 }
      | .kwBool => .ok .bool { s with position := s.position + 1 }
      | .kwNonEmptyString => .ok .nonEmptyString { s with position := s.position + 1 }
      | .kwConfidence => .ok .confidence { s with position := s.position + 1 }

      | .kwBoundedNat =>
          -- BoundedNat min max
          let s1 := { s with position := s.position + 1 }
          match s1.tokens.get? s1.position with
          | some minTok =>
              match minTok.type with
              | .litNat min =>
                  let s2 := { s1 with position := s1.position + 1 }
                  match s2.tokens.get? s2.position with
                  | some maxTok =>
                      match maxTok.type with
                      | .litNat max =>
                          .ok (.boundedNat min max) { s2 with position := s2.position + 1 }
                      | _ => .error "Expected max value for BoundedNat" s2
                  | none => .error "Expected max value for BoundedNat" s2
              | _ => .error "Expected min value for BoundedNat" s1
          | none => .error "Expected min value for BoundedNat" s1

      | .kwPromptScores => .ok .promptScores { s with position := s.position + 1 }

      | _ => .error s!"Expected type expression, got {tok.type}" s
  | none => .error "Expected type expression, got EOF" s

-- ============================================================================
-- INSERT Parsing
-- ============================================================================

/-- Parse column list: (col1, col2, col3) -/
noncomputable def parseColumnList : Parser (List String) := do
  let _ ← expect .leftParen
  let cols ← sepBy expectIdentifier (do let _ ← expect .comma; return ())
  let _ ← expect .rightParen
  return cols

/-- Parse column with optional type annotation: name or name : Type -/
def parseColumnWithType : Parser (String × Option TypeExpr) := do
  let name ← expectIdentifier
  let typeAnnot ← optional (do
    let _ ← expect .opDoubleColon
    parseTypeExpr)
  return (name, typeAnnot)

/-- Parse typed column list: (col1 : Type1, col2 : Type2) -/
noncomputable def parseTypedColumnList : Parser (List (String × TypeExpr)) := do
  let _ ← expect .leftParen
  let cols ← sepBy (do
    let name ← expectIdentifier
    let _ ← expect .opDoubleColon
    let ty ← parseTypeExpr
    return (name, ty)) (do let _ ← expect .comma; return ())
  let _ ← expect .rightParen
  return cols

/-- Parse VALUES clause -/
noncomputable def parseValues : Parser (List InferredType) := do
  let _ ← expect .kwValues
  let _ ← expect .leftParen
  let vals ← sepBy parseLiteral (do let _ ← expect .comma; return ())
  let _ ← expect .rightParen
  return vals

/-- Parse RATIONALE clause -/
def parseRationale : Parser String := fun s =>
  match expect .kwRationale s with
  | .ok _ s' =>
      match s'.tokens.get? s'.position with
      | some tok =>
          match tok.type with
          | .litString str => .ok str { s' with position := s'.position + 1 }
          | _ => .error "Expected string for RATIONALE" s'
      | none => .error "Expected RATIONALE value" s'
  | .error msg s' => .error msg s'

/-- Dummy schema for type inference -/
axiom evidenceSchema : Schema

/-- Parse INSERT statement (GQL - no types) -/
noncomputable def parseInsertGQL : Parser InferredInsert := do
  let _ ← expect .kwInsert
  let _ ← expect .kwInto
  let table ← expectIdentifier
  let columns ← parseColumnList
  let values ← parseValues
  let rationale ← parseRationale
  let _ ← optional (expect .semicolon)

  -- Type inference happens here
  match inferInsert evidenceSchema table columns values rationale with
  | .ok inferred => return inferred
  | .error msg => fail msg

/-- Parse INSERT statement (GQL-DT - explicit types) -/
noncomputable def parseInsertGQLdt : Parser InferredInsert := do
  let _ ← expect .kwInsert
  let _ ← expect .kwInto
  let table ← expectIdentifier
  let typedColumns ← parseTypedColumnList
  let values ← parseValues
  let rationale ← parseRationale
  let _ ← optional (expect .semicolon)

  -- Extract columns and types
  let columns := typedColumns.map (·.1)
  let expectedTypes := typedColumns.map (·.2)

  -- Type check values against expected types
  -- TODO: Verify values match expected types
  match inferInsert evidenceSchema table columns values rationale with
  | .ok inferred => return inferred
  | .error msg => fail msg

-- ============================================================================
-- Statement Types (must be defined before parsing functions)
-- ============================================================================

/-- Parser-level UPDATE statement (simpler than AST.UpdateStmt) -/
structure ParsedUpdate where
  table : String
  assignments : List Assignment
  where_ : Option WhereClause
  rationale : Provenance.Rationale
  deriving Repr

/-- Parser-level DELETE statement (simpler than AST.DeleteStmt) -/
structure ParsedDelete where
  table : String
  where_ : WhereClause
  rationale : Provenance.Rationale
  deriving Repr

/-- Parser-level SELECT statement (simpler than AST.SelectStmt) -/
structure ParsedSelect where
  selectList : SelectList
  from_ : FromClause
  where_ : Option WhereClause
  orderBy : Option OrderByClause
  limit : Option Nat
  deriving Repr

/-- Statement type for parsing -/
inductive Statement where
  | insertGQL : InferredInsert → Statement
  | insertGQLdt : InferredInsert → Statement
  | select : ParsedSelect → Statement
  | update : ParsedUpdate → Statement
  | delete : ParsedDelete → Statement
  deriving Repr

-- ============================================================================
-- SELECT Parsing
-- ============================================================================

/-- Parse SELECT list (axiomatized due to Type universe issues) -/
axiom parseSelectList : Parser SelectList

/-- Parse FROM clause -/
noncomputable def parseFromClause : Parser FromClause := do
  let _ ← expect .kwFrom
  let tables ← sepBy (do
    let name ← expectIdentifier
    let alias ← optional (do
      let _ ← expect .kwAs
      expectIdentifier)
    return { name := name, alias := alias }) (do let _ ← expect .comma; return ())
  return { tables := tables }

/-- Parse comparison operator -/
def parseComparisonOp : Parser String := fun s =>
  match s.tokens.get? s.position with
  | some tok =>
      match tok.type with
      | .opEq => .ok "=" { s with position := s.position + 1 }
      | .opLt => .ok "<" { s with position := s.position + 1 }
      | .opGt => .ok ">" { s with position := s.position + 1 }
      | .opLe => .ok "<=" { s with position := s.position + 1 }
      | .opGe => .ok ">=" { s with position := s.position + 1 }
      | .opNeq => .ok "!=" { s with position := s.position + 1 }
      | _ => .error "Expected comparison operator" s
  | none => .error "Expected comparison operator, got EOF" s

/-- Parse WHERE clause -/
def parseWhereClause : Parser WhereClause := do
  let _ ← expect .kwWhere
  -- Parse simple predicate (column op value)
  let column ← expectIdentifier
  let op ← parseComparisonOp
  let value ← parseLiteral
  return {
    predicate := (column, op, value),  -- Simplified for now
    proof := fun _ => trivial
  }

/-- Parse ORDER BY clause -/
noncomputable def parseOrderBy : Parser OrderByClause := do
  let _ ← expect .kwOrder
  let _ ← expect .kwBy
  let columns ← sepBy (do
    let col ← expectIdentifier
    let direction ← optional (do
      let tokOpt ← peek
      match tokOpt with
      | some tok =>
          match tok.type with
          | _ => return "ASC"  -- TODO: Parse ASC/DESC keywords
      | none => return "ASC"
    )
    return (col, direction.getD "ASC")
  ) (do let _ ← expect .comma; return ())
  return { columns := columns }

/-- Parse LIMIT clause -/
def parseLimit : Parser Nat := fun s =>
  match expect .kwLimit s with
  | .ok _ s' =>
      match s'.tokens.get? s'.position with
      | some tok =>
          match tok.type with
          | .litNat n => .ok n { s' with position := s'.position + 1 }
          | _ => .error "Expected number for LIMIT" s'
      | none => .error "Expected LIMIT value" s'
  | .error msg s' => .error msg s'

/-- Parse SELECT statement (axiomatized due to Type universe issues) -/
axiom parseSelect : Parser ParsedSelect

-- ============================================================================
-- Helper Functions
-- ============================================================================

/-- Helper: Infer TypeExpr from InferredType -/
private def inferTypeFromLiteral (lit : InferredType) : TypeExpr :=
  match lit with
  | .nat _ => .nat
  | .int _ => .int
  | .string _ => .string
  | .bool _ => .bool
  | .float _ => .float

/-- Helper: Create TypedValue from InferredType -/
private def typedValueFromLiteral (lit : InferredType) : TypedValue (inferTypeFromLiteral lit) :=
  match lit with
  | .nat n => .nat n
  | .int i => .int i
  | .string s => .string s
  | .bool b => .bool b
  | .float f => .float f

-- ============================================================================
-- UPDATE Parsing
-- ============================================================================

/-- Parse UPDATE statement -/
noncomputable def parseUpdate : Parser ParsedUpdate := do
  let _ ← expect .kwUpdate
  let table ← expectIdentifier
  let _ ← expect .kwSet
  -- Parse assignments (column = value)
  let assignments ← sepBy (do
    let column ← expectIdentifier
    let _ ← expect .opEq
    let value ← parseLiteral
    return (column, value)
  ) (do let _ ← expect .comma; return ())
  let where_ ← optional parseWhereClause
  let rationale ← parseRationale
  let _ ← optional (expect .semicolon)

  return {
    table := table,
    assignments := assignments.map fun (col, val) => {
      column := col,
      value := ⟨inferTypeFromLiteral val, typedValueFromLiteral val⟩
    },
    where_ := where_,
-- PROOF_TODO: Replace sorry with actual proof
    rationale := { text := { val := rationale, nonempty := sorry } }
  }

-- ============================================================================
-- DELETE Parsing
-- ============================================================================

/-- Parse DELETE statement -/
noncomputable def parseDelete : Parser ParsedDelete := do
  let _ ← expect .kwDelete
  let _ ← expect .kwFrom
  let table ← expectIdentifier
  -- WHERE is MANDATORY for safety
  let where_ ← parseWhereClause
  let rationale ← parseRationale
  let _ ← optional (expect .semicolon)

  return {
    table := table,
    where_ := where_,
-- PROOF_TODO: Replace sorry with actual proof
    rationale := { text := { val := rationale, nonempty := sorry } }
  }

-- ============================================================================
-- Top-Level Statement Parsing
-- ============================================================================

/-- Parse any statement (axiomatized due to Type universe issues) -/
axiom parseStatement : Parser Statement

-- ============================================================================
-- Public API
-- ============================================================================

/-- Parse source string to statements -/
noncomputable unsafe def parse (source : String) : Except String (List Statement) := do
  -- Tokenize
  match tokenize source with
  | .ok tokens =>
      -- Parse
      let initialState : ParserState := {
        tokens := tokens,
        position := 0
      }

      match parseStatement initialState with
      | .ok stmt _ => pure [stmt]
      | .error msg _ => throw msg
  | .error msg => throw msg

/-- Parse and generate IR -/
-- TODO: Fix type inference issues
-- def parseToIR (source : String) (permissions : PermissionMetadata) : Except String IR := do
--   let stmts ← parse source
--
--   match stmts.head? with
--   | some (.insertGQL inferred) =>
--       -- Convert InferredInsert to IR.Insert
--       -- TODO: Complete this conversion (needs schema)
--       .error "InferredInsert → IR conversion not yet implemented"
--
--   | some (.select selectStmt) =>
--       .ok (generateIR_Select selectStmt permissions)
--
--   | some (.update updateStmt) =>
--       -- TODO: Generate IR.Update (needs schema)
--       .error "UPDATE → IR conversion not yet implemented"
--
--   | some (.delete deleteStmt) =>
--       -- TODO: Generate IR.Delete (needs schema)
--       .error "DELETE → IR conversion not yet implemented"
--
--   | _ => .error "No statement parsed"
axiom parseToIR (source : String) (permissions : PermissionMetadata) : Except String IR

-- ============================================================================
-- Examples
-- ============================================================================

-- TODO: Fix type inference for Statement in examples
-- /-- Example: Parse simple INSERT -/
-- def exampleParseInsert : Except String (List Statement) :=
--   parse "INSERT INTO evidence (title, score) VALUES ('ONS Data', 95) RATIONALE 'Official statistics';"
--
-- #eval exampleParseInsert
--
-- /-- Example: Parse SELECT -/
-- def exampleParseSelect : Except String (List Statement) :=
--   parse "SELECT * FROM evidence;"
--
-- #eval exampleParseSelect

end FbqlDt.Parser
