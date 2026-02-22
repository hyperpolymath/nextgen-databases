// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Message type for the NQC Web UI TEA application.
Every user interaction and asynchronous result is modelled as a variant
of this type, ensuring the update function is the single place where
state transitions occur.
")

// ============================================================================
// Output format — how query results are rendered
// ============================================================================

@ocaml.doc("Result rendering format, matching the Gleam `OutputFormat` type.")
type outputFormat =
  | Table
  | Json
  | Csv

@ocaml.doc("Convert output format to its lowercase string key for URL serialization.")
let formatToString = (fmt: outputFormat): string =>
  switch fmt {
  | Table => "table"
  | Json => "json"
  | Csv => "csv"
  }

@ocaml.doc("Parse a string into an output format, defaulting to `Table`.")
let formatFromString = (s: string): outputFormat =>
  switch s->String.toLowerCase {
  | "json" => Json
  | "csv" => Csv
  | _ => Table
  }

// ============================================================================
// Connection state — tracks health-check / handshake lifecycle
// ============================================================================

@ocaml.doc("
Connection state for the currently selected database.
The status indicator dot colour maps directly to these variants.
")
type connectionState =
  | Disconnected
  | Connecting
  | Connected
  | ConnectionError(string)

// ============================================================================
// History entry — records past queries for the session
// ============================================================================

@ocaml.doc("A single entry in the in-memory query history ring buffer.")
type historyEntry = {
  query: string,
  dbId: string,
  timestamp: float,
}

// ============================================================================
// Message type — exhaustive set of application events
// ============================================================================

@ocaml.doc("
All events that can occur in the NQC Web UI.  Each variant maps to
a handler branch in `Update.update`.  Async results arrive as `Ok`/`Error`
wrapped in the appropriate result message.
")
type t =
  // --- Routing ---
  | @ocaml.doc("Browser URL changed (popstate event from cadre-router)") UrlChanged(Tea_Url.t)
  | @ocaml.doc("Programmatic navigation request (e.g. clicking a card or link)") NavigateTo(string)
  // --- Database selection ---
  | @ocaml.doc("User selected a database from the picker grid") SelectDatabase(string)
  // --- Query editing ---
  | @ocaml.doc("Query textarea content changed") UpdateQuery(string)
  | @ocaml.doc("User submitted the current query (button click or Ctrl+Enter)") SubmitQuery
  | @ocaml.doc("Server responded to a query execution request") QueryResult(result<JSON.t, Tea_Http.httpError>)
  // --- Health checks ---
  | @ocaml.doc("Server responded to a health check for a given database id") HealthResult(string, result<string, Tea_Http.httpError>)
  // --- UI controls ---
  | @ocaml.doc("User changed the result output format") SetFormat(outputFormat)
  | @ocaml.doc("User toggled dependent types on/off") ToggleDt
  | @ocaml.doc("User dismissed the current results") ClearResults
  | @ocaml.doc("User selected a query from the history list") HistorySelect(int)
  | @ocaml.doc("Dismiss the error banner") DismissError
