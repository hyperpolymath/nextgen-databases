// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Field Editor Component

open Types

type fieldFormState = {
  name: string,
  fieldType: string,
  minValue: option<int>,
  maxValue: option<int>,
  required: bool,
}

let emptyFieldForm = {
  name: "",
  fieldType: "text",
  minValue: None,
  maxValue: None,
  required: false,
}

let fieldFormToField = (form: fieldFormState): option<Field.t> => {
  if form.name == "" {
    None
  } else {
    let fieldType = switch form.fieldType {
    | "number" => FieldType.Number({min: form.minValue, max: form.maxValue})
    | "text" => FieldType.Text({required: form.required})
    | "confidence" => FieldType.Confidence
    | "prompt_scores" => FieldType.PromptScores
    | _ => FieldType.Text({required: false})
    }
    Some({Field.name: form.name, fieldType})
  }
}

@react.component
let make = (~onAdd: Field.t => unit) => {
  let (form, setForm) = React.useState(() => emptyFieldForm)

  let handleSubmit = evt => {
    ReactEvent.Form.preventDefault(evt)
    switch fieldFormToField(form) {
    | Some(field) =>
      onAdd(field)
      setForm(_ => emptyFieldForm)
    | None => ()
    }
  }

  let updateName = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    setForm(prev => {...prev, name: value})
  }

  let updateType = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    setForm(prev => {...prev, fieldType: value})
  }

  let updateMin = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    let intVal = Int.fromString(value)
    setForm(prev => {...prev, minValue: intVal})
  }

  let updateMax = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    let intVal = Int.fromString(value)
    setForm(prev => {...prev, maxValue: intVal})
  }

  let updateRequired = evt => {
    let checked = ReactEvent.Form.target(evt)["checked"]
    setForm(prev => {...prev, required: checked})
  }

  <form className="add-field-form" onSubmit={handleSubmit}>
    <input
      type_="text"
      placeholder="Field name"
      value={form.name}
      onChange={updateName}
    />
    <select value={form.fieldType} onChange={updateType}>
      <option value="text"> {React.string("Text")} </option>
      <option value="number"> {React.string("Number")} </option>
      <option value="confidence"> {React.string("Confidence (0-100)")} </option>
      <option value="prompt_scores"> {React.string("PROMPT Scores")} </option>
    </select>
    <button type_="submit" className="btn btn-primary btn-small">
      {React.string("Add")}
    </button>
    <div className="constraint-options">
      {switch form.fieldType {
      | "number" =>
        <>
          <div className="constraint-option">
            <label> {React.string("Min:")} </label>
            <input
              type_="number"
              value={form.minValue->Option.mapOr("", n => Int.toString(n))}
              onChange={updateMin}
            />
          </div>
          <div className="constraint-option">
            <label> {React.string("Max:")} </label>
            <input
              type_="number"
              value={form.maxValue->Option.mapOr("", n => Int.toString(n))}
              onChange={updateMax}
            />
          </div>
        </>
      | "text" =>
        <div className="constraint-option">
          <input
            type_="checkbox"
            id="required"
            checked={form.required}
            onChange={updateRequired}
          />
          <label htmlFor="required"> {React.string("Required")} </label>
        </div>
      | _ => React.null
      }}
    </div>
  </form>
}
