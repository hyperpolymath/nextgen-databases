// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith operation types and CBOR encoding

import lithoglyph/cbor
import gleam/list
import gleam/option.{type Option}
import types.{
  type CellValue, type Field, type FieldType, Attachment, AttachmentValue,
  Barcode, Checkbox, CheckboxValue, Date, DateTime, DateValue, Email, Formula,
  Link, LinkValue, Lookup, MultiSelect, MultiSelectValue, NullValue, Number,
  NumberValue, Phone, Rating, Rollup, Select, SelectValue, Text, TextValue, Url,
}

/// Lith operations
pub type Operation {
  // Base operations
  CreateBase(id: String, name: String, description: Option(String))
  GetBase(id: String)
  ListBases
  UpdateBase(id: String, name: Option(String), description: Option(String))
  DeleteBase(id: String)
  // Table operations
  CreateTable(
    base_id: String,
    id: String,
    name: String,
    fields: List(Field),
    primary_field_id: String,
  )
  GetTable(base_id: String, table_id: String)
  ListTables(base_id: String)
  UpdateTable(base_id: String, table_id: String, name: Option(String))
  DeleteTable(base_id: String, table_id: String)
  // Row operations
  CreateRow(base_id: String, table_id: String, id: String, cells: List(CellData))
  GetRow(base_id: String, table_id: String, row_id: String)
  ListRows(
    base_id: String,
    table_id: String,
    limit: Option(Int),
    offset: Option(Int),
    filter: Option(String),
  )
  UpdateRow(
    base_id: String,
    table_id: String,
    row_id: String,
    cells: List(CellData),
    rationale: Option(String),
  )
  DeleteRow(base_id: String, table_id: String, row_id: String)
  // Cell operations
  GetCell(base_id: String, table_id: String, row_id: String, field_id: String)
  UpdateCell(
    base_id: String,
    table_id: String,
    row_id: String,
    field_id: String,
    value: CellValue,
    rationale: Option(String),
  )
  // Provenance
  GetProvenance(
    base_id: String,
    table_id: String,
    row_id: String,
    field_id: String,
  )
}

/// Cell data for row operations
pub type CellData {
  CellData(field_id: String, value: CellValue)
}

/// Encode an operation to CBOR
pub fn encode_operation(op: Operation) -> BitArray {
  case op {
    CreateBase(id, name, desc) -> encode_create_base(id, name, desc)
    GetBase(id) -> encode_get_base(id)
    ListBases -> encode_list_bases()
    UpdateBase(id, name, desc) -> encode_update_base(id, name, desc)
    DeleteBase(id) -> encode_delete_base(id)
    CreateTable(base_id, id, name, fields, primary) ->
      encode_create_table(base_id, id, name, fields, primary)
    GetTable(base_id, table_id) -> encode_get_table(base_id, table_id)
    ListTables(base_id) -> encode_list_tables(base_id)
    UpdateTable(base_id, table_id, name) ->
      encode_update_table(base_id, table_id, name)
    DeleteTable(base_id, table_id) -> encode_delete_table(base_id, table_id)
    CreateRow(base_id, table_id, id, cells) ->
      encode_create_row(base_id, table_id, id, cells)
    GetRow(base_id, table_id, row_id) ->
      encode_get_row(base_id, table_id, row_id)
    ListRows(base_id, table_id, limit, offset, filter) ->
      encode_list_rows(base_id, table_id, limit, offset, filter)
    UpdateRow(base_id, table_id, row_id, cells, rationale) ->
      encode_update_row(base_id, table_id, row_id, cells, rationale)
    DeleteRow(base_id, table_id, row_id) ->
      encode_delete_row(base_id, table_id, row_id)
    GetCell(base_id, table_id, row_id, field_id) ->
      encode_get_cell(base_id, table_id, row_id, field_id)
    UpdateCell(base_id, table_id, row_id, field_id, value, rationale) ->
      encode_update_cell(base_id, table_id, row_id, field_id, value, rationale)
    GetProvenance(base_id, table_id, row_id, field_id) ->
      encode_get_provenance(base_id, table_id, row_id, field_id)
  }
}

// ============================================================
// Operation Encoders
// ============================================================

fn encode_create_base(
  id: String,
  name: String,
  desc: Option(String),
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("create_base")),
    #(cbor.encode_text("id"), cbor.encode_text(id)),
    #(cbor.encode_text("name"), cbor.encode_text(name)),
    #(cbor.encode_text("description"), cbor.encode_optional(desc, cbor.encode_text)),
  ])
}

fn encode_get_base(id: String) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("get_base")),
    #(cbor.encode_text("id"), cbor.encode_text(id)),
  ])
}

fn encode_list_bases() -> BitArray {
  cbor.encode_map([#(cbor.encode_text("op"), cbor.encode_text("list_bases"))])
}

fn encode_update_base(
  id: String,
  name: Option(String),
  desc: Option(String),
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("update_base")),
    #(cbor.encode_text("id"), cbor.encode_text(id)),
    #(cbor.encode_text("name"), cbor.encode_optional(name, cbor.encode_text)),
    #(cbor.encode_text("description"), cbor.encode_optional(desc, cbor.encode_text)),
  ])
}

fn encode_delete_base(id: String) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("delete_base")),
    #(cbor.encode_text("id"), cbor.encode_text(id)),
  ])
}

fn encode_create_table(
  base_id: String,
  id: String,
  name: String,
  fields: List(Field),
  primary_field_id: String,
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("create_table")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("id"), cbor.encode_text(id)),
    #(cbor.encode_text("name"), cbor.encode_text(name)),
    #(cbor.encode_text("fields"), encode_fields(fields)),
    #(cbor.encode_text("primary_field_id"), cbor.encode_text(primary_field_id)),
  ])
}

fn encode_get_table(base_id: String, table_id: String) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("get_table")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
  ])
}

fn encode_list_tables(base_id: String) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("list_tables")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
  ])
}

fn encode_update_table(
  base_id: String,
  table_id: String,
  name: Option(String),
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("update_table")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("name"), cbor.encode_optional(name, cbor.encode_text)),
  ])
}

fn encode_delete_table(base_id: String, table_id: String) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("delete_table")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
  ])
}

fn encode_create_row(
  base_id: String,
  table_id: String,
  id: String,
  cells: List(CellData),
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("create_row")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("id"), cbor.encode_text(id)),
    #(cbor.encode_text("cells"), encode_cells(cells)),
  ])
}

fn encode_get_row(
  base_id: String,
  table_id: String,
  row_id: String,
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("get_row")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("row_id"), cbor.encode_text(row_id)),
  ])
}

fn encode_list_rows(
  base_id: String,
  table_id: String,
  limit: Option(Int),
  offset: Option(Int),
  filter: Option(String),
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("list_rows")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("limit"), cbor.encode_optional(limit, cbor.encode_int)),
    #(cbor.encode_text("offset"), cbor.encode_optional(offset, cbor.encode_int)),
    #(cbor.encode_text("filter"), cbor.encode_optional(filter, cbor.encode_text)),
  ])
}

fn encode_update_row(
  base_id: String,
  table_id: String,
  row_id: String,
  cells: List(CellData),
  rationale: Option(String),
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("update_row")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("row_id"), cbor.encode_text(row_id)),
    #(cbor.encode_text("cells"), encode_cells(cells)),
    #(cbor.encode_text("rationale"), cbor.encode_optional(rationale, cbor.encode_text)),
  ])
}

fn encode_delete_row(
  base_id: String,
  table_id: String,
  row_id: String,
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("delete_row")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("row_id"), cbor.encode_text(row_id)),
  ])
}

fn encode_get_cell(
  base_id: String,
  table_id: String,
  row_id: String,
  field_id: String,
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("get_cell")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("row_id"), cbor.encode_text(row_id)),
    #(cbor.encode_text("field_id"), cbor.encode_text(field_id)),
  ])
}

fn encode_update_cell(
  base_id: String,
  table_id: String,
  row_id: String,
  field_id: String,
  value: CellValue,
  rationale: Option(String),
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("update_cell")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("row_id"), cbor.encode_text(row_id)),
    #(cbor.encode_text("field_id"), cbor.encode_text(field_id)),
    #(cbor.encode_text("value"), encode_cell_value(value)),
    #(cbor.encode_text("rationale"), cbor.encode_optional(rationale, cbor.encode_text)),
  ])
}

fn encode_get_provenance(
  base_id: String,
  table_id: String,
  row_id: String,
  field_id: String,
) -> BitArray {
  cbor.encode_map([
    #(cbor.encode_text("op"), cbor.encode_text("get_provenance")),
    #(cbor.encode_text("base_id"), cbor.encode_text(base_id)),
    #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
    #(cbor.encode_text("row_id"), cbor.encode_text(row_id)),
    #(cbor.encode_text("field_id"), cbor.encode_text(field_id)),
  ])
}

// ============================================================
// Helper Encoders
// ============================================================

fn encode_cell_value(value: CellValue) -> BitArray {
  case value {
    TextValue(s) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("text")),
        #(cbor.encode_text("value"), cbor.encode_text(s)),
      ])
    NumberValue(n) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("number")),
        #(cbor.encode_text("value"), cbor.encode_float(n)),
      ])
    SelectValue(s) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("select")),
        #(cbor.encode_text("value"), cbor.encode_text(s)),
      ])
    MultiSelectValue(items) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("multi_select")),
        #(
          cbor.encode_text("value"),
          cbor.encode_array(list.map(items, cbor.encode_text)),
        ),
      ])
    DateValue(s) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("date")),
        #(cbor.encode_text("value"), cbor.encode_text(s)),
      ])
    CheckboxValue(b) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("checkbox")),
        #(cbor.encode_text("value"), cbor.encode_bool(b)),
      ])
    LinkValue(ids) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("link")),
        #(
          cbor.encode_text("value"),
          cbor.encode_array(list.map(ids, cbor.encode_text)),
        ),
      ])
    AttachmentValue(ids) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("attachment")),
        #(
          cbor.encode_text("value"),
          cbor.encode_array(list.map(ids, cbor.encode_text)),
        ),
      ])
    NullValue -> cbor.encode_null()
  }
}

fn encode_cells(cells: List(CellData)) -> BitArray {
  cbor.encode_array(list.map(cells, encode_cell_data))
}

fn encode_cell_data(cell: CellData) -> BitArray {
  let CellData(field_id, value) = cell
  cbor.encode_map([
    #(cbor.encode_text("field_id"), cbor.encode_text(field_id)),
    #(cbor.encode_text("value"), encode_cell_value(value)),
  ])
}

fn encode_fields(fields: List(Field)) -> BitArray {
  cbor.encode_array(list.map(fields, encode_field))
}

fn encode_field(field: Field) -> BitArray {
  let types.Field(id, name, field_type, required, default_value) = field
  cbor.encode_map([
    #(cbor.encode_text("id"), cbor.encode_text(id)),
    #(cbor.encode_text("name"), cbor.encode_text(name)),
    #(cbor.encode_text("field_type"), encode_field_type(field_type)),
    #(cbor.encode_text("required"), cbor.encode_bool(required)),
    #(cbor.encode_text("default_value"), cbor.encode_optional(default_value, cbor.encode_text)),
  ])
}

fn encode_field_type(ft: FieldType) -> BitArray {
  case ft {
    Text -> cbor.encode_text("text")
    Number -> cbor.encode_text("number")
    Select(opts) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("select")),
        #(
          cbor.encode_text("options"),
          cbor.encode_array(list.map(opts, cbor.encode_text)),
        ),
      ])
    MultiSelect(opts) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("multi_select")),
        #(
          cbor.encode_text("options"),
          cbor.encode_array(list.map(opts, cbor.encode_text)),
        ),
      ])
    Date -> cbor.encode_text("date")
    DateTime -> cbor.encode_text("datetime")
    Checkbox -> cbor.encode_text("checkbox")
    Link(table_id) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("link")),
        #(cbor.encode_text("table_id"), cbor.encode_text(table_id)),
      ])
    Attachment -> cbor.encode_text("attachment")
    Formula(expr) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("formula")),
        #(cbor.encode_text("expression"), cbor.encode_text(expr)),
      ])
    Rollup(linked, agg) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("rollup")),
        #(cbor.encode_text("linked_field"), cbor.encode_text(linked)),
        #(cbor.encode_text("aggregation"), cbor.encode_text(agg)),
      ])
    Lookup(linked, lookup) ->
      cbor.encode_map([
        #(cbor.encode_text("type"), cbor.encode_text("lookup")),
        #(cbor.encode_text("linked_field"), cbor.encode_text(linked)),
        #(cbor.encode_text("lookup_field"), cbor.encode_text(lookup)),
      ])
    Url -> cbor.encode_text("url")
    Email -> cbor.encode_text("email")
    Phone -> cbor.encode_text("phone")
    Rating -> cbor.encode_text("rating")
    Barcode -> cbor.encode_text("barcode")
  }
}
