// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// safety.gleam - Proven-compatible safety functions for Glyphbase
//
// Pure Gleam implementations of critical safety checks from the proven
// library (SafePath, SafeString). These match the proven API signatures
// so they can be replaced with real NIF calls when the proven build
// pipeline (Idris2 → RefC → Zig → NIF) is operational.
//
// TODO: Replace with `import proven/path`, `import proven/string_ops`
// once libproven_nif.so is built.

import gleam/string

// ============================================================
// SafePath — Directory traversal prevention
// ============================================================

/// Check if a path contains directory traversal sequences.
/// Matches proven/path.has_traversal/1 API.
pub fn path_has_traversal(path: String) -> Result(Bool, String) {
  case string.contains(path, "..") {
    True -> Ok(True)
    False ->
      case string.contains(path, "\u{0000}") {
        True -> Ok(True)
        False -> Ok(False)
      }
  }
}

/// Sanitize a filename by removing path separators and traversal sequences.
/// Matches proven/path.sanitize_filename/1 API.
pub fn sanitize_filename(filename: String) -> Result(String, String) {
  let cleaned =
    filename
    |> string.replace("..", "")
    |> string.replace("/", "_")
    |> string.replace("\\", "_")
    |> string.replace("\u{0000}", "")

  case string.is_empty(cleaned) {
    True -> Error("filename_empty_after_sanitization")
    False -> Ok(cleaned)
  }
}

// ============================================================
// SafeString — Escaping for injection prevention
// ============================================================

/// Escape a string for safe use in SQL (single-quote doubling).
/// Matches proven/string_ops.escape_sql/1 API.
pub fn escape_sql(value: String) -> Result(String, String) {
  Ok(string.replace(value, "'", "''"))
}

/// Escape a string for safe use in HTML content.
/// Matches proven/string_ops.escape_html/1 API.
pub fn escape_html(value: String) -> Result(String, String) {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#x27;")
  |> Ok
}

/// Escape a string for safe use in JavaScript string literals.
/// Matches proven/string_ops.escape_js/1 API.
pub fn escape_js(value: String) -> Result(String, String) {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("'", "\\'")
  |> string.replace("<", "\\u003C")
  |> string.replace(">", "\\u003E")
  |> string.replace("/", "\\/")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> Ok
}
