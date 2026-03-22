// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// cache_test.gleam — Tests for the query result cache.

import gleam/dynamic.{type Dynamic}
import gleeunit/should
import nqc/cache

/// Coerce any value to Dynamic for testing.
@external(erlang, "test_ffi", "to_dynamic")
fn to_dynamic(value: a) -> Dynamic

// ---------------------------------------------------------------------------
// Basic operations
// ---------------------------------------------------------------------------

pub fn empty_cache_has_size_zero_test() {
  should.equal(cache.size(cache.empty()), 0)
}

pub fn put_then_get_returns_value_test() {
  let c = cache.empty()
  let value = to_dynamic("result")
  let c = cache.put(c, "vql", "SELECT 1", value)
  should.be_ok(cache.get(c, "vql", "SELECT 1"))
}

pub fn get_missing_returns_error_test() {
  let c = cache.empty()
  should.be_error(cache.get(c, "vql", "SELECT 1"))
}

pub fn put_increments_size_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "SELECT 1", to_dynamic(1))
  let c = cache.put(c, "vql", "SELECT 2", to_dynamic(2))
  should.equal(cache.size(c), 2)
}

pub fn same_key_overwrites_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "SELECT 1", to_dynamic("first"))
  let c = cache.put(c, "vql", "SELECT 1", to_dynamic("second"))
  should.equal(cache.size(c), 1)
}

// ---------------------------------------------------------------------------
// Mutation bypass
// ---------------------------------------------------------------------------

pub fn insert_query_not_cached_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "INSERT INTO users VALUES (1)", to_dynamic("ok"))
  should.equal(cache.size(c), 0)
}

pub fn delete_query_not_cached_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "DELETE FROM users WHERE id = 1", to_dynamic("ok"))
  should.equal(cache.size(c), 0)
}

pub fn create_query_not_cached_test() {
  let c = cache.empty()
  let c = cache.put(c, "gql", "CREATE VERTEX user", to_dynamic("ok"))
  should.equal(cache.size(c), 0)
}

pub fn update_query_not_cached_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "UPDATE users SET name = 'Bob'", to_dynamic("ok"))
  should.equal(cache.size(c), 0)
}

pub fn deform_query_not_cached_test() {
  let c = cache.empty()
  let c = cache.put(c, "kql", "DEFORM knot_3_1 UNDER R1", to_dynamic("ok"))
  should.equal(cache.size(c), 0)
}

pub fn select_query_is_cached_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "SELECT * FROM users", to_dynamic("data"))
  should.equal(cache.size(c), 1)
}

// ---------------------------------------------------------------------------
// Database isolation
// ---------------------------------------------------------------------------

pub fn different_dbs_separate_cache_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "SELECT 1", to_dynamic("vql-result"))
  let c = cache.put(c, "gql", "SELECT 1", to_dynamic("gql-result"))
  should.equal(cache.size(c), 2)
  should.be_ok(cache.get(c, "vql", "SELECT 1"))
  should.be_ok(cache.get(c, "gql", "SELECT 1"))
}

pub fn invalidate_db_clears_only_that_db_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "SELECT 1", to_dynamic("v"))
  let c = cache.put(c, "gql", "SELECT 1", to_dynamic("g"))
  let c = cache.invalidate_db(c, "vql")
  should.be_error(cache.get(c, "vql", "SELECT 1"))
  should.be_ok(cache.get(c, "gql", "SELECT 1"))
}

// ---------------------------------------------------------------------------
// Clear
// ---------------------------------------------------------------------------

pub fn clear_empties_cache_test() {
  let c = cache.empty()
  let c = cache.put(c, "vql", "SELECT 1", to_dynamic(1))
  let c = cache.put(c, "vql", "SELECT 2", to_dynamic(2))
  let c = cache.clear(c)
  should.equal(cache.size(c), 0)
}
