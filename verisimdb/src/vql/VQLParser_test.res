// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Parser Tests

open VQLParser

// Test helper
let assertOk = (result: Result<'a, 'b>, testName: string) => {
  switch result {
  | Ok(_) => Js.Console.log(`✓ ${testName}`)
  | Error(e) => Js.Console.error(`✗ ${testName}: ${e.message}`)
  }
}

let assertError = (result: Result<'a, 'b>, testName: string) => {
  switch result {
  | Ok(_) => Js.Console.error(`✗ ${testName}: Expected error but got Ok`)
  | Error(_) => Js.Console.log(`✓ ${testName}`)
  }
}

// ============================================================================
// Test Suite
// ============================================================================

Js.Console.log("\n=== VQL Parser Tests ===\n")

// Test 1: Simple hexad query
let test1 = `
  SELECT *
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
`

assertOk(parseSlipstream(test1), "Test 1: Simple hexad query")

// Test 2: Federation query with drift policy
let test2 = `
  SELECT GRAPH, VECTOR
  FROM FEDERATION /universities/* WITH DRIFT REPAIR
`

assertOk(parseSlipstream(test2), "Test 2: Federation with drift policy")

// Test 3: Full-text search with LIMIT
let test3 = `
  SELECT DOCUMENT
  FROM STORE tantivy-node-1
  WHERE FULLTEXT CONTAINS "machine learning"
  LIMIT 100
`

assertOk(parseSlipstream(test3), "Test 3: Full-text search with LIMIT")

// Test 4: Vector similarity query
let test4 = `
  SELECT VECTOR
  FROM HEXAD abc12345-0000-0000-0000-000000000000
  WHERE h.embedding SIMILAR TO [0.1, 0.2, 0.3] WITHIN 0.9
`

assertOk(parseSlipstream(test4), "Test 4: Vector similarity query")

// Test 5: Multiple modalities
let test5 = `
  SELECT GRAPH, VECTOR, DOCUMENT
  FROM FEDERATION /research/*
  LIMIT 50
  OFFSET 100
`

assertOk(parseSlipstream(test5), "Test 5: Multiple modalities with pagination")

// Test 6: Dependent-type query (should have PROOF)
let test6 = `
  SELECT GRAPH
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  WHERE FULLTEXT CONTAINS "climate change"
  PROOF CITATION(CitationContract)
`

assertOk(parseDependentType(test6), "Test 6: Dependent-type with PROOF")

// Test 7: Slipstream with PROOF (should fail)
let test7 = `
  SELECT *
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  PROOF EXISTENCE(ExistenceContract)
`

assertError(parseSlipstream(test7), "Test 7: Slipstream rejects PROOF clause")

// Test 8: Dependent-type without PROOF (should fail)
let test8 = `
  SELECT GRAPH
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
`

assertError(parseDependentType(test8), "Test 8: Dependent-type requires PROOF")

// Test 9: Field condition
let test9 = `
  SELECT DOCUMENT
  FROM STORE archive-1
  WHERE FIELD year >= 2020
  LIMIT 10
`

assertOk(parseSlipstream(test9), "Test 9: Field condition with operator")

// Test 10: Multiple WHERE conditions (simplified - parser needs enhancement)
let test10 = `
  SELECT DOCUMENT
  FROM FEDERATION /archives/*
  WHERE FULLTEXT CONTAINS "quantum computing"
`

assertOk(parseSlipstream(test10), "Test 10: WHERE with FULLTEXT")

// Test 11: Complex dependent-type query
let test11 = `
  SELECT GRAPH, VECTOR, SEMANTIC
  FROM FEDERATION /universities/* WITH DRIFT STRICT
  WHERE h.embedding SIMILAR TO [0.5, 0.3, 0.2]
  PROOF INTEGRITY(DataIntegrityContract)
  LIMIT 100
`

assertOk(parseDependentType(test11), "Test 11: Complex dependent-type query")

// Test 12: All modalities
let test12 = `
  SELECT *
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  LIMIT 10
`

assertOk(parseSlipstream(test12), "Test 12: All modalities (wildcard)")

// Test 13: Store query
let test13 = `
  SELECT VECTOR
  FROM STORE milvus-us-east-1
  WHERE h.embedding SIMILAR TO [0.1, 0.2]
  LIMIT 20
`

assertOk(parseSlipstream(test13), "Test 13: Store-specific query")

// Test 14: PROOF with different types
let test14a = `SELECT * FROM HEXAD 550e8400-e29b-41d4-a716-446655440000 PROOF EXISTENCE(ExistenceContract)`
assertOk(parseDependentType(test14a), "Test 14a: EXISTENCE proof")

let test14b = `SELECT * FROM HEXAD 550e8400-e29b-41d4-a716-446655440000 PROOF ACCESS(AccessContract)`
assertOk(parseDependentType(test14b), "Test 14b: ACCESS proof")

let test14c = `SELECT * FROM HEXAD 550e8400-e29b-41d4-a716-446655440000 PROOF PROVENANCE(ProvenanceContract)`
assertOk(parseDependentType(test14c), "Test 14c: PROVENANCE proof")

// Test 15: Invalid UUID (should fail)
let test15 = `
  SELECT *
  FROM HEXAD not-a-valid-uuid
`

assertError(parse(test15), "Test 15: Invalid UUID format")

// Test 16: Missing FROM (should fail)
let test16 = `
  SELECT GRAPH
  WHERE FULLTEXT CONTAINS "test"
`

assertError(parse(test16), "Test 16: Missing FROM clause")

// Test 17: Drift policy variations
let test17a = `SELECT * FROM FEDERATION /nodes/* WITH DRIFT STRICT`
assertOk(parseSlipstream(test17a), "Test 17a: DRIFT STRICT")

let test17b = `SELECT * FROM FEDERATION /nodes/* WITH DRIFT REPAIR`
assertOk(parseSlipstream(test17b), "Test 17b: DRIFT REPAIR")

let test17c = `SELECT * FROM FEDERATION /nodes/* WITH DRIFT TOLERATE`
assertOk(parseSlipstream(test17c), "Test 17c: DRIFT TOLERATE")

let test17d = `SELECT * FROM FEDERATION /nodes/* WITH DRIFT LATEST`
assertOk(parseSlipstream(test17d), "Test 17d: DRIFT LATEST")

// ============================================================================
// SQL Compatibility Tests
// ============================================================================

Js.Console.log("\n=== SQL Compatibility Tests ===\n")

// Test 18: ORDER BY single field
let test18 = `
  SELECT DOCUMENT
  FROM STORE archive-1
  WHERE FULLTEXT CONTAINS "security"
  ORDER BY DOCUMENT.severity DESC
  LIMIT 50
`

assertOk(parseSlipstream(test18), "Test 18: ORDER BY single field DESC")

// Test 19: ORDER BY multiple fields
let test19 = `
  SELECT DOCUMENT
  FROM FEDERATION /archives/*
  ORDER BY DOCUMENT.severity DESC, DOCUMENT.name ASC
  LIMIT 100
`

assertOk(parseSlipstream(test19), "Test 19: ORDER BY multiple fields")

// Test 20: ORDER BY default direction (ASC)
let test20 = `
  SELECT DOCUMENT
  FROM STORE archive-1
  ORDER BY DOCUMENT.name
  LIMIT 10
`

assertOk(parseSlipstream(test20), "Test 20: ORDER BY default ASC direction")

// Test 21: Column projection (DOCUMENT.name, DOCUMENT.severity)
let test21 = `
  SELECT DOCUMENT.name, DOCUMENT.severity
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
`

assertOk(parseSlipstream(test21), "Test 21: Column projection within modality")

// Test 22: Mixed modalities and column projections
let test22 = `
  SELECT GRAPH, DOCUMENT.name, DOCUMENT.severity
  FROM FEDERATION /universities/*
  LIMIT 50
`

assertOk(parseSlipstream(test22), "Test 22: Mixed modalities and column projections")

// Test 23: COUNT(*) aggregate
let test23 = `
  SELECT COUNT(*)
  FROM FEDERATION /archives/*
  WHERE FULLTEXT CONTAINS "vulnerability"
`

assertOk(parseSlipstream(test23), "Test 23: COUNT(*) aggregate")

// Test 24: AVG aggregate with field ref
let test24 = `
  SELECT AVG(DOCUMENT.severity)
  FROM FEDERATION /scans/*
`

assertOk(parseSlipstream(test24), "Test 24: AVG(DOCUMENT.severity) aggregate")

// Test 25: GROUP BY with aggregate
let test25 = `
  SELECT DOCUMENT.name, COUNT(*), AVG(DOCUMENT.severity)
  FROM FEDERATION /universities/*
  GROUP BY DOCUMENT.name
  LIMIT 100
`

assertOk(parseSlipstream(test25), "Test 25: GROUP BY with aggregates")

// Test 26: GROUP BY + HAVING
let test26 = `
  SELECT DOCUMENT.name, COUNT(*)
  FROM FEDERATION /archives/*
  GROUP BY DOCUMENT.name
  HAVING FIELD count > 3
  ORDER BY DOCUMENT.name ASC
  LIMIT 50
`

assertOk(parseSlipstream(test26), "Test 26: GROUP BY + HAVING + ORDER BY")

// Test 27: Full SQL-compat query (all features combined)
let test27 = `
  SELECT DOCUMENT.name, DOCUMENT.severity, COUNT(*), SUM(DOCUMENT.severity), AVG(DOCUMENT.severity)
  FROM FEDERATION /universities/* WITH DRIFT REPAIR
  WHERE FIELD severity > 3
  GROUP BY DOCUMENT.name, DOCUMENT.severity
  HAVING FIELD total > 10
  ORDER BY DOCUMENT.severity DESC, DOCUMENT.name ASC
  LIMIT 100
  OFFSET 20
`

assertOk(parseSlipstream(test27), "Test 27: Full SQL-compat query (all features)")

// Test 28: MIN/MAX aggregates
let test28 = `
  SELECT MIN(DOCUMENT.severity), MAX(DOCUMENT.severity)
  FROM STORE tantivy-node-1
`

assertOk(parseSlipstream(test28), "Test 28: MIN/MAX aggregates")

// Test 29: SQL-compat with PROOF (dependent-type path)
let test29 = `
  SELECT DOCUMENT.name, COUNT(*)
  FROM FEDERATION /universities/* WITH DRIFT STRICT
  GROUP BY DOCUMENT.name
  PROOF INTEGRITY(DataIntegrityContract)
  ORDER BY DOCUMENT.name ASC
  LIMIT 50
`

assertOk(parseDependentType(test29), "Test 29: SQL-compat with PROOF clause")

// Test 30: Verify parsed projections are populated
switch parse(test21) {
| Ok(query) => {
    let hasProjections = query.projections->Belt.Option.isSome
    if hasProjections {
      Js.Console.log("✓ Test 30: Projections populated correctly")
    } else {
      Js.Console.error("✗ Test 30: Projections should be Some but got None")
    }
  }
| Error(e) => Js.Console.error(`✗ Test 30: Parse failed: ${e.message}`)
}

// Test 31: Verify ORDER BY parsed correctly
switch parse(test18) {
| Ok(query) => {
    let hasOrderBy = query.orderBy->Belt.Option.isSome
    if hasOrderBy {
      Js.Console.log("✓ Test 31: ORDER BY parsed correctly")
    } else {
      Js.Console.error("✗ Test 31: orderBy should be Some but got None")
    }
  }
| Error(e) => Js.Console.error(`✗ Test 31: Parse failed: ${e.message}`)
}

// Test 32: Verify GROUP BY parsed correctly
switch parse(test25) {
| Ok(query) => {
    let hasGroupBy = query.groupBy->Belt.Option.isSome
    let hasAggregates = query.aggregates->Belt.Option.isSome
    if hasGroupBy && hasAggregates {
      Js.Console.log("✓ Test 32: GROUP BY and aggregates parsed correctly")
    } else {
      Js.Console.error(`✗ Test 32: groupBy=${hasGroupBy->Belt.Bool.toString}, aggregates=${hasAggregates->Belt.Bool.toString}`)
    }
  }
| Error(e) => Js.Console.error(`✗ Test 32: Parse failed: ${e.message}`)
}

Js.Console.log("\n=== Multi-Proof Tests ===\n")

// Test 33: Multi-proof composition (AND separated)
let test33 = `
  SELECT GRAPH, SEMANTIC
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  PROOF EXISTENCE(ExistenceContract) AND INTEGRITY(IntegrityContract)
`

assertOk(parseDependentType(test33), "Test 33: Multi-proof (EXISTENCE AND INTEGRITY)")

// Test 34: Triple proof composition
let test34 = `
  SELECT *
  FROM FEDERATION /hospitals/* WITH DRIFT STRICT
  PROOF ACCESS(AccessContract) AND PROVENANCE(ProvenanceContract) AND INTEGRITY(IntegrityContract)
`

assertOk(parseDependentType(test34), "Test 34: Triple proof composition")

// Test 35: Verify multi-proof parsed as array
switch parse(test33) {
| Ok(query) => {
    switch query.proof {
    | Some(proofs) =>
      if Js.Array2.length(proofs) == 2 {
        Js.Console.log("✓ Test 35: Multi-proof parsed as array of 2")
      } else {
        Js.Console.error(`✗ Test 35: Expected 2 proofs, got ${Belt.Int.toString(Js.Array2.length(proofs))}`)
      }
    | None => Js.Console.error("✗ Test 35: Proof should be Some but got None")
    }
  }
| Error(e) => Js.Console.error(`✗ Test 35: Parse failed: ${e.message}`)
}

Js.Console.log("\n=== Cross-Modal Condition Tests ===\n")

// Test 36: DRIFT condition
let test36 = `
  SELECT VECTOR, DOCUMENT
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  WHERE DRIFT(VECTOR, DOCUMENT) > 0.3
`

assertOk(parseSlipstream(test36), "Test 36: DRIFT(VECTOR, DOCUMENT) condition")

// Test 37: CONSISTENT condition
let test37 = `
  SELECT VECTOR, SEMANTIC
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  WHERE CONSISTENT(VECTOR, SEMANTIC) USING COSINE
`

assertOk(parseSlipstream(test37), "Test 37: CONSISTENT(VECTOR, SEMANTIC) USING COSINE")

// Test 38: EXISTS condition
let test38 = `
  SELECT *
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  WHERE VECTOR EXISTS
`

assertOk(parseSlipstream(test38), "Test 38: VECTOR EXISTS condition")

// Test 39: NOT EXISTS condition
let test39 = `
  SELECT *
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  WHERE TENSOR NOT EXISTS
`

assertOk(parseSlipstream(test39), "Test 39: TENSOR NOT EXISTS condition")

// Test 40: Cross-modal field compare
let test40 = `
  SELECT DOCUMENT, GRAPH
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  WHERE DOCUMENT.severity > GRAPH.centrality
`

assertOk(parseSlipstream(test40), "Test 40: Cross-modal field compare")

Js.Console.log("\n=== Mutation Tests ===\n")

// Test 41: INSERT mutation
let test41 = `
  INSERT HEXAD WITH
    DOCUMENT(title = "New Paper", author = "Jane Doe"),
    VECTOR([0.1, 0.2, 0.3, 0.4])
`

assertOk(parseMutation(test41), "Test 41: INSERT HEXAD with DOCUMENT and VECTOR")

// Test 42: UPDATE mutation
let test42 = `
  UPDATE HEXAD 550e8400-e29b-41d4-a716-446655440000
  SET DOCUMENT.title = "Updated Title", DOCUMENT.severity = 5
`

assertOk(parseMutation(test42), "Test 42: UPDATE HEXAD with SET")

// Test 43: DELETE mutation
let test43 = `
  DELETE HEXAD 550e8400-e29b-41d4-a716-446655440000
`

assertOk(parseMutation(test43), "Test 43: DELETE HEXAD")

// Test 44: INSERT with PROOF
let test44 = `
  INSERT HEXAD WITH
    DOCUMENT(title = "Verified Entry")
  PROOF INTEGRITY(WriteContract)
`

assertOk(parseMutation(test44), "Test 44: INSERT with PROOF clause")

// Test 45: DELETE with multi-proof
let test45 = `
  DELETE HEXAD 550e8400-e29b-41d4-a716-446655440000
  PROOF ACCESS(AccessContract) AND PROVENANCE(AuditContract)
`

assertOk(parseMutation(test45), "Test 45: DELETE with multi-proof")

Js.Console.log("\n=== Statement Tests ===\n")

// Test 46: parseStatement with query
let test46 = `
  SELECT GRAPH
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  LIMIT 10
`

assertOk(parseStatement(test46), "Test 46: parseStatement dispatches to query")

// Test 47: parseStatement with mutation
let test47 = `
  DELETE HEXAD 550e8400-e29b-41d4-a716-446655440000
`

assertOk(parseStatement(test47), "Test 47: parseStatement dispatches to mutation")

// Test 48: parseStatement with INSERT
let test48 = `
  INSERT HEXAD WITH DOCUMENT(title = "Test")
`

assertOk(parseStatement(test48), "Test 48: parseStatement dispatches INSERT to mutation")

Js.Console.log("\n=== Tests Complete ===\n")

// ============================================================================
// Example: Extracting parsed data
// ============================================================================

Js.Console.log("=== Example: Parsing and Inspecting Query ===\n")

let exampleQuery = `
  SELECT GRAPH, VECTOR
  FROM FEDERATION /universities/* WITH DRIFT REPAIR
  WHERE FULLTEXT CONTAINS "neural networks"
  PROOF CITATION(NeuralNetworkContract)
  LIMIT 50
`

switch parseDependentType(exampleQuery) {
| Ok(query) => {
    Js.Console.log("Parsed query successfully:")
    Js.Console.log(`  Modalities: ${query.modalities->Js.Array2.length->Belt.Int.toString}`)
    Js.Console.log(`  Source: ${switch query.source {
      | Hexad(id) => `Hexad(${id})`
      | Federation(pattern, drift) => {
          let driftStr = switch drift {
          | Some(Strict) => " WITH DRIFT STRICT"
          | Some(Repair) => " WITH DRIFT REPAIR"
          | Some(Tolerate) => " WITH DRIFT TOLERATE"
          | Some(Latest) => " WITH DRIFT LATEST"
          | None => ""
          }
          `Federation(${pattern}${driftStr})`
        }
      | Store(id) => `Store(${id})`
      }}`)
    Js.Console.log(`  Has WHERE: ${query.where->Belt.Option.isSome->Belt.Bool.toString}`)
    Js.Console.log(`  Has PROOF: ${query.proof->Belt.Option.isSome->Belt.Bool.toString}`)
    switch query.proof {
    | Some(proofs) =>
      proofs->Js.Array2.forEach(proof => {
        Js.Console.log(`    Proof contract: ${proof.contractName}`)
      })
    | None => ()
    }
    Js.Console.log(`  Limit: ${switch query.limit {
      | Some(n) => Belt.Int.toString(n)
      | None => "None"
    }}`)
  }
| Error(e) => {
    Js.Console.error(`Parse error: ${e.message}`)
  }
}

Js.Console.log("\n")
