// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// Dashboard page — statistics overview

@react.component
let make = (~stats: Types.remoteData<Types.statistics, string>, ~onNavigate: Route.t => unit) => {
  <div className="page-dashboard">
    <h1> {React.string("QuandleDB")} </h1>
    <p className="subtitle">
      {React.string("A knot-theory database powered by Skein.jl")}
    </p>
    {switch stats {
    | NotAsked => <View_Helpers.Loading />
    | Loading => <View_Helpers.Loading />
    | Failure(err) => <View_Helpers.ErrorDisplay message=err />
    | Success(s) =>
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-value"> {React.string(Belt.Int.toString(s.totalKnots))} </div>
          <div className="stat-label"> {React.string("Total Knots")} </div>
        </div>
        <div className="stat-card">
          <div className="stat-value">
            {React.string(
              switch s.minCrossings {
              | Some(n) => Belt.Int.toString(n)
              | None => "-"
              },
            )}
          </div>
          <div className="stat-label"> {React.string("Min Crossings")} </div>
        </div>
        <div className="stat-card">
          <div className="stat-value">
            {React.string(
              switch s.maxCrossings {
              | Some(n) => Belt.Int.toString(n)
              | None => "-"
              },
            )}
          </div>
          <div className="stat-label"> {React.string("Max Crossings")} </div>
        </div>
        <div className="stat-card">
          <div className="stat-value">
            {React.string(Belt.Int.toString(s.schemaVersion))}
          </div>
          <div className="stat-label"> {React.string("Schema Version")} </div>
        </div>
        <View_Helpers.DistributionTable
          title="Crossing Number Distribution" data={s.crossingDistribution}
        />
        <View_Helpers.DistributionTable
          title="Genus Distribution" data={s.genusDistribution}
        />
        <div className="actions">
          <button
            className="btn-primary"
            onClick={_ => onNavigate(Route.KnotList)}>
            {React.string("Browse Knots")}
          </button>
        </div>
      </div>
    }}
  </div>
}
