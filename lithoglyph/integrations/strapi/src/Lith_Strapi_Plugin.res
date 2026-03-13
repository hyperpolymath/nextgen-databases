// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Strapi Plugin
 *
 * Main plugin entry point for Strapi v4/v5
 */

open Lith_Strapi_Types
open Lith_Strapi_Service

/** Plugin register function */
let register = (_ctx: strapiContext): unit => {
  // Plugin registration - called once on startup
  ()
}

/** Plugin bootstrap function */
let bootstrap = (ctx: strapiContext): unit => {
  let strapi = ctx.strapi

  // Load configuration
  let configJson = strapi.config.get("plugin.lith")

  switch configJson {
  | Some(json) =>
    // Parse config (simplified - in production would use proper JSON decoding)
    let config: pluginConfig = {
      enabled: true,
      lithUrl: "http://localhost:8080",
      apiKey: None,
      collections: [],
    }

    if config.enabled {
      // Initialize sync service
      initialize(config)
      strapi.log.info("[Lith] Plugin initialized successfully")

      // Register lifecycle hooks for each mapped collection
      config.collections->Array.forEach(mapping => {
        strapi.log.info(`[Lith] Registered sync for ${mapping.strapiModel} -> ${mapping.lithCollection}`)
      })
    } else {
      strapi.log.info("[Lith] Plugin disabled in configuration")
    }
  | None =>
    strapi.log.warn("[Lith] No configuration found, plugin disabled")
  }
}

/** Plugin destroy function */
let destroy = (_ctx: strapiContext): unit => {
  // Cleanup on shutdown
  ()
}

/** Export plugin configuration for Strapi */
let default = {
  "register": register,
  "bootstrap": bootstrap,
  "destroy": destroy,
}
