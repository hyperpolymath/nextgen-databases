// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// nqc.gleam — NextGen Query Client entry point.
//
// A unified REPL for database query languages. Ships with built-in support
// for the three NextGen databases (VQL, GQL, KQL) and is extensible to any
// database that speaks HTTP + JSON.
//
// Usage:
//   gleam run                                  # Interactive database selector
//   gleam run -- --db vql                      # Connect to VeriSimDB
//   gleam run -- --db gql --port 8081          # Connect to Lithoglyph
//   gleam run -- --db kql --host 10.0.0.5      # Connect to QuandleDB
//   gleam run -- --db vql --dt                 # Enable dependent types
//   gleam run -- --db sql --port 3000          # Connect to a custom SQL database

import gleam/io
import gleam/list
import gleam/string
import gleam/result
import gleam/int
import argv

import nqc/database.{type DatabaseProfile}
import nqc/client
import nqc/formatter

/// REPL session state.
type Session {
  Session(
    /// Active database connection.
    conn: database.Connection,
    /// Current output format.
    format: formatter.OutputFormat,
    /// Whether to show query timing.
    show_timing: Bool,
    /// Whether the REPL should exit.
    should_exit: Bool,
  )
}

/// Entry point — parse CLI arguments and start the REPL.
pub fn main() {
  let args = argv.load().arguments

  case parse_args(args) {
    Ok(session) -> {
      print_banner(session)
      repl_loop(session)
    }
    Error("interactive") -> {
      case interactive_select() {
        Ok(session) -> {
          print_banner(session)
          repl_loop(session)
        }
        Error(_) -> {
          io.println("\nGoodbye.")
        }
      }
    }
    Error("help") -> {
      print_usage()
    }
    Error(msg) -> {
      io.println("Error: " <> msg)
      io.println("")
      print_usage()
    }
  }
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

/// Parse CLI arguments into a Session.
fn parse_args(args: List(String)) -> Result(Session, String) {
  let db_flag = find_flag_value(args, "--db")
  let host = find_flag_value(args, "--host")
  let port = find_flag_value(args, "--port")
  let format = find_flag_value(args, "--format")
  let dt = list.contains(args, "--dt")

  case db_flag {
    Ok(k) -> {
      use profile <- result.try(database.find_profile(k))
      let conn = database.connection_from_profile(profile)

      // Apply overrides.
      let conn = case host {
        Ok(h) -> database.Connection(..conn, host: h)
        Error(_) -> conn
      }
      let conn = case port {
        Ok(p) ->
          case int.parse(p) {
            Ok(n) -> database.Connection(..conn, port: n)
            Error(_) -> conn
          }
        Error(_) -> conn
      }
      let conn = database.Connection(..conn, dt_enabled: dt)

      let fmt = case format {
        Ok(f) -> result.unwrap(formatter.parse_format(f), formatter.Table)
        Error(_) -> formatter.Table
      }

      Ok(Session(
        conn: conn,
        format: fmt,
        show_timing: False,
        should_exit: False,
      ))
    }
    Error(_) -> {
      case args {
        [] -> Error("interactive")
        ["--help"] | ["-h"] -> Error("help")
        _ -> {
          let ids =
            database.all_profiles()
            |> list.map(fn(p) { p.id })
            |> string.join(", ")
          Error("Missing --db flag. Available databases: " <> ids <> ".")
        }
      }
    }
  }
}

/// Find the value following a flag in the argument list.
fn find_flag_value(
  args: List(String),
  flag: String,
) -> Result(String, Nil) {
  case args {
    [] -> Error(Nil)
    [f, value, ..] if f == flag -> Ok(value)
    [_, ..rest] -> find_flag_value(rest, flag)
  }
}

// ---------------------------------------------------------------------------
// REPL loop
// ---------------------------------------------------------------------------

/// Main REPL loop — reads lines, dispatches commands, displays results.
fn repl_loop(session: Session) -> Nil {
  case session.should_exit {
    True -> {
      io.println("Goodbye.")
      Nil
    }
    False -> {
      let prompt = session.conn.profile.prompt
      case read_line(prompt) {
        Ok(line) -> {
          let trimmed = string.trim(line)
          let new_session = handle_input(session, trimmed)
          repl_loop(new_session)
        }
        Error(_) -> {
          // EOF (Ctrl-D)
          io.println("\nGoodbye.")
          Nil
        }
      }
    }
  }
}

/// Handle a line of input — dispatch to meta-commands or query execution.
fn handle_input(session: Session, input: String) -> Session {
  case input {
    "" -> session
    "\\" <> _ -> handle_meta_command(session, input)
    _ -> {
      // Strip trailing semicolons.
      let query = string.trim_end(input) |> strip_trailing_semicolons
      execute_and_display(session, query)
    }
  }
}

/// Strip trailing semicolons from a query.
fn strip_trailing_semicolons(s: String) -> String {
  case string.ends_with(s, ";") {
    True -> strip_trailing_semicolons(string.drop_end(s, 1))
    False -> s
  }
}

/// Execute a query and display the result.
fn execute_and_display(session: Session, query: String) -> Session {
  case query {
    "" -> session
    _ -> {
      let start = now_ms()
      case client.execute(session.conn, query) {
        Ok(value) -> {
          let output = formatter.format_result(value, session.format)
          io.println(output)

          case session.show_timing {
            True -> {
              let elapsed = now_ms() - start
              io.println(
                "Time: " <> int.to_string(elapsed) <> "ms",
              )
            }
            False -> Nil
          }

          session
        }
        Error(err) -> {
          io.println("Error: " <> client.error_to_string(err))
          session
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Meta-commands
// ---------------------------------------------------------------------------

/// Handle a meta-command (line starting with '\').
fn handle_meta_command(session: Session, line: String) -> Session {
  let parts = string.split(line, " ")
  let cmd = result.unwrap(list.first(parts), "")
  let arg =
    parts
    |> list.drop(1)
    |> string.join(" ")
    |> string.trim

  case cmd {
    "\\quit" | "\\q" -> Session(..session, should_exit: True)

    "\\help" | "\\h" | "\\?" -> {
      print_help(session.conn.profile)
      session
    }

    "\\connect" -> {
      case arg {
        "" -> {
          io.println(
            "Connected to: "
            <> session.conn.profile.display_name
            <> " at "
            <> database.base_url(session.conn),
          )
          io.println("Usage: \\connect <host:port>")
          session
        }
        addr -> {
          let parts = string.split(addr, ":")
          case parts {
            [host, port_str] ->
              case int.parse(port_str) {
                Ok(port) -> {
                  let new_conn =
                    database.Connection(..session.conn, host: host, port: port)
                  io.println(
                    "Connected to " <> database.base_url(new_conn),
                  )
                  Session(..session, conn: new_conn)
                }
                Error(_) -> {
                  io.println("Invalid port: " <> port_str)
                  session
                }
              }
            [host] -> {
              let new_conn = database.Connection(..session.conn, host: host)
              io.println("Connected to " <> database.base_url(new_conn))
              Session(..session, conn: new_conn)
            }
            _ -> {
              io.println("Usage: \\connect <host:port>")
              session
            }
          }
        }
      }
    }

    "\\timing" -> {
      let new_timing = !session.show_timing
      io.println(
        "Timing display: "
        <> case new_timing {
          True -> "on"
          False -> "off"
        },
      )
      Session(..session, show_timing: new_timing)
    }

    "\\format" -> {
      case arg {
        "" -> {
          io.println("Current format: " <> format_to_string(session.format))
          io.println("Usage: \\format <table|json|csv>")
          session
        }
        fmt_str ->
          case formatter.parse_format(fmt_str) {
            Ok(fmt) -> {
              io.println("Output format: " <> format_to_string(fmt))
              Session(..session, format: fmt)
            }
            Error(msg) -> {
              io.println("Error: " <> msg)
              session
            }
          }
      }
    }

    "\\status" -> {
      case client.health(session.conn) {
        Ok(value) -> {
          let output = formatter.format_result(value, session.format)
          io.println(output)
        }
        Error(err) -> {
          io.println(
            "Error: Server at "
            <> database.base_url(session.conn)
            <> " is unreachable: "
            <> client.error_to_string(err),
          )
        }
      }
      session
    }

    "\\dt" -> {
      case session.conn.profile.supports_dt {
        True -> {
          let new_dt = !session.conn.dt_enabled
          let new_conn = database.Connection(..session.conn, dt_enabled: new_dt)
          io.println(
            "Dependent type verification: "
            <> case new_dt {
              True -> "ON"
              False -> "OFF"
            },
          )
          Session(..session, conn: new_conn)
        }
        False -> {
          io.println(
            session.conn.profile.display_name
            <> " does not support dependent type verification.",
          )
          session
        }
      }
    }

    "\\db" -> {
      case arg {
        "" -> {
          io.println(
            "Current database: "
            <> session.conn.profile.display_name
            <> " ("
            <> session.conn.profile.language_name
            <> ")",
          )
          let ids =
            database.all_profiles()
            |> list.map(fn(p) { p.id })
            |> string.join("|")
          io.println("Usage: \\db <" <> ids <> ">")
          session
        }
        id_str ->
          case database.find_profile(id_str) {
            Ok(new_profile) -> {
              let new_conn = database.connection_from_profile(new_profile)
              // Preserve host and DT settings when switching.
              let new_conn =
                database.Connection(
                  ..new_conn,
                  host: session.conn.host,
                  dt_enabled: session.conn.dt_enabled,
                )
              io.println(
                "Switched to "
                <> new_profile.display_name
                <> " at "
                <> database.base_url(new_conn),
              )
              Session(..session, conn: new_conn)
            }
            Error(msg) -> {
              io.println("Error: " <> msg)
              session
            }
          }
      }
    }

    "\\keywords" -> {
      io.println(
        session.conn.profile.language_name <> " keywords:",
      )
      io.println(string.join(session.conn.profile.keywords, ", "))
      session
    }

    "\\databases" | "\\dbs" -> {
      print_database_list()
      session
    }

    _ -> {
      io.println(
        "Unknown command: "
        <> cmd
        <> ". Type \\help for available commands.",
      )
      session
    }
  }
}

// ---------------------------------------------------------------------------
// Interactive database selection
// ---------------------------------------------------------------------------

/// Present an interactive menu for choosing which database to connect to.
/// Shown when NQC is launched with no arguments. Lists ALL registered
/// databases — built-in and custom.
fn interactive_select() -> Result(Session, Nil) {
  let profiles = database.all_profiles()
  let count = list.length(profiles)

  io.println("")
  io.println("  NQC - NextGen Query Client v0.1.0")
  io.println("")
  io.println("  Select a database:")
  io.println("")

  // Print numbered list of all available databases.
  print_profile_menu(profiles, 1)

  io.println("")
  select_database_loop(profiles, count)
}

/// Print the numbered profile menu.
fn print_profile_menu(profiles: List(DatabaseProfile), n: Int) -> Nil {
  case profiles {
    [] -> Nil
    [profile, ..rest] -> {
      let num = int.to_string(n)
      let pad = case n < 10 {
        True -> " "
        False -> ""
      }
      io.println(
        "    "
        <> pad
        <> num
        <> ". "
        <> profile.display_name
        <> "  ("
        <> profile.language_name
        <> ")  — "
        <> profile.description,
      )
      print_profile_menu(rest, n + 1)
    }
  }
}

/// Prompt loop — keeps asking until the user picks a valid option or cancels.
fn select_database_loop(
  profiles: List(DatabaseProfile),
  count: Int,
) -> Result(Session, Nil) {
  let prompt_text =
    "  Enter number (1-" <> int.to_string(count) <> ") or database ID: "

  case read_line(prompt_text) {
    Ok(input) -> {
      let trimmed = string.trim(input)
      case trimmed {
        "q" | "quit" | "" -> Error(Nil)
        _ -> {
          // Try as a number first.
          case int.parse(trimmed) {
            Ok(n) if n >= 1 && n <= count -> {
              case list_at(profiles, n - 1) {
                Ok(profile) ->
                  Ok(make_session_from_profile(profile))
                Error(_) -> {
                  io.println("  Invalid number.")
                  select_database_loop(profiles, count)
                }
              }
            }
            _ -> {
              // Try as a database ID or alias.
              case database.find_profile(trimmed) {
                Ok(profile) ->
                  Ok(make_session_from_profile(profile))
                Error(_) -> {
                  io.println(
                    "  Unknown database. Enter a number or ID (q to quit).",
                  )
                  select_database_loop(profiles, count)
                }
              }
            }
          }
        }
      }
    }
    // EOF (Ctrl-D)
    Error(_) -> Error(Nil)
  }
}

/// Get the nth element from a list (0-indexed).
fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    [], _ -> Error(Nil)
    [item, ..], 0 -> Ok(item)
    [_, ..rest], n -> list_at(rest, n - 1)
  }
}

/// Create a default session from a database profile.
fn make_session_from_profile(profile: DatabaseProfile) -> Session {
  Session(
    conn: database.connection_from_profile(profile),
    format: formatter.Table,
    show_timing: False,
    should_exit: False,
  )
}

// ---------------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------------

/// Print the welcome banner.
fn print_banner(session: Session) -> Nil {
  let profile = session.conn.profile
  io.println("")
  io.println("  NQC - NextGen Query Client v0.1.0")
  io.println(
    "  Database: "
    <> profile.display_name
    <> " ("
    <> profile.language_name
    <> ")",
  )
  io.println("  Server:   " <> database.base_url(session.conn))
  case profile.supports_dt {
    True ->
      io.println(
        "  DT:       "
        <> case session.conn.dt_enabled {
          True -> "ON"
          False -> "OFF"
        },
      )
    False -> Nil
  }
  io.println("  Format:   " <> format_to_string(session.format))
  io.println("")
  io.println("  Type \\help for help, \\quit to exit.")
  io.println("")
}

/// Print help text.
fn print_help(profile: DatabaseProfile) -> Nil {
  let lang = profile.language_name
  let ids =
    database.all_profiles()
    |> list.map(fn(p) { p.id })
    |> string.join("|")

  io.println("")
  io.println("  NQC Meta-Commands")
  io.println("")
  io.println("  \\connect <host:port>  Change server connection")
  io.println("  \\db <" <> ids <> ">   Switch database backend")
  io.println("  \\databases            List all available databases")
  case profile.supports_dt {
    True ->
      io.println("  \\dt                   Toggle dependent type verification")
    False -> Nil
  }
  io.println("  \\format <fmt>         Set output format (table|json|csv)")
  io.println("  \\timing               Toggle query timing display")
  io.println("  \\status               Show server health")
  io.println("  \\keywords             List " <> lang <> " keywords")
  io.println("  \\help                 Show this help")
  io.println("  \\quit / \\q            Exit")
  io.println("")
  io.println("  Query Input")
  io.println("")
  io.println(
    "  Enter " <> lang <> " queries at the prompt. Trailing semicolons stripped.",
  )
  io.println("")
}

/// Print the list of all available databases (for \databases command).
fn print_database_list() -> Nil {
  let profiles = database.all_profiles()
  io.println("")
  io.println("  Available databases:")
  io.println("")
  print_database_list_items(profiles)
  io.println("")
  io.println("  Switch with: \\db <id>")
  io.println(
    "  Add your own in database.gleam → custom_profiles()",
  )
  io.println("")
}

/// Print each database profile in the list view.
fn print_database_list_items(profiles: List(DatabaseProfile)) -> Nil {
  case profiles {
    [] -> Nil
    [p, ..rest] -> {
      let dt_marker = case p.supports_dt {
        True -> " [DT]"
        False -> ""
      }
      io.println(
        "    "
        <> p.id
        <> "  "
        <> p.display_name
        <> " ("
        <> p.language_name
        <> ")"
        <> dt_marker
        <> "  — "
        <> p.description,
      )
      print_database_list_items(rest)
    }
  }
}

/// Print usage for --help.
fn print_usage() -> Nil {
  let ids =
    database.all_profiles()
    |> list.map(fn(p) { p.id })
    |> string.join("|")

  io.println("Usage: nqc [OPTIONS]")
  io.println("")
  io.println("Options:")
  io.println("  --db <" <> ids <> ">  Database backend (interactive if omitted)")
  io.println("  --host <host>         Server hostname (default: localhost)")
  io.println("  --port <port>         Server port (default: per database)")
  io.println("  --format <fmt>        Output format: table|json|csv (default: table)")
  io.println("  --dt                  Enable dependent type verification")
  io.println("  --help / -h           Show this help")
}

/// Format name for display.
fn format_to_string(format: formatter.OutputFormat) -> String {
  case format {
    formatter.Table -> "table"
    formatter.Json -> "json"
    formatter.Csv -> "csv"
  }
}

// ---------------------------------------------------------------------------
// FFI helpers
// ---------------------------------------------------------------------------

/// Read a line from stdin with a prompt.
fn read_line(prompt: String) -> Result(String, Nil) {
  case read_line_ffi(prompt) {
    Ok(line) -> Ok(string.trim_end(line))
    Error(_) -> Error(Nil)
  }
}

@external(erlang, "nqc_ffi", "read_line")
fn read_line_ffi(prompt: String) -> Result(String, Nil)

/// Get current time in milliseconds (monotonic).
@external(erlang, "erlang", "system_time")
fn now_ms() -> Int
