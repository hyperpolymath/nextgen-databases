// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Query editor component for the NQC Web UI.
Renders a resizable textarea for composing queries, a submit button,
a keyword hint ribbon showing the database's query language keywords,
and a hint bar showing the Ctrl+Enter keyboard shortcut.

Features:
  - Ctrl+Enter submits the query (standard REPL ergonomics)
  - Placeholder text adapts to the selected database's prompt string
  - Submit button is disabled when the textarea is empty
  - Session query history dropdown for recalling past queries
  - Keyword ribbon showing available query language keywords
    (clicking a keyword inserts it at the cursor / appends to query)

The textarea uses monospace font to match terminal aesthetics.
CSS classes are defined in `index.html` under `.nqc-editor*`.
")

// ============================================================================
// Component
// ============================================================================

@ocaml.doc("
Render the query editor.
`query`    — current textarea content (controlled component)
`prompt`   — database-specific placeholder (e.g. 'vql> ')
`keywords` — array of query language keywords for hint ribbon
`history`  — session query history for the recall dropdown
`dispatch` — TEA message dispatcher
")
let make = (
  ~query: string,
  ~prompt: string,
  ~keywords: array<string>,
  ~history: array<Msg.historyEntry>,
  ~dispatch: Msg.t => unit,
) => {
  let isEmpty = query->String.trim->String.length == 0

  <div className="nqc-editor">
    // Textarea — the main query input area
    <textarea
      className="nqc-editor__textarea"
      value={query}
      placeholder={prompt ++ "Enter your query here..."}
      onChange={e => {
        let value = ReactEvent.Form.target(e)["value"]
        dispatch(Msg.UpdateQuery(value))
      }}
      onKeyDown={e => {
        // Ctrl+Enter or Cmd+Enter submits the query
        let key = ReactEvent.Keyboard.key(e)
        let ctrl = ReactEvent.Keyboard.ctrlKey(e) || ReactEvent.Keyboard.metaKey(e)
        if key == "Enter" && ctrl {
          ReactEvent.Keyboard.preventDefault(e)
          dispatch(Msg.SubmitQuery)
        }
      }}
    />
    // Keyword ribbon — clickable keyword hints from the database profile
    {if Array.length(keywords) > 0 {
      <div className="nqc-keywords">
        {keywords
        ->Array.map(kw => {
          <span
            key={kw}
            className="nqc-keywords__chip"
            onClick={_ => {
              // Append keyword to query with a trailing space
              let sep = if query->String.length > 0 && !(query->String.endsWith(" ")) {
                " "
              } else {
                ""
              }
              dispatch(Msg.UpdateQuery(query ++ sep ++ kw ++ " "))
            }}>
            {React.string(kw)}
          </span>
        })
        ->React.array}
      </div>
    } else {
      React.null
    }}
    // Bottom bar — hint text + history dropdown + submit button
    <div className="nqc-editor__bar">
      <div style={{display: "flex", alignItems: "center", gap: "16px"}}>
        <span className="nqc-editor__hint">
          {React.string("Ctrl+Enter to execute")}
        </span>
        // Query history dropdown — only shown if there are past queries
        {if Array.length(history) > 0 {
          <div className="nqc-history">
            <details>
              <summary
                style={{
                  fontSize: "12px",
                  color: "#8b949e",
                  cursor: "pointer",
                  fontFamily: "var(--font-mono)",
                }}>
                {React.string(`History (${Int.toString(Array.length(history))})`)}
              </summary>
              <ul className="nqc-history__list">
                {history
                ->Array.mapWithIndex((entry, idx) => {
                  // Truncate long queries for display
                  let display = if String.length(entry.query) > 60 {
                    String.slice(entry.query, ~start=0, ~end=57) ++ "..."
                  } else {
                    entry.query
                  }
                  <li
                    key={Int.toString(idx)}
                    className="nqc-history__item"
                    onClick={_ => dispatch(Msg.HistorySelect(idx))}>
                    {React.string(display)}
                  </li>
                })
                ->React.array}
              </ul>
            </details>
          </div>
        } else {
          React.null
        }}
      </div>
      // Submit button
      <button
        className="nqc-editor__submit"
        disabled={isEmpty}
        onClick={_ => dispatch(Msg.SubmitQuery)}>
        {React.string("Execute")}
      </button>
    </div>
  </div>
}
