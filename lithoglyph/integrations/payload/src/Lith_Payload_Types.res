// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Payload CMS Adapter Types
 *
 * Type definitions for Payload CMS integration
 */

/** Payload hook arguments */
type hookArgs<'doc> = {
  doc: 'doc,
  previousDoc: option<'doc>,
  collection: collectionConfig,
  operation: hookOperation,
  context: hookContext,
}
and collectionConfig = {
  slug: string,
  labels: collectionLabels,
}
and collectionLabels = {
  singular: string,
  plural: string,
}
and hookOperation =
  | Create
  | Update
  | Delete
  | Read
and hookContext = {
  payload: payloadInstance,
}
and payloadInstance = {
  logger: payloadLogger,
  config: payloadConfig,
}
and payloadLogger = {
  info: string => unit,
  warn: string => unit,
  error: string => unit,
}
and payloadConfig = {
  custom: option<customConfig>,
}
and customConfig

/** Plugin configuration */
type pluginConfig = {
  lithUrl: string,
  apiKey: option<string>,
  collections: array<collectionMapping>,
  enabled: bool,
}
and collectionMapping = {
  payloadSlug: string,
  lithCollection: string,
  syncMode: syncMode,
  excludeFields: array<string>,
}
and syncMode =
  | Bidirectional
  | PayloadToLith
  | LithToPayload

/** Hook result */
type hookResult<'doc> = {
  doc: 'doc,
}

/** Sync result */
type syncResult = {
  success: bool,
  collection: string,
  operation: string,
  error: option<string>,
}

/** Parse sync mode */
let parseSyncMode = (str: string): syncMode =>
  switch String.toLowerCase(str) {
  | "bidirectional" => Bidirectional
  | "payload-to-lith" | "payloadtolith" => PayloadToLith
  | "lith-to-payload" | "lithtopayload" => LithToPayload
  | _ => Bidirectional
  }

/** Sync mode to string */
let syncModeToString = (mode: syncMode): string =>
  switch mode {
  | Bidirectional => "bidirectional"
  | PayloadToLith => "payload-to-lith"
  | LithToPayload => "lith-to-payload"
  }

/** Operation to string */
let operationToString = (op: hookOperation): string =>
  switch op {
  | Create => "create"
  | Update => "update"
  | Delete => "delete"
  | Read => "read"
  }
