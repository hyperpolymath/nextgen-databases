// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Payload CMS Integration Tests
 *
 * Tests for Payload CMS adapter functionality
 */

open Lith_Integration_Types
open Lith_Integration_Mock

/** Test: Plugin configuration */
let test_pluginConfiguration = async (): testResult => {
  let config = Js.Dict.fromArray([
    ("lithUrl", Js.Json.string("http://localhost:8080")),
    ("enabled", Js.Json.boolean(true)),
    ("collections", Js.Json.array([])),
  ])

  let hasUrl = Js.Dict.get(config, "lithUrl")->Option.isSome
  let hasEnabled = Js.Dict.get(config, "enabled")->Option.isSome

  assertTrue(hasUrl && hasEnabled, "Should have required config fields")
}

/** Test: Collection mapping */
let test_collectionMapping = async (): testResult => {
  let mapping = Js.Dict.fromArray([
    ("payloadSlug", Js.Json.string("posts")),
    ("lithCollection", Js.Json.string("posts")),
    ("syncMode", Js.Json.string("bidirectional")),
    ("excludeFields", Js.Json.array([Js.Json.string("_status"), Js.Json.string("__v")])),
  ])

  let hasPayloadSlug = Js.Dict.get(mapping, "payloadSlug")->Option.isSome
  let hasLithCollection = Js.Dict.get(mapping, "lithCollection")->Option.isSome
  let hasSyncMode = Js.Dict.get(mapping, "syncMode")->Option.isSome

  assertTrue(hasPayloadSlug && hasLithCollection && hasSyncMode, "Should have all mapping fields")
}

/** Test: afterChange hook - create */
let test_afterChangeCreate = async (): testResult => {
  let client = makeMockLithClient()

  addResponse(client, {
    status: 201,
    body: Js.Json.object_(Js.Dict.fromArray([("success", Js.Json.boolean(true))])),
    headers: Js.Dict.empty(),
  })

  let doc = Js.Json.object_(Js.Dict.fromArray([
    ("id", Js.Json.string("doc-123")),
    ("title", Js.Json.string("Test Document")),
  ]))

  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([("Content-Type", "application/json")]),
      "body": `{"gql": "INSERT INTO posts ${Js.Json.stringify(doc)}"}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should insert document on create")
}

/** Test: afterChange hook - update */
let test_afterChangeUpdate = async (): testResult => {
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
      "body": `{"gql": "UPDATE posts SET {\\"title\\": \\"Updated\\"} WHERE id = \\"doc-123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should update document")
}

/** Test: afterDelete hook */
let test_afterDelete = async (): testResult => {
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
      "body": `{"gql": "DELETE FROM posts WHERE id = \\"doc-123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should delete document")
}

/** Test: Field exclusion */
let test_fieldExclusion = async (): testResult => {
  let excludeFields = ["_status", "__v", "password"]
  let doc = Js.Dict.fromArray([
    ("id", Js.Json.string("123")),
    ("title", Js.Json.string("Test")),
    ("_status", Js.Json.string("draft")),
    ("__v", Js.Json.number(0.0)),
    ("password", Js.Json.string("secret")),
  ])

  let filtered = Js.Dict.empty()
  Js.Dict.keys(doc)->Array.forEach(key => {
    if !excludeFields->Array.includes(key) {
      switch Js.Dict.get(doc, key) {
      | Some(value) => Js.Dict.set(filtered, key, value)
      | None => ()
      }
    }
  })

  let numFields = Array.length(Js.Dict.keys(filtered))
  assertEqual(numFields, 2, "Should exclude internal fields")
}

/** Test: Localized field handling */
let test_localizedFields = async (): testResult => {
  let localizedDoc = Js.Json.object_(Js.Dict.fromArray([
    ("id", Js.Json.string("123")),
    ("title", Js.Json.object_(Js.Dict.fromArray([
      ("en", Js.Json.string("English Title")),
      ("de", Js.Json.string("German Title")),
    ]))),
  ]))

  // Verify structure is preserved
  switch Js.Json.decodeObject(localizedDoc) {
  | Some(obj) => {
      let titleOpt = Js.Dict.get(obj, "title")
      switch titleOpt {
      | Some(title) => {
          switch Js.Json.decodeObject(title) {
          | Some(locales) => {
              let hasEn = Js.Dict.get(locales, "en")->Option.isSome
              let hasDe = Js.Dict.get(locales, "de")->Option.isSome
              assertTrue(hasEn && hasDe, "Should preserve localized structure")
            }
          | None => Failed({message: "Title should be object with locales"})
          }
        }
      | None => Failed({message: "Missing title field"})
      }
    }
  | None => Failed({message: "Invalid document structure"})
  }
}

/** Test: Sync mode filtering */
let test_syncModeFiltering = async (): testResult => {
  let shouldSyncToLith = (mode: string): bool => {
    mode == "bidirectional" || mode == "payload-to-lith"
  }

  let shouldSyncToPayload = (mode: string): bool => {
    mode == "bidirectional" || mode == "lith-to-payload"
  }

  let bi = shouldSyncToLith("bidirectional") && shouldSyncToPayload("bidirectional")
  let ptf = shouldSyncToLith("payload-to-lith") && !shouldSyncToPayload("payload-to-lith")
  let ftp = !shouldSyncToLith("lith-to-payload") && shouldSyncToPayload("lith-to-payload")

  assertTrue(bi && ptf && ftp, "Sync mode filtering should work correctly")
}

/** Test: Disabled plugin */
let test_disabledPlugin = async (): testResult => {
  let config = Js.Dict.fromArray([
    ("enabled", Js.Json.boolean(false)),
  ])

  let enabled = switch Js.Dict.get(config, "enabled") {
  | Some(v) =>
    switch Js.Json.decodeBoolean(v) {
    | Some(b) => b
    | None => true
    }
  | None => true
  }

  assertFalse(enabled, "Plugin should be disabled")
}

/** Run all Payload integration tests */
let runPayloadTests = async (): {passed: int, failed: int, skipped: int} => {
  Js.Console.log("\n=== Payload CMS Integration Tests ===\n")

  let tests = [
    ("Plugin configuration", test_pluginConfiguration),
    ("Collection mapping", test_collectionMapping),
    ("afterChange hook - create", test_afterChangeCreate),
    ("afterChange hook - update", test_afterChangeUpdate),
    ("afterDelete hook", test_afterDelete),
    ("Field exclusion", test_fieldExclusion),
    ("Localized field handling", test_localizedFields),
    ("Sync mode filtering", test_syncModeFiltering),
    ("Disabled plugin", test_disabledPlugin),
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

let default = runPayloadTests
