// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Playground API client — connects to a real verisim-api backend.
// Falls back gracefully to demo mode when the backend is unreachable.

/// Response shape from POST /api/v1/vql/execute.
type vqlResponse = {
  success: bool,
  statement_type: string,
  row_count: int,
  data: JSON.t,
  message: option<string>,
}

/// Connection state for the backend.
type connectionState =
  | Disconnected
  | Connecting
  | Connected(string)
  | Failed(string)

// === Fetch API bindings (no external package needed) ===

type response

@val external fetch: (string, {..}) => promise<response> = "fetch"
@val external fetchGet: string => promise<response> = "fetch"
@send external responseJson: response => promise<JSON.t> = "json"
@get external responseOk: response => bool = "ok"
@get external responseStatus: response => int = "status"

/// Backend URL — defaults to localhost:8080 (verisim-api default port).
/// Override by setting window.__VERISIM_API_URL__ before the script loads.
@val @scope("window") external apiUrlOverride: Nullable.t<string> = "__VERISIM_API_URL__"

let getBaseUrl = (): string => {
  switch Nullable.toOption(apiUrlOverride) {
  | Some(url) => url
  | None => "http://localhost:8080"
  }
}

/// Check backend health by hitting GET /api/v1/health.
let checkHealth = async (): result<string, string> => {
  let url = getBaseUrl() ++ "/api/v1/health"
  try {
    let response = await fetchGet(url)
    if responseOk(response) {
      Ok(getBaseUrl())
    } else {
      Error("Backend returned " ++ Int.toString(responseStatus(response)))
    }
  } catch {
  | _ => Error("Backend unreachable at " ++ url)
  }
}

/// Execute a VQL query against the real backend.
/// Returns Ok(vqlResponse) on success, Error(string) on failure.
let executeQuery = async (query: string): result<vqlResponse, string> => {
  let url = getBaseUrl() ++ "/api/v1/vql/execute"
  let bodyDict = Dict.make()
  Dict.set(bodyDict, "query", JSON.Encode.string(query))
  let body = JSON.Encode.object(bodyDict)

  try {
    let response = await fetch(
      url,
      {
        "method": "POST",
        "headers": {"Content-Type": "application/json"},
        "body": JSON.stringify(body),
      },
    )

    let json = await responseJson(response)

    if responseOk(response) {
      // Parse the response fields.
      switch JSON.Classify.classify(json) {
      | JSON.Classify.Object(obj) => {
          let success = switch Dict.get(obj, "success") {
          | Some(v) =>
            switch JSON.Classify.classify(v) {
            | JSON.Classify.Bool(b) => b
            | _ => false
            }
          | None => false
          }
          let statementType = switch Dict.get(obj, "statement_type") {
          | Some(v) =>
            switch JSON.Classify.classify(v) {
            | JSON.Classify.String(s) => s
            | _ => "UNKNOWN"
            }
          | None => "UNKNOWN"
          }
          let rowCount = switch Dict.get(obj, "row_count") {
          | Some(v) =>
            switch JSON.Classify.classify(v) {
            | JSON.Classify.Number(n) => Float.toInt(n)
            | _ => 0
            }
          | None => 0
          }
          let data = switch Dict.get(obj, "data") {
          | Some(v) => v
          | None => JSON.Encode.null
          }
          let message = switch Dict.get(obj, "message") {
          | Some(v) =>
            switch JSON.Classify.classify(v) {
            | JSON.Classify.String(s) => Some(s)
            | _ => None
            }
          | None => None
          }

          Ok({
            success,
            statement_type: statementType,
            row_count: rowCount,
            data,
            message,
          })
        }
      | _ => Error("Unexpected response format")
      }
    } else {
      // Parse error message from response body.
      switch JSON.Classify.classify(json) {
      | JSON.Classify.Object(obj) =>
        switch Dict.get(obj, "error") {
        | Some(v) =>
          switch JSON.Classify.classify(v) {
          | JSON.Classify.String(s) => Error(s)
          | _ =>
            Error("Backend error (status " ++ Int.toString(responseStatus(response)) ++ ")")
          }
        | None =>
          Error("Backend error (status " ++ Int.toString(responseStatus(response)) ++ ")")
        }
      | _ => Error("Backend error (status " ++ Int.toString(responseStatus(response)) ++ ")")
      }
    }
  } catch {
  | exn =>
    let msg = switch exn {
    | Exn.Error(e) =>
      switch Exn.message(e) {
      | Some(m) => m
      | None => "Network error"
      }
    | _ => "Network error"
    }
    Error(msg)
  }
}

// === Response conversion helpers (defined before toExecuteResult) ===

/// Convert a JSON value to a display string for table cells.
let jsonToString = (value: JSON.t): string => {
  switch JSON.Classify.classify(value) {
  | JSON.Classify.String(s) => s
  | JSON.Classify.Number(n) =>
    if Float.mod(n, 1.0) == 0.0 {
      Int.toString(Float.toInt(n))
    } else {
      Float.toFixed(n, ~digits=3)
    }
  | JSON.Classify.Bool(b) => if b { "true" } else { "false" }
  | JSON.Classify.Null => "null"
  | _ => JSON.stringify(value)
  }
}

/// Format an EXPLAIN response into readable text.
let formatExplainResponse = (data: JSON.t): string => {
  let text = ref("=== EXPLAIN OUTPUT (from backend) ===\n\n")
  switch JSON.Classify.classify(data) {
  | JSON.Classify.Object(obj) => {
      switch Dict.get(obj, "query") {
      | Some(q) =>
        switch JSON.Classify.classify(q) {
        | JSON.Classify.String(s) => text := text.contents ++ "Query: " ++ s ++ "\n\n"
        | _ => ()
        }
      | None => ()
      }
      switch Dict.get(obj, "plan") {
      | Some(plan) => text := text.contents ++ "Plan:\n" ++ JSON.stringify(plan, ~space=2) ++ "\n"
      | None => ()
      }
    }
  | _ => text := text.contents ++ JSON.stringify(data, ~space=2) ++ "\n"
  }
  text.contents
}

/// Convert a VQL response with a JSON data array into a table result.
let formatAsTable = (response: vqlResponse): DemoExecutor.executeResult => {
  switch JSON.Classify.classify(response.data) {
  | JSON.Classify.Array(items) =>
    if Array.length(items) == 0 {
      DemoExecutor.Success({
        columns: ["result"],
        rows: [],
        timing_ms: 0.0,
        row_count: 0,
      })
    } else {
      // Extract columns from the first item's keys.
      let firstItem = items[0]
      let columns = switch firstItem {
      | Some(item) =>
        switch JSON.Classify.classify(item) {
        | JSON.Classify.Object(obj) => Dict.keysToArray(obj)
        | _ => ["value"]
        }
      | None => ["value"]
      }

      // Extract rows.
      let rows = items->Array.map(item =>
        columns->Array.map(col =>
          switch JSON.Classify.classify(item) {
          | JSON.Classify.Object(obj) =>
            switch Dict.get(obj, col) {
            | Some(v) => jsonToString(v)
            | None => "null"
            }
          | _ => jsonToString(item)
          }
        )
      )

      DemoExecutor.Success({
        columns,
        rows,
        timing_ms: 0.0,
        row_count: response.row_count,
      })
    }
  | JSON.Classify.Object(_) =>
    // Single object result (e.g., COUNT, SHOW STATUS) — render as key-value pairs.
    let text = JSON.stringify(response.data, ~space=2)
    switch response.message {
    | Some(msg) => DemoExecutor.ExplainResult(msg ++ "\n\n" ++ text)
    | None =>
      DemoExecutor.ExplainResult(response.statement_type ++ " result:\n\n" ++ text)
    }
  | JSON.Classify.Null =>
    switch response.message {
    | Some(msg) => DemoExecutor.ExplainResult(msg)
    | None => DemoExecutor.ExplainResult(response.statement_type ++ " completed successfully.")
    }
  | _ => DemoExecutor.ExplainResult(JSON.stringify(response.data, ~space=2))
  }
}

/// Convert a VQL API response into a DemoExecutor-compatible result.
/// This bridges the real backend response format to the existing rendering code.
let toExecuteResult = (response: vqlResponse): DemoExecutor.executeResult => {
  if !response.success {
    DemoExecutor.Error(
      switch response.message {
      | Some(msg) => msg
      | None => "Query failed"
      },
    )
  } else if response.statement_type == "EXPLAIN" {
    // EXPLAIN returns structured JSON — format it as readable text.
    DemoExecutor.ExplainResult(formatExplainResponse(response.data))
  } else {
    // Convert JSON data array to columns + rows table format.
    formatAsTable(response)
  }
}
