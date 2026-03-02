// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL formatter — canonical formatting for queries.

/// Clause-starting keywords that get their own line.
let clauseStarters = [
  "SELECT", "FROM", "WHERE", "ORDER", "GROUP", "HAVING", "LIMIT",
  "OFFSET", "JOIN", "ON", "WITH", "SET", "INTO", "VALUES",
  "TRAVERSE", "PROOF", "EXPLAIN",
]

let formatVql = (query: string): string => {
  let upper = String.toUpperCase
  let tokens =
    Js.String2.splitByRe(query, %re("/(\s+|'[^']*'|\"[^\"]*\")/"))
    ->Array.filterMap(t => t)
    ->Array.filter(t => String.trim(t) !== "")

  let result = ref("")
  let isFirst = ref(true)

  tokens->Array.forEach(token => {
    let trimmed = String.trim(token)
    if trimmed === "" {
      // Whitespace — will be normalized
      if !(String.endsWith(result.contents, " ") || String.endsWith(result.contents, "\n")) {
        result := result.contents ++ " "
      }
    } else if String.startsWith(trimmed, "'") || String.startsWith(trimmed, "\"") {
      // String literal — preserve as-is
      result := result.contents ++ trimmed
    } else {
      let word = upper(trimmed)
      let formatted = if VqlKeywords.isKeyword(word) || VqlKeywords.isModality(word) {
        word
      } else {
        trimmed
      }

      if clauseStarters->Array.includes(word) && !isFirst.contents {
        // Remove trailing space
        if String.endsWith(result.contents, " ") {
          result := String.slice(result.contents, ~start=0, ~end=String.length(result.contents) - 1)
        }
        // Check EXPLAIN + SELECT same line
        if word === "SELECT" && String.endsWith(String.trim(result.contents), "EXPLAIN") {
          result := result.contents ++ " " ++ formatted
        } else {
          result := result.contents ++ "\n" ++ formatted
        }
      } else if word === "AND" || word === "OR" {
        if String.endsWith(result.contents, " ") {
          result := String.slice(result.contents, ~start=0, ~end=String.length(result.contents) - 1)
        }
        result := result.contents ++ "\n  " ++ formatted
      } else {
        if !(String.endsWith(result.contents, " ") || String.endsWith(result.contents, "\n") || result.contents === "") {
          result := result.contents ++ " "
        }
        result := result.contents ++ formatted
      }

      isFirst := false
    }
  })

  String.trim(result.contents)
}
