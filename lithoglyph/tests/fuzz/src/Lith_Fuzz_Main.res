// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Fuzz Test Entry Point
 *
 * Imports and runs all 4 fuzz targets:
 *   1. FDQL Parser
 *   2. Deep Nesting
 *   3. Unicode Handling
 *   4. Long Input
 *
 * Usage:
 *   deno run --allow-read --allow-env src/Lith_Fuzz_Main.res.js
 *   deno run --allow-read --allow-env src/Lith_Fuzz_Main.res.js --iterations 1000
 */

open Lith_Fuzz_Types
open Lith_Fuzz_FDQL
open Lith_Fuzz_Runner

/** Parse --iterations from command-line args */
let getIterations = (): int => {
  let args = Deno.args
  let idx = args->Array.findIndex(a => a == "--iterations")
  if idx >= 0 && idx + 1 < Array.length(args) {
    args->Array.get(idx + 1)->Option.flatMap(Int.fromString)->Option.getOr(10000)
  } else {
    10000
  }
}

/** Parse --seed from command-line args */
let getSeed = (): option<int> => {
  let args = Deno.args
  let idx = args->Array.findIndex(a => a == "--seed")
  if idx >= 0 && idx + 1 < Array.length(args) {
    args->Array.get(idx + 1)->Option.flatMap(Int.fromString)
  } else {
    None
  }
}

/** Main entry point */
let main = () => {
  let iterations = getIterations()
  let seed = getSeed()

  Js.Console.log("======================================")
  Js.Console.log("Lith Fuzz Test Suite")
  Js.Console.log("======================================")
  Js.Console.log(`Iterations per target: ${Int.toString(iterations)}`)

  let config: fuzzConfig = {
    ...defaultConfig,
    iterations,
    seed,
    verbose: true,
  }

  let results = runFDQLFuzz(~config)

  Js.Console.log("\n======================================")
  Js.Console.log("Summary")
  Js.Console.log("======================================")

  let totalCrashes = ref(0)
  results->Array.forEach(((name, result)) => {
    let status = if result.crashed > 0 { "FAIL" } else { "PASS" }
    Js.Console.log(`  ${status}: ${name} (${Int.toString(result.crashed)} crashes / ${Int.toString(result.iterations)} iters)`)
    totalCrashes := totalCrashes.contents + result.crashed
  })

  if totalCrashes.contents > 0 {
    Js.Console.log(`\nFAILED: ${Int.toString(totalCrashes.contents)} total crashes found`)
    Deno.exit(1)
  } else {
    Js.Console.log("\nAll fuzz targets passed without crashes")
  }
}

main()
