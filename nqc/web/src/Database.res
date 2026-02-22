// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Database profile registry for NQC Web UI.
Mirrors the Gleam `DatabaseProfile` type from `src/nqc/database.gleam` exactly,
ensuring the web UI and CLI REPL share identical profile definitions.
Each profile describes connection parameters, query language metadata,
and keyword lists for a NextGen database engine.
")

// ============================================================================
// Profile type — one-to-one with the Gleam DatabaseProfile record
// ============================================================================

@ocaml.doc("
A database profile defines everything needed to connect to and interact with
a NextGen database engine.  The `id` is the canonical short identifier used
in URLs and profile lookups. `languageName` is the query language acronym
(VQL, GQL, KQL) while `displayName` is the human-friendly engine name.
")
type profile = {
  id: string,
  displayName: string,
  languageName: string,
  description: string,
  aliases: array<string>,
  defaultHost: string,
  defaultPort: int,
  executePath: string,
  healthPath: string,
  prompt: string,
  supportsDt: bool,
  keywords: array<string>,
}

// ============================================================================
// Built-in profiles — VeriSimDB, Lithoglyph, QuandleDB
// ============================================================================

@ocaml.doc("
VeriSimDB (VQL) — 6-core multimodal database with self-normalization.
Handles text, vector, graph, tensor, semantic, document, and temporal data
within a single hexad-based storage model.  Supports dependent-type
verification of query results via PROOF/WITNESS/VERIFY keywords.
")
let vql: profile = {
  id: "vql",
  displayName: "VeriSimDB",
  languageName: "VQL",
  description: "6-core multimodal database with self-normalization",
  aliases: ["verisimdb", "verisim"],
  defaultHost: "localhost",
  defaultPort: 8080,
  executePath: "/vql/execute",
  healthPath: "/health",
  prompt: "vql> ",
  supportsDt: true,
  keywords: [
    "SELECT", "FROM", "WHERE", "LIMIT", "INSERT", "INTO", "VALUES",
    "DELETE", "SEARCH", "TEXT", "VECTOR", "RELATED", "BY", "SHOW",
    "STATUS", "DRIFT", "NORMALIZER", "HEXADS", "COUNT", "EXPLAIN",
    "GRAPH", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL", "HEXAD",
    "PROOF", "WITNESS", "VERIFY",
  ],
}

@ocaml.doc("
Lithoglyph (GQL) — graph database with formal verification.
Operates on vertices, edges, and paths with pattern matching syntax
inspired by ISO GQL / openCypher.  Adds algebraic primitives (morphism,
functor) and proof-carrying results.
")
let gql: profile = {
  id: "gql",
  displayName: "Lithoglyph",
  languageName: "GQL",
  description: "Graph database with formal verification",
  aliases: ["lithoglyph", "formdb"],
  defaultHost: "localhost",
  defaultPort: 8081,
  executePath: "/gql/execute",
  healthPath: "/health",
  prompt: "gql> ",
  supportsDt: true,
  keywords: [
    "MATCH", "CREATE", "DELETE", "SET", "RETURN", "WHERE", "AND", "OR",
    "NOT", "WITH", "UNWIND", "ORDER", "BY", "LIMIT", "SKIP", "VERTEX",
    "EDGE", "PATH", "SHORTEST", "PATTERN", "PROPERTIES", "LABELS",
    "PROOF", "WITNESS", "VERIFY", "MORPHISM", "FUNCTOR",
  ],
}

@ocaml.doc("
QuandleDB (KQL) — knot-theoretic structural equivalence database.
Stores and queries algebraic structures (quandles, racks, braids) with
knot invariant computation (Jones, Alexander, HOMFLY polynomials).
Query language operates via deformation, classification, and equivalence
rather than traditional CRUD.
")
let kql: profile = {
  id: "kql",
  displayName: "QuandleDB",
  languageName: "KQL",
  description: "Knot-theoretic structural equivalence database",
  aliases: ["quandledb", "quandle"],
  defaultHost: "localhost",
  defaultPort: 8082,
  executePath: "/kql/execute",
  healthPath: "/health",
  prompt: "kql> ",
  supportsDt: true,
  keywords: [
    "DEFORM", "CLASSIFY", "CONNECT", "DISTINGUISH", "TRANSFORM",
    "WITNESS", "UNDER", "REIDEMEISTER", "ISOTOPY", "INVARIANT",
    "CROSSING", "KNOT", "LINK", "BRAID", "QUANDLE", "RACK",
    "JONES", "ALEXANDER", "HOMFLY", "BRACKET", "WRITHE",
    "PROOF", "VERIFY", "EQUIVALENT",
  ],
}

// ============================================================================
// Registry — all known profiles + lookup helpers
// ============================================================================

@ocaml.doc("
All built-in database profiles.  The array ordering determines the
display order in the Picker page card grid.
")
let builtins: array<profile> = [vql, gql, kql]

@ocaml.doc("
Mutable storage for user-defined custom profiles loaded at runtime.
Populated by `loadCustomProfiles` from the `/nqc-profiles.json` config file.
Falls back to empty if the file doesn't exist or fails to parse.
")
let customs: ref<array<profile>> = ref([])

@ocaml.doc("
All known profiles: builtins first, then any custom additions.
This is a function rather than a static binding so it always reflects
the latest custom profiles after runtime loading.
")
let all = (): array<profile> => Array.concat(builtins, customs.contents)

// ============================================================================
// Custom profile JSON decoder
// ============================================================================

@ocaml.doc("
Decode a JSON object into a database profile.
Expects the same field names as the Gleam `profiles.json` format:
```json
{
  \"id\": \"mydb\",
  \"displayName\": \"My Database\",
  \"languageName\": \"MQL\",
  \"description\": \"...\",
  \"aliases\": [\"mydb\", \"my\"],
  \"defaultHost\": \"localhost\",
  \"defaultPort\": 9090,
  \"executePath\": \"/mql/execute\",
  \"healthPath\": \"/health\",
  \"prompt\": \"mql> \",
  \"supportsDt\": false,
  \"keywords\": [\"SELECT\", \"FROM\"]
}
```
Returns `None` for any object that is missing required fields.
")
let decodeProfile = (json: JSON.t): option<profile> => {
  switch JSON.Classify.classify(json) {
  | Object(dict) => {
      // Helper: extract a required string field
      let getString = (key: string): option<string> =>
        switch Dict.get(dict, key) {
        | Some(v) =>
          switch JSON.Classify.classify(v) {
          | String(s) => Some(s)
          | Bool(_) | Null | Number(_) | Object(_) | Array(_) => None
          }
        | None => None
        }

      // Helper: extract a required int field
      let getInt = (key: string): option<int> =>
        switch Dict.get(dict, key) {
        | Some(v) =>
          switch JSON.Classify.classify(v) {
          | Number(n) => Some(Float.toInt(n))
          | Bool(_) | Null | String(_) | Object(_) | Array(_) => None
          }
        | None => None
        }

      // Helper: extract a required bool field (defaults to false)
      let getBool = (key: string): bool =>
        switch Dict.get(dict, key) {
        | Some(v) =>
          switch JSON.Classify.classify(v) {
          | Bool(b) => b
          | Null | String(_) | Number(_) | Object(_) | Array(_) => false
          }
        | None => false
        }

      // Helper: extract a string array field (defaults to empty)
      let getStringArray = (key: string): array<string> =>
        switch Dict.get(dict, key) {
        | Some(v) =>
          switch JSON.Classify.classify(v) {
          | Array(arr) =>
            arr->Array.filterMap(item =>
              switch JSON.Classify.classify(item) {
              | String(s) => Some(s)
              | Bool(_) | Null | Number(_) | Object(_) | Array(_) => None
              }
            )
          | Bool(_) | Null | String(_) | Number(_) | Object(_) => []
          }
        | None => []
        }

      // All required fields must be present
      switch (
        getString("id"),
        getString("displayName"),
        getString("languageName"),
        getString("description"),
        getInt("defaultPort"),
        getString("executePath"),
        getString("healthPath"),
        getString("prompt"),
      ) {
      | (
          Some(id),
          Some(displayName),
          Some(languageName),
          Some(description),
          Some(defaultPort),
          Some(executePath),
          Some(healthPath),
          Some(prompt),
        ) =>
        Some({
          id,
          displayName,
          languageName,
          description,
          aliases: getStringArray("aliases"),
          defaultHost: getString("defaultHost")->Option.getOr("localhost"),
          defaultPort,
          executePath,
          healthPath,
          prompt,
          supportsDt: getBool("supportsDt"),
          keywords: getStringArray("keywords"),
        })
      | _ => None
      }
    }
  | Bool(_) | Null | String(_) | Number(_) | Array(_) => None
  }
}

@ocaml.doc("
Parse a JSON array of profile objects into validated profiles.
Silently skips any entries that fail to decode.
")
let decodeProfiles = (json: JSON.t): array<profile> => {
  switch JSON.Classify.classify(json) {
  | Array(arr) => arr->Array.filterMap(decodeProfile)
  | Bool(_) | Null | String(_) | Number(_) | Object(_) => []
  }
}

@ocaml.doc("
Load custom profiles from `/nqc-profiles.json` served alongside the web app.
This is a TEA command that fetches the config file and merges any valid
profiles into the `customs` registry. Silently succeeds (with empty customs)
if the file doesn't exist or contains invalid JSON.

The config file should contain a JSON array of profile objects.
Place it in the same directory as `index.html`.
")
// ============================================================================
// Fetch API bindings (browser-native, no third-party dependency)
// ============================================================================

module FetchResponse = {
  type t
  @get external ok: t => bool = "ok"
  @send external json: t => Promise.t<JSON.t> = "json"
}

@val external fetch: string => Promise.t<FetchResponse.t> = "fetch"

let loadCustomProfiles = (): Tea_Cmd.t<Msg.t> => {
  Tea_Cmd.effect(_dispatch => {
    let _ = fetch("/nqc-profiles.json")
    ->Promise.then(response => {
      if FetchResponse.ok(response) {
        FetchResponse.json(response)
      } else {
        // File not found or server error — not an error, just no custom profiles
        Promise.resolve(JSON.Encode.array([]))
      }
    })
    ->Promise.then(json => {
      let profiles = decodeProfiles(json)
      if Array.length(profiles) > 0 {
        customs := profiles
        Console.log2("NQC: Loaded", `${Int.toString(Array.length(profiles))} custom database profile(s)`)
      }
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      // Fetch failed entirely (network error, CORS, etc.) — silently ignore
      Promise.resolve()
    })
    ()
  })
}

@ocaml.doc("
Find a profile by its canonical `id` or any of its `aliases`.
Used by route parsing to resolve `/query/:dbId` URL segments.
Returns `None` if no profile matches.
")
let findById = (targetId: string): option<profile> => {
  let lower = targetId->String.toLowerCase
  all()->Array.find(p => {
    p.id == lower || p.aliases->Array.some(a => a->String.toLowerCase == lower)
  })
}
