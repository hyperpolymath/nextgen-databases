// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Type Checker — Thin facade over VQLBidir bidirectional type inference
//
// Maintains backward-compatible public API (checkQuery, planProofGeneration)
// while delegating to the real type system in VQLBidir.

module AST = VQLParser.AST
module Error = VQLError
module Types = VQLTypes
module Ctx = VQLContext
module Bidir = VQLBidir
module ProofObl = VQLProofObligation

// ============================================================================
// Type Context (backward-compatible)
// ============================================================================

type contractInfo = {
  name: string,
  proofType: AST.proofType,
  requiredFields: array<string>,
  constraints: array<constraint>,
}

and constraint =
  | FieldMustExist(string)
  | FieldMustBeType(string, primitiveType)
  | ModalityRequired(AST.modality)
  | MinimumSelectivity(float)
  | MaxDriftThreshold(float)

and primitiveType =
  | TString
  | TInt
  | TFloat
  | TBool
  | TArray(primitiveType)
  | TVector(int)
  | TUuid

type typeContext = {
  contracts: Js.Dict.t<contractInfo>,
  availableModalities: array<AST.modality>,
  strictMode: bool,
}

// ============================================================================
// Context construction
// ============================================================================

type typeCheckResult = Result<unit, Error.typeError>

let makeTypeContext = (
  ~contracts: Js.Dict.t<contractInfo>=Js.Dict.empty(),
  ~strictMode=true,
  (),
): typeContext => {
  {
    contracts: contracts,
    availableModalities: [Graph, Vector, Tensor, Semantic, Document, Temporal],
    strictMode: strictMode,
  }
}

let createDefaultContext = (): typeContext => {
  makeTypeContext(~strictMode=true, ())
}

// Convert old-style context to new bidirectional context
let toBidirContext = (ctx: typeContext): Ctx.context => {
  let bidirCtx = Ctx.defaultContext()

  // Register contracts from old context
  Js.Dict.entries(ctx.contracts)->Js.Array2.forEach(((name, info)) => {
    let proofKind = Types.proofKindOfAstProofType(info.proofType)
    let requiredMods = info.constraints->Belt.Array.keepMap(c => {
      switch c {
      | ModalityRequired(m) => Types.modalityTypeOfAstModality(m)
      | _ => None
      }
    })
    let spec: Ctx.contractSpec = {
      name: name,
      proofKind: proofKind,
      requiredModalities: requiredMods,
      requiredFields: [],
      composableWith: [
        Types.ExistenceProof,
        Types.CitationProof,
        Types.AccessProof,
        Types.IntegrityProof,
        Types.ProvenanceProof,
        Types.CustomProof,
      ],
    }
    Js.Dict.set(bidirCtx.contracts, name, spec)
  })

  bidirCtx
}

// ============================================================================
// Public API (backward-compatible)
// ============================================================================

let checkQuery = (query: AST.query, context: typeContext): typeCheckResult => {
  // First: SQL-compat validation (HAVING requires GROUP BY, etc.)
  switch checkSqlCompat(query) {
  | Error(e) => Error(e)
  | Ok() =>
    // Delegate to bidirectional type checker
    let bidirCtx = toBidirContext(context)
    switch Bidir.synthesizeQuery(bidirCtx, query) {
    | Ok(_type) => Ok()
    | Error(typeErr) =>
      // Convert Bidir.typeError to VQLError.typeError
      Error({
        kind: Error.TypeMismatch({
          expected: "well-typed query",
          found: Bidir.formatTypeError(typeErr),
        }),
        hexad_id: None,
        modality: None,
        context: Bidir.formatTypeError(typeErr),
      })
    }
  }
}

// ============================================================================
// Proof Generation Verification
// ============================================================================

type proofGenerationResult = Result<proofPlan, Error.typeError>

and proofPlan = {
  contract: string,
  proofType: AST.proofType,
  witnessFields: array<string>,
  circuit: string,
  estimatedTimeMs: int,
}

let planProofGeneration = (query: AST.query, context: typeContext): proofGenerationResult => {
  switch query.proof {
  | None =>
    Error({
      kind: Error.MissingTypeAnnotation("proof"),
      hexad_id: None,
      modality: None,
      context: "No PROOF clause in query",
    })
  | Some(proofSpecs) => {
      let bidirCtx = toBidirContext(context)
      let resolvedMods = Types.resolveModalities(query.modalities)
      let resultInfo: Types.queryResultInfo = {
        modalities: resolvedMods,
        projections: [],
        aggregates: [],
      }
      switch ProofObl.generateObligations(bidirCtx, proofSpecs, resultInfo) {
      | Error(msg) =>
        Error({
          kind: Error.ProofGenerationFailed({
            contract: switch proofSpecs[0] {
            | Some(s) => s.contractName
            | None => "unknown"
            },
            error: msg,
          }),
          hexad_id: None,
          modality: None,
          context: msg,
        })
      | Ok(plan) =>
        // Return the first obligation as the primary plan (backward compat)
        switch plan.obligations[0] {
        | Some(obl) =>
          Ok({
            contract: obl.contractName,
            proofType: switch proofSpecs[0] {
            | Some(s) => s.proofType
            | None => Existence
            },
            witnessFields: obl.witnessFields,
            circuit: obl.circuit,
            estimatedTimeMs: plan.totalEstimatedTimeMs,
          })
        | None =>
          Error({
            kind: Error.MissingTypeAnnotation("proof"),
            hexad_id: None,
            modality: None,
            context: "No proof obligations generated",
          })
        }
      }
    }
  }
}

// ============================================================================
// SQL-Compat Validation
// ============================================================================

let validateAggregates = (query: AST.query): typeCheckResult => {
  switch (query.having, query.groupBy) {
  | (Some(_), None) =>
    Error({
      kind: Error.ContractViolation({
        contract: "sql-compat",
        reason: "HAVING clause requires GROUP BY",
      }),
      hexad_id: None,
      modality: None,
      context: "Add a GROUP BY clause or remove the HAVING clause",
    })
  | _ => Ok()
  }
}

let validateOrderByModalities = (query: AST.query): typeCheckResult => {
  switch query.orderBy {
  | None => Ok()
  | Some(items) => {
      let invalidField = items->Belt.Array.getBy(item => {
        !(query.modalities->Belt.Array.some(m => m == item.field.modality || m == All))
      })
      switch invalidField {
      | None => Ok()
      | Some(item) => {
          let modStr = modalityToString(item.field.modality)
          Error({
            kind: Error.ContractViolation({
              contract: "order-by-validation",
              reason: `ORDER BY references modality ${modStr} which is not in SELECT`,
            }),
            hexad_id: None,
            modality: Some(modStr),
            context: `Add ${modStr} to your SELECT clause or remove it from ORDER BY`,
          })
        }
      }
    }
  }
}

let validateGroupByModalities = (query: AST.query): typeCheckResult => {
  switch query.groupBy {
  | None => Ok()
  | Some(fields) => {
      let invalidField = fields->Belt.Array.getBy(f => {
        !(query.modalities->Belt.Array.some(m => m == f.modality || m == All))
      })
      switch invalidField {
      | None => Ok()
      | Some(field) => {
          let modStr = modalityToString(field.modality)
          Error({
            kind: Error.ContractViolation({
              contract: "group-by-validation",
              reason: `GROUP BY references modality ${modStr} which is not in SELECT`,
            }),
            hexad_id: None,
            modality: Some(modStr),
            context: `Add ${modStr} to your SELECT clause or remove it from GROUP BY`,
          })
        }
      }
    }
  }
}

let checkSqlCompat = (query: AST.query): typeCheckResult => {
  switch validateAggregates(query) {
  | Error(e) => Error(e)
  | Ok() =>
    switch validateOrderByModalities(query) {
    | Error(e) => Error(e)
    | Ok() => validateGroupByModalities(query)
    }
  }
}

// ============================================================================
// Utility Functions
// ============================================================================

let proofTypeToString = (pt: AST.proofType): string => {
  switch pt {
  | Existence => "EXISTENCE"
  | Citation => "CITATION"
  | Access => "ACCESS"
  | Integrity => "INTEGRITY"
  | Provenance => "PROVENANCE"
  | Custom => "CUSTOM"
  }
}

let modalityToString = (m: AST.modality): string => {
  switch m {
  | Graph => "GRAPH"
  | Vector => "VECTOR"
  | Tensor => "TENSOR"
  | Semantic => "SEMANTIC"
  | Document => "DOCUMENT"
  | Temporal => "TEMPORAL"
  | All => "*"
  }
}

let primitiveTypeToString = (pt: primitiveType): string => {
  switch pt {
  | TString => "String"
  | TInt => "Int"
  | TFloat => "Float"
  | TBool => "Bool"
  | TArray(inner) => `Array<${primitiveTypeToString(inner)}>`
  | TVector(dim) => `Vector<${Belt.Int.toString(dim)}>`
  | TUuid => "UUID"
  }
}

// ============================================================================
// Registration (backward-compatible)
// ============================================================================

let registerContract = (
  context: typeContext,
  name: string,
  info: contractInfo,
): typeContext => {
  let newContracts = Js.Dict.fromArray(Js.Dict.entries(context.contracts))
  Js.Dict.set(newContracts, name, info)
  {...context, contracts: newContracts}
}

// Export for testing
let testCreateConstraint = (
  constraintType: string,
  param: string,
): option<constraint> => {
  switch constraintType {
  | "FieldMustExist" => Some(FieldMustExist(param))
  | "ModalityRequired" =>
    switch param {
    | "GRAPH" => Some(ModalityRequired(Graph))
    | "VECTOR" => Some(ModalityRequired(Vector))
    | "SEMANTIC" => Some(ModalityRequired(Semantic))
    | _ => None
    }
  | _ => None
  }
}
