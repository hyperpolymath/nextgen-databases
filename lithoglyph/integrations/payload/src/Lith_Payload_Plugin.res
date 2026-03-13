// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Payload CMS Plugin
 *
 * Plugin entry point for Payload CMS
 */

open Lith_Payload_Types
open Lith_Payload_Hooks

/** Payload plugin type */
type payloadPlugin = payloadConfig => payloadConfig

/** Create Lith plugin for Payload */
let lithPlugin = (pluginConfig: pluginConfig): payloadPlugin => {
  // Initialize the sync state
  if pluginConfig.enabled {
    initialize(pluginConfig)
  }

  // Return config modifier
  (incomingConfig: payloadConfig): payloadConfig => {
    if !pluginConfig.enabled {
      incomingConfig
    } else {
      // In a real implementation, this would modify the config
      // to add hooks to each collection specified in pluginConfig.collections
      //
      // Example:
      // incomingConfig.collections = incomingConfig.collections.map(collection => {
      //   if (shouldSyncCollection(collection.slug)) {
      //     return {
      //       ...collection,
      //       hooks: {
      //         ...collection.hooks,
      //         afterChange: [...(collection.hooks?.afterChange || []), afterChangeHook],
      //         afterDelete: [...(collection.hooks?.afterDelete || []), afterDeleteHook],
      //       }
      //     }
      //   }
      //   return collection
      // })

      incomingConfig
    }
  }
}

/** Default export */
let default = lithPlugin

/** Helper to create config from environment */
let configFromEnv = (): pluginConfig => {
  {
    lithUrl: %raw(`process.env.LITH_URL || "http://localhost:8080"`),
    apiKey: %raw(`process.env.LITH_API_KEY || undefined`),
    collections: [],
    enabled: %raw(`process.env.LITH_ENABLED !== "false"`),
  }
}
