// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// highlight.gleam — ANSI keyword highlighting for NQC query output.
//
// Highlights recognised query language keywords in ANSI bold/colour when
// displaying queries in the REPL. Uses the keyword list from the active
// database profile. Terminal colour support is detected via TERM env var.

import gleam/list
import gleam/string

/// ANSI escape codes for keyword highlighting.
const ansi_bold = "\u{001b}[1m"

const ansi_cyan = "\u{001b}[36m"

const ansi_yellow = "\u{001b}[33m"

const ansi_reset = "\u{001b}[0m"

/// Highlight keywords in a query string using ANSI escape codes.
/// Keywords are matched case-insensitively and rendered in bold cyan.
/// Non-keyword tokens are left unchanged.
pub fn highlight_query(query: String, keywords: List(String)) -> String {
  case supports_colour() {
    False -> query
    True -> {
      let upper_keywords = list.map(keywords, string.uppercase)
      let tokens = tokenize(query)
      tokens
      |> list.map(fn(token) { highlight_token(token, upper_keywords) })
      |> string.join("")
    }
  }
}

/// Highlight a keyword ribbon (the \keywords display).
/// Renders each keyword in bold yellow, separated by commas.
pub fn highlight_keyword_list(keywords: List(String)) -> String {
  case supports_colour() {
    False -> string.join(keywords, ", ")
    True ->
      keywords
      |> list.map(fn(kw) { ansi_bold <> ansi_yellow <> kw <> ansi_reset })
      |> string.join(", ")
  }
}

/// Highlight a single token if it matches a keyword.
fn highlight_token(token: String, upper_keywords: List(String)) -> String {
  let upper = string.uppercase(token)
  case list.contains(upper_keywords, upper) {
    True -> ansi_bold <> ansi_cyan <> token <> ansi_reset
    False -> token
  }
}

/// Tokenize a string into words and whitespace/punctuation runs.
/// This is a simple split that preserves all characters.
fn tokenize(input: String) -> List(String) {
  tokenize_loop(string.to_graphemes(input), "", [], False)
}

/// Tokenize loop — accumulates characters into word or non-word tokens.
fn tokenize_loop(
  chars: List(String),
  current: String,
  acc: List(String),
  in_word: Bool,
) -> List(String) {
  case chars {
    [] -> {
      case current {
        "" -> list.reverse(acc)
        _ -> list.reverse([current, ..acc])
      }
    }
    [ch, ..rest] -> {
      let is_word_char = is_alpha(ch) || ch == "_"
      case is_word_char, in_word {
        // Word char while in word — extend current token.
        True, True -> tokenize_loop(rest, current <> ch, acc, True)
        // Word char while not in word — flush current, start word.
        True, False ->
          case current {
            "" -> tokenize_loop(rest, ch, acc, True)
            _ -> tokenize_loop(rest, ch, [current, ..acc], True)
          }
        // Non-word char while in word — flush word, start non-word.
        False, True ->
          case current {
            "" -> tokenize_loop(rest, ch, acc, False)
            _ -> tokenize_loop(rest, ch, [current, ..acc], False)
          }
        // Non-word char while not in word — extend current.
        False, False -> tokenize_loop(rest, current <> ch, acc, False)
      }
    }
  }
}

/// Check if a single grapheme is alphabetic.
fn is_alpha(ch: String) -> Bool {
  let upper = string.uppercase(ch)
  case upper {
    "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L"
    | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W"
    | "X" | "Y" | "Z" -> True
    _ -> False
  }
}

/// Check if the terminal supports ANSI colour.
/// Returns True if TERM is set and is not "dumb".
fn supports_colour() -> Bool {
  case get_term_env() {
    Ok("dumb") -> False
    Ok("") -> False
    Ok(_) -> True
    Error(_) -> False
  }
}

@external(erlang, "nqc_highlight_ffi", "get_term_env")
fn get_term_env() -> Result(String, Nil)
