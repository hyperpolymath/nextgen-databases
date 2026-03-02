// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL EXPLAIN - Query Plan Visualization

module AST = VQLParser.AST

type planNode = {
  step: int,
  operation: string,
  modality: string,
  estimatedCost: int,
  estimatedSelectivity: float,
  optimizationHint: option<string>,
  pushedPredicates: array<string>,
}

type proofPlanNode = {
  proofType: string,
  contractName: string,
  circuit: string,
  estimatedTimeMs: int,
}

type executionPlan = {
  strategy: [#Sequential | #Parallel],
  totalCost: int,
  optimizationMode: string,
  nodes: array<planNode>,
  bidirectionalOptimization: bool,
  proofObligations: array<proofPlanNode>,
}

// Parse EXPLAIN query
let parseExplain = (query: string): Result<(bool, string), string> => {
  let trimmed = Js.String2.trim(query)
  if Js.String2.startsWith(trimmed, "EXPLAIN") {
    let queryWithoutExplain = Js.String2.sliceToEnd(trimmed, ~from=7) |> Js.String2.trim
    Ok((true, queryWithoutExplain))
  } else {
    Ok((false, query))
  }
}

// Format execution plan for display
let formatPlan = (plan: executionPlan): string => {
  let lines = []

  // Header
  lines->Js.Array2.push("╔════════════════════════════════════════════════════════════════╗")
  lines->Js.Array2.push("║              VQL QUERY EXECUTION PLAN                          ║")
  lines->Js.Array2.push("╚════════════════════════════════════════════════════════════════╝")
  lines->Js.Array2.push("")

  // Strategy
  let strategyStr = switch plan.strategy {
  | #Sequential => "Sequential Pipeline (operations run in series)"
  | #Parallel => "Parallel Execution (operations run concurrently)"
  }
  lines->Js.Array2.push(`Strategy: ${strategyStr}`)
  lines->Js.Array2.push(`Optimization Mode: ${plan.optimizationMode}`)
  lines->Js.Array2.push(`Bidirectional Optimization: ${plan.bidirectionalOptimization ? "Enabled" : "Disabled"}`)
  lines->Js.Array2.push(`Estimated Total Cost: ${Belt.Int.toString(plan.totalCost)}ms`)
  lines->Js.Array2.push("")
  lines->Js.Array2.push("─────────────────────────────────────────────────────────────────")
  lines->Js.Array2.push("")

  // Steps
  plan.nodes->Js.Array2.forEach(node => {
    lines->Js.Array2.push(`Step ${Belt.Int.toString(node.step)}: ${node.operation} (${node.modality})`)
    lines->Js.Array2.push(`  Cost: ${Belt.Int.toString(node.estimatedCost)}ms`)
    lines->Js.Array2.push(`  Selectivity: ${Belt.Float.toString(node.estimatedSelectivity *. 100.0)}% of data`)

    // Optimization hints
    switch node.optimizationHint {
    | Some(hint) => lines->Js.Array2.push(`  Optimization: ${hint}`)
    | None => ()
    }

    // Pushed predicates
    if Js.Array2.length(node.pushedPredicates) > 0 {
      lines->Js.Array2.push(`  Pushed predicates:`)
      node.pushedPredicates->Js.Array2.forEach(pred => {
        lines->Js.Array2.push(`    - ${pred}`)
      })
    }

    lines->Js.Array2.push("")
  })

  lines->Js.Array2.push("─────────────────────────────────────────────────────────────────")
  lines->Js.Array2.push("")

  // Cost breakdown
  let costByModality = plan.nodes->Belt.Array.reduce(Js.Dict.empty(), (acc, node) => {
    let current = Js.Dict.get(acc, node.modality)->Belt.Option.getWithDefault(0)
    Js.Dict.set(acc, node.modality, current + node.estimatedCost)
    acc
  })

  lines->Js.Array2.push("Cost Breakdown by Modality:")
  costByModality
  ->Js.Dict.entries
  ->Js.Array2.forEach(((modality, cost)) => {
    let percentage = Belt.Float.fromInt(cost) /. Belt.Float.fromInt(plan.totalCost) *. 100.0
    lines->Js.Array2.push(`  ${modality}: ${Belt.Int.toString(cost)}ms (${Belt.Float.toString(percentage)}%)`)
  })

  lines->Js.Array2.push("")

  // Proof obligations
  if Js.Array2.length(plan.proofObligations) > 0 {
    lines->Js.Array2.push("Proof Obligations:")
    plan.proofObligations->Js.Array2.forEach(proof => {
      lines->Js.Array2.push(`  ${proof.proofType}(${proof.contractName}) circuit=${proof.circuit} est=${Belt.Int.toString(proof.estimatedTimeMs)}ms`)
    })
    lines->Js.Array2.push("")
  }

  // Performance hints
  lines->Js.Array2.push("Performance Hints:")
  let hints = generatePerformanceHints(plan)
  if Js.Array2.length(hints) == 0 {
    lines->Js.Array2.push("  ✓ Query plan is optimal")
  } else {
    hints->Js.Array2.forEach(hint => {
      lines->Js.Array2.push(`  • ${hint}`)
    })
  }

  lines->Js.Array2.joinWith("\n")
}

// Generate performance improvement hints
let generatePerformanceHints = (plan: executionPlan): array<string> => {
  let hints = []

  // Hint 1: Sequential with low selectivity first step
  switch plan.strategy {
  | #Sequential => {
      switch plan.nodes[0] {
      | Some(firstNode) =>
        if firstNode.estimatedSelectivity > 0.1 {
          hints->Js.Array2.push(
            "First step has low selectivity (>10%). Consider reordering or using more selective conditions."
          )
        }
      | None => ()
      }
    }
  | #Parallel => ()
  }

  // Hint 2: Expensive operation without index
  plan.nodes->Js.Array2.forEach(node => {
    if node.estimatedCost > 200 && node.optimizationHint == None {
      hints->Js.Array2.push(
        `${node.modality} operation is expensive (${Belt.Int.toString(node.estimatedCost)}ms) and not using indexes. Consider adding predicates.`
      )
    }
  })

  // Hint 3: Parallel execution opportunity
  if plan.strategy == #Sequential && Js.Array2.length(plan.nodes) > 2 {
    let firstSelectivity = plan.nodes[0]->Belt.Option.map(n => n.estimatedSelectivity)->Belt.Option.getWithDefault(0.0)
    if firstSelectivity > 0.2 {
      hints->Js.Array2.push(
        "Query might benefit from parallel execution. First step is not highly selective."
      )
    }
  }

  // Hint 4: Missing LIMIT
  if plan.totalCost > 500 {
    hints->Js.Array2.push(
      "Query is expensive. Consider adding LIMIT clause to reduce result size."
    )
  }

  hints
}

// Example usage in client
let explainQuery = (query: string): Result<string, string> => {
  switch parseExplain(query) {
  | Ok((true, actualQuery)) => {
      // Parse the query
      switch VQLParser.parse(actualQuery) {
      | Ok(ast) => {
          // Generate plan (this would call Elixir QueryPlanner)
          let plan = generatePlanFromAst(ast)
          Ok(formatPlan(plan))
        }
      | Error(e) => Error(`Parse error: ${e.message}`)
      }
    }
  | Ok((false, _)) => Error("Not an EXPLAIN query")
  | Error(msg) => Error(msg)
  }
}

// Generate plan based on actual AST analysis (replaces hardcoded mock)
let generatePlanFromAst = (ast: VQLParser.query): executionPlan => {
  let nodes = ast.modalities->Belt.Array.mapWithIndex((idx, modality) => {
    let modalityStr = switch modality {
    | Graph => "GRAPH"
    | Vector => "VECTOR"
    | Tensor => "TENSOR"
    | Semantic => "SEMANTIC"
    | Document => "DOCUMENT"
    | Temporal => "TEMPORAL"
    | Provenance => "PROVENANCE"
    | Spatial => "SPATIAL"
    | All => "ALL"
    }

    // Estimate costs based on modality type
    let (cost, selectivity, hint) = switch modality {
    | Graph => (150, 0.2, Some("Graph traversal — O(E) scan"))
    | Vector => (50, 0.01, Some("HNSW approximate nearest neighbor"))
    | Tensor => (200, 0.5, Some("Tensor reduction — shape dependent"))
    | Semantic => (300, 0.8, Some("ZKP verification — expensive"))
    | Document => (80, 0.05, Some("Tantivy inverted index lookup"))
    | Temporal => (30, 0.1, Some("Version tree lookup — cached"))
    | Provenance => (60, 0.3, Some("Hash-chain traversal — O(n) chain length"))
    | Spatial => (70, 0.1, Some("R-tree spatial index lookup"))
    | All => (500, 1.0, Some("Full hexad scan across all modalities"))
    }

    // Adjust for LIMIT clause
    let adjustedSelectivity = switch ast.limit {
    | Some(limit) =>
      let limitF = Belt.Float.fromInt(limit)
      Js.Math.min_float(selectivity, limitF /. 1000.0)
    | None => selectivity
    }

    {
      step: idx + 1,
      operation: "Query",
      modality: modalityStr,
      estimatedCost: cost,
      estimatedSelectivity: adjustedSelectivity,
      optimizationHint: hint,
      pushedPredicates: [],
    }
  })

  // Add GROUP BY / Aggregate step if present
  let aggregateNode = switch (ast.groupBy, ast.aggregates) {
  | (Some(groupFields), Some(_aggs)) => {
      let groupFieldStrs = groupFields->Belt.Array.map(f => {
        let modStr = switch f.modality {
        | Graph => "GRAPH"
        | Vector => "VECTOR"
        | Tensor => "TENSOR"
        | Semantic => "SEMANTIC"
        | Document => "DOCUMENT"
        | Temporal => "TEMPORAL"
        | Provenance => "PROVENANCE"
        | Spatial => "SPATIAL"
        | All => "ALL"
        }
        `${modStr}.${f.field}`
      })
      Some({
        step: Js.Array2.length(nodes) + 1,
        operation: "Group & Aggregate",
        modality: "AGGREGATE",
        estimatedCost: 20,
        estimatedSelectivity: 0.3,
        optimizationHint: Some(`Group by: ${groupFieldStrs->Js.Array2.joinWith(", ")}`),
        pushedPredicates: [],
      })
    }
  | (None, Some(_aggs)) =>
    Some({
      step: Js.Array2.length(nodes) + 1,
      operation: "Aggregate (no grouping)",
      modality: "AGGREGATE",
      estimatedCost: 10,
      estimatedSelectivity: 1.0,
      optimizationHint: Some("Full-result aggregation — single output row"),
      pushedPredicates: [],
    })
  | _ => None
  }

  switch aggregateNode {
  | Some(node) => nodes->Js.Array2.push(node)->ignore
  | None => ()
  }

  // Add ORDER BY / Sort step if present
  switch ast.orderBy {
  | Some(orderItems) => {
      let orderStrs = orderItems->Belt.Array.map(item => {
        let modStr = switch item.field.modality {
        | Graph => "GRAPH"
        | Vector => "VECTOR"
        | Tensor => "TENSOR"
        | Semantic => "SEMANTIC"
        | Document => "DOCUMENT"
        | Temporal => "TEMPORAL"
        | Provenance => "PROVENANCE"
        | Spatial => "SPATIAL"
        | All => "ALL"
        }
        let dirStr = switch item.direction {
        | Asc => "ASC"
        | Desc => "DESC"
        }
        `${modStr}.${item.field.field} ${dirStr}`
      })
      nodes->Js.Array2.push({
        step: Js.Array2.length(nodes) + 1,
        operation: "Sort",
        modality: "SORT",
        estimatedCost: 15,
        estimatedSelectivity: 1.0,
        optimizationHint: Some(`Order by: ${orderStrs->Js.Array2.joinWith(", ")}`),
        pushedPredicates: [],
      })->ignore
    }
  | None => ()
  }

  // Determine strategy
  let strategy = if Js.Array2.length(nodes) > 1 {
    #Parallel
  } else {
    #Sequential
  }

  let totalCost = nodes->Belt.Array.reduce(0, (acc, node) => acc + node.estimatedCost)

  // Generate proof obligation nodes from PROOF clause
  let proofNodes = switch ast.proof {
  | None => []
  | Some(proofSpecs) =>
    proofSpecs->Belt.Array.map(spec => {
      let typeStr = switch spec.proofType {
      | Existence => "EXISTENCE"
      | Citation => "CITATION"
      | Access => "ACCESS"
      | Integrity => "INTEGRITY"
      | Provenance => "PROVENANCE"
      | Custom => "CUSTOM"
      }
      let circuit = switch spec.proofType {
      | Existence => "existence-proof-v1"
      | Citation => "citation-proof-v1"
      | Access => "access-control-v1"
      | Integrity => "integrity-check-v1"
      | Provenance => "provenance-chain-v1"
      | Custom => "custom-circuit"
      }
      let est = switch spec.proofType {
      | Existence => 50
      | Citation => 100
      | Access => 150
      | Integrity => 200
      | Provenance => 300
      | Custom => 500
      }
      {
        proofType: typeStr,
        contractName: spec.contractName,
        circuit: circuit,
        estimatedTimeMs: est,
      }
    })
  }

  let proofCost = proofNodes->Belt.Array.reduce(0, (acc, p) => acc + p.estimatedTimeMs)

  {
    strategy: strategy,
    totalCost: totalCost + proofCost,
    optimizationMode: "Balanced (client-side estimate)",
    nodes: nodes,
    bidirectionalOptimization: false,
    proofObligations: proofNodes,
  }
}

// Deprecated: Use generatePlanFromAst instead. Kept for test compatibility only.
let generateMockPlan = (ast: VQLParser.query): executionPlan => {
  let nodes = ast.modalities->Belt.Array.mapWithIndex((idx, modality) => {
    let modalityStr = switch modality {
    | Graph => "GRAPH"
    | Vector => "VECTOR"
    | Tensor => "TENSOR"
    | Semantic => "SEMANTIC"
    | Document => "DOCUMENT"
    | Temporal => "TEMPORAL"
    | Provenance => "PROVENANCE"
    | Spatial => "SPATIAL"
    | All => "ALL"
    }

    {
      step: idx + 1,
      operation: "Query",
      modality: modalityStr,
      estimatedCost: 100,
      estimatedSelectivity: 0.05,
      optimizationHint: Some("Using index"),
      pushedPredicates: ["LIMIT 10"],
    }
  })

  {
    strategy: #Sequential,
    totalCost: 300,
    optimizationMode: "Balanced",
    nodes: nodes,
    bidirectionalOptimization: true,
    proofObligations: [],
  }
}

// Export for testing
let testExplain = () => {
  let query = `
    EXPLAIN
    SELECT GRAPH, VECTOR
    FROM FEDERATION /universities/*
    WHERE (h)-[:CITES]->(target)
      AND h.embedding SIMILAR TO [0.1, 0.2, 0.3] WITHIN 0.9
    LIMIT 10
  `

  switch explainQuery(query) {
  | Ok(plan) => Js.Console.log(plan)
  | Error(e) => Js.Console.error(e)
  }
}
