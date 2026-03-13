// SPDX-License-Identifier: PMPL-1.0-or-later
// Kanban View Store

open Types
open Jotai

// Selected view configuration
let selectedViewAtom: atom<option<viewConfig>> = Jotai.atom(None)

// Group by field for Kanban
let kanbanGroupByFieldAtom: atom<option<string>> = Jotai.atom(None)

// Compute Kanban columns from rows and group field
// Use %raw to create derived atom due to ReScript type constraints
let kanbanColumnsAtom: Jotai.atom<array<(string, array<row>)>> = %raw(`
  require('jotai').atom((get) => {
    // For now, return empty - will be populated by the component
    return [];
  })
`)

// Update row status (move card to different column)
let updateRowStatus: (string, string, cellValue) => promise<unit> = async (
  rowId,
  fieldId,
  newValue,
) => {
  // Call API to update the row
  let response = await Fetch.fetch(
    `/api/rows/${rowId}`,
    %raw(`{
      method: "PATCH",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        fieldId: fieldId,
        value: newValue
      })
    }`),
  )

  if response->Fetch.Response.ok {
    // Success - the component will refetch data
    ()
  } else {
    throw(JsError.throwWithMessage("Failed to update row"))
  }
}
