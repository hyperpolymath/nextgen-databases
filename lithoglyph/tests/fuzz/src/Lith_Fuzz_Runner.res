// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Fuzz Test Runner
 *
 * Main fuzzing loop and result tracking
 */

open Lith_Fuzz_Types
open Lith_Fuzz_Mutators

/** Fuzz target function type */
type fuzzTarget = string => fuzzInputResult

/** Seed corpus - valid FDQL statements */
let seedCorpus: array<string> = [
  "SELECT * FROM users",
  "SELECT id, name FROM posts WHERE status = \"published\"",
  "SELECT * FROM articles LIMIT 10",
  "INSERT INTO users {\"name\": \"test\", \"email\": \"test@example.com\"}",
  "UPDATE posts SET {\"status\": \"draft\"} WHERE id = 123",
  "DELETE FROM comments WHERE spam = true",
  "CREATE COLLECTION products",
  "CREATE EDGE COLLECTION follows",
  "DROP COLLECTION temp",
  "EXPLAIN SELECT * FROM users WHERE active = true",
  "EXPLAIN ANALYZE SELECT * FROM posts LIMIT 100",
  "EXPLAIN VERBOSE SELECT id FROM articles",
  "INTROSPECT SCHEMA users",
  "INTROSPECT CONSTRAINTS posts",
  "INTROSPECT COLLECTIONS",
  "INTROSPECT JOURNAL",
  "SELECT * FROM users WHERE age > 18 AND status = \"active\"",
  "SELECT * FROM posts WHERE category IN [\"tech\", \"science\"]",
  "SELECT title, content FROM articles WHERE title LIKE \"%test%\"",
  "TRAVERSE OUTBOUND users/123 follows",
]

/** Run fuzzing session */
let runFuzz = (
  ~config: fuzzConfig=defaultConfig,
  ~target: fuzzTarget,
): fuzzResult => {
  let seed = config.seed->Option.getOr(Int.fromFloat(Js.Date.now()))
  let rng = makeRng(seed)

  let startTime = Js.Date.now()

  // Initialize corpus with seeds
  let corpus = seedCorpus->Array.copy

  // Track results
  let accepted = ref(0)
  let rejected = ref(0)
  let crashed = ref(0)
  let timeout = ref(0)
  let interesting = ref(0)
  let crashingInputs: array<string> = []
  let interestingInputs: array<(string, string)> = []

  if config.verbose {
    Js.Console.log(`Starting fuzz session`)
    Js.Console.log(`  Seed: ${Int.toString(seed)}`)
    Js.Console.log(`  Iterations: ${Int.toString(config.iterations)}`)
    Js.Console.log(`  Corpus size: ${Int.toString(Array.length(corpus))}`)
  }

  // Main fuzzing loop
  for i in 1 to config.iterations {
    // Generate or mutate input
    let input = if intInRange(rng, ~min=0, ~max=100) < 10 {
      // 10% chance of completely random input
      generateRandom(rng, config.maxInputLength)
    } else {
      // 90% chance of mutating corpus
      let base = pick(rng, corpus)->Option.getOr("SELECT * FROM test")
      mutateRandom(rng, base, corpus)
    }

    // Run target
    let result = target(input)

    // Track result
    switch result {
    | Accepted => {
        accepted := accepted.contents + 1
        // Add to corpus if new and interesting
        if !(corpus->Array.includes(input)) && String.length(input) < config.maxInputLength {
          corpus->Array.push(input)->ignore
        }
      }
    | Rejected => rejected := rejected.contents + 1
    | Crashed({error}) => {
        crashed := crashed.contents + 1
        crashingInputs->Array.push(input)->ignore
        if config.verbose {
          Js.Console.log(`[${Int.toString(i)}] CRASH: ${error}`)
          Js.Console.log(`  Input: ${input}`)
        }
      }
    | Timeout => timeout := timeout.contents + 1
    | Interesting({reason}) => {
        interesting := interesting.contents + 1
        interestingInputs->Array.push((input, reason))->ignore
        if config.verbose {
          Js.Console.log(`[${Int.toString(i)}] INTERESTING: ${reason}`)
        }
      }
    }

    // Progress update
    if config.verbose && mod(i, 1000) == 0 {
      Js.Console.log(`[${Int.toString(i)}/${Int.toString(config.iterations)}] corpus=${Int.toString(Array.length(corpus))}`)
    }
  }

  let endTime = Js.Date.now()
  let duration = (endTime -. startTime) /. 1000.0

  {
    iterations: config.iterations,
    accepted: accepted.contents,
    rejected: rejected.contents,
    crashed: crashed.contents,
    timeout: timeout.contents,
    interesting: interesting.contents,
    crashingInputs,
    interestingInputs,
    duration,
  }
}

/** Print fuzz results */
let printResults = (result: fuzzResult): unit => {
  Js.Console.log("\n=== Fuzz Test Results ===\n")
  Js.Console.log(`Iterations: ${Int.toString(result.iterations)}`)
  Js.Console.log(`Duration: ${Float.toFixedWithPrecision(result.duration, ~digits=2)}s`)
  Js.Console.log(`Rate: ${Float.toFixedWithPrecision(Float.fromInt(result.iterations) /. result.duration, ~digits=0)} iter/s`)
  Js.Console.log("")
  Js.Console.log(`Accepted: ${Int.toString(result.accepted)}`)
  Js.Console.log(`Rejected: ${Int.toString(result.rejected)}`)
  Js.Console.log(`Crashed: ${Int.toString(result.crashed)}`)
  Js.Console.log(`Timeout: ${Int.toString(result.timeout)}`)
  Js.Console.log(`Interesting: ${Int.toString(result.interesting)}`)

  if Array.length(result.crashingInputs) > 0 {
    Js.Console.log("\n=== Crashing Inputs ===")
    result.crashingInputs->Array.forEachWithIndex((input, i) => {
      Js.Console.log(`\n[${Int.toString(i + 1)}] ${input}`)
    })
  }

  if Array.length(result.interestingInputs) > 0 {
    Js.Console.log("\n=== Interesting Inputs ===")
    result.interestingInputs->Array.forEachWithIndex(((input, reason), i) => {
      Js.Console.log(`\n[${Int.toString(i + 1)}] ${reason}`)
      Js.Console.log(`    ${input}`)
    })
  }
}

/** Check if fuzz run found bugs */
let hasBugs = (result: fuzzResult): bool => {
  result.crashed > 0
}
