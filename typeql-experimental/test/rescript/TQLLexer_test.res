// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// TQLLexer_test.res — Dedicated lexer-level unit tests for VQL-dt++ parser
//
// Tests the low-level parser combinators (string matching, keyword recognition,
// identifier parsing, integer parsing, string literal parsing) and the
// individual extension clause tokenizers in TQLParser.res.
//
// These tests complement TQLParser_test.res which tests at the clause level.
// Here we verify individual token recognition and combinator behaviour.
//
// Run with: deno task res:build && deno run test/rescript/TQLLexer_test.res.mjs

// ============================================================================
// Test Utilities
// ============================================================================

let passed = ref(0)
let failed = ref(0)
let total = ref(0)

let assert_ = (name: string, condition: bool): unit => {
  total := total.contents + 1
  if condition {
    passed := passed.contents + 1
    Js.Console.log("  PASS: " ++ name)
  } else {
    failed := failed.contents + 1
    Js.Console.error("  FAIL: " ++ name)
  }
}

let assertParseOk = (name: string, parser: TQLParser.Parser.parser<'a>, input: string): unit => {
  switch parser(input) {
  | Ok(_) => assert_(name, true)
  | Error(_) => assert_(name, false)
  }
}

let assertParseErr = (name: string, parser: TQLParser.Parser.parser<'a>, input: string): unit => {
  switch parser(input) {
  | Ok(_) => assert_(name ++ " (expected error)", false)
  | Error(_) => assert_(name, true)
  }
}

let assertParseValue = (
  name: string,
  parser: TQLParser.Parser.parser<'a>,
  input: string,
  check: 'a => bool,
): unit => {
  switch parser(input) {
  | Ok((value, _consumed)) => assert_(name, check(value))
  | Error(_) => assert_(name ++ " (parse failed)", false)
  }
}

let assertConsumed = (
  name: string,
  parser: TQLParser.Parser.parser<'a>,
  input: string,
  expectedConsumed: int,
): unit => {
  switch parser(input) {
  | Ok((_value, consumed)) => assert_(name, consumed == expectedConsumed)
  | Error(_) => assert_(name ++ " (parse failed)", false)
  }
}

// ============================================================================
// Test: string combinator (case-insensitive keyword matching)
// ============================================================================

let testStringCombinator = (): unit => {
  Js.Console.log("\n--- string combinator (case-insensitive matching) ---")
  open TQLParser.Parser

  // Exact match
  assertParseOk("exact match SELECT", string("SELECT"), "SELECT")
  assertParseOk("exact match FROM", string("FROM"), "FROM")

  // Case insensitivity
  assertParseOk("lowercase select", string("SELECT"), "select")
  assertParseOk("mixed case SeLeCt", string("SELECT"), "SeLeCt")
  assertParseOk("uppercase CONSUME", string("CONSUME"), "CONSUME")
  assertParseOk("lowercase consume", string("CONSUME"), "consume")

  // Consumed length matches keyword length
  assertConsumed("SELECT consumes 6", string("SELECT"), "SELECT rest", 6)
  assertConsumed("FROM consumes 4", string("FROM"), "FROM rest", 4)

  // Non-match
  assertParseErr("mismatch INSERT vs SELECT", string("SELECT"), "INSERT")
  assertParseErr("partial match SEL", string("SELECT"), "SEL")
  assertParseErr("empty input", string("SELECT"), "")
}

// ============================================================================
// Test: keyword combinator (lexeme-wrapped string)
// ============================================================================

let testKeywordCombinator = (): unit => {
  Js.Console.log("\n--- keyword combinator ---")
  open TQLParser.Parser

  // Keywords consume trailing whitespace
  assertParseOk("keyword with trailing space", keyword("SELECT"), "SELECT ")
  assertParseOk("keyword with trailing tab", keyword("SELECT"), "SELECT\t")
  assertParseOk("keyword with trailing newline", keyword("SELECT"), "SELECT\n")
  assertParseOk("keyword no trailing ws", keyword("SELECT"), "SELECT")

  // VQL-dt++ specific keywords
  assertParseOk("CONSUME keyword", keyword("CONSUME"), "CONSUME")
  assertParseOk("AFTER keyword", keyword("AFTER"), "AFTER")
  assertParseOk("USE keyword", keyword("USE"), "USE")
  assertParseOk("WITH keyword", keyword("WITH"), "WITH")
  assertParseOk("SESSION keyword", keyword("SESSION"), "SESSION")
  assertParseOk("EFFECTS keyword", keyword("EFFECTS"), "EFFECTS")
  assertParseOk("IN keyword", keyword("IN"), "IN")
  assertParseOk("TRANSACTION keyword", keyword("TRANSACTION"), "TRANSACTION")
  assertParseOk("PROOF keyword", keyword("PROOF"), "PROOF")
  assertParseOk("ATTACHED keyword", keyword("ATTACHED"), "ATTACHED")
  assertParseOk("USAGE keyword", keyword("USAGE"), "USAGE")
  assertParseOk("LIMIT keyword", keyword("LIMIT"), "LIMIT")
}

// ============================================================================
// Test: identifier parser
// ============================================================================

let testIdentifier = (): unit => {
  Js.Console.log("\n--- identifier parser ---")
  open TQLParser.Parser

  // Valid identifiers
  assertParseValue("simple alpha", identifier, "hello rest",
    v => v == "hello")
  assertParseValue("alphanumeric", identifier, "col2 rest",
    v => v == "col2")
  assertParseValue("underscore start", identifier, "_private rest",
    v => v == "_private")
  assertParseValue("mixed", identifier, "my_table_name rest",
    v => v == "my_table_name")

  // Protocol names used as identifiers
  assertParseValue("ReadOnlyProtocol", identifier, "ReadOnlyProtocol rest",
    v => v == "ReadOnlyProtocol")
  assertParseValue("MutationProtocol", identifier, "MutationProtocol rest",
    v => v == "MutationProtocol")
  assertParseValue("StreamProtocol", identifier, "StreamProtocol rest",
    v => v == "StreamProtocol")
  assertParseValue("BatchProtocol", identifier, "BatchProtocol rest",
    v => v == "BatchProtocol")

  // Effect labels used as identifiers
  assertParseValue("Read as id", identifier, "Read rest", v => v == "Read")
  assertParseValue("Write as id", identifier, "Write rest", v => v == "Write")
  assertParseValue("Cite as id", identifier, "Cite rest", v => v == "Cite")
  assertParseValue("Audit as id", identifier, "Audit rest", v => v == "Audit")
  assertParseValue("Transform as id", identifier, "Transform rest", v => v == "Transform")
  assertParseValue("Federate as id", identifier, "Federate rest", v => v == "Federate")

  // Transaction states as identifiers
  assertParseValue("Fresh", identifier, "Fresh rest", v => v == "Fresh")
  assertParseValue("Active", identifier, "Active rest", v => v == "Active")
  assertParseValue("Committed", identifier, "Committed rest", v => v == "Committed")
  assertParseValue("RolledBack", identifier, "RolledBack rest", v => v == "RolledBack")
  assertParseValue("ReadSnapshot", identifier, "ReadSnapshot rest", v => v == "ReadSnapshot")

  // Identifier does not match digits
  assertParseErr("digit start fails", identifier, "123abc")
}

// ============================================================================
// Test: integer parser
// ============================================================================

let testInteger = (): unit => {
  Js.Console.log("\n--- integer parser ---")
  open TQLParser.Parser

  assertParseValue("zero", integer, "0 rest", v => v == 0)
  assertParseValue("single digit", integer, "5 rest", v => v == 5)
  assertParseValue("multi digit", integer, "42 rest", v => v == 42)
  assertParseValue("large number", integer, "123456 rest", v => v == 123456)
  assertParseValue("one", integer, "1 USE", v => v == 1)
  assertParseValue("hundred", integer, "100 rest", v => v == 100)

  // Should fail on non-numeric input
  assertParseErr("alpha fails", integer, "abc")
  assertParseErr("empty fails", integer, "")
}

// ============================================================================
// Test: stringLiteral parser
// ============================================================================

let testStringLiteral = (): unit => {
  Js.Console.log("\n--- stringLiteral parser ---")
  open TQLParser.Parser

  // Basic double-quoted strings
  assertParseValue("simple string", stringLiteral, "\"hello\" rest",
    v => v == "hello")
  assertParseValue("empty string", stringLiteral, "\"\" rest",
    v => v == "")
  assertParseValue("string with spaces", stringLiteral, "\"hello world\" rest",
    v => v == "hello world")

  // Strings with escape sequences
  assertParseValue("escaped quote", stringLiteral, "\"say \\\"hi\\\"\" rest",
    v => Js.String2.includes(v, "\\\""))

  // Non-string input
  assertParseErr("non-quoted fails", stringLiteral, "hello")
  assertParseErr("single-quoted fails", stringLiteral, "'hello'")
}

// ============================================================================
// Test: ws (whitespace) parser
// ============================================================================

let testWhitespace = (): unit => {
  Js.Console.log("\n--- whitespace parser ---")
  open TQLParser.Parser

  assertConsumed("single space", ws, " rest", 1)
  assertConsumed("multiple spaces", ws, "   rest", 3)
  assertConsumed("tab", ws, "\t rest", 1)
  assertConsumed("newline", ws, "\n rest", 1)
  assertConsumed("mixed whitespace", ws, " \t\n rest", 3)
  assertConsumed("no whitespace", ws, "rest", 0)
  assertConsumed("empty input", ws, "", 0)
}

// ============================================================================
// Test: sepBy combinator
// ============================================================================

let testSepBy = (): unit => {
  Js.Console.log("\n--- sepBy combinator ---")
  open TQLParser.Parser

  // Single element
  assertParseValue("single element", sepBy(identifier, keyword(",")), "Read }",
    v => Js.Array2.length(v) == 1)

  // Multiple elements
  assertParseValue("three elements", sepBy(identifier, keyword(",")), "Read, Write, Cite }",
    v => Js.Array2.length(v) == 3)

  // Six elements (all standard effects)
  assertParseValue("six elements",
    sepBy(identifier, keyword(",")),
    "Read, Write, Cite, Audit, Transform, Federate }",
    v => Js.Array2.length(v) == 6)
}

// ============================================================================
// Test: optional combinator
// ============================================================================

let testOptional = (): unit => {
  Js.Console.log("\n--- optional combinator ---")
  open TQLParser.Parser

  // Present value
  assertParseValue("present value", optional(keyword("SELECT")), "SELECT rest",
    v => {
      switch v {
      | Some(_) => true
      | None => false
      }
    })

  // Absent value (non-matching input)
  assertParseValue("absent value", optional(keyword("SELECT")), "INSERT rest",
    v => {
      switch v {
      | Some(_) => false
      | None => true
      }
    })

  // Absent on empty
  assertParseValue("absent on empty", optional(keyword("SELECT")), "",
    v => {
      switch v {
      | Some(_) => false
      | None => true
      }
    })
}

// ============================================================================
// Test: <|> (alternative) combinator
// ============================================================================

let testAlternative = (): unit => {
  Js.Console.log("\n--- alternative (<|>) combinator ---")
  open TQLParser.Parser

  let selectOrInsert = \"<|>"(keyword("SELECT"), keyword("INSERT"))

  assertParseOk("first alternative matches", selectOrInsert, "SELECT rest")
  assertParseOk("second alternative matches", selectOrInsert, "INSERT rest")
  assertParseErr("neither matches", selectOrInsert, "UPDATE rest")
}

// ============================================================================
// Test: Session protocol token recognition
// ============================================================================

let testSessionProtocolTokens = (): unit => {
  Js.Console.log("\n--- Session protocol tokens ---")

  // Each built-in protocol
  let test = (name, input, check) => {
    switch TQLParser.parseExtensions(input) {
    | Ok(ann) => assert_(name, check(ann.sessionProtocol))
    | Error(_) => assert_(name ++ " (parse failed)", false)
    }
  }

  test("ReadOnlyProtocol",
    "WITH SESSION ReadOnlyProtocol",
    p => p == Some(TQLAst.ReadOnlyProtocol))
  test("MutationProtocol",
    "WITH SESSION MutationProtocol",
    p => p == Some(TQLAst.MutationProtocol))
  test("StreamProtocol",
    "WITH SESSION StreamProtocol",
    p => p == Some(TQLAst.StreamProtocol))
  test("BatchProtocol",
    "WITH SESSION BatchProtocol",
    p => p == Some(TQLAst.BatchProtocol))
  test("CustomProtocol",
    "WITH SESSION MyCustomThing",
    p => {
      switch p {
      | Some(TQLAst.CustomProtocol(name)) => name == "MyCustomThing"
      | _ => false
      }
    })
}

// ============================================================================
// Test: Effect label token recognition
// ============================================================================

let testEffectLabelTokens = (): unit => {
  Js.Console.log("\n--- Effect label tokens ---")

  let test = (name, input, expectedCount) => {
    switch TQLParser.parseExtensions(input) {
    | Ok(ann) =>
      switch ann.declaredEffects {
      | Some({effects}) => assert_(name, Js.Array2.length(effects) == expectedCount)
      | None => assert_(name ++ " (no effects)", false)
      }
    | Error(_) => assert_(name ++ " (parse failed)", false)
    }
  }

  test("single Read effect", "EFFECTS { Read }", 1)
  test("single Write effect", "EFFECTS { Write }", 1)
  test("single Cite effect", "EFFECTS { Cite }", 1)
  test("single Audit effect", "EFFECTS { Audit }", 1)
  test("single Transform effect", "EFFECTS { Transform }", 1)
  test("single Federate effect", "EFFECTS { Federate }", 1)
  test("custom effect", "EFFECTS { MyEffect }", 1)
  test("two effects", "EFFECTS { Read, Write }", 2)
  test("all six standard effects",
    "EFFECTS { Read, Write, Cite, Audit, Transform, Federate }", 6)
}

// ============================================================================
// Test: Transaction state token recognition
// ============================================================================

let testTransactionStateTokens = (): unit => {
  Js.Console.log("\n--- Transaction state tokens ---")

  let test = (name, input, expected) => {
    switch TQLParser.parseExtensions(input) {
    | Ok(ann) =>
      switch ann.modalScope {
      | Some({state}) => assert_(name, state == expected)
      | None => assert_(name ++ " (no modalScope)", false)
      }
    | Error(_) => assert_(name ++ " (parse failed)", false)
    }
  }

  test("Fresh", "IN TRANSACTION Fresh", TQLAst.TxFresh)
  test("Active", "IN TRANSACTION Active", TQLAst.TxActive)
  test("Committed", "IN TRANSACTION Committed", TQLAst.TxCommitted)
  test("RolledBack", "IN TRANSACTION RolledBack", TQLAst.TxRolledBack)
  test("ReadSnapshot", "IN TRANSACTION ReadSnapshot", TQLAst.TxReadSnapshot)

  // Custom transaction state
  switch TQLParser.parseExtensions("IN TRANSACTION MyCustomState") {
  | Ok(ann) =>
    switch ann.modalScope {
    | Some({state: TQLAst.TxCustom(name)}) => assert_("custom state", name == "MyCustomState")
    | _ => assert_("custom state (wrong type)", false)
    }
  | Error(_) => assert_("custom state (parse failed)", false)
  }
}

// ============================================================================
// Test: Dependent type syntax (CONSUME AFTER n USE)
// ============================================================================

let testDependentTypeSyntax = (): unit => {
  Js.Console.log("\n--- Dependent type syntax (CONSUME AFTER) ---")

  let test = (name, input, expectedCount) => {
    switch TQLParser.parseExtensions(input) {
    | Ok(ann) =>
      switch ann.consumeAfter {
      | Some({count}) => assert_(name, count == expectedCount)
      | None => assert_(name ++ " (no consumeAfter)", false)
      }
    | Error(_) => assert_(name ++ " (parse failed)", false)
    }
  }

  test("CONSUME AFTER 1 USE", "CONSUME AFTER 1 USE", 1)
  test("CONSUME AFTER 3 USE", "CONSUME AFTER 3 USE", 3)
  test("CONSUME AFTER 10 USE", "CONSUME AFTER 10 USE", 10)
  test("CONSUME AFTER 100 USE", "CONSUME AFTER 100 USE", 100)
}

// ============================================================================
// Test: Proof carrying syntax (PROOF ATTACHED)
// ============================================================================

let testProofCarryingSyntax = (): unit => {
  Js.Console.log("\n--- Proof carrying syntax (PROOF ATTACHED) ---")

  // Simple theorem reference
  switch TQLParser.parseExtensions("PROOF ATTACHED IntegrityTheorem") {
  | Ok(ann) =>
    switch ann.proofAttached {
    | Some({name, params}) =>
      assert_("theorem name", name == "IntegrityTheorem")
      assert_("no params", params == None)
    | None => assert_("has proofAttached", false)
    }
  | Error(_) => assert_("parse PROOF ATTACHED (simple)", false)
  }

  // Theorem with parameters
  switch TQLParser.parseExtensions(`PROOF ATTACHED FreshnessGuarantee(maxAge="300")`) {
  | Ok(ann) =>
    switch ann.proofAttached {
    | Some({name, params}) =>
      assert_("theorem name with params", name == "FreshnessGuarantee")
      assert_("has params", {
        switch params {
        | Some(p) => Js.Array2.length(p) == 1
        | None => false
        }
      })
    | None => assert_("has proofAttached (with params)", false)
    }
  | Error(_) => assert_("parse PROOF ATTACHED (with params)", false)
  }
}

// ============================================================================
// Test: USAGE LIMIT (quantitative type theory)
// ============================================================================

let testUsageLimitSyntax = (): unit => {
  Js.Console.log("\n--- USAGE LIMIT syntax ---")

  let test = (name, input, expectedLimit) => {
    switch TQLParser.parseExtensions(input) {
    | Ok(ann) =>
      switch ann.usageLimit {
      | Some({limit}) => assert_(name, limit == expectedLimit)
      | None => assert_(name ++ " (no usageLimit)", false)
      }
    | Error(_) => assert_(name ++ " (parse failed)", false)
    }
  }

  test("USAGE LIMIT 1", "USAGE LIMIT 1", 1)
  test("USAGE LIMIT 10", "USAGE LIMIT 10", 10)
  test("USAGE LIMIT 100", "USAGE LIMIT 100", 100)
  test("USAGE LIMIT 1000", "USAGE LIMIT 1000", 1000)
}

// ============================================================================
// Test: Error cases
// ============================================================================

let testErrorCases = (): unit => {
  Js.Console.log("\n--- Error cases ---")

  // Incomplete keywords
  assertParseErr("CONSUME without AFTER",
    TQLParser.ExtensionParsers.consumeClause, "CONSUME rest")

  assertParseErr("WITH without SESSION",
    TQLParser.ExtensionParsers.sessionClause, "WITH rest")

  assertParseErr("IN without TRANSACTION",
    TQLParser.ExtensionParsers.modalClause, "IN rest")

  assertParseErr("PROOF without ATTACHED",
    TQLParser.ExtensionParsers.proofAttachedClause, "PROOF rest")

  assertParseErr("USAGE without LIMIT",
    TQLParser.ExtensionParsers.usageLimitClause, "USAGE rest")

  assertParseErr("EFFECTS without braces",
    TQLParser.ExtensionParsers.effectsClause, "EFFECTS Read")

  // Validation errors
  assert_("negative CONSUME AFTER rejected",
    switch TQLParser.parseAndValidateExtensions("CONSUME AFTER 0 USE") {
    | Ok(ann) =>
      switch ann.consumeAfter {
      | Some({count}) => count > 0 // may parse but validation catches it
      | None => true
      }
    | Error(_) => true
    })

  // Misspelled keywords don't match
  assertParseErr("SELEC (misspelled) fails",
    TQLParser.Parser.keyword("SELECT"), "SELEC rest")

  // Completely wrong input
  switch TQLParser.parseExtensions("GOBBLEDYGOOK") {
  | Ok(ann) =>
    // Should parse as empty annotations (all None) since extensions are optional
    assert_("garbage yields empty annotations",
      ann.consumeAfter == None &&
      ann.sessionProtocol == None &&
      ann.declaredEffects == None &&
      ann.modalScope == None &&
      ann.proofAttached == None &&
      ann.usageLimit == None)
  | Error(_) => assert_("garbage input handled", true)
  }
}

// ============================================================================
// Test: Token ordering in combined queries
// ============================================================================

let testTokenOrdering = (): unit => {
  Js.Console.log("\n--- Token ordering in combined queries ---")

  // Extensions must appear in specific order
  let fullQuery = "CONSUME AFTER 1 USE WITH SESSION ReadOnlyProtocol EFFECTS { Read, Write } IN TRANSACTION Active PROOF ATTACHED TestTheorem USAGE LIMIT 50"
  switch TQLParser.parseExtensions(fullQuery) {
  | Ok(ann) =>
    assert_("all six clauses present", {
      ann.consumeAfter != None &&
      ann.sessionProtocol != None &&
      ann.declaredEffects != None &&
      ann.modalScope != None &&
      ann.proofAttached != None &&
      ann.usageLimit != None
    })
  | Error(_) => assert_("full combined query parses", false)
  }

  // Partial combinations
  switch TQLParser.parseExtensions("WITH SESSION BatchProtocol USAGE LIMIT 5") {
  | Ok(ann) =>
    assert_("session + usage only", {
      ann.consumeAfter == None &&
      ann.sessionProtocol != None &&
      ann.declaredEffects == None &&
      ann.modalScope == None &&
      ann.proofAttached == None &&
      ann.usageLimit != None
    })
  | Error(_) => assert_("partial combination parses", false)
  }
}

// ============================================================================
// Run all tests
// ============================================================================

let () = {
  Js.Console.log("=== VQL-dt++ Lexer / Token Unit Tests ===")
  testStringCombinator()
  testKeywordCombinator()
  testIdentifier()
  testInteger()
  testStringLiteral()
  testWhitespace()
  testSepBy()
  testOptional()
  testAlternative()
  testSessionProtocolTokens()
  testEffectLabelTokens()
  testTransactionStateTokens()
  testDependentTypeSyntax()
  testProofCarryingSyntax()
  testUsageLimitSyntax()
  testErrorCases()
  testTokenOrdering()
  Js.Console.log(
    "\n=== Results: " ++
    Belt.Int.toString(passed.contents) ++ " passed, " ++
    Belt.Int.toString(failed.contents) ++ " failed, " ++
    Belt.Int.toString(total.contents) ++ " total ==="
  )
}
