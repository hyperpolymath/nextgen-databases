// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Schema Builder Component

open Types

@react.component
let make = (
  ~collection: Collection.t,
  ~onUpdateName: string => unit,
  ~onAddField: Field.t => unit,
  ~onRemoveField: int => unit,
) => {
  let handleNameChange = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    onUpdateName(value)
  }

  <section className="schema-builder">
    <h2> {React.string("Create Collection")} </h2>
    <div className="collection-form">
      <div className="form-group">
        <label htmlFor="collection-name"> {React.string("Collection Name")} </label>
        <input
          id="collection-name"
          type_="text"
          placeholder="e.g., evidence, sources, claims"
          value={collection.name}
          onChange={handleNameChange}
        />
      </div>
      <div className="fields-section">
        <h3> {React.string("Fields")} </h3>
        {if Array.length(collection.fields) == 0 {
          <div className="empty-state">
            <p> {React.string("No fields added yet.")} </p>
            <p> {React.string("Add fields below to define your schema.")} </p>
          </div>
        } else {
          <div className="fields-list">
            {collection.fields
            ->Array.mapWithIndex((field, index) => {
              let constraintText = switch field.fieldType {
              | FieldType.Number({min: Some(min), max: Some(max)}) =>
                `[${Int.toString(min)}-${Int.toString(max)}]`
              | FieldType.Number({min: Some(min), max: None}) =>
                `[>= ${Int.toString(min)}]`
              | FieldType.Number({min: None, max: Some(max)}) =>
                `[<= ${Int.toString(max)}]`
              | FieldType.Text({required: true}) => "[required]"
              | FieldType.Confidence => "[0-100, auto-validated]"
              | FieldType.PromptScores => "[PROMPT scoring]"
              | _ => ""
              }

              <div key={Int.toString(index)} className="field-item">
                <span className="field-name"> {React.string(field.name)} </span>
                <span className="field-type">
                  {React.string(FieldType.toString(field.fieldType))}
                </span>
                {if constraintText != "" {
                  <span className="field-constraints">
                    {React.string(constraintText)}
                  </span>
                } else {
                  React.null
                }}
                <button
                  type_="button"
                  className="remove-btn"
                  onClick={_ => onRemoveField(index)}
                  title="Remove field">
                  {React.string("\u00D7")}
                </button>
              </div>
            })
            ->React.array}
          </div>
        }}
        <FieldEditor onAdd={onAddField} />
      </div>
    </div>
  </section>
}
