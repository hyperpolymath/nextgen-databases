-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.Query.Parser - Parser combinators for GQL
--
-- Simple monadic parser for the Lithoglyph Query Language.
-- Supports SELECT, INSERT, UPDATE, DELETE with provenance metadata.

import FbqlDt.Query.AST

namespace FbqlDt.Query.Parser

-- ============================================================================
-- Parser Monad
-- ============================================================================

/-- Parser state: remaining input and current position -/
structure ParserState where
  input : String
  pos : Nat
  deriving Repr, Inhabited

/-- Parser result -/
inductive ParseResult (A : Type) where
  | ok : A → ParserState → ParseResult A
  | error : String → Nat → ParseResult A
  deriving Repr

instance {A : Type} : Inhabited (ParseResult A) where
  default := .error "default" 0

/-- Parser monad -/
def Parser (A : Type) := ParserState → ParseResult A

instance {A : Type} : Inhabited (Parser A) where
  default := fun s => .error "default" s.pos

namespace Parser

def run {A : Type} (p : Parser A) (input : String) : Except String A :=
  match p { input := input, pos := 0 } with
  | .ok a _ => .ok a
  | .error msg pos => .error s!"Parse error at position {pos}: {msg}"

def pure {A : Type} (a : A) : Parser A := fun s => .ok a s

def bind {A B : Type} (p : Parser A) (f : A → Parser B) : Parser B := fun s =>
  match p s with
  | .ok a s' => f a s'
  | .error msg pos => .error msg pos

instance : Monad Parser where
  pure := @pure
  bind := @bind

instance : MonadExceptOf String Parser where
  throw msg := fun s => .error msg s.pos
  tryCatch p handler := fun s =>
    match p s with
    | .ok a s' => .ok a s'
    | .error msg _ => handler msg s

/-- Get current position -/
def getPos : Parser Nat := fun s => .ok s.pos s

/-- Check if at end of input -/
def isEof : Parser Bool := fun s => .ok (s.pos ≥ s.input.length) s

/-- Peek at current character without consuming -/
def peek : Parser (Option Char) := fun s =>
  if s.pos < s.input.length then
    .ok (some (s.input.get ⟨s.pos⟩)) s
  else
    .ok none s

/-- Consume one character -/
def anyChar : Parser Char := fun s =>
  if s.pos < s.input.length then
    .ok (s.input.get ⟨s.pos⟩) { s with pos := s.pos + 1 }
  else
    .error "Unexpected end of input" s.pos

/-- Consume character satisfying predicate -/
def satisfy (pred : Char → Bool) (expected : String) : Parser Char := fun s =>
  if s.pos < s.input.length then
    let c := s.input.get ⟨s.pos⟩
    if pred c then
      .ok c { s with pos := s.pos + 1 }
    else
      .error s!"Expected {expected}, got '{c}'" s.pos
  else
    .error s!"Expected {expected}, got end of input" s.pos

/-- Parse a specific character -/
def char (c : Char) : Parser Char :=
  satisfy (· == c) s!"'{c}'"

/-- Parse a specific string (case-insensitive for keywords) -/
def stringCI (expected : String) : Parser String := fun s =>
  let len := expected.length
  if s.pos + len <= s.input.length then
    let slice := (s.input.drop s.pos).take len
    if slice.toLower == expected.toLower then
      .ok slice { s with pos := s.pos + len }
    else
      .error s!"Expected '{expected}'" s.pos
  else
    .error s!"Expected '{expected}'" s.pos

/-- Skip whitespace -/
def ws : Parser Unit := fun s =>
  let rec skipWs (pos : Nat) : Nat :=
    if pos < s.input.length then
      let c := s.input.get ⟨pos⟩
      if c == ' ' || c == '\t' || c == '\n' || c == '\r' then
        skipWs (pos + 1)
      else
        pos
    else
      pos
  .ok () { s with pos := skipWs s.pos }

/-- Parse zero or more occurrences -/
partial def many {A : Type} (p : Parser A) : Parser (List A) := fun s =>
  match p s with
  | .ok a s' =>
    match many p s' with
    | .ok as s'' => .ok (a :: as) s''
    | .error _ _ => .ok [a] s'
  | .error _ _ => .ok [] s

/-- Parse one or more occurrences -/
def many1 {A : Type} (p : Parser A) : Parser (List A) := do
  let first ← p
  let rest ← many p
  Pure.pure (first :: rest)

/-- Parse with optional result -/
def optional {A : Type} (p : Parser A) : Parser (Option A) := fun s =>
  match p s with
  | .ok a s' => .ok (some a) s'
  | .error _ _ => .ok none s

/-- Try first parser, fallback to second on failure -/
def orElse {A : Type} (p1 : Parser A) (p2 : Parser A) : Parser A := fun s =>
  match p1 s with
  | .ok a s' => .ok a s'
  | .error _ _ => p2 s

instance {A : Type} : OrElse (Parser A) where
  orElse p1 p2 := orElse p1 (p2 ())

/-- Parse separated list -/
partial def sepBy {A B : Type} (p : Parser A) (sep : Parser B) : Parser (List A) := fun s =>
  match p s with
  | .ok a s' =>
    let rec loop (acc : List A) (state : ParserState) : ParseResult (List A) :=
      match sep state with
      | .ok _ s'' =>
        match p s'' with
        | .ok a' s''' => loop (acc ++ [a']) s'''
        | .error _ _ => .ok acc s''
      | .error _ _ => .ok acc state
    loop [a] s'
  | .error _ _ => .ok [] s

/-- Parse separated list with at least one element -/
def sepBy1 {A B : Type} (p : Parser A) (sep : Parser B) : Parser (List A) := do
  let first ← p
  let rest ← many (do let _ ← sep; p)
  Pure.pure (first :: rest)

-- ============================================================================
-- Token Parsers
-- ============================================================================

/-- Parse an identifier (letter followed by alphanumeric/underscore) -/
def identifier : Parser String := do
  let _ ← ws
  let first ← satisfy (fun c => c.isAlpha || c == '_') "identifier"
  let rest ← many (satisfy (fun c => c.isAlphanum || c == '_') "identifier char")
  Pure.pure (String.mk (first :: rest))

/-- Parse a keyword (case-insensitive) -/
def keyword (kw : String) : Parser Unit := do
  let _ ← ws
  let _ ← stringCI kw
  -- Ensure keyword is not part of larger identifier
  let next ← peek
  match next with
  | some c => if c.isAlphanum || c == '_' then throw s!"Expected keyword '{kw}'"
  | none => Pure.pure ()

/-- Parse an integer literal -/
def intLiteral : Parser Int := do
  let _ ← ws
  let neg ← optional (char '-')
  let digits ← many1 (satisfy Char.isDigit "digit")
  let n := digits.foldl (fun acc d => acc * 10 + (d.toNat - '0'.toNat)) 0
  match neg with
  | some _ => Pure.pure (-(Int.ofNat n))
  | none => Pure.pure (Int.ofNat n)

/-- Parse a float literal (e.g., 3.14, -2.5) -/
def floatLiteral : Parser Float := do
  let _ ← ws
  let neg ← optional (char '-')
  let intPart ← many1 (satisfy Char.isDigit "digit")
  let _ ← char '.'
  let fracPart ← many1 (satisfy Char.isDigit "digit")
  let intVal := intPart.foldl (fun acc d => acc * 10 + (d.toNat - '0'.toNat)) 0
  let fracVal := fracPart.foldl (fun acc d => acc * 10 + (d.toNat - '0'.toNat)) 0
  let fracDiv := Float.pow 10.0 (Float.ofNat fracPart.length)
  let f := Float.ofNat intVal + (Float.ofNat fracVal / fracDiv)
  match neg with
  | some _ => Pure.pure (-f)
  | none => Pure.pure f

/-- Parse a string literal (double-quoted) -/
def stringLiteral : Parser String := do
  let _ ← ws
  let _ ← char '"'
  let chars ← many (satisfy (· != '"') "string character")
  let _ ← char '"'
  Pure.pure (String.mk chars)

/-- Parse a single-quoted string literal -/
def stringLiteralSingle : Parser String := do
  let _ ← ws
  let _ ← char '\''
  let chars ← many (satisfy (· != '\'') "string character")
  let _ ← char '\''
  Pure.pure (String.mk chars)

/-- Parse any string literal -/
def anyStringLiteral : Parser String :=
  stringLiteral <|> stringLiteralSingle

/-- Parse a symbol -/
def symbol (s : String) : Parser Unit := do
  let _ ← ws
  let _ ← stringCI s
  Pure.pure ()

-- ============================================================================
-- Expression Parsers
-- ============================================================================

/-- Parse a literal -/
def literal : Parser Literal := do
  let _ ← ws
  (do keyword "NULL"; Pure.pure Literal.null) <|>
  (do keyword "TRUE"; Pure.pure (Literal.bool true)) <|>
  (do keyword "FALSE"; Pure.pure (Literal.bool false)) <|>
  (do let s ← anyStringLiteral; Pure.pure (Literal.string s)) <|>
  (do let f ← floatLiteral; Pure.pure (Literal.float f)) <|>  -- Float before int!
  (do let n ← intLiteral; Pure.pure (Literal.int n))

/-- Parse a column reference -/
def columnRef : Parser QualifiedColumn := do
  let name1 ← identifier
  let dot ← optional (char '.')
  match dot with
  | some _ =>
    let name2 ← identifier
    Pure.pure (QualifiedColumn.qualified name1 name2)
  | none =>
    Pure.pure (QualifiedColumn.unqualified name1)

/-- Parse a comparison operator -/
def compOp : Parser CompOp := do
  let _ ← ws
  (do symbol "<="; Pure.pure CompOp.le) <|>
  (do symbol ">="; Pure.pure CompOp.ge) <|>
  (do symbol "<>"; Pure.pure CompOp.neq) <|>
  (do symbol "!="; Pure.pure CompOp.neq) <|>
  (do symbol "="; Pure.pure CompOp.eq) <|>
  (do symbol "<"; Pure.pure CompOp.lt) <|>
  (do symbol ">"; Pure.pure CompOp.gt)

/-- Parse a primary expression (literal or column) -/
def primaryExpr : Parser Expr := do
  (do let l ← literal; Pure.pure (Expr.lit l)) <|>
  (do let c ← columnRef; Pure.pure (Expr.col c))

/-- Parse a comparison expression -/
def compareExpr : Parser Expr := do
  let lhs ← primaryExpr
  let opOpt ← optional compOp
  match opOpt with
  | some op =>
    let rhs ← primaryExpr
    Pure.pure (Expr.compare lhs op rhs)
  | none => Pure.pure lhs

/-- Parse a NOT expression -/
def notExpr : Parser Expr := do
  let notKw ← optional (keyword "NOT")
  let e ← compareExpr
  match notKw with
  | some _ => Pure.pure (Expr.not e)
  | none => Pure.pure e

/-- Parse an AND expression -/
def andExpr : Parser Expr := do
  let first ← notExpr
  let rest ← many (do keyword "AND"; notExpr)
  Pure.pure (rest.foldl (fun acc e => Expr.logic acc LogicOp.and e) first)

/-- Parse an OR expression (top-level) -/
def expr : Parser Expr := do
  let first ← andExpr
  let rest ← many (do keyword "OR"; andExpr)
  Pure.pure (rest.foldl (fun acc e => Expr.logic acc LogicOp.or e) first)

-- ============================================================================
-- Query Parsers
-- ============================================================================

/-- Parse SELECT projection -/
def projection : Parser Projection := do
  (do symbol "*"; Pure.pure Projection.all) <|>
  (do
    let cols ← sepBy1 identifier (symbol ",")
    Pure.pure (Projection.columns (cols.map (fun n => { name := n }))))

/-- Parse ORDER BY clause -/
def orderByClause : Parser (List OrderBy) := do
  keyword "ORDER"
  keyword "BY"
  let items ← sepBy1 (do
    let col ← columnRef
    let dir ← (do keyword "DESC"; Pure.pure SortDir.desc) <|>
              (do let _ ← optional (keyword "ASC"); Pure.pure SortDir.asc)
    Pure.pure ({ column := col, direction := dir } : OrderBy)
  ) (symbol ",")
  Pure.pure items

/-- Parse LIMIT clause -/
def limitClause : Parser Nat := do
  keyword "LIMIT"
  let n ← intLiteral
  if n < 0 then throw "LIMIT must be non-negative"
  Pure.pure n.toNat

/-- Parse OFFSET clause -/
def offsetClause : Parser Nat := do
  keyword "OFFSET"
  let n ← intLiteral
  if n < 0 then throw "OFFSET must be non-negative"
  Pure.pure n.toNat

/-- Parse SELECT query -/
def selectQuery : Parser SelectQuery := do
  keyword "SELECT"
  let proj ← projection
  keyword "FROM"
  let table ← identifier
  let whereOpt ← optional (do keyword "WHERE"; expr)
  let orderByOpt ← optional orderByClause
  let limitOpt ← optional limitClause
  let offsetOpt ← optional offsetClause
  Pure.pure {
    projection := proj
    «from» := { name := table }
    whereClause := whereOpt
    orderBy := orderByOpt.getD []
    limit := limitOpt
    offset := offsetOpt
  }

/-- Parse column-value pair for INSERT/UPDATE -/
def columnValuePair : Parser ColumnValue := do
  let col ← identifier
  symbol "="
  let val ← expr
  Pure.pure { column := { name := col }, value := val }

/-- Parse INSERT statement -/
def insertStmt : Parser InsertStmt := do
  keyword "INSERT"
  keyword "INTO"
  let table ← identifier
  keyword "SET"
  let values ← sepBy1 columnValuePair (symbol ",")
  -- Optional provenance metadata (GQL extension)
  let actor ← optional (do keyword "ACTOR"; anyStringLiteral)
  let rationale ← optional (do keyword "RATIONALE"; anyStringLiteral)
  -- Optional PROMPT score for data quality enforcement
  let promptScore ← optional (do keyword "PROMPT"; intLiteral)
  Pure.pure {
    table := { name := table }
    values := values
    actor := actor
    rationale := rationale
    promptScore := promptScore.map (·.toNat)
  }

/-- Parse UPDATE statement -/
def updateStmt : Parser UpdateStmt := do
  keyword "UPDATE"
  let table ← identifier
  keyword "SET"
  let values ← sepBy1 columnValuePair (symbol ",")
  let whereOpt ← optional (do keyword "WHERE"; expr)
  let actor ← optional (do keyword "ACTOR"; anyStringLiteral)
  let rationale ← optional (do keyword "RATIONALE"; anyStringLiteral)
  Pure.pure {
    table := { name := table }
    set := values
    whereClause := whereOpt
    actor := actor
    rationale := rationale
  }

/-- Parse DELETE statement -/
def deleteStmt : Parser DeleteStmt := do
  keyword "DELETE"
  keyword "FROM"
  let table ← identifier
  let whereOpt ← optional (do keyword "WHERE"; expr)
  let actor ← optional (do keyword "ACTOR"; anyStringLiteral)
  let rationale ← optional (do keyword "RATIONALE"; anyStringLiteral)
  Pure.pure {
    table := { name := table }
    whereClause := whereOpt
    actor := actor
    rationale := rationale
  }

/-- Parse any GQL statement -/
def statement : Parser Statement := do
  let _ ← ws
  (do let q ← selectQuery; Pure.pure (Statement.select q)) <|>
  (do let i ← insertStmt; Pure.pure (Statement.insert i)) <|>
  (do let u ← updateStmt; Pure.pure (Statement.update u)) <|>
  (do let d ← deleteStmt; Pure.pure (Statement.delete d))

end Parser

-- ============================================================================
-- Public API
-- ============================================================================

/-- Parse an GQL statement from a string -/
def parse (input : String) : Except String Statement :=
  Parser.run Parser.statement input

/-- Parse a SELECT query from a string -/
def parseSelect (input : String) : Except String SelectQuery :=
  Parser.run Parser.selectQuery input

/-- Parse an expression from a string -/
def parseExpr (input : String) : Except String Expr :=
  Parser.run Parser.expr input

end FbqlDt.Query.Parser
