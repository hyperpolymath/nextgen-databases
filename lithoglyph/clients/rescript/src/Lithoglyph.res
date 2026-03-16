// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Lithoglyph ReScript Client
// Multi-protocol client for the Lithoglyph API server (REST + GraphQL)
//
// Stone-carved data for the ages: narrative-first, reversible, audit-grade database
// Compatible with Deno runtime (not Node/npm)

open Lithoglyph_Types
open Lithoglyph_Query

// =============================================================================
// HTTP Helpers
// =============================================================================

@val external fetch: (string, 'options) => promise<'response> = "fetch"

type fetchOptions = {
  method: string,
  headers: Dict.t<string>,
  body?: string,
}

type fetchResponse = {
  ok: bool,
  status: int,
  json: unit => promise<JSON.t>,
  text: unit => promise<string>,
}

// =============================================================================
// Client
// =============================================================================

/** The Lithoglyph client instance */
type t = {
  config: config,
}

/** Create a new Lithoglyph client with explicit configuration */
let make = (~baseUrl, ~auth=?, ~timeout=?, ~retries=?, ~protocol=?) => {
  config: {
    baseUrl,
    auth,
    timeout,
    retries,
    protocol,
  },
}

/** Create a client from Deno environment variables.
 *  Reads LITHOGLYPH_URL (or LITH_URL for backwards compatibility)
 *  and LITHOGLYPH_API_KEY (or LITH_API_KEY). */
let fromEnv = () => {
  let baseUrl = %raw(`
    (typeof Deno !== 'undefined')
      ? (Deno.env.get("LITHOGLYPH_URL") || Deno.env.get("LITH_URL") || "http://localhost:8080")
      : "http://localhost:8080"
  `)
  let apiKey = %raw(`
    (typeof Deno !== 'undefined')
      ? (Deno.env.get("LITHOGLYPH_API_KEY") || Deno.env.get("LITH_API_KEY") || null)
      : null
  `)

  make(
    ~baseUrl,
    ~auth=?switch apiKey {
    | Some(key) => Some(ApiKey(key))
    | None => None
    },
  )
}

// Internal: Build headers for requests
let buildHeaders = client => {
  let headers = Dict.make()
  headers->Dict.set("Content-Type", "application/json")
  headers->Dict.set("Accept", "application/json")

  switch client.config.auth {
  | Some(ApiKey(key)) => headers->Dict.set("X-API-Key", key)
  | Some(Bearer(token)) => headers->Dict.set("Authorization", `Bearer ${token}`)
  | Some(NoAuth) | None => ()
  }

  headers
}

// Internal: Make HTTP request to REST API
let request = async (client, ~method, ~path, ~body=?) => {
  let url = `${client.config.baseUrl}${path}`
  let headers = buildHeaders(client)

  let options: fetchOptions = {
    method,
    headers,
    body: ?body->Option.map(JSON.stringify),
  }

  let response: fetchResponse = await fetch(url, options)

  if !response.ok {
    let text = await response.text()
    Error({
      code: Int.toString(response.status),
      message: text,
      details: None,
    })
  } else {
    let json = await response.json()
    Ok(json)
  }
}

// Internal: Make GraphQL request
let graphqlRequest = async (client, ~query, ~variables=?, ~operationName=?) => {
  let body: JSON.t = JSON.Encode.object([
    ("query", JSON.Encode.string(query)),
    ...switch variables {
    | Some(v) => [("variables", v)]
    | None => []
    },
    ...switch operationName {
    | Some(n) => [("operationName", JSON.Encode.string(n))]
    | None => []
    },
  ])

  let url = `${client.config.baseUrl}/graphql`
  let headers = buildHeaders(client)

  let options: fetchOptions = {
    method: "POST",
    headers,
    body: ?Some(JSON.stringify(body)),
  }

  let response: fetchResponse = await fetch(url, options)

  if !response.ok {
    let text = await response.text()
    Error({
      code: Int.toString(response.status),
      message: text,
      details: None,
    })
  } else {
    let json = await response.json()
    let obj = json->JSON.Decode.object->Option.getExn

    // Check for GraphQL errors
    switch obj->Dict.get("errors") {
    | Some(errors) => {
        let errArr = errors->JSON.Decode.array->Option.getOr([])
        let firstErr =
          errArr
          ->Array.get(0)
          ->Option.flatMap(JSON.Decode.object)
        let message =
          firstErr
          ->Option.flatMap(e => e->Dict.get("message"))
          ->Option.flatMap(JSON.Decode.string)
          ->Option.getOr("GraphQL error")
        Error({
          code: "GRAPHQL_ERROR",
          message,
          details: Some(errors),
        })
      }
    | None =>
      switch obj->Dict.get("data") {
      | Some(data) => Ok(data)
      | None =>
        Error({
          code: "NO_DATA",
          message: "GraphQL response contained no data",
          details: None,
        })
      }
    }
  }
}

// =============================================================================
// Query Operations (REST)
// =============================================================================

/** Execute an GQL query via REST API */
let query = async (client, ~gql, ~provenance=?, ~explain=?) => {
  let body: JSON.t = JSON.Encode.object([
    ("gql", JSON.Encode.string(gql)),
    ...switch provenance {
    | Some(p) => [
        (
          "provenance",
          JSON.Encode.object([
            ("actor", JSON.Encode.string(p.actor)),
            ("rationale", JSON.Encode.string(p.rationale)),
          ]),
        ),
      ]
    | None => []
    },
    ...switch explain {
    | Some(true) => [("explain", JSON.Encode.bool(true))]
    | Some(false) | None => []
    },
  ])

  let result = await request(client, ~method="POST", ~path="/v1/query", ~body)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      rows: obj
        ->Dict.get("rows")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(row => row->JSON.Decode.object->Option.getOr(Dict.make())),
      rowCount: obj
        ->Dict.get("rowCount")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
      journalSeq: obj
        ->Dict.get("journalSeq")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
      provenance: None,
      timing: obj
        ->Dict.get("timing")
        ->Option.flatMap(JSON.Decode.object)
        ->Option.map(t => {
          parseMs: t->Dict.get("parseMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
          planMs: t->Dict.get("planMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
          executeMs: t
            ->Dict.get("executeMs")
            ->Option.flatMap(JSON.Decode.float)
            ->Option.getOr(0.0),
          totalMs: t->Dict.get("totalMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
        }),
    }
  })
}

/** Execute a query using the query builder */
let queryWith = async (client, builder) => {
  let gql = builder->toGql
  let provenance = builder.provenance
  await query(client, ~gql, ~provenance?)
}

// =============================================================================
// Query Operations (GraphQL)
// =============================================================================

/** Execute an GQL query via GraphQL API */
let queryGraphQL = async (client, ~gql, ~provenance=?) => {
  let variables: JSON.t = JSON.Encode.object([
    ("gql", JSON.Encode.string(gql)),
    ...switch provenance {
    | Some(p) => [
        (
          "provenance",
          JSON.Encode.object([
            ("actor", JSON.Encode.string(p.actor)),
            ("rationale", JSON.Encode.string(p.rationale)),
          ]),
        ),
      ]
    | None => []
    },
  ])

  let gqlQuery = `
    query ExecuteQuery($gql: String!, $provenance: ProvenanceInput) {
      query(gql: $gql, provenance: $provenance) {
        rows
        rowCount
        journalSeq
        timing {
          parseMs
          planMs
          executeMs
          totalMs
        }
      }
    }
  `

  let result = await graphqlRequest(client, ~query=gqlQuery, ~variables)

  result->Result.map(data => {
    let queryObj =
      data
      ->JSON.Decode.object
      ->Option.flatMap(d => d->Dict.get("query"))
      ->Option.flatMap(JSON.Decode.object)
      ->Option.getExn
    {
      rows: queryObj
        ->Dict.get("rows")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(row => row->JSON.Decode.object->Option.getOr(Dict.make())),
      rowCount: queryObj
        ->Dict.get("rowCount")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
      journalSeq: queryObj
        ->Dict.get("journalSeq")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
      provenance: None,
      timing: queryObj
        ->Dict.get("timing")
        ->Option.flatMap(JSON.Decode.object)
        ->Option.map(t => {
          parseMs: t->Dict.get("parseMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
          planMs: t->Dict.get("planMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
          executeMs: t
            ->Dict.get("executeMs")
            ->Option.flatMap(JSON.Decode.float)
            ->Option.getOr(0.0),
          totalMs: t->Dict.get("totalMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
        }),
    }
  })
}

// =============================================================================
// EXPLAIN Operations
// =============================================================================

/** Get the query execution plan without running the query */
let explain = async (client, ~gql, ~analyze=?, ~verbose=?) => {
  let body: JSON.t = JSON.Encode.object([
    ("gql", JSON.Encode.string(gql)),
    ("explain", JSON.Encode.bool(true)),
    ...switch analyze {
    | Some(true) => [("analyze", JSON.Encode.bool(true))]
    | Some(false) | None => []
    },
    ...switch verbose {
    | Some(true) => [("verbose", JSON.Encode.bool(true))]
    | Some(false) | None => []
    },
  ])

  let result = await request(client, ~method="POST", ~path="/v1/query", ~body)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    let planObj =
      obj
      ->Dict.get("plan")
      ->Option.flatMap(JSON.Decode.object)
      ->Option.getExn

    {
      plan: {
        steps: planObj
          ->Dict.get("steps")
          ->Option.flatMap(JSON.Decode.array)
          ->Option.getOr([])
          ->Array.map(step => {
            let s = step->JSON.Decode.object->Option.getExn
            {
              stepType: switch s
                ->Dict.get("type")
                ->Option.flatMap(JSON.Decode.string)
                ->Option.getOr("SCAN") {
              | "FILTER" | "filter" => Filter
              | "PROJECT" | "project" => Project
              | "LIMIT" | "limit" => Limit
              | "TRAVERSE" | "traverse" => Traverse
              | "INSERT" | "insert" => StepInsert
              | "UPDATE" | "update" => StepUpdate
              | "DELETE" | "delete" => StepDelete
              | _ => Scan
              },
              collection: s->Dict.get("collection")->Option.flatMap(JSON.Decode.string),
              expression: s->Dict.get("expression")->Option.flatMap(JSON.Decode.string),
              count: s
                ->Dict.get("count")
                ->Option.flatMap(JSON.Decode.float)
                ->Option.map(Float.toInt),
              details: s->Dict.get("details"),
            }
          }),
        estimatedCost: planObj
          ->Dict.get("estimatedCost")
          ->Option.flatMap(JSON.Decode.float)
          ->Option.getOr(0.0),
        rationale: planObj->Dict.get("rationale")->Option.flatMap(JSON.Decode.string),
      },
      timing: obj
        ->Dict.get("timing")
        ->Option.flatMap(JSON.Decode.object)
        ->Option.map(t => {
          parseMs: t->Dict.get("parseMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
          planMs: t->Dict.get("planMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
          executeMs: t
            ->Dict.get("executeMs")
            ->Option.flatMap(JSON.Decode.float)
            ->Option.getOr(0.0),
          totalMs: t->Dict.get("totalMs")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0),
        }),
      verboseOutput: None,
    }
  })
}

// =============================================================================
// Collection Operations
// =============================================================================

/** List all collections */
let listCollections = async client => {
  let result = await request(client, ~method="GET", ~path="/v1/collections")

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    obj
    ->Dict.get("collections")
    ->Option.flatMap(JSON.Decode.array)
    ->Option.getOr([])
    ->Array.map(item => {
      let col = item->JSON.Decode.object->Option.getExn
      {
        name: col->Dict.get("name")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
        collectionType: switch col
          ->Dict.get("type")
          ->Option.flatMap(JSON.Decode.string)
          ->Option.getOr("DOCUMENT") {
        | "EDGE" | "edge" => Edge
        | "SCHEMA" | "schema" => Schema
        | _ => Document
        },
        documentCount: col
          ->Dict.get("documentCount")
          ->Option.flatMap(JSON.Decode.float)
          ->Option.map(Float.toInt)
          ->Option.getOr(0),
        normalForm: col->Dict.get("normalForm")->Option.flatMap(JSON.Decode.string),
        schema: col->Dict.get("schema"),
      }
    })
  })
}

/** Get a specific collection by name */
let getCollection = async (client, ~name) => {
  let result = await request(client, ~method="GET", ~path=`/v1/collections/${name}`)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      name: obj->Dict.get("name")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
      collectionType: switch obj
        ->Dict.get("type")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("DOCUMENT") {
      | "EDGE" | "edge" => Edge
      | "SCHEMA" | "schema" => Schema
      | _ => Document
      },
      documentCount: obj
        ->Dict.get("documentCount")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
      normalForm: obj->Dict.get("normalForm")->Option.flatMap(JSON.Decode.string),
      schema: obj->Dict.get("schema"),
    }
  })
}

/** Create a new collection */
let createCollection = async (client, ~name, ~collectionType=Document, ~schema=?) => {
  let typeStr = switch collectionType {
  | Document => "DOCUMENT"
  | Edge => "EDGE"
  | Schema => "SCHEMA"
  }

  let body: JSON.t = JSON.Encode.object([
    ("name", JSON.Encode.string(name)),
    ("type", JSON.Encode.string(typeStr)),
    ...switch schema {
    | Some(s) => [("schema", s)]
    | None => []
    },
  ])

  let result = await request(client, ~method="POST", ~path="/v1/collections", ~body)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      name: obj->Dict.get("name")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
      collectionType: switch obj
        ->Dict.get("type")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("DOCUMENT") {
      | "EDGE" | "edge" => Edge
      | "SCHEMA" | "schema" => Schema
      | _ => Document
      },
      documentCount: 0,
      normalForm: obj->Dict.get("normalForm")->Option.flatMap(JSON.Decode.string),
      schema: obj->Dict.get("schema"),
    }
  })
}

/** Delete a collection */
let deleteCollection = async (client, ~name) => {
  let result = await request(client, ~method="DELETE", ~path=`/v1/collections/${name}`)
  result->Result.map(_ => ())
}

// =============================================================================
// Journal Operations
// =============================================================================

/** Get journal entries with optional filtering */
let getJournal = async (client, ~since=?, ~limit=?, ~collection=?) => {
  let params = []
  switch since {
  | Some(seq) => params->Array.push(`since=${Int.toString(seq)}`)->ignore
  | None => ()
  }
  switch limit {
  | Some(n) => params->Array.push(`limit=${Int.toString(n)}`)->ignore
  | None => ()
  }
  switch collection {
  | Some(c) => params->Array.push(`collection=${c}`)->ignore
  | None => ()
  }

  let queryStr = params->Array.length > 0 ? `?${params->Array.join("&")}` : ""

  let result = await request(client, ~method="GET", ~path=`/v1/journal${queryStr}`)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      entries: obj
        ->Dict.get("entries")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(item => {
          let entry = item->JSON.Decode.object->Option.getExn
          {
            seq: entry
              ->Dict.get("seq")
              ->Option.flatMap(JSON.Decode.float)
              ->Option.map(Float.toInt)
              ->Option.getOr(0),
            timestamp: entry
              ->Dict.get("timestamp")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr(""),
            operation: switch entry
              ->Dict.get("operation")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr("insert") {
            | "update" | "UPDATE" => Update
            | "delete" | "DELETE" => Delete
            | "CREATE_COLLECTION" | "create_collection" => CreateCollection
            | "DROP_COLLECTION" | "drop_collection" => DropCollection
            | "MIGRATION_START" | "migration_start" => MigrationStart
            | "MIGRATION_COMMIT" | "migration_commit" => MigrationCommit
            | _ => Insert
            },
            collection: entry->Dict.get("collection")->Option.flatMap(JSON.Decode.string),
            documentId: entry->Dict.get("documentId")->Option.flatMap(JSON.Decode.string),
            before: entry->Dict.get("before"),
            after: entry->Dict.get("after"),
            provenance: entry
              ->Dict.get("provenance")
              ->Option.flatMap(JSON.Decode.object)
              ->Option.map(p => {
                actor: p
                  ->Dict.get("actor")
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr(""),
                rationale: p
                  ->Dict.get("rationale")
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr(""),
              }),
            inverse: entry->Dict.get("inverse")->Option.flatMap(JSON.Decode.string),
          }
        }),
      hasMore: obj
        ->Dict.get("hasMore")
        ->Option.flatMap(JSON.Decode.bool)
        ->Option.getOr(false),
      nextSeq: obj
        ->Dict.get("nextSeq")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt),
    }
  })
}

// =============================================================================
// Normalization Operations
// =============================================================================

/** Discover functional dependencies in a collection */
let discoverDependencies = async (client, ~collection, ~confidence=?) => {
  let body: JSON.t = JSON.Encode.object([
    ("collection", JSON.Encode.string(collection)),
    ...switch confidence {
    | Some(c) => [("confidenceThreshold", JSON.Encode.float(c))]
    | None => []
    },
  ])

  let result = await request(client, ~method="POST", ~path="/v1/normalize/discover", ~body)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      collection: obj
        ->Dict.get("collection")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr(""),
      functionalDependencies: obj
        ->Dict.get("functionalDependencies")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(item => {
          let fd = item->JSON.Decode.object->Option.getExn
          {
            determinant: fd
              ->Dict.get("determinant")
              ->Option.flatMap(JSON.Decode.array)
              ->Option.getOr([])
              ->Array.filterMap(JSON.Decode.string),
            dependent: fd
              ->Dict.get("dependent")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr(""),
            confidence: fd
              ->Dict.get("confidence")
              ->Option.flatMap(JSON.Decode.float)
              ->Option.getOr(0.0),
            tier: switch fd
              ->Dict.get("tier")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr("medium") {
            | "high" | "HIGH" => High
            | "low" | "LOW" => Low
            | _ => Medium
            },
          }
        }),
      candidateKeys: obj
        ->Dict.get("candidateKeys")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(keyArr =>
          keyArr
          ->JSON.Decode.array
          ->Option.getOr([])
          ->Array.filterMap(JSON.Decode.string)
        ),
    }
  })
}

/** Analyze normal form of a collection */
let analyzeNormalForm = async (client, ~collection) => {
  let body: JSON.t = JSON.Encode.object([("collection", JSON.Encode.string(collection))])

  let result = await request(client, ~method="POST", ~path="/v1/normalize/analyze", ~body)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      collection: obj
        ->Dict.get("collection")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr(""),
      currentForm: switch obj
        ->Dict.get("currentForm")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("1NF") {
      | "2NF" => NF2
      | "3NF" => NF3
      | "BCNF" => BCNF
      | _ => NF1
      },
      violations: obj
        ->Dict.get("violations")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(item => {
          let v = item->JSON.Decode.object->Option.getExn
          {
            violationType: switch v
              ->Dict.get("type")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr("TRANSITIVE_DEPENDENCY") {
            | "PARTIAL_DEPENDENCY" | "partial_dependency" => PartialDependency
            | "BCNF_VIOLATION" | "bcnf_violation" => BcnfViolation
            | _ => TransitiveDependency
            },
            description: v
              ->Dict.get("description")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr(""),
            affectedFields: v
              ->Dict.get("affectedFields")
              ->Option.flatMap(JSON.Decode.array)
              ->Option.getOr([])
              ->Array.filterMap(JSON.Decode.string),
          }
        }),
      recommendations: obj
        ->Dict.get("recommendations")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(item => {
          let r = item->JSON.Decode.object->Option.getExn
          {
            action: switch r
              ->Dict.get("action")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr("DECOMPOSE") {
            | "ADD_CONSTRAINT" | "add_constraint" => AddConstraint
            | "DENORMALIZE" | "denormalize" => Denormalize
            | _ => Decompose
            },
            description: r
              ->Dict.get("description")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.getOr(""),
            targetForm: r
              ->Dict.get("targetForm")
              ->Option.flatMap(JSON.Decode.string)
              ->Option.map(f =>
                switch f {
                | "1NF" => NF1
                | "2NF" => NF2
                | "3NF" => NF3
                | _ => BCNF
                }
              ),
            migrationSteps: r
              ->Dict.get("migrationSteps")
              ->Option.flatMap(JSON.Decode.array)
              ->Option.getOr([])
              ->Array.filterMap(JSON.Decode.string),
          }
        }),
    }
  })
}

// =============================================================================
// Migration Operations
// =============================================================================

// Internal: Parse migration response (shared between start/shadow/commit/abort)
let parseMigrationResponse = json => {
  let obj = json->JSON.Decode.object->Option.getExn
  {
    id: obj->Dict.get("id")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
    collection: obj
      ->Dict.get("collection")
      ->Option.flatMap(JSON.Decode.string)
      ->Option.getOr(""),
    phase: switch obj
      ->Dict.get("phase")
      ->Option.flatMap(JSON.Decode.string)
      ->Option.getOr("announce") {
    | "shadow" | "SHADOW" => Shadow
    | "commit" | "COMMIT" => Commit
    | "complete" | "COMPLETE" => Complete
    | "aborted" | "ABORTED" => Aborted
    | "rollback" | "ROLLBACK" => Rollback
    | _ => Announce
    },
    startedAt: obj
      ->Dict.get("startedAt")
      ->Option.flatMap(JSON.Decode.string)
      ->Option.getOr(""),
    narrative: obj
      ->Dict.get("narrative")
      ->Option.flatMap(JSON.Decode.string)
      ->Option.getOr(""),
  }
}

/** Start a schema migration */
let startMigration = async (client, ~collection, ~targetForm) => {
  let targetStr = switch targetForm {
  | NF1 => "1NF"
  | NF2 => "2NF"
  | NF3 => "3NF"
  | BCNF => "BCNF"
  }

  let body: JSON.t = JSON.Encode.object([
    ("collection", JSON.Encode.string(collection)),
    ("targetForm", JSON.Encode.string(targetStr)),
  ])

  let result = await request(client, ~method="POST", ~path="/v1/migrate/start", ~body)
  result->Result.map(parseMigrationResponse)
}

/** Advance a migration to the shadow (dual-write) phase */
let advanceToShadow = async (client, ~migrationId) => {
  let body: JSON.t = JSON.Encode.object([("migrationId", JSON.Encode.string(migrationId))])
  let result = await request(client, ~method="POST", ~path="/v1/migrate/shadow", ~body)
  result->Result.map(parseMigrationResponse)
}

/** Commit a migration (finalize the schema change) */
let commitMigration = async (client, ~migrationId) => {
  let body: JSON.t = JSON.Encode.object([("migrationId", JSON.Encode.string(migrationId))])
  let result = await request(client, ~method="POST", ~path="/v1/migrate/commit", ~body)
  result->Result.map(parseMigrationResponse)
}

/** Abort a migration (roll back to the original schema) */
let abortMigration = async (client, ~migrationId) => {
  let body: JSON.t = JSON.Encode.object([("migrationId", JSON.Encode.string(migrationId))])
  let result = await request(client, ~method="POST", ~path="/v1/migrate/abort", ~body)
  result->Result.map(parseMigrationResponse)
}

// =============================================================================
// Health Check
// =============================================================================

/** Check server health via REST API */
let health = async client => {
  let result = await request(client, ~method="GET", ~path="/v1/health")

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      status: switch obj
        ->Dict.get("status")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("UNHEALTHY") {
      | "healthy" | "HEALTHY" => Healthy
      | "degraded" | "DEGRADED" => Degraded
      | _ => Unhealthy
      },
      version: obj->Dict.get("version")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
      uptimeSeconds: obj
        ->Dict.get("uptime")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
      checks: obj
        ->Dict.get("checks")
        ->Option.flatMap(JSON.Decode.object)
        ->Option.map(checks => {
          let result = []
          checks
          ->Dict.toArray
          ->Array.forEach(((name, value)) => {
            let status = switch value->JSON.Decode.string->Option.getOr("fail") {
            | "pass" | "PASS" => Pass
            | _ => Fail
            }
            result->Array.push({name, status})->ignore
          })
          result
        }),
    }
  })
}

/** Check server health via GraphQL API */
let healthGraphQL = async client => {
  let gqlQuery = `
    query Health {
      health {
        status
        version
        uptimeSeconds
        checks {
          name
          status
        }
      }
    }
  `

  let result = await graphqlRequest(client, ~query=gqlQuery)

  result->Result.map(data => {
    let healthObj =
      data
      ->JSON.Decode.object
      ->Option.flatMap(d => d->Dict.get("health"))
      ->Option.flatMap(JSON.Decode.object)
      ->Option.getExn
    {
      status: switch healthObj
        ->Dict.get("status")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("UNHEALTHY") {
      | "HEALTHY" => Healthy
      | "DEGRADED" => Degraded
      | _ => Unhealthy
      },
      version: healthObj
        ->Dict.get("version")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr(""),
      uptimeSeconds: healthObj
        ->Dict.get("uptimeSeconds")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
      checks: None,
    }
  })
}

// =============================================================================
// Re-exports
// =============================================================================

module Types = Lithoglyph_Types
module Query = Lithoglyph_Query
module Subscriptions = Lithoglyph_Subscriptions
