// SPDX-License-Identifier: PMPL-1.0-or-later
// Form View - Public-facing form for data entry

open Types

type formConfig = {
  title: string,
  description: option<string>,
  submitButtonText: string,
  successMessage: string,
  redirectUrl: option<string>,
}

type validationError = {
  fieldId: string,
  message: string,
}

type formState =
  | Idle
  | Submitting
  | Success
  | Failed(string)

@react.component
let make = (
  ~tableId: string,
  ~fields: array<fieldConfig>,
  ~config: formConfig,
  ~onSubmit: Dict.t<cellValue> => promise<result<string, string>>,
  ~showFieldLabels: bool=true,
  ~showRequiredIndicator: bool=true,
) => {
  let (formData, setFormData) = React.useState(() => Dict.make())
  let (validationErrors, setValidationErrors) = React.useState(() => [])
  let (formState, setFormState) = React.useState(() => Idle)

  // Validate a single field
  let validateField = (field: fieldConfig, value: option<cellValue>): option<validationError> => {
    // Check required fields
    if field.required {
      switch value {
      | None => Some({fieldId: field.id, message: `${field.name} is required`})
      | Some(TextValue(text)) if text->String.trim == "" =>
        Some({fieldId: field.id, message: `${field.name} is required`})
      | Some(TextValue(email)) if email->String.trim == "" =>
        Some({fieldId: field.id, message: `${field.name} is required`})
      | _ => None
      }
    } else {
      None
    }
  }

  // Validate email format
  let validateEmail = (email: string): bool => {
    let emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    emailRegex->RegExp.test(email)
  }

  // Validate URL format
  let validateUrl = (url: string): bool => {
    try {
      let _ = %raw(`new URL(url)`)
      true
    } catch {
    | _ => false
    }
  }

  // Validate all fields
  let validateForm = (): array<validationError> => {
    fields->Array.filterMap(field => {
      let value = formData->Dict.get(field.id)

      // Required field validation
      let requiredError = validateField(field, value)
      if requiredError->Option.isSome {
        requiredError
      } else {
        // Type-specific validation
        switch (field.fieldType, value) {
        | (Email, Some(TextValue(email))) if !validateEmail(email) =>
          Some({fieldId: field.id, message: "Invalid email format"})
        | (Url, Some(UrlValue(url))) if !validateUrl(url) =>
          Some({fieldId: field.id, message: "Invalid URL format"})
        | _ => None
        }
      }
    })
  }

  // Handle field change
  let handleFieldChange = (fieldId: string, value: cellValue) => {
    setFormData(prev => {
      let next = Dict.copy(prev)
      next->Dict.set(fieldId, value)
      next
    })

    // Clear validation error for this field
    setValidationErrors(prev =>
      prev->Array.filter((err: validationError) => err.fieldId != fieldId)
    )
  }

  // Handle form submission
  let handleSubmit = async (evt: ReactEvent.Form.t) => {
    evt->ReactEvent.Form.preventDefault

    // Validate form
    let errors = validateForm()
    if errors->Array.length > 0 {
      setValidationErrors(_ => errors)
    } else {
      setFormState(_ => Submitting)

      try {
        let result = await onSubmit(formData)
        switch result {
        | Ok(_) => {
            setFormState(_ => Success)
            // Redirect if configured
            switch config.redirectUrl {
            | Some(url) =>
              // Wait 2 seconds before redirect
              let _ = setTimeout(() => {
                %raw(`window.location.href = url`)
              }, 2000)
            | None => ()
            }
          }
        | Error(message) => setFormState(_ => Failed(message))
        }
      } catch {
      | error =>
        setFormState(_ => Failed(
          `Submission failed: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`,
        ))
      }
    }
  }

  // Get validation error for a field
  let getFieldError = (fieldId: string): option<string> => {
    validationErrors->Array.find(err => err.fieldId == fieldId)->Option.map(err => err.message)
  }

  // Render field input based on type
  let renderFieldInput = (field: fieldConfig) => {
    let currentValue = formData->Dict.get(field.id)
    let error = getFieldError(field.id)
    let hasError = error->Option.isSome

    <div key={field.id} className={`form-field ${hasError ? "form-field-error" : ""}`}>
      {showFieldLabels
        ? <label htmlFor={field.id} className="form-label">
            {React.string(field.name)}
            {showRequiredIndicator && field.required
              ? <span className="form-required"> {React.string("*")} </span>
              : React.null}
          </label>
        : React.null}
      {switch field.fieldType {
      | Text =>
        <input
          id={field.id}
          type_="text"
          className="form-input"
          placeholder={field.description->Option.getOr("")}
          value={switch currentValue {
          | Some(TextValue(text)) => text
          | _ => ""
          }}
          onChange={evt => {
            let value = %raw(`evt.target.value`)
            handleFieldChange(field.id, TextValue(value))
          }}
          required={field.required}
        />
      | Number =>
        <input
          id={field.id}
          type_="number"
          className="form-input"
          placeholder={field.description->Option.getOr("")}
          value={switch currentValue {
          | Some(NumberValue(num)) => Float.toString(num)
          | _ => ""
          }}
          onChange={evt => {
            let value = %raw(`evt.target.value`)
            switch Float.fromString(value) {
            | Some(num) => handleFieldChange(field.id, NumberValue(num))
            | None => ()
            }
          }}
          required={field.required}
        />
      | Email =>
        <input
          id={field.id}
          type_="email"
          className="form-input"
          placeholder={field.description->Option.getOr("email@example.com")}
          value={switch currentValue {
          | Some(TextValue(email)) => email
          | _ => ""
          }}
          onChange={evt => {
            let value = %raw(`evt.target.value`)
            handleFieldChange(field.id, TextValue(value))
          }}
          required={field.required}
        />
      | Url =>
        <input
          id={field.id}
          type_="url"
          className="form-input"
          placeholder={field.description->Option.getOr("https://example.com")}
          value={switch currentValue {
          | Some(UrlValue(url)) => url
          | _ => ""
          }}
          onChange={evt => {
            let value = %raw(`evt.target.value`)
            handleFieldChange(field.id, UrlValue(value))
          }}
          required={field.required}
        />
      | Date =>
        <input
          id={field.id}
          type_="date"
          className="form-input"
          value={switch currentValue {
          | Some(DateValue(date)) => {
              let year = date->Date.getFullYear->Int.toString
              let month = (date->Date.getMonth + 1)->Int.toString->String.padStart(2, "0")
              let day = date->Date.getDate->Int.toString->String.padStart(2, "0")
              `${year}-${month}-${day}`
            }
          | _ => ""
          }}
          onChange={evt => {
            let value = %raw(`evt.target.value`)
            if value != "" {
              let date = Date.fromString(value)
              handleFieldChange(field.id, DateValue(date))
            }
          }}
          required={field.required}
        />
      | Checkbox =>
        <label className="form-checkbox-label">
          <input
            id={field.id}
            type_="checkbox"
            className="form-checkbox"
            checked={switch currentValue {
            | Some(CheckboxValue(checked)) => checked
            | _ => false
            }}
            onChange={evt => {
              let checked = %raw(`evt.target.checked`)
              handleFieldChange(field.id, CheckboxValue(checked))
            }}
          />
          <span> {React.string(field.description->Option.getOr("Check this box"))} </span>
        </label>
      | Select(options) =>
        <select
          id={field.id}
          className="form-select"
          value={switch currentValue {
          | Some(SelectValue(option)) => option
          | _ => ""
          }}
          onChange={evt => {
            let value = %raw(`evt.target.value`)
            if value != "" {
              handleFieldChange(field.id, SelectValue(value))
            }
          }}
          required={field.required}
        >
          <option value=""> {React.string("-- Select --")} </option>
          {options
          ->Array.map(opt => {
            <option key={opt} value={opt}> {React.string(opt)} </option>
          })
          ->React.array}
        </select>
      | _ =>
        <div className="form-unsupported">
          {React.string("Field type not supported in forms")}
        </div>
      }}
      {switch error {
      | Some(msg) => <div className="form-error-message"> {React.string(msg)} </div>
      | None => React.null
      }}
    </div>
  }

  // Render success state
  let renderSuccess = () => {
    <div className="form-success">
      <div className="form-success-icon"> {React.string("✓")} </div>
      <div className="form-success-title"> {React.string("Success!")} </div>
      <div className="form-success-message"> {React.string(config.successMessage)} </div>
      {switch config.redirectUrl {
      | Some(_) => <div className="form-success-redirect"> {React.string("Redirecting...")} </div>
      | None => React.null
      }}
    </div>
  }

  // Render error state
  let renderError = (message: string) => {
    <div className="form-error-banner">
      <div className="form-error-banner-icon"> {React.string("⚠")} </div>
      <div className="form-error-banner-message"> {React.string(message)} </div>
      <button className="form-error-banner-close" onClick={_ => setFormState(_ => Idle)}>
        {React.string("×")}
      </button>
    </div>
  }

  <div className="form-view">
    <div className="form-container">
      {switch formState {
      | Success => renderSuccess()
      | _ =>
        <>
          <div className="form-header">
            <h1 className="form-title"> {React.string(config.title)} </h1>
            {switch config.description {
            | Some(desc) => <p className="form-description"> {React.string(desc)} </p>
            | None => React.null
            }}
          </div>
          {switch formState {
          | Failed(message) => renderError(message)
          | _ => React.null
          }}
          <form className="form-body" onSubmit={evt => handleSubmit(evt)->ignore}>
            {fields
            ->Array.filter(field =>
              switch field.fieldType {
              | Formula(_) | Rollup(_, _) | Lookup(_, _) => false
              | _ => true
              }
            )
            ->Array.map(renderFieldInput)
            ->React.array}
            <button
              type_="submit" className="form-submit-button" disabled={formState == Submitting}
            >
              {React.string(formState == Submitting ? "Submitting..." : config.submitButtonText)}
            </button>
          </form>
        </>
      }}
    </div>
  </div>
}
