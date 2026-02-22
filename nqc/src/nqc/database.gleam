// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// database.gleam — Extensible database profile registry for the NextGen Query Client.
//
// Defines database profiles (connection parameters, keywords, prompts) for
// the three built-in NextGen databases (VQL, GQL, KQL) and supports custom
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
/// Built-in databases (VQL, GQL, KQL) are pre-defined profiles.
/// Custom databases use the same structure.
pub type DatabaseProfile {
  DatabaseProfile(
    /// Short identifier used in CLI flags and \db command (e.g. "vql", "sql").
    id: String,
    /// Human-readable name (e.g. "VeriSimDB", "PostgreSQL").
    display_name: String,
    /// Query language name (e.g. "VQL", "SQL").
    language_name: String,
    /// Short description for the interactive selector.
    description: String,
    /// Alternative names accepted by parse_kind (e.g. ["verisimdb", "verisim"]).
    aliases: List(String),
    /// Default server hostname.
    default_host: String,
    /// Default server port.
    default_port: Int,
    /// API endpoint path for query execution (e.g. "/vql/execute").
    execute_path: String,
    /// API endpoint path for health checks (e.g. "/health").
    health_path: String,
    /// REPL prompt string (e.g. "vql> ").
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
pub fn vql_profile() -> DatabaseProfile {
  DatabaseProfile(
    id: "vql",
    display_name: "VeriSimDB",
    language_name: "VQL",
    description: "6-core multimodal database with self-normalization",
    aliases: ["verisimdb", "verisim"],
    default_host: "localhost",
    default_port: 8080,
    execute_path: "/vql/execute",
    health_path: "/health",
    prompt: "vql> ",
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
  [vql_profile(), gql_profile(), kql_profile()]
}

/// Return all available database profiles — builtins plus any custom ones.
/// Custom profiles are appended after the built-in three.
pub fn all_profiles() -> List(DatabaseProfile) {
  list.append(builtin_profiles(), custom_profiles())
}

/// Custom database profiles. Edit this function to register your own databases.
///
/// Any database that accepts HTTP POST with {"query": "..."} and returns JSON
/// can be added here. Examples are provided as comments below.
pub fn custom_profiles() -> List(DatabaseProfile) {
  [
    // --- Uncomment or add your own profiles below ---
    //
    // DatabaseProfile(
    //   id: "sql",
    //   display_name: "PostgreSQL",
    //   language_name: "SQL",
    //   description: "PostgreSQL via PostgREST or pg-gateway",
    //   aliases: ["postgres", "postgresql", "pg"],
    //   default_host: "localhost",
    //   default_port: 3000,
    //   execute_path: "/rpc/query",
    //   health_path: "/",
    //   prompt: "sql> ",
    //   supports_dt: False,
    //   keywords: [
    //     "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES",
    //     "UPDATE", "SET", "DELETE", "JOIN", "LEFT", "RIGHT", "INNER",
    //     "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET",
    //     "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW",
    //     "BEGIN", "COMMIT", "ROLLBACK", "EXPLAIN", "ANALYZE",
    //   ],
    // ),
    //
    // DatabaseProfile(
    //   id: "mongo",
    //   display_name: "MongoDB",
    //   language_name: "MQL",
    //   description: "MongoDB via Data API",
    //   aliases: ["mongodb"],
    //   default_host: "localhost",
    //   default_port: 27017,
    //   execute_path: "/api/v1/action/find",
    //   health_path: "/api/v1",
    //   prompt: "mql> ",
    //   supports_dt: False,
    //   keywords: [
    //     "find", "insertOne", "insertMany", "updateOne", "updateMany",
    //     "deleteOne", "deleteMany", "aggregate", "count", "distinct",
    //   ],
    // ),
  ]
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
