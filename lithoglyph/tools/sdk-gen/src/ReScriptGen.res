// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * ReScript Code Generator
 *
 * Generates ReScript client code from API specification
 */

open ApiSpec
open Generator

let name = "ReScript"
let fileExtension = ".res"

/** Convert data type to ReScript type string */
let rec dataTypeToRescript = (dt: dataType): string =>
  switch dt {
  | String => "string"
  | Int => "int"
  | Float => "float"
  | Bool => "bool"
  | Array(inner) => `array<${dataTypeToRescript(inner)}>`
  | Object(_) => "Js.Json.t"
  | Optional(inner) => `option<${dataTypeToRescript(inner)}>`
  | Enum(name, _) => uncapitalize(name)
  | Ref(name) => uncapitalize(name)
  }

/** Generate enum type */
let generateEnum = (name: string, values: array<string>): string => {
  let variants = values
    ->Array.map(v => `  | ${capitalize(String.replaceAll(v, "-", "_"))}`)
    ->Array.joinWith("\n")

  `type ${uncapitalize(name)} =\n${variants}`
}

/** Generate record type */
let generateRecord = (name: string, fields: array<(string, dataType)>): string => {
  let fieldStrs = fields
    ->Array.map(((fieldName, fieldType)) =>
      `  ${fieldName}: ${dataTypeToRescript(fieldType)},`
    )
    ->Array.joinWith("\n")

  `type ${uncapitalize(name)} = {\n${fieldStrs}\n}`
}

/** Generate type definition */
let generateTypeDef = (typeDef: typeDef): string => {
  let desc = `/** ${typeDef.description} */\n`
  let typeStr = switch typeDef.dataType {
  | Enum(name, values) => generateEnum(name, values)
  | Object(fields) => generateRecord(typeDef.name, fields)
  | _ => `type ${uncapitalize(typeDef.name)} = ${dataTypeToRescript(typeDef.dataType)}`
  }
  desc ++ typeStr
}

/** Generate types file */
let generateTypesFile = (spec: apiSpec): generatedFile => {
  let header = `// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Types
 *
 * Auto-generated from API specification v${spec.version}
 */

`

  let types = spec.types
    ->Array.map(generateTypeDef)
    ->Array.joinWith("\n\n")

  {
    path: "Lith_Types.res",
    content: header ++ types ++ "\n",
  }
}

/** Generate endpoint function */
let generateEndpoint = (endpoint: endpoint): string => {
  let methodStr = methodToString(endpoint.method)
  let desc = `/** ${endpoint.description} */`

  // Build parameter list
  let params = endpoint.parameters
    ->Array.filter(p => p.required)
    ->Array.map(p => `${p.name}: ${dataTypeToRescript(p.dataType)}`)

  let optParams = endpoint.parameters
    ->Array.filter(p => !p.required)
    ->Array.map(p => `~${p.name}: ${dataTypeToRescript(p.dataType)}=?`)

  let allParams = Array.concat(params, optParams)
  let paramStr = if Array.length(allParams) > 0 {
    ", " ++ Array.joinWith(allParams, ", ")
  } else {
    ""
  }

  let returnType = dataTypeToRescript(endpoint.responseType)

  `${desc}
let ${endpoint.name} = async (client: t${paramStr}): ${returnType} => {
  let path = "${endpoint.path}"
  let response = await request(client, "${methodStr}", path, None)
  response
}`
}

/** Generate client file */
let generateClientFile = (spec: apiSpec): generatedFile => {
  let header = `// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Client
 *
 * Auto-generated from API specification v${spec.version}
 */

open Lith_Types

/** Client configuration */
type config = {
  baseUrl: string,
  apiKey: option<string>,
  bearerToken: option<string>,
}

/** Client instance */
type t = {
  config: config,
}

/** Create a new client */
let make = (~baseUrl: string, ~apiKey: option<string>=?, ~bearerToken: option<string>=?): t => {
  {
    config: {
      baseUrl,
      apiKey,
      bearerToken,
    },
  }
}

/** Create client from environment */
let fromEnv = (): t => {
  make(
    ~baseUrl=Deno.env->Deno.Env.get("LITH_URL")->Option.getOr("http://localhost:8080"),
    ~apiKey=Deno.env->Deno.Env.get("LITH_API_KEY"),
  )
}

/** Internal request helper */
let request = async (client: t, method: string, path: string, body: option<Js.Json.t>): Js.Json.t => {
  let url = client.config.baseUrl ++ path
  let headers = Js.Dict.empty()
  Js.Dict.set(headers, "Content-Type", "application/json")
  Js.Dict.set(headers, "Accept", "application/json")

  switch client.config.apiKey {
  | Some(key) => Js.Dict.set(headers, "X-API-Key", key)
  | None => ()
  }

  switch client.config.bearerToken {
  | Some(token) => Js.Dict.set(headers, "Authorization", "Bearer " ++ token)
  | None => ()
  }

  let options = {
    "method": method,
    "headers": headers,
    "body": body->Option.map(Js.Json.stringify),
  }

  let response = await Fetch.fetch(url, options)
  await Fetch.Response.json(response)
}

`

  let endpoints = spec.endpoints
    ->Array.map(generateEndpoint)
    ->Array.joinWith("\n\n")

  {
    path: "Lith.res",
    content: header ++ endpoints ++ "\n",
  }
}

/** Generate all files */
let generate = (spec: apiSpec): array<generatedFile> => {
  [
    generateTypesFile(spec),
    generateClientFile(spec),
  ]
}
