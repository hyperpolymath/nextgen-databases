// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith E2E API Tests
 *
 * End-to-end tests for the Lith REST API
 */

open Lith_E2E_Types

/** Test: Health check endpoint */
let test_healthCheck = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()

  try {
    let client = makeHttpClient(env)
    let response = await client.get("/health")

    let status = response["status"]
    assertE2E(status == "healthy", "Health check should return healthy status", startTime)
  } catch {
  | _ => Failed({message: "Health check request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Create collection */
let test_createCollection = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`CREATE COLLECTION ${collectionName}`)),
    ]))
    let response = await client.post("/v1/query", body)

    let success = response["success"]
    assertE2E(success == true, "Should create collection successfully", startTime)
  } catch {
  | _ => Failed({message: "Create collection request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Insert document */
let test_insertDocument = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`INSERT INTO ${collectionName} {"title": "Test Article", "status": "draft"}`)),
    ]))
    let response = await client.post("/v1/query", body)

    let id = response["id"]
    assertE2E(id != "", "Should return document ID", startTime)
  } catch {
  | _ => Failed({message: "Insert document request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Select documents */
let test_selectDocuments = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`SELECT * FROM ${collectionName}`)),
    ]))
    let response = await client.post("/v1/query", body)

    let results = response["results"]
    assertE2E(Js.Array.isArray(results), "Should return array of results", startTime)
  } catch {
  | _ => Failed({message: "Select documents request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Update document */
let test_updateDocument = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`UPDATE ${collectionName} SET {"status": "published"} WHERE status = "draft"`)),
    ]))
    let response = await client.post("/v1/query", body)

    let affected = response["affected"]
    assertE2E(affected >= 0, "Should return affected count", startTime)
  } catch {
  | _ => Failed({message: "Update document request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Delete document */
let test_deleteDocument = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`DELETE FROM ${collectionName} WHERE status = "published"`)),
    ]))
    let response = await client.post("/v1/query", body)

    let deleted = response["deleted"]
    assertE2E(deleted >= 0, "Should return deleted count", startTime)
  } catch {
  | _ => Failed({message: "Delete document request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Query with WHERE clause */
let test_queryWithWhere = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`SELECT title, status FROM ${collectionName} WHERE status = "draft" LIMIT 10`)),
    ]))
    let response = await client.post("/v1/query", body)

    let results = response["results"]
    assertE2E(Js.Array.isArray(results), "Should return filtered results", startTime)
  } catch {
  | _ => Failed({message: "Query with WHERE request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: EXPLAIN query */
let test_explainQuery = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`EXPLAIN SELECT * FROM ${collectionName}`)),
    ]))
    let response = await client.post("/v1/query", body)

    let plan = response["plan"]
    assertE2E(plan != Js.Nullable.undefined, "Should return query plan", startTime)
  } catch {
  | _ => Failed({message: "EXPLAIN request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: INTROSPECT schema */
let test_introspectSchema = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`INTROSPECT SCHEMA ${collectionName}`)),
    ]))
    let response = await client.post("/v1/query", body)

    let schema = response["schema"]
    assertE2E(schema != Js.Nullable.undefined, "Should return schema", startTime)
  } catch {
  | _ => Failed({message: "INTROSPECT request failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Drop collection */
let test_dropCollection = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "articles"

  try {
    let client = makeHttpClient(env)
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("fdql", Js.Json.string(`DROP COLLECTION ${collectionName}`)),
    ]))
    let response = await client.post("/v1/query", body)

    let success = response["success"]
    assertE2E(success == true, "Should drop collection successfully", startTime)
  } catch {
  | _ => Failed({message: "Drop collection request failed", duration: Js.Date.now() -. startTime})
  }
}

/** API E2E test suite */
let apiSuite: e2eSuite = {
  name: "API E2E Tests",
  description: "End-to-end tests for Lith REST API",
  setup: async (_env) => (),
  teardown: async (_env) => (),
  tests: [
    {name: "Health check", description: "Test health endpoint", timeout: 5000, run: test_healthCheck},
    {name: "Create collection", description: "Test collection creation", timeout: 5000, run: test_createCollection},
    {name: "Insert document", description: "Test document insertion", timeout: 5000, run: test_insertDocument},
    {name: "Select documents", description: "Test document retrieval", timeout: 5000, run: test_selectDocuments},
    {name: "Update document", description: "Test document update", timeout: 5000, run: test_updateDocument},
    {name: "Query with WHERE", description: "Test filtered queries", timeout: 5000, run: test_queryWithWhere},
    {name: "EXPLAIN query", description: "Test query explanation", timeout: 5000, run: test_explainQuery},
    {name: "INTROSPECT schema", description: "Test schema introspection", timeout: 5000, run: test_introspectSchema},
    {name: "Delete document", description: "Test document deletion", timeout: 5000, run: test_deleteDocument},
    {name: "Drop collection", description: "Test collection removal", timeout: 5000, run: test_dropCollection},
  ],
}

/** Run API E2E suite */
let runAPISuite = async (~env: testEnvironment=defaultEnvironment): {passed: int, failed: int, skipped: int} => {
  Js.Console.log(`\n=== ${apiSuite.name} ===`)
  Js.Console.log(`${apiSuite.description}\n`)

  await apiSuite.setup(env)

  let passed = ref(0)
  let failed = ref(0)
  let skipped = ref(0)

  for i in 0 to Array.length(apiSuite.tests) - 1 {
    switch apiSuite.tests[i] {
    | Some(test) => {
        let result = await test.run(env)
        switch result {
        | Passed({duration}) => {
            Js.Console.log(`✓ ${test.name} (${Float.toFixedWithPrecision(duration, ~digits=0)}ms)`)
            passed := passed.contents + 1
          }
        | Failed({message, duration}) => {
            Js.Console.log(`✗ ${test.name}: ${message} (${Float.toFixedWithPrecision(duration, ~digits=0)}ms)`)
            failed := failed.contents + 1
          }
        | Skipped({reason}) => {
            Js.Console.log(`○ ${test.name}: ${reason}`)
            skipped := skipped.contents + 1
          }
        | Timeout({duration}) => {
            Js.Console.log(`⏱ ${test.name}: Timeout (${Float.toFixedWithPrecision(duration, ~digits=0)}ms)`)
            failed := failed.contents + 1
          }
        }
      }
    | None => ()
    }
  }

  await apiSuite.teardown(env)

  Js.Console.log(`\nPassed: ${Int.toString(passed.contents)}, Failed: ${Int.toString(failed.contents)}, Skipped: ${Int.toString(skipped.contents)}`)

  {passed: passed.contents, failed: failed.contents, skipped: skipped.contents}
}

let default = runAPISuite
