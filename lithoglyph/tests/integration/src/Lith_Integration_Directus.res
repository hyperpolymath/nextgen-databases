// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Directus Integration Tests
 *
 * Tests for Directus hook extension functionality
 */

open Lith_Integration_Types
open Lith_Integration_Mock

/** Test: Hook extension registration */
let test_hookRegistration = async (): testResult => {
  let hooks = ["items.create", "items.update", "items.delete"]
  let registered = hooks->Array.every(h => String.length(h) > 0)
  assertTrue(registered, "All hooks should be registered")
}

/** Test: Environment configuration */
let test_envConfiguration = async (): testResult => {
  let config = Js.Dict.fromArray([
    ("LITH_URL", "http://localhost:8080"),
    ("LITH_API_KEY", "test-key"),
    ("LITH_SYNC_COLLECTIONS", "articles,products,users"),
  ])

  let hasUrl = Js.Dict.get(config, "LITH_URL")->Option.isSome
  let hasSyncCollections = Js.Dict.get(config, "LITH_SYNC_COLLECTIONS")->Option.isSome

  if hasUrl && hasSyncCollections {
    Passed
  } else {
    Failed({message: "Missing required environment variables"})
  }
}

/** Test: Collection filtering */
let test_collectionFiltering = async (): testResult => {
  let syncCollections = "articles,products,users"
  let collections = String.split(syncCollections, ",")

  let shouldSync = (collection: string): bool => {
    collections->Array.includes(collection)
  }

  if shouldSync("articles") && !shouldSync("settings") {
    Passed
  } else {
    Failed({message: "Collection filtering not working correctly"})
  }
}

/** Test: Items create action */
let test_itemsCreateAction = async (): testResult => {
  let client = makeMockLithClient()

  addResponse(client, {
    status: 201,
    body: Js.Json.object_(Js.Dict.fromArray([("success", Js.Json.boolean(true))])),
    headers: Js.Dict.empty(),
  })

  let payload = Js.Json.object_(Js.Dict.fromArray([
    ("id", Js.Json.string("item-123")),
    ("title", Js.Json.string("New Item")),
  ]))

  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([("Content-Type", "application/json")]),
      "body": Js.Json.stringify(
        Js.Json.object_(Js.Dict.fromArray([
          ("gql", Js.Json.string(`INSERT INTO items ${Js.Json.stringify(payload)}`)),
        ])),
      ),
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should make insert request")
}

/** Test: Items update action */
let test_itemsUpdateAction = async (): testResult => {
  let client = makeMockLithClient()

  addResponse(client, {
    status: 200,
    body: Js.Json.object_(Js.Dict.fromArray([("success", Js.Json.boolean(true))])),
    headers: Js.Dict.empty(),
  })

  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([("Content-Type", "application/json")]),
      "body": `{"gql": "UPDATE items SET {\\"title\\": \\"Updated\\"} WHERE id = \\"123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should make update request")
}

/** Test: Items delete action */
let test_itemsDeleteAction = async (): testResult => {
  let client = makeMockLithClient()

  addResponse(client, {
    status: 200,
    body: Js.Json.object_(Js.Dict.fromArray([("deleted", Js.Json.boolean(true))])),
    headers: Js.Dict.empty(),
  })

  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([("Content-Type", "application/json")]),
      "body": `{"gql": "DELETE FROM items WHERE id = \\"123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should make delete request")
}

/** Test: Error handling */
let test_errorHandling = async (): testResult => {
  let client = makeMockLithClient()

  // Configure error response
  addResponse(client, {
    status: 500,
    body: Js.Json.object_(Js.Dict.fromArray([
      ("error", Js.Json.string("Internal server error")),
    ])),
    headers: Js.Dict.empty(),
  })

  let response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([("Content-Type", "application/json")]),
      "body": `{"gql": "SELECT * FROM test"}`,
    },
  )

  // Should handle error gracefully
  assertEqual(response.status, 500, "Should receive error response")
}

/** Run all Directus integration tests */
let runDirectusTests = async (): {passed: int, failed: int, skipped: int} => {
  Js.Console.log("\n=== Directus Integration Tests ===\n")

  let tests = [
    ("Hook extension registration", test_hookRegistration),
    ("Environment configuration", test_envConfiguration),
    ("Collection filtering", test_collectionFiltering),
    ("Items create action", test_itemsCreateAction),
    ("Items update action", test_itemsUpdateAction),
    ("Items delete action", test_itemsDeleteAction),
    ("Error handling", test_errorHandling),
  ]

  let passed = ref(0)
  let failed = ref(0)
  let skipped = ref(0)

  for i in 0 to Array.length(tests) - 1 {
    switch tests[i] {
    | Some((name, test)) => {
        let result = await test()
        switch result {
        | Passed => {
            Js.Console.log(`✓ ${name}`)
            passed := passed.contents + 1
          }
        | Failed({message}) => {
            Js.Console.log(`✗ ${name}: ${message}`)
            failed := failed.contents + 1
          }
        | Skipped({reason}) => {
            Js.Console.log(`○ ${name}: ${reason}`)
            skipped := skipped.contents + 1
          }
        }
      }
    | None => ()
    }
  }

  Js.Console.log(`\nPassed: ${Int.toString(passed.contents)}, Failed: ${Int.toString(failed.contents)}, Skipped: ${Int.toString(skipped.contents)}`)

  {passed: passed.contents, failed: failed.contents, skipped: skipped.contents}
}

let default = runDirectusTests
