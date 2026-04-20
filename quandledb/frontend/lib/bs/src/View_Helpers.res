// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// Shared view components for QuandleDB

module NavBar = {
  @react.component
  let make = (~currentRoute: Route.t, ~onNavigate: Route.t => unit) => {
    let navLink = (route: Route.t, label: string) => {
      let isActive = currentRoute == route
      <a
        href={Route.toPath(route)}
        className={isActive ? "nav-link active" : "nav-link"}
        onClick={e => {
          ReactEvent.Mouse.preventDefault(e)
          onNavigate(route)
        }}>
        {React.string(label)}
      </a>
    }

    <nav className="navbar">
      <div className="navbar-brand">
        <a
          href="/"
          className="brand-link"
          onClick={e => {
            ReactEvent.Mouse.preventDefault(e)
            onNavigate(Route.Dashboard)
          }}>
          {React.string("QuandleDB")}
        </a>
      </div>
      <div className="navbar-links">
        {navLink(Route.Dashboard, "Dashboard")}
        {navLink(Route.KnotList, "Knots")}
        {navLink(Route.Query, "Query")}
      </div>
    </nav>
  }
}

module Loading = {
  @react.component
  let make = () =>
    <div className="loading"> {React.string("Loading...")} </div>
}

module ErrorDisplay = {
  @react.component
  let make = (~message: string) =>
    <div className="error-message"> {React.string(message)} </div>
}

module DistributionTable = {
  @react.component
  let make = (~title: string, ~data: Js.Dict.t<int>) => {
    let entries =
      data
      ->Js.Dict.entries
      ->Belt.SortArray.stableSortBy(((a, _), (b, _)) => compare(a, b))

    <div className="distribution-table">
      <h3> {React.string(title)} </h3>
      <table>
        <thead>
          <tr>
            <th> {React.string("Value")} </th>
            <th> {React.string("Count")} </th>
          </tr>
        </thead>
        <tbody>
          {entries
          ->Belt.Array.map(((key, count)) =>
            <tr key>
              <td> {React.string(key)} </td>
              <td> {React.string(Belt.Int.toString(count))} </td>
            </tr>
          )
          ->React.array}
        </tbody>
      </table>
    </div>
  }
}
