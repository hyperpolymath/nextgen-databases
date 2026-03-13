// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Directus Hook Extension
 *
 * Directus hook for syncing content to Lith
 */

open Lith_Directus_Types

/** Node.js fetch binding */
@val external fetch: (string, {..}) => promise<{..}> = "fetch"

/** Environment variable access */
@val @scope("process.env") external lithUrl: option<string> = "LITH_URL"
@val @scope("process.env") external lithApiKey: option<string> = "LITH_API_KEY"
@val @scope("process.env") external lithSyncCollections: option<string> = "LITH_SYNC_COLLECTIONS"

/** Create Lith client */
let makeClient = (~baseUrl: string, ~apiKey: option<string>=?): lithClient => {
  let headers = {
    "Content-Type": "application/json",
    "Accept": "application/json",
  }

  let headersWithAuth = switch apiKey {
  | Some(key) => {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-API-Key": key,
    }
  | None => headers
  }

  let request = async (method: string, path: string, body: option<Js.Json.t>): Js.Json.t => {
    let url = baseUrl ++ path
    let options = switch body {
    | Some(b) => {
        "method": method,
        "headers": headersWithAuth,
        "body": Js.Json.stringify(b),
      }
    | None => {
        "method": method,
        "headers": headersWithAuth,
      }
    }

    let response = await fetch(url, options)
    let json = await response["json"]()
    json
  }

  {
    query: async (fdql: string): queryResult => {
      let body = Js.Json.object_(Js.Dict.fromArray([("fdql", Js.Json.string(fdql))]))
      let result = await request("POST", "/v1/query", Some(body))
      {
        rows: result["rows"],
        rowCount: result["rowCount"],
        affectedCount: result["affectedCount"],
      }
    },

    insert: async (collection: string, document: Js.Json.t): queryResult => {
      let fdql = `INSERT INTO ${collection} ${Js.Json.stringify(document)}`
      let body = Js.Json.object_(Js.Dict.fromArray([("fdql", Js.Json.string(fdql))]))
      let result = await request("POST", "/v1/query", Some(body))
      {
        rows: result["rows"],
        rowCount: result["rowCount"],
        affectedCount: result["affectedCount"],
      }
    },

    update: async (collection: string, document: Js.Json.t, id: string): queryResult => {
      let setClause = Js.Json.stringify(document)
      let fdql = `UPDATE ${collection} SET ${setClause} WHERE id = "${id}"`
      let body = Js.Json.object_(Js.Dict.fromArray([("fdql", Js.Json.string(fdql))]))
      let result = await request("POST", "/v1/query", Some(body))
      {
        rows: result["rows"],
        rowCount: result["rowCount"],
        affectedCount: result["affectedCount"],
      }
    },

    delete: async (collection: string, id: string): queryResult => {
      let fdql = `DELETE FROM ${collection} WHERE id = "${id}"`
      let body = Js.Json.object_(Js.Dict.fromArray([("fdql", Js.Json.string(fdql))]))
      let result = await request("POST", "/v1/query", Some(body))
      {
        rows: result["rows"],
        rowCount: result["rowCount"],
        affectedCount: result["affectedCount"],
      }
    },

    health: async (): healthResponse => {
      let result = await request("GET", "/v1/health", None)
      {
        status: result["status"],
        version: result["version"],
      }
    },
  }
}

/** Get sync collections from environment */
let getSyncCollections = (): array<string> => {
  switch lithSyncCollections {
  | Some(str) => String.split(str, ",")->Array.map(String.trim)
  | None => []
  }
}

/** Check if collection should sync */
let shouldSync = (collection: string): bool => {
  let syncCollections = getSyncCollections()
  if Array.length(syncCollections) === 0 {
    // If no collections specified, sync all (except system collections)
    !String.startsWith(collection, "directus_")
  } else {
    syncCollections->Array.includes(collection)
  }
}

/** Directus hook definition */
type hookDefinition = {
  filter: Js.Dict.t<(Js.Json.t, hookContext) => promise<Js.Json.t>>,
  action: Js.Dict.t<(eventPayload<Js.Json.t>, hookContext) => promise<unit>>,
}

/** Create the hook extension */
let createHook = (): hookDefinition => {
  let baseUrl = lithUrl->Option.getOr("http://localhost:8080")
  let client = makeClient(~baseUrl, ~apiKey=lithApiKey)

  let actionHandlers = Js.Dict.empty()

  // items.create handler
  Js.Dict.set(actionHandlers, "items.create", async (event: eventPayload<Js.Json.t>, _ctx: hookContext): unit => {
    if shouldSync(event.collection) {
      switch event.payload {
      | Some(data) =>
        try {
          let _ = await client.insert(event.collection, data)
          ()
        } catch {
        | _ => ()
        }
      | None => ()
      }
    }
  })

  // items.update handler
  Js.Dict.set(actionHandlers, "items.update", async (event: eventPayload<Js.Json.t>, _ctx: hookContext): unit => {
    if shouldSync(event.collection) {
      switch (event.payload, event.keys) {
      | (Some(data), Some(keys)) =>
        try {
          let _ = await Promise.all(
            keys->Array.map(key => client.update(event.collection, data, key))
          )
          ()
        } catch {
        | _ => ()
        }
      | _ => ()
      }
    }
  })

  // items.delete handler
  Js.Dict.set(actionHandlers, "items.delete", async (event: eventPayload<Js.Json.t>, _ctx: hookContext): unit => {
    if shouldSync(event.collection) {
      switch event.keys {
      | Some(keys) =>
        try {
          let _ = await Promise.all(
            keys->Array.map(key => client.delete(event.collection, key))
          )
          ()
        } catch {
        | _ => ()
        }
      | None => ()
      }
    }
  })

  {
    filter: Js.Dict.empty(),
    action: actionHandlers,
  }
}

/** Export hook */
let default = createHook
