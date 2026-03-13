// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith FDQL Fuzz Targets
 *
 * Fuzz testing targets for the FDQL parser
 */

open Lith_Fuzz_Types
open Lith_Fuzz_Runner

/** Mock FDQL parser for fuzz testing
 * In production, this would call the actual parser
 */
let parseFDQL = (input: string): result<string, string> => {
  // Basic syntax validation (simplified parser simulation)
  let trimmed = String.trim(input)

  if String.length(trimmed) == 0 {
    Error("Empty input")
  } else {
    // Check for balanced quotes
    let quoteCount = ref(0)
    String.split(trimmed, "")->Array.forEach(c => {
      if c == "\"" {
        quoteCount := quoteCount.contents + 1
      }
    })
    if mod(quoteCount.contents, 2) != 0 {
      Error("Unbalanced quotes")
    } else {
      // Check for balanced braces
      let braceCount = ref(0)
      String.split(trimmed, "")->Array.forEach(c => {
        if c == "{" {
          braceCount := braceCount.contents + 1
        }
        if c == "}" {
          braceCount := braceCount.contents - 1
        }
      })
      if braceCount.contents != 0 {
        Error("Unbalanced braces")
      } else {
        // Check for balanced brackets
        let bracketCount = ref(0)
        String.split(trimmed, "")->Array.forEach(c => {
          if c == "[" {
            bracketCount := bracketCount.contents + 1
          }
          if c == "]" {
            bracketCount := bracketCount.contents - 1
          }
        })
        if bracketCount.contents != 0 {
          Error("Unbalanced brackets")
        } else {
          // Check for valid starting keyword
          let upper = String.toUpperCase(trimmed)
          let validStarts = ["SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "EXPLAIN", "INTROSPECT", "TRAVERSE"]
          let hasValidStart = validStarts->Array.some(kw => String.startsWith(upper, kw))

          if hasValidStart {
            Ok("Parsed successfully")
          } else {
            Error("Invalid statement: must start with valid keyword")
          }
        }
      }
    }
  }
}

/** Fuzz target for FDQL parser */
let fdqlParserTarget: fuzzTarget = (input: string): fuzzInputResult => {
  try {
    switch parseFDQL(input) {
    | Ok(_) => Accepted
    | Error(_) => Rejected
    }
  } catch {
  | Js.Exn.Error(e) => {
      let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
      // Check if this is an expected error or a crash
      if String.includes(msg, "RangeError") || String.includes(msg, "Maximum call stack") {
        Crashed({error: msg})
      } else {
        Rejected
      }
    }
  | _ => Crashed({error: "Unknown exception"})
  }
}

/** Fuzz target for deep nesting (potential stack overflow) */
let deepNestingTarget: fuzzTarget = (input: string): fuzzInputResult => {
  // Count nesting depth
  let depth = ref(0)
  let maxDepth = ref(0)
  String.split(input, "")->Array.forEach(c => {
    if c == "{" || c == "[" || c == "(" {
      depth := depth.contents + 1
      if depth.contents > maxDepth.contents {
        maxDepth := depth.contents
      }
    }
    if c == "}" || c == "]" || c == ")" {
      depth := depth.contents - 1
    }
  })

  // Flag extremely deep nesting as interesting
  if maxDepth.contents > 100 {
    Interesting({reason: `Deep nesting: ${Int.toString(maxDepth.contents)} levels`})
  } else {
    fdqlParserTarget(input)
  }
}

/** Fuzz target for unicode handling */
let unicodeTarget: fuzzTarget = (input: string): fuzzInputResult => {
  // Check for non-ASCII characters
  let hasNonAscii = ref(false)
  String.split(input, "")->Array.forEach(c => {
    if String.charCodeAt(c, 0) > 127.0 {
      hasNonAscii := true
    }
  })

  if hasNonAscii.contents {
    // Try parsing and flag if accepted
    switch parseFDQL(input) {
    | Ok(_) => Interesting({reason: "Unicode input accepted"})
    | Error(_) => Rejected
    }
  } else {
    fdqlParserTarget(input)
  }
}

/** Fuzz target for long inputs */
let longInputTarget: fuzzTarget = (input: string): fuzzInputResult => {
  let len = String.length(input)

  // Flag very long inputs
  if len > 10000 {
    Interesting({reason: `Very long input: ${Int.toString(len)} chars`})
  } else {
    fdqlParserTarget(input)
  }
}

/** Run all FDQL fuzz targets */
let runFDQLFuzz = (~config: fuzzConfig=defaultConfig): array<(string, fuzzResult)> => {
  let targets = [
    ("FDQL Parser", fdqlParserTarget),
    ("Deep Nesting", deepNestingTarget),
    ("Unicode Handling", unicodeTarget),
    ("Long Input", longInputTarget),
  ]

  targets->Array.map(((name, target)) => {
    Js.Console.log(`\nFuzzing: ${name}`)
    let result = runFuzz(~config, ~target)
    printResults(result)
    (name, result)
  })
}

/** Default export */
let default = () => runFDQLFuzz()
