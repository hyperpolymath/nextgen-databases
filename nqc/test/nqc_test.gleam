// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// nqc_test.gleam — Tests for main module utility functions.
//
// Tests the pub utility functions: find_flag_value, strip_trailing_semicolons,
// list_at, and format_to_string. These were promoted from private to pub to
// enable direct testing.

import gleeunit
import gleeunit/should
import nqc
import nqc/formatter

pub fn main() -> Nil {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// find_flag_value — extract value following a CLI flag
// ---------------------------------------------------------------------------

pub fn find_flag_value_present_test() {
  let args = ["--db", "vql", "--port", "8080"]
  should.equal(nqc.find_flag_value(args, "--db"), Ok("vql"))
}

pub fn find_flag_value_second_flag_test() {
  let args = ["--db", "vql", "--port", "8080"]
  should.equal(nqc.find_flag_value(args, "--port"), Ok("8080"))
}

pub fn find_flag_value_missing_flag_test() {
  let args = ["--db", "vql"]
  should.be_error(nqc.find_flag_value(args, "--host"))
}

pub fn find_flag_value_empty_args_test() {
  should.be_error(nqc.find_flag_value([], "--db"))
}

pub fn find_flag_value_flag_at_end_without_value_test() {
  // Flag exists but has no following value.
  let args = ["--db"]
  should.be_error(nqc.find_flag_value(args, "--db"))
}

pub fn find_flag_value_multiple_same_flags_returns_first_test() {
  let args = ["--db", "vql", "--db", "gql"]
  should.equal(nqc.find_flag_value(args, "--db"), Ok("vql"))
}

pub fn find_flag_value_non_flag_args_skipped_test() {
  let args = ["query", "text", "--format", "json"]
  should.equal(nqc.find_flag_value(args, "--format"), Ok("json"))
}

// ---------------------------------------------------------------------------
// strip_trailing_semicolons — clean up query input
// ---------------------------------------------------------------------------

pub fn strip_trailing_semicolons_none_test() {
  should.equal(nqc.strip_trailing_semicolons("SELECT 1"), "SELECT 1")
}

pub fn strip_trailing_semicolons_one_test() {
  should.equal(nqc.strip_trailing_semicolons("SELECT 1;"), "SELECT 1")
}

pub fn strip_trailing_semicolons_multiple_test() {
  should.equal(nqc.strip_trailing_semicolons("SELECT 1;;;"), "SELECT 1")
}

pub fn strip_trailing_semicolons_empty_test() {
  should.equal(nqc.strip_trailing_semicolons(""), "")
}

pub fn strip_trailing_semicolons_only_semicolons_test() {
  should.equal(nqc.strip_trailing_semicolons(";;;"), "")
}

pub fn strip_trailing_semicolons_preserves_internal_test() {
  // Semicolons inside the query are preserved.
  should.equal(
    nqc.strip_trailing_semicolons("a;b;c;"),
    "a;b;c",
  )
}

pub fn strip_trailing_semicolons_preserves_leading_test() {
  should.equal(nqc.strip_trailing_semicolons(";start"), ";start")
}

// ---------------------------------------------------------------------------
// list_at — 0-indexed list element access
// ---------------------------------------------------------------------------

pub fn list_at_first_element_test() {
  should.equal(nqc.list_at(["a", "b", "c"], 0), Ok("a"))
}

pub fn list_at_second_element_test() {
  should.equal(nqc.list_at(["a", "b", "c"], 1), Ok("b"))
}

pub fn list_at_last_element_test() {
  should.equal(nqc.list_at(["a", "b", "c"], 2), Ok("c"))
}

pub fn list_at_out_of_bounds_test() {
  should.be_error(nqc.list_at(["a", "b"], 5))
}

pub fn list_at_empty_list_test() {
  should.be_error(nqc.list_at([], 0))
}

pub fn list_at_negative_index_test() {
  // Negative indices should not match (no items at index < 0).
  should.be_error(nqc.list_at(["a"], -1))
}

pub fn list_at_single_element_test() {
  should.equal(nqc.list_at([42], 0), Ok(42))
}

// ---------------------------------------------------------------------------
// format_to_string — OutputFormat to display string
// ---------------------------------------------------------------------------

pub fn format_to_string_table_test() {
  should.equal(nqc.format_to_string(formatter.Table), "table")
}

pub fn format_to_string_json_test() {
  should.equal(nqc.format_to_string(formatter.Json), "json")
}

pub fn format_to_string_csv_test() {
  should.equal(nqc.format_to_string(formatter.Csv), "csv")
}
