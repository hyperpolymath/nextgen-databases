// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Directus Extension Types
 *
 * Type definitions for Directus integration
 */

/** Directus hook context */
type hookContext = {
  database: knex,
  schema: directusSchema,
  accountability: option<accountability>,
}
and knex
and directusSchema = {
  collections: Js.Dict.t<collectionSchema>,
}
and collectionSchema = {
  collection: string,
  fields: Js.Dict.t<fieldSchema>,
}
and fieldSchema = {
  field: string,
  fieldType: string,
  nullable: bool,
}
and accountability = {
  user: option<string>,
  role: option<string>,
  admin: bool,
}

/** Directus event types */
type eventType =
  | ItemsCreate
  | ItemsUpdate
  | ItemsDelete
  | ItemsRead

/** Event payload */
type eventPayload<'a> = {
  event: string,
  collection: string,
  key: option<string>,
  keys: option<array<string>>,
  payload: option<'a>,
}

/** Extension configuration */
type extensionConfig = {
  lithUrl: string,
  apiKey: option<string>,
  syncCollections: array<string>,
  excludeCollections: array<string>,
  syncMode: syncMode,
}
and syncMode =
  | Realtime
  | Batch
  | Manual

/** Sync result */
type syncResult = {
  success: bool,
  collection: string,
  operation: string,
  itemCount: int,
  error: option<string>,
}

/** Lith client */
type lithClient = {
  query: string => promise<queryResult>,
  insert: (string, Js.Json.t) => promise<queryResult>,
  update: (string, Js.Json.t, string) => promise<queryResult>,
  delete: (string, string) => promise<queryResult>,
  health: unit => promise<healthResponse>,
}
and queryResult = {
  rows: array<Js.Json.t>,
  rowCount: int,
  affectedCount: option<int>,
}
and healthResponse = {
  status: string,
  version: string,
}

/** Event to string */
let eventToString = (event: eventType): string =>
  switch event {
  | ItemsCreate => "items.create"
  | ItemsUpdate => "items.update"
  | ItemsDelete => "items.delete"
  | ItemsRead => "items.read"
  }

/** Parse event from string */
let parseEvent = (str: string): option<eventType> =>
  switch str {
  | "items.create" => Some(ItemsCreate)
  | "items.update" => Some(ItemsUpdate)
  | "items.delete" => Some(ItemsDelete)
  | "items.read" => Some(ItemsRead)
  | _ => None
  }

/** Parse sync mode */
let parseSyncMode = (str: string): syncMode =>
  switch String.toLowerCase(str) {
  | "realtime" => Realtime
  | "batch" => Batch
  | "manual" => Manual
  | _ => Realtime
  }
