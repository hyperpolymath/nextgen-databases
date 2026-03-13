// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * SDK Generator Main Entry Point
 *
 * Usage:
 *   deno run --allow-read --allow-write src/main.res.js <language> [output-dir]
 *
 * Languages:
 *   rescript - Generate ReScript client
 *   php      - Generate PHP client
 */

open ApiSpec

/** Deno bindings */
module Deno = {
  @val external args: array<string> = "Deno.args"

  module TextEncoder = {
    type t
    @new external make: unit => t = "TextEncoder"
    @send external encode: (t, string) => Js.TypedArray2.Uint8Array.t = "encode"
  }

  @val external writeTextFile: (string, string) => promise<unit> = "Deno.writeTextFile"
  @val external mkdir: (string, {"recursive": bool}) => promise<unit> = "Deno.mkdir"

  module Console = {
    @val external log: string => unit = "console.log"
    @val external error: string => unit = "console.error"
  }
}

/** Write generated files to disk */
let writeFiles = async (files: array<Generator.generatedFile>, outputDir: string): unit => {
  // Create output directory
  await Deno.mkdir(outputDir, {"recursive": true})

  // Write each file
  for i in 0 to Array.length(files) - 1 {
    let file = files[i]->Option.getExn
    let path = outputDir ++ "/" ++ file.path
    await Deno.writeTextFile(path, file.content)
    Deno.Console.log(`Generated: ${path}`)
  }
}

/** Main entry point */
let main = async () => {
  let args = Deno.args

  if Array.length(args) < 1 {
    Deno.Console.error("Usage: sdk-gen <language> [output-dir]")
    Deno.Console.error("Languages: rescript, php")
    %raw(`Deno.exit(1)`)
  }

  let language = args[0]->Option.getOr("rescript")
  let outputDir = args[1]->Option.getOr("./generated")

  let files = switch language {
  | "rescript" => ReScriptGen.generate(lithSpec)
  | "php" => PhpGen.generate(lithSpec)
  | other => {
      Deno.Console.error(`Unknown language: ${other}`)
      Deno.Console.error("Supported languages: rescript, php")
      %raw(`Deno.exit(1)`)
      []
    }
  }

  Deno.Console.log(`Generating ${String.length(language) > 0 ? language : "unknown"} SDK...`)
  await writeFiles(files, outputDir)
  Deno.Console.log("Done!")
}

// Run main
let _ = main()
