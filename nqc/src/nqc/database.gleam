// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// database.gleam — Extensible database profile registry for the NextGen Query Client.
//
// Defines database profiles (connection parameters, keywords, prompts) for
// the three built-in NextGen databases (VCL, GQL, KQL) and supports custom
// profiles for any database that speaks HTTP + JSON. All databases use the
// same protocol pattern: POST /execute with {"query": "..."} and receive
// JSON results.
//
// Adding a new database:
//   1. Create a DatabaseProfile with your database's metadata.
//   2. Add it to the registry via custom_profiles() or load from config.
//   3. NQC will show it in the interactive selector automatically.

import gleam/int
import gleam/list
import gleam/string

/// A database profile — everything NQC needs to know about a database.
/// Built-in databases (VCL, GQL, KQL) are pre-defined profiles.
/// Custom databases use the same structure.
pub type DatabaseProfile {
  DatabaseProfile(
    /// Short identifier used in CLI flags and \db command (e.g. "vcl", "sql").
    id: String,
    /// Human-readable name (e.g. "VeriSimDB", "PostgreSQL").
    display_name: String,
    /// Query language name (e.g. "VCL", "SQL").
    language_name: String,
    /// Short description for the interactive selector.
    description: String,
    /// Alternative names accepted by parse_kind (e.g. ["verisimdb", "verisim"]).
    aliases: List(String),
    /// Default server hostname.
    default_host: String,
    /// Default server port.
    default_port: Int,
    /// API endpoint path for query execution (e.g. "/vcl/execute").
    execute_path: String,
    /// API endpoint path for health checks (e.g. "/health").
    health_path: String,
    /// REPL prompt string (e.g. "vcl> ").
    prompt: String,
    /// Whether this database supports dependent type verification.
    supports_dt: Bool,
    /// Primary keywords for the query language (used for display and future
    /// syntax highlighting / tab completion).
    keywords: List(String),
  )
}

/// Connection configuration for a live database session.
pub type Connection {
  Connection(
    /// The active database profile.
    profile: DatabaseProfile,
    /// Hostname or IP address (overrides profile default).
    host: String,
    /// Port number (overrides profile default).
    port: Int,
    /// Whether dependent type verification is enabled.
    dt_enabled: Bool,
  )
}

// ---------------------------------------------------------------------------
// Built-in NextGen database profiles
// ---------------------------------------------------------------------------

/// VeriSimDB — 6-core multimodal database with self-normalization.
pub fn vcl_profile() -> DatabaseProfile {
  DatabaseProfile(
    id: "vcl",
    display_name: "VeriSimDB",
    language_name: "VCL",
    description: "6-core multimodal database with self-normalization",
    aliases: ["verisimdb", "verisim"],
    default_host: "localhost",
    default_port: 8080,
    execute_path: "/vcl/execute",
    health_path: "/health",
    prompt: "vcl> ",
    supports_dt: True,
    keywords: [
      "SELECT", "FROM", "WHERE", "LIMIT", "INSERT", "INTO", "VALUES",
      "DELETE", "SEARCH", "TEXT", "VECTOR", "RELATED", "BY", "SHOW",
      "STATUS", "DRIFT", "NORMALIZER", "HEXADS", "COUNT", "EXPLAIN",
      "GRAPH", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL", "HEXAD",
      "PROOF", "WITNESS", "VERIFY",
    ],
  )
}

/// Lithoglyph — graph database with formal verification.
pub fn gql_profile() -> DatabaseProfile {
  DatabaseProfile(
    id: "gql",
    display_name: "Lithoglyph",
    language_name: "GQL",
    description: "Graph database with formal verification",
    aliases: ["lithoglyph", "formdb"],
    default_host: "localhost",
    default_port: 8081,
    execute_path: "/gql/execute",
    health_path: "/health",
    prompt: "gql> ",
    supports_dt: True,
    keywords: [
      "MATCH", "CREATE", "DELETE", "SET", "RETURN", "WHERE", "AND", "OR",
      "NOT", "WITH", "UNWIND", "ORDER", "BY", "LIMIT", "SKIP", "VERTEX",
      "EDGE", "PATH", "SHORTEST", "PATTERN", "PROPERTIES", "LABELS",
      "PROOF", "WITNESS", "VERIFY", "MORPHISM", "FUNCTOR",
    ],
  )
}

/// QuandleDB — knot-theoretic database for structural equivalence.
pub fn kql_profile() -> DatabaseProfile {
  DatabaseProfile(
    id: "kql",
    display_name: "QuandleDB",
    language_name: "KQL",
    description: "Knot-theoretic structural equivalence database",
    aliases: ["quandledb", "quandle"],
    default_host: "localhost",
    default_port: 8082,
    execute_path: "/kql/execute",
    health_path: "/health",
    prompt: "kql> ",
    supports_dt: True,
    keywords: [
      "DEFORM", "CLASSIFY", "CONNECT", "DISTINGUISH", "TRANSFORM",
      "WITNESS", "UNDER", "REIDEMEISTER", "ISOTOPY", "INVARIANT",
      "CROSSING", "KNOT", "LINK", "BRAID", "QUANDLE", "RACK",
      "JONES", "ALEXANDER", "HOMFLY", "BRACKET", "WRITHE",
      "PROOF", "VERIFY", "EQUIVALENT",
    ],
  )
}

// ---------------------------------------------------------------------------
// Profile registry
// ---------------------------------------------------------------------------

/// Return all built-in database profiles (the three NextGen databases).
pub fn builtin_profiles() -> List(DatabaseProfile) {
  [vcl_profile(), gql_profile(), kql_profile()]
}

/// Return all available database profiles — builtins plus any custom ones.
/// Custom profiles are appended after the built-in three.
pub fn all_profiles() -> List(DatabaseProfile) {
  list.append(builtin_profiles(), custom_profiles())
}

/// Custom database profiles. Returns an empty list by default.
/// Use database.load_all_profiles() to include file-loaded profiles.
pub fn custom_profiles() -> List(DatabaseProfile) {
  []
}

/// Load all profiles — builtins plus any from nqc-profiles.json.
/// This is the preferred entry point for the REPL (avoids import cycle).
pub fn load_all_profiles(file_profiles: List(DatabaseProfile)) -> List(DatabaseProfile) {
  list.append(builtin_profiles(), file_profiles)
}

// ---------------------------------------------------------------------------
// Profile lookup
// ---------------------------------------------------------------------------

/// Find a database profile by ID or alias string.
/// Searches all registered profiles (built-in + custom).
pub fn find_profile(s: String) -> Result(DatabaseProfile, String) {
  let needle = string.lowercase(s)
  let profiles = all_profiles()

  case find_profile_in(profiles, needle) {
    Ok(profile) -> Ok(profile)
    Error(_) -> {
      let ids =
        profiles
        |> list.map(fn(p) { p.id })
        |> string.join(", ")
      Error("Unknown database: '" <> s <> "'. Available: " <> ids <> ".")
    }
  }
}

/// Search a profile list for a matching ID or alias.
fn find_profile_in(
  profiles: List(DatabaseProfile),
  needle: String,
) -> Result(DatabaseProfile, Nil) {
  case profiles {
    [] -> Error(Nil)
    [profile, ..rest] -> {
      case profile.id == needle || list.contains(profile.aliases, needle) {
        True -> Ok(profile)
        False -> find_profile_in(rest, needle)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Connection builders
// ---------------------------------------------------------------------------

/// Create a default connection from a database profile.
pub fn connection_from_profile(profile: DatabaseProfile) -> Connection {
  Connection(
    profile: profile,
    host: profile.default_host,
    port: profile.default_port,
    dt_enabled: False,
  )
}

/// Build the full base URL for a connection.
pub fn base_url(conn: Connection) -> String {
  "http://" <> conn.host <> ":" <> int.to_string(conn.port)
}

/// Build the full execute URL for a connection.
pub fn execute_url(conn: Connection) -> String {
  base_url(conn) <> conn.profile.execute_path
}

/// Build the full health URL for a connection.
pub fn health_url(conn: Connection) -> String {
  base_url(conn) <> conn.profile.health_path
}
