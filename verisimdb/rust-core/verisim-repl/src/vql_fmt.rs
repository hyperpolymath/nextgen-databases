// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! VQL query formatter.
//!
//! Provides canonical formatting for VQL queries:
//! - Keywords uppercased
//! - Consistent indentation for clauses
//! - Normalized whitespace
//! - Aligned modality lists

/// VQL keywords that should be uppercased.
const VQL_KEYWORDS: &[&str] = &[
    "SELECT", "FROM", "WHERE", "PROOF", "LIMIT", "OFFSET", "ORDER", "BY",
    "GROUP", "HAVING", "AS", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE",
    "EXISTS", "CONTAINS", "SIMILAR", "TO", "TRAVERSE", "DEPTH", "THRESHOLD",
    "DRIFT", "CONSISTENCY", "AT", "TIME", "EXPLAIN", "INSERT", "UPDATE",
    "DELETE", "SET", "INTO", "VALUES", "CREATE", "DROP", "ALTER", "JOIN",
    "ON", "WITH", "FEDERATION", "STORE", "HEXAD", "ALL", "ASC", "DESC",
    "COUNT", "SUM", "AVG", "MIN", "MAX", "DISTINCT", "ANALYZE",
];

/// VQL modality names that should be uppercased.
/// All 8 octad modalities: Graph, Vector, Tensor, Semantic, Document, Temporal,
/// Provenance, Spatial.
const VQL_MODALITIES: &[&str] = &[
    "GRAPH", "VECTOR", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL",
    "PROVENANCE", "SPATIAL",
];

/// Keywords that start a new major clause (indented on a new line).
const CLAUSE_STARTERS: &[&str] = &[
    "SELECT", "FROM", "WHERE", "ORDER", "GROUP", "HAVING", "LIMIT",
    "OFFSET", "JOIN", "ON", "WITH", "SET", "INTO", "VALUES",
    "TRAVERSE", "PROOF", "EXPLAIN",
];

/// Format a VQL query string into canonical form.
///
/// Applies:
/// 1. Keyword uppercasing
/// 2. Modality name uppercasing
/// 3. Clause-level newlines and indentation
/// 4. Whitespace normalization
/// 5. String literal preservation
pub fn format_vql(query: &str) -> String {
    let tokens = tokenize(query);
    let formatted_tokens = uppercase_keywords(&tokens);
    let indented = indent_clauses(&formatted_tokens);
    normalize_whitespace(&indented)
}

/// Compact format — normalize whitespace and case without indentation.
pub fn format_vql_compact(query: &str) -> String {
    let tokens = tokenize(query);
    let formatted = uppercase_keywords(&tokens);
    let mut result = String::with_capacity(query.len());
    let mut prev_was_space = false;

    for token in &formatted {
        match token {
            Token::Whitespace => {
                if !prev_was_space && !result.is_empty() {
                    result.push(' ');
                    prev_was_space = true;
                }
            }
            Token::Word(w) | Token::Keyword(w) | Token::Modality(w) => {
                result.push_str(w);
                prev_was_space = false;
            }
            Token::StringLiteral(s) => {
                result.push_str(s);
                prev_was_space = false;
            }
            Token::Number(n) => {
                result.push_str(n);
                prev_was_space = false;
            }
            Token::Punctuation(c) => {
                // No space before comma/semicolon, space after
                if *c == ',' || *c == ';' {
                    // Remove trailing space before punctuation
                    if result.ends_with(' ') {
                        result.pop();
                    }
                    result.push(*c);
                    result.push(' ');
                    prev_was_space = true;
                } else {
                    result.push(*c);
                    prev_was_space = false;
                }
            }
        }
    }

    result.trim().to_string()
}

/// Token types in VQL input.
#[derive(Debug, Clone, PartialEq)]
enum Token {
    Keyword(String),
    Modality(String),
    Word(String),
    StringLiteral(String),
    Number(String),
    Whitespace,
    Punctuation(char),
}

/// Tokenize VQL input into a sequence of tokens.
///
/// Preserves string literals as atomic units.
fn tokenize(input: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = input.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        let ch = chars[i];

        // String literals (single or double quoted)
        if ch == '\'' || ch == '"' {
            let quote = ch;
            let start = i;
            i += 1;
            while i < len && chars[i] != quote {
                if chars[i] == '\\' {
                    i += 1;
                }
                i += 1;
            }
            if i < len {
                i += 1; // closing quote
            }
            let s: String = chars[start..i].iter().collect();
            tokens.push(Token::StringLiteral(s));
            continue;
        }

        // Whitespace
        if ch.is_whitespace() {
            while i < len && chars[i].is_whitespace() {
                i += 1;
            }
            tokens.push(Token::Whitespace);
            continue;
        }

        // Word tokens
        if ch.is_alphabetic() || ch == '_' {
            let start = i;
            while i < len && (chars[i].is_alphanumeric() || chars[i] == '_') {
                i += 1;
            }
            let word: String = chars[start..i].iter().collect();
            tokens.push(Token::Word(word));
            continue;
        }

        // Numbers
        if ch.is_ascii_digit() || (ch == '-' && i + 1 < len && chars[i + 1].is_ascii_digit()) {
            let start = i;
            if ch == '-' {
                i += 1;
            }
            while i < len && (chars[i].is_ascii_digit() || chars[i] == '.') {
                i += 1;
            }
            // Scientific notation
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
            tokens.push(Token::Number(num));
            continue;
        }

        // Operators and punctuation
        tokens.push(Token::Punctuation(ch));
        i += 1;
    }

    tokens
}

/// Uppercase keywords and modalities in the token stream.
fn uppercase_keywords(tokens: &[Token]) -> Vec<Token> {
    tokens
        .iter()
        .map(|t| match t {
            Token::Word(w) => {
                let upper = w.to_uppercase();
                if VQL_KEYWORDS.contains(&upper.as_str()) {
                    Token::Keyword(upper)
                } else if VQL_MODALITIES.contains(&upper.as_str()) {
                    Token::Modality(upper)
                } else {
                    Token::Word(w.clone())
                }
            }
            other => other.clone(),
        })
        .collect()
}

/// Insert newlines and indentation before major clause keywords.
fn indent_clauses(tokens: &[Token]) -> Vec<Token> {
    let mut result = Vec::with_capacity(tokens.len());
    let mut is_first_keyword = true;

    for (i, token) in tokens.iter().enumerate() {
        match token {
            Token::Keyword(kw) if CLAUSE_STARTERS.contains(&kw.as_str()) => {
                if is_first_keyword {
                    is_first_keyword = false;
                    result.push(token.clone());
                } else {
                    // Remove trailing whitespace before clause
                    while matches!(result.last(), Some(Token::Whitespace)) {
                        result.pop();
                    }
                    // Check if previous keyword is EXPLAIN and this is SELECT
                    let prev_is_explain = i > 0
                        && matches!(&tokens[i.saturating_sub(2)..i],
                            [Token::Keyword(k), ..] if k == "EXPLAIN");
                    if prev_is_explain && kw == "SELECT" {
                        result.push(Token::Whitespace);
                        result.push(token.clone());
                    } else {
                        // Newline before clause
                        result.push(Token::Punctuation('\n'));
                        result.push(token.clone());
                    }
                }
            }
            // Sub-clause keywords (AND, OR) get indentation
            Token::Keyword(kw) if kw == "AND" || kw == "OR" => {
                while matches!(result.last(), Some(Token::Whitespace)) {
                    result.pop();
                }
                result.push(Token::Punctuation('\n'));
                result.push(Token::Word("  ".to_string())); // indent
                result.push(token.clone());
            }
            _ => {
                result.push(token.clone());
            }
        }
    }

    result
}

/// Normalize whitespace: collapse runs, trim trailing.
fn normalize_whitespace(tokens: &[Token]) -> String {
    let mut result = String::new();

    for token in tokens {
        match token {
            Token::Whitespace => {
                if !result.is_empty() && !result.ends_with('\n') && !result.ends_with(' ') {
                    result.push(' ');
                }
            }
            Token::Keyword(w) | Token::Modality(w) | Token::Word(w) => {
                result.push_str(w);
            }
            Token::StringLiteral(s) => {
                result.push_str(s);
            }
            Token::Number(n) => {
                result.push_str(n);
            }
            Token::Punctuation('\n') => {
                // Trim trailing space before newline
                while result.ends_with(' ') {
                    result.pop();
                }
                result.push('\n');
            }
            Token::Punctuation(c) => {
                result.push(*c);
            }
        }
    }

    result.trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keyword_uppercasing() {
        let input = "select graph from hexad where id = 'abc'";
        let output = format_vql(input);
        assert!(output.contains("SELECT"));
        assert!(output.contains("GRAPH"));
        assert!(output.contains("FROM"));
        assert!(output.contains("HEXAD"));
        assert!(output.contains("WHERE"));
    }

    #[test]
    fn test_modality_uppercasing() {
        let input = "select vector, tensor from hexad";
        let output = format_vql(input);
        assert!(output.contains("VECTOR"));
        assert!(output.contains("TENSOR"));
    }

    #[test]
    fn test_string_literals_preserved() {
        let input = "select graph from hexad where name = 'hello world'";
        let output = format_vql(input);
        assert!(output.contains("'hello world'"));
    }

    #[test]
    fn test_clause_newlines() {
        let input = "SELECT GRAPH FROM HEXAD WHERE id = 'abc' LIMIT 10";
        let output = format_vql(input);
        // FROM should be on a new line
        assert!(output.contains("\nFROM"));
        // WHERE should be on a new line
        assert!(output.contains("\nWHERE"));
        // LIMIT should be on a new line
        assert!(output.contains("\nLIMIT"));
    }

    #[test]
    fn test_and_or_indentation() {
        let input = "SELECT GRAPH FROM HEXAD WHERE a = 1 AND b = 2 OR c = 3";
        let output = format_vql(input);
        assert!(output.contains("\n  AND"));
        assert!(output.contains("\n  OR"));
    }

    #[test]
    fn test_compact_format() {
        let input = "  select   graph   from   hexad  ";
        let output = format_vql_compact(input);
        assert_eq!(output, "SELECT GRAPH FROM HEXAD");
    }

    #[test]
    fn test_whitespace_normalization() {
        let input = "SELECT    GRAPH    FROM     HEXAD";
        let compact = format_vql_compact(input);
        assert_eq!(compact, "SELECT GRAPH FROM HEXAD");
    }

    #[test]
    fn test_number_preservation() {
        let input = "select graph from hexad limit 42 offset 10";
        let output = format_vql(input);
        assert!(output.contains("42"));
        assert!(output.contains("10"));
    }

    #[test]
    fn test_mixed_case_keywords() {
        let input = "Select Graph From Hexad Where Id = 'test'";
        let output = format_vql(input);
        assert!(output.contains("SELECT"));
        assert!(output.contains("GRAPH"));
        assert!(output.contains("FROM"));
        assert!(output.contains("HEXAD"));
        assert!(output.contains("WHERE"));
    }

    #[test]
    fn test_non_keyword_preserved() {
        let input = "SELECT graph FROM hexad WHERE entity_name = 'test'";
        let output = format_vql(input);
        assert!(output.contains("entity_name"));
    }

    #[test]
    fn test_explain_select_same_line() {
        let input = "explain select graph from hexad";
        let output = format_vql(input);
        // EXPLAIN and SELECT should stay on the same line
        let first_line = output.lines().next().unwrap();
        assert!(first_line.contains("EXPLAIN"));
        assert!(first_line.contains("SELECT"));
    }

    #[test]
    fn test_empty_input() {
        assert_eq!(format_vql(""), "");
        assert_eq!(format_vql_compact(""), "");
    }

    #[test]
    fn test_tokenize_string_with_escape() {
        let input = r#"WHERE name = 'it\'s a test'"#;
        let tokens = tokenize(input);
        let string_tokens: Vec<_> = tokens
            .iter()
            .filter(|t| matches!(t, Token::StringLiteral(_)))
            .collect();
        assert_eq!(string_tokens.len(), 1);
    }

    #[test]
    fn test_traverse_depth_formatting() {
        let input = "select graph from hexad traverse relates_to depth 3";
        let output = format_vql(input);
        assert!(output.contains("TRAVERSE"));
        assert!(output.contains("DEPTH"));
        assert!(output.contains("3"));
    }

    #[test]
    fn test_proof_clause_formatting() {
        let input = "select semantic from hexad proof existence threshold 0.95";
        let output = format_vql(input);
        assert!(output.contains("SEMANTIC"));
        assert!(output.contains("PROOF"));
        assert!(output.contains("THRESHOLD"));
        assert!(output.contains("0.95"));
    }

    #[test]
    fn test_comma_spacing() {
        let input = "select graph , vector , tensor from hexad";
        let compact = format_vql_compact(input);
        assert!(compact.contains("GRAPH, VECTOR, TENSOR"));
    }

    #[test]
    fn test_federation_formatting() {
        let input = "select graph from federation store 'remote-1' hexad";
        let output = format_vql(input);
        assert!(output.contains("FEDERATION"));
        assert!(output.contains("STORE"));
        assert!(output.contains("'remote-1'"));
    }

    #[test]
    fn test_roundtrip_idempotent() {
        let input = "SELECT GRAPH\nFROM HEXAD\nWHERE id = 'abc'\nLIMIT 10";
        let first = format_vql(input);
        let second = format_vql(&first);
        assert_eq!(first, second, "Formatting should be idempotent");
    }
}
