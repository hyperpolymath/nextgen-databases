// SPDX-License-Identifier: PMPL-1.0-or-later
// Gallery Store - State management for Gallery View

open Types

type galleryLayout = Grid | Masonry

// Atoms for gallery state
let layoutAtom: Jotai.atom<galleryLayout> = Jotai.atom(Grid)

let coverFieldIdAtom: Jotai.atom<option<string>> = Jotai.atom(None)

let selectedCardIdAtom: Jotai.atom<option<string>> = Jotai.atom(None)

// Helper functions for layout
module Layout = {
  let toggleLayout = (current: galleryLayout): galleryLayout => {
    switch current {
    | Grid => Masonry
    | Masonry => Grid
    }
  }

  let getLayoutName = (layout: galleryLayout): string => {
    switch layout {
    | Grid => "Grid"
    | Masonry => "Masonry"
    }
  }
}

// API integration helpers
module API = {
  // Upload attachment to a row
  // File type from Web API
  type file

  let uploadAttachment = async (
    tableId: string,
    rowId: string,
    fieldId: string,
    file: file,
  ): result<string, string> => {
    try {
      // Create FormData with the file
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
        Error("Failed to upload attachment")
      }
    } catch {
    | error => Error(`API error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }

  // Delete attachment from a row
  let deleteAttachment = async (
    tableId: string,
    rowId: string,
    fieldId: string,
    attachmentId: string,
  ): result<unit, string> => {
    try {
      let response = await Fetch.fetch(
        `/api/tables/${tableId}/rows/${rowId}/attachments/${fieldId}/${attachmentId}`,
        %raw(`{ method: "DELETE" }`),
      )

      if response->Fetch.Response.ok {
        Ok()
      } else {
        Error("Failed to delete attachment")
      }
    } catch {
    | error => Error(`API error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }

  // Update card field value
  let updateCardField = async (
    tableId: string,
    rowId: string,
    fieldId: string,
    value: cellValue,
  ): result<unit, string> => {
    try {
      let valueJson = switch value {
      | TextValue(text) => JSON.stringifyAny({"value": text})
      | NumberValue(num) => JSON.stringifyAny({"value": num})
      | DateValue(date) => JSON.stringifyAny({"value": date->Date.toISOString})
      | CheckboxValue(checked) => JSON.stringifyAny({"value": checked})
      | SelectValue(option) => JSON.stringifyAny({"value": option})
      | MultiSelectValue(options) => JSON.stringifyAny({"value": options})
      | UrlValue(url) => JSON.stringifyAny({"value": url})
      | EmailValue(email) => JSON.stringifyAny({"value": email})
      | _ => None
      }

      switch valueJson {
      | Some(json) => {
          let response = await Fetch.fetch(
            `/api/tables/${tableId}/rows/${rowId}`,
            %raw(`{
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: json
            }`),
          )

          if response->Fetch.Response.ok {
            Ok()
          } else {
            Error("Failed to update field")
          }
        }
      | None => Error("Invalid value type")
      }
    } catch {
    | error => Error(`API error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }
}

// Filter helpers for gallery view
module Filter = {
  // Filter cards that have images
  let hasImage = (coverFieldId: option<string>, row: row): bool => {
    switch coverFieldId {
    | Some(fieldId) =>
      switch row.cells->Dict.get(fieldId) {
      | Some({value: AttachmentValue(attachments)}) => attachments->Array.length > 0
      | Some({value: UrlValue(_)}) => true
      | _ => false
      }
    | None => false
    }
  }

  // Filter cards without images
  let noImage = (coverFieldId: option<string>, row: row): bool => {
    !hasImage(coverFieldId, row)
  }

  // Search cards by title or field values
  let search = (searchTerm: string, primaryFieldId: string, row: row): bool => {
    if searchTerm == "" {
      true
    } else {
      let lowerSearchTerm = searchTerm->String.toLowerCase

      // Check title
      let titleMatches = switch row.cells->Dict.get(primaryFieldId) {
      | Some({value: TextValue(text)}) => text->String.toLowerCase->String.includes(lowerSearchTerm)
      | _ => false
      }

      // Check all text fields
      let fieldMatches =
        row.cells
        ->Dict.valuesToArray
        ->Array.some(cell => {
          switch cell.value {
          | TextValue(text) => text->String.toLowerCase->String.includes(lowerSearchTerm)
          | EmailValue(email) => email->String.toLowerCase->String.includes(lowerSearchTerm)
          | UrlValue(url) => url->String.toLowerCase->String.includes(lowerSearchTerm)
          | _ => false
          }
        })

      titleMatches || fieldMatches
    }
  }
}
