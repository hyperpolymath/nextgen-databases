// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Query result renderer for the NQC Web UI.
Displays query output in one of three formats:
  - **Table** — auto-detected columns from first result row, rendered as `<table>`
  - **JSON**  — pretty-printed JSON in a `<pre>` block
  - **CSV**   — comma-separated values in a `<pre>` block

The rendering logic mirrors the Gleam `formatter.gleam` module but produces
React elements instead of terminal strings.  Each database engine returns
different JSON shapes, so the renderer handles:
  - Array of objects  → table with object keys as columns
  - Array of arrays   → table with numeric column indices
  - Single object     → key-value pair table
  - Scalar / other    → JSON fallback

CSS classes are defined in `index.html` under `.nqc-results*`.
")

// ============================================================================
// Internal helpers
// ============================================================================

@ocaml.doc("
Attempt to extract an array of JSON objects from the raw response.
Database engines may wrap results in various envelopes:
  {\"rows\": [...]}  or  {\"data\": [...]}  or  {\"results\": [...]}
  or just a bare array  [...]
Returns the inner array if found, otherwise wraps the value in a singleton array.

Classified JSON is matched exhaustively against all `JSON.Classify.t` variants
to avoid fragile pattern-matching warnings.
")
let extractRows = (json: JSON.t): array<JSON.t> => {
  // Helper: check if a JSON value is an array, return its elements or fallback
  let asArrayOr = (value: JSON.t, fallback: array<JSON.t>): array<JSON.t> =>
    switch JSON.Classify.classify(value) {
    | Array(arr) => arr
    | Bool(_) | Null | String(_) | Number(_) | Object(_) => fallback
    }

  switch JSON.Classify.classify(json) {
  | Array(arr) => arr
  | Object(dict) =>
    // Try common envelope keys in precedence order
    switch Dict.get(dict, "rows") {
    | Some(rows) => asArrayOr(rows, [json])
    | None =>
      switch Dict.get(dict, "data") {
      | Some(data) => asArrayOr(data, [json])
      | None =>
        switch Dict.get(dict, "results") {
        | Some(results) => asArrayOr(results, [json])
        | None => [json]
        }
      }
    }
  | Bool(_) | Null | String(_) | Number(_) => [json]
  }
}

@ocaml.doc("
Extract column names from the first row of results.
If the first row is an object, its keys become column headers.
If it's an array, column headers are zero-indexed numbers.
Otherwise returns a single 'value' column.
")
let extractColumns = (rows: array<JSON.t>): array<string> => {
  switch rows->Array.get(0) {
  | Some(firstRow) =>
    switch JSON.Classify.classify(firstRow) {
    | Object(dict) => Dict.keysToArray(dict)
    | Array(arr) =>
      Array.fromInitializer(~length=Array.length(arr), i => Int.toString(i))
    | Bool(_) | Null | String(_) | Number(_) => ["value"]
    }
  | None => []
  }
}

@ocaml.doc("
Convert a single JSON value to a display string.
Handles each classified variant explicitly:
- Strings and numbers are rendered directly
- Booleans become 'true'/'false', null becomes 'null'
- Objects and arrays are JSON-stringified as fallback
")
let jsonToString = (v: JSON.t): string =>
  switch JSON.Classify.classify(v) {
  | String(s) => s
  | Number(n) => Float.toString(n)
  | Bool(true) => "true"
  | Bool(false) => "false"
  | Null => "null"
  | Object(_) | Array(_) => JSON.stringify(v)
  }

@ocaml.doc("
Extract a cell value from a row as a display string.
Handles nested JSON by stringifying complex values.
")
let cellValue = (row: JSON.t, column: string): string => {
  switch JSON.Classify.classify(row) {
  | Object(dict) =>
    switch Dict.get(dict, column) {
    | Some(v) => jsonToString(v)
    | None => ""
    }
  | Array(arr) =>
    // For array rows, column is a numeric index
    switch Int.fromString(column) {
    | Some(idx) =>
      switch arr->Array.get(idx) {
      | Some(v) => jsonToString(v)
      | None => ""
      }
    | None => ""
    }
  | String(s) => s
  | Number(n) => Float.toString(n)
  | Bool(true) => "true"
  | Bool(false) => "false"
  | Null => "null"
  }
}

// ============================================================================
// Table renderer
// ============================================================================

@ocaml.doc("Render results as an HTML table with auto-detected columns.")
let renderTable = (json: JSON.t): React.element => {
  let rows = extractRows(json)
  let columns = extractColumns(rows)

  if Array.length(rows) == 0 {
    <div className="nqc-results__empty">
      {React.string("Query returned no results.")}
    </div>
  } else {
    <table className="nqc-results__table">
      <thead>
        <tr>
          {columns
          ->Array.map(col => <th key={col}> {React.string(col)} </th>)
          ->React.array}
        </tr>
      </thead>
      <tbody>
        {rows
        ->Array.mapWithIndex((row, rowIdx) =>
          <tr key={Int.toString(rowIdx)}>
            {columns
            ->Array.map(col =>
              <td key={col}> {React.string(cellValue(row, col))} </td>
            )
            ->React.array}
          </tr>
        )
        ->React.array}
      </tbody>
    </table>
  }
}

// ============================================================================
// JSON renderer
// ============================================================================

@ocaml.doc("Render results as pretty-printed JSON in a pre block.")
let renderJson = (json: JSON.t): React.element => {
  let formatted = switch JSON.stringify(json, ~space=2) {
  | s => s
  | exception _ => "Failed to format JSON"
  }
  <pre className="nqc-results__pre"> {React.string(formatted)} </pre>
}

// ============================================================================
// CSV renderer
// ============================================================================

@ocaml.doc("
Render results as CSV text in a pre block.
First line is the column header row; subsequent lines are data rows.
Values containing commas or quotes are double-quote escaped per RFC 4180.
")
let renderCsv = (json: JSON.t): React.element => {
  let rows = extractRows(json)
  let columns = extractColumns(rows)

  // RFC 4180 escaping — wrap in quotes if the value contains comma, quote, or newline
  let escapeCell = (value: string): string => {
    if (
      value->String.includes(",") ||
      value->String.includes("\"") ||
      value->String.includes("\n")
    ) {
      "\"" ++ value->String.replaceAll("\"", "\"\"") ++ "\""
    } else {
      value
    }
  }

  let headerLine = columns->Array.map(escapeCell)->Array.join(",")
  let dataLines = rows->Array.map(row => {
    columns->Array.map(col => escapeCell(cellValue(row, col)))->Array.join(",")
  })
  let csvText = Array.concat([headerLine], dataLines)->Array.join("\n")

  <pre className="nqc-results__pre"> {React.string(csvText)} </pre>
}

// ============================================================================
// Public API — dispatches to the correct renderer
// ============================================================================

@ocaml.doc("
Render query results in the specified format.
If no results are available, shows an empty-state placeholder.
")
let make = (~results: option<JSON.t>, ~format: Msg.outputFormat) => {
  switch results {
  | None =>
    <div className="nqc-results__empty">
      <div> {React.string("No results yet.")} </div>
      <div style={{marginTop: "8px", fontSize: "13px"}}>
        {React.string("Write a query above and press Ctrl+Enter to execute.")}
      </div>
    </div>
  | Some(json) =>
    switch format {
    | Msg.Table => renderTable(json)
    | Msg.Json => renderJson(json)
    | Msg.Csv => renderCsv(json)
    }
  }
}
