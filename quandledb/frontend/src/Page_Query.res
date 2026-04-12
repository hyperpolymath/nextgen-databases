// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// KRL / SQL query page — textarea editor, dynamic results table, trace panel

// ── Example queries shown as quick-load buttons ───────────────────────────────

let examples = [
  (
    "Trefoil family",
    "from knots\n| filter crossing_number <= 5\n| sort crossing_number asc\n| return name, crossing_number, writhe, jones_polynomial",
  ),
  (
    "Equivalents of 3_1",
    "from knots\n| find_equivalent \"3_1\" via [jones_polynomial]\n| return name, crossing_number",
  ),
  (
    "SQL: figure-eight",
    "SELECT name, crossing_number, writhe\nFROM knots\nWHERE crossing_number = 4\nORDER BY name ASC",
  ),
  (
    "By determinant",
    "from knots\n| filter determinant == 3\n| return name, crossing_number, determinant, signature, alexander_polynomial",
  ),
  (
    "All invariants",
    "from invariants",
  ),
]

// ── Local state ───────────────────────────────────────────────────────────────

type queryPhase =
  | Idle
  | Fetching
  | Done(Types.queryResponse)
  | Failed(Types.queryError)

type state = {
  input: string,
  format: string,
  maxRows: string,
  phase: queryPhase,
  showTrace: bool,
}

type action =
  | SetInput(string)
  | SetFormat(string)
  | SetMaxRows(string)
  | Submit
  | GotOk(Types.queryResponse)
  | GotErr(Types.queryError)
  | ToggleTrace
  | LoadExample(string)

let initialState: state = {
  input: Belt.Array.getExn(examples, 0)->snd,
  format: "auto",
  maxRows: "500",
  phase: Idle,
  showTrace: false,
}

let reducer = (state: state, action: action): state =>
  switch action {
  | SetInput(s)   => {...state, input: s}
  | SetFormat(f)  => {...state, format: f}
  | SetMaxRows(n) => {...state, maxRows: n}
  | Submit        => {...state, phase: Fetching}
  | GotOk(r)      => {...state, phase: Done(r)}
  | GotErr(e)     => {...state, phase: Failed(e)}
  | ToggleTrace   => {...state, showTrace: !state.showTrace}
  | LoadExample(s) => {...state, input: s, phase: Idle}
  }

// ── Helpers ───────────────────────────────────────────────────────────────────

let fmtMs = (n: float): string => {
  let rounded = Js.Math.round(n *. 10.0) /. 10.0
  Js.Float.toString(rounded) ++ "ms"
}

let cellText = (json: Js.Json.t): string => {
  open Js.Json
  switch classify(json) {
  | JSONString(s) => s
  | JSONNumber(n) =>
    if Js.Math.floor_float(n) === n {
      Belt.Int.toString(Belt.Float.toInt(n))
    } else {
      Js.Float.toFixedWithPrecision(n, ~digits=4)
    }
  | JSONTrue  => "true"
  | JSONFalse => "false"
  | JSONNull  => "∅"
  | JSONArray(arr) => "[" ++ Belt.Int.toString(Belt.Array.length(arr)) ++ " items]"
  | JSONObject(_) => "{…}"
  }
}

// Return visible column names from the first row (skip _internal keys)
let getColumns = (rows: array<Js.Json.t>): array<string> => {
  open Js.Json
  switch Belt.Array.get(rows, 0) {
  | None => []
  | Some(first) =>
    switch classify(first) {
    | JSONObject(obj) =>
      Js.Dict.keys(obj)
      ->Belt.Array.keep(k => !Js.String2.startsWith(k, "_"))
    | _ => []
    }
  }
}

let getCellValue = (row: Js.Json.t, col: string): string => {
  open Js.Json
  switch classify(row) {
  | JSONObject(obj) =>
    switch Js.Dict.get(obj, col) {
    | Some(v) => cellText(v)
    | None => ""
    }
  | _ => ""
  }
}

// ── Sub-components ────────────────────────────────────────────────────────────

module StatsBar = {
  @react.component
  let make = (~resp: Types.queryResponse) => {
    let pdBadge =
      resp.pushdownUsed
        ? <span className="badge badge-green"> {React.string("pushdown")} </span>
        : React.null
    let srcBadge =
      <span className="badge badge-blue">
        {React.string(resp.parseSource)}
      </span>

    <div className="query-stats-bar">
      <span className="stats-count">
        {React.string(Belt.Int.toString(resp.count) ++ " row" ++ (resp.count == 1 ? "" : "s"))}
      </span>
      <span className="stats-sep"> {React.string("·")} </span>
      <span className="stats-timing">
        {React.string("parse " ++ fmtMs(resp.parseTimeMs) ++
                       " · eval " ++ fmtMs(resp.evalTimeMs) ++
                       " · total " ++ fmtMs(resp.totalMs))}
      </span>
      <span className="stats-sep"> {React.string("·")} </span>
      {pdBadge}
      {srcBadge}
    </div>
  }
}

module TracePanel = {
  @react.component
  let make = (~trace: array<Types.stageTrace>, ~show: bool, ~onToggle: unit => unit) => {
    let label = show ? "▼ Hide trace" : "▶ Show trace"
    <div className="query-trace-wrapper">
      <button className="trace-toggle" onClick={_ => onToggle()}>
        {React.string(label)}
      </button>
      {if show {
        <table className="query-trace-table">
          <thead>
            <tr>
              <th> {React.string("Stage")} </th>
              <th className="num"> {React.string("In")} </th>
              <th className="num"> {React.string("Out")} </th>
              <th className="num"> {React.string("Time")} </th>
              <th> {React.string("Note")} </th>
            </tr>
          </thead>
          <tbody>
            {trace
            ->Belt.Array.mapWithIndex((i, t) =>
              <tr key={Belt.Int.toString(i)}>
                <td className="stage-name"> {React.string(t.stage)} </td>
                <td className="num"> {React.string(Belt.Int.toString(t.rowsIn))} </td>
                <td className="num"> {React.string(Belt.Int.toString(t.rowsOut))} </td>
                <td className="num"> {React.string(fmtMs(t.elapsedMs))} </td>
                <td className="trace-note"> {React.string(t.note)} </td>
              </tr>
            )
            ->React.array}
          </tbody>
        </table>
      } else {
        React.null
      }}
    </div>
  }
}

module WarningList = {
  @react.component
  let make = (~warnings: array<string>) => {
    if Belt.Array.length(warnings) == 0 {
      React.null
    } else {
      <ul className="query-warnings">
        {warnings
        ->Belt.Array.mapWithIndex((i, w) =>
          <li key={Belt.Int.toString(i)}> {React.string("⚠ " ++ w)} </li>
        )
        ->React.array}
      </ul>
    }
  }
}

module ResultTable = {
  @react.component
  let make = (~resp: Types.queryResponse) => {
    let cols = getColumns(resp.rows)

    if Belt.Array.length(cols) == 0 && Belt.Array.length(resp.rows) == 0 {
      <p className="query-empty"> {React.string("Query returned 0 rows.")} </p>
    } else if Belt.Array.length(cols) == 0 {
      <p className="query-empty"> {React.string("Rows returned but no displayable columns.")} </p>
    } else {
      <div className="query-result-scroll">
        <table className="query-result-table">
          <thead>
            <tr>
              {cols
              ->Belt.Array.map(col => <th key=col> {React.string(col)} </th>)
              ->React.array}
            </tr>
          </thead>
          <tbody>
            {resp.rows
            ->Belt.Array.mapWithIndex((i, row) =>
              <tr key={Belt.Int.toString(i)}>
                {cols
                ->Belt.Array.map(col =>
                  <td key=col> {React.string(getCellValue(row, col))} </td>
                )
                ->React.array}
              </tr>
            )
            ->React.array}
          </tbody>
        </table>
      </div>
    }
  }
}

module ErrorCard = {
  @react.component
  let make = (~err: Types.queryError) => {
    let locStr = switch (err.line, err.col) {
    | (Some(l), Some(c)) => " at line " ++ Belt.Int.toString(l) ++ ", col " ++ Belt.Int.toString(c)
    | (Some(l), None)    => " at line " ++ Belt.Int.toString(l)
    | _ => ""
    }
    let kindLabel = switch err.errorKind {
    | "parse_error"   => "Parse error"
    | "eval_error"    => "Evaluation error"
    | "timeout"       => "Query timeout"
    | "circuit_open"  => "Database unavailable"
    | "network_error" => "Network error"
    | other           => other
    }
    <div className="query-error-card">
      <div className="query-error-kind"> {React.string(kindLabel ++ locStr)} </div>
      <pre className="query-error-message"> {React.string(err.message)} </pre>
    </div>
  }
}

// ── Main component ────────────────────────────────────────────────────────────

@react.component
let make = () => {
  let (state, dispatch) = React.useReducer(reducer, initialState)

  // Fire the fetch whenever phase transitions to Fetching
  React.useEffect1(() => {
    if state.phase == Fetching {
      let maxRows = Belt.Int.fromString(state.maxRows)->Belt.Option.getWithDefault(500)
      let _ = {
        open Promise
        Api.postQuery(~src=state.input, ~format=state.format, ~maxRows)->then(result => {
          switch result {
          | Ok(r)  => dispatch(GotOk(r))
          | Error(e) => dispatch(GotErr(e))
          }
          resolve()
        })
      }
    }
    None
  }, [state.phase])

  let onSubmit = (e: ReactEvent.Form.t) => {
    ReactEvent.Form.preventDefault(e)
    if Js.String2.trim(state.input) != "" {
      dispatch(Submit)
    }
  }

  let onKeyDown = (e: ReactEvent.Keyboard.t) => {
    // Ctrl+Enter or Cmd+Enter runs the query
    let key = ReactEvent.Keyboard.key(e)
    let ctrl = ReactEvent.Keyboard.ctrlKey(e) || ReactEvent.Keyboard.metaKey(e)
    if ctrl && key == "Enter" {
      ReactEvent.Keyboard.preventDefault(e)
      if Js.String2.trim(state.input) != "" {
        dispatch(Submit)
      }
    }
  }

  let isRunning = state.phase == Fetching

  <div className="page-query">
    <div className="query-header">
      <h1> {React.string("Query")} </h1>
      <p className="query-subtitle">
        {React.string("KRL pipeline syntax or SQL SELECT · Ctrl+Enter to run")}
      </p>
    </div>

    <div className="query-examples">
      {examples
      ->Belt.Array.map(((label, src)) =>
        <button
          key=label
          className="example-btn"
          onClick={_ => dispatch(LoadExample(src))}>
          {React.string(label)}
        </button>
      )
      ->React.array}
    </div>

    <form className="query-form" onSubmit>
      <div className="query-editor-area">
        <textarea
          className="query-textarea"
          value={state.input}
          onChange={e => dispatch(SetInput(ReactEvent.Form.target(e)["value"]))}
          onKeyDown
          spellCheck=false
          rows=8
          placeholder="from knots | filter crossing_number == 3 | return *"
        />
      </div>
      <div className="query-controls">
        <div className="control-group">
          <label htmlFor="q-format"> {React.string("Format")} </label>
          <select
            id="q-format"
            value={state.format}
            onChange={e => dispatch(SetFormat(ReactEvent.Form.target(e)["value"]))}>
            <option value="auto"> {React.string("Auto")} </option>
            <option value="krl">  {React.string("KRL")} </option>
            <option value="sql">  {React.string("SQL")} </option>
          </select>
        </div>
        <div className="control-group">
          <label htmlFor="q-maxrows"> {React.string("Max rows")} </label>
          <input
            id="q-maxrows"
            type_="number"
            min="1"
            max="10000"
            value={state.maxRows}
            onChange={e => dispatch(SetMaxRows(ReactEvent.Form.target(e)["value"]))}
          />
        </div>
        <button
          type_="submit"
          className={"btn-primary query-run-btn" ++ (isRunning ? " running" : "")}
          disabled=isRunning>
          {React.string(isRunning ? "Running…" : "▶  Run")}
        </button>
      </div>
    </form>

    <div className="query-results-area">
      {switch state.phase {
      | Idle => React.null

      | Fetching =>
        <div className="query-loading"> {React.string("Running query…")} </div>

      | Failed(err) => <ErrorCard err />

      | Done(resp) =>
        <div className="query-results">
          <StatsBar resp />
          <TracePanel
            trace={resp.trace}
            show={state.showTrace}
            onToggle={() => dispatch(ToggleTrace)}
          />
          <WarningList warnings={resp.warnings} />
          <ResultTable resp />
        </div>
      }}
    </div>
  </div>
}
