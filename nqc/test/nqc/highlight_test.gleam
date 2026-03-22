// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// highlight_test.gleam — Tests for keyword highlighting.
//
// Note: ANSI highlighting depends on TERM env var. These tests verify
// the core logic works regardless of terminal support.

import gleam/string
import gleeunit/should
import nqc/highlight

// ---------------------------------------------------------------------------
// highlight_query — keyword detection
// ---------------------------------------------------------------------------

pub fn highlight_query_returns_non_empty_test() {
  let result = highlight.highlight_query("SELECT * FROM users", ["SELECT", "FROM"])
  should.be_true(string.length(result) > 0)
}

pub fn highlight_query_preserves_non_keywords_test() {
  // Regardless of colour support, the original text should be present.
  let result = highlight.highlight_query("hello world", ["SELECT"])
  should.be_true(string.contains(result, "hello"))
  should.be_true(string.contains(result, "world"))
}

pub fn highlight_query_empty_input_test() {
  let result = highlight.highlight_query("", ["SELECT"])
  should.equal(result, "")
}

pub fn highlight_query_no_keywords_test() {
  let result = highlight.highlight_query("SELECT 1", [])
  should.be_true(string.contains(result, "SELECT"))
}

// ---------------------------------------------------------------------------
// highlight_keyword_list
// ---------------------------------------------------------------------------

pub fn highlight_keyword_list_contains_all_keywords_test() {
  let keywords = ["SELECT", "FROM", "WHERE"]
  let result = highlight.highlight_keyword_list(keywords)
  should.be_true(string.contains(result, "SELECT"))
  should.be_true(string.contains(result, "FROM"))
  should.be_true(string.contains(result, "WHERE"))
}

pub fn highlight_keyword_list_empty_test() {
  let result = highlight.highlight_keyword_list([])
  should.equal(result, "")
}
