// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// history_test.gleam — Tests for query history.

import gleam/list
import gleeunit/should
import nqc/history

// ---------------------------------------------------------------------------
// Basic operations
// ---------------------------------------------------------------------------

pub fn empty_history_has_length_zero_test() {
  should.equal(history.length(history.empty()), 0)
}

pub fn add_increases_length_test() {
  let h = history.empty()
  let h = history.add(h, "SELECT 1")
  should.equal(history.length(h), 1)
}

pub fn add_multiple_entries_test() {
  let h = history.empty()
  let h = history.add(h, "SELECT 1")
  let h = history.add(h, "SELECT 2")
  let h = history.add(h, "SELECT 3")
  should.equal(history.length(h), 3)
}

pub fn add_empty_string_ignored_test() {
  let h = history.empty()
  let h = history.add(h, "")
  should.equal(history.length(h), 0)
}

pub fn add_whitespace_only_ignored_test() {
  let h = history.empty()
  let h = history.add(h, "   ")
  should.equal(history.length(h), 0)
}

// ---------------------------------------------------------------------------
// Consecutive deduplication
// ---------------------------------------------------------------------------

pub fn consecutive_duplicate_not_added_test() {
  let h = history.empty()
  let h = history.add(h, "SELECT 1")
  let h = history.add(h, "SELECT 1")
  should.equal(history.length(h), 1)
}

pub fn non_consecutive_duplicate_is_added_test() {
  let h = history.empty()
  let h = history.add(h, "SELECT 1")
  let h = history.add(h, "SELECT 2")
  let h = history.add(h, "SELECT 1")
  should.equal(history.length(h), 3)
}

// ---------------------------------------------------------------------------
// Recent queries
// ---------------------------------------------------------------------------

pub fn recent_returns_newest_first_test() {
  let h = history.empty()
  let h = history.add(h, "first")
  let h = history.add(h, "second")
  let h = history.add(h, "third")
  let recent = history.recent(h, 2)
  should.equal(recent, ["third", "second"])
}

pub fn recent_with_count_exceeding_length_test() {
  let h = history.empty()
  let h = history.add(h, "only")
  let recent = history.recent(h, 10)
  should.equal(recent, ["only"])
}

pub fn recent_empty_history_test() {
  let recent = history.recent(history.empty(), 5)
  should.equal(recent, [])
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

pub fn search_finds_matching_entries_test() {
  let h = history.empty()
  let h = history.add(h, "SELECT * FROM users")
  let h = history.add(h, "SELECT * FROM orders")
  let h = history.add(h, "DELETE FROM users")
  let matches = history.search(h, "users")
  should.equal(list.length(matches), 2)
}

pub fn search_is_case_insensitive_test() {
  let h = history.empty()
  let h = history.add(h, "SELECT * FROM Users")
  let matches = history.search(h, "users")
  should.equal(list.length(matches), 1)
}

pub fn search_no_matches_returns_empty_test() {
  let h = history.empty()
  let h = history.add(h, "SELECT 1")
  let matches = history.search(h, "nonexistent")
  should.equal(matches, [])
}

pub fn search_empty_history_returns_empty_test() {
  let matches = history.search(history.empty(), "anything")
  should.equal(matches, [])
}
