// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Subtyping — Subtype relation for the VQL type system
//
// Implements the 6 subtyping rules from the formal spec (Section 4):
// 1. Reflexivity: t <: t
// 2. Transitivity: if t1 <: t2 and t2 <: t3 then t1 <: t3
// 3. List covariance: if t <: s then Array<t> <: Array<s>
// 4. Arrow contra/covariance: if s1 <: t1 and t2 <: s2 then (t1 -> t2) <: (s1 -> s2)
// 5. Hexad modality contravariance: requesting fewer modalities subtypes requesting more
// 6. Refinement subsumption: DEFERRED (needs SMT solver)

module Types = VQLTypes

type subtypeResult = Result<unit, subtypeError>

and subtypeError = {
  expected: Types.vqlType,
  got: Types.vqlType,
  reason: string,
}

// ============================================================================
// Primitive subtyping
// ============================================================================

// Numeric widening: Int <: Float (safe promotion)
let isSubPrimitive = (sub: Types.primitiveType, sup: Types.primitiveType): bool => {
  Types.eqPrimitiveType(sub, sup) ||
  switch (sub, sup) {
  | (IntType, FloatType) => true // Int widens to Float
  | (VectorType(_), VectorType(0)) => true // any vector subtypes unknown-dim vector
  | _ => false
  }
}

// ============================================================================
// Core subtype relation
// ============================================================================

let rec isSubtype = (sub: Types.vqlType, sup: Types.vqlType): subtypeResult => {
  // Rule 1: Reflexivity
  if Types.eqType(sub, sup) {
    Ok()
  } else {
    checkStructuralSubtype(sub, sup)
  }
}

and checkStructuralSubtype = (sub: Types.vqlType, sup: Types.vqlType): subtypeResult => {
  switch (sub, sup) {
  // Primitive widening
  | (Primitive(ps), Primitive(pp)) =>
    if isSubPrimitive(ps, pp) {
      Ok()
    } else {
      Error({
        expected: sup,
        got: sub,
        reason: `${Types.primitiveTypeToString(ps)} is not a subtype of ${Types.primitiveTypeToString(pp)}`,
      })
    }

  // Rule 3: List covariance — Array<t> <: Array<s> if t <: s
  | (ArrayType(innerSub), ArrayType(innerSup)) =>
    switch isSubtype(innerSub, innerSup) {
    | Ok() => Ok()
    | Error(e) =>
      Error({
        expected: sup,
        got: sub,
        reason: `Array element type mismatch: ${e.reason}`,
      })
    }

  // Rule 4: Arrow contra/covariance — Pi(x, t1, t2) <: Pi(x, s1, s2) if s1 <: t1 and t2 <: s2
  | (PiType(_, domSub, codSub), PiType(_, domSup, codSup)) =>
    // Contravariant in domain
    switch isSubtype(domSup, domSub) {
    | Ok() =>
      // Covariant in codomain
      switch isSubtype(codSub, codSup) {
      | Ok() => Ok()
      | Error(e) =>
        Error({
          expected: sup,
          got: sub,
          reason: `Function codomain: ${e.reason}`,
        })
      }
    | Error(e) =>
      Error({
        expected: sup,
        got: sub,
        reason: `Function domain (contravariant): ${e.reason}`,
      })
    }

  // Rule 5: Hexad modality contravariance
  // A hexad with MORE modalities is a subtype of one requesting FEWER
  // (having more data satisfies a request for less)
  | (HexadType(modsSub), HexadType(modsSup)) =>
    // Check that every modality in sup is present in sub
    let missing = modsSup->Belt.Array.keep(supMod => {
      !(modsSub->Js.Array2.some(subMod => Types.eqModalityType(subMod, supMod)))
    })
    if Js.Array2.length(missing) == 0 {
      Ok()
    } else {
      let missingStrs = missing->Belt.Array.map(Types.modalityTypeToString)->Js.Array2.joinWith(", ")
      Error({
        expected: sup,
        got: sub,
        reason: `Hexad missing required modalities: ${missingStrs}`,
      })
    }

  // ModalityType is a subtype of itself only (handled by reflexivity)
  | (ModalityType(a), ModalityType(b)) =>
    if Types.eqModalityType(a, b) {
      Ok()
    } else {
      Error({
        expected: sup,
        got: sub,
        reason: `${Types.modalityTypeToString(a)} is not ${Types.modalityTypeToString(b)}`,
      })
    }

  // NeverType is a subtype of everything (bottom type)
  | (NeverType, _) => Ok()

  // Everything is a subtype of UnitType (top for values)
  | (_, UnitType) => Ok()

  // ProvedResult subtypes plain QueryResult (can forget proof)
  | (ProvedResultType(info, _, _), QueryResultType(infoSup)) =>
    isSubQueryResult(info, infoSup)

  // QueryResult subtyping: covariant in modalities and projections
  | (QueryResultType(infoSub), QueryResultType(infoSup)) =>
    isSubQueryResult(infoSub, infoSup)

  // No other subtyping relationships
  | _ =>
    Error({
      expected: sup,
      got: sub,
      reason: `${Types.vqlTypeToString(sub)} is not a subtype of ${Types.vqlTypeToString(sup)}`,
    })
  }
}

// Query result subtyping: sub result must provide at least what sup requires
and isSubQueryResult = (
  sub: Types.queryResultInfo,
  sup: Types.queryResultInfo,
): subtypeResult => {
  // Check that all required modalities are present
  let missingMods = sup.modalities->Belt.Array.keep(supMod => {
    !(sub.modalities->Js.Array2.some(subMod => Types.eqModalityType(subMod, supMod)))
  })

  if Js.Array2.length(missingMods) > 0 {
    let missingStrs = missingMods->Belt.Array.map(Types.modalityTypeToString)->Js.Array2.joinWith(", ")
    Error({
      expected: QueryResultType(sup),
      got: QueryResultType(sub),
      reason: `Result missing modalities: ${missingStrs}`,
    })
  } else {
    Ok()
  }
}

// ============================================================================
// Rule 2: Transitivity check (explicit)
// If a <: b and b <: c, then a <: c
// ============================================================================

let transitiveSubtype = (
  a: Types.vqlType,
  b: Types.vqlType,
  c: Types.vqlType,
): subtypeResult => {
  switch isSubtype(a, b) {
  | Ok() =>
    switch isSubtype(b, c) {
    | Ok() => Ok()
    | Error(e) =>
      Error({
        expected: c,
        got: a,
        reason: `Transitivity failed at second step: ${e.reason}`,
      })
    }
  | Error(e) =>
    Error({
      expected: c,
      got: a,
      reason: `Transitivity failed at first step: ${e.reason}`,
    })
  }
}

// ============================================================================
// Convenience: check operator type compatibility
// ============================================================================

// Given two types and an operator, check if comparison is valid
let checkOperatorTypes = (
  leftType: Types.primitiveType,
  op: VQLParser.AST.operator,
  rightType: Types.primitiveType,
): subtypeResult => {
  // Types must be compatible (one subtype of the other, or same)
  let compatible =
    Types.eqPrimitiveType(leftType, rightType) ||
    isSubPrimitive(leftType, rightType) ||
    isSubPrimitive(rightType, leftType)

  if !compatible {
    Error({
      expected: Primitive(leftType),
      got: Primitive(rightType),
      reason: `Cannot compare ${Types.primitiveTypeToString(leftType)} with ${Types.primitiveTypeToString(rightType)}`,
    })
  } else if !Types.isOperatorValidForType(op, leftType) && !Types.isOperatorValidForType(op, rightType) {
    let opStr = switch op {
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
    Error({
      expected: Primitive(leftType),
      got: Primitive(rightType),
      reason: `Operator ${opStr} is not valid for types ${Types.primitiveTypeToString(leftType)} and ${Types.primitiveTypeToString(rightType)}`,
    })
  } else {
    Ok()
  }
}
