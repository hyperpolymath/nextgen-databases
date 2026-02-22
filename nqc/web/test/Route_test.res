// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Tests for Route.res — URL parsing and serialization.
Verifies that cadre-router URL strings correctly map to typed Route.t variants
and that Route.toPath round-trips back to valid URL strings.
")

// ============================================================================
// Node.js test/assert bindings
// ============================================================================

@module("node:test") external test: (string, unit => unit) => unit = "test"
@module("node:assert") external strictEqual: ('a, 'a) => unit = "strictEqual"
@module("node:assert") external ok: bool => unit = "ok"

// ============================================================================
// fromUrl tests
// ============================================================================

test("fromUrl: root path maps to Picker", () => {
  let url = Tea_Url.parse("/")
  let route = Route.fromUrl(url)
  switch route {
  | Route.Picker => ok(true)
  | Route.Query(_) | Route.NotFound => ok(false)
  }
})

test("fromUrl: /query/vql maps to Query with dbId=vql", () => {
  let url = Tea_Url.parse("/query/vql")
  let route = Route.fromUrl(url)
  switch route {
  | Route.Query({dbId, dt, format}) =>
    strictEqual(dbId, "vql")
    strictEqual(dt, false)
    strictEqual(format, "table")
  | Route.Picker | Route.NotFound => ok(false)
  }
})

test("fromUrl: /query/gql?dt=true parses dependent types flag", () => {
  let url = Tea_Url.parse("/query/gql?dt=true")
  let route = Route.fromUrl(url)
  switch route {
  | Route.Query({dbId, dt, _}) =>
    strictEqual(dbId, "gql")
    strictEqual(dt, true)
  | Route.Picker | Route.NotFound => ok(false)
  }
})

test("fromUrl: /query/kql?format=json parses format parameter", () => {
  let url = Tea_Url.parse("/query/kql?format=json")
  let route = Route.fromUrl(url)
  switch route {
  | Route.Query({dbId, format, _}) =>
    strictEqual(dbId, "kql")
    strictEqual(format, "json")
  | Route.Picker | Route.NotFound => ok(false)
  }
})

test("fromUrl: /query/vql?dt=true&format=csv parses both params", () => {
  let url = Tea_Url.parse("/query/vql?dt=true&format=csv")
  let route = Route.fromUrl(url)
  switch route {
  | Route.Query({dbId, dt, format}) =>
    strictEqual(dbId, "vql")
    strictEqual(dt, true)
    strictEqual(format, "csv")
  | Route.Picker | Route.NotFound => ok(false)
  }
})

test("fromUrl: unknown path maps to NotFound", () => {
  let url = Tea_Url.parse("/unknown/path")
  let route = Route.fromUrl(url)
  switch route {
  | Route.NotFound => ok(true)
  | Route.Picker | Route.Query(_) => ok(false)
  }
})

test("fromUrl: /query without dbId maps to NotFound", () => {
  let url = Tea_Url.parse("/query")
  let route = Route.fromUrl(url)
  switch route {
  | Route.NotFound => ok(true)
  | Route.Picker | Route.Query(_) => ok(false)
  }
})

// ============================================================================
// toPath tests
// ============================================================================

test("toPath: Picker serializes to /", () => {
  strictEqual(Route.toPath(Route.Picker), "/")
})

test("toPath: Query with defaults serializes to /query/:dbId", () => {
  let path = Route.toPath(Route.Query({dbId: "vql", dt: false, format: "table"}))
  strictEqual(path, "/query/vql")
})

test("toPath: Query with dt=true includes ?dt=true", () => {
  let path = Route.toPath(Route.Query({dbId: "gql", dt: true, format: "table"}))
  ok(path->String.includes("dt=true"))
  ok(path->String.startsWith("/query/gql"))
})

test("toPath: Query with format=json includes ?format=json", () => {
  let path = Route.toPath(Route.Query({dbId: "kql", dt: false, format: "json"}))
  ok(path->String.includes("format=json"))
  ok(path->String.startsWith("/query/kql"))
})

test("toPath: NotFound serializes to /404", () => {
  strictEqual(Route.toPath(Route.NotFound), "/404")
})
