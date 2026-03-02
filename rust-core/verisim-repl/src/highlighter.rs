// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! VQL syntax highlighting for the interactive REPL.
//!
//! Implements `rustyline::highlight::Highlighter` to colour VQL keywords,
//! modality names, string literals, and numeric literals as the user types.

use colored::Colorize;
use rustyline::highlight::Highlighter;
use std::borrow::Cow;

/// VQL keywords that are highlighted in blue/bold.
const VQL_KEYWORDS: &[&str] = &[
    "SELECT", "FROM", "WHERE", "PROOF", "LIMIT", "OFFSET", "ORDER", "BY",
    "GROUP", "HAVING", "AS", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE",
    "EXISTS", "CONTAINS", "SIMILAR", "TO", "TRAVERSE", "DEPTH", "THRESHOLD",
    "DRIFT", "CONSISTENCY", "AT", "TIME", "EXPLAIN", "INSERT", "UPDATE",
    "DELETE", "SET", "INTO", "VALUES", "CREATE", "DROP", "ALTER", "JOIN",
    "ON", "WITH", "FEDERATION", "STORE", "HEXAD", "ALL", "ASC", "DESC",
    "COUNT", "SUM", "AVG", "MIN", "MAX", "DISTINCT",
];

/// VQL modality names highlighted in green.
/// All 8 octad modalities: Graph, Vector, Tensor, Semantic, Document, Temporal,
/// Provenance, Spatial.
const VQL_MODALITIES: &[&str] = &[
    "GRAPH", "VECTOR", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL",
    "PROVENANCE", "SPATIAL",
];

/// Syntax highlighter for VQL input lines.
///
/// This is used by the rustyline `Editor` to provide real-time syntax
/// colouring as the user types queries.
pub struct VqlHighlighter;

impl Highlighter for VqlHighlighter {
    /// Highlight the input line with ANSI colour codes.
    ///
    /// The highlighting strategy is token-based:
    /// 1. String literals (single or double quoted) are coloured yellow.
    /// 2. Tokens matching VQL keywords are coloured blue and bold.
    /// 3. Tokens matching modality names are coloured green and bold.
    /// 4. Numeric tokens are coloured cyan.
    /// 5. Everything else is left uncoloured.
    fn highlight<'l>(&self, line: &'l str, _pos: usize) -> Cow<'l, str> {
        let highlighted = highlight_line(line);
        Cow::Owned(highlighted)
    }

    /// Indicate that we always want to repaint when the line changes.
    fn highlight_char(&self, _line: &str, _pos: usize, _forced: rustyline::highlight::CmdKind) -> bool {
        true
    }

    /// Highlight the prompt itself (not coloured — we handle prompt
    /// colouring in main).
    fn highlight_prompt<'b, 's: 'b, 'p: 'b>(
        &'s self,
        prompt: &'p str,
        _default: bool,
    ) -> Cow<'b, str> {
        Cow::Borrowed(prompt)
    }

    /// Highlight a hint (dimmed text shown after the cursor).
    fn highlight_hint<'h>(&self, hint: &'h str) -> Cow<'h, str> {
        Cow::Owned(hint.dimmed().to_string())
    }

    /// Highlight the currently selected candidate during completion.
    fn highlight_candidate<'c>(
        &self,
        candidate: &'c str,
        _completion: rustyline::CompletionType,
    ) -> Cow<'c, str> {
        Cow::Borrowed(candidate)
    }
}

/// Apply syntax highlighting to a single line of VQL input.
///
/// Handles quoted strings as atomic units so that keywords inside strings
/// are not incorrectly coloured.
fn highlight_line(line: &str) -> String {
    let mut result = String::with_capacity(line.len() * 2);
    let chars: Vec<char> = line.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        let ch = chars[i];

        // Handle string literals (single or double quoted).
        if ch == '\'' || ch == '"' {
            let quote = ch;
            let start = i;
            i += 1;
            while i < len && chars[i] != quote {
                if chars[i] == '\\' {
                    i += 1; // Skip escaped character.
                }
                i += 1;
            }
            if i < len {
                i += 1; // Consume closing quote.
            }
            let string_slice: String = chars[start..i].iter().collect();
            result.push_str(&string_slice.yellow().to_string());
            continue;
        }

        // Handle meta-commands (lines starting with \).
        if ch == '\\' && i == 0 {
            // Colour the entire line as a meta-command.
            let rest: String = chars[i..].iter().collect();
            result.push_str(&rest.bright_magenta().to_string());
            break;
        }

        // Handle word tokens (identifiers and keywords).
        if ch.is_alphabetic() || ch == '_' {
            let start = i;
            while i < len && (chars[i].is_alphanumeric() || chars[i] == '_') {
                i += 1;
            }
            let word: String = chars[start..i].iter().collect();
            let upper = word.to_uppercase();

            if VQL_MODALITIES.contains(&upper.as_str()) {
                result.push_str(&word.green().bold().to_string());
            } else if VQL_KEYWORDS.contains(&upper.as_str()) {
                result.push_str(&word.blue().bold().to_string());
            } else {
                result.push_str(&word);
            }
            continue;
        }

        // Handle numeric literals (integers and floats).
        if ch.is_ascii_digit() || (ch == '-' && i + 1 < len && chars[i + 1].is_ascii_digit()) {
            let start = i;
            if ch == '-' {
                i += 1;
            }
            while i < len && (chars[i].is_ascii_digit() || chars[i] == '.') {
                i += 1;
            }
            // Handle scientific notation (e.g. 1e10, 2.5E-3).
            if i < len && (chars[i] == 'e' || chars[i] == 'E') {
                i += 1;
                if i < len && (chars[i] == '+' || chars[i] == '-') {
                    i += 1;
                }
                while i < len && chars[i].is_ascii_digit() {
                    i += 1;
                }
            }
            let num: String = chars[start..i].iter().collect();
            result.push_str(&num.cyan().to_string());
            continue;
        }

        // Pass through everything else (whitespace, operators, etc.).
        result.push(ch);
        i += 1;
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_highlight_returns_something() {
        let hl = VqlHighlighter;
        let output = hl.highlight("SELECT FROM hexad", 0);
        // Just verify it does not panic and returns non-empty output.
        assert!(!output.is_empty());
    }

    #[test]
    fn test_highlight_char_always_true() {
        let hl = VqlHighlighter;
        assert!(hl.highlight_char("test", 0, rustyline::highlight::CmdKind::Other));
    }

    #[test]
    fn test_highlight_preserves_plain_text() {
        // A line with no keywords should not gain extra visible characters
        // (it may have ANSI reset codes, but the visible text should match).
        let line = "foobar baz";
        let output = highlight_line(line);
        // Strip ANSI codes and check the visible text is preserved.
        let stripped = strip_ansi(&output);
        assert_eq!(stripped, line);
    }

    #[test]
    fn test_highlight_string_literal() {
        let line = "WHERE name = 'hello'";
        let output = highlight_line(line);
        // The string 'hello' should be present in output (with ANSI codes).
        let stripped = strip_ansi(&output);
        assert!(stripped.contains("'hello'"));
    }

    #[test]
    fn test_highlight_number() {
        let line = "LIMIT 42";
        let output = highlight_line(line);
        let stripped = strip_ansi(&output);
        assert!(stripped.contains("42"));
    }

    /// Strip ANSI escape sequences from a string (for testing visible content).
    fn strip_ansi(s: &str) -> String {
        let mut result = String::new();
        let mut in_escape = false;
        for ch in s.chars() {
            if ch == '\x1b' {
                in_escape = true;
                continue;
            }
            if in_escape {
                if ch == 'm' {
                    in_escape = false;
                }
                continue;
            }
            result.push(ch);
        }
        result
    }
}
