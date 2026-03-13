// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Data Entry Component (Phase 3)

open Types

// Field validation state
module Validation = {
  type fieldState =
    | NotValidated
    | Valid
    | Invalid(string)
    | Warning(string)

  type t = dict<fieldState>

  let empty = (): t => Dict.make()

  let get = (v: t, field: string): fieldState =>
    v->Dict.get(field)->Option.getOr(NotValidated)

  let set = (v: t, field: string, state: fieldState): t => {
    let copy = Dict.fromArray(Dict.toArray(v))
    copy->Dict.set(field, state)
    copy
  }
}

// Document being entered
module Document = {
  type t = dict<string>

  let empty = (): t => Dict.make()

  let get = (doc: t, field: string): string =>
    doc->Dict.get(field)->Option.getOr("")

  let set = (doc: t, field: string, value: string): t => {
    let copy = Dict.fromArray(Dict.toArray(doc))
    copy->Dict.set(field, value)
    copy
  }
}

// Provenance metadata
module Provenance = {
  type t = {
    source: string,
    rationale: string,
    confidence: int,
    timestamp: string,
  }

  let empty = () => {
    source: "",
    rationale: "",
    confidence: 80,
    timestamp: "",
  }
}

// Field input component with validation
module FieldInput = {
  @react.component
  let make = (
    ~field: Field.t,
    ~value: string,
    ~validation: Validation.fieldState,
    ~onChange: string => unit,
  ) => {
    let (constraintHint, inputType, _inputProps) = switch field.fieldType {
    | FieldType.Number({min, max}) =>
      let hint = switch (min, max) {
      | (Some(lo), Some(hi)) => `Number between ${Int.toString(lo)} and ${Int.toString(hi)}`
      | (Some(lo), None) => `Number >= ${Int.toString(lo)}`
      | (None, Some(hi)) => `Number <= ${Int.toString(hi)}`
      | (None, None) => "Any number"
      }
      (hint, "number", {"min": min, "max": max})
    | FieldType.Text({required}) =>
      let hint = if required { "Required text" } else { "Optional text" }
      (hint, "text", {"min": None, "max": None})
    | FieldType.Confidence =>
      ("Confidence score 0-100", "number", {"min": Some(0), "max": Some(100)})
    | FieldType.PromptScores =>
      ("PROMPT journalism scores", "text", {"min": None, "max": None})
    }

    let validationClass = switch validation {
    | Validation.Valid => "field-valid"
    | Validation.Invalid(_) => "field-invalid"
    | Validation.Warning(_) => "field-warning"
    | Validation.NotValidated => ""
    }

    <div className={`form-group ${validationClass}`}>
      <label htmlFor={field.name}>
        {React.string(field.name)}
        <span className="constraint-hint"> {React.string(` (${constraintHint})`)} </span>
      </label>
      <input
        id={field.name}
        type_={inputType}
        value
        onChange={evt => onChange(ReactEvent.Form.target(evt)["value"])}
        placeholder={constraintHint}
      />
      {switch validation {
      | Validation.Invalid(msg) =>
        <span className="validation-error"> {React.string(msg)} </span>
      | Validation.Warning(msg) =>
        <span className="validation-warning"> {React.string(msg)} </span>
      | _ => React.null
      }}
    </div>
  }
}

// Provenance form
module ProvenanceForm = {
  @react.component
  let make = (
    ~provenance: Provenance.t,
    ~onChange: Provenance.t => unit,
  ) => {
    let updateSource = evt => {
      let value = ReactEvent.Form.target(evt)["value"]
      onChange({...provenance, source: value})
    }

    let updateRationale = evt => {
      let value = ReactEvent.Form.target(evt)["value"]
      onChange({...provenance, rationale: value})
    }

    let updateConfidence = evt => {
      let value = ReactEvent.Form.target(evt)["value"]
      let conf = Int.fromString(value)->Option.getOr(80)
      onChange({...provenance, confidence: conf})
    }

    <div className="provenance-form">
      <h3> {React.string("Provenance (Audit Trail)")} </h3>
      <p className="provenance-hint">
        {React.string("Lith tracks who added data, when, and why. This ensures audit compliance.")}
      </p>

      <div className="form-group">
        <label htmlFor="source"> {React.string("Source")} </label>
        <input
          id="source"
          type_="text"
          value={provenance.source}
          onChange={updateSource}
          placeholder="e.g., ONS official statistics, court filing, interview"
        />
      </div>

      <div className="form-group">
        <label htmlFor="rationale"> {React.string("Rationale")} </label>
        <textarea
          id="rationale"
          value={provenance.rationale}
          onChange={updateRationale}
          placeholder="Why is this data being added? What's the justification?"
          rows={3}
        />
      </div>

      <div className="form-group">
        <label htmlFor="confidence">
          {React.string(`Confidence: ${Int.toString(provenance.confidence)}%`)}
        </label>
        <input
          id="confidence"
          type_="range"
          min="0"
          max="100"
          value={Int.toString(provenance.confidence)}
          onChange={updateConfidence}
        />
        <div className="confidence-labels">
          <span> {React.string("Uncertain")} </span>
          <span> {React.string("Confident")} </span>
        </div>
      </div>
    </div>
  }
}

// Submission state
type submissionState =
  | NotSubmitted
  | Submitting
  | Success(string)
  | Failed(string)

@react.component
let make = (~collections: array<Collection.t>) => {
  let (selectedCollection, setSelectedCollection) = React.useState(() => "")
  let (document, setDocument) = React.useState(() => Document.empty())
  let (validation, setValidation) = React.useState(() => Validation.empty())
  let (provenance, setProvenance) = React.useState(() => Provenance.empty())
  let (submission, setSubmission) = React.useState(() => NotSubmitted)

  let currentCollection = collections->Array.find(c => c.name == selectedCollection)

  // Validate a field value against its type
  let validateField = (field: Field.t, value: string): Validation.fieldState => {
    if value == "" {
      switch field.fieldType {
      | FieldType.Text({required: true}) => Validation.Invalid("This field is required")
      | _ => Validation.NotValidated
      }
    } else {
      switch field.fieldType {
      | FieldType.Number({min, max}) =>
        switch Int.fromString(value) {
        | None => Validation.Invalid("Must be a number")
        | Some(n) =>
          switch (min, max) {
          | (Some(lo), _) if n < lo =>
            Validation.Invalid(`Must be at least ${Int.toString(lo)}`)
          | (_, Some(hi)) if n > hi =>
            Validation.Invalid(`Must be at most ${Int.toString(hi)}`)
          | _ => Validation.Valid
          }
        }
      | FieldType.Confidence =>
        switch Int.fromString(value) {
        | None => Validation.Invalid("Must be a number 0-100")
        | Some(n) if n < 0 || n > 100 =>
          Validation.Invalid("Must be between 0 and 100")
        | Some(_) => Validation.Valid
        }
      | FieldType.Text({required: true}) =>
        if String.length(value) == 0 {
          Validation.Invalid("This field is required")
        } else {
          Validation.Valid
        }
      | _ => Validation.Valid
      }
    }
  }

  let handleFieldChange = (fieldName: string, field: Field.t, value: string) => {
    setDocument(prev => Document.set(prev, fieldName, value))
    let fieldValidation = validateField(field, value)
    setValidation(prev => Validation.set(prev, fieldName, fieldValidation))
  }

  let handleCollectionChange = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    setSelectedCollection(_ => value)
    setDocument(_ => Document.empty())
    setValidation(_ => Validation.empty())
    setSubmission(_ => NotSubmitted)
  }

  let allFieldsValid = switch currentCollection {
  | None => false
  | Some(coll) =>
    coll.fields->Array.every(field => {
      let value = Document.get(document, field.name)
      let state = validateField(field, value)
      switch state {
      | Validation.Valid => true
      | Validation.NotValidated =>
        switch field.fieldType {
        | FieldType.Text({required: true}) => false
        | _ => true
        }
      | _ => false
      }
    })
  }

  let handleSubmit = evt => {
    ReactEvent.Form.preventDefault(evt)
    if allFieldsValid && provenance.source != "" && provenance.rationale != "" {
      setSubmission(_ => Submitting)
      // TODO: Call Tauri command to insert document
      let _ = setTimeout(() => {
        setSubmission(_ => Success("Document inserted successfully with provenance tracking"))
        setDocument(_ => Document.empty())
        setValidation(_ => Validation.empty())
      }, 500)
    }
  }

  <section className="data-entry">
    <h2> {React.string("Data Entry")} </h2>

    <div className="form-group">
      <label> {React.string("Collection")} </label>
      <select value={selectedCollection} onChange={handleCollectionChange}>
        <option value=""> {React.string("Select collection...")} </option>
        {collections
        ->Array.map(c =>
          <option key={c.name} value={c.name}> {React.string(c.name)} </option>
        )
        ->React.array}
      </select>
    </div>

    {switch currentCollection {
    | None =>
      <div className="empty-state">
        <p> {React.string("Select a collection to enter data")} </p>
      </div>
    | Some(coll) =>
      <form onSubmit={handleSubmit}>
        <div className="document-form">
          <h3> {React.string("Document Fields")} </h3>
          {coll.fields
          ->Array.map(field =>
            <FieldInput
              key={field.name}
              field
              value={Document.get(document, field.name)}
              validation={Validation.get(validation, field.name)}
              onChange={value => handleFieldChange(field.name, field, value)}
            />
          )
          ->React.array}
        </div>

        <ProvenanceForm provenance onChange={p => setProvenance(_ => p)} />

        {switch submission {
        | Success(msg) =>
          <div className="submission-success">
            <span className="icon"> {React.string("\u2713")} </span>
            {React.string(msg)}
          </div>
        | Failed(msg) =>
          <div className="submission-error">
            <span className="icon"> {React.string("\u2717")} </span>
            {React.string(msg)}
          </div>
        | _ => React.null
        }}

        <div className="actions-bar">
          <button
            type_="button"
            className="btn btn-secondary"
            onClick={_ => {
              setDocument(_ => Document.empty())
              setValidation(_ => Validation.empty())
            }}>
            {React.string("Clear")}
          </button>
          <button
            type_="submit"
            className="btn btn-primary"
            disabled={!allFieldsValid || provenance.source == "" || provenance.rationale == ""}>
            {switch submission {
            | Submitting => React.string("Inserting...")
            | _ => React.string("Insert Document")
            }}
          </button>
        </div>
      </form>
    }}
  </section>
}
