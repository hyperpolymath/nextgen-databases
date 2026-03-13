// SPDX-License-Identifier: PMPL-1.0-or-later
// Kanban Board View

open Types

type kanbanColumn = {
  value: string,
  label: string,
  rows: array<row>,
}

@react.component
let make = (
  ~tableId: string,
  ~groupByFieldId: string,
  ~rows: array<row>,
  ~fields: array<fieldConfig>,
  ~onUpdateRow: (string, string, cellValue) => unit,
) => {
  let (draggedRowId, setDraggedRowId) = React.useState(() => None)
  let (draggedFromColumn, setDraggedFromColumn) = React.useState(() => None)

  // Find the field to group by
  let groupByField = fields->Array.find(f => f.id == groupByFieldId)

  // Get column options from the field
  let columnOptions = switch groupByField {
  | Some({fieldType: Select(options)}) => options
  | Some({fieldType: MultiSelect(options)}) => options
  | _ => []
  }

  // Group rows by the select field value
  let columns = columnOptions->Array.map(option => {
    let filteredRows = rows->Array.filter(row => {
      switch row.cells->Dict.get(groupByFieldId) {
      | Some({value: SelectValue(val)}) => val == option
      | Some({value: MultiSelectValue(vals)}) => vals->Array.includes(option)
      | _ => false
      }
    })

    {
      value: option,
      label: option,
      rows: filteredRows,
    }
  })

  // Add "No Status" column for rows without a value
  let noStatusRows = rows->Array.filter(row => {
    switch row.cells->Dict.get(groupByFieldId) {
    | None => true
    | Some({value: NullValue}) => true
    | Some({value: SelectValue("")}) => true
    | _ => false
    }
  })

  let allColumns = if noStatusRows->Array.length > 0 {
    columns->Array.concat([
      {
        value: "",
        label: "No Status",
        rows: noStatusRows,
      },
    ])
  } else {
    columns
  }

  // Drag handlers
  let handleDragStart = (rowId: string, columnValue: string, evt: ReactEvent.Mouse.t) => {
    setDraggedRowId(_ => Some(rowId))
    setDraggedFromColumn(_ => Some(columnValue))

    // Set drag data
    let target = ReactEvent.Mouse.target(evt)
    let dataTransfer = %raw(`target.dataTransfer`)
    dataTransfer["effectAllowed"] = "move"
    dataTransfer["setData"]("text/plain", rowId)
  }

  let handleDragOver = (evt: ReactEvent.Mouse.t) => {
    ReactEvent.Mouse.preventDefault(evt)
    let target = ReactEvent.Mouse.target(evt)
    let dataTransfer = %raw(`target.dataTransfer`)
    dataTransfer["dropEffect"] = "move"
  }

  let handleDrop = (columnValue: string, evt: ReactEvent.Mouse.t) => {
    ReactEvent.Mouse.preventDefault(evt)

    switch (draggedRowId, draggedFromColumn) {
    | (Some(rowId), Some(fromColumn)) if fromColumn != columnValue => {
        // Update the row's status field
        onUpdateRow(rowId, groupByFieldId, SelectValue(columnValue))
        setDraggedRowId(_ => None)
        setDraggedFromColumn(_ => None)
      }
    | _ => {
        setDraggedRowId(_ => None)
        setDraggedFromColumn(_ => None)
      }
    }
  }

  let handleDragEnd = (_evt: ReactEvent.Mouse.t) => {
    setDraggedRowId(_ => None)
    setDraggedFromColumn(_ => None)
  }

  // Render a card for a row
  let renderCard = (row: row, columnValue: string) => {
    let isDragging = switch draggedRowId {
    | Some(id) => id == row.id
    | None => false
    }

    // Get primary field value for card title
    let primaryField = fields->Array.find(f => f.name == "Title" || f.name == "Name")
    let primaryFieldId = switch primaryField {
    | Some(f) => f.id
    | None => fields->Array.get(0)->Option.mapOr("", f => f.id)
    }

    let cardTitle = switch row.cells->Dict.get(primaryFieldId) {
    | Some({value: TextValue(text)}) => text
    | _ => `Record ${row.id}`
    }

    <div
      key={row.id}
      className={`kanban-card ${isDragging ? "dragging" : ""}`}
      draggable={true}
      onDragStart={evt => handleDragStart(row.id, columnValue, evt)}
      onDragEnd={handleDragEnd}
    >
      <div className="kanban-card-title"> {React.string(cardTitle)} </div>
      <div className="kanban-card-meta">
        {row.cells
        ->Dict.toArray
        ->Array.slice(~start=0, ~end=3)
        ->Array.map(((fieldId, cell)) => {
          let fieldName = fields->Array.find(f => f.id == fieldId)->Option.mapOr("", f => f.name)
          let valueText = switch cell.value {
          | TextValue(text) => text
          | NumberValue(num) => Float.toString(num)
          | SelectValue(val) => val
          | DateValue(_) => "Date"
          | CheckboxValue(checked) => checked ? "✓" : ""
          | _ => ""
          }

          if valueText != "" && fieldId != primaryFieldId {
            <div key={fieldId} className="kanban-card-field">
              <span className="field-name"> {React.string(fieldName ++ ": ")} </span>
              <span className="field-value"> {React.string(valueText)} </span>
            </div>
          } else {
            React.null
          }
        })
        ->React.array}
      </div>
    </div>
  }

  // Render a column
  let renderColumn = (column: kanbanColumn) => {
    <div
      key={column.value}
      className="kanban-column"
      onDragOver={handleDragOver}
      onDrop={evt => handleDrop(column.value, evt)}
    >
      <div className="kanban-column-header">
        <h3 className="kanban-column-title"> {React.string(column.label)} </h3>
        <span className="kanban-column-count">
          {React.string(Int.toString(column.rows->Array.length))}
        </span>
      </div>
      <div className="kanban-column-cards">
        {column.rows->Array.map(row => renderCard(row, column.value))->React.array}
      </div>
    </div>
  }

  <div className="kanban-board">
    <div className="kanban-columns"> {allColumns->Array.map(renderColumn)->React.array} </div>
  </div>
}
