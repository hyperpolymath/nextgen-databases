// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Top-level view function for the NQC Web UI.
Dispatches to the appropriate page component based on the current route.
The Header is always rendered; the page content below it changes by route.

Route dispatch:
  `/`             → Picker page (database card grid)
  `/query/:dbId`  → Query page (editor + results)
  `*`             → 404 Not Found page
")

// ============================================================================
// View function — called by the TEA runtime on every model change
// ============================================================================

@ocaml.doc("
Render the full application UI from the current model.
`dispatch` is provided by `Tea_App.MakeWithDispatch` for event handling.

Structure:
  <div id='app-root'>
    <Header />
    <main>  -- route-dependent page content --  </main>
  </div>
")
let make = (model: Model.t, dispatch: Msg.t => unit): React.element => {
  <div>
    // Header — always visible on all pages
    {Header.make(~model, ~dispatch)}
    // Page content — determined by route
    {switch model.route {
    | Route.Picker => Picker.make(~model, ~dispatch)
    | Route.Query(_) => Query.make(~model, ~dispatch)
    | Route.NotFound =>
      <div className="nqc-notfound">
        <div className="nqc-notfound__code"> {React.string("404")} </div>
        <div> {React.string("Page not found")} </div>
        <a
          className="nqc-notfound__link"
          href="/"
          onClick={e => {
            ReactEvent.Mouse.preventDefault(e)
            dispatch(Msg.NavigateTo("/"))
          }}>
          {React.string("Back to database picker")}
        </a>
      </div>
    }}
  </div>
}
