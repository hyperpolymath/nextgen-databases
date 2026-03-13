// SPDX-License-Identifier: PMPL-1.0-or-later
// FQL (Lith Query Language) builder for type-safe queries

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// FQL query builder
pub opaque type Query {
  Query(
    collection: String,
    select_fields: List(String),
    where_clause: Option(String),
    order_by: Option(#(String, Order)),
    limit_count: Option(Int),
    offset_count: Option(Int),
  )
}

pub type Order {
  Asc
  Desc
}

/// Start building a query for a collection
pub fn from(collection: String) -> Query {
  Query(
    collection: collection,
    select_fields: [],
    where_clause: None,
    order_by: None,
    limit_count: None,
    offset_count: None,
  )
}

/// Select specific fields (empty = all fields)
pub fn select(query: Query, fields: List(String)) -> Query {
  Query(..query, select_fields: fields)
}

/// Add a where clause (FQL filter expression)
pub fn where(query: Query, clause: String) -> Query {
  Query(..query, where_clause: Some(clause))
}

/// Add ordering
pub fn order_by(query: Query, field: String, order: Order) -> Query {
  Query(..query, order_by: Some(#(field, order)))
}

/// Limit results
pub fn limit(query: Query, count: Int) -> Query {
  Query(..query, limit_count: Some(count))
}

/// Skip results
pub fn offset(query: Query, count: Int) -> Query {
  Query(..query, offset_count: Some(count))
}

/// Build the FQL string
pub fn build(query: Query) -> String {
  let select_part = case query.select_fields {
    [] -> "*"
    fields -> string.join(fields, ", ")
  }

  let base = "SELECT " <> select_part <> " FROM " <> query.collection

  let with_where = case query.where_clause {
    None -> base
    Some(clause) -> base <> " WHERE " <> clause
  }

  let with_order = case query.order_by {
    None -> with_where
    Some(#(field, Asc)) -> with_where <> " ORDER BY " <> field <> " ASC"
    Some(#(field, Desc)) -> with_where <> " ORDER BY " <> field <> " DESC"
  }

  let with_limit = case query.limit_count {
    None -> with_order
    Some(count) -> with_order <> " LIMIT " <> string.inspect(count)
  }

  case query.offset_count {
    None -> with_limit
    Some(count) -> with_limit <> " OFFSET " <> string.inspect(count)
  }
}

// Mutation builders

pub type Insert {
  Insert(collection: String, fields: List(#(String, String)))
}

pub type Update {
  Update(
    collection: String,
    document_id: String,
    fields: List(#(String, String)),
  )
}

pub type Delete {
  Delete(collection: String, document_id: String)
}

/// Build an INSERT statement
pub fn insert(collection: String, fields: List(#(String, String))) -> String {
  let field_names = list.map(fields, fn(f) { f.0 })
  let field_values = list.map(fields, fn(f) { "'" <> f.1 <> "'" })

  "INSERT INTO "
  <> collection
  <> " ("
  <> string.join(field_names, ", ")
  <> ") VALUES ("
  <> string.join(field_values, ", ")
  <> ")"
}

/// Build an UPDATE statement
pub fn update(
  collection: String,
  document_id: String,
  fields: List(#(String, String)),
) -> String {
  let set_clauses =
    list.map(fields, fn(f) { f.0 <> " = '" <> f.1 <> "'" })
    |> string.join(", ")

  "UPDATE " <> collection <> " SET " <> set_clauses <> " WHERE _id = '" <> document_id <> "'"
}

/// Build a DELETE statement
pub fn delete(collection: String, document_id: String) -> String {
  "DELETE FROM " <> collection <> " WHERE _id = '" <> document_id <> "'"
}
