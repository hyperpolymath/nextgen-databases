// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith ReScript Client - Query Builder

open Lith_Types

// =============================================================================
// Comparison Operators
// =============================================================================

type compareOp =
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  | Like
  | In

let compareOpToString = op =>
  switch op {
  | Eq => "="
  | Ne => "!="
  | Lt => "<"
  | Le => "<="
  | Gt => ">"
  | Ge => ">="
  | Like => "LIKE"
  | In => "IN"
  }

// =============================================================================
// Filter Expressions
// =============================================================================

type rec filterExpr =
  | Field(string, compareOp, JSON.t)
  | And(filterExpr, filterExpr)
  | Or(filterExpr, filterExpr)
  | Not(filterExpr)

let rec filterToGql = filter =>
  switch filter {
  | Field(name, op, value) => {
      let valueStr = switch value {
      | JSON.String(s) => `"${s}"`
      | JSON.Number(n) => Float.toString(n)
      | JSON.Boolean(b) => b ? "true" : "false"
      | JSON.Null => "null"
      | _ => JSON.stringify(value)
      }
      `${name} ${compareOpToString(op)} ${valueStr}`
    }
  | And(a, b) => `(${filterToGql(a)} AND ${filterToGql(b)})`
  | Or(a, b) => `(${filterToGql(a)} OR ${filterToGql(b)})`
  | Not(f) => `NOT (${filterToGql(f)})`
  }

// =============================================================================
// Query Builder
// =============================================================================

type queryBuilder = {
  mutable collection: option<string>,
  mutable fields: option<array<string>>,
  mutable filter: option<filterExpr>,
  mutable limit: option<int>,
  mutable offset: option<int>,
  mutable orderBy: option<(string, bool)>, // (field, ascending)
  mutable provenance: option<provenance>,
}

/** Create a new query builder */
let make = () => {
  collection: None,
  fields: None,
  filter: None,
  limit: None,
  offset: None,
  orderBy: None,
  provenance: None,
}

/** Set the collection to query */
let from = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

/** Set fields to select (default: all) */
let select = (builder, fieldList) => {
  builder.fields = Some(fieldList)
  builder
}

/** Add a WHERE filter */
let where = (builder, filter) => {
  builder.filter = Some(filter)
  builder
}

/** Add a field comparison filter (convenience) */
let whereField = (builder, fieldName, op, value) => {
  let newFilter = Field(fieldName, op, value)
  builder.filter = switch builder.filter {
  | Some(existing) => Some(And(existing, newFilter))
  | None => Some(newFilter)
  }
  builder
}

/** Set limit */
let limit = (builder, n) => {
  builder.limit = Some(n)
  builder
}

/** Set offset */
let offset = (builder, n) => {
  builder.offset = Some(n)
  builder
}

/** Set order by */
let orderBy = (builder, field, ~ascending=true) => {
  builder.orderBy = Some((field, ascending))
  builder
}

/** Add provenance metadata */
let withProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

/** Build the GQL query string */
let toGql = builder => {
  let collection = switch builder.collection {
  | Some(c) => c
  | None => panic("Collection is required")
  }

  let fieldsStr = switch builder.fields {
  | Some(fields) => fields->Array.join(", ")
  | None => "*"
  }

  let mut query = `SELECT ${fieldsStr} FROM ${collection}`

  switch builder.filter {
  | Some(filter) => query = query ++ ` WHERE ${filterToGql(filter)}`
  | None => ()
  }

  switch builder.orderBy {
  | Some((field, asc)) => {
      let dir = asc ? "ASC" : "DESC"
      query = query ++ ` ORDER BY ${field} ${dir}`
    }
  | None => ()
  }

  switch builder.limit {
  | Some(n) => query = query ++ ` LIMIT ${Int.toString(n)}`
  | None => ()
  }

  switch builder.offset {
  | Some(n) => query = query ++ ` OFFSET ${Int.toString(n)}`
  | None => ()
  }

  switch builder.provenance {
  | Some(prov) =>
    query =
      query ++ ` WITH PROVENANCE { actor: "${prov.actor}", rationale: "${prov.rationale}" }`
  | None => ()
  }

  query
}

// =============================================================================
// Insert Builder
// =============================================================================

type insertBuilder = {
  mutable collection: option<string>,
  mutable document: option<JSON.t>,
  mutable provenance: option<provenance>,
}

let makeInsert = () => {
  collection: None,
  document: None,
  provenance: None,
}

let into = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

let values = (builder, doc) => {
  builder.document = Some(doc)
  builder
}

let insertWithProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

let insertToGql = builder => {
  let collection = switch builder.collection {
  | Some(c) => c
  | None => panic("Collection is required")
  }

  let doc = switch builder.document {
  | Some(d) => JSON.stringify(d)
  | None => panic("Document is required")
  }

  let mut query = `INSERT INTO ${collection} ${doc}`

  switch builder.provenance {
  | Some(prov) =>
    query =
      query ++ ` WITH PROVENANCE { actor: "${prov.actor}", rationale: "${prov.rationale}" }`
  | None => ()
  }

  query
}

// =============================================================================
// Update Builder
// =============================================================================

type updateBuilder = {
  mutable collection: option<string>,
  mutable sets: array<(string, JSON.t)>,
  mutable filter: option<filterExpr>,
  mutable provenance: option<provenance>,
}

let makeUpdate = () => {
  collection: None,
  sets: [],
  filter: None,
  provenance: None,
}

let updateCollection = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

let set = (builder, field, value) => {
  builder.sets = builder.sets->Array.concat([(field, value)])
  builder
}

let updateWhere = (builder, filter) => {
  builder.filter = Some(filter)
  builder
}

let updateWithProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

let updateToGql = builder => {
  let collection = switch builder.collection {
  | Some(c) => c
  | None => panic("Collection is required")
  }

  if builder.sets->Array.length == 0 {
    panic("At least one SET clause is required")
  }

  let setsClauses =
    builder.sets
    ->Array.map(((field, value)) => {
      let valueStr = switch value {
      | JSON.String(s) => `"${s}"`
      | JSON.Number(n) => Float.toString(n)
      | JSON.Boolean(b) => b ? "true" : "false"
      | JSON.Null => "null"
      | _ => JSON.stringify(value)
      }
      `${field} = ${valueStr}`
    })
    ->Array.join(", ")

  let mut query = `UPDATE ${collection} SET ${setsClauses}`

  switch builder.filter {
  | Some(filter) => query = query ++ ` WHERE ${filterToGql(filter)}`
  | None => ()
  }

  switch builder.provenance {
  | Some(prov) =>
    query =
      query ++ ` WITH PROVENANCE { actor: "${prov.actor}", rationale: "${prov.rationale}" }`
  | None => ()
  }

  query
}

// =============================================================================
// Delete Builder
// =============================================================================

type deleteBuilder = {
  mutable collection: option<string>,
  mutable filter: option<filterExpr>,
  mutable provenance: option<provenance>,
}

let makeDelete = () => {
  collection: None,
  filter: None,
  provenance: None,
}

let deleteFrom = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

let deleteWhere = (builder, filter) => {
  builder.filter = Some(filter)
  builder
}

let deleteWithProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

let deleteToGql = builder => {
  let collection = switch builder.collection {
  | Some(c) => c
  | None => panic("Collection is required")
  }

  let mut query = `DELETE FROM ${collection}`

  switch builder.filter {
  | Some(filter) => query = query ++ ` WHERE ${filterToGql(filter)}`
  | None => ()
  }

  switch builder.provenance {
  | Some(prov) =>
    query =
      query ++ ` WITH PROVENANCE { actor: "${prov.actor}", rationale: "${prov.rationale}" }`
  | None => ()
  }

  query
}
