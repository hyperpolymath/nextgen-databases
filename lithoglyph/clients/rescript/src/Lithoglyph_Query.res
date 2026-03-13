// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>
//
// Lithoglyph ReScript Client - Query Builder
// Type-safe FDQL query construction with fluent API
//
// Compatible with Deno runtime (not Node/npm)

open Lithoglyph_Types

// =============================================================================
// Comparison Operators
// =============================================================================

/** Comparison operators for FDQL WHERE clauses */
type compareOp =
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  | Like
  | In

/** Convert a comparison operator to its FDQL string representation */
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

/** Recursive filter expression type for building complex WHERE clauses */
type rec filterExpr =
  | Field(string, compareOp, JSON.t)
  | And(filterExpr, filterExpr)
  | Or(filterExpr, filterExpr)
  | Not(filterExpr)

/** Convert a filter expression to its FDQL string representation */
let rec filterToFdql = filter =>
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
  | And(a, b) => `(${filterToFdql(a)} AND ${filterToFdql(b)})`
  | Or(a, b) => `(${filterToFdql(a)} OR ${filterToFdql(b)})`
  | Not(f) => `NOT (${filterToFdql(f)})`
  }

// =============================================================================
// SELECT Query Builder
// =============================================================================

/** Query builder for constructing SELECT statements */
type queryBuilder = {
  mutable collection: option<string>,
  mutable fields: option<array<string>>,
  mutable filter: option<filterExpr>,
  mutable limit: option<int>,
  mutable offset: option<int>,
  mutable orderBy: option<(string, bool)>,
  mutable provenance: option<provenance>,
}

/** Create a new SELECT query builder */
let make = () => {
  collection: None,
  fields: None,
  filter: None,
  limit: None,
  offset: None,
  orderBy: None,
  provenance: None,
}

/** Set the collection to query from */
let from = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

/** Set the fields to select (default: all) */
let select = (builder, fieldList) => {
  builder.fields = Some(fieldList)
  builder
}

/** Add a WHERE filter expression */
let where = (builder, filter) => {
  builder.filter = Some(filter)
  builder
}

/** Add a field comparison filter (convenience, ANDs with existing) */
let whereField = (builder, fieldName, op, value) => {
  let newFilter = Field(fieldName, op, value)
  builder.filter = switch builder.filter {
  | Some(existing) => Some(And(existing, newFilter))
  | None => Some(newFilter)
  }
  builder
}

/** Set the maximum number of rows to return */
let limit = (builder, n) => {
  builder.limit = Some(n)
  builder
}

/** Set the number of rows to skip */
let offset = (builder, n) => {
  builder.offset = Some(n)
  builder
}

/** Set the ordering field and direction */
let orderBy = (builder, field, ~ascending=true) => {
  builder.orderBy = Some((field, ascending))
  builder
}

/** Attach provenance metadata to the query */
let withProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

/** Build the FDQL query string from the query builder */
let toFdql = builder => {
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
  | Some(filter) => query = query ++ ` WHERE ${filterToFdql(filter)}`
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
// INSERT Builder
// =============================================================================

/** Builder for constructing INSERT statements */
type insertBuilder = {
  mutable collection: option<string>,
  mutable document: option<JSON.t>,
  mutable provenance: option<provenance>,
}

/** Create a new INSERT builder */
let makeInsert = () => {
  collection: None,
  document: None,
  provenance: None,
}

/** Set the target collection for the insert */
let into = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

/** Set the document to insert */
let values = (builder, doc) => {
  builder.document = Some(doc)
  builder
}

/** Attach provenance metadata to the insert */
let insertWithProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

/** Build the FDQL INSERT string */
let insertToFdql = builder => {
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
// UPDATE Builder
// =============================================================================

/** Builder for constructing UPDATE statements */
type updateBuilder = {
  mutable collection: option<string>,
  mutable sets: array<(string, JSON.t)>,
  mutable filter: option<filterExpr>,
  mutable provenance: option<provenance>,
}

/** Create a new UPDATE builder */
let makeUpdate = () => {
  collection: None,
  sets: [],
  filter: None,
  provenance: None,
}

/** Set the target collection for the update */
let updateCollection = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

/** Add a SET clause to the update */
let set = (builder, field, value) => {
  builder.sets = builder.sets->Array.concat([(field, value)])
  builder
}

/** Add a WHERE filter to the update */
let updateWhere = (builder, filter) => {
  builder.filter = Some(filter)
  builder
}

/** Attach provenance metadata to the update */
let updateWithProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

/** Build the FDQL UPDATE string */
let updateToFdql = builder => {
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
  | Some(filter) => query = query ++ ` WHERE ${filterToFdql(filter)}`
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
// DELETE Builder
// =============================================================================

/** Builder for constructing DELETE statements */
type deleteBuilder = {
  mutable collection: option<string>,
  mutable filter: option<filterExpr>,
  mutable provenance: option<provenance>,
}

/** Create a new DELETE builder */
let makeDelete = () => {
  collection: None,
  filter: None,
  provenance: None,
}

/** Set the target collection for the delete */
let deleteFrom = (builder, collectionName) => {
  builder.collection = Some(collectionName)
  builder
}

/** Add a WHERE filter to the delete */
let deleteWhere = (builder, filter) => {
  builder.filter = Some(filter)
  builder
}

/** Attach provenance metadata to the delete */
let deleteWithProvenance = (builder, prov) => {
  builder.provenance = Some(prov)
  builder
}

/** Build the FDQL DELETE string */
let deleteToFdql = builder => {
  let collection = switch builder.collection {
  | Some(c) => c
  | None => panic("Collection is required")
  }

  let mut query = `DELETE FROM ${collection}`

  switch builder.filter {
  | Some(filter) => query = query ++ ` WHERE ${filterToFdql(filter)}`
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
