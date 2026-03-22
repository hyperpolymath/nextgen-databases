// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// profiles.gleam — Custom profile loader for nqc-profiles.json.
//
// Loads database profiles from a JSON configuration file, enabling users
// to add custom database backends without modifying source code. The file
// is expected at ./nqc-profiles.json or ~/.config/nqc/profiles.json.
//
// Returns DatabaseProfile values from nqc/database — but to avoid import
// cycles, the loader is called from nqc.gleam (the main module) which
// passes the results to database.load_all_profiles().
//
// JSON format:
//   [
//     {
//       "id": "sql",
//       "display_name": "PostgreSQL",
//       "language_name": "SQL",
//       "description": "PostgreSQL via PostgREST",
//       "aliases": ["postgres", "pg"],
//       "default_host": "localhost",
//       "default_port": 3000,
//       "execute_path": "/rpc/query",
//       "health_path": "/",
//       "prompt": "sql> ",
//       "supports_dt": false,
//       "keywords": ["SELECT", "FROM", "WHERE"]
//     }
//   ]

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import nqc/database.{type DatabaseProfile, DatabaseProfile}
import simplifile

/// Paths to search for profile configuration files, in priority order.
const profile_paths = [
  "./nqc-profiles.json", "~/.config/nqc/profiles.json",
]

/// Load custom profiles from the first available config file.
/// Returns an empty list if no config file is found or parsing fails.
pub fn load_custom_profiles() -> List(DatabaseProfile) {
  case find_config_file(profile_paths) {
    Ok(path) -> load_from_file(path)
    Error(_) -> []
  }
}

/// Find the first config file that exists.
fn find_config_file(paths: List(String)) -> Result(String, Nil) {
  case paths {
    [] -> Error(Nil)
    [path, ..rest] -> {
      let expanded = expand_home(path)
      case simplifile.is_file(expanded) {
        Ok(True) -> Ok(expanded)
        _ -> find_config_file(rest)
      }
    }
  }
}

/// Expand ~ to the home directory.
fn expand_home(path: String) -> String {
  case path {
    "~/" <> rest -> {
      case get_home_dir() {
        Ok(home) -> home <> "/" <> rest
        Error(_) -> path
      }
    }
    _ -> path
  }
}

/// Read and parse profiles from a JSON file.
fn load_from_file(path: String) -> List(DatabaseProfile) {
  case simplifile.read(path) {
    Ok(contents) -> parse_profiles_json(contents)
    Error(_) -> []
  }
}

/// Parse a JSON string into a list of database profiles.
pub fn parse_profiles_json(input: String) -> List(DatabaseProfile) {
  case json.parse(input, decode.dynamic) {
    Ok(value) -> decode_profile_list(value)
    Error(_) -> []
  }
}

/// Decode a dynamic value as a list of profiles.
fn decode_profile_list(value: Dynamic) -> List(DatabaseProfile) {
  let items = extract_list(value)
  list.filter_map(items, decode_profile)
}

/// Decode a single profile from a dynamic map.
fn decode_profile(value: Dynamic) -> Result(DatabaseProfile, Nil) {
  let id_result = extract_string_field(value, "id")
  let display_name_result = extract_string_field(value, "display_name")
  let language_name_result = extract_string_field(value, "language_name")
  let description_result = extract_string_field(value, "description")
  let default_host = result.unwrap(extract_string_field(value, "default_host"), "localhost")
  let default_port = result.unwrap(extract_int_field(value, "default_port"), 8080)
  let execute_path_result = extract_string_field(value, "execute_path")
  let health_path = result.unwrap(extract_string_field(value, "health_path"), "/health")
  let prompt = result.unwrap(extract_string_field(value, "prompt"), "nqc> ")
  let supports_dt = result.unwrap(extract_bool_field(value, "supports_dt"), False)
  let aliases = result.unwrap(extract_string_list_field(value, "aliases"), [])
  let keywords = result.unwrap(extract_string_list_field(value, "keywords"), [])

  case id_result, display_name_result, language_name_result, description_result, execute_path_result {
    Ok(id), Ok(display_name), Ok(language_name), Ok(description), Ok(execute_path) ->
      Ok(DatabaseProfile(
        id: id,
        display_name: display_name,
        language_name: language_name,
        description: description,
        aliases: aliases,
        default_host: default_host,
        default_port: default_port,
        execute_path: execute_path,
        health_path: health_path,
        prompt: prompt,
        supports_dt: supports_dt,
        keywords: keywords,
      ))
    _, _, _, _, _ -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// FFI helpers for dynamic JSON field extraction
// ---------------------------------------------------------------------------

@external(erlang, "nqc_ffi", "extract_list")
fn extract_list(value: Dynamic) -> List(Dynamic)

@external(erlang, "nqc_profiles_ffi", "extract_string_field")
fn extract_string_field(obj: Dynamic, key: String) -> Result(String, Nil)

@external(erlang, "nqc_profiles_ffi", "extract_int_field")
fn extract_int_field(obj: Dynamic, key: String) -> Result(Int, Nil)

@external(erlang, "nqc_profiles_ffi", "extract_bool_field")
fn extract_bool_field(obj: Dynamic, key: String) -> Result(Bool, Nil)

@external(erlang, "nqc_profiles_ffi", "extract_string_list_field")
fn extract_string_list_field(obj: Dynamic, key: String) -> Result(List(String), Nil)

@external(erlang, "nqc_profiles_ffi", "get_home_dir")
fn get_home_dir() -> Result(String, Nil)
