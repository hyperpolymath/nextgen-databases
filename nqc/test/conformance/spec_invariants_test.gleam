// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// spec_invariants_test.gleam — Conformance tests derived from SPEC.core.scm.
//
// These tests verify the formal invariants declared in the specification.
// Each test references the specific invariant it validates.

import gleam/list
import gleam/string
import gleeunit/should
import nqc
import nqc/database
import nqc/formatter

// ---------------------------------------------------------------------------
// Invariant: format-roundtrip
// "parse-format(format-to-string(f)) == Ok(f) for all OutputFormat values."
// ---------------------------------------------------------------------------

pub fn invariant_format_roundtrip_table_test() {
  let fmt = formatter.Table
  let assert Ok(parsed) = formatter.parse_format(nqc.format_to_string(fmt))
  should.equal(parsed, fmt)
}

pub fn invariant_format_roundtrip_json_test() {
  let fmt = formatter.Json
  let assert Ok(parsed) = formatter.parse_format(nqc.format_to_string(fmt))
  should.equal(parsed, fmt)
}

pub fn invariant_format_roundtrip_csv_test() {
  let fmt = formatter.Csv
  let assert Ok(parsed) = formatter.parse_format(nqc.format_to_string(fmt))
  should.equal(parsed, fmt)
}

// ---------------------------------------------------------------------------
// Invariant: profile-lookup-consistent
// "find-profile(p.id) == Ok(p) for every registered profile p."
// ---------------------------------------------------------------------------

pub fn invariant_profile_lookup_all_ids_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    let assert Ok(found) = database.find_profile(p.id)
    should.equal(found.id, p.id)
    should.equal(found.display_name, p.display_name)
    should.equal(found.default_port, p.default_port)
  })
}

// ---------------------------------------------------------------------------
// Invariant: alias-lookup-consistent
// "find-profile(alias) == Ok(p) for every alias of profile p."
// ---------------------------------------------------------------------------

pub fn invariant_alias_lookup_all_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    list.each(p.aliases, fn(alias) {
      let assert Ok(found) = database.find_profile(alias)
      should.equal(found.id, p.id)
    })
  })
}

// ---------------------------------------------------------------------------
// Invariant: url-construction
// "execute-url(conn) == base-url(conn) ++ conn.profile.execute-path"
// ---------------------------------------------------------------------------

pub fn invariant_url_construction_execute_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    let conn = database.connection_from_profile(p)
    let expected = database.base_url(conn) <> p.execute_path
    should.equal(database.execute_url(conn), expected)
  })
}

pub fn invariant_url_construction_health_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    let conn = database.connection_from_profile(p)
    let expected = database.base_url(conn) <> p.health_path
    should.equal(database.health_url(conn), expected)
  })
}

// ---------------------------------------------------------------------------
// Invariant: semicolon-stripping-idempotent
// "strip(strip(s)) == strip(s) for all strings s."
// ---------------------------------------------------------------------------

pub fn invariant_semicolon_strip_idempotent_no_semicolons_test() {
  let s = "SELECT 1"
  let once = nqc.strip_trailing_semicolons(s)
  let twice = nqc.strip_trailing_semicolons(once)
  should.equal(once, twice)
}

pub fn invariant_semicolon_strip_idempotent_with_semicolons_test() {
  let s = "SELECT 1;;;"
  let once = nqc.strip_trailing_semicolons(s)
  let twice = nqc.strip_trailing_semicolons(once)
  should.equal(once, twice)
}

pub fn invariant_semicolon_strip_idempotent_empty_test() {
  let s = ""
  let once = nqc.strip_trailing_semicolons(s)
  let twice = nqc.strip_trailing_semicolons(once)
  should.equal(once, twice)
}

pub fn invariant_semicolon_strip_idempotent_only_semicolons_test() {
  let s = ";;;"
  let once = nqc.strip_trailing_semicolons(s)
  let twice = nqc.strip_trailing_semicolons(once)
  should.equal(once, twice)
}

pub fn invariant_semicolon_strip_idempotent_internal_test() {
  let s = "a;b;c;"
  let once = nqc.strip_trailing_semicolons(s)
  let twice = nqc.strip_trailing_semicolons(once)
  should.equal(once, twice)
}

// ---------------------------------------------------------------------------
// Invariant: unique-ids
// "All profile IDs are distinct."
// ---------------------------------------------------------------------------

pub fn invariant_unique_profile_ids_test() {
  let profiles = database.all_profiles()
  let ids = list.map(profiles, fn(p) { p.id })
  should.equal(list.length(ids), list.length(list.unique(ids)))
}

// ---------------------------------------------------------------------------
// Invariant: no-alias-id-overlap
// "No alias of profile A matches the ID of profile B."
// ---------------------------------------------------------------------------

pub fn invariant_no_alias_id_overlap_test() {
  let profiles = database.all_profiles()
  let ids = list.map(profiles, fn(p) { p.id })
  list.each(profiles, fn(p) {
    list.each(p.aliases, fn(alias) {
      // Alias should not match any other profile's ID.
      let matches_other_id =
        list.any(ids, fn(id) { id == alias && id != p.id })
      should.be_false(matches_other_id)
    })
  })
}

// ---------------------------------------------------------------------------
// Invariant: unique-aliases
// "No alias appears in more than one profile."
// ---------------------------------------------------------------------------

pub fn invariant_unique_aliases_test() {
  let profiles = database.all_profiles()
  let all_aliases = list.flat_map(profiles, fn(p) { p.aliases })
  should.equal(
    list.length(all_aliases),
    list.length(list.unique(all_aliases)),
  )
}

// ---------------------------------------------------------------------------
// Invariant: order-preserved
// "Built-in profiles always appear before custom profiles."
// ---------------------------------------------------------------------------

pub fn invariant_builtin_order_preserved_test() {
  let all = database.all_profiles()
  let builtins = database.builtin_profiles()
  let first_n = list.take(all, list.length(builtins))
  let first_ids = list.map(first_n, fn(p) { p.id })
  let builtin_ids = list.map(builtins, fn(p) { p.id })
  should.equal(first_ids, builtin_ids)
}

// ---------------------------------------------------------------------------
// Invariant: non-empty-id, valid-port, path-starts-slash, non-empty-prompt
// (DatabaseProfile field invariants)
// ---------------------------------------------------------------------------

pub fn invariant_profile_field_constraints_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    // non-empty-id
    should.be_true(string.length(p.id) > 0)
    // valid-port
    should.be_true(p.default_port >= 1)
    should.be_true(p.default_port <= 65535)
    // path-starts-slash
    should.be_true(string.starts_with(p.execute_path, "/"))
    should.be_true(string.starts_with(p.health_path, "/"))
    // non-empty-prompt
    should.be_true(string.length(p.prompt) > 0)
  })
}

// ---------------------------------------------------------------------------
// Invariant: Connection valid-port
// ---------------------------------------------------------------------------

pub fn invariant_connection_default_port_valid_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    let conn = database.connection_from_profile(p)
    should.be_true(conn.port >= 1)
    should.be_true(conn.port <= 65535)
  })
}

// ---------------------------------------------------------------------------
// Invariant: no-data-loss
// "NQC never modifies query text beyond stripping trailing semicolons."
// ---------------------------------------------------------------------------

pub fn invariant_no_data_loss_preserves_content_test() {
  // Internal semicolons, whitespace, special characters preserved.
  let query = "SELECT * FROM users WHERE name = 'O\\'Brien'; -- comment"
  let stripped = nqc.strip_trailing_semicolons(query)
  // Only the trailing semicolons after "comment" should be removed.
  // The semicolons inside the query should remain.
  should.be_true(string.contains(stripped, "SELECT"))
  should.be_true(string.contains(stripped, "O\\'Brien"))
  should.be_true(string.contains(stripped, "comment"))
}
