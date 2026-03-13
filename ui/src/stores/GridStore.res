// SPDX-License-Identifier: PMPL-1.0-or-later
// State management for the grid view

open Types

// Rows in the current table view
let rowsAtom: Jotai.atom<array<row>> = Jotai.atom([])

// Selected cells (for multi-select)
type selection = {
  startRow: int,
  startCol: int,
  endRow: int,
  endCol: int,
}

let selectionAtom: Jotai.atom<option<selection>> = Jotai.atom(None)

// Currently editing cell
type editingCell = {
  rowId: string,
  fieldId: string,
}

let editingCellAtom: Jotai.atom<option<editingCell>> = Jotai.atom(None)

// Current edit value (string representation for input)
let editValueAtom: Jotai.atom<string> = Jotai.atom("")

// Pending cell updates (rowId.fieldId => newValue)
let pendingUpdatesAtom: Jotai.atom<dict<cellValue>> = Jotai.atom(Dict.make())

// Column widths (field id => width in px)
let columnWidthsAtom: Jotai.atom<dict<int>> = Jotai.atom(Dict.make())

// Row heights (row id => height in px)
let rowHeightsAtom: Jotai.atom<dict<int>> = Jotai.atom(Dict.make())

// Hidden columns
let hiddenColumnsAtom: Jotai.atom<array<string>> = Jotai.atom([])

// Sort configuration
type sortConfig = {
  fieldId: string,
  direction: [#Asc | #Desc],
}

let sortConfigAtom: Jotai.atom<option<sortConfig>> = Jotai.atom(None)

// Helper to compare cell values for sorting
let compareCellValues = (a: cellValue, b: cellValue): int => {
  switch (a, b) {
  | (NumberValue(na), NumberValue(nb)) =>
    if na < nb {
      -1
    } else if na > nb {
      1
    } else {
      0
    }
  | (TextValue(sa), TextValue(sb)) => String.localeCompare(sa, sb)->Float.toInt
  | (SelectValue(sa), SelectValue(sb)) => String.localeCompare(sa, sb)->Float.toInt
  | (DateValue(da), DateValue(db)) => {
      let ta = Date.getTime(da)
      let tb = Date.getTime(db)
      if ta < tb {
        -1
      } else if ta > tb {
        1
      } else {
        0
      }
    }
  | (CheckboxValue(ba), CheckboxValue(bb)) =>
    if ba == bb {
      0
    } else if ba {
      1
    } else {
      -1
    }
  | (NullValue, NullValue) => 0
  | (NullValue, _) => 1 // Nulls sort to end
  | (_, NullValue) => -1
  | _ => 0
  }
}

// Apply sorting to rows
let applySort = (rows: array<row>, sortConfig: option<sortConfig>): array<row> => {
  switch sortConfig {
  | None => rows
  | Some({fieldId, direction}) =>
    rows->Array.toSorted((a, b) => {
      let cellA = a.cells->Dict.get(fieldId)->Option.map(c => c.value)->Option.getOr(NullValue)
      let cellB = b.cells->Dict.get(fieldId)->Option.map(c => c.value)->Option.getOr(NullValue)
      let cmp = compareCellValues(cellA, cellB)
      let result = switch direction {
      | #Asc => cmp
      | #Desc => -cmp
      }
      Int.toFloat(result)
    })
  }
}

// Filter configuration
type filterOperator =
  | Contains
  | DoesNotContain
  | Is
  | IsNot
  | IsEmpty
  | IsNotEmpty
  | GreaterThan
  | LessThan
  | GreaterOrEqual
  | LessOrEqual

type filterCondition = {
  id: string,
  fieldId: string,
  operator: filterOperator,
  value: string,
}

let filtersAtom: Jotai.atom<array<filterCondition>> = Jotai.atom([])

// Filter conjunction (AND/OR)
let filterConjunctionAtom: Jotai.atom<[#And | #Or]> = Jotai.atom(#And)

// Filter (FQL expression) - legacy
let filterAtom: Jotai.atom<option<string>> = Jotai.atom(None)

// Helper to check if a cell value matches a filter condition
let cellMatchesFilter = (value: cellValue, operator: filterOperator, filterValue: string): bool => {
  let strValue = switch value {
  | TextValue(s) => s
  | NumberValue(n) => Float.toString(n)
  | SelectValue(s) => s
  | MultiSelectValue(arr) => arr->Array.join(", ")
  | DateValue(d) => Date.toISOString(d)->String.slice(~start=0, ~end=10)
  | CheckboxValue(b) => b ? "true" : "false"
  | NullValue => ""
  | _ => ""
  }

  switch operator {
  | Contains => strValue->String.toLowerCase->String.includes(filterValue->String.toLowerCase)
  | DoesNotContain =>
    !(strValue->String.toLowerCase->String.includes(filterValue->String.toLowerCase))
  | Is => strValue->String.toLowerCase == filterValue->String.toLowerCase
  | IsNot => strValue->String.toLowerCase != filterValue->String.toLowerCase
  | IsEmpty => strValue == ""
  | IsNotEmpty => strValue != ""
  | GreaterThan =>
    switch (Float.fromString(strValue), Float.fromString(filterValue)) {
    | (Some(a), Some(b)) => a > b
    | _ => strValue > filterValue
    }
  | LessThan =>
    switch (Float.fromString(strValue), Float.fromString(filterValue)) {
    | (Some(a), Some(b)) => a < b
    | _ => strValue < filterValue
    }
  | GreaterOrEqual =>
    switch (Float.fromString(strValue), Float.fromString(filterValue)) {
    | (Some(a), Some(b)) => a >= b
    | _ => strValue >= filterValue
    }
  | LessOrEqual =>
    switch (Float.fromString(strValue), Float.fromString(filterValue)) {
    | (Some(a), Some(b)) => a <= b
    | _ => strValue <= filterValue
    }
  }
}

// Apply filters to rows
let applyFilters = (
  rows: array<row>,
  filters: array<filterCondition>,
  conjunction: [#And | #Or],
): array<row> => {
  if Array.length(filters) == 0 {
    rows
  } else {
    rows->Array.filter(row => {
      let results = filters->Array.map(filter => {
        let cell = row.cells->Dict.get(filter.fieldId)
        let value = cell->Option.map(c => c.value)->Option.getOr(NullValue)
        cellMatchesFilter(value, filter.operator, filter.value)
      })

      switch conjunction {
      | #And => results->Array.every(r => r)
      | #Or => results->Array.some(r => r)
      }
    })
  }
}

// Search configuration
let searchTermAtom: Jotai.atom<string> = Jotai.atom("")

// Apply search to rows (searches across all cells)
let applySearch = (rows: array<row>, searchTerm: string): array<row> => {
  if searchTerm->String.trim == "" {
    rows
  } else {
    let lowerSearchTerm = searchTerm->String.toLowerCase->String.trim
    rows->Array.filter(row => {
      // Check if any cell in the row matches the search term
      row.cells
      ->Dict.valuesToArray
      ->Array.some(cell => {
        let strValue = switch cell.value {
        | TextValue(s) => s
        | NumberValue(n) => Float.toString(n)
        | SelectValue(s) => s
        | MultiSelectValue(arr) => arr->Array.join(" ")
        | DateValue(d) => Date.toISOString(d)->String.slice(~start=0, ~end=10)
        | CheckboxValue(b) => b ? "checked" : "unchecked"
        | NullValue => ""
        | _ => ""
        }
        strValue->String.toLowerCase->String.includes(lowerSearchTerm)
      })
    })
  }
}

// Undo/Redo configuration
type historyAction = {
  rowId: string,
  fieldId: string,
  oldValue: cellValue,
  newValue: cellValue,
}

type historyState = {
  past: array<historyAction>,
  future: array<historyAction>,
}

let historyAtom: Jotai.atom<historyState> = Jotai.atom({past: [], future: []})

// Record a cell edit to history
let recordEdit = (
  history: historyState,
  rowId: string,
  fieldId: string,
  oldValue: cellValue,
  newValue: cellValue,
): historyState => {
  {
    past: Array.concat(history.past, [{rowId, fieldId, oldValue, newValue}]),
    future: [], // Clear future when new edit is made
  }
}

// Get undo action (most recent edit)
let getUndoAction = (history: historyState): option<historyAction> => {
  history.past->Array.at(-1)
}

// Get redo action (most recent undone edit)
let getRedoAction = (history: historyState): option<historyAction> => {
  history.future->Array.at(-1)
}

// Perform undo
let performUndo = (history: historyState): (historyState, option<historyAction>) => {
  switch getUndoAction(history) {
  | Some(action) => {
      let newPast = history.past->Array.slice(~start=0, ~end=-1)
      let newFuture = Array.concat(history.future, [action])
      ({past: newPast, future: newFuture}, Some(action))
    }
  | None => (history, None)
  }
}

// Perform redo
let performRedo = (history: historyState): (historyState, option<historyAction>) => {
  switch getRedoAction(history) {
  | Some(action) => {
      let newFuture = history.future->Array.slice(~start=0, ~end=-1)
      let newPast = Array.concat(history.past, [action])
      ({past: newPast, future: newFuture}, Some(action))
    }
  | None => (history, None)
  }
}

// Check if undo is available
let canUndo = (history: historyState): bool => {
  Array.length(history.past) > 0
}

// Check if redo is available
let canRedo = (history: historyState): bool => {
  Array.length(history.future) > 0
}
