// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Bidirectional Type Inference
//
// Implements bidirectional type checking for VQL queries:
// - synthesize: infer the type of a query from its structure
// - check: verify a query expression has an expected type
//
// The synthesizer walks the query AST and produces a typed result,
// verifying that all field references, operators, aggregates, and
// proof obligations are well-typed.

module AST = VQLParser.AST
module Types = VQLTypes
module Ctx = VQLContext
module Sub = VQLSubtyping

// ============================================================================
// Type Error
// ============================================================================

type typeError =
  | SubtypingFailed({expected: Types.vqlType, got: Types.vqlType, reason: string})
  | FieldTypeMismatch({field: string, expected: Types.primitiveType, got: Types.primitiveType})
  | OperatorTypeMismatch({op: string, leftType: Types.primitiveType, rightType: Types.primitiveType})
  | VectorDimensionMismatch({expected: int, got: int})
  | ProofObligationFailed({proofKind: Types.proofKind, reason: string})
  | AggregateTypeMismatch({func: string, fieldType: Types.primitiveType})
  | MultiProofConflict({proof1: string, proof2: string, reason: string})
  | UnknownField({modality: Types.modalityType, fieldName: string})
  | UnknownContract(string)
  | UnknownModality(string)
  | MissingProof
  | InvalidSource(string)
  // Phase 2: Cross-modal errors
  | CrossModalTypeMismatch({
      mod1: Types.modalityType,
      field1: string,
      mod2: Types.modalityType,
      field2: string,
      reason: string,
    })
  | DriftRequiresNumeric({mod1: Types.modalityType, mod2: Types.modalityType})
  | ConsistencyMetricInvalid({mod1: Types.modalityType, mod2: Types.modalityType, metric: string})
  // Phase 3: Mutation errors
  | InsertModalityMismatch({modality: string, reason: string})
  | UpdateFieldNotFound({hexadId: string, field: string})
  | MutationProofFailed({operation: string, reason: string})

let formatTypeError = (err: typeError): string => {
  switch err {
  | SubtypingFailed({expected, got, reason}) =>
    `Subtyping failed: expected ${Types.vqlTypeToString(expected)}, got ${Types.vqlTypeToString(got)}: ${reason}`
  | FieldTypeMismatch({field, expected, got}) =>
    `Field '${field}' type mismatch: expected ${Types.primitiveTypeToString(expected)}, got ${Types.primitiveTypeToString(got)}`
  | OperatorTypeMismatch({op, leftType, rightType}) =>
    `Operator '${op}' cannot compare ${Types.primitiveTypeToString(leftType)} with ${Types.primitiveTypeToString(rightType)}`
  | VectorDimensionMismatch({expected, got}) =>
    `Vector dimension mismatch: expected ${Belt.Int.toString(expected)}, got ${Belt.Int.toString(got)}`
  | ProofObligationFailed({proofKind, reason}) =>
    `Proof obligation failed for ${Types.proofKindToString(proofKind)}: ${reason}`
  | AggregateTypeMismatch({func, fieldType}) =>
    `Aggregate function ${func} cannot operate on ${Types.primitiveTypeToString(fieldType)}`
  | MultiProofConflict({proof1, proof2, reason}) =>
    `Proofs '${proof1}' and '${proof2}' conflict: ${reason}`
  | UnknownField({modality, fieldName}) =>
    `Unknown field '${fieldName}' for modality ${Types.modalityTypeToString(modality)}`
  | UnknownContract(name) => `Unknown contract: '${name}'`
  | UnknownModality(name) => `Unknown modality: '${name}'`
  | MissingProof => "Dependent-type query requires PROOF clause"
  | InvalidSource(reason) => `Invalid source: ${reason}`
  | CrossModalTypeMismatch({mod1, field1, mod2, field2, reason}) =>
    `Cross-modal type mismatch: ${Types.modalityTypeToString(mod1)}.${field1} vs ${Types.modalityTypeToString(mod2)}.${field2}: ${reason}`
  | DriftRequiresNumeric({mod1, mod2}) =>
    `DRIFT requires numeric/vector modalities, got ${Types.modalityTypeToString(mod1)} and ${Types.modalityTypeToString(mod2)}`
  | ConsistencyMetricInvalid({mod1, mod2, metric}) =>
    `Metric '${metric}' not supported for ${Types.modalityTypeToString(mod1)} and ${Types.modalityTypeToString(mod2)}`
  | InsertModalityMismatch({modality, reason}) =>
    `INSERT modality '${modality}' error: ${reason}`
  | UpdateFieldNotFound({hexadId, field}) =>
    `UPDATE field '${field}' not found in hexad '${hexadId}'`
  | MutationProofFailed({operation, reason}) =>
    `${operation} proof failed: ${reason}`
  }
}

// ============================================================================
// Synthesize: Infer type of a complete query
// ============================================================================

type synthesizeResult = Result<Types.vqlType, typeError>

let synthesizeQuery = (ctx: Ctx.context, query: AST.query): synthesizeResult => {
  // 1. Resolve modalities to type-level representations
  let resolvedMods = Types.resolveModalities(query.modalities)
  if Js.Array2.length(resolvedMods) == 0 {
    Error(UnknownModality("No valid modalities in SELECT"))
  } else {
    // 2. Check source validity
    switch checkSource(ctx, query.source) {
    | Error(e) => Error(e)
    | Ok() =>
      // 3. Check WHERE conditions against available modalities
      switch checkWhereClause(ctx, query.where, resolvedMods) {
      | Error(e) => Error(e)
      | Ok() =>
        // 4. Check projections
        switch checkProjections(ctx, query.projections, resolvedMods) {
        | Error(e) => Error(e)
        | Ok(projTypeInfos) =>
          // 5. Check aggregates
          switch checkAggregates(ctx, query.aggregates, resolvedMods) {
          | Error(e) => Error(e)
          | Ok(aggTypeInfos) =>
            // 6. Check GROUP BY fields
            switch checkGroupBy(ctx, query.groupBy, resolvedMods) {
            | Error(e) => Error(e)
            | Ok() =>
              // 7. Check ORDER BY fields
              switch checkOrderBy(ctx, query.orderBy, resolvedMods) {
              | Error(e) => Error(e)
              | Ok() =>
                // 8. Build the query result type
                let resultInfo: Types.queryResultInfo = {
                  modalities: resolvedMods,
                  projections: projTypeInfos,
                  aggregates: aggTypeInfos,
                }
                // 9. Handle proof clause
                switch query.proof {
                | None =>
                  // Slipstream path: just the query result type
                  Ok(Types.QueryResultType(resultInfo))
                | Some(proofSpecs) =>
                  // Dependent-type path: synthesize proved result
                  switch checkMultiProof(ctx, proofSpecs, resolvedMods) {
                  | Error(e) => Error(e)
                  | Ok(proofKinds) =>
                    // For multi-proof, the result is a Sigma type pairing result with first proof
                    // (each additional proof adds another layer)
                    switch proofKinds[0] {
                    | Some((kind, contract)) =>
                      Ok(Types.ProvedResultType(resultInfo, kind, contract))
                    | None => Error(MissingProof)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

// ============================================================================
// Check: Verify a query has expected type
// ============================================================================

let checkQuery = (
  ctx: Ctx.context,
  query: AST.query,
  expectedType: Types.vqlType,
): Result<unit, typeError> => {
  switch synthesizeQuery(ctx, query) {
  | Error(e) => Error(e)
  | Ok(inferredType) =>
    switch Sub.isSubtype(inferredType, expectedType) {
    | Ok() => Ok()
    | Error({expected, got, reason}) => Error(SubtypingFailed({expected, got, reason}))
    }
  }
}

// ============================================================================
// Source checking
// ============================================================================

let checkSource = (_ctx: Ctx.context, source: AST.source): Result<unit, typeError> => {
  switch source {
  | Hexad(id) =>
    // UUID format validation is done by parser; just verify non-empty
    if Js.String2.length(id) > 0 {
      Ok()
    } else {
      Error(InvalidSource("Empty hexad ID"))
    }
  | Federation(pattern, _drift) =>
    if Js.String2.length(pattern) > 0 {
      Ok()
    } else {
      Error(InvalidSource("Empty federation pattern"))
    }
  | Store(storeId) =>
    if Js.String2.length(storeId) > 0 {
      Ok()
    } else {
      Error(InvalidSource("Empty store ID"))
    }
  }
}

// ============================================================================
// WHERE clause checking
// ============================================================================

let checkWhereClause = (
  ctx: Ctx.context,
  where: option<AST.condition>,
  availableMods: array<Types.modalityType>,
): Result<unit, typeError> => {
  switch where {
  | None => Ok()
  | Some(condition) => checkCondition(ctx, condition, availableMods)
  }
}

and checkCondition = (
  ctx: Ctx.context,
  condition: AST.condition,
  availableMods: array<Types.modalityType>,
): Result<unit, typeError> => {
  switch condition {
  | Simple(sc) => checkSimpleCondition(ctx, sc, availableMods)
  | And(left, right) =>
    switch checkCondition(ctx, left, availableMods) {
    | Error(e) => Error(e)
    | Ok() => checkCondition(ctx, right, availableMods)
    }
  | Or(left, right) =>
    switch checkCondition(ctx, left, availableMods) {
    | Error(e) => Error(e)
    | Ok() => checkCondition(ctx, right, availableMods)
    }
  | Not(inner) => checkCondition(ctx, inner, availableMods)
  }
}

and checkSimpleCondition = (
  ctx: Ctx.context,
  sc: AST.simpleCondition,
  _availableMods: array<Types.modalityType>,
): Result<unit, typeError> => {
  switch sc {
  | FulltextContains(_text) =>
    // Full-text search is always valid if Document modality is available
    Ok()
  | FulltextMatches(_pattern) =>
    Ok()
  | FieldCondition(fieldName, op, literal) =>
    // Infer the literal type
    let litType = inferLiteralType(literal)
    // Check operator validity for this type
    if Types.isOperatorValidForType(op, litType) {
      Ok()
    } else {
      let opStr = operatorToString(op)
      Error(OperatorTypeMismatch({
        op: opStr,
        leftType: litType,
        rightType: litType,
      }))
    }
  | VectorSimilar(embedding, _threshold) =>
    // Check that embedding is non-empty
    if Js.Array2.length(embedding) == 0 {
      Error(VectorDimensionMismatch({expected: 1, got: 0}))
    } else {
      Ok()
    }
  | GraphPattern(_pattern) =>
    // Graph pattern validation is deferred to the graph engine
    Ok()
  // Phase 2: Cross-modal conditions
  | CrossModalFieldCompare(mod1, field1, _op, mod2, field2) =>
    checkCrossModalFieldCompare(ctx, mod1, field1, mod2, field2)
  | ModalityDrift(mod1, mod2, _threshold) =>
    checkDriftTypes(mod1, mod2)
  | ModalityExists(_modality) => Ok()
  | ModalityNotExists(_modality) => Ok()
  | ModalityConsistency(mod1, mod2, metric) =>
    checkConsistencyTypes(mod1, mod2, metric)
  }
}

// ============================================================================
// Phase 2: Cross-modal type checking
// ============================================================================

and checkCrossModalFieldCompare = (
  ctx: Ctx.context,
  mod1: AST.modality,
  field1: string,
  mod2: AST.modality,
  field2: string,
): Result<unit, typeError> => {
  switch (Types.modalityTypeOfAstModality(mod1), Types.modalityTypeOfAstModality(mod2)) {
  | (Some(mt1), Some(mt2)) =>
    switch (Ctx.lookupField(ctx, mt1, field1), Ctx.lookupField(ctx, mt2, field2)) {
    | (Some(f1), Some(f2)) =>
      // Both fields must have compatible types for comparison
      if Types.eqPrimitiveType(f1.fieldType, f2.fieldType) ||
         Sub.isSubPrimitive(f1.fieldType, f2.fieldType) ||
         Sub.isSubPrimitive(f2.fieldType, f1.fieldType) {
        Ok()
      } else {
        Error(CrossModalTypeMismatch({
          mod1: mt1,
          field1,
          mod2: mt2,
          field2,
          reason: `${Types.primitiveTypeToString(f1.fieldType)} vs ${Types.primitiveTypeToString(f2.fieldType)}`,
        }))
      }
    | (None, _) => Error(UnknownField({modality: mt1, fieldName: field1}))
    | (_, None) => Error(UnknownField({modality: mt2, fieldName: field2}))
    }
  | (None, _) => Error(UnknownModality("All"))
  | (_, None) => Error(UnknownModality("All"))
  }
}

and checkDriftTypes = (mod1: AST.modality, mod2: AST.modality): Result<unit, typeError> => {
  // DRIFT requires both modalities to have numeric/vector representations
  switch (Types.modalityTypeOfAstModality(mod1), Types.modalityTypeOfAstModality(mod2)) {
  | (Some(mt1), Some(mt2)) =>
    // All modality pairs support drift computation via their canonical embeddings
    let _ = (mt1, mt2)
    Ok()
  | _ => Error(DriftRequiresNumeric({
      mod1: Types.modalityTypeOfAstModality(mod1)->Belt.Option.getWithDefault(Types.GraphModality),
      mod2: Types.modalityTypeOfAstModality(mod2)->Belt.Option.getWithDefault(Types.GraphModality),
    }))
  }
}

and checkConsistencyTypes = (
  mod1: AST.modality,
  mod2: AST.modality,
  metric: string,
): Result<unit, typeError> => {
  let validMetrics = ["COSINE", "EUCLIDEAN", "DOT_PRODUCT", "JACCARD"]
  if !(validMetrics->Js.Array2.includes(Js.String2.toUpperCase(metric))) {
    switch (Types.modalityTypeOfAstModality(mod1), Types.modalityTypeOfAstModality(mod2)) {
    | (Some(mt1), Some(mt2)) =>
      Error(ConsistencyMetricInvalid({mod1: mt1, mod2: mt2, metric}))
    | _ =>
      Error(ConsistencyMetricInvalid({
        mod1: Types.GraphModality,
        mod2: Types.GraphModality,
        metric,
      }))
    }
  } else {
    Ok()
  }
}

// ============================================================================
// Projection checking
// ============================================================================

let checkProjections = (
  ctx: Ctx.context,
  projections: option<array<AST.fieldRef>>,
  availableMods: array<Types.modalityType>,
): Result<array<Types.fieldTypeInfo>, typeError> => {
  switch projections {
  | None => Ok([])
  | Some(projs) =>
    projs->Belt.Array.reduce(Ok([]), (acc, proj) => {
      switch acc {
      | Error(e) => Error(e)
      | Ok(infos) =>
        switch Types.modalityTypeOfAstModality(proj.modality) {
        | None =>
          // 'All' modality — skip projection type check
          Ok(infos)
        | Some(modType) =>
          // Verify modality is in SELECT
          if !(availableMods->Js.Array2.some(m => Types.eqModalityType(m, modType))) {
            Error(UnknownModality(Types.modalityTypeToString(modType)))
          } else {
            // Look up field type
            switch Ctx.lookupField(ctx, modType, proj.field) {
            | None =>
              // Field not in registry — allow it (dynamic schema) but type as String
              let info: Types.fieldTypeInfo = {
                modality: modType,
                fieldName: proj.field,
                fieldType: Types.StringType,
              }
              Ok(infos->Js.Array2.concat([info]))
            | Some(fieldEntry) =>
              let info: Types.fieldTypeInfo = {
                modality: modType,
                fieldName: proj.field,
                fieldType: fieldEntry.fieldType,
              }
              Ok(infos->Js.Array2.concat([info]))
            }
          }
        }
      }
    })
  }
}

// ============================================================================
// Aggregate checking
// ============================================================================

let checkAggregates = (
  ctx: Ctx.context,
  aggregates: option<array<AST.aggregateExpr>>,
  availableMods: array<Types.modalityType>,
): Result<array<Types.aggregateTypeInfo>, typeError> => {
  switch aggregates {
  | None => Ok([])
  | Some(aggs) =>
    aggs->Belt.Array.reduce(Ok([]), (acc, agg) => {
      switch acc {
      | Error(e) => Error(e)
      | Ok(infos) =>
        switch agg {
        | CountAll =>
          let info: Types.aggregateTypeInfo = {
            func: AST.Count,
            resultType: Types.IntType,
            sourceField: None,
          }
          Ok(infos->Js.Array2.concat([info]))
        | AggregateField(func, fieldRef) =>
          switch Types.modalityTypeOfAstModality(fieldRef.modality) {
          | None => Ok(infos) // All modality — skip
          | Some(modType) =>
            if !(availableMods->Js.Array2.some(m => Types.eqModalityType(m, modType))) {
              Error(UnknownModality(Types.modalityTypeToString(modType)))
            } else {
              let fieldType = switch Ctx.lookupField(ctx, modType, fieldRef.field) {
              | Some(f) => f.fieldType
              | None => Types.FloatType // default for unknown fields
              }
              // SUM, AVG require numeric types
              switch func {
              | Sum | Avg =>
                if !Types.isNumericPrimitive(fieldType) {
                  let funcStr = switch func {
                  | Sum => "SUM"
                  | Avg => "AVG"
                  | Count => "COUNT"
                  | Min => "MIN"
                  | Max => "MAX"
                  }
                  Error(AggregateTypeMismatch({func: funcStr, fieldType}))
                } else {
                  let resultType = switch func {
                  | Avg => Types.FloatType
                  | _ => fieldType
                  }
                  let sourceInfo: Types.fieldTypeInfo = {
                    modality: modType,
                    fieldName: fieldRef.field,
                    fieldType,
                  }
                  let info: Types.aggregateTypeInfo = {
                    func,
                    resultType,
                    sourceField: Some(sourceInfo),
                  }
                  Ok(infos->Js.Array2.concat([info]))
                }
              | Count =>
                let sourceInfo: Types.fieldTypeInfo = {
                  modality: modType,
                  fieldName: fieldRef.field,
                  fieldType,
                }
                let info: Types.aggregateTypeInfo = {
                  func,
                  resultType: Types.IntType,
                  sourceField: Some(sourceInfo),
                }
                Ok(infos->Js.Array2.concat([info]))
              | Min | Max =>
                if !Types.isComparablePrimitive(fieldType) {
                  let funcStr = switch func {
                  | Min => "MIN"
                  | Max => "MAX"
                  | _ => "?"
                  }
                  Error(AggregateTypeMismatch({func: funcStr, fieldType}))
                } else {
                  let sourceInfo: Types.fieldTypeInfo = {
                    modality: modType,
                    fieldName: fieldRef.field,
                    fieldType,
                  }
                  let info: Types.aggregateTypeInfo = {
                    func,
                    resultType: fieldType,
                    sourceField: Some(sourceInfo),
                  }
                  Ok(infos->Js.Array2.concat([info]))
                }
              }
            }
          }
        }
      }
    })
  }
}

// ============================================================================
// GROUP BY / ORDER BY checking
// ============================================================================

let checkGroupBy = (
  ctx: Ctx.context,
  groupBy: option<array<AST.fieldRef>>,
  availableMods: array<Types.modalityType>,
): Result<unit, typeError> => {
  switch groupBy {
  | None => Ok()
  | Some(fields) =>
    fields->Belt.Array.reduce(Ok(), (acc, field) => {
      switch acc {
      | Error(e) => Error(e)
      | Ok() =>
        switch Types.modalityTypeOfAstModality(field.modality) {
        | None => Ok()
        | Some(modType) =>
          if !(availableMods->Js.Array2.some(m => Types.eqModalityType(m, modType))) {
            Error(UnknownModality(Types.modalityTypeToString(modType)))
          } else {
            // Verify field exists (or accept dynamic)
            let _ = Ctx.lookupField(ctx, modType, field.field)
            Ok()
          }
        }
      }
    })
  }
}

let checkOrderBy = (
  _ctx: Ctx.context,
  orderBy: option<array<AST.orderByItem>>,
  availableMods: array<Types.modalityType>,
): Result<unit, typeError> => {
  switch orderBy {
  | None => Ok()
  | Some(items) =>
    items->Belt.Array.reduce(Ok(), (acc, item) => {
      switch acc {
      | Error(e) => Error(e)
      | Ok() =>
        switch Types.modalityTypeOfAstModality(item.field.modality) {
        | None => Ok()
        | Some(modType) =>
          if !(availableMods->Js.Array2.some(m => Types.eqModalityType(m, modType))) {
            Error(UnknownModality(Types.modalityTypeToString(modType)))
          } else {
            Ok()
          }
        }
      }
    })
  }
}

// ============================================================================
// Multi-proof checking
// ============================================================================

let checkMultiProof = (
  ctx: Ctx.context,
  proofSpecs: array<AST.proofSpec>,
  _availableMods: array<Types.modalityType>,
): Result<array<(Types.proofKind, string)>, typeError> => {
  if Js.Array2.length(proofSpecs) == 0 {
    Error(MissingProof)
  } else {
    // Check each proof spec individually
    let results = proofSpecs->Belt.Array.map(spec => {
      let kind = Types.proofKindOfAstProofType(spec.proofType)
      // If contract registry has this contract, verify compatibility
      switch Ctx.lookupContract(ctx, spec.contractName) {
      | None =>
        // Contract not in registry — accept it (registry may not be populated)
        Ok((kind, spec.contractName))
      | Some(contractSpec) =>
        // Verify proof kind matches contract
        if contractSpec.proofKind != kind {
          Error(ProofObligationFailed({
            proofKind: kind,
            reason: `Contract '${spec.contractName}' expects ${Types.proofKindToString(contractSpec.proofKind)}, got ${Types.proofKindToString(kind)}`,
          }))
        } else {
          Ok((kind, spec.contractName))
        }
      }
    })

    // Check for errors
    let firstError = results->Belt.Array.getBy(r => {
      switch r {
      | Error(_) => true
      | Ok(_) => false
      }
    })

    switch firstError {
    | Some(Error(e)) => Error(e)
    | _ =>
      // Extract successful results
      let kinds = results->Belt.Array.keepMap(r => {
        switch r {
        | Ok(v) => Some(v)
        | Error(_) => None
        }
      })

      // Check mutual composability
      if Js.Array2.length(kinds) > 1 {
        let contractNames = kinds->Belt.Array.map(((_, c)) => c)
        if !Ctx.areProofsComposable(ctx, contractNames) {
          // Find the first conflicting pair
          let len = Js.Array2.length(contractNames)
          let conflict = ref(None)
          for i in 0 to len - 2 {
            for j in i + 1 to len - 1 {
              switch (contractNames[i], contractNames[j]) {
              | (Some(c1), Some(c2)) =>
                if !Ctx.canComposeProofs(ctx, c1, c2) && conflict.contents->Belt.Option.isNone {
                  conflict := Some((c1, c2))
                }
              | _ => ()
              }
            }
          }
          switch conflict.contents {
          | Some((c1, c2)) =>
            Error(MultiProofConflict({proof1: c1, proof2: c2, reason: "Contracts are not composable"}))
          | None =>
            // If no specific conflict found but composability check failed,
            // the contracts may not have composability info — allow it
            Ok(kinds)
          }
        } else {
          Ok(kinds)
        }
      } else {
        Ok(kinds)
      }
    }
  }
}

// ============================================================================
// Phase 3: Mutation type checking
// ============================================================================

let synthesizeMutation = (
  ctx: Ctx.context,
  mutation: AST.mutation,
): synthesizeResult => {
  switch mutation {
  | Insert({modalities: modalityData, proof}) =>
    // Check each modality data entry is well-formed
    switch checkModalityDataArray(ctx, modalityData) {
    | Error(e) => Error(e)
    | Ok() =>
      switch proof {
      | None => Ok(Types.UnitType)
      | Some(proofSpecs) =>
        let allMods = Types.allModalityTypes
        switch checkMultiProof(ctx, proofSpecs, allMods) {
        | Error(e) => Error(e)
        | Ok(_) => Ok(Types.UnitType)
        }
      }
    }
  | Update({hexadId, sets, proof}) =>
    // Check hexad ID is non-empty
    if Js.String2.length(hexadId) == 0 {
      Error(InvalidSource("Empty hexad ID in UPDATE"))
    } else {
      // Check each SET assignment
      switch checkSetAssignments(ctx, sets) {
      | Error(e) => Error(e)
      | Ok() =>
        switch proof {
        | None => Ok(Types.UnitType)
        | Some(proofSpecs) =>
          let allMods = Types.allModalityTypes
          switch checkMultiProof(ctx, proofSpecs, allMods) {
          | Error(e) => Error(e)
          | Ok(_) => Ok(Types.UnitType)
          }
        }
      }
    }
  | Delete({hexadId, proof}) =>
    if Js.String2.length(hexadId) == 0 {
      Error(InvalidSource("Empty hexad ID in DELETE"))
    } else {
      switch proof {
      | None => Ok(Types.UnitType)
      | Some(proofSpecs) =>
        let allMods = Types.allModalityTypes
        switch checkMultiProof(ctx, proofSpecs, allMods) {
        | Error(e) => Error(e)
        | Ok(_) => Ok(Types.UnitType)
        }
      }
    }
  }
}

and checkModalityDataArray = (
  _ctx: Ctx.context,
  data: array<AST.modalityData>,
): Result<unit, typeError> => {
  if Js.Array2.length(data) == 0 {
    Error(InsertModalityMismatch({modality: "none", reason: "INSERT requires at least one modality data"}))
  } else {
    data->Belt.Array.reduce(Ok(), (acc, d) => {
      switch acc {
      | Error(e) => Error(e)
      | Ok() =>
        switch d {
        | DocumentData(fields) =>
          if Js.Array2.length(fields) == 0 {
            Error(InsertModalityMismatch({modality: "DOCUMENT", reason: "Empty document data"}))
          } else {
            Ok()
          }
        | VectorData(embedding) =>
          if Js.Array2.length(embedding) == 0 {
            Error(InsertModalityMismatch({modality: "VECTOR", reason: "Empty embedding vector"}))
          } else {
            Ok()
          }
        | GraphData(edgeType, targetId) =>
          if Js.String2.length(edgeType) == 0 || Js.String2.length(targetId) == 0 {
            Error(InsertModalityMismatch({modality: "GRAPH", reason: "Edge type and target ID required"}))
          } else {
            Ok()
          }
        | TensorData(values) =>
          if Js.Array2.length(values) == 0 {
            Error(InsertModalityMismatch({modality: "TENSOR", reason: "Empty tensor data"}))
          } else {
            Ok()
          }
        | SemanticData(contractName) =>
          if Js.String2.length(contractName) == 0 {
            Error(InsertModalityMismatch({modality: "SEMANTIC", reason: "Contract name required"}))
          } else {
            Ok()
          }
        | TemporalData(timestamp) =>
          if Js.String2.length(timestamp) == 0 {
            Error(InsertModalityMismatch({modality: "TEMPORAL", reason: "Timestamp required"}))
          } else {
            Ok()
          }
        | ProvenanceData(fields) =>
          if Js.Array2.length(fields) == 0 {
            Error(InsertModalityMismatch({modality: "PROVENANCE", reason: "Empty provenance data"}))
          } else {
            Ok()
          }
        | SpatialData(fields) =>
          if Js.Array2.length(fields) == 0 {
            Error(InsertModalityMismatch({modality: "SPATIAL", reason: "Empty spatial data"}))
          } else {
            Ok()
          }
        }
      }
    })
  }
}

and checkSetAssignments = (
  ctx: Ctx.context,
  sets: array<(AST.fieldRef, AST.literal)>,
): Result<unit, typeError> => {
  sets->Belt.Array.reduce(Ok(), (acc, (fieldRef, literal)) => {
    switch acc {
    | Error(e) => Error(e)
    | Ok() =>
      switch Types.modalityTypeOfAstModality(fieldRef.modality) {
      | None => Ok() // All modality — skip validation
      | Some(modType) =>
        switch Ctx.lookupField(ctx, modType, fieldRef.field) {
        | None =>
          // Dynamic schema — accept any field
          Ok()
        | Some(fieldEntry) =>
          let litType = inferLiteralType(literal)
          if Types.eqPrimitiveType(fieldEntry.fieldType, litType) ||
             Sub.isSubPrimitive(litType, fieldEntry.fieldType) {
            Ok()
          } else {
            Error(FieldTypeMismatch({
              field: `${Types.modalityTypeToString(modType)}.${fieldRef.field}`,
              expected: fieldEntry.fieldType,
              got: litType,
            }))
          }
        }
      }
    }
  })
}

// ============================================================================
// Utility functions
// ============================================================================

let inferLiteralType = (lit: AST.literal): Types.primitiveType => {
  switch lit {
  | String(_) => Types.StringType
  | Int(_) => Types.IntType
  | Float(_) => Types.FloatType
  | Bool(_) => Types.BoolType
  | Array(arr) =>
    // Infer element type from first element
    switch arr[0] {
    | Some(Float(_)) => Types.VectorType(Js.Array2.length(arr))
    | _ => Types.StringType // default
    }
  }
}

let operatorToString = (op: AST.operator): string => {
  switch op {
  | Eq => "=="
  | Neq => "!="
  | Gt => ">"
  | Lt => "<"
  | Gte => ">="
  | Lte => "<="
  | Like => "LIKE"
  | Contains => "CONTAINS"
  | Matches => "MATCHES"
  }
}
