// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Application model (state) for the NQC Web UI.
The model is a single immutable record updated exclusively by `Update.update`.
It captures the full UI state: current route, selected database, query text,
results, formatting preferences, connection health, and session history.
")

// ============================================================================
// Model type
// ============================================================================

@ocaml.doc("
The full application state.  Every field is immutable — the update function
produces a new model record on each state transition.
- `route` — current page derived from the URL
- `databases` — all known database profiles (builtins + custom)
- `activeDb` — currently selected database profile, if any
- `connection` — health-check state for the active database
- `healthMap` — per-database health status (keyed by profile id)
- `query` — current contents of the query editor textarea
- `results` — last successful query response as raw JSON
- `format` — current output rendering mode (table / json / csv)
- `dtEnabled` — whether dependent-type verification is toggled on
- `history` — ring buffer of past queries in this session
- `error` — dismissible error message for the user
")
type t = {
  route: Route.t,
  databases: array<Database.profile>,
  activeDb: option<Database.profile>,
  connection: Msg.connectionState,
  healthMap: dict<Msg.connectionState>,
  query: string,
  results: option<JSON.t>,
  format: Msg.outputFormat,
  dtEnabled: bool,
  history: array<Msg.historyEntry>,
  error: option<string>,
}

// ============================================================================
// Initialization
// ============================================================================

@ocaml.doc("
Create the initial model from the current browser URL.
The route determines which page to show on first paint.
If the URL targets a specific database (`/query/:dbId`), the active
database and DT flag are set from the route parameters.
")
let init = (route: Route.t): t => {
  let activeDb = switch route {
  | Route.Query({dbId, _}) => Database.findById(dbId)
  | Picker | NotFound => None
  }

  let dtEnabled = switch route {
  | Route.Query({dt, _}) => dt
  | Picker | NotFound => false
  }

  let format = switch route {
  | Route.Query({format, _}) => Msg.formatFromString(format)
  | Picker | NotFound => Msg.Table
  }

  {
    route,
    databases: Database.all(),
    activeDb,
    connection: Msg.Disconnected,
    healthMap: Dict.make(),
    query: "",
    results: None,
    format,
    dtEnabled,
    history: [],
    error: None,
  }
}
