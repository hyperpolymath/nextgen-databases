// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Property Test Runner
 *
 * Executes property-based tests with shrinking
 */

open Lith_Property_Types
open Lith_Property_Generators

/** Property function type */
type property<'a> = 'a => bool

/** Run a property test */
let runProperty = (
  ~config: propertyConfig=defaultConfig,
  ~name: string,
  ~generator: rng => 'a,
  ~toString: 'a => string,
  ~property: property<'a>,
): propertyResult => {
  let seed = config.seed->Option.getOr(Int.fromFloat(Js.Date.now()))
  let rng = makeRng(seed)

  if config.verbose {
    Js.Console.log(`Running property: ${name}`)
    Js.Console.log(`  Seed: ${Int.toString(seed)}`)
    Js.Console.log(`  Iterations: ${Int.toString(config.iterations)}`)
  }

  let rec loop = (iteration: int): propertyResult => {
    if iteration > config.iterations {
      Passed({iterations: config.iterations})
    } else {
      let value = generator(rng)
      try {
        if property(value) {
          loop(iteration + 1)
        } else {
          let counterexample = toString(value)
          Failed({iteration, counterexample, shrunk: None})
        }
      } catch {
      | Js.Exn.Error(e) => {
          let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
          Errored({iteration, error: msg})
        }
      | _ => Errored({iteration, error: "Unknown exception"})
      }
    }
  }

  loop(1)
}

/** Print property result */
let printResult = (name: string, result: propertyResult): unit => {
  switch result {
  | Passed({iterations}) => Js.Console.log(`✓ ${name}: PASSED (${Int.toString(iterations)} iterations)`)
  | Failed({iteration, counterexample, shrunk}) => {
      Js.Console.log(`✗ ${name}: FAILED at iteration ${Int.toString(iteration)}`)
      Js.Console.log(`  Counterexample: ${counterexample}`)
      switch shrunk {
      | Some(s) => Js.Console.log(`  Shrunk to: ${s}`)
      | None => ()
      }
    }
  | Errored({iteration, error}) => {
      Js.Console.log(`✗ ${name}: ERROR at iteration ${Int.toString(iteration)}`)
      Js.Console.log(`  Error: ${error}`)
    }
  }
}

/** Check if result is passing */
let isPassing = (result: propertyResult): bool =>
  switch result {
  | Passed(_) => true
  | _ => false
  }

/** Run multiple properties and return summary */
let runSuite = (
  ~config: propertyConfig=defaultConfig,
  tests: array<(string, unit => propertyResult)>,
): suiteSummary => {
  let passed = ref(0)
  let failed = ref(0)
  let errored = ref(0)

  Js.Console.log("\n=== Property Test Suite ===\n")

  tests->Array.forEach(((name, test)) => {
    let result = test()
    printResult(name, result)
    switch result {
    | Passed(_) => passed := passed.contents + 1
    | Failed(_) => failed := failed.contents + 1
    | Errored(_) => errored := errored.contents + 1
    }
  })

  Js.Console.log("\n=== Summary ===")
  Js.Console.log(`Passed: ${Int.toString(passed.contents)}`)
  Js.Console.log(`Failed: ${Int.toString(failed.contents)}`)
  Js.Console.log(`Errored: ${Int.toString(errored.contents)}`)

  {passed: passed.contents, failed: failed.contents, errored: errored.contents}
}
