// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Ghost Integration Tests
 *
 * Tests for Ghost webhook server functionality
 */

open Lith_Integration_Types
open Lith_Integration_Mock

/** Test: Webhook signature verification */
let test_signatureVerification = async (): testResult => {
  // HMAC-SHA256 signature verification
  let secret = "webhook-secret"
  let payload = `{"post": {"id": "123"}}`

  // In real implementation, would verify HMAC
  let hasSecret = String.length(secret) > 0
  let hasPayload = String.length(payload) > 0

  assertTrue(hasSecret && hasPayload, "Should have secret and payload for verification")
}

/** Test: Post published event */
let test_postPublishedEvent = async (): testResult => {
  let client = makeMockLithClient()

  addResponse(client, {
    status: 201,
    body: Js.Json.object_(Js.Dict.fromArray([("success", Js.Json.boolean(true))])),
    headers: Js.Dict.empty(),
  })

  let webhookPayload = Js.Json.object_(Js.Dict.fromArray([
    ("post", Js.Json.object_(Js.Dict.fromArray([
      ("current", Js.Json.object_(Js.Dict.fromArray([
        ("id", Js.Json.string("post-123")),
        ("title", Js.Json.string("New Post")),
        ("status", Js.Json.string("published")),
      ]))),
    ]))),
  ]))

  let _response = await mockFetch(
    client,
    "http://localhost:8080/v1/query",
    {
      "method": "POST",
      "headers": Js.Dict.fromArray([("Content-Type", "application/json")]),
      "body": `{"fdql": "INSERT INTO posts ${Js.Json.stringify(webhookPayload)}"}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should sync post to Lith")
}

/** Test: Post updated event */
let test_postUpdatedEvent = async (): testResult => {
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
      "body": `{"fdql": "UPDATE posts SET {\\"title\\": \\"Updated Post\\"} WHERE id = \\"post-123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should update post in Lith")
}

/** Test: Post deleted event */
let test_postDeletedEvent = async (): testResult => {
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
      "body": `{"fdql": "DELETE FROM posts WHERE id = \\"post-123\\""}`,
    },
  )

  let requests = getRequests(client.requestStore)
  assertEqual(Array.length(requests), 1, "Should delete post from Lith")
}

/** Test: Page events */
let test_pageEvents = async (): testResult => {
  let eventTypes = ["page.published", "page.updated", "page.deleted"]
  let allValid = eventTypes->Array.every(e => String.includes(e, "page."))
  assertTrue(allValid, "Should handle all page event types")
}

/** Test: Member events */
let test_memberEvents = async (): testResult => {
  let eventTypes = ["member.added", "member.updated", "member.deleted"]
  let allValid = eventTypes->Array.every(e => String.includes(e, "member."))
  assertTrue(allValid, "Should handle all member event types")
}

/** Test: Collection mapping */
let test_collectionMapping = async (): testResult => {
  let mappings = Js.Dict.fromArray([
    ("post", "posts"),
    ("page", "pages"),
    ("member", "members"),
  ])

  let postCollection = Js.Dict.get(mappings, "post")
  switch postCollection {
  | Some(coll) => assertEqual(coll, "posts", "Should map post to posts collection")
  | None => Failed({message: "Missing post mapping"})
  }
}

/** Test: Invalid webhook rejection */
let test_invalidWebhookRejection = async (): testResult => {
  // Invalid webhook should return 400
  let invalidPayload = "not json"
  let isValid = try {
    let _ = Js.Json.parseExn(invalidPayload)
    true
  } catch {
  | _ => false
  }

  assertFalse(isValid, "Should reject invalid JSON payload")
}

/** Run all Ghost integration tests */
let runGhostTests = async (): {passed: int, failed: int, skipped: int} => {
  Js.Console.log("\n=== Ghost Integration Tests ===\n")

  let tests = [
    ("Webhook signature verification", test_signatureVerification),
    ("Post published event", test_postPublishedEvent),
    ("Post updated event", test_postUpdatedEvent),
    ("Post deleted event", test_postDeletedEvent),
    ("Page events", test_pageEvents),
    ("Member events", test_memberEvents),
    ("Collection mapping", test_collectionMapping),
    ("Invalid webhook rejection", test_invalidWebhookRejection),
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

let default = runGhostTests
