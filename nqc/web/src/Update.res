// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Pure update function for the NQC Web UI TEA application.
Every state transition is handled here.  Side effects (HTTP requests,
navigation) are described as `Tea_Cmd.t` values returned alongside the
new model — they are never executed directly.
")

// ============================================================================
// Navigation helper — push to browser history + update model route
// ============================================================================

@ocaml.doc("
Navigate to a path string: push to browser history via cadre-router
and update the model's route to match.  Returns a `Tea_Cmd.effect` that
performs the History API side effect.
")
let navigateTo = (model: Model.t, path: string): (Model.t, Tea_Cmd.t<Msg.t>) => {
  let url = Tea_Url.parse(path)
  let route = Route.fromUrl(url)
  let activeDb = switch route {
  | Route.Query({dbId, _}) => Database.findById(dbId)
  | Picker | NotFound => None
  }
  let dtEnabled = switch route {
  | Route.Query({dt, _}) => dt
  | Picker | NotFound => model.dtEnabled
  }
  let format = switch route {
  | Route.Query({format, _}) => Msg.formatFromString(format)
  | Picker | NotFound => model.format
  }
  let newModel = {
    ...model,
    route,
    activeDb,
    dtEnabled,
    format,
    // Clear results when navigating to a different database
    results: switch (model.activeDb, activeDb) {
    | (Some(old), Some(new_)) if old.id != new_.id => None
    | (None, _) => None
    | _ => model.results
    },
    // Reset connection when switching databases
    connection: switch activeDb {
    | Some(_) => Msg.Connecting
    | None => Msg.Disconnected
    },
  }
  let navCmd = Tea_Cmd.effect(_dispatch => {
    Tea_Navigation.execute(Tea_Navigation.Push(url))
  })
  // If navigating to a specific database, also check its health
  let healthCmd = switch activeDb {
  | Some(db) => Api.checkHealth(db)
  | None => Tea_Cmd.none
  }
  (newModel, Tea_Cmd.batch([navCmd, healthCmd]))
}

// ============================================================================
// Main update function
// ============================================================================

@ocaml.doc("
Handle a single message, producing a new model and any side-effect commands.
Pattern-matches exhaustively on all `Msg.t` variants.
")
let update = (msg: Msg.t, model: Model.t): (Model.t, Tea_Cmd.t<Msg.t>) => {
  switch msg {
  // ---- Routing ----

  | Msg.UrlChanged(url) => {
      // Browser back/forward button fired a popstate event
      let route = Route.fromUrl(url)
      let activeDb = switch route {
      | Route.Query({dbId, _}) => Database.findById(dbId)
      | Picker | NotFound => None
      }
      let dtEnabled = switch route {
      | Route.Query({dt, _}) => dt
      | Picker | NotFound => model.dtEnabled
      }
      let format = switch route {
      | Route.Query({format, _}) => Msg.formatFromString(format)
      | Picker | NotFound => model.format
      }
      let healthCmd = switch activeDb {
      | Some(db) => Api.checkHealth(db)
      | None => Tea_Cmd.none
      }
      ({...model, route, activeDb, dtEnabled, format}, healthCmd)
    }

  | Msg.NavigateTo(path) => navigateTo(model, path)

  // ---- Database selection ----

  | Msg.SelectDatabase(dbId) => {
      let path = "/query/" ++ dbId
      navigateTo(model, path)
    }

  // ---- Query editing ----

  | Msg.UpdateQuery(text) => ({...model, query: text}, Tea_Cmd.none)

  | Msg.SubmitQuery => {
      switch model.activeDb {
      | Some(db) if model.query->String.trim->String.length > 0 => {
          // Record in history
          let entry: Msg.historyEntry = {
            query: model.query,
            dbId: db.id,
            timestamp: Date.now(),
          }
          let newHistory = Array.concat([entry], model.history)->Array.slice(~start=0, ~end=50)
          let newModel = {...model, history: newHistory, error: None}
          (newModel, Api.executeQuery(db, model.query, model.dtEnabled))
        }
      | _ => (model, Tea_Cmd.none)
      }
    }

  | Msg.QueryResult(Ok(json)) => ({...model, results: Some(json), error: None}, Tea_Cmd.none)

  | Msg.QueryResult(Error(httpError)) => {
      let errMsg = Tea_Http.errorToString(httpError)
      ({...model, error: Some(errMsg)}, Tea_Cmd.none)
    }

  // ---- Health checks ----

  | Msg.HealthResult(dbId, Ok(_)) => {
      let healthMap = Dict.fromArray(
        Dict.toArray(model.healthMap)->Array.concat([(dbId, Msg.Connected)]),
      )
      // If this is the active database, update connection state too
      let connection = switch model.activeDb {
      | Some(db) if db.id == dbId => Msg.Connected
      | _ => model.connection
      }
      ({...model, healthMap, connection}, Tea_Cmd.none)
    }

  | Msg.HealthResult(dbId, Error(err)) => {
      let errMsg = Tea_Http.errorToString(err)
      let healthMap = Dict.fromArray(
        Dict.toArray(model.healthMap)->Array.concat([
          (dbId, Msg.ConnectionError(errMsg)),
        ]),
      )
      let connection = switch model.activeDb {
      | Some(db) if db.id == dbId => Msg.ConnectionError(errMsg)
      | _ => model.connection
      }
      ({...model, healthMap, connection}, Tea_Cmd.none)
    }

  // ---- UI controls ----

  | Msg.SetFormat(fmt) => {
      let newModel = {...model, format: fmt}
      // Update URL to reflect format change
      let path = Route.toPath(Route.Query({
        dbId: switch model.activeDb {
        | Some(db) => db.id
        | None => "unknown"
        },
        dt: model.dtEnabled,
        format: Msg.formatToString(fmt),
      }))
      let cmd = Tea_Cmd.effect(_dispatch => {
        Tea_Navigation.execute(Tea_Navigation.Replace(Tea_Url.parse(path)))
      })
      (newModel, cmd)
    }

  | Msg.ToggleDt => {
      let newDt = !model.dtEnabled
      let newModel = {...model, dtEnabled: newDt}
      // Update URL to reflect DT change
      let path = Route.toPath(Route.Query({
        dbId: switch model.activeDb {
        | Some(db) => db.id
        | None => "unknown"
        },
        dt: newDt,
        format: Msg.formatToString(model.format),
      }))
      let cmd = Tea_Cmd.effect(_dispatch => {
        Tea_Navigation.execute(Tea_Navigation.Replace(Tea_Url.parse(path)))
      })
      (newModel, cmd)
    }

  | Msg.ClearResults => ({...model, results: None}, Tea_Cmd.none)

  | Msg.HistorySelect(idx) => {
      switch model.history->Array.get(idx) {
      | Some(entry) => ({...model, query: entry.query}, Tea_Cmd.none)
      | None => (model, Tea_Cmd.none)
      }
    }

  | Msg.DismissError => ({...model, error: None}, Tea_Cmd.none)
  }
}
