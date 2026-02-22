// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
HTTP command layer for the NQC Web UI.
All requests are routed through the Deno CORS proxy at `localhost:4000`
which forwards to the appropriate database port.  This avoids CORS issues
when the browser communicates with backend database engines.

Two operations are supported:
  1. `executeQuery` — POST a query string to the database's execute endpoint
  2. `checkHealth`  — GET the database's health endpoint to update status dots
")

// ============================================================================
// Configuration
// ============================================================================

@ocaml.doc("Base URL for the CORS proxy.  All API requests are prefixed with this.")
let proxyBase = "http://localhost:4000"

// ============================================================================
// Query execution
// ============================================================================

@ocaml.doc("
Send a query to the specified database via the CORS proxy.
The proxy routes `/api/:dbId/*` to `localhost:<dbPort>/*`.

The request body matches the Gleam client's format:
  `{\"query\": \"...\", \"dt\": true/false}`

The response is decoded as raw `JSON.t` since each database engine
returns a different schema.  The `Results` component handles rendering
the heterogeneous response shapes.
")
let executeQuery = (
  profile: Database.profile,
  query: string,
  dtEnabled: bool,
): Tea_Cmd.t<Msg.t> => {
  let url = `${proxyBase}/api/${profile.id}${profile.executePath}`
  let body =
    JSON.Encode.object(Dict.fromArray([
      ("query", JSON.Encode.string(query)),
      ("dt", JSON.Encode.bool(dtEnabled)),
    ]))

  Tea_Http.postJson(url, body, Tea_Json.value, result => Msg.QueryResult(result))
}

// ============================================================================
// Health checks
// ============================================================================

@ocaml.doc("
Check the health of a single database engine.
GETs the health endpoint through the CORS proxy and reports success/failure
back as a `HealthResult` message tagged with the database id.
")
let checkHealth = (profile: Database.profile): Tea_Cmd.t<Msg.t> => {
  let url = `${proxyBase}/api/${profile.id}${profile.healthPath}`
  Tea_Http.getString(url, result => Msg.HealthResult(profile.id, result))
}

// ============================================================================
// Batch health check
// ============================================================================

@ocaml.doc("
Check health of all known database profiles in parallel.
Returns a batched command that fires one `HealthResult` per profile.
Called on app init and whenever the picker page is displayed.
")
let checkAllHealth = (): Tea_Cmd.t<Msg.t> => {
  Tea_Cmd.batch(Database.all()->Array.map(checkHealth))
}
