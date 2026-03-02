// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL client-side linter — mirrors the Rust linter rules (VQL001–VQL011).

type severity = Hint | Warning | Error

type diagnostic = {
  code: string,
  severity: severity,
  message: string,
}

let severityToString = s =>
  switch s {
  | Hint => "hint"
  | Warning => "warning"
  | Error => "error"
  }

let lint = (query: string, ~vqlDt: bool=false): array<diagnostic> => {
  let diagnostics = []
  let upper = String.toUpperCase(query)
  let tokens =
    Js.String2.splitByRe(String.trim(upper), %re("/\s+/"))
    ->Array.filterMap(x => x)

  let has = tok => tokens->Array.includes(tok)

  let isSelect = has("SELECT")
  let isDelete = has("DELETE")
  let isUpdate = has("UPDATE")
  let isExplain = has("EXPLAIN")

  // VQL001: Missing LIMIT
  if isSelect && !has("LIMIT") && !isExplain {
    diagnostics->Array.push({
      code: "VQL001",
      severity: Warning,
      message: "Query lacks LIMIT clause — may return unbounded results",
    })
  }

  // VQL002: SELECT all modalities
  if isSelect {
    let count =
      VqlKeywords.modalities->Array.filter(m => has(m))->Array.length
    if count >= 6 {
      diagnostics->Array.push({
        code: "VQL002",
        severity: Hint,
        message: "Query selects " ++ Int.toString(count) ++ " of 8 modalities — consider selecting only what you need",
      })
    }
  }

  // VQL003: Semantic without PROOF
  if has("SEMANTIC") && !has("PROOF") && isSelect {
    diagnostics->Array.push({
      code: "VQL003",
      severity: if vqlDt { Error } else { Warning },
      message: "Semantic modality accessed without PROOF clause",
    })
  }

  // VQL004: TRAVERSE without DEPTH
  if has("TRAVERSE") && !has("DEPTH") {
    diagnostics->Array.push({
      code: "VQL004",
      severity: Error,
      message: "TRAVERSE without DEPTH limit — may explore entire graph",
    })
  }

  // VQL005: DRIFT without THRESHOLD
  if (has("DRIFT") || has("CONSISTENCY")) && !has("THRESHOLD") {
    diagnostics->Array.push({
      code: "VQL005",
      severity: Hint,
      message: "DRIFT/CONSISTENCY check without THRESHOLD — using implicit default",
    })
  }

  // VQL006: ORDER BY without LIMIT
  if has("ORDER") && !has("LIMIT") && isSelect {
    diagnostics->Array.push({
      code: "VQL006",
      severity: Warning,
      message: "ORDER BY without LIMIT — sorting potentially unbounded result set",
    })
  }

  // VQL007: Dangerous write without WHERE
  if (isDelete || isUpdate) && !has("WHERE") {
    diagnostics->Array.push({
      code: "VQL007",
      severity: Error,
      message: "DELETE/UPDATE without WHERE clause — affects all entities",
    })
  }

  // VQL010: Multi-modality without EXPLAIN
  if isSelect && !isExplain {
    let count =
      VqlKeywords.modalities->Array.filter(m => has(m))->Array.length
    if count >= 3 {
      diagnostics->Array.push({
        code: "VQL010",
        severity: Hint,
        message: "Multi-modality query — consider running EXPLAIN first",
      })
    }
  }

  // VQL011: FEDERATION without STORE
  if has("FEDERATION") && !has("STORE") {
    diagnostics->Array.push({
      code: "VQL011",
      severity: Warning,
      message: "FEDERATION query without STORE — will query all federated instances",
    })
  }

  // VQL-DT specific: PROOF required for all semantic access
  if vqlDt && isSelect && has("SEMANTIC") && !has("PROOF") {
    // Already covered by VQL003 with Error severity
    ignore()
  }

  // Sort: errors first
  diagnostics->Array.sort((a, b) => {
    let severityOrder = s =>
      switch s {
      | Error => 0
      | Warning => 1
      | Hint => 2
      }
    Float.fromInt(severityOrder(a.severity) - severityOrder(b.severity))
  })

  diagnostics
}
