// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// TQLParser_test.res — Parser tests for VQL-dt++ extension clauses
//
// Tests each of the six extension clause parsers individually and
// in combination.

// ============================================================================
// Test Utilities
// ============================================================================

let assertOk = (name: string, result: Result<'a, 'b>): unit => {
  switch result {
  | Ok(_) => Js.Console.log("PASS: " ++ name)
  | Error(_) => Js.Console.error("FAIL: " ++ name)
  }
}

let assertError = (name: string, result: Result<'a, 'b>): unit => {
  switch result {
  | Ok(_) => Js.Console.error("FAIL (expected error): " ++ name)
  | Error(_) => Js.Console.log("PASS: " ++ name)
  }
}

let assertSome = (name: string, opt: option<'a>): unit => {
  switch opt {
  | Some(_) => Js.Console.log("PASS: " ++ name)
  | None => Js.Console.error("FAIL (expected Some): " ++ name)
  }
}

let assertNone = (name: string, opt: option<'a>): unit => {
  switch opt {
  | Some(_) => Js.Console.error("FAIL (expected None): " ++ name)
  | None => Js.Console.log("PASS: " ++ name)
  }
}

// ============================================================================
// Test: CONSUME AFTER N USE
// ============================================================================

let testConsumeAfter = (): unit => {
  Js.Console.log("\n--- CONSUME AFTER tests ---")

  // Parse valid CONSUME AFTER
  let r1 = TQLParser.parseExtensions("CONSUME AFTER 1 USE")
  assertOk("CONSUME AFTER 1 USE parses", r1)
  switch r1 {
  | Ok(ann) => assertSome("has consumeAfter", ann.consumeAfter)
  | Error(_) => ()
  }

  let r2 = TQLParser.parseExtensions("CONSUME AFTER 3 USE")
  assertOk("CONSUME AFTER 3 USE parses", r2)

  // Empty input (no extensions) should parse to empty annotations
  let r3 = TQLParser.parseExtensions("")
  assertOk("empty input parses", r3)
  switch r3 {
  | Ok(ann) => assertNone("empty has no consumeAfter", ann.consumeAfter)
  | Error(_) => ()
  }
}

// ============================================================================
// Test: WITH SESSION
// ============================================================================

let testWithSession = (): unit => {
  Js.Console.log("\n--- WITH SESSION tests ---")

  let r1 = TQLParser.parseExtensions("WITH SESSION ReadOnlyProtocol")
  assertOk("WITH SESSION ReadOnlyProtocol parses", r1)
  switch r1 {
  | Ok(ann) => assertSome("has sessionProtocol", ann.sessionProtocol)
  | Error(_) => ()
  }

  let r2 = TQLParser.parseExtensions("WITH SESSION MutationProtocol")
  assertOk("WITH SESSION MutationProtocol parses", r2)

  let r3 = TQLParser.parseExtensions("WITH SESSION MyCustomProto")
  assertOk("WITH SESSION custom protocol parses", r3)
}

// ============================================================================
// Test: EFFECTS { ... }
// ============================================================================

let testEffects = (): unit => {
  Js.Console.log("\n--- EFFECTS tests ---")

  let r1 = TQLParser.parseExtensions("EFFECTS { Read }")
  assertOk("EFFECTS { Read } parses", r1)
  switch r1 {
  | Ok(ann) => assertSome("has declaredEffects", ann.declaredEffects)
  | Error(_) => ()
  }

  let r2 = TQLParser.parseExtensions("EFFECTS { Read, Write, Cite }")
  assertOk("EFFECTS { Read, Write, Cite } parses", r2)

  let r3 = TQLParser.parseExtensions("EFFECTS { Read, Write, Cite, Audit, Transform, Federate }")
  assertOk("all standard effects parse", r3)
}

// ============================================================================
// Test: IN TRANSACTION
// ============================================================================

let testInTransaction = (): unit => {
  Js.Console.log("\n--- IN TRANSACTION tests ---")

  let r1 = TQLParser.parseExtensions("IN TRANSACTION Active")
  assertOk("IN TRANSACTION Active parses", r1)
  switch r1 {
  | Ok(ann) => assertSome("has modalScope", ann.modalScope)
  | Error(_) => ()
  }

  let r2 = TQLParser.parseExtensions("IN TRANSACTION Committed")
  assertOk("IN TRANSACTION Committed parses", r2)

  let r3 = TQLParser.parseExtensions("IN TRANSACTION ReadSnapshot")
  assertOk("IN TRANSACTION ReadSnapshot parses", r3)
}

// ============================================================================
// Test: PROOF ATTACHED
// ============================================================================

let testProofAttached = (): unit => {
  Js.Console.log("\n--- PROOF ATTACHED tests ---")

  let r1 = TQLParser.parseExtensions("PROOF ATTACHED IntegrityTheorem")
  assertOk("PROOF ATTACHED IntegrityTheorem parses", r1)
  switch r1 {
  | Ok(ann) => assertSome("has proofAttached", ann.proofAttached)
  | Error(_) => ()
  }

  let r2 = TQLParser.parseExtensions(`PROOF ATTACHED FreshnessGuarantee(maxAge="300")`)
  assertOk("PROOF ATTACHED with params parses", r2)
}

// ============================================================================
// Test: USAGE LIMIT
// ============================================================================

let testUsageLimit = (): unit => {
  Js.Console.log("\n--- USAGE LIMIT tests ---")

  let r1 = TQLParser.parseExtensions("USAGE LIMIT 100")
  assertOk("USAGE LIMIT 100 parses", r1)
  switch r1 {
  | Ok(ann) => assertSome("has usageLimit", ann.usageLimit)
  | Error(_) => ()
  }

  let r2 = TQLParser.parseExtensions("USAGE LIMIT 1")
  assertOk("USAGE LIMIT 1 parses", r2)
}

// ============================================================================
// Test: Combined (all 6 extensions)
// ============================================================================

let testCombined = (): unit => {
  Js.Console.log("\n--- Combined tests ---")

  let input = "CONSUME AFTER 1 USE WITH SESSION ReadOnlyProtocol EFFECTS { Read, Cite } IN TRANSACTION Committed PROOF ATTACHED IntegrityTheorem USAGE LIMIT 100"
  let r1 = TQLParser.parseExtensions(input)
  assertOk("maximal query parses", r1)
  switch r1 {
  | Ok(ann) => {
      assertSome("has consumeAfter", ann.consumeAfter)
      assertSome("has sessionProtocol", ann.sessionProtocol)
      assertSome("has declaredEffects", ann.declaredEffects)
      assertSome("has modalScope", ann.modalScope)
      assertSome("has proofAttached", ann.proofAttached)
      assertSome("has usageLimit", ann.usageLimit)
    }
  | Error(_) => ()
  }
}

// ============================================================================
// Test: Validation
// ============================================================================

let testValidation = (): unit => {
  Js.Console.log("\n--- Validation tests ---")

  // Valid: CONSUME AFTER 1 USE with USAGE LIMIT 100
  let r1 = TQLParser.parseAndValidateExtensions("CONSUME AFTER 1 USE USAGE LIMIT 100")
  assertOk("CONSUME 1 + USAGE 100 validates", r1)

  // Invalid: USAGE LIMIT < CONSUME AFTER
  let r2 = TQLParser.parseAndValidateExtensions("CONSUME AFTER 10 USE USAGE LIMIT 5")
  assertError("CONSUME 10 + USAGE 5 fails validation", r2)
}

// ============================================================================
// Run all tests
// ============================================================================

let () = {
  Js.Console.log("=== VQL-dt++ Parser Tests ===")
  testConsumeAfter()
  testWithSession()
  testEffects()
  testInTransaction()
  testProofAttached()
  testUsageLimit()
  testCombined()
  testValidation()
  Js.Console.log("\n=== Tests complete ===")
}
