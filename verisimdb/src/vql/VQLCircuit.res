// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Circuit DSL — Defines types for custom ZKP circuits in VQL.
//
// Usage in VQL:
//   PROOF CUSTOM "circuit-name" WITH (threshold=0.5, min_score=0.1)

/// Gate types available in custom circuits
type gateType =
  | AND
  | OR
  | XOR
  | NOT
  | LinearCombination

/// A wire in the circuit (carries a signal)
type wire = {
  name: string,
  isPublic: bool,
  isOutput: bool,
}

/// A gate connecting input wires to an output wire
type gate = {
  gateType: gateType,
  inputs: array<string>,
  output: string,
}

/// A constraint in the circuit (R1CS: A * B = C)
type constraint = {
  description: string,
  a: array<(int, float)>,
  b: array<(int, float)>,
  c: array<(int, float)>,
}

/// A circuit definition from VQL PROOF CUSTOM clause
type circuitDef = {
  name: string,
  wires: array<wire>,
  gates: array<gate>,
  parameters: array<string>,
}

/// Parameters passed via VQL WITH clause
type circuitParams = {
  values: Js.Dict.t<string>,
}

/// Result of a custom circuit verification
type verificationResult = {
  circuitName: string,
  verified: bool,
  publicInputs: array<float>,
  constraintsSatisfied: int,
  totalConstraints: int,
}

/// Parse a PROOF CUSTOM clause from VQL
let parseCustomProof = (circuitName: string, withParams: array<(string, string)>): (string, circuitParams) => {
  let dict = Js.Dict.empty()
  withParams->Array.forEach(((key, value)) => {
    Js.Dict.set(dict, key, value)
  })
  (circuitName, {values: dict})
}

/// Serialize a circuit definition to JSON for the Rust bridge
let serializeCircuitDef = (def: circuitDef): string => {
  Js.Json.stringifyAny(def)->Option.getOr("{}")
}
