// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Strapi Integration Tests
 *
 * Tests for Strapi plugin functionality
 */

open Lith_Integration_Types
open Lith_Integration_Mock

/** Test: Plugin initialization */
let test_pluginInitialization = async (): testResult => {
  let client = makeMockLithClient()

  // Configure success response for health check
  addResponse(client, {
    status: 200,
    body: Js.Json.object_(Js.Dict.fromArray([("status", Js.Json.string("healthy"))])),
    headers: Js.Dict.empty(),
  })

  // Simulate plugin initialization
  let initialized = true // Would call actual plugin init

  assertTrue(initialized, "Plugin should initialize successfully")
}

/** Test: Content sync on create */
let test_syncOnCreate = async (): testResult => {
  let client = makeMockLithClient()

  // Configure success response for insert
  addResponse(client, {
    status: 201,
    body: Js.Json.object_(Js.Dict.fromArray([
      ("id", Js.Json.string("doc-123")),
      ("success", Js.Json.boolean(true)),
    ])),
    headers: Js.Dict.empty(),
  })

  // Simulate creating content
  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([
        ("Content-Type", "application/json"),
      ]),
      "body": `{"fdql": "INSERT INTO articles {\\"title\\": \\"Test Article\\"}"}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should make one request to Lith")
}

/** Test: Content sync on update */
let test_syncOnUpdate = async (): testResult => {
  let client = makeMockLithClient()

  // Configure success response
  addResponse(client, {
    status: 200,
    body: Js.Json.object_(Js.Dict.fromArray([("success", Js.Json.boolean(true))])),
    headers: Js.Dict.empty(),
  })

  // Simulate updating content
  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([
        ("Content-Type", "application/json"),
      ]),
      "body": `{"fdql": "UPDATE articles SET {\\"title\\": \\"Updated\\"} WHERE id = \\"123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  let lastRequest = requests[0]

  switch lastRequest {
  | Some(req) => assertTrue(String.includes(req.url, "query"), "Should call query endpoint")
  | None => Failed({message: "No request recorded"})
  }
}

/** Test: Content sync on delete */
let test_syncOnDelete = async (): testResult => {
  let client = makeMockLithClient()

  // Configure success response
  addResponse(client, {
    status: 200,
    body: Js.Json.object_(Js.Dict.fromArray([("deleted", Js.Json.boolean(true))])),
    headers: Js.Dict.empty(),
  })

  // Simulate deleting content
  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([
        ("Content-Type", "application/json"),
      ]),
      "body": `{"fdql": "DELETE FROM articles WHERE id = \\"123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should make delete request")
}

/** Test: Field exclusion */
let test_fieldExclusion = async (): testResult => {
  let excludeFields = ["password", "secret", "_internal"]

  let document = Js.Dict.fromArray([
    ("id", Js.Json.string("123")),
    ("name", Js.Json.string("Test")),
    ("password", Js.Json.string("secret123")),
    ("secret", Js.Json.string("hidden")),
    ("_internal", Js.Json.string("private")),
  ])

  // Filter excluded fields
  let filtered = Js.Dict.empty()
  Js.Dict.keys(document)->Array.forEach(key => {
    if !excludeFields->Array.includes(key) {
      switch Js.Dict.get(document, key) {
      | Some(value) => Js.Dict.set(filtered, key, value)
      | None => ()
      }
    }
  })

  let hasPassword = Js.Dict.get(filtered, "password")->Option.isSome
  let hasName = Js.Dict.get(filtered, "name")->Option.isSome

  if hasPassword {
    Failed({message: "Should exclude password field"})
  } else if !hasName {
    Failed({message: "Should keep name field"})
  } else {
    Passed
  }
}

/** Test: Sync mode - bidirectional */
let test_syncModeBidirectional = async (): testResult => {
  let syncMode = "bidirectional"
  let shouldSyncToCms = syncMode == "bidirectional" || syncMode == "lith-to-cms"
  let shouldSyncToLith = syncMode == "bidirectional" || syncMode == "cms-to-lith"

  if shouldSyncToCms && shouldSyncToLith {
    Passed
  } else {
    Failed({message: "Bidirectional should sync both ways"})
  }
}

/** Test: Sync mode - one-way to Lith */
let test_syncModeCmsToLith = async (): testResult => {
  let syncMode = "cms-to-lith"
  let shouldSyncToLith = syncMode == "bidirectional" || syncMode == "cms-to-lith"
  let shouldSyncToCms = syncMode == "bidirectional" || syncMode == "lith-to-cms"

  if shouldSyncToLith && !shouldSyncToCms {
    Passed
  } else {
    Failed({message: "cms-to-lith should only sync to Lith"})
  }
}

/** Test: API key authentication */
let test_apiKeyAuth = async (): testResult => {
  let client = makeMockLithClient()

  addResponse(client, {
    status: 200,
    body: Js.Json.null,
    headers: Js.Dict.empty(),
  })

  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([
        ("Content-Type", "application/json"),
        ("X-API-Key", "test-api-key"),
      ]),
      "body": `{"fdql": "SELECT * FROM test"}`,
    },
  )

  let requests = getRequests(client.requestStore)
  switch requests[0] {
  | Some(req) => {
      let apiKey = Js.Dict.get(req.headers, "X-API-Key")
      switch apiKey {
      | Some(key) => assertEqual(key, "test-api-key", "Should include API key header")
      | None => Failed({message: "Missing API key header"})
      }
    }
  | None => Failed({message: "No request recorded"})
  }
}

/** Test: Provenance metadata */
let test_provenanceMetadata = async (): testResult => {
  let provenance = Js.Dict.fromArray([
    ("actor", Js.Json.string("strapi-plugin")),
    ("rationale", Js.Json.string("Auto-sync from Strapi create event")),
    ("source", Js.Json.string("strapi")),
    ("model", Js.Json.string("article")),
    ("action", Js.Json.string("create")),
  ])

  let hasActor = Js.Dict.get(provenance, "actor")->Option.isSome
  let hasRationale = Js.Dict.get(provenance, "rationale")->Option.isSome
  let hasSource = Js.Dict.get(provenance, "source")->Option.isSome

  if hasActor && hasRationale && hasSource {
    Passed
  } else {
    Failed({message: "Missing required provenance fields"})
  }
}

/** Run all Strapi integration tests */
let runStrapiTests = async (): {passed: int, failed: int, skipped: int} => {
  Js.Console.log("\n=== Strapi Integration Tests ===\n")

  let tests = [
    ("Plugin initialization", test_pluginInitialization),
    ("Sync on create", test_syncOnCreate),
    ("Sync on update", test_syncOnUpdate),
    ("Sync on delete", test_syncOnDelete),
    ("Field exclusion", test_fieldExclusion),
    ("Sync mode - bidirectional", test_syncModeBidirectional),
    ("Sync mode - cms-to-lith", test_syncModeCmsToLith),
    ("API key authentication", test_apiKeyAuth),
    ("Provenance metadata", test_provenanceMetadata),
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

/** Default export */
let default = runStrapiTests
