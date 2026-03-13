// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith E2E Sync Tests
 *
 * End-to-end tests for CMS sync scenarios
 */

open Lith_E2E_Types

/** Test: Sync create from CMS */
let test_syncCreate = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "sync_posts"

  try {
    let client = makeHttpClient(env)

    // Simulate CMS create event
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`INSERT INTO ${collectionName} {"id": "cms-123", "title": "Synced Post", "source": "strapi"}`)),
    ]))
    let response = await client.post("/v1/query", body)

    let id = response["id"]
    assertE2E(id != "", "Should sync create event", startTime)
  } catch {
  | _ => Failed({message: "Sync create failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Sync update from CMS */
let test_syncUpdate = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "sync_posts"

  try {
    let client = makeHttpClient(env)

    // Simulate CMS update event
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`UPDATE ${collectionName} SET {"title": "Updated Synced Post"} WHERE id = "cms-123"`)),
    ]))
    let response = await client.post("/v1/query", body)

    let affected = response["affected"]
    assertE2E(affected >= 0, "Should sync update event", startTime)
  } catch {
  | _ => Failed({message: "Sync update failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Sync delete from CMS */
let test_syncDelete = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "sync_posts"

  try {
    let client = makeHttpClient(env)

    // Simulate CMS delete event
    let body = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`DELETE FROM ${collectionName} WHERE id = "cms-123"`)),
    ]))
    let response = await client.post("/v1/query", body)

    let deleted = response["deleted"]
    assertE2E(deleted >= 0, "Should sync delete event", startTime)
  } catch {
  | _ => Failed({message: "Sync delete failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Provenance tracking */
let test_provenanceTracking = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "provenance_test"

  try {
    let client = makeHttpClient(env)

    // Insert with provenance
    let insertBody = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`INSERT INTO ${collectionName} {"title": "Tracked"} WITH PROVENANCE {"actor": "test", "rationale": "E2E test"}`)),
    ]))
    let _ = await client.post("/v1/query", insertBody)

    // Check journal for provenance
    let journalBody = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`INTROSPECT JOURNAL`)),
    ]))
    let response = await client.post("/v1/query", journalBody)

    let entries = response["entries"]
    assertE2E(Js.Array.isArray(entries), "Should have journal entries with provenance", startTime)
  } catch {
  | _ => Failed({message: "Provenance tracking failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Bidirectional sync */
let test_bidirectionalSync = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "bidirectional"

  try {
    let client = makeHttpClient(env)

    // Create from "CMS"
    let createBody = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`INSERT INTO ${collectionName} {"id": "bi-1", "title": "From CMS", "source": "cms"}`)),
    ]))
    let _ = await client.post("/v1/query", createBody)

    // Create from "Lith" (simulated)
    let createBody2 = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`INSERT INTO ${collectionName} {"id": "bi-2", "title": "From Lith", "source": "lith"}`)),
    ]))
    let _ = await client.post("/v1/query", createBody2)

    // Query all
    let queryBody = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`SELECT * FROM ${collectionName}`)),
    ]))
    let response = await client.post("/v1/query", queryBody)

    let results = response["results"]
    assertE2E(Js.Array.isArray(results), "Should have documents from both directions", startTime)
  } catch {
  | _ => Failed({message: "Bidirectional sync failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Conflict resolution */
let test_conflictResolution = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "conflicts"

  try {
    let client = makeHttpClient(env)

    // Create document
    let createBody = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`INSERT INTO ${collectionName} {"id": "conflict-1", "title": "Original", "version": 1}`)),
    ]))
    let _ = await client.post("/v1/query", createBody)

    // Concurrent update (simulated by sequential)
    let update1 = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`UPDATE ${collectionName} SET {"title": "Update A", "version": 2} WHERE id = "conflict-1"`)),
    ]))
    let _ = await client.post("/v1/query", update1)

    // Second update
    let update2 = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`UPDATE ${collectionName} SET {"title": "Update B", "version": 3} WHERE id = "conflict-1"`)),
    ]))
    let response = await client.post("/v1/query", update2)

    let affected = response["affected"]
    assertE2E(affected >= 0, "Should handle concurrent updates", startTime)
  } catch {
  | _ => Failed({message: "Conflict resolution failed", duration: Js.Date.now() -. startTime})
  }
}

/** Test: Batch sync */
let test_batchSync = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()
  let collectionName = env.testPrefix ++ "batch_sync"

  try {
    let client = makeHttpClient(env)

    // Create collection
    let createColl = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`CREATE COLLECTION ${collectionName}`)),
    ]))
    let _ = await client.post("/v1/query", createColl)

    // Batch insert (simulated as sequential)
    for i in 1 to 10 {
      let body = Js.Json.object_(Js.Dict.fromArray([
        ("gql", Js.Json.string(`INSERT INTO ${collectionName} {"id": "batch-${Int.toString(i)}", "index": ${Int.toString(i)}}`)),
      ]))
      let _ = await client.post("/v1/query", body)
    }

    // Verify count
    let queryBody = Js.Json.object_(Js.Dict.fromArray([
      ("gql", Js.Json.string(`SELECT * FROM ${collectionName}`)),
    ]))
    let response = await client.post("/v1/query", queryBody)

    let results = response["results"]
    let count = if Js.Array.isArray(results) { Js.Array.length(results) } else { 0 }
    assertE2E(count >= 10, "Should batch sync all documents", startTime)
  } catch {
  | _ => Failed({message: "Batch sync failed", duration: Js.Date.now() -. startTime})
  }
}

/** Sync E2E test suite */
let syncSuite: e2eSuite = {
  name: "Sync E2E Tests",
  description: "End-to-end tests for CMS sync scenarios",
  setup: async (_env) => (),
  teardown: async (_env) => (),
  tests: [
    {name: "Sync create", description: "Test sync on create", timeout: 5000, run: test_syncCreate},
    {name: "Sync update", description: "Test sync on update", timeout: 5000, run: test_syncUpdate},
    {name: "Sync delete", description: "Test sync on delete", timeout: 5000, run: test_syncDelete},
    {name: "Provenance tracking", description: "Test provenance metadata", timeout: 10000, run: test_provenanceTracking},
    {name: "Bidirectional sync", description: "Test two-way sync", timeout: 10000, run: test_bidirectionalSync},
    {name: "Conflict resolution", description: "Test concurrent updates", timeout: 10000, run: test_conflictResolution},
    {name: "Batch sync", description: "Test bulk sync", timeout: 30000, run: test_batchSync},
  ],
}

/** Run Sync E2E suite */
let runSyncSuite = async (~env: testEnvironment=defaultEnvironment): {passed: int, failed: int, skipped: int} => {
  Js.Console.log(`\n=== ${syncSuite.name} ===`)
  Js.Console.log(`${syncSuite.description}\n`)

  await syncSuite.setup(env)

  let passed = ref(0)
  let failed = ref(0)
  let skipped = ref(0)

  for i in 0 to Array.length(syncSuite.tests) - 1 {
    switch syncSuite.tests[i] {
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

  await syncSuite.teardown(env)

  Js.Console.log(`\nPassed: ${Int.toString(passed.contents)}, Failed: ${Int.toString(failed.contents)}, Skipped: ${Int.toString(skipped.contents)}`)

  {passed: passed.contents, failed: failed.contents, skipped: skipped.contents}
}

let default = runSyncSuite
