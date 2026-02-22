// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Query page — the interactive query interface at route `/query/:dbId`.
Composed of three vertical sections:
  1. **Editor pane** (top) — the query textarea with Ctrl+Enter submission
  2. **Error banner** (conditional) — dismissible error message
  3. **Results pane** (bottom, scrollable) — table/JSON/CSV output

The layout uses flexbox so the results pane fills remaining vertical space.
CSS classes are defined in `index.html` under `.nqc-query*`.
")

// ============================================================================
// Page component
// ============================================================================

@ocaml.doc("
Render the query page.  Reads the active database from the model
to determine the editor prompt and whether to show an error banner.
If no active database is selected (URL has unknown dbId), shows a
fallback message with a link back to the picker.
")
let make = (~model: Model.t, ~dispatch: Msg.t => unit) => {
  switch model.activeDb {
  | None =>
    // Unknown database ID in the URL — show a helpful error
    <div className="nqc-query">
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          height: "100%",
          color: "#8b949e",
        }}>
        <div style={{fontSize: "18px", marginBottom: "16px"}}>
          {React.string("Database not found.")}
        </div>
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
    </div>

  | Some(db) =>
    <div className="nqc-query">
      // Editor pane — fixed height at top
      <div className="nqc-query__editor-pane">
        // Error banner — shown only when an error exists
        {switch model.error {
        | Some(errMsg) =>
          <div className="nqc-error">
            <span> {React.string(errMsg)} </span>
            <button className="nqc-error__dismiss" onClick={_ => dispatch(Msg.DismissError)}>
              {React.string("\u00D7")}
            </button>
          </div>
        | None => React.null
        }}
        {Editor.make(
          ~query=model.query,
          ~prompt=db.prompt,
          ~keywords=db.keywords,
          ~history=model.history,
          ~dispatch,
        )}
      </div>
      // Results pane — fills remaining vertical space, scrollable
      <div className="nqc-query__results-pane">
        {Results.make(~results=model.results, ~format=model.format)}
      </div>
    </div>
  }
}
