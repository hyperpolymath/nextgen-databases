// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - GQLdt Preview Component

open Types

let fieldTypeToGqldt = (ft: FieldType.t): string => {
  switch ft {
  | Number({min: Some(min), max: Some(max)}) => `BoundedNat ${Int.toString(min)} ${Int.toString(max)}`
  | Number({min: Some(min), max: None}) => `Nat (>= ${Int.toString(min)})`
  | Number({min: None, max: Some(max)}) => `Nat (<= ${Int.toString(max)})`
  | Number(_) => "Int"
  | Text({required: true}) => "NonEmptyString"
  | Text({required: false}) => "Option String"
  | Confidence => "Confidence"
  | PromptScores => "PromptScores"
  }
}

let generateGqldtCode = (collection: Collection.t): string => {
  if collection.name == "" {
    "-- Enter a collection name to see generated GQLdt"
  } else {
    let fieldsCode =
      collection.fields
      ->Array.map(f => `  ${f.name} : ${fieldTypeToGqldt(f.fieldType)}`)
      ->Array.join(",\n")

    let fieldsSection = if Array.length(collection.fields) > 0 {
      `,\n${fieldsCode}`
    } else {
      ""
    }

    `CREATE COLLECTION ${collection.name} (
  id : UUID${fieldsSection}
) WITH DEPENDENT_TYPES, PROVENANCE_TRACKING;`
  }
}

// Clipboard API binding
module Clipboard = {
  @val @scope(("navigator", "clipboard"))
  external writeText: string => promise<unit> = "writeText"
}

@react.component
let make = (
  ~collection: Collection.t,
  ~validationState: validationState,
  ~onCreateCollection: unit => unit,
) => {
  let code = generateGqldtCode(collection)
  let (copied, setCopied) = React.useState(() => false)

  let handleCopy = _ => {
    Clipboard.writeText(code)->Promise.then(_ => {
      setCopied(_ => true)
      let _ = setTimeout(() => setCopied(_ => false), 2000)
      Promise.resolve()
    })->ignore
  }

  let canCreate = collection.name != "" && Array.length(collection.fields) > 0

  <aside className="gqldt-preview">
    <h2> {React.string("Generated GQLdt")} </h2>
    <div className="code-block">
      <pre> {React.string(code)} </pre>
    </div>
    {switch validationState {
    | NotValidated => React.null
    | Validating =>
      <div className="validation-status">
        {React.string("Validating...")}
      </div>
    | Valid(proofs) =>
      <div className="validation-status valid">
        <span className="icon"> {React.string("\u2713")} </span>
        <span>
          {React.string(`Types verified. ${Int.toString(Array.length(proofs))} proofs generated.`)}
        </span>
      </div>
    | Invalid(errors) =>
      <div className="validation-status invalid">
        <span className="icon"> {React.string("\u2717")} </span>
        <span> {React.string(errors->Array.join(", "))} </span>
      </div>
    }}
    <div className="actions-bar">
      <button className="btn btn-secondary" onClick={handleCopy}>
        {React.string(if copied { "Copied!" } else { "Copy Code" })}
      </button>
      <button
        className="btn btn-primary"
        disabled={!canCreate}
        onClick={_ => onCreateCollection()}>
        {React.string("Create Collection")}
      </button>
    </div>
  </aside>
}
