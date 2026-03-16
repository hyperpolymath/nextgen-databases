# @lithoglyph/rescript

Type-safe ReScript client for the Lithoglyph multi-protocol API server.

Supports REST, GraphQL, and WebSocket (subscriptions) protocols.

SPDX-License-Identifier: PMPL-1.0-or-later

## Installation

### With Deno (Recommended)

```bash
# Add to deno.json imports
{
  "imports": {
    "@lithoglyph/rescript": "jsr:@lithoglyph/rescript@1.0.0"
  }
}
```

### With ReScript + Deno

Add to `rescript.json`:

```json
{
  "bs-dependencies": ["@lithoglyph/rescript", "@rescript/core"]
}
```

## Quick Start

```rescript
open Lithoglyph
open Lithoglyph_Types
open Lithoglyph_Query

// Create client
let client = Lithoglyph.make(~baseUrl="http://localhost:8080")

// Or from environment (reads LITHOGLYPH_URL / LITHOGLYPH_API_KEY)
let client = Lithoglyph.fromEnv()

// Check health
let healthResult = await client->Lithoglyph.health
switch healthResult {
| Ok(h) => Console.log(`Server: ${h.status == Healthy ? "healthy" : "unhealthy"}`)
| Error(e) => Console.error(e.message)
}
```

## Query Examples

### Using Query Builder

```rescript
let query = Lithoglyph_Query.make()
  ->from("articles")
  ->select(["id", "title", "author"])
  ->whereField("status", Eq, JSON.Encode.string("published"))
  ->whereField("views", Gt, JSON.Encode.int(100))
  ->orderBy("createdAt", ~ascending=false)
  ->limit(10)
  ->withProvenance({
    actor: "editor@news.org",
    rationale: "Daily review of popular articles"
  })

let result = await client->Lithoglyph.queryWith(query)
```

### Raw GQL

```rescript
let result = await client->Lithoglyph.query(
  ~gql=`SELECT * FROM articles WHERE status = "published" LIMIT 10`,
  ~provenance={
    actor: "editor@news.org",
    rationale: "Daily review"
  }
)

switch result {
| Ok(r) => Console.log(`Found ${Int.toString(r.rowCount)} articles`)
| Error(e) => Console.error(e.message)
}
```

### Via GraphQL

```rescript
let result = await client->Lithoglyph.queryGraphQL(
  ~gql=`SELECT * FROM articles LIMIT 5`
)
```

## EXPLAIN

```rescript
let plan = await client->Lithoglyph.explain(
  ~gql=`SELECT * FROM articles WHERE status = "published"`,
  ~analyze=true
)

switch plan {
| Ok(e) => {
    Console.log(`Estimated cost: ${Float.toString(e.plan.estimatedCost)}`)
    e.plan.steps->Array.forEach(step =>
      Console.log(`  Step: ${step.collection->Option.getOr("?")}`)
    )
  }
| Error(e) => Console.error(e.message)
}
```

## Collection Operations

```rescript
// List collections
let collections = await client->Lithoglyph.listCollections

// Create collection
let newCol = await client->Lithoglyph.createCollection(
  ~name="users",
  ~collectionType=Document,
)

// Get collection
let col = await client->Lithoglyph.getCollection(~name="articles")

// Delete collection
let _ = await client->Lithoglyph.deleteCollection(~name="temp_data")
```

## Journal Operations

```rescript
let journal = await client->Lithoglyph.getJournal(
  ~since=1000,
  ~limit=50,
  ~collection="articles"
)

switch journal {
| Ok(j) => {
    j.entries->Array.forEach(entry =>
      Console.log(`[${Int.toString(entry.seq)}] ${entry.collection->Option.getOr("?")}`)
    )
    if j.hasMore { Console.log("More entries available...") }
  }
| Error(e) => Console.error(e.message)
}
```

## Normalization

```rescript
// Discover functional dependencies
let fds = await client->Lithoglyph.discoverDependencies(
  ~collection="orders",
  ~confidence=0.95
)

// Analyze normal form
let analysis = await client->Lithoglyph.analyzeNormalForm(~collection="orders")
```

## Migrations (Announce-Shadow-Commit)

```rescript
// Start migration
let migration = await client->Lithoglyph.startMigration(
  ~collection="orders",
  ~targetForm=BCNF
)

switch migration {
| Ok(m) => {
    Console.log(`Migration ${m.id}: ${m.narrative}`)

    // Advance to shadow (dual-write) phase
    let _ = await client->Lithoglyph.advanceToShadow(~migrationId=m.id)

    // When ready, commit
    let _ = await client->Lithoglyph.commitMigration(~migrationId=m.id)

    // Or abort if something goes wrong
    // let _ = await client->Lithoglyph.abortMigration(~migrationId=m.id)
  }
| Error(e) => Console.error(e.message)
}
```

## WebSocket Subscriptions

### Journal Streaming

```rescript
open Lithoglyph_Subscriptions

let handle = subscribeJournal(
  ~baseUrl="http://localhost:8080",
  ~collection="articles",
  ~onEntry=entry => {
    Console.log(`[${Int.toString(entry.seq)}] New journal entry`)
  },
  ~onError=err => Console.error(err),
)

// Later: stop streaming
handle.unsubscribe()
```

### Migration Progress

```rescript
open Lithoglyph_Subscriptions

let handle = subscribeMigrationProgress(
  ~baseUrl="http://localhost:8080",
  ~migrationId="mig-001",
  ~onProgress=progress => {
    Console.log(`Migration ${Float.toString(progress.progress * 100.0)}%: ${progress.message}`)
  },
)
```

## Authentication

```rescript
// API Key
let client = Lithoglyph.make(
  ~baseUrl="http://localhost:8080",
  ~auth=ApiKey("your-api-key")
)

// Bearer Token (JWT)
let client = Lithoglyph.make(
  ~baseUrl="http://localhost:8080",
  ~auth=Bearer("your-jwt-token")
)
```

## Module Structure

| Module | Purpose |
|--------|---------|
| `Lithoglyph` | Main client (REST + GraphQL) |
| `Lithoglyph_Types` | All type definitions |
| `Lithoglyph_Query` | GQL query builder |
| `Lithoglyph_Subscriptions` | WebSocket real-time subscriptions |

## Error Handling

All API methods return `Result.t<'a, apiError>`:

```rescript
switch result {
| Ok(data) => // Handle success
| Error({code, message, details}) => {
    Console.error(`Error ${code}: ${message}`)
  }
}
```

## Backwards Compatibility

The client reads `LITHOGLYPH_URL` / `LITHOGLYPH_API_KEY` environment variables,
falling back to the legacy `LITH_URL` / `LITH_API_KEY` names.

The old `Lith` / `Lith_Types` / `Lith_Query` modules are still present
for backwards compatibility but should be considered deprecated.

## License

PMPL-1.0-or-later (Palimpsest License)

Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
