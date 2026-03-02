// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Types — Core type definitions for the bidirectional type checker
//
// Implements the type system from vql-type-system.adoc:
// - Pi types (dependent function types)
// - Sigma types (dependent pair types)
// - Modality types
// - Hexad types
// - Query result types
// - Proof types

module AST = VQLParser.AST

// ============================================================================
// Modality Types (type-level representation)
// ============================================================================

type modalityType =
  | GraphModality
  | VectorModality
  | TensorModality
  | SemanticModality
  | DocumentModality
  | TemporalModality
  | ProvenanceModality
  | SpatialModality

// ============================================================================
// Primitive Types
// ============================================================================

type primitiveType =
  | IntType
  | FloatType
  | StringType
  | BoolType
  | VectorType(int) // fixed-size vector with dimension
  | TensorType(array<int>) // shape
  | UuidType
  | TimestampType

// ============================================================================
// Core VQL Type System
// ============================================================================

type rec vqlType =
  | Primitive(primitiveType)
  | ArrayType(vqlType)
  | ModalityType(modalityType)
  | HexadType(array<modalityType>) // hexad carrying specific modalities
  | QueryResultType(queryResultInfo) // result of a SELECT query
  | ProofType(proofKind, string) // Proof<kind, contract>
  | ProvedResultType(queryResultInfo, proofKind, string) // Sigma(result, proof)
  | PiType(string, vqlType, vqlType) // Pi(x, domain, codomain)
  | SigmaType(string, vqlType, vqlType) // Sigma(x, fst, snd)
  | UnitType
  | NeverType

and queryResultInfo = {
  modalities: array<modalityType>,
  projections: array<fieldTypeInfo>,
  aggregates: array<aggregateTypeInfo>,
}

and fieldTypeInfo = {
  modality: modalityType,
  fieldName: string,
  fieldType: primitiveType,
}

and aggregateTypeInfo = {
  func: AST.aggregateFunc,
  resultType: primitiveType,
  sourceField: option<fieldTypeInfo>,
}

and proofKind =
  | ExistenceProof
  | CitationProof
  | AccessProof
  | IntegrityProof
  | ProvenanceProof
  | CustomProof

// ============================================================================
// Conversions from AST types
// ============================================================================

let proofKindOfAstProofType = (pt: AST.proofType): proofKind => {
  switch pt {
  | Existence => ExistenceProof
  | Citation => CitationProof
  | Access => AccessProof
  | Integrity => IntegrityProof
  | Provenance => ProvenanceProof
  | Custom => CustomProof
  }
}

let astProofTypeOfProofKind = (pk: proofKind): AST.proofType => {
  switch pk {
  | ExistenceProof => Existence
  | CitationProof => Citation
  | AccessProof => Access
  | IntegrityProof => Integrity
  | ProvenanceProof => Provenance
  | CustomProof => Custom
  }
}

let modalityTypeOfAstModality = (m: AST.modality): option<modalityType> => {
  switch m {
  | Graph => Some(GraphModality)
  | Vector => Some(VectorModality)
  | Tensor => Some(TensorModality)
  | Semantic => Some(SemanticModality)
  | Document => Some(DocumentModality)
  | Temporal => Some(TemporalModality)
  | Provenance => Some(ProvenanceModality)
  | Spatial => Some(SpatialModality)
  | All => None // 'All' expands to all modalities, not a single type
  }
}

let astModalityOfModalityType = (m: modalityType): AST.modality => {
  switch m {
  | GraphModality => Graph
  | VectorModality => Vector
  | TensorModality => Tensor
  | SemanticModality => Semantic
  | DocumentModality => Document
  | TemporalModality => Temporal
  | ProvenanceModality => Provenance
  | SpatialModality => Spatial
  }
}

let allModalityTypes: array<modalityType> = [
  GraphModality,
  VectorModality,
  TensorModality,
  SemanticModality,
  DocumentModality,
  TemporalModality,
  ProvenanceModality,
  SpatialModality,
]

let resolveModalities = (mods: array<AST.modality>): array<modalityType> => {
  if mods->Js.Array2.some(m => m == AST.All) {
    allModalityTypes
  } else {
    mods->Belt.Array.keepMap(modalityTypeOfAstModality)
  }
}

// ============================================================================
// String representations for error messages
// ============================================================================

let modalityTypeToString = (m: modalityType): string => {
  switch m {
  | GraphModality => "GRAPH"
  | VectorModality => "VECTOR"
  | TensorModality => "TENSOR"
  | SemanticModality => "SEMANTIC"
  | DocumentModality => "DOCUMENT"
  | TemporalModality => "TEMPORAL"
  | ProvenanceModality => "PROVENANCE"
  | SpatialModality => "SPATIAL"
  }
}

let primitiveTypeToString = (pt: primitiveType): string => {
  switch pt {
  | IntType => "Int"
  | FloatType => "Float"
  | StringType => "String"
  | BoolType => "Bool"
  | VectorType(dim) => `Vector<${Belt.Int.toString(dim)}>`
  | TensorType(shape) => {
      let shapeStr = shape->Belt.Array.map(Belt.Int.toString)->Js.Array2.joinWith("x")
      `Tensor<${shapeStr}>`
    }
  | UuidType => "UUID"
  | TimestampType => "Timestamp"
  }
}

let proofKindToString = (pk: proofKind): string => {
  switch pk {
  | ExistenceProof => "EXISTENCE"
  | CitationProof => "CITATION"
  | AccessProof => "ACCESS"
  | IntegrityProof => "INTEGRITY"
  | ProvenanceProof => "PROVENANCE"
  | CustomProof => "CUSTOM"
  }
}

let rec vqlTypeToString = (t: vqlType): string => {
  switch t {
  | Primitive(pt) => primitiveTypeToString(pt)
  | ArrayType(inner) => `Array<${vqlTypeToString(inner)}>`
  | ModalityType(m) => modalityTypeToString(m)
  | HexadType(mods) => {
      let modStrs = mods->Belt.Array.map(modalityTypeToString)->Js.Array2.joinWith(", ")
      `Hexad<${modStrs}>`
    }
  | QueryResultType(info) => {
      let modStrs = info.modalities->Belt.Array.map(modalityTypeToString)->Js.Array2.joinWith(", ")
      `QueryResult<${modStrs}>`
    }
  | ProofType(kind, contract) => `Proof<${proofKindToString(kind)}, ${contract}>`
  | ProvedResultType(info, kind, contract) => {
      let modStrs = info.modalities->Belt.Array.map(modalityTypeToString)->Js.Array2.joinWith(", ")
      `Sigma(QueryResult<${modStrs}>, Proof<${proofKindToString(kind)}, ${contract}>)`
    }
  | PiType(x, domain, codomain) =>
    `Pi(${x}: ${vqlTypeToString(domain)}) -> ${vqlTypeToString(codomain)}`
  | SigmaType(x, fst, snd) =>
    `Sigma(${x}: ${vqlTypeToString(fst)}, ${vqlTypeToString(snd)})`
  | UnitType => "Unit"
  | NeverType => "Never"
  }
}

// ============================================================================
// Type equality (structural)
// ============================================================================

let rec eqPrimitiveType = (a: primitiveType, b: primitiveType): bool => {
  switch (a, b) {
  | (IntType, IntType) => true
  | (FloatType, FloatType) => true
  | (StringType, StringType) => true
  | (BoolType, BoolType) => true
  | (VectorType(d1), VectorType(d2)) => d1 == d2
  | (TensorType(s1), TensorType(s2)) =>
    Js.Array2.length(s1) == Js.Array2.length(s2) &&
    s1->Js.Array2.everyi((v, i) => {
      switch s2[i] {
      | Some(v2) => v == v2
      | None => false
      }
    })
  | (UuidType, UuidType) => true
  | (TimestampType, TimestampType) => true
  | _ => false
  }
}

let eqModalityType = (a: modalityType, b: modalityType): bool => {
  switch (a, b) {
  | (GraphModality, GraphModality) => true
  | (VectorModality, VectorModality) => true
  | (TensorModality, TensorModality) => true
  | (SemanticModality, SemanticModality) => true
  | (DocumentModality, DocumentModality) => true
  | (TemporalModality, TemporalModality) => true
  | _ => false
  }
}

let rec eqType = (a: vqlType, b: vqlType): bool => {
  switch (a, b) {
  | (Primitive(pa), Primitive(pb)) => eqPrimitiveType(pa, pb)
  | (ArrayType(ia), ArrayType(ib)) => eqType(ia, ib)
  | (ModalityType(ma), ModalityType(mb)) => eqModalityType(ma, mb)
  | (HexadType(ma), HexadType(mb)) =>
    Js.Array2.length(ma) == Js.Array2.length(mb) &&
    ma->Js.Array2.every(m => mb->Js.Array2.some(m2 => eqModalityType(m, m2)))
  | (UnitType, UnitType) => true
  | (NeverType, NeverType) => true
  | (ProofType(k1, c1), ProofType(k2, c2)) => k1 == k2 && c1 == c2
  | _ => false
  }
}

// ============================================================================
// Numeric type checks (for aggregates and comparisons)
// ============================================================================

let isNumericPrimitive = (pt: primitiveType): bool => {
  switch pt {
  | IntType | FloatType => true
  | _ => false
  }
}

let isComparablePrimitive = (pt: primitiveType): bool => {
  switch pt {
  | IntType | FloatType | StringType | TimestampType => true
  | _ => false
  }
}

// Check if an operator is valid for given primitive types
let isOperatorValidForType = (op: AST.operator, pt: primitiveType): bool => {
  switch op {
  | Eq | Neq => true // equality works on all types
  | Gt | Lt | Gte | Lte => isComparablePrimitive(pt)
  | Like | Contains | Matches => pt == StringType
  }
}
