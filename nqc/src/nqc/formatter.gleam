// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// formatter.gleam — Output formatting for query results.
//
// Formats JSON query results as tables, raw JSON, or CSV.
// Supports the response format from all three database backends.
// Uses Erlang FFI for ad-hoc dynamic field extraction since the Gleam
// dynamic/decode API is designed for statically-typed decoding, not the
// kind of ad-hoc field access needed for formatting arbitrary JSON.

import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/string

/// Output format selection.
pub type OutputFormat {
  Table
  Json
  Csv
}

/// Parse an output format from a string.
pub fn parse_format(s: String) -> Result(OutputFormat, String) {
  case string.lowercase(s) {
    "table" -> Ok(Table)
    "json" -> Ok(Json)
    "csv" -> Ok(Csv)
    _ -> Error("Unknown format: '" <> s <> "'. Use table, json, or csv.")
  }
}

/// Format a query result for display.
pub fn format_result(value: Dynamic, format: OutputFormat) -> String {
  case format {
    Json -> format_json(value)
    Table -> format_table(value)
    Csv -> format_csv(value)
  }
}

/// Format as pretty-printed JSON.
fn format_json(value: Dynamic) -> String {
  json_encode_dynamic(value)
}

/// Format as an ASCII table.
///
/// Handles two response shapes:
/// 1. VQL execute response: {"success": true, "data": [...], "row_count": n}
/// 2. Raw JSON object or array
fn format_table(value: Dynamic) -> String {
  // Try to extract the "data" field (VQL execute response format).
  // Falls back to the raw value if "data" doesn't exist.
  let data_result = extract_field_or_self(value, "data")

  // Try to treat data as a list of objects.
  let items = extract_list(data_result)
  case items {
    [] -> {
      // Either not a list, or empty. Check if it was originally a list.
      let keys = extract_keys(data_result)
      case keys {
        [] -> json_encode_dynamic(data_result)
        _ -> format_single_object(data_result)
      }
    }
    _ -> format_items_as_table(items)
  }
}

/// Format a list of items as an ASCII table.
fn format_items_as_table(items: List(Dynamic)) -> String {
  case items {
    [] -> "(0 rows)"
    [first, ..] -> {
      // Extract column names from the first item.
      let columns = extract_keys(first)
      case columns {
        [] -> json_encode_dynamic(dynamic.list(items))
        _ -> {
          // Build header.
          let header = string.join(columns, " | ")
          let separator =
            columns
            |> list.map(fn(col) { string.repeat("-", string.length(col) + 2) })
            |> string.join("+")

          // Build rows.
          let rows =
            items
            |> list.map(fn(item) {
              columns
              |> list.map(fn(col) {
                extract_field_string(item, col)
              })
              |> string.join(" | ")
            })

          let row_count = list.length(items)

          [header, separator, ..rows]
          |> list.append(["(" <> int.to_string(row_count) <> " rows)"])
          |> string.join("\n")
        }
      }
    }
  }
}

/// Format a single JSON object as key-value pairs.
fn format_single_object(value: Dynamic) -> String {
  let keys = extract_keys(value)
  case keys {
    [] -> json_encode_dynamic(value)
    _ -> {
      keys
      |> list.map(fn(key) {
        let val = extract_field_string(value, key)
        key <> ": " <> val
      })
      |> string.join("\n")
    }
  }
}

/// Format as CSV.
fn format_csv(value: Dynamic) -> String {
  let data_result = extract_field_or_self(value, "data")
  let items = extract_list(data_result)

  case items {
    [] -> ""
    [first, ..] -> {
      let columns = extract_keys(first)
      let header = string.join(columns, ",")
      let rows =
        items
        |> list.map(fn(item) {
          columns
          |> list.map(fn(col) { csv_escape(extract_field_string(item, col)) })
          |> string.join(",")
        })
      [header, ..rows] |> string.join("\n")
    }
  }
}

/// Escape a value for CSV output.
fn csv_escape(s: String) -> String {
  case
    string.contains(s, ",")
    || string.contains(s, "\"")
    || string.contains(s, "\n")
  {
    True -> "\"" <> string.replace(s, "\"", "\"\"") <> "\""
    False -> s
  }
}

// ---------------------------------------------------------------------------
// Erlang FFI — ad-hoc dynamic value manipulation.
//
// The Gleam dynamic/decode API is designed for statically-typed decoding,
// but we need ad-hoc field extraction from arbitrary JSON structures.
// These FFI functions operate on raw Erlang terms via maps:keys/1,
// maps:get/2, and the OTP json module.
// ---------------------------------------------------------------------------

/// Extract keys from a JSON object (via Erlang maps:keys/1).
@external(erlang, "nqc_ffi", "extract_keys")
fn extract_keys(obj: Dynamic) -> List(String)

/// Encode a dynamic value as a JSON string.
@external(erlang, "nqc_ffi", "json_encode")
fn json_encode_dynamic(value: Dynamic) -> String

/// Extract a named field from a dynamic map, returning the value
/// or the original value if the field doesn't exist.
@external(erlang, "nqc_ffi", "extract_field_or_self")
fn extract_field_or_self(obj: Dynamic, key: String) -> Dynamic

/// Extract a dynamic value as a list of dynamic values.
/// Returns an empty list if the value is not a list.
@external(erlang, "nqc_ffi", "extract_list")
fn extract_list(value: Dynamic) -> List(Dynamic)

/// Extract a field value as a display string.
@external(erlang, "nqc_ffi", "extract_field_string")
fn extract_field_string(obj: Dynamic, key: String) -> String
