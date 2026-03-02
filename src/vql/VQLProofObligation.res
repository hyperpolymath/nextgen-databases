// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Proof Obligation — Generates typed proof obligations from queries
//
// For each PROOF spec in a dependent-type query, generates a structured
// obligation that the executor must satisfy. Handles multi-proof
// composition validation and conflict detection.

module AST = VQLParser.AST
module Types = VQLTypes
module Ctx = VQLContext

// ============================================================================
// Proof Obligation Types
// ============================================================================

type obligationKind =
  | ExistenceObligation // Hexad must exist and be accessible
  | IntegrityObligation // Data integrity (hash/Merkle verification)
  | AccessObligation // Access control (ZKP-based permission)
  | CitationObligation // Citation chain validity
  | ProvenanceObligation // Lineage/provenance chain
  | CustomObligation(string) // Custom contract-specific

type proofObligation = {
  kind: obligationKind,
  contractName: string,
  witnessFields: array<string>,
  circuit: string,
  estimatedTimeMs: int,
  requiredModalities: array<Types.modalityType>,
}

type composedProofPlan = {
  obligations: array<proofObligation>,
  totalEstimatedTimeMs: int,
  isParallelizable: bool,
  compositionStrategy: compositionStrategy,
}

and compositionStrategy =
  | Independent // proofs are independent, can run in parallel
  | Sequential(array<int>) // indices of obligations in dependency order
  | Nested // proof N requires result of proof N-1

// ============================================================================
// Obligation generation
// ============================================================================

let generateObligation = (
  ctx: Ctx.context,
  proofSpec: AST.proofSpec,
  queryResultType: Types.queryResultInfo,
): Result<proofObligation, string> => {
  let proofKind = Types.proofKindOfAstProofType(proofSpec.proofType)
  let kind = proofKindToObligationKind(proofKind, proofSpec.contractName)

  // Determine witness fields based on proof type
  let witnessFields = switch proofSpec.proofType {
  | Existence => ["hexad_id", "timestamp"]
  | Citation => ["hexad_id", "citation_chain", "source_ids"]
  | Access => ["hexad_id", "user_id", "role", "permissions"]
  | Integrity => ["hexad_id", "modality_hashes", "merkle_root"]
  | Provenance => ["hexad_id", "lineage_chain", "actors", "timestamps"]
  | Custom => ["hexad_id", "contract_params"]
  }

  // Get required modalities from contract spec or query
  let requiredMods = switch Ctx.lookupContract(ctx, proofSpec.contractName) {
  | Some(spec) => spec.requiredModalities
  | None => queryResultType.modalities
  }

  Ok({
    kind,
    contractName: proofSpec.contractName,
    witnessFields,
    circuit: proofKindToCircuit(proofKind),
    estimatedTimeMs: estimateProofTime(proofKind),
    requiredModalities: requiredMods,
  })
}

// Generate obligations for multiple proof specs (multi-proof)
let generateObligations = (
  ctx: Ctx.context,
  proofSpecs: array<AST.proofSpec>,
  queryResultType: Types.queryResultInfo,
): Result<composedProofPlan, string> => {
  // Generate each obligation
  let obligationResults = proofSpecs->Belt.Array.map(spec => {
    generateObligation(ctx, spec, queryResultType)
  })

  // Check for errors
  let firstError = obligationResults->Belt.Array.getBy(r => {
    switch r {
    | Error(_) => true
    | Ok(_) => false
    }
  })

  switch firstError {
  | Some(Error(e)) => Error(e)
  | _ =>
    let obligations = obligationResults->Belt.Array.keepMap(r => {
      switch r {
      | Ok(o) => Some(o)
      | Error(_) => None
      }
    })

    // Determine composition strategy
    let strategy = determineCompositionStrategy(obligations)
    let totalTime = switch strategy {
    | Independent =>
      // Parallel: max of all obligations
      obligations->Belt.Array.reduce(0, (acc, o) =>
        Js.Math.max_int(acc, o.estimatedTimeMs)
      )
    | Sequential(_) | Nested =>
      // Sequential: sum of all obligations
      obligations->Belt.Array.reduce(0, (acc, o) => acc + o.estimatedTimeMs)
    }

    Ok({
      obligations,
      totalEstimatedTimeMs: totalTime,
      isParallelizable: strategy == Independent,
      compositionStrategy: strategy,
    })
  }
}

// ============================================================================
// Composition strategy determination
// ============================================================================

let determineCompositionStrategy = (obligations: array<proofObligation>): compositionStrategy => {
  let len = Js.Array2.length(obligations)
  if len <= 1 {
    Independent
  } else {
    // Check if any obligation depends on another's result
    let hasProvenance = obligations->Js.Array2.some(o => {
      switch o.kind {
      | ProvenanceObligation => true
      | _ => false
      }
    })

    let hasCitation = obligations->Js.Array2.some(o => {
      switch o.kind {
      | CitationObligation => true
      | _ => false
      }
    })

    // Provenance + Citation must be sequential (provenance verifies citation chain)
    if hasProvenance && hasCitation {
      // Citation first, then provenance
      let indices = []
      obligations->Js.Array2.forEachi((o, i) => {
        switch o.kind {
        | CitationObligation => indices->Js.Array2.push(i)->ignore
        | _ => ()
        }
      })
      obligations->Js.Array2.forEachi((o, i) => {
        switch o.kind {
        | CitationObligation => () // already added
        | _ => indices->Js.Array2.push(i)->ignore
        }
      })
      Sequential(indices)
    } else {
      // All other combinations are independent
      Independent
    }
  }
}

// ============================================================================
// Utility functions
// ============================================================================

let proofKindToObligationKind = (pk: Types.proofKind, contractName: string): obligationKind => {
  switch pk {
  | ExistenceProof => ExistenceObligation
  | CitationProof => CitationObligation
  | AccessProof => AccessObligation
  | IntegrityProof => IntegrityObligation
  | ProvenanceProof => ProvenanceObligation
  | CustomProof => CustomObligation(contractName)
  }
}

let proofKindToCircuit = (pk: Types.proofKind): string => {
  switch pk {
  | ExistenceProof => "existence-proof-v1"
  | CitationProof => "citation-proof-v1"
  | AccessProof => "access-control-v1"
  | IntegrityProof => "integrity-check-v1"
  | ProvenanceProof => "provenance-chain-v1"
  | CustomProof => "custom-circuit"
  }
}

let estimateProofTime = (pk: Types.proofKind): int => {
  switch pk {
  | ExistenceProof => 50
  | CitationProof => 100
  | AccessProof => 150
  | IntegrityProof => 200
  | ProvenanceProof => 300
  | CustomProof => 500
  }
}

let obligationKindToString = (k: obligationKind): string => {
  switch k {
  | ExistenceObligation => "EXISTENCE"
  | IntegrityObligation => "INTEGRITY"
  | AccessObligation => "ACCESS"
  | CitationObligation => "CITATION"
  | ProvenanceObligation => "PROVENANCE"
  | CustomObligation(name) => `CUSTOM(${name})`
  }
}

let formatObligation = (o: proofObligation): string => {
  let kind = obligationKindToString(o.kind)
  let witnesses = o.witnessFields->Js.Array2.joinWith(", ")
  `${kind}(${o.contractName}) circuit=${o.circuit} witnesses=[${witnesses}] est=${Belt.Int.toString(o.estimatedTimeMs)}ms`
}

let formatPlan = (plan: composedProofPlan): string => {
  let lines = []
  lines->Js.Array2.push("Proof Plan:")->ignore
  lines->Js.Array2.push(`  Strategy: ${switch plan.compositionStrategy {
    | Independent => "Independent (parallel)"
    | Sequential(_) => "Sequential (ordered)"
    | Nested => "Nested (chained)"
  }}`)->ignore
  lines->Js.Array2.push(`  Parallelizable: ${plan.isParallelizable ? "yes" : "no"}`)->ignore
  lines->Js.Array2.push(`  Estimated time: ${Belt.Int.toString(plan.totalEstimatedTimeMs)}ms`)->ignore
  lines->Js.Array2.push(`  Obligations:`)->ignore
  plan.obligations->Js.Array2.forEachi((o, i) => {
    lines->Js.Array2.push(`    ${Belt.Int.toString(i + 1)}. ${formatObligation(o)}`)->ignore
  })
  lines->Js.Array2.joinWith("\n")
}
