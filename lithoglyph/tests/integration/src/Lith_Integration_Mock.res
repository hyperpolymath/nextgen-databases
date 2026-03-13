// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Integration Test Mocks
 *
 * Mock servers and clients for integration testing
 */

open Lith_Integration_Types

/** Recorded request store */
type requestStore = {
  mutable requests: array<mockRequest>,
}

/** Create request store */
let makeRequestStore = (): requestStore => {
  {requests: []}
}

/** Record a request */
let recordRequest = (store: requestStore, request: mockRequest): unit => {
  store.requests->Array.push(request)->ignore
}

/** Get recorded requests */
let getRequests = (store: requestStore): array<mockRequest> => {
  store.requests
}

/** Clear recorded requests */
let clearRequests = (store: requestStore): unit => {
  store.requests = []
}

/** Mock Lith client for testing */
type mockLithClient = {
  requestStore: requestStore,
  mutable responses: array<mockResponse>,
  mutable responseIndex: int,
}

/** Create mock Lith client */
let makeMockLithClient = (): mockLithClient => {
  {
    requestStore: makeRequestStore(),
    responses: [],
    responseIndex: 0,
  }
}

/** Add response to mock client */
let addResponse = (client: mockLithClient, response: mockResponse): unit => {
  client.responses->Array.push(response)->ignore
}

/** Get next response */
let nextResponse = (client: mockLithClient): mockResponse => {
  let idx = client.responseIndex
  client.responseIndex = client.responseIndex + 1
  client.responses[idx]->Option.getOr({
    status: 200,
    body: Js.Json.null,
    headers: Js.Dict.empty(),
  })
}

/** Mock HTTP fetch for testing */
let mockFetch = (
  client: mockLithClient,
  url: string,
  options: {..},
): promise<mockResponse> => {
  // Record the request
  let method = options["method"]->Option.getOr("GET")
  let headers = options["headers"]->Option.getOr(Js.Dict.empty())
  let bodyStr = options["body"]->Option.getOr("")

  let body = if String.length(bodyStr) > 0 {
    try {
      Some(Js.Json.parseExn(bodyStr))
    } catch {
    | _ => None
    }
  } else {
    None
  }

  recordRequest(client.requestStore, {
    method,
    url,
    headers,
    body,
  })

  // Return next configured response
  Promise.resolve(nextResponse(client))
}

/** Mock Strapi context */
type mockStrapiContext = {
  strapi: {..},
  mutable contentTypes: Js.Dict.t<{..}>,
  mutable entries: Js.Dict.t<array<Js.Json.t>>,
}

/** Create mock Strapi context */
let makeMockStrapiContext = (): mockStrapiContext => {
  {
    strapi: %raw(`{
      plugin: (name) => ({ service: (svc) => ({}) }),
      log: { info: console.log, error: console.error, warn: console.warn },
      contentTypes: {},
    }`),
    contentTypes: Js.Dict.empty(),
    entries: Js.Dict.empty(),
  }
}

/** Mock Directus context */
type mockDirectusContext = {
  mutable items: Js.Dict.t<array<Js.Json.t>>,
  mutable hooks: array<string>,
}

/** Create mock Directus context */
let makeMockDirectusContext = (): mockDirectusContext => {
  {
    items: Js.Dict.empty(),
    hooks: [],
  }
}

/** Mock Ghost webhook payload */
type mockGhostPayload = {
  eventType: string,
  data: Js.Json.t,
  timestamp: string,
}

/** Create mock Ghost payload */
let makeMockGhostPayload = (eventType: string, data: Js.Json.t): mockGhostPayload => {
  {
    eventType,
    data,
    timestamp: Js.Date.toISOString(Js.Date.make()),
  }
}

/** Mock Payload CMS context */
type mockPayloadContext = {
  mutable collections: Js.Dict.t<array<Js.Json.t>>,
  mutable hooks: array<{..}>,
}

/** Create mock Payload context */
let makeMockPayloadContext = (): mockPayloadContext => {
  {
    collections: Js.Dict.empty(),
    hooks: [],
  }
}
