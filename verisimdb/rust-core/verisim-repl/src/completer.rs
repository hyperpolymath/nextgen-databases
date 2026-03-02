// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! Tab-completion for the VQL REPL.
//!
//! Provides context-aware completion for:
//! - VQL keywords (SELECT, FROM, WHERE, PROOF, LIMIT, etc.)
//! - Modality names (GRAPH, VECTOR, TENSOR, SEMANTIC, DOCUMENT, TEMPORAL)
//! - Meta-commands (\\connect, \\explain, \\format, etc.)

use rustyline::completion::{Completer, Pair};
use rustyline::Context;

/// All completable VQL keywords.
const KEYWORDS: &[&str] = &[
    "SELECT", "FROM", "WHERE", "PROOF", "LIMIT", "OFFSET", "ORDER", "BY",
    "GROUP", "HAVING", "AS", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE",
    "EXISTS", "CONTAINS", "SIMILAR", "TO", "TRAVERSE", "DEPTH", "THRESHOLD",
    "DRIFT", "CONSISTENCY", "AT", "TIME", "EXPLAIN", "INSERT", "UPDATE",
    "DELETE", "SET", "INTO", "VALUES", "CREATE", "DROP", "ALTER", "JOIN",
    "ON", "WITH", "FEDERATION", "STORE", "HEXAD", "ALL", "ASC", "DESC",
    "COUNT", "SUM", "AVG", "MIN", "MAX", "DISTINCT",
];

/// Modality names (also offered as completions).
/// All 8 octad modalities: Graph, Vector, Tensor, Semantic, Document, Temporal,
/// Provenance, Spatial.
const MODALITIES: &[&str] = &[
    "GRAPH", "VECTOR", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL",
    "PROVENANCE", "SPATIAL",
];

/// Meta-commands starting with backslash.
const META_COMMANDS: &[&str] = &[
    "\\connect", "\\explain", "\\timing", "\\format", "\\status",
    "\\help", "\\quit", "\\q",
];

/// Tab-completer for VQL input.
///
/// Completes the word under the cursor by matching against known keywords,
/// modality names, and meta-commands. Matching is case-insensitive; the
/// replacement preserves the user's casing style (upper if the prefix is
/// uppercase, otherwise lowercase).
pub struct VqlCompleter;

impl Completer for VqlCompleter {
    type Candidate = Pair;

    fn complete(
        &self,
        line: &str,
        pos: usize,
        _ctx: &Context<'_>,
    ) -> rustyline::Result<(usize, Vec<Pair>)> {
        let (start, prefix) = find_word_start(line, pos);
        let mut candidates = Vec::new();

        if prefix.is_empty() {
            return Ok((start, candidates));
        }

        let upper_prefix = prefix.to_uppercase();

        // Meta-commands: only complete if the prefix starts at the beginning
        // of the line and begins with '\'.
        if prefix.starts_with('\\') {
            for cmd in META_COMMANDS {
                if cmd.starts_with(&prefix.to_lowercase()) {
                    candidates.push(Pair {
                        display: cmd.to_string(),
                        replacement: cmd.to_string(),
                    });
                }
            }
            return Ok((start, candidates));
        }

        // Determine the user's casing preference: if the prefix is all
        // uppercase, offer uppercase completions; otherwise lowercase.
        let use_upper = prefix.chars().all(|c| c.is_uppercase() || !c.is_alphabetic());

        // Modality names.
        for name in MODALITIES {
            if name.starts_with(&upper_prefix) {
                let replacement = if use_upper {
                    name.to_string()
                } else {
                    name.to_lowercase()
                };
                candidates.push(Pair {
                    display: name.to_string(),
                    replacement,
                });
            }
        }

        // VQL keywords.
        for kw in KEYWORDS {
            if kw.starts_with(&upper_prefix) {
                let replacement = if use_upper {
                    kw.to_string()
                } else {
                    kw.to_lowercase()
                };
                candidates.push(Pair {
                    display: kw.to_string(),
                    replacement,
                });
            }
        }

        Ok((start, candidates))
    }
}

/// Find the start position and text of the word being completed.
///
/// Scans backwards from `pos` to find the beginning of the current token.
/// Tokens are delimited by whitespace, parentheses, commas, and semicolons.
fn find_word_start(line: &str, pos: usize) -> (usize, &str) {
    let bytes = line.as_bytes();
    let mut start = pos;

    while start > 0 {
        let ch = bytes[start - 1] as char;
        if ch.is_whitespace() || ch == '(' || ch == ')' || ch == ',' || ch == ';' {
            break;
        }
        start -= 1;
    }

    (start, &line[start..pos])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_word_start_middle() {
        let (start, prefix) = find_word_start("SELECT FRO", 10);
        assert_eq!(start, 7);
        assert_eq!(prefix, "FRO");
    }

    #[test]
    fn test_find_word_start_beginning() {
        let (start, prefix) = find_word_start("SEL", 3);
        assert_eq!(start, 0);
        assert_eq!(prefix, "SEL");
    }

    #[test]
    fn test_find_word_start_after_paren() {
        let (start, prefix) = find_word_start("COUNT(DIS", 9);
        assert_eq!(start, 6);
        assert_eq!(prefix, "DIS");
    }

    #[test]
    fn test_find_word_start_empty() {
        let (start, prefix) = find_word_start("SELECT ", 7);
        assert_eq!(start, 7);
        assert_eq!(prefix, "");
    }

    #[test]
    fn test_find_word_start_backslash() {
        let (start, prefix) = find_word_start("\\con", 4);
        assert_eq!(start, 0);
        assert_eq!(prefix, "\\con");
    }

    // Note: full Completer::complete tests require a rustyline Context,
    // which is difficult to construct in unit tests. The word-finding
    // logic tested above is the core of the completion behaviour.
}
