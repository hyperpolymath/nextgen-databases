// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Top navigation header component.
Always visible across all pages.  Contains:
  - Brand logo / link back to picker
  - Active database badge (when on Query page)
  - Connection status indicator
  - Dependent types (DT) toggle switch
  - Output format tabs (Table / JSON / CSV)

The header adapts its content based on the current route:
  - Picker page: just the brand name
  - Query page: full toolbar with db badge, DT toggle, format tabs
  - NotFound: just the brand name

All user interactions dispatch messages via the `dispatch` callback.
CSS classes are defined in `index.html` under `.nqc-header*`.
")

// ============================================================================
// Component
// ============================================================================

@ocaml.doc("
Render the header bar.  Receives the full model for reading state
and a dispatch function for firing messages on user interaction.
")
let make = (~model: Model.t, ~dispatch: Msg.t => unit) => {
  <header className="nqc-header">
    // Brand — clicking navigates back to the picker
    <a
      className="nqc-header__brand"
      href="/"
      onClick={e => {
        ReactEvent.Mouse.preventDefault(e)
        dispatch(Msg.NavigateTo("/"))
      }}>
      {React.string("NQC")}
      <span style={{color: "#8b949e", fontWeight: "400", fontSize: "13px"}}>
        {React.string("NextGen Query Client")}
      </span>
    </a>
    // Right-side navigation — only shown on the Query page
    <nav className="nqc-header__nav">
      {switch model.activeDb {
      | Some(db) =>
        <>
          // Database badge — shows language name + connection health
          <span className="nqc-header__db-badge"> {React.string(db.languageName)} </span>
          {Status.make(~state=model.connection, ~showLabel=true)}
          // Dependent types toggle
          {if db.supportsDt {
            <div
              className={"nqc-toggle" ++ if model.dtEnabled { " nqc-toggle--active" } else { "" }}
              onClick={_ => dispatch(Msg.ToggleDt)}>
              <span className="nqc-toggle__switch" />
              <span> {React.string("DT")} </span>
              {if model.dtEnabled {
                <span className="nqc-dt-badge"> {React.string("on")} </span>
              } else {
                React.null
              }}
            </div>
          } else {
            React.null
          }}
          // Format tabs — Table | JSON | CSV
          <div className="nqc-format-tabs">
            {[Msg.Table, Msg.Json, Msg.Csv]
            ->Array.map(fmt => {
              let label = switch fmt {
              | Msg.Table => "Table"
              | Msg.Json => "JSON"
              | Msg.Csv => "CSV"
              }
              let isActive = model.format == fmt
              <button
                key={label}
                className={"nqc-format-tab" ++ if isActive { " nqc-format-tab--active" } else { "" }}
                onClick={_ => dispatch(Msg.SetFormat(fmt))}>
                {React.string(label)}
              </button>
            })
            ->React.array}
          </div>
        </>
      | None => React.null
      }}
    </nav>
  </header>
}
