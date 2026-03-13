-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- Lexer for GQL-DT/GQL
-- Tokenizes source text according to spec/GQL-DT-Lexical.md
-- Rewritten without Parsec for Lean 4.15.0 compatibility

namespace FbqlDt.Lexer

/-!
# GQL-DT Lexer

Tokenizes GQL-DT/GQL source code into tokens according to the formal
lexical specification (spec/GQL-DT-Lexical.md).

**Token Types:**
- Keywords: SELECT, INSERT, CREATE, etc. (80+ keywords)
- Identifiers: table names, column names, etc.
- Literals: numbers, strings, booleans
- Operators: +, -, *, /, =, etc.
- Delimiters: (, ), {, }, [, ], ;, ,
- Comments: -- single line, /* multi-line */

**Unicode Support:**
- Identifiers: XID_Start, XID_Continue (approximated)
- Escape sequences: \n, \t, \x2A, \u{1F4A9}
-/

-- ============================================================================
-- Token Types
-- ============================================================================

/-- Token type -/
inductive TokenType where
  -- Keywords (SQL - case insensitive)
  | kwSelect | kwInsert | kwUpdate | kwDelete | kwCreate | kwDrop
  | kwFrom | kwWhere | kwInto | kwValues | kwSet
  | kwAnd | kwOr | kwNot | kwIs | kwNull
  | kwAs | kwOn | kwJoin | kwLeft | kwRight | kwOuter | kwInner
  | kwGroup | kwOrder | kwBy | kwHaving | kwLimit | kwOffset
  | kwDistinct | kwAll | kwExists | kwIn | kwBetween | kwLike
  | kwTable | kwCollection | kwIf | kwWith

  -- Type Keywords (case sensitive)
  | kwNat | kwInt | kwString | kwBool | kwFloat | kwDate | kwUUID
  | kwBoundedNat | kwBoundedInt | kwBoundedFloat
  | kwNonEmptyString | kwConfidence | kwPromptScores
  | kwTracked | kwRationale

  -- Proof Keywords
  | kwWithProof | kwTheorem | kwProof | kwQed
  | kwOmega | kwDecide | kwSimp | kwSorry

  -- Lithoglyph Keywords
  | kwTarget | kwNormalForm | kwNormalize
  | kwPermissions | kwGrant | kwRevoke | kwTo
  | kwValidation | kwLevel | kwRuntime | kwCompile

  -- Literals
  | litNat (n : Nat)
  | litInt (i : Int)
  | litFloat (f : Float)
  | litString (s : String)
  | litBool (b : Bool)

  -- Identifiers
  | identifier (name : String)
  | qualifiedId (parts : List String)

  -- Operators
  | opPlus | opMinus | opStar | opSlash | opPercent | opCaret
  | opEq | opNeq | opLt | opLe | opGt | opGe
  | opAnd | opOr | opNot
  | opDot | opColon | opDoubleColon | opArrow

  -- Delimiters
  | leftParen | rightParen
  | leftBrace | rightBrace
  | leftBracket | rightBracket
  | semicolon | comma

  -- Special
  | eof
  deriving Repr, BEq

-- ToString instance for TokenType
instance : ToString TokenType where
  toString
    | .kwSelect => "SELECT"
    | .kwInsert => "INSERT"
    | .kwUpdate => "UPDATE"
    | .kwDelete => "DELETE"
    | .kwFrom => "FROM"
    | .kwWhere => "WHERE"
    | .kwInto => "INTO"
    | .kwValues => "VALUES"
    | .kwSet => "SET"
    | .kwRationale => "RATIONALE"
    | .kwNat => "Nat"
    | .kwInt => "Int"
    | .kwString => "String"
    | .kwBool => "Bool"
    | .kwNonEmptyString => "NonEmptyString"
    | .kwBoundedNat => "BoundedNat"
    | .kwConfidence => "Confidence"
    | .kwPromptScores => "PromptScores"
    | .litNat n => s!"<Nat:{n}>"
    | .litInt i => s!"<Int:{i}>"
    | .litFloat f => s!"<Float:{f}>"
    | .litString s => s!"<String:\"{s}\">"
    | .litBool b => s!"<Bool:{b}>"
    | .identifier name => s!"<id:{name}>"
    | .opEq => "="
    | .opLt => "<"
    | .opGt => ">"
    | .opLe => "<="
    | .opGe => ">="
    | .opNeq => "!="
    | .opDoubleColon => "::"
    | .leftParen => "("
    | .rightParen => ")"
    | .comma => ","
    | .semicolon => ";"
    | .opStar => "*"
    | .eof => "EOF"
    | _ => "<token>"

/-- Token with location information -/
structure Token where
  type : TokenType
  line : Nat
  column : Nat
  lexeme : String  -- Original text
  deriving Repr

-- ============================================================================
-- Lexer State
-- ============================================================================

structure LexerState where
  input : String
  pos : String.Pos
  line : Nat
  column : Nat
  deriving Repr

def LexerState.atEnd (s : LexerState) : Bool :=
  s.pos >= s.input.endPos

def LexerState.curr (s : LexerState) : Option Char :=
  if s.atEnd then none else some (s.input.get s.pos)

def LexerState.advance (s : LexerState) : LexerState :=
  if s.atEnd then s
  else
    let c := s.input.get s.pos
    let nextPos := s.input.next s.pos
    if c = '\n' then
      { input := s.input, pos := nextPos, line := s.line + 1, column := 1 }
    else
      { input := s.input, pos := nextPos, line := s.line, column := s.column + 1 }

def LexerState.peek (s : LexerState) (offset : Nat := 1) : Option Char :=
  let endPos := s.input.endPos
  let rec loop (p : String.Pos) (n : Nat) : Option Char :=
    if n >= offset then
      if p >= endPos then none else some (s.input.get p)
    else
      if p >= endPos then none
      else loop (s.input.next p) (n + 1)
  termination_by (offset - n)
  loop s.pos 0

-- ============================================================================
-- Character Classification
-- ============================================================================

def isWhitespace (c : Char) : Bool :=
  c = ' ' || c = '\t' || c = '\n' || c = '\r'

def isDigit (c : Char) : Bool :=
  c >= '0' && c <= '9'

def isAlpha (c : Char) : Bool :=
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

def isAlphaNum (c : Char) : Bool :=
  isAlpha c || isDigit c

def isIdentifierStart (c : Char) : Bool :=
  isAlpha c || c = '_' || c.val > 127  -- Unicode support

def isIdentifierContinue (c : Char) : Bool :=
  isAlphaNum c || c = '_' || c.val > 127

-- ============================================================================
-- Keyword Recognition
-- ============================================================================

def sqlKeywords : List (String × TokenType) := [
  ("SELECT", .kwSelect), ("INSERT", .kwInsert), ("UPDATE", .kwUpdate),
  ("DELETE", .kwDelete), ("CREATE", .kwCreate), ("DROP", .kwDrop),
  ("FROM", .kwFrom), ("WHERE", .kwWhere), ("INTO", .kwInto),
  ("VALUES", .kwValues), ("SET", .kwSet),
  ("AND", .kwAnd), ("OR", .kwOr), ("NOT", .kwNot),
  ("IS", .kwIs), ("NULL", .kwNull),
  ("AS", .kwAs), ("ON", .kwOn), ("JOIN", .kwJoin),
  ("LEFT", .kwLeft), ("RIGHT", .kwRight), ("OUTER", .kwOuter), ("INNER", .kwInner),
  ("GROUP", .kwGroup), ("ORDER", .kwOrder), ("BY", .kwBy),
  ("HAVING", .kwHaving), ("LIMIT", .kwLimit), ("OFFSET", .kwOffset),
  ("DISTINCT", .kwDistinct), ("ALL", .kwAll),
  ("EXISTS", .kwExists), ("IN", .kwIn), ("BETWEEN", .kwBetween), ("LIKE", .kwLike),
  ("TABLE", .kwTable), ("COLLECTION", .kwCollection), ("IF", .kwIf), ("WITH", .kwWith)
]

def typeKeywords : List (String × TokenType) := [
  ("Nat", .kwNat), ("Int", .kwInt), ("String", .kwString),
  ("Bool", .kwBool), ("Float", .kwFloat), ("Date", .kwDate), ("UUID", .kwUUID),
  ("BoundedNat", .kwBoundedNat), ("BoundedInt", .kwBoundedInt),
  ("BoundedFloat", .kwBoundedFloat),
  ("NonEmptyString", .kwNonEmptyString),
  ("Confidence", .kwConfidence), ("PromptScores", .kwPromptScores),
  ("Tracked", .kwTracked), ("Rationale", .kwRationale)
]

def proofKeywords : List (String × TokenType) := [
  ("WITH_PROOF", .kwWithProof), ("THEOREM", .kwTheorem),
  ("PROOF", .kwProof), ("QED", .kwQed),
  ("omega", .kwOmega), ("decide", .kwDecide),
  ("simp", .kwSimp), ("sorry", .kwSorry)
]

def lithoglyphKeywords : List (String × TokenType) := [
  ("RATIONALE", .kwRationale), ("TARGET_NORMAL_FORM", .kwTarget),
  ("NORMALIZE", .kwNormalize),
  ("PERMISSIONS", .kwPermissions), ("GRANT", .kwGrant), ("REVOKE", .kwRevoke),
  ("TO", .kwTo), ("VALIDATION", .kwValidation), ("LEVEL", .kwLevel),
  ("runtime", .kwRuntime), ("compile", .kwCompile)
]

def lookupKeyword (s : String) : Option TokenType :=
  (typeKeywords ++ proofKeywords ++ lithoglyphKeywords).lookup s
  <|>
  sqlKeywords.lookup s.toUpper

-- ============================================================================
-- Token Parsing
-- ============================================================================

partial def skipWhitespace (s : LexerState) : LexerState :=
  match s.curr with
  | none => s
  | some c =>
    if isWhitespace c then
      skipWhitespace s.advance
    else
      s

partial def skipLineComment (s : LexerState) : LexerState :=
  match s.curr with
  | none => s
  | some '\n' => s.advance
  | some _ => skipLineComment s.advance

partial def skipBlockComment (s : LexerState) : LexerState :=
  match s.curr, s.peek 0 with
  | some '*', some '/' => s.advance.advance
  | none, _ => s
  | _, _ => skipBlockComment s.advance

partial def skipWhitespaceAndComments (s : LexerState) : LexerState :=
  let s' := skipWhitespace s
  match s'.curr, s'.peek 0 with
  | some '-', some '-' => skipWhitespaceAndComments (skipLineComment (s'.advance.advance))
  | some '/', some '*' => skipWhitespaceAndComments (skipBlockComment (s'.advance.advance))
  | _, _ => s'

partial def parseNumber (s : LexerState) : LexerState × String :=
  let start := s.pos
  let rec loop (state : LexerState) : LexerState :=
    match state.curr with
    | some c =>
      if isDigit c then loop state.advance
      else state
    | none => state
  let final := loop s
  (final, s.input.extract start final.pos)

partial def parseString (s : LexerState) (quote : Char) : LexerState × String :=
  let start := s.pos
  let rec loop (state : LexerState) (acc : String) : LexerState × String :=
    match state.curr with
    | none => (state, acc)
    | some c =>
      if c = quote then
        (state.advance, acc)
      else if c = '\\' then
        match state.peek 0 with
        | some 'n' => loop (state.advance.advance) (acc ++ "\n")
        | some 't' => loop (state.advance.advance) (acc ++ "\t")
        | some 'r' => loop (state.advance.advance) (acc ++ "\r")
        | some '\\' => loop (state.advance.advance) (acc ++ "\\")
        | some '\'' => loop (state.advance.advance) (acc ++ "'")
        | some '"' => loop (state.advance.advance) (acc ++ "\"")
        | some esc => loop (state.advance.advance) (acc.push esc)
        | none => (state, acc)
      else
        loop (state.advance) (acc.push c)
  loop s.advance ""

partial def parseIdentifier (s : LexerState) : LexerState × String :=
  let start := s.pos
  let rec loop (state : LexerState) : LexerState :=
    match state.curr with
    | some c =>
      if isIdentifierContinue c then loop state.advance
      else state
    | none => state
  let final := loop s.advance
  (final, s.input.extract start final.pos)

def tokenizeOne (s : LexerState) : Option (Token × LexerState) :=
  let s' := skipWhitespaceAndComments s
  if s'.atEnd then
    some ({ type := .eof, line := s'.line, column := s'.column, lexeme := "" }, s')
  else
    match s'.curr with
    | none => none
    | some c =>
      let line := s'.line
      let column := s'.column

      -- Numbers
      if isDigit c then
        let (s'', numStr) := parseNumber s'
        match numStr.toNat? with
        | some n => some ({ type := .litNat n, line := line, column := column, lexeme := numStr }, s'')
        | none => none

      -- Strings
      else if c = '\'' || c = '"' then
        let (s'', str) := parseString s' c
        some ({ type := .litString str, line := line, column := column, lexeme := "\"" ++ str ++ "\"" }, s'')

      -- Identifiers and keywords
      else if isIdentifierStart c then
        let (s'', id) := parseIdentifier s'
        let tokType := lookupKeyword id |>.getD (.identifier id)
        some ({ type := tokType, line := line, column := column, lexeme := id }, s'')

      -- Operators and delimiters
      else if c = '+' then some ({ type := .opPlus, line := line, column := column, lexeme := "+" }, s'.advance)
      else if c = '-' then some ({ type := .opMinus, line := line, column := column, lexeme := "-" }, s'.advance)
      else if c = '*' then some ({ type := .opStar, line := line, column := column, lexeme := "*" }, s'.advance)
      else if c = '/' then some ({ type := .opSlash, line := line, column := column, lexeme := "/" }, s'.advance)
      else if c = '%' then some ({ type := .opPercent, line := line, column := column, lexeme := "%" }, s'.advance)
      else if c = '^' then some ({ type := .opCaret, line := line, column := column, lexeme := "^" }, s'.advance)
      else if c = '=' then some ({ type := .opEq, line := line, column := column, lexeme := "=" }, s'.advance)
      else if c = '<' then
        match s'.peek 0 with
        | some '=' => some ({ type := .opLe, line := line, column := column, lexeme := "<=" }, s'.advance.advance)
        | some '>' => some ({ type := .opNeq, line := line, column := column, lexeme := "<>" }, s'.advance.advance)
        | _ => some ({ type := .opLt, line := line, column := column, lexeme := "<" }, s'.advance)
      else if c = '>' then
        match s'.peek 0 with
        | some '=' => some ({ type := .opGe, line := line, column := column, lexeme := ">=" }, s'.advance.advance)
        | _ => some ({ type := .opGt, line := line, column := column, lexeme := ">" }, s'.advance)
      else if c = '!' then
        match s'.peek 0 with
        | some '=' => some ({ type := .opNeq, line := line, column := column, lexeme := "!=" }, s'.advance.advance)
        | _ => some ({ type := .opNot, line := line, column := column, lexeme := "!" }, s'.advance)
      else if c = '.' then some ({ type := .opDot, line := line, column := column, lexeme := "." }, s'.advance)
      else if c = ':' then
        match s'.peek 0 with
        | some ':' => some ({ type := .opDoubleColon, line := line, column := column, lexeme := "::" }, s'.advance.advance)
        | _ => some ({ type := .opColon, line := line, column := column, lexeme := ":" }, s'.advance)
      else if c = '(' then some ({ type := .leftParen, line := line, column := column, lexeme := "(" }, s'.advance)
      else if c = ')' then some ({ type := .rightParen, line := line, column := column, lexeme := ")" }, s'.advance)
      else if c = '{' then some ({ type := .leftBrace, line := line, column := column, lexeme := "{" }, s'.advance)
      else if c = '}' then some ({ type := .rightBrace, line := line, column := column, lexeme := "}" }, s'.advance)
      else if c = '[' then some ({ type := .leftBracket, line := line, column := column, lexeme := "[" }, s'.advance)
      else if c = ']' then some ({ type := .rightBracket, line := line, column := column, lexeme := "]" }, s'.advance)
      else if c = ';' then some ({ type := .semicolon, line := line, column := column, lexeme := ";" }, s'.advance)
      else if c = ',' then some ({ type := .comma, line := line, column := column, lexeme := "," }, s'.advance)

      else none

partial def tokenizeAll (s : LexerState) (acc : List Token) : List Token :=
  match tokenizeOne s with
  | none => acc.reverse
  | some (tok, s') =>
    if tok.type == .eof then
      (tok :: acc).reverse
    else
      tokenizeAll s' (tok :: acc)

def tokenize (source : String) : Except String (List Token) :=
  let initialState : LexerState := {
    input := source,
    pos := 0,
    line := 1,
    column := 1
  }
  .ok (tokenizeAll initialState [])

-- ============================================================================
-- Examples & Tests
-- ============================================================================

/-- Example: Tokenize simple INSERT -/
def exampleTokenizeInsert : Except String (List Token) :=
  tokenize "INSERT INTO evidence (title, score) VALUES ('ONS Data', 95)"

#eval exampleTokenizeInsert

/-- Example: Tokenize with type annotations -/
def exampleTokenizeTyped : Except String (List Token) :=
  tokenize "INSERT INTO evidence (title : NonEmptyString) VALUES ('ONS Data')"

#eval exampleTokenizeTyped

end FbqlDt.Lexer
