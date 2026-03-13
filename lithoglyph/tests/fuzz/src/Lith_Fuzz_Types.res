// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Fuzz Test Types
 *
 * Type definitions for fuzz testing
 */

/** Fuzz test configuration */
type fuzzConfig = {
  iterations: int,
  maxInputLength: int,
  seed: option<int>,
  saveCorpus: bool,
  corpusDir: string,
  verbose: bool,
}

/** Default fuzz config */
let defaultConfig: fuzzConfig = {
  iterations: 10000,
  maxInputLength: 1024,
  seed: None,
  saveCorpus: false,
  corpusDir: "./corpus",
  verbose: false,
}

/** Fuzz result for a single input */
type fuzzInputResult =
  | Accepted  // Parser accepted the input
  | Rejected  // Parser rejected with error (expected)
  | Crashed({error: string})  // Parser crashed (bug!)
  | Timeout  // Parser timed out
  | Interesting({reason: string})  // Found something interesting

/** Fuzz session result */
type fuzzResult = {
  iterations: int,
  accepted: int,
  rejected: int,
  crashed: int,
  timeout: int,
  interesting: int,
  crashingInputs: array<string>,
  interestingInputs: array<(string, string)>,
  duration: float,
}

/** Empty fuzz result */
let emptyResult: fuzzResult = {
  iterations: 0,
  accepted: 0,
  rejected: 0,
  crashed: 0,
  timeout: 0,
  interesting: 0,
  crashingInputs: [],
  interestingInputs: [],
  duration: 0.0,
}

/** Mutation strategy */
type mutationStrategy =
  | BitFlip  // Flip random bits
  | ByteFlip  // Flip random bytes
  | ByteInsert  // Insert random bytes
  | ByteDelete  // Delete random bytes
  | ByteReplace  // Replace random bytes
  | TokenSplice  // Splice tokens from corpus
  | Arithmetic  // Add/subtract from bytes
  | Dictionary  // Insert dictionary words

/** All mutation strategies */
let allStrategies: array<mutationStrategy> = [
  BitFlip,
  ByteFlip,
  ByteInsert,
  ByteDelete,
  ByteReplace,
  TokenSplice,
  Arithmetic,
  Dictionary,
]

/** Strategy to string */
let strategyToString = (s: mutationStrategy): string =>
  switch s {
  | BitFlip => "bit-flip"
  | ByteFlip => "byte-flip"
  | ByteInsert => "byte-insert"
  | ByteDelete => "byte-delete"
  | ByteReplace => "byte-replace"
  | TokenSplice => "token-splice"
  | Arithmetic => "arithmetic"
  | Dictionary => "dictionary"
  }
