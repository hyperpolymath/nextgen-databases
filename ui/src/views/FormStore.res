// SPDX-License-Identifier: PMPL-1.0-or-later
// Form Store - State management for Form View

open Types

// File type from Web API
type file

type formConfig = {
  title: string,
  description: option<string>,
  submitButtonText: string,
  successMessage: string,
  redirectUrl: option<string>,
}

type validationRule =
  | Required
  | MinLength(int)
  | MaxLength(int)
  | Pattern(RegExp.t)
  | Custom(cellValue => option<string>)

type fieldWithRules = {
  field: fieldConfig,
  rules: array<validationRule>,
}

// Atoms for form state
let formDataAtom: Jotai.atom<Dict.t<cellValue>> = Jotai.atom(Dict.make())

let formConfigAtom: Jotai.atom<formConfig> = Jotai.atom({
  title: "Submit Form",
  description: None,
  submitButtonText: "Submit",
  successMessage: "Thank you for your submission!",
  redirectUrl: None,
})

// Validation helpers
module Validation = {
  // Validate a value against a rule
  let validateRule = (rule: validationRule, value: option<cellValue>): option<string> => {
    switch (rule, value) {
    | (Required, None) => Some("This field is required")
    | (Required, Some(TextValue(text))) if text->String.trim == "" => Some("This field is required")
    | (Required, Some(EmailValue(email))) if email->String.trim == "" =>
      Some("This field is required")
    | (MinLength(min), Some(TextValue(text))) if text->String.length < min =>
      Some(`Must be at least ${min->Int.toString} characters`)
    | (MaxLength(max), Some(TextValue(text))) if text->String.length > max =>
      Some(`Must be no more than ${max->Int.toString} characters`)
    | (Pattern(regex), Some(TextValue(text))) if !RegExp.test(regex, text) => Some("Invalid format")
    | (Custom(validator), Some(val)) => validator(val)
    | _ => None
    }
  }

  // Validate a field against all its rules
  let validateField = (fieldWithRules: fieldWithRules, value: option<cellValue>): array<string> => {
    fieldWithRules.rules->Array.filterMap(rule => validateRule(rule, value))
  }

  // Email validation
  let emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  let isValidEmail = (email: string): bool => emailRegex->RegExp.test(email)

  // URL validation
  let isValidUrl = (url: string): bool => {
    try {
      let _ = %raw(`new URL(url)`)
      true
    } catch {
    | _ => false
    }
  }

  // Phone validation (basic international format)
  let phoneRegex = /^[+]?[(]?[0-9]{1,4}[)]?[-\s\.]?[(]?[0-9]{1,4}[)]?[-\s\.]?[0-9]{1,9}$/
  let isValidPhone = (phone: string): bool => phoneRegex->RegExp.test(phone)
}

// API integration
module API = {
  // Submit form data
  let submitForm = async (tableId: string, formData: Dict.t<cellValue>): result<string, string> => {
    try {
      // Convert form data to API format
      let cells = Dict.make()
      formData
      ->Dict.toArray
      ->Array.forEach(((fieldId, value)) => {
        let cellData = switch value {
        | TextValue(text) => {"value": text}
        | NumberValue(num) => {"value": Float.toString(num)}
        | DateValue(date) => {"value": date->Date.toISOString}
        | CheckboxValue(checked) => {"value": checked ? "true" : "false"}
        | SelectValue(option) => {"value": option}
        | MultiSelectValue(options) => {"value": options->Array.join(", ")}
        | UrlValue(url) => {"value": url}
        | EmailValue(email) => {"value": email}
        | _ => {"value": ""}
        }
        cells->Dict.set(fieldId, cellData)
      })

      let bodyJson = JSON.stringifyAny({"cells": cells})->Option.getOr("{}")
      let response = await Fetch.fetch(
        `/api/tables/${tableId}/rows`,
        %raw(`{
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: bodyJson
        }`),
      )

      if response->Fetch.Response.ok {
        let json = await response->Fetch.Response.json
        switch json->JSON.Decode.object->Option.flatMap(obj => obj->Dict.get("id")) {
        | Some(id) =>
          switch id->JSON.Decode.string {
          | Some(rowId) => Ok(rowId)
          | None => Error("Invalid row ID in response")
          }
        | None => Error("No row ID in response")
        }
      } else {
        let errorText = await response->Fetch.Response.text
        Error(`Submission failed: ${errorText}`)
      }
    } catch {
    | error => Error(`API error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }

  // Upload file attachment
  let uploadFormAttachment = async (
    tableId: string,
    rowId: string,
    fieldId: string,
    file: file,
  ): result<string, string> => {
    try {
      let formData = %raw(`new FormData()`)
      %raw(`formData.append("file", file)`)

      let response = await Fetch.fetch(
        `/api/tables/${tableId}/rows/${rowId}/attachments/${fieldId}`,
        %raw(`{
          method: "POST",
          body: formData
        }`),
      )

      if response->Fetch.Response.ok {
        let json = await response->Fetch.Response.json
        switch json->JSON.Decode.object->Option.flatMap(obj => obj->Dict.get("url")) {
        | Some(url) =>
          switch url->JSON.Decode.string {
          | Some(urlStr) => Ok(urlStr)
          | None => Error("Invalid URL in response")
          }
        | None => Error("No URL in response")
        }
      } else {
        Error("File upload failed")
      }
    } catch {
    | error => Error(`Upload error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }
}

// Form configuration helpers
module Config = {
  // Create default config
  let makeDefault = (title: string): formConfig => {
    {
      title,
      description: None,
      submitButtonText: "Submit",
      successMessage: "Thank you for your submission!",
      redirectUrl: None,
    }
  }

  // Builder pattern for config
  let withDescription = (config: formConfig, description: string): formConfig => {
    {...config, description: Some(description)}
  }

  let withSubmitText = (config: formConfig, text: string): formConfig => {
    {...config, submitButtonText: text}
  }

  let withSuccessMessage = (config: formConfig, message: string): formConfig => {
    {...config, successMessage: message}
  }

  let withRedirect = (config: formConfig, url: string): formConfig => {
    {...config, redirectUrl: Some(url)}
  }
}

// Form utilities
module Utils = {
  // Filter fields suitable for forms
  let getFormFields = (fields: array<fieldConfig>): array<fieldConfig> => {
    fields->Array.filter(field => {
      switch field.fieldType {
      | Text | Number | Email | Url | Date | Checkbox | Select(_) => true
      | MultiSelect(_) => true // Can be supported with checkboxes
      | Attachment => true // Can be supported with file input
      | Formula(_) | Rollup(_, _) | Lookup(_, _) => false // Computed fields can't be in forms
      | _ => false // All other field types not supported
      }
    })
  }

  // Group fields by sections (if using description as section name)
  let groupFieldsBySection = (fields: array<fieldConfig>): Dict.t<array<fieldConfig>> => {
    let sections = Dict.make()
    fields->Array.forEach(field => {
      let section = field.description->Option.getOr("General")
      switch sections->Dict.get(section) {
      | Some(sectionFields) => sections->Dict.set(section, sectionFields->Array.concat([field]))
      | None => sections->Dict.set(section, [field])
      }
    })
    sections
  }

  // Generate shareable form URL
  let getShareableUrl = (baseUrl: string, tableId: string, formId: string): string => {
    `${baseUrl}/form/${tableId}/${formId}`
  }
}
