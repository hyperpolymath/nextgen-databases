// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Context — Typing environment for bidirectional type checking
//
// Maintains bindings, contract registry, modality field registries,
// and store capabilities.

module Types = VQLTypes

// ============================================================================
// Contract Specification
// ============================================================================

type contractSpec = {
  name: string,
  proofKind: Types.proofKind,
  requiredModalities: array<Types.modalityType>,
  requiredFields: array<(Types.modalityType, string, Types.primitiveType)>,
  composableWith: array<Types.proofKind>, // proof kinds this can compose with
}

// ============================================================================
// Field Registry — known fields per modality
// ============================================================================

type fieldEntry = {
  fieldName: string,
  fieldType: Types.primitiveType,
}

// ============================================================================
// Context
// ============================================================================

type context = {
  bindings: Js.Dict.t<Types.vqlType>,
  contracts: Js.Dict.t<contractSpec>,
  modalityFields: Js.Dict.t<array<fieldEntry>>,
  storeModalities: Js.Dict.t<array<Types.modalityType>>,
}

// ============================================================================
// Construction
// ============================================================================

let empty = (): context => {
  {
    bindings: Js.Dict.empty(),
    contracts: Js.Dict.empty(),
    modalityFields: Js.Dict.empty(),
    storeModalities: Js.Dict.empty(),
  }
}

// Default context with standard modality field registries
let defaultContext = (): context => {
  let fields = Js.Dict.empty()

  // Graph modality fields
  Js.Dict.set(fields, "GRAPH", [
    {fieldName: "predicate", fieldType: Types.StringType},
    {fieldName: "subject", fieldType: Types.StringType},
    {fieldName: "object", fieldType: Types.StringType},
    {fieldName: "centrality", fieldType: Types.FloatType},
    {fieldName: "degree", fieldType: Types.IntType},
    {fieldName: "edge_type", fieldType: Types.StringType},
  ])

  // Vector modality fields
  Js.Dict.set(fields, "VECTOR", [
    {fieldName: "embedding", fieldType: Types.VectorType(768)},
    {fieldName: "magnitude", fieldType: Types.FloatType},
    {fieldName: "dimension", fieldType: Types.IntType},
  ])

  // Tensor modality fields
  Js.Dict.set(fields, "TENSOR", [
    {fieldName: "rank", fieldType: Types.IntType},
    {fieldName: "dtype", fieldType: Types.StringType},
    {fieldName: "mean", fieldType: Types.FloatType},
    {fieldName: "std", fieldType: Types.FloatType},
  ])

  // Semantic modality fields
  Js.Dict.set(fields, "SEMANTIC", [
    {fieldName: "contract", fieldType: Types.StringType},
    {fieldName: "verified", fieldType: Types.BoolType},
    {fieldName: "verifier", fieldType: Types.StringType},
  ])

  // Document modality fields
  Js.Dict.set(fields, "DOCUMENT", [
    {fieldName: "name", fieldType: Types.StringType},
    {fieldName: "title", fieldType: Types.StringType},
    {fieldName: "severity", fieldType: Types.IntType},
    {fieldName: "author", fieldType: Types.StringType},
    {fieldName: "year", fieldType: Types.IntType},
    {fieldName: "doi", fieldType: Types.StringType},
    {fieldName: "impact_factor", fieldType: Types.FloatType},
    {fieldName: "count", fieldType: Types.IntType},
    {fieldName: "total", fieldType: Types.IntType},
  ])

  // Temporal modality fields
  Js.Dict.set(fields, "TEMPORAL", [
    {fieldName: "timestamp", fieldType: Types.TimestampType},
    {fieldName: "version", fieldType: Types.StringType},
    {fieldName: "actor", fieldType: Types.StringType},
  ])

  // Provenance modality fields
  Js.Dict.set(fields, "PROVENANCE", [
    {fieldName: "origin", fieldType: Types.StringType},
    {fieldName: "actor", fieldType: Types.StringType},
    {fieldName: "event_type", fieldType: Types.StringType},
    {fieldName: "chain_length", fieldType: Types.IntType},
    {fieldName: "chain_valid", fieldType: Types.BoolType},
    {fieldName: "content_hash", fieldType: Types.StringType},
    {fieldName: "description", fieldType: Types.StringType},
  ])

  // Spatial modality fields
  Js.Dict.set(fields, "SPATIAL", [
    {fieldName: "latitude", fieldType: Types.FloatType},
    {fieldName: "longitude", fieldType: Types.FloatType},
    {fieldName: "altitude", fieldType: Types.FloatType},
    {fieldName: "geometry_type", fieldType: Types.StringType},
    {fieldName: "srid", fieldType: Types.IntType},
  ])

  {
    bindings: Js.Dict.empty(),
    contracts: Js.Dict.empty(),
    modalityFields: fields,
    storeModalities: Js.Dict.empty(),
  }
}

// ============================================================================
// Lookup operations
// ============================================================================

let bind = (ctx: context, name: string, ty: Types.vqlType): context => {
  let newBindings = Js.Dict.fromArray(Js.Dict.entries(ctx.bindings))
  Js.Dict.set(newBindings, name, ty)
  {...ctx, bindings: newBindings}
}

let lookup = (ctx: context, name: string): option<Types.vqlType> => {
  Js.Dict.get(ctx.bindings, name)
}

let lookupContract = (ctx: context, name: string): option<contractSpec> => {
  Js.Dict.get(ctx.contracts, name)
}

let lookupModalityFields = (ctx: context, modality: Types.modalityType): array<fieldEntry> => {
  let key = Types.modalityTypeToString(modality)
  Js.Dict.get(ctx.modalityFields, key)->Belt.Option.getWithDefault([])
}

let lookupField = (
  ctx: context,
  modality: Types.modalityType,
  fieldName: string,
): option<fieldEntry> => {
  let fields = lookupModalityFields(ctx, modality)
  fields->Belt.Array.getBy(f => f.fieldName == fieldName)
}

let lookupStoreModalities = (ctx: context, storeId: string): option<array<Types.modalityType>> => {
  Js.Dict.get(ctx.storeModalities, storeId)
}

// ============================================================================
// Registration operations
// ============================================================================

let registerContract = (ctx: context, spec: contractSpec): context => {
  let newContracts = Js.Dict.fromArray(Js.Dict.entries(ctx.contracts))
  Js.Dict.set(newContracts, spec.name, spec)
  {...ctx, contracts: newContracts}
}

let registerField = (
  ctx: context,
  modality: Types.modalityType,
  entry: fieldEntry,
): context => {
  let key = Types.modalityTypeToString(modality)
  let existing = lookupModalityFields(ctx, modality)
  // Only add if not already present
  let alreadyExists = existing->Js.Array2.some(f => f.fieldName == entry.fieldName)
  if alreadyExists {
    ctx
  } else {
    let newFields = Js.Dict.fromArray(Js.Dict.entries(ctx.modalityFields))
    Js.Dict.set(newFields, key, existing->Js.Array2.concat([entry]))
    {...ctx, modalityFields: newFields}
  }
}

let registerStoreModalities = (
  ctx: context,
  storeId: string,
  modalities: array<Types.modalityType>,
): context => {
  let newStores = Js.Dict.fromArray(Js.Dict.entries(ctx.storeModalities))
  Js.Dict.set(newStores, storeId, modalities)
  {...ctx, storeModalities: newStores}
}

// ============================================================================
// Contract composition checks
// ============================================================================

// Check if two proof kinds can be composed together
let canComposeProofs = (ctx: context, contract1: string, contract2: string): bool => {
  switch (lookupContract(ctx, contract1), lookupContract(ctx, contract2)) {
  | (Some(spec1), Some(spec2)) =>
    spec1.composableWith->Js.Array2.some(k => k == spec2.proofKind) &&
    spec2.composableWith->Js.Array2.some(k => k == spec1.proofKind)
  | _ => false
  }
}

// Check if a list of proof specs are all mutually composable
let areProofsComposable = (ctx: context, contractNames: array<string>): bool => {
  let len = Js.Array2.length(contractNames)
  if len <= 1 {
    true
  } else {
    // Check all pairs
    let allOk = ref(true)
    for i in 0 to len - 2 {
      for j in i + 1 to len - 1 {
        switch (contractNames[i], contractNames[j]) {
        | (Some(c1), Some(c2)) =>
          if !canComposeProofs(ctx, c1, c2) {
            allOk := false
          }
        | _ => allOk := false
        }
      }
    }
    allOk.contents
  }
}
