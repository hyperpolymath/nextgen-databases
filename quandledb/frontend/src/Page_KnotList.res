// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// Knot list page — filterable table

@react.component
let make = (
  ~knots: Types.remoteData<Types.knotListResponse, string>,
  ~filters: Types.filters,
  ~onFilterChange: Types.filters => unit,
  ~onNavigate: Route.t => unit,
) => {
  let onCrossingChange = (e: ReactEvent.Form.t) => {
    let value = ReactEvent.Form.target(e)["value"]
    let cn = if value == "" {
      None
    } else {
      Belt.Int.fromString(value)
    }
    onFilterChange({...filters, crossingNumber: cn})
  }

  let onGenusChange = (e: ReactEvent.Form.t) => {
    let value = ReactEvent.Form.target(e)["value"]
    let g = if value == "" {
      None
    } else {
      Belt.Int.fromString(value)
    }
    onFilterChange({...filters, genus: g})
  }

  let onNameChange = (e: ReactEvent.Form.t) => {
    let value = ReactEvent.Form.target(e)["value"]
    onFilterChange({...filters, nameSearch: value})
  }

  <div className="page-knot-list">
    <h1> {React.string("Knot Database")} </h1>
    <div className="filters">
      <div className="filter-group">
        <label htmlFor="filter-crossing"> {React.string("Crossing Number")} </label>
        <select
          id="filter-crossing"
          value={switch filters.crossingNumber {
          | Some(n) => Belt.Int.toString(n)
          | None => ""
          }}
          onChange=onCrossingChange>
          <option value=""> {React.string("All")} </option>
          {Belt.Array.range(0, 10)
          ->Belt.Array.map(n => {
            let s = Belt.Int.toString(n)
            <option key=s value=s> {React.string(s)} </option>
          })
          ->React.array}
        </select>
      </div>
      <div className="filter-group">
        <label htmlFor="filter-genus"> {React.string("Genus")} </label>
        <select
          id="filter-genus"
          value={switch filters.genus {
          | Some(n) => Belt.Int.toString(n)
          | None => ""
          }}
          onChange=onGenusChange>
          <option value=""> {React.string("All")} </option>
          {Belt.Array.range(0, 5)
          ->Belt.Array.map(n => {
            let s = Belt.Int.toString(n)
            <option key=s value=s> {React.string(s)} </option>
          })
          ->React.array}
        </select>
      </div>
      <div className="filter-group">
        <label htmlFor="filter-name"> {React.string("Name")} </label>
        <input
          id="filter-name"
          type_="text"
          placeholder="e.g. 3_1"
          value={filters.nameSearch}
          onChange=onNameChange
        />
      </div>
    </div>
    {switch knots {
    | NotAsked => <View_Helpers.Loading />
    | Loading => <View_Helpers.Loading />
    | Failure(err) => <View_Helpers.ErrorDisplay message=err />
    | Success(resp) =>
      <div>
        <p className="result-count">
          {React.string(Belt.Int.toString(resp.count) ++ " knots")}
        </p>
        <table className="knot-table">
          <thead>
            <tr>
              <th> {React.string("Name")} </th>
              <th> {React.string("Crossings")} </th>
              <th> {React.string("Writhe")} </th>
              <th> {React.string("Genus")} </th>
              <th> {React.string("Seifert Circles")} </th>
              <th> {React.string("Jones Polynomial")} </th>
            </tr>
          </thead>
          <tbody>
            {resp.knots
            ->Belt.Array.map(knot =>
              <tr
                key={knot.name}
                className="knot-row clickable"
                onClick={_ => onNavigate(Route.KnotDetail(knot.name))}>
                <td className="knot-name"> {React.string(knot.name)} </td>
                <td> {React.string(Belt.Int.toString(knot.crossingNumber))} </td>
                <td> {React.string(Belt.Int.toString(knot.writhe))} </td>
                <td>
                  {React.string(
                    switch knot.genus {
                    | Some(g) => Belt.Int.toString(g)
                    | None => "-"
                    },
                  )}
                </td>
                <td>
                  {React.string(
                    switch knot.seifertCircleCount {
                    | Some(s) => Belt.Int.toString(s)
                    | None => "-"
                    },
                  )}
                </td>
                <td className="jones">
                  {React.string(
                    switch knot.jonesDisplay {
                    | Some(j) => j
                    | None => "-"
                    },
                  )}
                </td>
              </tr>
            )
            ->React.array}
          </tbody>
        </table>
      </div>
    }}
  </div>
}
