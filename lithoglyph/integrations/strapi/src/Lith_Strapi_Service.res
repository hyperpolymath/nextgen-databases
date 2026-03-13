// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Strapi Service
 *
 * Service layer for Lith synchronization
 */

open Lith_Strapi_Types
open Lith_Strapi_Client

/** Sync service state */
type syncState = {
  mutable client: option<lithClient>,
  mutable config: option<pluginConfig>,
  mutable mappings: Js.Dict.t<collectionMapping>,
}

/** Global sync state */
let state: syncState = {
  client: None,
  config: None,
  mappings: Js.Dict.empty(),
}

/** Initialize service with config */
let initialize = (config: pluginConfig): unit => {
  state.config = Some(config)
  state.client = Some(fromStrapiConfig(config))

  // Build mappings lookup
  let mappings = Js.Dict.empty()
  config.collections->Array.forEach(mapping => {
    Js.Dict.set(mappings, mapping.strapiModel, mapping)
  })
  state.mappings = mappings
}

/** Get Lith collection for Strapi model */
let getLithCollection = (strapiModel: string): option<string> => {
  switch Js.Dict.get(state.mappings, strapiModel) {
  | Some(mapping) => Some(mapping.lithCollection)
  | None => None
  }
}

/** Check if model should sync to Lith */
let shouldSyncToLith = (strapiModel: string): bool => {
  switch Js.Dict.get(state.mappings, strapiModel) {
  | Some(mapping) =>
    switch mapping.syncMode {
    | Bidirectional | StrapiToLith => true
    | LithToStrapi => false
    }
  | None => false
  }
}

/** Check if model should sync from Lith */
let shouldSyncFromLith = (strapiModel: string): bool => {
  switch Js.Dict.get(state.mappings, strapiModel) {
  | Some(mapping) =>
    switch mapping.syncMode {
    | Bidirectional | LithToStrapi => true
    | StrapiToLith => false
    }
  | None => false
  }
}

/** Sync create event to Lith */
let syncCreate = async (model: string, data: Js.Json.t): result<queryResult, string> => {
  switch (state.client, getLithCollection(model)) {
  | (Some(client), Some(collection)) =>
    if shouldSyncToLith(model) {
      try {
        let result = await client.insert(collection, data)
        Ok(result)
      } catch {
      | Js.Exn.Error(e) =>
        let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
        Error(`Failed to sync create to Lith: ${msg}`)
      }
    } else {
      Error("Sync to Lith disabled for this model")
    }
  | (None, _) => Error("Lith client not initialized")
  | (_, None) => Error(`No Lith collection mapped for ${model}`)
  }
}

/** Sync update event to Lith */
let syncUpdate = async (model: string, data: Js.Json.t, id: string): result<queryResult, string> => {
  switch (state.client, getLithCollection(model)) {
  | (Some(client), Some(collection)) =>
    if shouldSyncToLith(model) {
      try {
        let result = await client.update(collection, data, id)
        Ok(result)
      } catch {
      | Js.Exn.Error(e) =>
        let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
        Error(`Failed to sync update to Lith: ${msg}`)
      }
    } else {
      Error("Sync to Lith disabled for this model")
    }
  | (None, _) => Error("Lith client not initialized")
  | (_, None) => Error(`No Lith collection mapped for ${model}`)
  }
}

/** Sync delete event to Lith */
let syncDelete = async (model: string, id: string): result<queryResult, string> => {
  switch (state.client, getLithCollection(model)) {
  | (Some(client), Some(collection)) =>
    if shouldSyncToLith(model) {
      try {
        let result = await client.delete(collection, id)
        Ok(result)
      } catch {
      | Js.Exn.Error(e) =>
        let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
        Error(`Failed to sync delete to Lith: ${msg}`)
      }
    } else {
      Error("Sync to Lith disabled for this model")
    }
  | (None, _) => Error("Lith client not initialized")
  | (_, None) => Error(`No Lith collection mapped for ${model}`)
  }
}

/** Query Lith for model data */
let queryLith = async (model: string, ~where: option<string>=?, ~limit: option<int>=?): result<array<Js.Json.t>, string> => {
  switch (state.client, getLithCollection(model)) {
  | (Some(client), Some(collection)) =>
    try {
      let whereClause = where->Option.map(w => ` WHERE ${w}`)->Option.getOr("")
      let limitClause = limit->Option.map(l => ` LIMIT ${Int.toString(l)}`)->Option.getOr("")
      let gql = `SELECT * FROM ${collection}${whereClause}${limitClause}`
      let result = await client.query(gql)
      Ok(result.rows)
    } catch {
    | Js.Exn.Error(e) =>
      let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
      Error(`Failed to query Lith: ${msg}`)
    }
  | (None, _) => Error("Lith client not initialized")
  | (_, None) => Error(`No Lith collection mapped for ${model}`)
  }
}

/** Check Lith health */
let checkHealth = async (): result<healthResponse, string> => {
  switch state.client {
  | Some(client) =>
    try {
      let health = await client.health()
      Ok(health)
    } catch {
    | Js.Exn.Error(e) =>
      let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
      Error(`Lith health check failed: ${msg}`)
    }
  | None => Error("Lith client not initialized")
  }
}
