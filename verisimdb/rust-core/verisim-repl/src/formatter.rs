// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! Output formatters for VQL query results.
//!
//! Supports three output modes:
//! - **Table**: Human-readable columnar output using `comfy-table`.
//! - **JSON**: Pretty-printed JSON (pass-through from server response).
//! - **CSV**: Comma-separated values for pipeline consumption.

use comfy_table::{Cell, ContentArrangement, Table};
use serde_json::Value;
use std::fmt;

/// Available output formats.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputFormat {
    Table,
    Json,
    Csv,
}

impl fmt::Display for OutputFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OutputFormat::Table => write!(f, "table"),
            OutputFormat::Json => write!(f, "json"),
            OutputFormat::Csv => write!(f, "csv"),
        }
    }
}

impl std::str::FromStr for OutputFormat {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "table" => Ok(OutputFormat::Table),
            "json" => Ok(OutputFormat::Json),
            "csv" => Ok(OutputFormat::Csv),
            other => Err(format!(
                "Unknown format '{other}'. Valid formats: table, json, csv"
            )),
        }
    }
}

/// Format a JSON value according to the selected output format.
///
/// The JSON value may be:
/// - An array of objects (query result rows)
/// - A single object (health check, explain output, etc.)
/// - A scalar or other shape (rendered as-is for JSON, best-effort for table/CSV)
pub fn format_value(value: &Value, format: OutputFormat) -> String {
    match format {
        OutputFormat::Json => format_json(value),
        OutputFormat::Table => format_table(value),
        OutputFormat::Csv => format_csv(value),
    }
}

/// Pretty-print JSON with 2-space indentation.
fn format_json(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
}

/// Render a JSON value as a table.
///
/// For arrays of objects, each object becomes a row and each unique key becomes
/// a column. For single objects, each key-value pair becomes a row with two
/// columns ("Field" and "Value"). For scalars, a single-cell table is produced.
fn format_table(value: &Value) -> String {
    match value {
        Value::Array(rows) if !rows.is_empty() => format_array_table(rows),
        Value::Object(obj) => format_object_table(obj),
        other => format!("{other}"),
    }
}

/// Render an array of JSON objects as a columnar table.
fn format_array_table(rows: &[Value]) -> String {
    // Collect all unique keys in insertion order from the first object,
    // then add any keys found in subsequent objects.
    let mut columns: Vec<String> = Vec::new();
    for row in rows {
        if let Value::Object(obj) = row {
            for key in obj.keys() {
                if !columns.contains(key) {
                    columns.push(key.clone());
                }
            }
        }
    }

    if columns.is_empty() {
        // Array of non-objects: render each element as a single row.
        let mut table = Table::new();
        table.set_content_arrangement(ContentArrangement::Dynamic);
        table.set_header(vec![Cell::new("value")]);
        for item in rows {
            table.add_row(vec![Cell::new(value_to_cell(item))]);
        }
        return table.to_string();
    }

    let mut table = Table::new();
    table.set_content_arrangement(ContentArrangement::Dynamic);
    table.set_header(columns.iter().map(|c| Cell::new(c)));

    for row in rows {
        let cells: Vec<Cell> = columns
            .iter()
            .map(|col| {
                let val = row.get(col).unwrap_or(&Value::Null);
                Cell::new(value_to_cell(val))
            })
            .collect();
        table.add_row(cells);
    }

    let row_count = rows.len();
    format!("{table}\n({row_count} row{})", if row_count == 1 { "" } else { "s" })
}

/// Render a single JSON object as a two-column table (Field | Value).
fn format_object_table(obj: &serde_json::Map<String, Value>) -> String {
    let mut table = Table::new();
    table.set_content_arrangement(ContentArrangement::Dynamic);
    table.set_header(vec![Cell::new("Field"), Cell::new("Value")]);

    for (key, val) in obj {
        table.add_row(vec![Cell::new(key), Cell::new(value_to_cell(val))]);
    }

    table.to_string()
}

/// Convert a JSON value to a short string suitable for a table cell.
///
/// Arrays and nested objects are truncated to avoid overwhelming the table.
fn value_to_cell(value: &Value) -> String {
    match value {
        Value::Null => "NULL".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => s.clone(),
        Value::Array(arr) => {
            if arr.len() <= 3 {
                format!("{value}")
            } else {
                format!("[{} items]", arr.len())
            }
        }
        Value::Object(obj) => {
            if obj.len() <= 3 {
                format!("{value}")
            } else {
                format!("{{{} fields}}", obj.len())
            }
        }
    }
}

/// Render a JSON value as CSV.
///
/// For arrays of objects, the first row is a header line derived from keys.
/// For single objects, each key-value pair becomes a row.
fn format_csv(value: &Value) -> String {
    match value {
        Value::Array(rows) if !rows.is_empty() => format_array_csv(rows),
        Value::Object(obj) => format_object_csv(obj),
        other => format!("{other}"),
    }
}

/// Render an array of JSON objects as CSV rows.
fn format_array_csv(rows: &[Value]) -> String {
    let mut columns: Vec<String> = Vec::new();
    for row in rows {
        if let Value::Object(obj) = row {
            for key in obj.keys() {
                if !columns.contains(key) {
                    columns.push(key.clone());
                }
            }
        }
    }

    let mut output = String::new();

    // Header row
    output.push_str(&columns.join(","));
    output.push('\n');

    // Data rows
    for row in rows {
        let cells: Vec<String> = columns
            .iter()
            .map(|col| {
                let val = row.get(col).unwrap_or(&Value::Null);
                csv_escape(val)
            })
            .collect();
        output.push_str(&cells.join(","));
        output.push('\n');
    }

    output
}

/// Render a single JSON object as CSV (key,value rows).
fn format_object_csv(obj: &serde_json::Map<String, Value>) -> String {
    let mut output = String::from("field,value\n");
    for (key, val) in obj {
        output.push_str(&format!("{},{}\n", csv_escape_str(key), csv_escape(val)));
    }
    output
}

/// Escape a JSON value for CSV output.
///
/// Strings containing commas, quotes, or newlines are double-quoted with
/// internal quotes escaped per RFC 4180.
fn csv_escape(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(s) => csv_escape_str(s),
        other => csv_escape_str(&other.to_string()),
    }
}

/// Escape a string for CSV output per RFC 4180.
fn csv_escape_str(s: &str) -> String {
    if s.contains(',') || s.contains('"') || s.contains('\n') {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_output_format_parse() {
        assert_eq!("table".parse::<OutputFormat>().unwrap(), OutputFormat::Table);
        assert_eq!("JSON".parse::<OutputFormat>().unwrap(), OutputFormat::Json);
        assert_eq!("csv".parse::<OutputFormat>().unwrap(), OutputFormat::Csv);
        assert!("xml".parse::<OutputFormat>().is_err());
    }

    #[test]
    fn test_output_format_display() {
        assert_eq!(OutputFormat::Table.to_string(), "table");
        assert_eq!(OutputFormat::Json.to_string(), "json");
        assert_eq!(OutputFormat::Csv.to_string(), "csv");
    }

    #[test]
    fn test_format_json_pretty() {
        let val = json!({"status": "healthy", "version": "0.1.0"});
        let out = format_value(&val, OutputFormat::Json);
        assert!(out.contains("\"status\": \"healthy\""));
        assert!(out.contains('\n'));
    }

    #[test]
    fn test_format_table_array() {
        let val = json!([
            {"id": "abc", "score": 0.95},
            {"id": "def", "score": 0.80}
        ]);
        let out = format_value(&val, OutputFormat::Table);
        assert!(out.contains("abc"));
        assert!(out.contains("0.95"));
        assert!(out.contains("(2 rows)"));
    }

    #[test]
    fn test_format_table_object() {
        let val = json!({"status": "healthy", "uptime_seconds": 42});
        let out = format_value(&val, OutputFormat::Table);
        assert!(out.contains("Field"));
        assert!(out.contains("Value"));
        assert!(out.contains("healthy"));
    }

    #[test]
    fn test_format_csv_array() {
        let val = json!([
            {"name": "Alice", "age": 30},
            {"name": "Bob", "age": 25}
        ]);
        let out = format_value(&val, OutputFormat::Csv);
        assert!(out.starts_with("name,age\n") || out.starts_with("age,name\n"));
        assert!(out.contains("Alice"));
        assert!(out.contains("30"));
    }

    #[test]
    fn test_csv_escape_commas() {
        assert_eq!(csv_escape_str("hello,world"), "\"hello,world\"");
    }

    #[test]
    fn test_csv_escape_quotes() {
        assert_eq!(csv_escape_str("say \"hi\""), "\"say \"\"hi\"\"\"");
    }

    #[test]
    fn test_value_to_cell_null() {
        assert_eq!(value_to_cell(&Value::Null), "NULL");
    }

    #[test]
    fn test_value_to_cell_large_array() {
        let val = json!([1, 2, 3, 4, 5]);
        assert_eq!(value_to_cell(&val), "[5 items]");
    }

    #[test]
    fn test_format_single_row() {
        let val = json!([{"id": "only-one"}]);
        let out = format_value(&val, OutputFormat::Table);
        assert!(out.contains("(1 row)"));
    }
}
