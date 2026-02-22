// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Tests for Database.res — profile registry and JSON decoder.
Verifies that:
  - Built-in profiles (VQL, GQL, KQL) are present and correct
  - findById resolves by canonical id and aliases
  - decodeProfile correctly parses valid JSON and rejects invalid JSON
")

// ============================================================================
// Node.js test/assert bindings
// ============================================================================

@module("node:test") external test: (string, unit => unit) => unit = "test"
@module("node:assert") external strictEqual: ('a, 'a) => unit = "strictEqual"
@module("node:assert") external ok: bool => unit = "ok"

// ============================================================================
// Built-in profile tests
// ============================================================================

test("builtins contains 3 profiles", () => {
  strictEqual(Array.length(Database.builtins), 3)
})

test("VQL profile has correct id and port", () => {
  strictEqual(Database.vql.id, "vql")
  strictEqual(Database.vql.defaultPort, 8080)
  strictEqual(Database.vql.languageName, "VQL")
  ok(Database.vql.supportsDt)
})

test("GQL profile has correct id and port", () => {
  strictEqual(Database.gql.id, "gql")
  strictEqual(Database.gql.defaultPort, 8081)
  strictEqual(Database.gql.languageName, "GQL")
})

test("KQL profile has correct id and port", () => {
  strictEqual(Database.kql.id, "kql")
  strictEqual(Database.kql.defaultPort, 8082)
  strictEqual(Database.kql.languageName, "KQL")
})

test("all() includes at least the 3 builtins", () => {
  ok(Array.length(Database.all()) >= 3)
})

// ============================================================================
// findById tests
// ============================================================================

test("findById resolves canonical id 'vql'", () => {
  switch Database.findById("vql") {
  | Some(p) => strictEqual(p.id, "vql")
  | None => ok(false)
  }
})

test("findById resolves alias 'verisimdb'", () => {
  switch Database.findById("verisimdb") {
  | Some(p) => strictEqual(p.id, "vql")
  | None => ok(false)
  }
})

test("findById resolves alias 'lithoglyph'", () => {
  switch Database.findById("lithoglyph") {
  | Some(p) => strictEqual(p.id, "gql")
  | None => ok(false)
  }
})

test("findById resolves alias 'quandle'", () => {
  switch Database.findById("quandle") {
  | Some(p) => strictEqual(p.id, "kql")
  | None => ok(false)
  }
})

test("findById is case-insensitive", () => {
  switch Database.findById("VQL") {
  | Some(p) => strictEqual(p.id, "vql")
  | None => ok(false)
  }
})

test("findById returns None for unknown id", () => {
  switch Database.findById("nonexistent") {
  | Some(_) => ok(false)
  | None => ok(true)
  }
})

// ============================================================================
// decodeProfile tests
// ============================================================================

test("decodeProfile: valid JSON object decodes to profile", () => {
  let json = JSON.parseExn(`{
    "id": "test",
    "displayName": "Test DB",
    "languageName": "TQL",
    "description": "A test database",
    "aliases": ["testdb"],
    "defaultHost": "localhost",
    "defaultPort": 9999,
    "executePath": "/tql/execute",
    "healthPath": "/health",
    "prompt": "tql> ",
    "supportsDt": false,
    "keywords": ["SELECT", "FROM"]
  }`)
  switch Database.decodeProfile(json) {
  | Some(p) =>
    strictEqual(p.id, "test")
    strictEqual(p.displayName, "Test DB")
    strictEqual(p.defaultPort, 9999)
    strictEqual(p.supportsDt, false)
    strictEqual(Array.length(p.keywords), 2)
  | None => ok(false)
  }
})

test("decodeProfile: missing required field returns None", () => {
  let json = JSON.parseExn(`{
    "id": "test",
    "displayName": "Test DB"
  }`)
  switch Database.decodeProfile(json) {
  | Some(_) => ok(false)
  | None => ok(true)
  }
})

test("decodeProfile: non-object returns None", () => {
  let json = JSON.parseExn(`"just a string"`)
  switch Database.decodeProfile(json) {
  | Some(_) => ok(false)
  | None => ok(true)
  }
})

test("decodeProfile: defaultHost defaults to localhost when absent", () => {
  let json = JSON.parseExn(`{
    "id": "test",
    "displayName": "Test DB",
    "languageName": "TQL",
    "description": "A test database",
    "defaultPort": 9999,
    "executePath": "/tql/execute",
    "healthPath": "/health",
    "prompt": "tql> "
  }`)
  switch Database.decodeProfile(json) {
  | Some(p) => strictEqual(p.defaultHost, "localhost")
  | None => ok(false)
  }
})

// ============================================================================
// decodeProfiles tests
// ============================================================================

test("decodeProfiles: parses array of profile objects", () => {
  let json = JSON.parseExn(`[
    {
      "id": "a", "displayName": "A", "languageName": "AQL",
      "description": "DB A", "defaultPort": 1000,
      "executePath": "/a/exec", "healthPath": "/h", "prompt": "a> "
    },
    {
      "id": "b", "displayName": "B", "languageName": "BQL",
      "description": "DB B", "defaultPort": 2000,
      "executePath": "/b/exec", "healthPath": "/h", "prompt": "b> "
    }
  ]`)
  let profiles = Database.decodeProfiles(json)
  strictEqual(Array.length(profiles), 2)
})

test("decodeProfiles: skips invalid entries", () => {
  let json = JSON.parseExn(`[
    {"id": "good", "displayName": "G", "languageName": "GQL",
     "description": "Good", "defaultPort": 1000,
     "executePath": "/g/exec", "healthPath": "/h", "prompt": "g> "},
    {"bad": "entry"},
    "not an object"
  ]`)
  let profiles = Database.decodeProfiles(json)
  strictEqual(Array.length(profiles), 1)
})

test("decodeProfiles: non-array returns empty", () => {
  let json = JSON.parseExn(`{"not": "an array"}`)
  let profiles = Database.decodeProfiles(json)
  strictEqual(Array.length(profiles), 0)
})
