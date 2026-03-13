// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Client for Strapi
 *
 * HTTP client wrapper for Lith API within Strapi context
 */

open Lith_Strapi_Types

/** Node.js fetch binding */
@val external fetch: (string, {..}) => promise<{..}> = "fetch"

/** Create Lith client */
let make = (~baseUrl: string, ~apiKey: option<string>=?): lithClient => {
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
    query: async (gql: string): queryResult => {
      let body = Js.Json.object_(
        Js.Dict.fromArray([("gql", Js.Json.string(gql))])
      )
      let result = await request("POST", "/v1/query", Some(body))
      {
        rows: result["rows"],
        rowCount: result["rowCount"],
        affectedCount: result["affectedCount"],
      }
    },

    insert: async (collection: string, document: Js.Json.t): queryResult => {
      let gql = `INSERT INTO ${collection} ${Js.Json.stringify(document)}`
      let body = Js.Json.object_(
        Js.Dict.fromArray([("gql", Js.Json.string(gql))])
      )
      let result = await request("POST", "/v1/query", Some(body))
      {
        rows: result["rows"],
        rowCount: result["rowCount"],
        affectedCount: result["affectedCount"],
      }
    },

    update: async (collection: string, document: Js.Json.t, id: string): queryResult => {
      let setClause = Js.Json.stringify(document)
      let gql = `UPDATE ${collection} SET ${setClause} WHERE id = "${id}"`
      let body = Js.Json.object_(
        Js.Dict.fromArray([("gql", Js.Json.string(gql))])
      )
      let result = await request("POST", "/v1/query", Some(body))
      {
        rows: result["rows"],
        rowCount: result["rowCount"],
        affectedCount: result["affectedCount"],
      }
    },

    delete: async (collection: string, id: string): queryResult => {
      let gql = `DELETE FROM ${collection} WHERE id = "${id}"`
      let body = Js.Json.object_(
        Js.Dict.fromArray([("gql", Js.Json.string(gql))])
      )
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

/** Create client from Strapi config */
let fromStrapiConfig = (config: pluginConfig): lithClient => {
  make(~baseUrl=config.lithUrl, ~apiKey=config.apiKey)
}
