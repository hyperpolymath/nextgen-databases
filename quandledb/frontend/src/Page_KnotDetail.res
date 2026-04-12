// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// Knot detail page — single knot with all invariants

@react.component
let make = (
  ~knot: Types.remoteData<Types.knot, string>,
  ~onNavigate: Route.t => unit,
) => {
  let renderField = (label: string, value: string) =>
    <tr>
      <th> {React.string(label)} </th>
      <td> {React.string(value)} </td>
    </tr>

  let renderOptField = (label: string, value: option<string>) =>
    <tr>
      <th> {React.string(label)} </th>
      <td>
        {React.string(
          switch value {
          | Some(v) => v
          | None => "-"
          },
        )}
      </td>
    </tr>

  <div className="page-knot-detail">
    <button className="btn-back" onClick={_ => onNavigate(Route.KnotList)}>
      {React.string("Back to List")}
    </button>
    {switch knot {
    | NotAsked => <View_Helpers.Loading />
    | Loading => <View_Helpers.Loading />
    | Failure(err) => <View_Helpers.ErrorDisplay message=err />
    | Success(k) =>
      <div>
        <h1> {React.string("Knot " ++ k.name)} </h1>
        <div className="knot-detail-grid">
          <div className="detail-section">
            <h2> {React.string("Invariants")} </h2>
            <table className="detail-table">
              <tbody>
                {renderField("Name", k.name)}
                {renderField("Crossing Number", Belt.Int.toString(k.crossingNumber))}
                {renderField("Writhe", Belt.Int.toString(k.writhe))}
                {renderOptField(
                  "Genus",
                  k.genus->Belt.Option.map(Belt.Int.toString),
                )}
                {renderOptField(
                  "Seifert Circles",
                  k.seifertCircleCount->Belt.Option.map(Belt.Int.toString),
                )}
                {renderOptField(
                  "Determinant",
                  k.determinant->Belt.Option.map(Belt.Int.toString),
                )}
                {renderOptField(
                  "Signature",
                  k.signature->Belt.Option.map(Belt.Int.toString),
                )}
                {renderOptField("Alexander Polynomial", k.alexanderDisplay)}
                {renderOptField("Jones Polynomial", k.jonesDisplay)}
                {renderOptField("HOMFLY-PT", k.homflyPolynomial)}
              </tbody>
            </table>
          </div>
          <div className="detail-section">
            <h2> {React.string("Gauss Code")} </h2>
            <code className="gauss-code">
              {React.string(
                "[" ++
                k.gaussCode
                ->Belt.Array.map(Belt.Int.toString)
                ->Js.Array2.joinWith(", ") ++
                "]",
              )}
            </code>
          </div>
          {if Js.Dict.keys(k.metadata)->Belt.Array.length > 0 {
            <div className="detail-section">
              <h2> {React.string("Metadata")} </h2>
              <table className="detail-table">
                <tbody>
                  {k.metadata
                  ->Js.Dict.entries
                  ->Belt.Array.map(((key, value)) =>
                    <tr key>
                      <th> {React.string(key)} </th>
                      <td> {React.string(value)} </td>
                    </tr>
                  )
                  ->React.array}
                </tbody>
              </table>
            </div>
          } else {
            React.null
          }}
          <div className="detail-section detail-meta">
            <p className="meta-text">
              {React.string("Created: " ++ k.createdAt)}
            </p>
            <p className="meta-text">
              {React.string("Updated: " ++ k.updatedAt)}
            </p>
          </div>
        </div>
      </div>
    }}
  </div>
}
