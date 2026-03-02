// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Playground — main application entry point.
// Wires up the editor, VQL-DT toggle, linter, formatter, and query executor.
// Tries the real verisim-api backend first, falls back to demo mode.

// === DOM helpers ===

@val external document: {..} = "document"

let getElementById = (id: string): {..} => document["getElementById"](id)
let addEventListener = (el: {..}, event: string, handler: {..} => unit): unit =>
  el["addEventListener"](event, handler)

// === State ===

let vqlDtMode = ref(false)
let backendConnected = ref(false)
let queryInFlight = ref(false)

// === Initialization ===

let rec init = () => {
  let editor = getElementById("editor")
  let output = getElementById("output")
  let lintBar = getElementById("lint-bar")
  let charCount = getElementById("char-count")
  let modeBadge = getElementById("mode-badge")
  let statusMode = getElementById("status-mode")
  let statusBar = getElementById("status-bar")
  let statusConnection = getElementById("status-connection")
  let toggle = getElementById("vql-dt-toggle")

  // === Check backend connectivity ===
  checkBackend(statusConnection)->ignore

  // === VQL-DT Toggle ===
  let updateMode = () => {
    if vqlDtMode.contents {
      toggle["classList"]["add"]("active")->ignore
      modeBadge["className"] = "mode-badge vql-dt"
      modeBadge["textContent"] = "VQL-DT"
      statusMode["textContent"] = "Mode: VQL-DT (Dependent Types)"
      statusBar["classList"]["add"]("vql-dt")->ignore
    } else {
      toggle["classList"]["remove"]("active")->ignore
      modeBadge["className"] = "mode-badge vql"
      modeBadge["textContent"] = "VQL"
      statusMode["textContent"] = "Mode: VQL"
      statusBar["classList"]["remove"]("vql-dt")->ignore
    }
  }

  addEventListener(toggle, "click", _ => {
    vqlDtMode := !vqlDtMode.contents
    updateMode()->ignore
    // Re-lint current query
    let query = editor["value"]
    if String.trim(query) !== "" {
      runLint(query, lintBar)
    }
  })

  // Keyboard accessibility for toggle
  addEventListener(toggle, "keydown", e => {
    let key: string = e["key"]
    if key == " " || key == "Enter" {
      e["preventDefault"]()
      vqlDtMode := !vqlDtMode.contents
      updateMode()
    }
  })

  // === Editor events ===
  addEventListener(editor, "input", _ => {
    let query: string = editor["value"]
    let len = String.length(query)
    charCount["textContent"] = `${Int.toString(len)} chars`

    // Live lint
    if String.trim(query) !== "" {
      runLint(query, lintBar)
    } else {
      lintBar["textContent"] = "Ready"
      lintBar["className"] = "lint-bar"
    }
  })

  // Ctrl+Enter to run
  addEventListener(editor, "keydown", e => {
    let key: string = e["key"]
    let ctrlKey: bool = e["ctrlKey"]
    let metaKey: bool = e["metaKey"]
    if key == "Enter" && (ctrlKey || metaKey) {
      e["preventDefault"]()
      runQuery(editor, output)
    }
    // Tab inserts spaces
    if key == "Tab" {
      e["preventDefault"]()
      // Insert 2 spaces at cursor
      let start: int = editor["selectionStart"]
      let endd: int = editor["selectionEnd"]
      let value: string = editor["value"]
      editor["value"] =
        String.slice(value, ~start=0, ~end=start) ++ "  " ++ String.sliceToEnd(value, ~start=endd)
      editor["selectionStart"] = start + 2
      editor["selectionEnd"] = start + 2
    }
  })

  // === Button handlers ===
  addEventListener(getElementById("run-btn"), "click", _ => {
    runQuery(editor, output)
  })

  addEventListener(getElementById("explain-btn"), "click", _ => {
    let query: string = editor["value"]
    if String.trim(query) !== "" {
      let explainQuery = if String.includes(String.toUpperCase(query), "EXPLAIN") {
        query
      } else {
        "EXPLAIN " ++ query
      }
      executeAndDisplay(explainQuery, output)
    }
  })

  addEventListener(getElementById("lint-btn"), "click", _ => {
    let query: string = editor["value"]
    if String.trim(query) !== "" {
      let diagnostics = Linter.lint(query, ~vqlDt=vqlDtMode.contents)
      if Array.length(diagnostics) == 0 {
        output["innerHTML"] = `<span class="output-success">No lint issues found.</span>`
      } else {
        let html =
          diagnostics
          ->Array.map(d => {
            let cls = switch d.severity {
            | Linter.Error => "output-error"
            | Linter.Warning => "output-warning"
            | Linter.Hint => "output-info"
            }
            `<span class="${cls}">[${d.code}] ${Linter.severityToString(d.severity)}: ${d.message}</span>`
          })
          ->Array.join("\n")
        output["innerHTML"] = html
      }
    }
  })

  addEventListener(getElementById("format-btn"), "click", _ => {
    let query: string = editor["value"]
    if String.trim(query) !== "" {
      editor["value"] = Formatter.formatVql(query)
      // Trigger input event to update char count
      let inputEvent = document["createEvent"]("Event")
      inputEvent["initEvent"]("input", true, true)->ignore
      editor["dispatchEvent"](inputEvent)->ignore
    }
  })

  addEventListener(getElementById("clear-btn"), "click", _ => {
    editor["value"] = ""
    output["innerHTML"] = `<span class="output-info">Output cleared.</span>`
    lintBar["textContent"] = "Ready"
    charCount["textContent"] = "0 chars"
  })

  addEventListener(getElementById("examples-btn"), "click", _ => {
    let exs = Examples.forMode(vqlDtMode.contents)
    let html =
      exs
      ->Array.map(ex => {
        let escaped = String.replaceAll(String.replaceAll(ex.query, "<", "&lt;"), ">", "&gt;")
        let dtBadge = if ex.vqlDt {
          ` <span class="mode-badge vql-dt" style="font-size:0.65rem">DT</span>`
        } else {
          ""
        }
        `<div class="example-query" data-query="${String.replaceAll(ex.query, "\"", "&quot;")}">
        <div class="example-label">${ex.label}${dtBadge}</div>
        <code>${escaped}</code>
      </div>`
      })
      ->Array.join("")

    output["innerHTML"] = `<div class="examples-drawer">${html}</div>`

    // Add click handlers to examples
    let exampleEls = output["querySelectorAll"](".example-query")
    let len: int = exampleEls["length"]
    let i = ref(0)
    while i.contents < len {
      let el = exampleEls[i.contents]->Option.getExn
      addEventListener(el, "click", _ => {
        let q: string = el["getAttribute"]("data-query")
        editor["value"] = q
        let inputEvent = document["createEvent"]("Event")
        inputEvent["initEvent"]("input", true, true)->ignore
        editor["dispatchEvent"](inputEvent)->ignore
      })
      i := i.contents + 1
    }
  })
}

// === Check backend health ===

and checkBackend = async (statusEl: {..}): unit => {
  statusEl["textContent"] = "Connecting..."
  let result = await ApiClient.checkHealth()
  switch result {
  | Ok(url) =>
    backendConnected := true
    statusEl["textContent"] = "Connected to " ++ url
    statusEl["style"]["color"] = "var(--accent, #4ade80)"
  | Error(_) =>
    backendConnected := false
    statusEl["textContent"] = "Demo mode (offline)"
    statusEl["style"]["color"] = ""
  }
}

// === Query execution ===

and runQuery = (editor: {..}, output: {..}) => {
  let query: string = editor["value"]
  if String.trim(query) !== "" {
    executeAndDisplay(query, output)
  }
}

and executeAndDisplay = (query: string, output: {..}) => {
  if !queryInFlight.contents {
    if backendConnected.contents {
      // Execute against real backend (async).
      queryInFlight := true
      output["innerHTML"] = `<span class="output-info">Executing query...</span>`
      executeOnBackend(query, output)->ignore
    } else {
      // Fall back to demo executor (synchronous).
      let result = DemoExecutor.execute(query, ~vqlDt=vqlDtMode.contents)
      renderResult(result, output)
    }
  }
}

and executeOnBackend = async (query: string, output: {..}): unit => {
  let startTime = Date.now()
  let response = await ApiClient.executeQuery(query)
  let elapsed = Date.now() -. startTime
  queryInFlight := false

  switch response {
  | Ok(apiResponse) => {
      let result = ApiClient.toExecuteResult(apiResponse)
      // Inject real timing into success results.
      let timedResult = switch result {
      | DemoExecutor.Success(data) =>
        DemoExecutor.Success({...data, timing_ms: elapsed, row_count: apiResponse.row_count})
      | other => other
      }
      renderResult(timedResult, output)
    }
  | Error(msg) =>
    // Backend failed — try demo mode as fallback.
    output["innerHTML"] =
      `<span class="output-warning">Backend error: ${msg}</span>\n` ++
      `<span class="output-info">Falling back to demo mode...</span>`
    let _ = setTimeout(() => {
      let result = DemoExecutor.execute(query, ~vqlDt=vqlDtMode.contents)
      renderResult(result, output)
    }, 300)
  }
}

and renderResult = (result: DemoExecutor.executeResult, output: {..}) => {
  switch result {
  | DemoExecutor.Success(data) => {
      // Render as table
      let headerHtml = data.columns->Array.map(c => `<th>${c}</th>`)->Array.join("")
      let rowsHtml =
        data.rows
        ->Array.map(row => {
          let cells = row->Array.map(cell => `<td>${cell}</td>`)->Array.join("")
          `<tr>${cells}</tr>`
        })
        ->Array.join("\n")

      let tableStyle = "border-collapse:collapse;width:100%;font-size:0.85rem;"
      let cellStyle = "border:1px solid var(--border);padding:0.3rem 0.6rem;text-align:left;"
      let headerStyle =
        cellStyle ++ "background:var(--bg-secondary);font-weight:600;color:var(--accent);"

      // Inline styles since we're injecting HTML
      let styledTable = String.replaceAll(
        String.replaceAll(
          `<table style="${tableStyle}"><thead><tr>${headerHtml}</tr></thead><tbody>${rowsHtml}</tbody></table>`,
          "<th>",
          `<th style="${headerStyle}">`,
        ),
        "<td>",
        `<td style="${cellStyle}">`,
      )

      let source = if backendConnected.contents { "live" } else { "demo" }

      output["innerHTML"] =
        styledTable ++
        `\n<span class="output-timing">(${Int.toString(data.row_count)} rows, ${Float.toFixed(data.timing_ms, ~digits=1)}ms, ${source})</span>`
    }
  | DemoExecutor.ExplainResult(text) => {
      let escaped = String.replaceAll(String.replaceAll(text, "<", "&lt;"), ">", "&gt;")
      output["innerHTML"] = `<pre class="output-info">${escaped}</pre>`
    }
  | DemoExecutor.Error(msg) => {
      output["innerHTML"] = `<span class="output-error">ERROR: ${msg}</span>`
    }
  }
}

// === Lint helper ===

and runLint = (query: string, lintBar: {..}) => {
  let diagnostics = Linter.lint(query, ~vqlDt=vqlDtMode.contents)
  let errors = diagnostics->Array.filter(d => d.severity == Linter.Error)->Array.length
  let warnings = diagnostics->Array.filter(d => d.severity == Linter.Warning)->Array.length
  let hints = diagnostics->Array.filter(d => d.severity == Linter.Hint)->Array.length

  if errors > 0 {
    lintBar["innerHTML"] =
      `<span class="lint-error">${Int.toString(errors)} error(s)</span>, <span class="lint-warning">${Int.toString(warnings)} warning(s)</span>, ${Int.toString(hints)} hint(s)`
  } else if warnings > 0 {
    lintBar["innerHTML"] =
      `<span class="lint-warning">${Int.toString(warnings)} warning(s)</span>, ${Int.toString(hints)} hint(s)`
  } else if hints > 0 {
    lintBar["innerHTML"] = `<span class="lint-hint">${Int.toString(hints)} hint(s)</span>`
  } else {
    lintBar["innerHTML"] = `<span class="output-success">No issues</span>`
  }
}

// === setTimeout binding ===
@val external setTimeout: (unit => unit, int) => int = "setTimeout"

// === Boot ===

// Wait for DOM
addEventListener(document, "DOMContentLoaded", _ => init())
