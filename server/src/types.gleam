// SPDX-License-Identifier: PMPL-1.0-or-later
// Core types for Glyphbase server

import gleam/option.{type Option}

/// Field types supported by Glyphbase
pub type FieldType {
  Text
  Number
  Select(options: List(String))
  MultiSelect(options: List(String))
  Date
  DateTime
  Checkbox
  Link(table_id: String)
  Attachment
  Formula(expression: String)
  Rollup(linked_field: String, aggregation: String)
  Lookup(linked_field: String, lookup_field: String)
  Url
  Email
  Phone
  Rating
  Barcode
}

/// Field configuration
pub type Field {
  Field(
    id: String,
    name: String,
    field_type: FieldType,
    required: Bool,
    default_value: Option(String),
  )
}

/// Cell values
pub type CellValue {
  TextValue(String)
  NumberValue(Float)
  SelectValue(String)
  MultiSelectValue(List(String))
  DateValue(String)
  CheckboxValue(Bool)
  LinkValue(List(String))
  AttachmentValue(List(String))
  NullValue
}

/// Provenance entry for a cell change
pub type ProvenanceEntry {
  ProvenanceEntry(
    timestamp: String,
    user_id: String,
    user_name: String,
    previous_value: Option(CellValue),
    new_value: CellValue,
    rationale: Option(String),
  )
}

/// A cell with its value and provenance history
pub type Cell {
  Cell(
    field_id: String,
    value: CellValue,
    provenance: List(ProvenanceEntry),
  )
}

/// A row in a table
pub type Row {
  Row(
    id: String,
    cells: List(Cell),
    created_at: String,
    updated_at: String,
  )
}

/// A table definition
pub type Table {
  Table(
    id: String,
    name: String,
    fields: List(Field),
    primary_field_id: String,
  )
}

/// A base (database)
pub type Base {
  Base(
    id: String,
    name: String,
    description: Option(String),
    tables: List(Table),
    created_at: String,
    updated_at: String,
  )
}

/// View types
pub type ViewType {
  Grid
  Kanban(group_by_field: String)
  Calendar(date_field: String)
  Gallery(image_field: String)
  Form
}

/// View configuration
pub type View {
  View(
    id: String,
    name: String,
    table_id: String,
    view_type: ViewType,
    visible_fields: List(String),
    sort_by: Option(#(String, SortDirection)),
    filter_by: Option(String),
  )
}

pub type SortDirection {
  Asc
  Desc
}
