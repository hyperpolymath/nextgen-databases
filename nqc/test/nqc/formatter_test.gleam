// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// formatter_test.gleam — Comprehensive tests for query result formatting.
//
// Covers: parse_format, csv_escape, and format_result for all three output
// modes (Table, Json, Csv) with various input shapes including VQL-style
// responses, raw arrays, single objects, and empty data.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import gleeunit/should
import nqc/formatter

/// Coerce any value to Dynamic for testing. On the Erlang target, Dynamic
/// is just any term — this FFI function is identity.
@external(erlang, "test_ffi", "to_dynamic")
fn to_dynamic(value: a) -> Dynamic

// ---------------------------------------------------------------------------
// parse_format — string to OutputFormat conversion
// ---------------------------------------------------------------------------

pub fn parse_format_table_test() {
  should.equal(formatter.parse_format("table"), Ok(formatter.Table))
}

pub fn parse_format_json_test() {
  should.equal(formatter.parse_format("json"), Ok(formatter.Json))
}

pub fn parse_format_csv_test() {
  should.equal(formatter.parse_format("csv"), Ok(formatter.Csv))
}

pub fn parse_format_uppercase_table_test() {
  should.equal(formatter.parse_format("TABLE"), Ok(formatter.Table))
}

pub fn parse_format_mixed_case_json_test() {
  should.equal(formatter.parse_format("Json"), Ok(formatter.Json))
}

pub fn parse_format_uppercase_csv_test() {
  should.equal(formatter.parse_format("CSV"), Ok(formatter.Csv))
}

pub fn parse_format_unknown_returns_error_test() {
  let result = formatter.parse_format("xml")
  should.be_error(result)
}

pub fn parse_format_error_message_contains_input_test() {
  let assert Error(msg) = formatter.parse_format("yaml")
  should.be_true(string.contains(msg, "yaml"))
}

pub fn parse_format_empty_string_returns_error_test() {
  should.be_error(formatter.parse_format(""))
}

// ---------------------------------------------------------------------------
// csv_escape — RFC 4180 compliance
// ---------------------------------------------------------------------------

pub fn csv_escape_plain_string_unchanged_test() {
  should.equal(formatter.csv_escape("hello"), "hello")
}

pub fn csv_escape_empty_string_unchanged_test() {
  should.equal(formatter.csv_escape(""), "")
}

pub fn csv_escape_comma_gets_quoted_test() {
  should.equal(formatter.csv_escape("a,b"), "\"a,b\"")
}

pub fn csv_escape_double_quote_gets_escaped_test() {
  should.equal(formatter.csv_escape("say \"hi\""), "\"say \"\"hi\"\"\"")
}

pub fn csv_escape_newline_gets_quoted_test() {
  should.equal(formatter.csv_escape("line1\nline2"), "\"line1\nline2\"")
}

pub fn csv_escape_all_special_chars_test() {
  // String with comma, quote, and newline — all should be handled.
  let input = "a,\"b\"\nc"
  let result = formatter.csv_escape(input)
  should.be_true(string.starts_with(result, "\""))
  should.be_true(string.ends_with(result, "\""))
}

// ---------------------------------------------------------------------------
// format_result with JSON output — returns JSON encoding of input
// ---------------------------------------------------------------------------

pub fn format_result_json_integer_test() {
  let value = to_dynamic(42)
  let result = formatter.format_result(value, formatter.Json)
  should.equal(result, "42")
}

pub fn format_result_json_string_test() {
  let value = to_dynamic("hello")
  let result = formatter.format_result(value, formatter.Json)
  should.equal(result, "\"hello\"")
}

pub fn format_result_json_list_test() {
  let value = to_dynamic([1, 2, 3])
  let result = formatter.format_result(value, formatter.Json)
  should.be_true(string.contains(result, "1"))
  should.be_true(string.contains(result, "2"))
  should.be_true(string.contains(result, "3"))
}

// ---------------------------------------------------------------------------
// format_result with Table output — ASCII table formatting
// ---------------------------------------------------------------------------

pub fn format_result_table_empty_list_test() {
  let value = to_dynamic([])
  let result = formatter.format_result(value, formatter.Table)
  // Empty list should produce some output.
  should.be_true(string.length(result) > 0)
}

pub fn format_result_table_list_of_maps_test() {
  // Construct Erlang-style maps for table formatting. The FFI operates
  // on raw Erlang maps, so we build them via the Erlang map syntax
  // that Gleam's Dict compiles to.
  let row1 = to_dynamic(map_from_pairs([#("id", "1"), #("name", "Alice")]))
  let row2 = to_dynamic(map_from_pairs([#("id", "2"), #("name", "Bob")]))
  let value = to_dynamic([row1, row2])
  let result = formatter.format_result(value, formatter.Table)
  // Should contain separator dashes and row count.
  should.be_true(string.contains(result, "---"))
  should.be_true(string.contains(result, "rows"))
}

pub fn format_result_table_single_map_test() {
  let value = to_dynamic(map_from_pairs([#("status", "ok"), #("version", "1.0")]))
  let result = formatter.format_result(value, formatter.Table)
  should.be_true(string.contains(result, "status"))
  should.be_true(string.contains(result, "ok"))
}

pub fn format_result_table_vql_response_shape_test() {
  // VQL responses wrap data in {"success": true, "data": [...], "row_count": n}.
  let row = map_from_pairs([#("entity", "user-1"), #("status", "active")])
  let response = map_from_mixed([
    #("success", to_dynamic(True)),
    #("data", to_dynamic([to_dynamic(row)])),
    #("row_count", to_dynamic(1)),
  ])
  let value = to_dynamic(response)
  let result = formatter.format_result(value, formatter.Table)
  // Should extract the "data" field and format as table.
  should.be_true(string.contains(result, "entity"))
  should.be_true(string.contains(result, "user-1"))
}

// ---------------------------------------------------------------------------
// format_result with CSV output
// ---------------------------------------------------------------------------

pub fn format_result_csv_list_of_maps_test() {
  let row1 = to_dynamic(map_from_pairs([#("id", "1"), #("name", "Alice")]))
  let row2 = to_dynamic(map_from_pairs([#("id", "2"), #("name", "Bob")]))
  let value = to_dynamic([row1, row2])
  let result = formatter.format_result(value, formatter.Csv)
  let lines = string.split(result, "\n")
  // Should have header + 2 data rows.
  should.equal(list.length(lines), 3)
}

pub fn format_result_csv_empty_returns_empty_test() {
  let value = to_dynamic([])
  let result = formatter.format_result(value, formatter.Csv)
  should.equal(result, "")
}

pub fn format_result_csv_header_contains_column_names_test() {
  let row = to_dynamic(map_from_pairs([#("city", "London"), #("pop", "9000000")]))
  let value = to_dynamic([row])
  let result = formatter.format_result(value, formatter.Csv)
  let assert Ok(header) = list.first(string.split(result, "\n"))
  should.be_true(string.contains(header, "city"))
  should.be_true(string.contains(header, "pop"))
}

// ---------------------------------------------------------------------------
// Edge cases — scalars
// ---------------------------------------------------------------------------

pub fn format_result_table_scalar_renders_as_json_test() {
  // A scalar value (not a map or list) should fall through to JSON encoding.
  let value = to_dynamic(42)
  let result = formatter.format_result(value, formatter.Table)
  should.equal(result, "42")
}

pub fn format_result_csv_scalar_returns_empty_test() {
  // CSV with no list data should return empty.
  let value = to_dynamic(42)
  let result = formatter.format_result(value, formatter.Csv)
  should.equal(result, "")
}

// ---------------------------------------------------------------------------
// FFI helpers — build Erlang maps for testing
// ---------------------------------------------------------------------------

/// Build an Erlang map from string key-value pairs.
@external(erlang, "maps", "from_list")
fn map_from_pairs(pairs: List(#(String, String))) -> Dynamic

/// Build an Erlang map from string-key to Dynamic-value pairs.
@external(erlang, "maps", "from_list")
fn map_from_mixed(pairs: List(#(String, Dynamic))) -> Dynamic
