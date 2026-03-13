// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Shared Types

module FieldType = {
  type t =
    | Number({min: option<int>, max: option<int>})
    | Text({required: bool})
    | Confidence
    | PromptScores

  let toString = (t: t) =>
    switch t {
    | Number(_) => "number"
    | Text(_) => "text"
    | Confidence => "confidence"
    | PromptScores => "prompt_scores"
    }
}

module Field = {
  type t = {
    name: string,
    fieldType: FieldType.t,
  }
}

module Collection = {
  type t = {
    name: string,
    fields: array<Field.t>,
  }

  let empty = () => {
    name: "",
    fields: [],
  }
}

// Tauri command bindings
module Tauri = {
  type invokeResult<'a>

  @module("@tauri-apps/api/core")
  external invoke: (string, 'a) => promise<'b> = "invoke"
}

// Validation state for FBQLdt preview
type validationState =
  | NotValidated
  | Validating
  | Valid(array<string>)
  | Invalid(array<string>)

// Service status types
module ServiceStatus = {
  type serviceInfo = {
    name: string,
    available: bool,
    version: option<string>,
    message: string,
    blocking_milestone: option<string>,
  }

  type featureAvailability = {
    schema_builder: bool,
    fbqldt_generation: bool,
    fbqldt_validation: bool,
    query_execution: bool,
    data_entry: bool,
    normalization: bool,
    proof_assistant: bool,
  }

  type t = {
    lith: serviceInfo,
    fbqldt: serviceInfo,
    overall_ready: bool,
    features: featureAvailability,
  }
}

// App info type
module AppInfo = {
  type t = {
    name: string,
    version: string,
    description: string,
    license: string,
    repository: string,
  }
}
