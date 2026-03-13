// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Fuzz Mutators
 *
 * Input mutation strategies for fuzz testing
 */

open Lith_Fuzz_Types

/** Random number generator */
type rng = {mutable seed: int}

/** Create RNG */
let makeRng = (seed: int): rng => {seed: seed}

/** Generate next random int */
let nextInt = (rng: rng): int => {
  rng.seed = land(rng.seed * 1103515245 + 12345, 0x7FFFFFFF)
  rng.seed
}

/** Random int in range */
let intInRange = (rng: rng, ~min: int, ~max: int): int => {
  let range = max - min
  if range <= 0 {
    min
  } else {
    min + mod(abs(nextInt(rng)), range)
  }
}

/** Random byte (0-255) */
let randomByte = (rng: rng): int => {
  intInRange(rng, ~min=0, ~max=256)
}

/** Pick random element */
let pick = (rng: rng, arr: array<'a>): option<'a> => {
  let len = Array.length(arr)
  if len == 0 {
    None
  } else {
    arr[intInRange(rng, ~min=0, ~max=len)]
  }
}

/** Convert string to byte array */
let toBytes = (s: string): array<int> => {
  let len = String.length(s)
  let result = []
  for i in 0 to len - 1 {
    result->Array.push(String.charCodeAt(s, i)->Float.toInt)->ignore
  }
  result
}

/** Convert byte array to string */
let fromBytes = (bytes: array<int>): string => {
  bytes->Array.map(b => String.fromCharCode(b))->Array.join("")
}

/** Bit flip mutation */
let bitFlip = (rng: rng, input: string): string => {
  let bytes = toBytes(input)
  let len = Array.length(bytes)
  if len == 0 {
    input
  } else {
    let pos = intInRange(rng, ~min=0, ~max=len)
    let bit = intInRange(rng, ~min=0, ~max=8)
    switch bytes[pos] {
    | Some(b) => {
        bytes->Array.setUnsafe(pos, lxor(b, lsl(1, bit)))
        fromBytes(bytes)
      }
    | None => input
    }
  }
}

/** Byte flip mutation */
let byteFlip = (rng: rng, input: string): string => {
  let bytes = toBytes(input)
  let len = Array.length(bytes)
  if len == 0 {
    input
  } else {
    let pos = intInRange(rng, ~min=0, ~max=len)
    bytes->Array.setUnsafe(pos, lxor(bytes[pos]->Option.getOr(0), 255))
    fromBytes(bytes)
  }
}

/** Byte insert mutation */
let byteInsert = (rng: rng, input: string): string => {
  let bytes = toBytes(input)
  let len = Array.length(bytes)
  let pos = intInRange(rng, ~min=0, ~max=len + 1)
  let newByte = randomByte(rng)

  let result = []
  for i in 0 to len - 1 {
    if i == pos {
      result->Array.push(newByte)->ignore
    }
    switch bytes[i] {
    | Some(b) => result->Array.push(b)->ignore
    | None => ()
    }
  }
  if pos == len {
    result->Array.push(newByte)->ignore
  }

  fromBytes(result)
}

/** Byte delete mutation */
let byteDelete = (rng: rng, input: string): string => {
  let bytes = toBytes(input)
  let len = Array.length(bytes)
  if len <= 1 {
    input
  } else {
    let pos = intInRange(rng, ~min=0, ~max=len)
    let result = []
    for i in 0 to len - 1 {
      if i != pos {
        switch bytes[i] {
        | Some(b) => result->Array.push(b)->ignore
        | None => ()
        }
      }
    }
    fromBytes(result)
  }
}

/** Byte replace mutation */
let byteReplace = (rng: rng, input: string): string => {
  let bytes = toBytes(input)
  let len = Array.length(bytes)
  if len == 0 {
    input
  } else {
    let pos = intInRange(rng, ~min=0, ~max=len)
    bytes->Array.setUnsafe(pos, randomByte(rng))
    fromBytes(bytes)
  }
}

/** GQL dictionary for dictionary mutation */
let gqlDictionary: array<string> = [
  "SELECT", "INSERT", "UPDATE", "DELETE", "FROM", "INTO", "SET", "WHERE",
  "CREATE", "DROP", "COLLECTION", "EDGE", "EXPLAIN", "ANALYZE", "VERBOSE",
  "INTROSPECT", "SCHEMA", "CONSTRAINTS", "COLLECTIONS", "JOURNAL",
  "LIMIT", "OFFSET", "ORDER", "BY", "ASC", "DESC", "AND", "OR", "NOT",
  "WITH", "PROVENANCE", "TRAVERSE", "OUTBOUND", "INBOUND", "ANY",
  "null", "true", "false", "=", "!=", "<", "<=", ">", ">=", "LIKE", "IN",
  "{", "}", "[", "]", "(", ")", ",", ":", "\"", "'", "*",
]

/** Dictionary mutation */
let dictionary = (rng: rng, input: string): string => {
  let word = pick(rng, gqlDictionary)->Option.getOr("SELECT")
  let len = String.length(input)
  if len == 0 {
    word
  } else {
    let pos = intInRange(rng, ~min=0, ~max=len)
    let before = String.slice(input, ~start=0, ~end=pos)
    let after = String.sliceToEnd(input, ~start=pos)
    before ++ word ++ after
  }
}

/** Arithmetic mutation (add/subtract small values) */
let arithmetic = (rng: rng, input: string): string => {
  let bytes = toBytes(input)
  let len = Array.length(bytes)
  if len == 0 {
    input
  } else {
    let pos = intInRange(rng, ~min=0, ~max=len)
    let delta = intInRange(rng, ~min=-35, ~max=36)
    switch bytes[pos] {
    | Some(b) => {
        let newVal = mod(b + delta + 256, 256)
        bytes->Array.setUnsafe(pos, newVal)
        fromBytes(bytes)
      }
    | None => input
    }
  }
}

/** Token splice mutation (combine parts of corpus) */
let tokenSplice = (rng: rng, input: string, corpus: array<string>): string => {
  if Array.length(corpus) == 0 {
    input
  } else {
    let other = pick(rng, corpus)->Option.getOr(input)
    let len1 = String.length(input)
    let len2 = String.length(other)

    if len1 == 0 || len2 == 0 {
      input
    } else {
      let pos1 = intInRange(rng, ~min=0, ~max=len1)
      let pos2 = intInRange(rng, ~min=0, ~max=len2)
      let before = String.slice(input, ~start=0, ~end=pos1)
      let after = String.sliceToEnd(other, ~start=pos2)
      before ++ after
    }
  }
}

/** Apply a mutation strategy */
let mutate = (rng: rng, strategy: mutationStrategy, input: string, corpus: array<string>): string => {
  switch strategy {
  | BitFlip => bitFlip(rng, input)
  | ByteFlip => byteFlip(rng, input)
  | ByteInsert => byteInsert(rng, input)
  | ByteDelete => byteDelete(rng, input)
  | ByteReplace => byteReplace(rng, input)
  | TokenSplice => tokenSplice(rng, input, corpus)
  | Arithmetic => arithmetic(rng, input)
  | Dictionary => dictionary(rng, input)
  }
}

/** Apply random mutation */
let mutateRandom = (rng: rng, input: string, corpus: array<string>): string => {
  let strategy = pick(rng, allStrategies)->Option.getOr(ByteReplace)
  mutate(rng, strategy, input, corpus)
}

/** Generate completely random input */
let generateRandom = (rng: rng, maxLen: int): string => {
  let len = intInRange(rng, ~min=1, ~max=maxLen + 1)
  let bytes = []
  for _ in 1 to len {
    // Bias toward printable ASCII
    let b = if intInRange(rng, ~min=0, ~max=10) < 8 {
      intInRange(rng, ~min=32, ~max=127) // Printable
    } else {
      randomByte(rng) // Any byte
    }
    bytes->Array.push(b)->ignore
  }
  fromBytes(bytes)
}
