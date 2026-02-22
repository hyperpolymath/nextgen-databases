// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Database picker page — the landing page at route `/`.
Displays a responsive grid of database cards, one per registered profile.
Each card shows the engine name, query language, description, port,
and a live health-status dot.  Clicking a card navigates to the
Query page for that database (`/query/:dbId`).

Layout: centered title + subtitle, then a CSS Grid of cards.
Grid is responsive via `auto-fit` with a 280px minimum column width.
CSS classes are defined in `index.html` under `.nqc-picker*` and `.nqc-card*`.
")

// ============================================================================
// Single database card
// ============================================================================

@ocaml.doc("
Render a single database card.
`profile` — the database profile to display
`healthState` — connection health for this database (from model.healthMap)
`dispatch` — TEA message dispatcher for handling clicks
")
let renderCard = (
  ~profile: Database.profile,
  ~healthState: Msg.connectionState,
  ~dispatch: Msg.t => unit,
) => {
  <div
    key={profile.id}
    className="nqc-card"
    onClick={_ => dispatch(Msg.SelectDatabase(profile.id))}>
    <div className="nqc-card__header">
      <span className="nqc-card__name"> {React.string(profile.displayName)} </span>
      <span className="nqc-card__lang"> {React.string(profile.languageName)} </span>
    </div>
    <div className="nqc-card__desc"> {React.string(profile.description)} </div>
    <div className="nqc-card__footer">
      <span className="nqc-card__port">
        {React.string(":" ++ Int.toString(profile.defaultPort))}
      </span>
      {Status.make(~state=healthState, ~showLabel=false)}
    </div>
  </div>
}

// ============================================================================
// Page component
// ============================================================================

@ocaml.doc("
Render the full picker page.
Iterates over all database profiles and renders a card for each,
looking up per-database health state from the model's healthMap.
")
let make = (~model: Model.t, ~dispatch: Msg.t => unit) => {
  <div className="nqc-picker">
    <h1 className="nqc-picker__title"> {React.string("NextGen Query Client")} </h1>
    <p className="nqc-picker__subtitle">
      {React.string("Select a database engine to start querying.")}
    </p>
    <div className="nqc-picker__grid">
      {model.databases
      ->Array.map(db => {
        let healthState =
          model.healthMap->Dict.get(db.id)->Option.getOr(Msg.Disconnected)
        renderCard(~profile=db, ~healthState, ~dispatch)
      })
      ->React.array}
    </div>
  </div>
}
