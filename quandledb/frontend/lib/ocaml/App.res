// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// QuandleDB — top-level application component
// Manages routing, state, and API interaction.

type model = {
  route: Route.t,
  stats: Types.remoteData<Types.statistics, string>,
  knots: Types.remoteData<Types.knotListResponse, string>,
  knotDetail: Types.remoteData<Types.knot, string>,
  filters: Types.filters,
}

type msg =
  | NavigateTo(Route.t)
  | UrlChanged
  | GotStatistics(result<Types.statistics, string>)
  | GotKnots(result<Types.knotListResponse, string>)
  | GotKnotDetail(result<Types.knot, string>)
  | SetFilters(Types.filters)

@val external pushState: (Js.Nullable.t<string>, string, string) => unit = "history.pushState"
@val external addWindowEventListener: (string, 'a => unit) => unit = "window.addEventListener"
@val external removeWindowEventListener: (string, 'a => unit) => unit = "window.removeEventListener"

@react.component
let make = () => {
  let (model, dispatch) = React.useReducer((model: model, msg: msg) =>
    switch msg {
    | NavigateTo(route) => {
        pushState(Js.Nullable.null, "", Route.toPath(route))
        {...model, route}
      }
    | UrlChanged => {...model, route: Route.fromUrl()}
    | GotStatistics(Ok(stats)) => {...model, stats: Success(stats)}
    | GotStatistics(Error(err)) => {...model, stats: Failure(err)}
    | GotKnots(Ok(knots)) => {...model, knots: Success(knots)}
    | GotKnots(Error(err)) => {...model, knots: Failure(err)}
    | GotKnotDetail(Ok(knot)) => {...model, knotDetail: Success(knot)}
    | GotKnotDetail(Error(err)) => {...model, knotDetail: Failure(err)}
    | SetFilters(filters) => {...model, filters, knots: Loading}
    }
  , {
    route: Route.fromUrl(),
    stats: NotAsked,
    knots: NotAsked,
    knotDetail: NotAsked,
    filters: Types.emptyFilters,
  })

  // Listen for popstate (browser back/forward)
  React.useEffect0(() => {
    let handler = _ => dispatch(UrlChanged)
    addWindowEventListener("popstate", handler)
    Some(() => removeWindowEventListener("popstate", handler))
  })

  // Fetch data when route changes
  React.useEffect1(() => {
    switch model.route {
    | Dashboard =>
      if model.stats == NotAsked {
        let _ = {
          open Promise
          Api.fetchStatistics()->then(result => {
            dispatch(GotStatistics(result))
            resolve()
          })
        }
      }
    | KnotList =>
      if model.knots == NotAsked {
        let _ = {
          open Promise
          Api.fetchKnots()->then(result => {
            dispatch(GotKnots(result))
            resolve()
          })
        }
      }
    | KnotDetail(name) => {
        let _ = {
          open Promise
          Api.fetchKnot(name)->then(result => {
            dispatch(GotKnotDetail(result))
            resolve()
          })
        }
      }
    | Query => ()
    | NotFound => ()
    }
    None
  }, [model.route])

  // Refetch knots when filters change
  React.useEffect1(() => {
    if model.route == KnotList {
      let _ = {
        open Promise
        Api.fetchKnots(~filters=model.filters)->then(result => {
          dispatch(GotKnots(result))
          resolve()
        })
      }
    }
    None
  }, [model.filters])

  let navigate = (route: Route.t) => dispatch(NavigateTo(route))

  <div className="app">
    <View_Helpers.NavBar currentRoute={model.route} onNavigate=navigate />
    <main className="content">
      {switch model.route {
      | Dashboard => <Page_Dashboard stats={model.stats} onNavigate=navigate />
      | KnotList =>
        <Page_KnotList
          knots={model.knots}
          filters={model.filters}
          onFilterChange={f => dispatch(SetFilters(f))}
          onNavigate=navigate
        />
      | KnotDetail(_) =>
        <Page_KnotDetail knot={model.knotDetail} onNavigate=navigate />
      | Query => <Page_Query />
      | NotFound =>
        <div className="not-found">
          <h1> {React.string("404 - Not Found")} </h1>
          <p> {React.string("The page you are looking for does not exist.")} </p>
          <button className="btn-primary" onClick={_ => navigate(Dashboard)}>
            {React.string("Go Home")}
          </button>
        </div>
      }}
    </main>
    <footer className="app-footer">
      <p> {React.string("QuandleDB — Powered by Skein.jl")} </p>
    </footer>
  </div>
}
