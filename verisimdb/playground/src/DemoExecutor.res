// SPDX-License-Identifier: PMPL-1.0-or-later
// Demo query executor — simulates VeriSimDB responses offline.
// In production, this would call the real verisim-api endpoint.

type queryResult = {
  columns: array<string>,
  rows: array<array<string>>,
  timing_ms: float,
  row_count: int,
}

type executeResult =
  | Success(queryResult)
  | ExplainResult(string)
  | Error(string)

/// Generate demo data based on the query modalities.
let execute = (query: string, ~vqlDt: bool=false): executeResult => {
  let upper = String.toUpperCase(query)
  let startTime = Date.now()

  // EXPLAIN mode
  if String.includes(upper, "EXPLAIN") {
    let modalities = VqlKeywords.modalities->Array.filter(m => String.includes(upper, m))
    let plan = ref("=== EXPLAIN OUTPUT ===\n\n")
    plan := plan.contents ++ "Strategy: " ++ (if Array.length(modalities) >= 2 { "Parallel" } else { "Sequential" }) ++ "\n\n"

    modalities->Array.forEachWithIndex((m, i) => {
      let cost = switch m {
      | "TEMPORAL" => "30.0"
      | "VECTOR" => "50.0"
      | "DOCUMENT" => "80.0"
      | "GRAPH" => "150.0"
      | "TENSOR" => "200.0"
      | "SEMANTIC" => "300.0"
      | _ => "100.0"
      }
      plan := plan.contents ++ `Step ${Int.toString(i + 1)}: ${m} query\n`
      plan := plan.contents ++ `  Estimated cost: ${cost}ms\n`
      plan := plan.contents ++ `  Estimated rows: 100\n`
      plan := plan.contents ++ `  Selectivity: 0.5\n\n`
    })

    if vqlDt && String.includes(upper, "PROOF") {
      plan := plan.contents ++ "Proof verification: ENABLED\n"
      plan := plan.contents ++ "ZKP scheme: PLONK\n"
      plan := plan.contents ++ "Circuit compilation: deferred\n"
    }

    let elapsed = Date.now() -. startTime
    plan := plan.contents ++ `\nPlan generated in ${Float.toFixed(elapsed, ~digits=1)}ms\n`
    ExplainResult(plan.contents)
  }
  // DELETE/UPDATE — always deny in demo mode
  else if String.includes(upper, "DELETE") || String.includes(upper, "UPDATE") {
    Error("Write operations are disabled in demo mode")
  }
  // SELECT queries — generate demo data
  else if String.includes(upper, "SELECT") {
    let modalities = VqlKeywords.modalities->Array.filter(m => String.includes(upper, m))
    if Array.length(modalities) == 0 {
      Error("No modalities specified in SELECT clause")
    } else {
      let columns = ["id"]->Array.concat(
        modalities->Array.map(m => String.toLowerCase(m) ++ "_data")
      )
      let rowCount = if String.includes(upper, "LIMIT") { 5 } else { 10 }
      let rows = Array.fromInitializer(~length=rowCount, i => {
        let id = `hexad-${Int.toString(1000 + i)}`
        let modalityData = modalities->Array.map(m =>
          switch m {
          | "GRAPH" => `{edges: ${Int.toString(3 + i)}, type: "Entity"}`
          | "VECTOR" => `[${Float.toFixed(Float.fromInt(i) *. 0.1, ~digits=2)}, 0.50, 0.30]`
          | "TENSOR" => `shape=[3,3], dtype=f32`
          | "SEMANTIC" => if vqlDt { `{proof: "verified", scheme: "PLONK"}` } else { `{types: ["Thing"]}` }
          | "DOCUMENT" => `"Sample document ${Int.toString(i + 1)}"`
          | "TEMPORAL" => `{version: ${Int.toString(i + 1)}, ts: "2026-02-28"}`
          | "PROVENANCE" => `{source: "scan-v1", actor: "hypatia", chain_length: ${Int.toString(i + 1)}}`
          | "SPATIAL" => `{lat: ${Float.toFixed(51.5 +. Float.fromInt(i) *. 0.01, ~digits=4)}, lon: -0.1278}`
          | _ => "null"
          }
        )
        [id]->Array.concat(modalityData)
      })

      let elapsed = Date.now() -. startTime +. 15.0 // simulate some latency

      Success({
        columns,
        rows,
        timing_ms: elapsed,
        row_count: rowCount,
      })
    }
  } else {
    Error("Unrecognized query — VQL queries must start with SELECT, EXPLAIN, INSERT, UPDATE, or DELETE")
  }
}
