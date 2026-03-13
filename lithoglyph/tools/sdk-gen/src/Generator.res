// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Code Generator Interface
 *
 * Defines the interface for language-specific code generators
 */

open ApiSpec

/** Generator output */
type generatedFile = {
  path: string,
  content: string,
}

/** Generator module type */
module type Generator = {
  let name: string
  let fileExtension: string
  let generate: apiSpec => array<generatedFile>
}

/** Helper to convert HTTP method to string */
let methodToString = (method: httpMethod): string =>
  switch method {
  | GET => "GET"
  | POST => "POST"
  | PUT => "PUT"
  | DELETE => "DELETE"
  | PATCH => "PATCH"
  }

/** Helper to capitalize first letter */
let capitalize = (str: string): string => {
  if String.length(str) === 0 {
    str
  } else {
    String.toUpperCase(String.sub(str, 0, 1)) ++ String.sub(str, 1, String.length(str) - 1)
  }
}

/** Helper to lowercase first letter */
let uncapitalize = (str: string): string => {
  if String.length(str) === 0 {
    str
  } else {
    String.toLowerCase(String.sub(str, 0, 1)) ++ String.sub(str, 1, String.length(str) - 1)
  }
}

/** Helper to convert to snake_case */
let toSnakeCase = (str: string): string => {
  let result = ref("")
  for i in 0 to String.length(str) - 1 {
    let char = String.sub(str, i, 1)
    if char >= "A" && char <= "Z" {
      if i > 0 {
        result := result.contents ++ "_"
      }
      result := result.contents ++ String.toLowerCase(char)
    } else {
      result := result.contents ++ char
    }
  }
  result.contents
}
