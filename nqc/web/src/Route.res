// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
URL routing for NQC Web UI using cadre-router.
Parses the current URL into a typed route variant and extracts
query parameters (dependent types toggle, output format).
Routes are the single source of truth for which page the app displays.
")

// ============================================================================
// Route type — exhaustive representation of all navigable pages
// ============================================================================

@ocaml.doc("
Discriminated union of all application routes.
- `Picker`  — landing page showing available database engines
- `Query`   — interactive query editor for a selected database
- `NotFound` — catch-all for unrecognised paths
")
type t =
  | Picker
  | Query({dbId: string, dt: bool, format: string})
  | NotFound

// ============================================================================
// URL parsing — converts Tea_Url.t into our Route.t
// ============================================================================

@ocaml.doc("
Parse a `Tea_Url.t` (from cadre-router) into an application `Route.t`.
Extracts path segments by splitting on '/' and maps them to route variants.
Query parameters `dt` and `format` are extracted for the Query page.

Examples:
  `/`                          => Picker
  `/query/vql`                 => Query({dbId: 'vql', dt: false, format: 'table'})
  `/query/gql?dt=true`         => Query({dbId: 'gql', dt: true, format: 'table'})
  `/query/kql?format=json`     => Query({dbId: 'kql', dt: false, format: 'json'})
  `/anything-else`             => NotFound
")
let fromUrl = (url: Tea_Url.t): t => {
  // Parse query parameters from the URL's query string
  let params = switch url.query {
  | Some(qs) => Tea_QueryParams.parse(qs)
  | None => Dict.make()
  }

  // Extract dt (dependent types) flag, defaults to false
  let dt = Tea_QueryParams.getBool(params, "dt")->Option.getOr(false)

  // Extract output format, defaults to "table"
  let format = Tea_QueryParams.getOr(params, "format", "table")

  // Split path into segments, filtering out empty strings from leading/trailing '/'
  let segments = url.path->String.split("/")->Array.filter(s => s->String.length > 0)

  switch segments {
  | [] => Picker
  | ["query", dbId] => Query({dbId, dt, format})
  | _ => NotFound
  }
}

// ============================================================================
// Route serialization — converts Route.t back to a URL path string
// ============================================================================

@ocaml.doc("
Serialize a route back into a URL path string suitable for
`Tea_Navigation.pushPath`.  Appends query parameters for the Query page
so that the URL always reflects the full application state (deep-linking).
")
let toPath = (route: t): string => {
  switch route {
  | Picker => "/"
  | Query({dbId, dt, format}) => {
      let base = "/query/" ++ dbId
      let params = Dict.make()
      if dt {
        Dict.set(params, "dt", "true")
      }
      if format != "table" {
        Dict.set(params, "format", format)
      }
      let qs = Tea_QueryParams.build(params)
      base ++ qs
    }
  | NotFound => "/404"
  }
}
