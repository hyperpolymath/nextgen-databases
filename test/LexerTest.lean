-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- LexerTest.lean — Dedicated unit tests for GqlDt.Lexer
--
-- Tests tokenization of GQL-DT source text: keywords, operators,
-- delimiters, literals, identifiers, comments, type annotations,
-- proof keywords, and error/edge cases.
--
-- Run with: lake build lexer_test && lake env lean --run test/LexerTest.lean

import GqlDt.Lexer

open GqlDt.Lexer

-- ============================================================================
-- Test Helpers
-- ============================================================================

/-- Count of test failures, tracked via IO.Ref -/
def runTest (name : String) (passed : Bool) : IO Unit := do
  if passed then
    IO.println s!"  PASS: {name}"
  else
    IO.eprintln s!"  FAIL: {name}"

/-- Extract token types from a tokenization result, excluding EOF -/
def tokenTypes (result : Except String (List Token)) : List TokenType :=
  match result with
  | .ok tokens => tokens.filter (·.type != .eof) |>.map (·.type)
  | .error _ => []

/-- Check that tokenization produces the expected sequence of types -/
def expectTypes (input : String) (expected : List TokenType) : Bool :=
  tokenTypes (tokenize input) == expected

/-- Check that tokenization succeeds -/
def expectOk (input : String) : Bool :=
  match tokenize input with
  | .ok _ => true
  | .error _ => false

/-- Get the first non-EOF token type -/
def firstType (input : String) : Option TokenType :=
  match tokenize input with
  | .ok (t :: _) => if t.type != .eof then some t.type else none
  | _ => none

-- ============================================================================
-- SQL Keywords (case-insensitive)
-- ============================================================================

def testSqlKeywords : IO Unit := do
  IO.println "\n--- SQL Keywords ---"

  runTest "SELECT" (firstType "SELECT" == some .kwSelect)
  runTest "select (lowercase)" (firstType "select" == some .kwSelect)
  runTest "SeLeCt (mixed case)" (firstType "SeLeCt" == some .kwSelect)
  runTest "INSERT" (firstType "INSERT" == some .kwInsert)
  runTest "UPDATE" (firstType "UPDATE" == some .kwUpdate)
  runTest "DELETE" (firstType "DELETE" == some .kwDelete)
  runTest "CREATE" (firstType "CREATE" == some .kwCreate)
  runTest "DROP" (firstType "DROP" == some .kwDrop)
  runTest "FROM" (firstType "FROM" == some .kwFrom)
  runTest "WHERE" (firstType "WHERE" == some .kwWhere)
  runTest "INTO" (firstType "INTO" == some .kwInto)
  runTest "VALUES" (firstType "VALUES" == some .kwValues)
  runTest "SET" (firstType "SET" == some .kwSet)
  runTest "AND" (firstType "AND" == some .kwAnd)
  runTest "OR" (firstType "OR" == some .kwOr)
  runTest "NOT" (firstType "NOT" == some .kwNot)
  runTest "IS" (firstType "IS" == some .kwIs)
  runTest "NULL" (firstType "NULL" == some .kwNull)
  runTest "AS" (firstType "AS" == some .kwAs)
  runTest "ON" (firstType "ON" == some .kwOn)
  runTest "JOIN" (firstType "JOIN" == some .kwJoin)
  runTest "LEFT" (firstType "LEFT" == some .kwLeft)
  runTest "RIGHT" (firstType "RIGHT" == some .kwRight)
  runTest "OUTER" (firstType "OUTER" == some .kwOuter)
  runTest "INNER" (firstType "INNER" == some .kwInner)
  runTest "GROUP" (firstType "GROUP" == some .kwGroup)
  runTest "ORDER" (firstType "ORDER" == some .kwOrder)
  runTest "BY" (firstType "BY" == some .kwBy)
  runTest "HAVING" (firstType "HAVING" == some .kwHaving)
  runTest "LIMIT" (firstType "LIMIT" == some .kwLimit)
  runTest "OFFSET" (firstType "OFFSET" == some .kwOffset)
  runTest "DISTINCT" (firstType "DISTINCT" == some .kwDistinct)
  runTest "ALL" (firstType "ALL" == some .kwAll)
  runTest "EXISTS" (firstType "EXISTS" == some .kwExists)
  runTest "IN" (firstType "IN" == some .kwIn)
  runTest "BETWEEN" (firstType "BETWEEN" == some .kwBetween)
  runTest "LIKE" (firstType "LIKE" == some .kwLike)
  runTest "TABLE" (firstType "TABLE" == some .kwTable)
  runTest "COLLECTION" (firstType "COLLECTION" == some .kwCollection)
  runTest "IF" (firstType "IF" == some .kwIf)
  runTest "WITH" (firstType "WITH" == some .kwWith)

-- ============================================================================
-- Type Keywords (case-sensitive)
-- ============================================================================

def testTypeKeywords : IO Unit := do
  IO.println "\n--- Type Keywords (case-sensitive) ---"

  runTest "Nat" (firstType "Nat" == some .kwNat)
  runTest "Int" (firstType "Int" == some .kwInt)
  runTest "String" (firstType "String" == some .kwString)
  runTest "Bool" (firstType "Bool" == some .kwBool)
  runTest "Float" (firstType "Float" == some .kwFloat)
  runTest "Date" (firstType "Date" == some .kwDate)
  runTest "UUID" (firstType "UUID" == some .kwUUID)
  runTest "BoundedNat" (firstType "BoundedNat" == some .kwBoundedNat)
  runTest "BoundedInt" (firstType "BoundedInt" == some .kwBoundedInt)
  runTest "BoundedFloat" (firstType "BoundedFloat" == some .kwBoundedFloat)
  runTest "NonEmptyString" (firstType "NonEmptyString" == some .kwNonEmptyString)
  runTest "Confidence" (firstType "Confidence" == some .kwConfidence)
  runTest "PromptScores" (firstType "PromptScores" == some .kwPromptScores)
  runTest "Tracked" (firstType "Tracked" == some .kwTracked)
  runTest "Rationale" (firstType "Rationale" == some .kwRationale)

  -- Case sensitivity: lowercase type names should be identifiers, not keywords
  runTest "nat is identifier (case-sensitive)" (
    match firstType "nat" with
    | some (.identifier _) => true
    | _ => false
  )
  runTest "int is identifier (case-sensitive)" (
    match firstType "int" with
    | some (.identifier _) => true
    | _ => false
  )

-- ============================================================================
-- Proof Keywords
-- ============================================================================

def testProofKeywords : IO Unit := do
  IO.println "\n--- Proof Keywords ---"

  runTest "WITH_PROOF" (firstType "WITH_PROOF" == some .kwWithProof)
  runTest "THEOREM" (firstType "THEOREM" == some .kwTheorem)
  runTest "PROOF" (firstType "PROOF" == some .kwProof)
  runTest "QED" (firstType "QED" == some .kwQed)
  runTest "omega" (firstType "omega" == some .kwOmega)
  runTest "decide" (firstType "decide" == some .kwDecide)
  runTest "simp" (firstType "simp" == some .kwSimp)
  runTest "sorry" (firstType "sorry" == some .kwSorry)

-- ============================================================================
-- Lithoglyph Keywords
-- ============================================================================

def testLithoglyphKeywords : IO Unit := do
  IO.println "\n--- Lithoglyph Keywords ---"

  runTest "TARGET_NORMAL_FORM" (firstType "TARGET_NORMAL_FORM" == some .kwTarget)
  runTest "NORMALIZE" (firstType "NORMALIZE" == some .kwNormalize)
  runTest "PERMISSIONS" (firstType "PERMISSIONS" == some .kwPermissions)
  runTest "GRANT" (firstType "GRANT" == some .kwGrant)
  runTest "REVOKE" (firstType "REVOKE" == some .kwRevoke)
  runTest "TO" (firstType "TO" == some .kwTo)
  runTest "VALIDATION" (firstType "VALIDATION" == some .kwValidation)
  runTest "LEVEL" (firstType "LEVEL" == some .kwLevel)
  runTest "runtime" (firstType "runtime" == some .kwRuntime)
  runTest "compile" (firstType "compile" == some .kwCompile)

-- ============================================================================
-- Operators
-- ============================================================================

def testOperators : IO Unit := do
  IO.println "\n--- Operators ---"

  runTest "+" (firstType "+" == some .opPlus)
  runTest "-" (firstType "-" == some .opMinus)
  runTest "*" (firstType "*" == some .opStar)
  runTest "/" (firstType "/" == some .opSlash)
  runTest "%" (firstType "%" == some .opPercent)
  runTest "^" (firstType "^" == some .opCaret)
  runTest "=" (firstType "=" == some .opEq)
  runTest "." (firstType "." == some .opDot)
  runTest "!" (firstType "!" == some .opNot)

  -- Multi-character operators
  runTest "<" (firstType "<" == some .opLt)
  runTest "<=" (expectTypes "<=" [.opLe])
  runTest "<> (as neq)" (expectTypes "<>" [.opNeq])
  runTest ">" (firstType ">" == some .opGt)
  runTest ">=" (expectTypes ">=" [.opGe])
  runTest "!=" (expectTypes "!=" [.opNeq])
  runTest ":" (firstType ":" == some .opColon)
  runTest "::" (expectTypes "::" [.opDoubleColon])

-- ============================================================================
-- Delimiters
-- ============================================================================

def testDelimiters : IO Unit := do
  IO.println "\n--- Delimiters ---"

  runTest "(" (firstType "(" == some .leftParen)
  runTest ")" (firstType ")" == some .rightParen)
  runTest "{" (firstType "{" == some .leftBrace)
  runTest "}" (firstType "}" == some .rightBrace)
  runTest "[" (firstType "[" == some .leftBracket)
  runTest "]" (firstType "]" == some .rightBracket)
  runTest ";" (firstType ";" == some .semicolon)
  runTest "," (firstType "," == some .comma)

  -- Sequence of delimiters
  runTest "(){}" (expectTypes "(){}" [.leftParen, .rightParen, .leftBrace, .rightBrace])
  runTest "[];" (expectTypes "[];" [.leftBracket, .rightBracket, .semicolon])

-- ============================================================================
-- Number Literals
-- ============================================================================

def testNumberLiterals : IO Unit := do
  IO.println "\n--- Number Literals ---"

  runTest "0" (firstType "0" == some (.litNat 0))
  runTest "1" (firstType "1" == some (.litNat 1))
  runTest "42" (firstType "42" == some (.litNat 42))
  runTest "123456" (firstType "123456" == some (.litNat 123456))
  runTest "999" (firstType "999" == some (.litNat 999))

  -- Number followed by operator
  runTest "42+" (expectTypes "42+" [.litNat 42, .opPlus])
  runTest "10,20" (expectTypes "10,20" [.litNat 10, .comma, .litNat 20])

-- ============================================================================
-- String Literals
-- ============================================================================

def testStringLiterals : IO Unit := do
  IO.println "\n--- String Literals ---"

  -- Single-quoted strings
  runTest "'hello'" (
    match firstType "'hello'" with
    | some (.litString "hello") => true
    | _ => false
  )

  -- Double-quoted strings
  runTest "\"world\"" (
    match firstType "\"world\"" with
    | some (.litString "world") => true
    | _ => false
  )

  -- Empty string
  runTest "''" (
    match firstType "''" with
    | some (.litString "") => true
    | _ => false
  )

  -- Escape sequences
  runTest "'line\\nbreak'" (
    match firstType "'line\\nbreak'" with
    | some (.litString s) => s.containsSubstr "\n"
    | _ => false
  )

  runTest "'tab\\there'" (
    match firstType "'tab\\there'" with
    | some (.litString s) => s.containsSubstr "\t"
    | _ => false
  )

  runTest "'escaped\\\\backslash'" (
    match firstType "'escaped\\\\backslash'" with
    | some (.litString s) => s.containsSubstr "\\"
    | _ => false
  )

-- ============================================================================
-- Identifiers
-- ============================================================================

def testIdentifiers : IO Unit := do
  IO.println "\n--- Identifiers ---"

  runTest "simple identifier" (
    match firstType "myTable" with
    | some (.identifier "myTable") => true
    | _ => false
  )

  runTest "underscore start" (
    match firstType "_private" with
    | some (.identifier "_private") => true
    | _ => false
  )

  runTest "alphanumeric" (
    match firstType "col2" with
    | some (.identifier "col2") => true
    | _ => false
  )

  runTest "identifier with underscores" (
    match firstType "my_table_name" with
    | some (.identifier "my_table_name") => true
    | _ => false
  )

  -- Path navigation via dot
  runTest "a.b tokenizes as id dot id" (
    expectTypes "a.b" [.identifier "a", .opDot, .identifier "b"]
  )

  -- Qualified identifier via double colon
  runTest "schema::table tokenizes" (
    expectTypes "schema::table" [.identifier "schema", .opDoubleColon, .identifier "table"]
  )

-- ============================================================================
-- Dependent Type Annotations
-- ============================================================================

def testDependentTypeAnnotations : IO Unit := do
  IO.println "\n--- Dependent Type Annotations ---"

  -- Field : Type
  runTest "title : NonEmptyString" (
    expectTypes "title : NonEmptyString" [
      .identifier "title", .opColon, .kwNonEmptyString
    ]
  )

  -- Column : BoundedNat
  runTest "score : BoundedNat" (
    expectTypes "score : BoundedNat" [
      .identifier "score", .opColon, .kwBoundedNat
    ]
  )

  -- Multiple typed columns
  runTest "name : String , age : Nat" (
    expectTypes "name : String , age : Nat" [
      .identifier "name", .opColon, .kwString, .comma,
      .identifier "age", .opColon, .kwNat
    ]
  )

  -- Confidence type
  runTest "conf : Confidence" (
    expectTypes "conf : Confidence" [
      .identifier "conf", .opColon, .kwConfidence
    ]
  )

  -- PromptScores type
  runTest "ps : PromptScores" (
    expectTypes "ps : PromptScores" [
      .identifier "ps", .opColon, .kwPromptScores
    ]
  )

-- ============================================================================
-- Comments
-- ============================================================================

def testComments : IO Unit := do
  IO.println "\n--- Comments ---"

  -- Line comment before content
  runTest "-- comment then SELECT" (
    firstType "-- this is a comment\nSELECT" == some .kwSelect
  )

  -- Line comment strips remainder
  runTest "SELECT -- trailing" (
    expectTypes "SELECT -- trailing comment" [.kwSelect]
  )

  -- Block comment
  runTest "/* block */ SELECT" (
    firstType "/* block comment */ SELECT" == some .kwSelect
  )

  -- Block comment mid-stream
  runTest "SELECT /* skip */ FROM" (
    expectTypes "SELECT /* skip */ FROM" [.kwSelect, .kwFrom]
  )

  -- Multiple comments
  runTest "-- line\n/* block */\nSELECT" (
    firstType "-- line\n/* block */\nSELECT" == some .kwSelect
  )

  -- Comment-only input yields EOF
  runTest "comment-only yields EOF" (
    match tokenize "-- just a comment" with
    | .ok [t] => t.type == .eof
    | _ => false
  )

-- ============================================================================
-- Whitespace Handling
-- ============================================================================

def testWhitespace : IO Unit := do
  IO.println "\n--- Whitespace ---"

  -- Leading whitespace
  runTest "leading spaces" (firstType "   SELECT" == some .kwSelect)
  runTest "leading tabs" (firstType "\t\tSELECT" == some .kwSelect)
  runTest "leading newlines" (firstType "\n\nSELECT" == some .kwSelect)
  runTest "mixed whitespace" (firstType " \t\n\r SELECT" == some .kwSelect)

  -- Whitespace between tokens
  runTest "generous spacing" (
    expectTypes "SELECT   *   FROM   users" [.kwSelect, .opStar, .kwFrom, .identifier "users"]
  )

  -- Empty input
  runTest "empty string yields EOF" (
    match tokenize "" with
    | .ok [t] => t.type == .eof
    | _ => false
  )

  -- Whitespace-only input
  runTest "whitespace-only yields EOF" (
    match tokenize "   \t\n  " with
    | .ok [t] => t.type == .eof
    | _ => false
  )

-- ============================================================================
-- Token Position Tracking
-- ============================================================================

def testPositionTracking : IO Unit := do
  IO.println "\n--- Position Tracking ---"

  -- First token at line 1, column 1
  match tokenize "SELECT" with
  | .ok (t :: _) =>
    runTest "first token at line 1" (t.line == 1)
    runTest "first token at column 1" (t.column == 1)
  | _ =>
    runTest "first token position" false

  -- Second token after space
  match tokenize "SELECT *" with
  | .ok (_ :: t :: _) =>
    runTest "second token on same line" (t.line == 1)
    runTest "second token at column 8" (t.column == 8)
  | _ =>
    runTest "second token position" false

  -- Newline advances line counter
  match tokenize "SELECT\n*" with
  | .ok (_ :: t :: _) =>
    runTest "token after newline at line 2" (t.line == 2)
    runTest "token after newline at column 1" (t.column == 1)
  | _ =>
    runTest "newline position tracking" false

-- ============================================================================
-- Complex Query Fragments
-- ============================================================================

def testComplexQueries : IO Unit := do
  IO.println "\n--- Complex Query Fragments ---"

  -- SELECT with WHERE
  runTest "SELECT * FROM t WHERE x = 1" (
    expectTypes "SELECT * FROM t WHERE x = 1" [
      .kwSelect, .opStar, .kwFrom, .identifier "t",
      .kwWhere, .identifier "x", .opEq, .litNat 1
    ]
  )

  -- INSERT with typed columns
  runTest "INSERT INTO t (title : NonEmptyString) VALUES ('data')" (
    expectOk "INSERT INTO t (title : NonEmptyString) VALUES ('data')"
  )

  -- SELECT with comparison operators
  runTest "WHERE x >= 10 AND y <= 100" (
    expectTypes "WHERE x >= 10 AND y <= 100" [
      .kwWhere, .identifier "x", .opGe, .litNat 10,
      .kwAnd, .identifier "y", .opLe, .litNat 100
    ]
  )

  -- JOIN syntax
  runTest "LEFT OUTER JOIN b ON a.id = b.id" (
    expectTypes "LEFT OUTER JOIN b ON a.id = b.id" [
      .kwLeft, .kwOuter, .kwJoin, .identifier "b", .kwOn,
      .identifier "a", .opDot, .identifier "id", .opEq,
      .identifier "b", .opDot, .identifier "id"
    ]
  )

  -- GROUP BY / HAVING
  runTest "GROUP BY dept HAVING count > 5" (
    expectTypes "GROUP BY dept HAVING count > 5" [
      .kwGroup, .kwBy, .identifier "dept",
      .kwHaving, .identifier "count", .opGt, .litNat 5
    ]
  )

  -- LIMIT OFFSET
  runTest "LIMIT 10 OFFSET 20" (
    expectTypes "LIMIT 10 OFFSET 20" [
      .kwLimit, .litNat 10, .kwOffset, .litNat 20
    ]
  )

  -- WITH_PROOF clause
  runTest "WITH_PROOF THEOREM proof_name QED" (
    expectTypes "WITH_PROOF THEOREM proof_name QED" [
      .kwWithProof, .kwTheorem, .identifier "proof_name", .kwQed
    ]
  )

  -- Validation level
  runTest "VALIDATION LEVEL runtime" (
    expectTypes "VALIDATION LEVEL runtime" [
      .kwValidation, .kwLevel, .kwRuntime
    ]
  )

  -- GRANT / REVOKE
  runTest "GRANT SELECT ON evidence TO analyst" (
    expectTypes "GRANT SELECT ON evidence TO analyst" [
      .kwGrant, .kwSelect, .kwOn, .identifier "evidence", .kwTo, .identifier "analyst"
    ]
  )

-- ============================================================================
-- Error / Edge Cases
-- ============================================================================

def testEdgeCases : IO Unit := do
  IO.println "\n--- Edge Cases ---"

  -- Consecutive operators
  runTest "+-*/" (
    expectTypes "+-*/" [.opPlus, .opMinus, .opStar, .opSlash]
  )

  -- Adjacent tokens without whitespace
  runTest "(42)" (
    expectTypes "(42)" [.leftParen, .litNat 42, .rightParen]
  )

  -- Nested delimiters
  runTest "((a))" (
    expectTypes "((a))" [.leftParen, .leftParen, .identifier "a", .rightParen, .rightParen]
  )

  -- Lexeme preservation
  match tokenize "SELECT" with
  | .ok (t :: _) =>
    runTest "lexeme preserved for SELECT" (t.lexeme == "SELECT")
  | _ =>
    runTest "lexeme preserved for SELECT" false

  match tokenize "42" with
  | .ok (t :: _) =>
    runTest "lexeme preserved for 42" (t.lexeme == "42")
  | _ =>
    runTest "lexeme preserved for 42" false

  -- Keywords are not prefix-matched
  runTest "SELECTING is identifier" (
    match firstType "SELECTING" with
    | some (.identifier _) => true
    | _ => false
  )

  runTest "SELECTOR is identifier" (
    match firstType "SELECTOR" with
    | some (.identifier _) => true
    | _ => false
  )

-- ============================================================================
-- Main Test Runner
-- ============================================================================

def main : IO Unit := do
  IO.println "==============================================="
  IO.println "  GQL-DT Lexer Unit Tests"
  IO.println "==============================================="

  testSqlKeywords
  testTypeKeywords
  testProofKeywords
  testLithoglyphKeywords
  testOperators
  testDelimiters
  testNumberLiterals
  testStringLiterals
  testIdentifiers
  testDependentTypeAnnotations
  testComments
  testWhitespace
  testPositionTracking
  testComplexQueries
  testEdgeCases

  IO.println ""
  IO.println "==============================================="
  IO.println "  Lexer tests completed"
  IO.println "==============================================="
