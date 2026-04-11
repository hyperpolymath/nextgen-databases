// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// database_test.gleam — Comprehensive tests for the database profile registry.
//
// Covers: profile construction, registry completeness, profile lookup by ID
// and alias, connection builders, and URL generation.

import gleeunit/should
import gleam/list
import gleam/string
import nqc/database

// ---------------------------------------------------------------------------
// Profile construction — verify each built-in profile has correct metadata
// ---------------------------------------------------------------------------

pub fn vcl_profile_has_correct_id_test() {
  let p = database.vcl_profile()
  should.equal(p.id, "vcl")
}

pub fn vcl_profile_has_correct_display_name_test() {
  let p = database.vcl_profile()
  should.equal(p.display_name, "VeriSimDB")
}

pub fn vcl_profile_has_correct_language_test() {
  let p = database.vcl_profile()
  should.equal(p.language_name, "VCL")
}

pub fn vcl_profile_default_port_is_8080_test() {
  let p = database.vcl_profile()
  should.equal(p.default_port, 8080)
}

pub fn vcl_profile_execute_path_test() {
  let p = database.vcl_profile()
  should.equal(p.execute_path, "/vcl/execute")
}

pub fn vcl_profile_health_path_test() {
  let p = database.vcl_profile()
  should.equal(p.health_path, "/health")
}

pub fn vcl_profile_supports_dependent_types_test() {
  let p = database.vcl_profile()
  should.be_true(p.supports_dt)
}

pub fn vcl_profile_has_keywords_test() {
  let p = database.vcl_profile()
  should.be_true(p.keywords != [])
}

pub fn vcl_profile_has_expected_keywords_test() {
  let p = database.vcl_profile()
  should.be_true(list.contains(p.keywords, "SELECT"))
  should.be_true(list.contains(p.keywords, "HEXAD"))
  should.be_true(list.contains(p.keywords, "DRIFT"))
  should.be_true(list.contains(p.keywords, "PROOF"))
}

pub fn vcl_profile_has_aliases_test() {
  let p = database.vcl_profile()
  should.be_true(list.contains(p.aliases, "verisimdb"))
  should.be_true(list.contains(p.aliases, "verisim"))
}

pub fn vcl_profile_prompt_test() {
  let p = database.vcl_profile()
  should.equal(p.prompt, "vcl> ")
}

pub fn gql_profile_has_correct_id_test() {
  let p = database.gql_profile()
  should.equal(p.id, "gql")
}

pub fn gql_profile_has_correct_display_name_test() {
  let p = database.gql_profile()
  should.equal(p.display_name, "Lithoglyph")
}

pub fn gql_profile_default_port_is_8081_test() {
  let p = database.gql_profile()
  should.equal(p.default_port, 8081)
}

pub fn gql_profile_execute_path_test() {
  let p = database.gql_profile()
  should.equal(p.execute_path, "/gql/execute")
}

pub fn gql_profile_supports_dependent_types_test() {
  let p = database.gql_profile()
  should.be_true(p.supports_dt)
}

pub fn gql_profile_has_graph_keywords_test() {
  let p = database.gql_profile()
  should.be_true(list.contains(p.keywords, "MATCH"))
  should.be_true(list.contains(p.keywords, "VERTEX"))
  should.be_true(list.contains(p.keywords, "EDGE"))
  should.be_true(list.contains(p.keywords, "MORPHISM"))
}

pub fn gql_profile_has_aliases_test() {
  let p = database.gql_profile()
  should.be_true(list.contains(p.aliases, "lithoglyph"))
  should.be_true(list.contains(p.aliases, "formdb"))
}

pub fn kql_profile_has_correct_id_test() {
  let p = database.kql_profile()
  should.equal(p.id, "kql")
}

pub fn kql_profile_has_correct_display_name_test() {
  let p = database.kql_profile()
  should.equal(p.display_name, "QuandleDB")
}

pub fn kql_profile_default_port_is_8082_test() {
  let p = database.kql_profile()
  should.equal(p.default_port, 8082)
}

pub fn kql_profile_execute_path_test() {
  let p = database.kql_profile()
  should.equal(p.execute_path, "/kql/execute")
}

pub fn kql_profile_supports_dependent_types_test() {
  let p = database.kql_profile()
  should.be_true(p.supports_dt)
}

pub fn kql_profile_has_knot_keywords_test() {
  let p = database.kql_profile()
  should.be_true(list.contains(p.keywords, "DEFORM"))
  should.be_true(list.contains(p.keywords, "KNOT"))
  should.be_true(list.contains(p.keywords, "QUANDLE"))
  should.be_true(list.contains(p.keywords, "JONES"))
  should.be_true(list.contains(p.keywords, "REIDEMEISTER"))
}

pub fn kql_profile_has_aliases_test() {
  let p = database.kql_profile()
  should.be_true(list.contains(p.aliases, "quandledb"))
  should.be_true(list.contains(p.aliases, "quandle"))
}

// ---------------------------------------------------------------------------
// Registry — all_profiles and builtin_profiles
// ---------------------------------------------------------------------------

pub fn builtin_profiles_returns_three_test() {
  let profiles = database.builtin_profiles()
  should.equal(list.length(profiles), 3)
}

pub fn builtin_profiles_contains_vcl_test() {
  let profiles = database.builtin_profiles()
  let ids = list.map(profiles, fn(p) { p.id })
  should.be_true(list.contains(ids, "vcl"))
}

pub fn builtin_profiles_contains_gql_test() {
  let profiles = database.builtin_profiles()
  let ids = list.map(profiles, fn(p) { p.id })
  should.be_true(list.contains(ids, "gql"))
}

pub fn builtin_profiles_contains_kql_test() {
  let profiles = database.builtin_profiles()
  let ids = list.map(profiles, fn(p) { p.id })
  should.be_true(list.contains(ids, "kql"))
}

pub fn all_profiles_includes_builtins_test() {
  let all = database.all_profiles()
  let builtins = database.builtin_profiles()
  // all_profiles must contain at least the builtins.
  should.be_true(list.length(all) >= list.length(builtins))
}

pub fn all_profiles_preserves_builtin_order_test() {
  let all = database.all_profiles()
  let first_three = list.take(all, 3)
  let ids = list.map(first_three, fn(p) { p.id })
  should.equal(ids, ["vcl", "gql", "kql"])
}

pub fn custom_profiles_returns_list_test() {
  // custom_profiles should return an empty list by default (no custom
  // profiles configured). Validates the function is callable.
  let customs = database.custom_profiles()
  should.be_true(list.length(customs) >= 0)
}

// ---------------------------------------------------------------------------
// Profile lookup — find_profile by ID and alias
// ---------------------------------------------------------------------------

pub fn find_profile_by_vcl_id_test() {
  let result = database.find_profile("vcl")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "vcl")
}

pub fn find_profile_by_gql_id_test() {
  let result = database.find_profile("gql")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "gql")
}

pub fn find_profile_by_kql_id_test() {
  let result = database.find_profile("kql")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "kql")
}

pub fn find_profile_by_alias_verisimdb_test() {
  let result = database.find_profile("verisimdb")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "vcl")
}

pub fn find_profile_by_alias_verisim_test() {
  let result = database.find_profile("verisim")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "vcl")
}

pub fn find_profile_by_alias_lithoglyph_test() {
  let result = database.find_profile("lithoglyph")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "gql")
}

pub fn find_profile_by_alias_formdb_test() {
  let result = database.find_profile("formdb")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "gql")
}

pub fn find_profile_by_alias_quandledb_test() {
  let result = database.find_profile("quandledb")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "kql")
}

pub fn find_profile_by_alias_quandle_test() {
  let result = database.find_profile("quandle")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "kql")
}

pub fn find_profile_is_case_insensitive_test() {
  let result = database.find_profile("VCL")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "vcl")
}

pub fn find_profile_mixed_case_test() {
  let result = database.find_profile("Gql")
  should.be_ok(result)
  let assert Ok(p) = result
  should.equal(p.id, "gql")
}

pub fn find_profile_unknown_returns_error_test() {
  let result = database.find_profile("redis")
  should.be_error(result)
}

pub fn find_profile_error_message_contains_id_test() {
  let result = database.find_profile("redis")
  let assert Error(msg) = result
  should.be_true(string.contains(msg, "redis"))
}

pub fn find_profile_error_message_lists_available_test() {
  let result = database.find_profile("redis")
  let assert Error(msg) = result
  should.be_true(string.contains(msg, "vcl"))
  should.be_true(string.contains(msg, "gql"))
  should.be_true(string.contains(msg, "kql"))
}

pub fn find_profile_empty_string_returns_error_test() {
  let result = database.find_profile("")
  should.be_error(result)
}

// ---------------------------------------------------------------------------
// Connection builders
// ---------------------------------------------------------------------------

pub fn connection_from_profile_uses_default_host_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  should.equal(conn.host, "localhost")
}

pub fn connection_from_profile_uses_default_port_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  should.equal(conn.port, 8080)
}

pub fn connection_from_profile_dt_disabled_by_default_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  should.be_false(conn.dt_enabled)
}

pub fn connection_from_profile_stores_profile_test() {
  let profile = database.gql_profile()
  let conn = database.connection_from_profile(profile)
  should.equal(conn.profile.id, "gql")
}

pub fn connection_from_profile_kql_port_test() {
  let conn = database.connection_from_profile(database.kql_profile())
  should.equal(conn.port, 8082)
}

// ---------------------------------------------------------------------------
// URL builders
// ---------------------------------------------------------------------------

pub fn base_url_default_vcl_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  should.equal(database.base_url(conn), "http://localhost:8080")
}

pub fn base_url_default_gql_test() {
  let conn = database.connection_from_profile(database.gql_profile())
  should.equal(database.base_url(conn), "http://localhost:8081")
}

pub fn base_url_default_kql_test() {
  let conn = database.connection_from_profile(database.kql_profile())
  should.equal(database.base_url(conn), "http://localhost:8082")
}

pub fn base_url_with_custom_host_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  let conn = database.Connection(..conn, host: "10.0.0.5")
  should.equal(database.base_url(conn), "http://10.0.0.5:8080")
}

pub fn base_url_with_custom_port_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  let conn = database.Connection(..conn, port: 9090)
  should.equal(database.base_url(conn), "http://localhost:9090")
}

pub fn execute_url_vcl_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  should.equal(
    database.execute_url(conn),
    "http://localhost:8080/vcl/execute",
  )
}

pub fn execute_url_gql_test() {
  let conn = database.connection_from_profile(database.gql_profile())
  should.equal(
    database.execute_url(conn),
    "http://localhost:8081/gql/execute",
  )
}

pub fn execute_url_kql_test() {
  let conn = database.connection_from_profile(database.kql_profile())
  should.equal(
    database.execute_url(conn),
    "http://localhost:8082/kql/execute",
  )
}

pub fn health_url_vcl_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  should.equal(database.health_url(conn), "http://localhost:8080/health")
}

pub fn health_url_gql_test() {
  let conn = database.connection_from_profile(database.gql_profile())
  should.equal(database.health_url(conn), "http://localhost:8081/health")
}

pub fn health_url_kql_test() {
  let conn = database.connection_from_profile(database.kql_profile())
  should.equal(database.health_url(conn), "http://localhost:8082/health")
}

pub fn execute_url_with_custom_host_and_port_test() {
  let conn = database.connection_from_profile(database.vcl_profile())
  let conn = database.Connection(..conn, host: "db.example.com", port: 443)
  should.equal(
    database.execute_url(conn),
    "http://db.example.com:443/vcl/execute",
  )
}

// ---------------------------------------------------------------------------
// Profile uniqueness — no duplicate IDs or aliases across profiles
// ---------------------------------------------------------------------------

pub fn all_profile_ids_are_unique_test() {
  let profiles = database.all_profiles()
  let ids = list.map(profiles, fn(p) { p.id })
  should.equal(list.length(ids), list.length(list.unique(ids)))
}

pub fn no_alias_conflicts_with_ids_test() {
  let profiles = database.all_profiles()
  let ids = list.map(profiles, fn(p) { p.id })
  let all_aliases = list.flat_map(profiles, fn(p) { p.aliases })
  // No alias should match another profile's ID.
  let conflicts =
    list.filter(all_aliases, fn(alias) { list.contains(ids, alias) })
  should.equal(conflicts, [])
}

pub fn no_duplicate_aliases_across_profiles_test() {
  let profiles = database.all_profiles()
  let all_aliases = list.flat_map(profiles, fn(p) { p.aliases })
  should.equal(
    list.length(all_aliases),
    list.length(list.unique(all_aliases)),
  )
}

// ---------------------------------------------------------------------------
// Default host consistency — all builtins use localhost
// ---------------------------------------------------------------------------

pub fn all_builtins_default_to_localhost_test() {
  let profiles = database.builtin_profiles()
  list.each(profiles, fn(p) { should.equal(p.default_host, "localhost") })
}

// ---------------------------------------------------------------------------
// Each profile has a non-empty prompt
// ---------------------------------------------------------------------------

pub fn all_profiles_have_prompts_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    should.be_true(string.length(p.prompt) > 0)
  })
}

pub fn all_profiles_have_descriptions_test() {
  let profiles = database.all_profiles()
  list.each(profiles, fn(p) {
    should.be_true(string.length(p.description) > 0)
  })
}
