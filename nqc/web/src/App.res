// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
TEA application entry point for the NQC Web UI.
Uses `Tea_App.MakeWithDispatch` to wire together:
  - init: parse current URL into initial model + set up URL listener + health checks
  - update: pure state machine (Update.update)
  - view: JSX rendering with dispatch (View.make)
  - subscriptions: event sources (Subs.subscriptions)

The `MakeWithDispatch` functor is used instead of `MakeSimple` because
rescript-tea's Tea_Html has no element constructors — the view uses JSX
directly, which requires a `dispatch` function for event handlers.

## Tea_Router.listen type safety note
cadre-router's `Tea_Router.listen` has a runtime issue: its `%raw` block
passes a raw URL string where `Tea_Url.t` is expected. We bypass it with
a direct `window.addEventListener('popstate', ...)` binding that properly
parses the URL string into a `Tea_Url.t` before dispatching.

## MakeWithDispatch re-export note
`MakeWithDispatch` produces a module with `make: (~flags: unit) => React.element`.
We wrap it in a `@react.component` that calls `AppComponent.make(~flags=())`
so that `Index.res` can use `<App />` without passing flags.
")

// ============================================================================
// Safe popstate listener — bypasses Tea_Router.listen's %raw bug
// ============================================================================

@ocaml.doc("
Browser location bindings for reading the current URL parts.
Used to construct a full URL string on popstate events.
")
module BrowserLocation = {
  @val @scope(("window", "location"))
  external pathname: string = "pathname"

  @val @scope(("window", "location"))
  external search: string = "search"

  @val @scope(("window", "location"))
  external hash: string = "hash"
}

@ocaml.doc("
Register a popstate event listener that fires on browser back/forward.
Unlike `Tea_Router.listen`, this implementation properly parses the
raw URL string into a `Tea_Url.t` before calling the callback,
ensuring type safety at runtime.

This is called once during app init and persists for the app lifetime.
")
@val @scope("window")
external addEventListener: (string, unit => unit) => unit = "addEventListener"

let setupPopstateListener = (onUrlChange: Tea_Url.t => unit): unit => {
  addEventListener("popstate", () => {
    let rawUrl = BrowserLocation.pathname ++ BrowserLocation.search ++ BrowserLocation.hash
    let url = Tea_Url.parse(rawUrl)
    onUrlChange(url)
  })
}

// ============================================================================
// Application module — fed into the MakeWithDispatch functor
// ============================================================================

module AppComponent = Tea_App.MakeWithDispatch({
  type model = Model.t
  type msg = Msg.t
  type flags = unit

  @ocaml.doc("
  Initialize the application:
  1. Read the current browser URL via cadre-router's `Tea_Url.current()`
  2. Parse it into a `Route.t` to determine the initial page
  3. Create the initial model from the route
  4. Return two commands:
     a. Set up the popstate listener (for browser back/forward navigation)
     b. Fire health checks for all registered database engines
  ")
  let init = (_flags: unit): (Model.t, Tea_Cmd.t<Msg.t>) => {
    let currentUrl = Tea_Url.current()
    let route = Route.fromUrl(currentUrl)
    let model = Model.init(route)

    // Command: set up the popstate listener so browser back/forward
    // fires UrlChanged messages through the TEA update loop.
    // Uses our safe wrapper instead of Tea_Router.listen.
    let routerCmd = Tea_Cmd.effect(dispatch => {
      setupPopstateListener(url => dispatch(Msg.UrlChanged(url)))
    })

    // Command: load custom database profiles from /nqc-profiles.json
    let customProfilesCmd = Database.loadCustomProfiles()

    // Command: check health of all databases on startup
    let healthCmd = Api.checkAllHealth()

    (model, Tea_Cmd.batch([routerCmd, customProfilesCmd, healthCmd]))
  }

  @ocaml.doc("Delegate to the pure Update module.")
  let update = Update.update

  @ocaml.doc("Delegate to the View module (receives model + dispatch).")
  let view = View.make

  @ocaml.doc("Delegate to the Subs module.")
  let subscriptions = Subs.subscriptions
})

// ============================================================================
// Public component — re-exported for Index.res
// ============================================================================

@ocaml.doc("
The top-level React component.  Rendered into `#root` by `Index.res`.
Wraps the functor-generated `AppComponent` so consumers can use `<App />`
without needing to pass flags. The `MakeWithDispatch` functor produces
`AppComponent.make({flags: unit})` — this wrapper provides the unit flag.
In ReScript 12, @react.component generates props-record API, not labeled args.
")
@react.component
let make = () => {
  AppComponent.make({flags: ()})
}
