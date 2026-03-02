// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Connection configuration, authentication, and HTTP transport.
//
// This module provides the core client configuration used by all other SDK modules.
// It wraps the Fetch API via external bindings (no npm packages) and supports
// multiple authentication methods: API key, Basic, Bearer token, or none.
//
// Usage:
//   let client = VeriSimClient.make(~baseUrl="http://localhost:8080")
//   let healthResult = await VeriSimClient.health(client)

// --------------------------------------------------------------------------
// Fetch API bindings (no npm dependencies — uses browser/Deno global fetch)
// --------------------------------------------------------------------------

/** External binding to the global fetch function. */
@val external fetch: (string, {..}) => promise<VeriSimTypes.fetchResponse> = "fetch"

/** Read the response body as a JSON value. */
@send external jsonBody: VeriSimTypes.fetchResponse => promise<JSON.t> = "json"

/** Read the response body as a UTF-8 string. */
@send external textBody: VeriSimTypes.fetchResponse => promise<string> = "text"

// --------------------------------------------------------------------------
// Authentication types
// --------------------------------------------------------------------------

/** Authentication method for connecting to VeriSimDB. */
type auth =
  | ApiKey(string)
  | Basic({username: string, password: string})
  | Bearer(string)
  | NoAuth

// --------------------------------------------------------------------------
// Client configuration
// --------------------------------------------------------------------------

/** Client holds the connection configuration for a VeriSimDB server. */
type t = {
  baseUrl: string,
  timeout: int,
  auth: auth,
}

/** Create a new unauthenticated client with the given base URL. */
let make = (~baseUrl: string, ~timeout: int=30000, ~auth: auth=NoAuth): t => {
  {
    baseUrl: baseUrl,
    timeout: timeout,
    auth: auth,
  }
}

/** Create a client authenticated with an API key. */
let makeWithApiKey = (~baseUrl: string, ~apiKey: string, ~timeout: int=30000): t => {
  make(~baseUrl, ~timeout, ~auth=ApiKey(apiKey))
}

/** Create a client authenticated with a Bearer token. */
let makeWithBearer = (~baseUrl: string, ~token: string, ~timeout: int=30000): t => {
  make(~baseUrl, ~timeout, ~auth=Bearer(token))
}

// --------------------------------------------------------------------------
// Internal helpers
// --------------------------------------------------------------------------

/** Build authentication headers from the client's auth configuration. */
let authHeaders = (client: t): Dict.t<string> => {
  let headers = Dict.make()
  switch client.auth {
  | ApiKey(key) => Dict.set(headers, "X-API-Key", key)
  | Basic({username, password}) => {
      let encoded = btoa(`${username}:${password}`)
      Dict.set(headers, "Authorization", `Basic ${encoded}`)
    }
  | Bearer(token) => Dict.set(headers, "Authorization", `Bearer ${token}`)
  | NoAuth => ()
  }
  headers
}

/** External binding to btoa for Base64 encoding (available in browser and Deno). */
@val external btoa: string => string = "btoa"

/** Perform a GET request to the given path on the client's base URL. */
let doGet = async (client: t, path: string): VeriSimTypes.fetchResponse => {
  let headers = authHeaders(client)
  await fetch(
    `${client.baseUrl}${path}`,
    {
      "method": "GET",
      "headers": headers,
    },
  )
}

/** Perform a POST request with a JSON body. */
let doPost = async (client: t, path: string, body: JSON.t): VeriSimTypes.fetchResponse => {
  let headers = authHeaders(client)
  Dict.set(headers, "Content-Type", "application/json")
  await fetch(
    `${client.baseUrl}${path}`,
    {
      "method": "POST",
      "headers": headers,
      "body": JSON.stringify(body),
    },
  )
}

/** Perform a PUT request with a JSON body. */
let doPut = async (client: t, path: string, body: JSON.t): VeriSimTypes.fetchResponse => {
  let headers = authHeaders(client)
  Dict.set(headers, "Content-Type", "application/json")
  await fetch(
    `${client.baseUrl}${path}`,
    {
      "method": "PUT",
      "headers": headers,
      "body": JSON.stringify(body),
    },
  )
}

/** Perform a DELETE request to the given path. */
let doDelete = async (client: t, path: string): VeriSimTypes.fetchResponse => {
  let headers = authHeaders(client)
  await fetch(
    `${client.baseUrl}${path}`,
    {
      "method": "DELETE",
      "headers": headers,
    },
  )
}

// --------------------------------------------------------------------------
// Health check
// --------------------------------------------------------------------------

/** Check whether the VeriSimDB server is reachable and healthy.
 *
 * Sends a GET request to /health and expects a 200 OK response.
 * Returns a result indicating success or an error message.
 */
let health = async (client: t): result<bool, VeriSimError.t> => {
  try {
    let resp = await doGet(client, "/health")
    if resp.ok {
      Ok(true)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Failed to connect to VeriSimDB server"))
  }
}
