// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith E2E Test Types
 *
 * Types for end-to-end testing
 */

/** E2E test environment */
type testEnvironment = {
  lithUrl: string,
  apiKey: option<string>,
  testPrefix: string,
}

/** Default test environment */
let defaultEnvironment: testEnvironment = {
  lithUrl: "http://localhost:8080",
  apiKey: None,
  testPrefix: "e2e_test_",
}

/** E2E test result */
type e2eResult =
  | Passed({duration: float})
  | Failed({message: string, duration: float})
  | Skipped({reason: string})
  | Timeout({duration: float})

/** E2E test case */
type e2eTestCase = {
  name: string,
  description: string,
  timeout: int,
  run: testEnvironment => promise<e2eResult>,
}

/** E2E test suite */
type e2eSuite = {
  name: string,
  description: string,
  setup: testEnvironment => promise<unit>,
  teardown: testEnvironment => promise<unit>,
  tests: array<e2eTestCase>,
}

/** HTTP client for E2E tests */
type httpClient = {
  get: string => promise<{..}>,
  post: (string, Js.Json.t) => promise<{..}>,
  put: (string, Js.Json.t) => promise<{..}>,
  delete: string => promise<{..}>,
}

/** Create HTTP client */
let makeHttpClient = (env: testEnvironment): httpClient => {
  let headers = switch env.apiKey {
  | Some(key) =>
    Js.Dict.fromArray([
      ("Content-Type", "application/json"),
      ("X-API-Key", key),
    ])
  | None => Js.Dict.fromArray([("Content-Type", "application/json")])
  }

  {
    get: async (path: string): {..} => {
      %raw(`
        const response = await fetch(env.lithUrl + path, {
          method: 'GET',
          headers: headers
        });
        return response.json();
      `)
    },
    post: async (path: string, body: Js.Json.t): {..} => {
      %raw(`
        const response = await fetch(env.lithUrl + path, {
          method: 'POST',
          headers: headers,
          body: JSON.stringify(body)
        });
        return response.json();
      `)
    },
    put: async (path: string, body: Js.Json.t): {..} => {
      %raw(`
        const response = await fetch(env.lithUrl + path, {
          method: 'PUT',
          headers: headers,
          body: JSON.stringify(body)
        });
        return response.json();
      `)
    },
    delete: async (path: string): {..} => {
      %raw(`
        const response = await fetch(env.lithUrl + path, {
          method: 'DELETE',
          headers: headers
        });
        return response.json();
      `)
    },
  }
}

/** Test assertions */
let assertE2E = (condition: bool, message: string, startTime: float): e2eResult => {
  let duration = Js.Date.now() -. startTime
  if condition {
    Passed({duration})
  } else {
    Failed({message, duration})
  }
}
