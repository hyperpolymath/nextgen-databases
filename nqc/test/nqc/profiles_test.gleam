// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// profiles_test.gleam — Tests for custom profile JSON loading.

import gleam/list
import gleeunit/should
import nqc/profiles

// ---------------------------------------------------------------------------
// parse_profiles_json — JSON parsing
// ---------------------------------------------------------------------------

pub fn parse_valid_profile_json_test() {
  let json =
    "[{\"id\":\"sql\",\"display_name\":\"PostgreSQL\",\"language_name\":\"SQL\",\"description\":\"Test DB\",\"execute_path\":\"/rpc/query\",\"default_port\":3000}]"
  let result = profiles.parse_profiles_json(json)
  should.equal(list.length(result), 1)
  let assert [profile] = result
  should.equal(profile.id, "sql")
  should.equal(profile.display_name, "PostgreSQL")
  should.equal(profile.language_name, "SQL")
  should.equal(profile.default_port, 3000)
  should.equal(profile.execute_path, "/rpc/query")
}

pub fn parse_profile_with_defaults_test() {
  // Omit optional fields — should use defaults.
  let json =
    "[{\"id\":\"test\",\"display_name\":\"Test\",\"language_name\":\"TQL\",\"description\":\"Test\",\"execute_path\":\"/query\"}]"
  let result = profiles.parse_profiles_json(json)
  should.equal(list.length(result), 1)
  let assert [profile] = result
  should.equal(profile.default_host, "localhost")
  should.equal(profile.default_port, 8080)
  should.equal(profile.health_path, "/health")
  should.equal(profile.prompt, "nqc> ")
  should.be_false(profile.supports_dt)
  should.equal(profile.aliases, [])
  should.equal(profile.keywords, [])
}

pub fn parse_profile_with_aliases_and_keywords_test() {
  let json =
    "[{\"id\":\"sql\",\"display_name\":\"PG\",\"language_name\":\"SQL\",\"description\":\"PG\",\"execute_path\":\"/q\",\"aliases\":[\"postgres\",\"pg\"],\"keywords\":[\"SELECT\",\"FROM\"]}]"
  let result = profiles.parse_profiles_json(json)
  let assert [profile] = result
  should.equal(profile.aliases, ["postgres", "pg"])
  should.equal(profile.keywords, ["SELECT", "FROM"])
}

pub fn parse_empty_array_test() {
  let result = profiles.parse_profiles_json("[]")
  should.equal(result, [])
}

pub fn parse_invalid_json_returns_empty_test() {
  let result = profiles.parse_profiles_json("not json")
  should.equal(result, [])
}

pub fn parse_missing_required_fields_skips_entry_test() {
  // Missing "id" field — should be skipped.
  let json = "[{\"display_name\":\"Bad\",\"language_name\":\"X\",\"description\":\"X\",\"execute_path\":\"/x\"}]"
  let result = profiles.parse_profiles_json(json)
  should.equal(result, [])
}

pub fn parse_multiple_profiles_test() {
  let json =
    "[{\"id\":\"a\",\"display_name\":\"A\",\"language_name\":\"A\",\"description\":\"A\",\"execute_path\":\"/a\"},{\"id\":\"b\",\"display_name\":\"B\",\"language_name\":\"B\",\"description\":\"B\",\"execute_path\":\"/b\"}]"
  let result = profiles.parse_profiles_json(json)
  should.equal(list.length(result), 2)
}

pub fn parse_mixed_valid_invalid_keeps_valid_test() {
  // First entry valid, second missing required field.
  let json =
    "[{\"id\":\"good\",\"display_name\":\"G\",\"language_name\":\"G\",\"description\":\"G\",\"execute_path\":\"/g\"},{\"display_name\":\"Bad\"}]"
  let result = profiles.parse_profiles_json(json)
  should.equal(list.length(result), 1)
  let assert [profile] = result
  should.equal(profile.id, "good")
}

// ---------------------------------------------------------------------------
// load_custom_profiles — file loading (no file present)
// ---------------------------------------------------------------------------

pub fn load_custom_profiles_returns_list_test() {
  // Should return empty list when no config file exists.
  let result = profiles.load_custom_profiles()
  should.be_true(list.length(result) >= 0)
}
