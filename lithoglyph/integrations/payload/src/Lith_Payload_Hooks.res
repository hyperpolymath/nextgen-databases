// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Payload CMS Hooks
 *
 * Collection hooks for syncing Payload content to Lith
 */

open Lith_Payload_Types

/** Node.js fetch binding */
@val external fetch: (string, {..}) => promise<{..}> = "fetch"

/** Lith client */
type lithClient = {
  insert: (string, Js.Json.t) => promise<unit>,
  update: (string, Js.Json.t, string) => promise<unit>,
  delete: (string, string) => promise<unit>,
}

/** Create Lith client */
let makeClient = (config: pluginConfig): lithClient => {
  let headers = switch config.apiKey {
  | Some(key) => {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-API-Key": key,
    }
  | None => {
      "Content-Type": "application/json",
      "Accept": "application/json",
    }
  }

  let request = async (gql: string): Js.Json.t => {
    let url = config.lithUrl ++ "/v1/query"
    let body = Js.Json.object_(Js.Dict.fromArray([("gql", Js.Json.string(gql))]))
    let options = {
      "method": "POST",
      "headers": headers,
      "body": Js.Json.stringify(body),
    }
    let response = await fetch(url, options)
    let json = await response["json"]()
    json
  }

  {
    insert: async (collection: string, document: Js.Json.t): unit => {
      let gql = `INSERT INTO ${collection} ${Js.Json.stringify(document)}`
      let _ = await request(gql)
      ()
    },

    update: async (collection: string, document: Js.Json.t, id: string): unit => {
      let setClause = Js.Json.stringify(document)
      let gql = `UPDATE ${collection} SET ${setClause} WHERE id = "${id}"`
      let _ = await request(gql)
      ()
    },

    delete: async (collection: string, id: string): unit => {
      let gql = `DELETE FROM ${collection} WHERE id = "${id}"`
      let _ = await request(gql)
      ()
    },
  }
}

/** Global plugin state */
type pluginState = {
  mutable config: option<pluginConfig>,
  mutable client: option<lithClient>,
  mutable mappings: Js.Dict.t<collectionMapping>,
}

let state: pluginState = {
  config: None,
  client: None,
  mappings: Js.Dict.empty(),
}

/** Initialize plugin */
let initialize = (config: pluginConfig): unit => {
  state.config = Some(config)
  state.client = Some(makeClient(config))

  // Build mappings lookup
  let mappings = Js.Dict.empty()
  config.collections->Array.forEach(mapping => {
    Js.Dict.set(mappings, mapping.payloadSlug, mapping)
  })
  state.mappings = mappings
}

/** Get Lith collection for Payload slug */
let getLithCollection = (payloadSlug: string): option<string> => {
  switch Js.Dict.get(state.mappings, payloadSlug) {
  | Some(mapping) => Some(mapping.lithCollection)
  | None => None
  }
}

/** Check if collection should sync to Lith */
let shouldSyncToLith = (payloadSlug: string): bool => {
  switch Js.Dict.get(state.mappings, payloadSlug) {
  | Some(mapping) =>
    switch mapping.syncMode {
    | Bidirectional | PayloadToLith => true
    | LithToPayload => false
    }
  | None => false
  }
}

/** Filter excluded fields from document */
let filterExcludedFields = (doc: Js.Json.t, excludeFields: array<string>): Js.Json.t => {
  switch Js.Json.decodeObject(doc) {
  | Some(obj) =>
    let filtered = Js.Dict.empty()
    Js.Dict.keys(obj)->Array.forEach(key => {
      if !excludeFields->Array.includes(key) {
        switch Js.Dict.get(obj, key) {
        | Some(value) => Js.Dict.set(filtered, key, value)
        | None => ()
        }
      }
    })
    Js.Json.object_(filtered)
  | None => doc
  }
}

/** Get document ID */
let getDocId = (doc: Js.Json.t): option<string> => {
  switch Js.Json.decodeObject(doc) {
  | Some(obj) =>
    switch Js.Dict.get(obj, "id") {
    | Some(idJson) =>
      switch Js.Json.decodeString(idJson) {
      | Some(s) => Some(s)
      | None =>
        switch Js.Json.decodeNumber(idJson) {
        | Some(n) => Some(Int.toString(Float.toInt(n)))
        | None => None
        }
      }
    | None => None
    }
  | None => None
  }
}

/** After change hook (create/update) */
let afterChangeHook = async (args: hookArgs<Js.Json.t>): hookResult<Js.Json.t> => {
  let slug = args.collection.slug

  if shouldSyncToLith(slug) {
    switch (state.client, getLithCollection(slug)) {
    | (Some(client), Some(collection)) =>
      let mapping = Js.Dict.get(state.mappings, slug)
      let excludeFields = mapping->Option.map(m => m.excludeFields)->Option.getOr([])
      let filteredDoc = filterExcludedFields(args.doc, excludeFields)

      switch getDocId(args.doc) {
      | Some(id) =>
        try {
          switch args.operation {
          | Create => await client.insert(collection, filteredDoc)
          | Update => await client.update(collection, filteredDoc, id)
          | _ => ()
          }
        } catch {
        | _ => ()
        }
      | None => ()
      }
    | _ => ()
    }
  }

  {doc: args.doc}
}

/** After delete hook */
let afterDeleteHook = async (args: hookArgs<Js.Json.t>): hookResult<Js.Json.t> => {
  let slug = args.collection.slug

  if shouldSyncToLith(slug) {
    switch (state.client, getLithCollection(slug)) {
    | (Some(client), Some(collection)) =>
      switch getDocId(args.doc) {
      | Some(id) =>
        try {
          await client.delete(collection, id)
        } catch {
        | _ => ()
        }
      | None => ()
      }
    | _ => ()
    }
  }

  {doc: args.doc}
}

/** Export hooks */
let hooks = {
  "afterChange": afterChangeHook,
  "afterDelete": afterDeleteHook,
}
