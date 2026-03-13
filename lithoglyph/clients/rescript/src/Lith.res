// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith ReScript Client
//
// Type-safe client for Lith REST API
// Compatible with Deno runtime

open Lith_Types
open Lith_Query

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

type t = {
  config: config,
}

/** Create a new Lith client */
let make = (~baseUrl, ~auth=?, ~timeout=?, ~retries=?) => {
  config: {
    baseUrl,
    auth,
    timeout,
    retries,
  },
}

/** Create client from environment (Deno) */
let fromEnv = () => {
  // Access Deno.env in Deno runtime
  let baseUrl = %raw(`Deno.env.get("LITH_URL") || "http://localhost:8080"`)
  let apiKey = %raw(`Deno.env.get("LITH_API_KEY")`)

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

// Internal: Make HTTP request
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

// =============================================================================
// Query Operations
// =============================================================================

/** Execute an GQL query */
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
    // Parse query result
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
// Collection Operations
// =============================================================================

/** List all collections */
let listCollections = async client => {
  let result = await request(client, ~method="GET", ~path="/v1/collections")

  result->Result.map(json => {
    json
    ->JSON.Decode.array
    ->Option.getOr([])
    ->Array.map(item => {
      let obj = item->JSON.Decode.object->Option.getExn
      {
        name: obj->Dict.get("name")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
        collectionType: switch obj
          ->Dict.get("type")
          ->Option.flatMap(JSON.Decode.string)
          ->Option.getOr("DOCUMENT") {
        | "EDGE" => Edge
        | "SCHEMA" => Schema
        | _ => Document
        },
        documentCount: obj
          ->Dict.get("documentCount")
          ->Option.flatMap(JSON.Decode.float)
          ->Option.map(Float.toInt)
          ->Option.getOr(0),
        schema: obj->Dict.get("schema"),
      }
    })
  })
}

/** Get a specific collection */
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
      | "EDGE" => Edge
      | "SCHEMA" => Schema
      | _ => Document
      },
      documentCount: obj
        ->Dict.get("documentCount")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
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
      | "EDGE" => Edge
      | "SCHEMA" => Schema
      | _ => Document
      },
      documentCount: 0,
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

/** Get journal entries */
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
    json
    ->JSON.Decode.array
    ->Option.getOr([])
    ->Array.map(item => {
      let obj = item->JSON.Decode.object->Option.getExn
      {
        seq: obj
          ->Dict.get("seq")
          ->Option.flatMap(JSON.Decode.float)
          ->Option.map(Float.toInt)
          ->Option.getOr(0),
        timestamp: obj->Dict.get("timestamp")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
        operation: switch obj
          ->Dict.get("operation")
          ->Option.flatMap(JSON.Decode.string)
          ->Option.getOr("INSERT") {
        | "UPDATE" => Update
        | "DELETE" => Delete
        | "CREATE_COLLECTION" => CreateCollection
        | "DROP_COLLECTION" => DropCollection
        | "MIGRATION_START" => MigrationStart
        | "MIGRATION_COMMIT" => MigrationCommit
        | _ => Insert
        },
        collection: obj->Dict.get("collection")->Option.flatMap(JSON.Decode.string),
        documentId: obj->Dict.get("documentId")->Option.flatMap(JSON.Decode.string),
        provenance: None,
      }
    })
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
    | Some(c) => [("minConfidence", JSON.Encode.float(c))]
    | None => []
    },
  ])

  let result = await request(client, ~method="POST", ~path="/v1/normalize/discover", ~body)

  result->Result.map(json => {
    json
    ->JSON.Decode.array
    ->Option.getOr([])
    ->Array.map(item => {
      let obj = item->JSON.Decode.object->Option.getExn
      {
        determinant: obj
          ->Dict.get("determinant")
          ->Option.flatMap(JSON.Decode.array)
          ->Option.getOr([])
          ->Array.filterMap(JSON.Decode.string),
        dependent: obj->Dict.get("dependent")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
        confidence: switch obj
          ->Dict.get("confidence")
          ->Option.flatMap(JSON.Decode.string)
          ->Option.getOr("MEDIUM") {
        | "HIGH" => High
        | "LOW" => Low
        | _ => Medium
        },
        sampleSize: obj
          ->Dict.get("sampleSize")
          ->Option.flatMap(JSON.Decode.float)
          ->Option.map(Float.toInt)
          ->Option.getOr(0),
      }
    })
  })
}

/** Analyze normal form of a collection */
let analyzeNormalForm = async (client, ~collection) => {
  let body: JSON.t = JSON.Encode.object([("collection", JSON.Encode.string(collection))])

  let result = await request(client, ~method="POST", ~path="/v1/normalize/analyze", ~body)

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      currentForm: switch obj
        ->Dict.get("currentForm")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("1NF") {
      | "2NF" => NF2
      | "3NF" => NF3
      | "BCNF" => BCNF
      | _ => NF1
      },
      targetForm: switch obj
        ->Dict.get("targetForm")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("BCNF") {
      | "1NF" => NF1
      | "2NF" => NF2
      | "3NF" => NF3
      | _ => BCNF
      },
      violations: obj
        ->Dict.get("violations")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.filterMap(JSON.Decode.string),
      recommendations: obj
        ->Dict.get("recommendations")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.filterMap(JSON.Decode.string),
    }
  })
}

// =============================================================================
// Migration Operations
// =============================================================================

/** Start a migration */
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

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      id: obj->Dict.get("id")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
      phase: switch obj
        ->Dict.get("phase")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("ANNOUNCE") {
      | "SHADOW" => Shadow
      | "COMMIT" => Commit
      | "ROLLBACK" => Rollback
      | _ => Announce
      },
      collection: obj
        ->Dict.get("collection")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr(""),
      startedAt: obj->Dict.get("startedAt")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
      narrative: obj->Dict.get("narrative")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
    }
  })
}

/** Commit a migration */
let commitMigration = async (client, ~migrationId) => {
  let body: JSON.t = JSON.Encode.object([("migrationId", JSON.Encode.string(migrationId))])

  let result = await request(client, ~method="POST", ~path="/v1/migrate/commit", ~body)
  result->Result.map(_ => ())
}

// =============================================================================
// Health Check
// =============================================================================

/** Check server health */
let health = async client => {
  let result = await request(client, ~method="GET", ~path="/v1/health")

  result->Result.map(json => {
    let obj = json->JSON.Decode.object->Option.getExn
    {
      status: switch obj
        ->Dict.get("status")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.getOr("UNHEALTHY") {
      | "HEALTHY" => Healthy
      | "DEGRADED" => Degraded
      | _ => Unhealthy
      },
      version: obj->Dict.get("version")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
      uptimeSeconds: obj
        ->Dict.get("uptimeSeconds")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.map(Float.toInt)
        ->Option.getOr(0),
    }
  })
}

// =============================================================================
// Re-exports
// =============================================================================

module Types = Lith_Types
module Query = Lith_Query
