// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Integration Test Types
 *
 * Common types for CMS integration testing
 */

/** Test result */
type testResult =
  | Passed
  | Failed({message: string})
  | Skipped({reason: string})

/** Test case */
type testCase = {
  name: string,
  run: unit => promise<testResult>,
}

/** Test suite */
type testSuite = {
  name: string,
  setup: unit => promise<unit>,
  teardown: unit => promise<unit>,
  tests: array<testCase>,
}

/** Mock HTTP response */
type mockResponse = {
  status: int,
  body: Js.Json.t,
  headers: Js.Dict.t<string>,
}

/** Mock HTTP request record */
type mockRequest = {
  method: string,
  url: string,
  headers: Js.Dict.t<string>,
  body: option<Js.Json.t>,
}

/** Sync event types */
type syncEvent =
  | Created({collection: string, id: string, data: Js.Json.t})
  | Updated({collection: string, id: string, data: Js.Json.t, previousData: option<Js.Json.t>})
  | Deleted({collection: string, id: string})

/** Sync direction */
type syncDirection =
  | CmsToLith
  | LithToCms
  | Bidirectional

/** Test assertions */
let assertEqual = (actual: 'a, expected: 'a, message: string): testResult => {
  if actual == expected {
    Passed
  } else {
    Failed({message})
  }
}

let assertTrue = (condition: bool, message: string): testResult => {
  if condition {
    Passed
  } else {
    Failed({message})
  }
}

let assertFalse = (condition: bool, message: string): testResult => {
  if !condition {
    Passed
  } else {
    Failed({message})
  }
}
