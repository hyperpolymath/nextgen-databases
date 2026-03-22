// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// history.gleam — Query history persistence for NQC.
//
// Stores query history across sessions in ~/.nqc_history (one query per line,
// most recent last). Limited to the last 500 entries to avoid unbounded growth.

import gleam/list
import gleam/string
import simplifile

/// Maximum number of history entries to retain.
const max_history_entries = 500

/// The history file path.
const history_file = "~/.nqc_history"

/// A query history — list of past queries, most recent last.
pub type History {
  History(entries: List(String))
}

/// Create an empty history.
pub fn empty() -> History {
  History(entries: [])
}

/// Load history from the persistent file.
/// Returns an empty history if the file doesn't exist or can't be read.
pub fn load() -> History {
  let path = expand_home(history_file)
  case simplifile.read(path) {
    Ok(contents) -> {
      let entries =
        contents
        |> string.split("\n")
        |> list.filter(fn(line) { string.trim(line) != "" })
      History(entries: entries)
    }
    Error(_) -> empty()
  }
}

/// Save history to the persistent file.
/// Truncates to the most recent max_history_entries entries.
pub fn save(history: History) -> Nil {
  let path = expand_home(history_file)
  let trimmed = trim_entries(history.entries)
  let contents = string.join(trimmed, "\n") <> "\n"
  let _ = simplifile.write(path, contents)
  Nil
}

/// Add a query to history (deduplicates consecutive identical queries).
pub fn add(history: History, query: String) -> History {
  let trimmed = string.trim(query)
  case trimmed {
    "" -> history
    _ -> {
      // Remove duplicate if it's the last entry (consecutive dedup).
      let entries = case list.last(history.entries) {
        Ok(last) if last == trimmed -> history.entries
        _ -> list.append(history.entries, [trimmed])
      }
      History(entries: trim_entries(entries))
    }
  }
}

/// Get the most recent N entries (most recent first).
pub fn recent(history: History, count: Int) -> List(String) {
  history.entries
  |> list.reverse
  |> list.take(count)
}

/// Get the total number of entries.
pub fn length(history: History) -> Int {
  list.length(history.entries)
}

/// Search history for entries containing a substring.
pub fn search(history: History, needle: String) -> List(String) {
  let lower_needle = string.lowercase(needle)
  history.entries
  |> list.filter(fn(entry) {
    string.contains(string.lowercase(entry), lower_needle)
  })
  |> list.reverse
}

/// Trim the entry list to max_history_entries, keeping the most recent.
fn trim_entries(entries: List(String)) -> List(String) {
  let len = list.length(entries)
  case len > max_history_entries {
    True -> list.drop(entries, len - max_history_entries)
    False -> entries
  }
}

/// Expand ~ to home directory.
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

@external(erlang, "nqc_profiles_ffi", "get_home_dir")
fn get_home_dir() -> Result(String, Nil)
