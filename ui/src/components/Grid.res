// SPDX-License-Identifier: PMPL-1.0-or-later
// Grid component - the core spreadsheet-like view

open Types

// Helper to convert cellValue to editable string
let cellValueToString = (value: cellValue): string => {
  switch value {
  | TextValue(s) => s
  | NumberValue(n) => Float.toString(n)
  | CheckboxValue(b) => b ? "true" : "false"
  | SelectValue(s) => s
  | MultiSelectValue(arr) => arr->Array.join(", ")
  | DateValue(d) => Date.toISOString(d)->String.slice(~start=0, ~end=10)
  | LinkValue(ids) => ids->Array.join(", ")
  | NullValue => ""
  | _ => ""
  }
}

// Helper to parse string back to cellValue based on field type
let stringToCellValue = (s: string, fieldType: fieldType): cellValue => {
  if s == "" {
    NullValue
  } else {
    switch fieldType {
    | Text | Url | Email | Phone | Barcode => TextValue(s)
    | Number | Rating => switch Float.fromString(s) {
      | Some(n) => NumberValue(n)
      | None => TextValue(s)
      }
    | Checkbox => CheckboxValue(s == "true" || s == "1" || s == "yes")
    | Select(_) => SelectValue(s)
    | MultiSelect(_) => MultiSelectValue(s->String.split(",")->Array.map(String.trim))
    | Date | DateTime => {
        let d = Date.fromString(s)
        if Float.isNaN(Date.getTime(d)) {
          TextValue(s)
        } else {
          DateValue(d)
        }
      }
    | Link(_) => LinkValue(s->String.split(",")->Array.map(String.trim))
    | Formula(_) | Rollup(_, _) | Lookup(_, _) => TextValue(s) // Read-only fields
    | Attachment => NullValue // Attachments need special handling
    }
  }
}

module EditableInput = {
  @react.component
  let make = (
    ~value: string,
    ~fieldType: fieldType,
    ~onChange: string => unit,
    ~onSave: unit => unit,
    ~onCancel: unit => unit,
  ) => {
    let inputRef = React.useRef(Nullable.null)

    // Auto-focus on mount
    React.useEffect0(() => {
      switch inputRef.current->Nullable.toOption {
      | Some(el) => {
          let domEl = el->Obj.magic
          domEl["focus"]()
          domEl["select"]()
        }
      | None => ()
      }
      None
    })

    let handleKeyDown = (e: ReactEvent.Keyboard.t) => {
      let key = ReactEvent.Keyboard.key(e)
      switch key {
      | "Enter" => {
          ReactEvent.Keyboard.preventDefault(e)
          onSave()
        }
      | "Escape" => {
          ReactEvent.Keyboard.preventDefault(e)
          onCancel()
        }
      | "Tab" => // Let Tab propagate for cell navigation
        onSave()
      | _ => ()
      }
    }

    let handleBlur = (_: ReactEvent.Focus.t) => {
      onSave()
    }

    // Render different input types based on field type
    switch fieldType {
    | Checkbox => <input
        ref={ReactDOM.Ref.domRef(inputRef)}
        type_="checkbox"
        checked={value == "true"}
        onChange={e => {
          let checked = %raw(`e.target.checked`)
          onChange(checked ? "true" : "false")
        }}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-checkbox"
      />
    | Number | Rating => <input
        ref={ReactDOM.Ref.domRef(inputRef)}
        type_="number"
        value
        onChange={e => onChange(%raw(`e.target.value`))}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-number"
      />
    | Date => <input
        ref={ReactDOM.Ref.domRef(inputRef)}
        type_="date"
        value
        onChange={e => onChange(%raw(`e.target.value`))}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-date"
      />
    | DateTime => <input
        ref={ReactDOM.Ref.domRef(inputRef)}
        type_="datetime-local"
        value
        onChange={e => onChange(%raw(`e.target.value`))}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-datetime"
      />
    | Select(options) => <select
        ref={ReactDOM.Ref.domRef(inputRef)}
        value
        onChange={e => onChange(%raw(`e.target.value`))}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-select"
      >
        <option value=""> {React.string("Select...")} </option>
        {options
        ->Array.map(opt => <option key={opt} value={opt}> {React.string(opt)} </option>)
        ->React.array}
      </select>
    | MultiSelect(options) => {
        // Parse current value to array of selected options
        let selectedValues =
          value->String.split(",")->Array.map(String.trim)->Array.filter(s => s != "")

        let toggleOption = (opt: string) => {
          let newSelected = if selectedValues->Array.includes(opt) {
            selectedValues->Array.filter(v => v != opt)
          } else {
            Array.concat(selectedValues, [opt])
          }
          onChange(newSelected->Array.join(", "))
        }

        <div className="multiselect-dropdown" tabIndex={0}>
          <div className="multiselect-header">
            {React.string(
              if Array.length(selectedValues) == 0 {
                "Select options..."
              } else {
                Int.toString(Array.length(selectedValues)) ++ " selected"
              },
            )}
          </div>
          <div className="multiselect-options">
            {options
            ->Array.map(opt => {
              let isSelected = selectedValues->Array.includes(opt)
              <label key={opt} className={"multiselect-option" ++ (isSelected ? " selected" : "")}>
                <input
                  type_="checkbox"
                  checked={isSelected}
                  onChange={_ => toggleOption(opt)}
                  className="multiselect-checkbox"
                />
                <span className="multiselect-label"> {React.string(opt)} </span>
              </label>
            })
            ->React.array}
          </div>
          <div className="multiselect-actions">
            <button type_="button" className="multiselect-done" onClick={_ => onSave()}>
              {React.string("Done")}
            </button>
          </div>
        </div>
      }
    | Url => <input
        ref={ReactDOM.Ref.domRef(inputRef)}
        type_="url"
        value
        placeholder="https://"
        onChange={e => onChange(%raw(`e.target.value`))}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-url"
      />
    | Email => <input
        ref={ReactDOM.Ref.domRef(inputRef)}
        type_="email"
        value
        placeholder="email@example.com"
        onChange={e => onChange(%raw(`e.target.value`))}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-email"
      />
    | Formula(_) | Rollup(_, _) | Lookup(_, _) => // Read-only computed fields
      <div className="grid-cell-readonly"> {React.string(value)} </div>
    | _ => // Default text input
      <input
        ref={ReactDOM.Ref.domRef(inputRef)}
        type_="text"
        value
        onChange={e => onChange(%raw(`e.target.value`))}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="grid-cell-input grid-cell-text"
      />
    }
  }
}

module Cell = {
  @react.component
  let make = (
    ~row: row,
    ~field: fieldConfig,
    ~isEditing: bool,
    ~editValue: string,
    ~onStartEdit: string => unit,
    ~onEditChange: string => unit,
    ~onSaveEdit: unit => unit,
    ~onCancelEdit: unit => unit,
  ) => {
    let cell = row.cells->Dict.get(field.id)
    let value = cell->Option.map(c => c.value)->Option.getOr(NullValue)

    // For multi-select, we render tags instead of plain text
    let isMultiSelect = switch field.fieldType {
    | MultiSelect(_) => true
    | _ => false
    }

    let displayValue = switch value {
    | TextValue(s) => s
    | NumberValue(n) => Float.toString(n)
    | CheckboxValue(b) => b ? "[x]" : "[ ]"
    | SelectValue(s) => s
    | MultiSelectValue(arr) => arr->Array.join(", ")
    | DateValue(d) => Date.toLocaleDateString(d)
    | LinkValue(ids) => ids->Array.length->Int.toString ++ " linked"
    | NullValue => ""
    | _ => "..."
    }

    let multiSelectTags = switch value {
    | MultiSelectValue(arr) if Array.length(arr) > 0 =>
      <div className="multiselect-tags">
        {arr
        ->Array.map(tag => <span key={tag} className="multiselect-tag"> {React.string(tag)} </span>)
        ->React.array}
      </div>
    | _ => React.null
    }

    let isComputed = switch field.fieldType {
    | Formula(_) | Rollup(_, _) | Lookup(_, _) => true
    | _ => false
    }

    let handleClick = (_: ReactEvent.Mouse.t) => {
      if !isEditing && !isComputed {
        onStartEdit(cellValueToString(value))
      }
    }

    let handleDoubleClick = (_: ReactEvent.Mouse.t) => {
      if !isEditing && !isComputed {
        onStartEdit(cellValueToString(value))
      }
    }

    <div
      className={"grid-cell" ++ (isEditing ? " editing" : "") ++ (isComputed ? " computed" : "")}
      onClick={handleClick}
      onDoubleClick={handleDoubleClick}
      role="gridcell"
      tabIndex=0
    >
      {if isEditing {
        <EditableInput
          value={editValue}
          fieldType={field.fieldType}
          onChange={onEditChange}
          onSave={onSaveEdit}
          onCancel={onCancelEdit}
        />
      } else if isMultiSelect {
        multiSelectTags
      } else {
        React.string(displayValue)
      }}
    </div>
  }
}

module HeaderCell = {
  @react.component
  let make = (
    ~field: fieldConfig,
    ~width: int,
    ~sortConfig: option<GridStore.sortConfig>,
    ~onSort: string => unit,
    ~onResize: (string, int) => unit,
  ) => {
    let (isResizing, setIsResizing) = React.useState(() => false)
    let startXRef = React.useRef(0)
    let startWidthRef = React.useRef(width)

    let icon = switch field.fieldType {
    | Text => "Aa"
    | Number => "#"
    | Select(_) => "v"
    | MultiSelect(_) => "vv"
    | Date | DateTime => "D"
    | Checkbox => "[]"
    | Url => "@"
    | Email => "M"
    | _ => "?"
    }

    let isSorted = sortConfig->Option.map(s => s.fieldId == field.id)->Option.getOr(false)
    let sortDirection = sortConfig->Option.flatMap(s =>
      if s.fieldId == field.id {
        Some(s.direction)
      } else {
        None
      }
    )

    let sortIndicator = switch sortDirection {
    | Some(#Asc) => " ↑"
    | Some(#Desc) => " ↓"
    | None => ""
    }

    // Handle resize drag
    React.useEffect1(() => {
      if isResizing {
        let handleMouseMove = (e: Dom.mouseEvent) => {
          let clientX = e->Obj.magic->Dict.get("clientX")->Option.getOr(0.0)->Float.toInt
          let delta = clientX - startXRef.current
          let calculatedWidth = startWidthRef.current + delta
          let newWidth = if calculatedWidth < 50 {
            50
          } else {
            calculatedWidth
          }
          onResize(field.id, newWidth)
        }

        let handleMouseUp = (_: Dom.mouseEvent) => {
          setIsResizing(_ => false)
        }

        let doc = Webapi.Dom.document
        doc->Webapi.Dom.Document.addMouseMoveEventListener(handleMouseMove)
        doc->Webapi.Dom.Document.addMouseUpEventListener(handleMouseUp)

        Some(
          () => {
            doc->Webapi.Dom.Document.removeMouseMoveEventListener(handleMouseMove)
            doc->Webapi.Dom.Document.removeMouseUpEventListener(handleMouseUp)
          },
        )
      } else {
        None
      }
    }, [isResizing])

    let handleResizeStart = (e: ReactEvent.Mouse.t) => {
      ReactEvent.Mouse.stopPropagation(e)
      ReactEvent.Mouse.preventDefault(e)
      startXRef.current = ReactEvent.Mouse.clientX(e)
      startWidthRef.current = width
      setIsResizing(_ => true)
    }

    <div
      className={"grid-header-cell" ++ (isSorted ? " sorted" : "")}
      style={{width: Int.toString(width) ++ "px"}}
      role="columnheader"
      onClick={_ => onSort(field.id)}
    >
      <span className="field-icon"> {React.string(icon)} </span>
      <span className="field-name"> {React.string(field.name)} </span>
      {if isSorted {
        <span className="sort-indicator"> {React.string(sortIndicator)} </span>
      } else {
        React.null
      }}
      <div
        className={"resize-handle" ++ (isResizing ? " resizing" : "")}
        onMouseDown={handleResizeStart}
      />
    </div>
  }
}

module Row = {
  @react.component
  let make = (
    ~row: row,
    ~fields: array<fieldConfig>,
    ~rowIndex: int,
    ~editingCell: option<GridStore.editingCell>,
    ~editValue: string,
    ~onStartEdit: (string, string, string) => unit,
    ~onEditChange: string => unit,
    ~onSaveEdit: unit => unit,
    ~onCancelEdit: unit => unit,
    ~onDeleteRow: string => unit,
  ) => {
    let (showDeleteConfirm, setShowDeleteConfirm) = React.useState(() => false)

    <div className="grid-row" role="row">
      <div className="grid-row-number">
        {if showDeleteConfirm {
          <div className="delete-confirm">
            <button
              className="delete-confirm-yes"
              onClick={_ => {
                onDeleteRow(row.id)
                setShowDeleteConfirm(_ => false)
              }}
              title="Confirm delete"
            >
              {React.string("Y")}
            </button>
            <button
              className="delete-confirm-no"
              onClick={_ => setShowDeleteConfirm(_ => false)}
              title="Cancel"
            >
              {React.string("N")}
            </button>
          </div>
        } else {
          <>
            <span className="row-number-text"> {React.string(Int.toString(rowIndex + 1))} </span>
            <button
              className="delete-row-button"
              onClick={_ => setShowDeleteConfirm(_ => true)}
              title="Delete row"
            >
              {React.string("x")}
            </button>
          </>
        }}
      </div>
      {fields
      ->Array.mapWithIndex((field, _fieldIndex) => {
        let isEditing =
          editingCell
          ->Option.map(e => e.rowId == row.id && e.fieldId == field.id)
          ->Option.getOr(false)
        <Cell
          key={field.id}
          row
          field
          isEditing
          editValue={isEditing ? editValue : ""}
          onStartEdit={initialValue => onStartEdit(row.id, field.id, initialValue)}
          onEditChange
          onSaveEdit
          onCancelEdit
        />
      })
      ->React.array}
    </div>
  }
}

@react.component
let make = (
  ~table: table,
  ~rows: array<row>,
  ~onCellUpdate: (string, string, cellValue) => unit,
  ~onAddRow: unit => unit,
  ~onDeleteRow: string => unit,
  ~sortConfig: option<GridStore.sortConfig>,
  ~onSort: string => unit,
  ~hiddenColumns: array<string>,
) => {
  let (editingCell, setEditingCell) = Jotai.useAtom(GridStore.editingCellAtom)
  let (editValue, setEditValue) = Jotai.useAtom(GridStore.editValueAtom)
  let (columnWidths, setColumnWidths) = Jotai.useAtom(GridStore.columnWidthsAtom)

  // Filter out hidden columns
  let visibleFields =
    table.fields->Array.filter(field => !(hiddenColumns->Array.includes(field.id)))

  let getColumnWidth = (fieldId: string) => {
    columnWidths->Dict.get(fieldId)->Option.getOr(150)
  }

  // Handle column resize
  let handleColumnResize = (fieldId: string, newWidth: int) => {
    setColumnWidths(prev => {
      let updated = prev->Dict.toArray->Dict.fromArray
      updated->Dict.set(fieldId, newWidth)
      updated
    })
  }

  // Start editing a cell
  let handleStartEdit = (rowId: string, fieldId: string, initialValue: string) => {
    setEditingCell(_ => Some({GridStore.rowId, fieldId}))
    setEditValue(_ => initialValue)
  }

  // Update the edit value as user types
  let handleEditChange = (newValue: string) => {
    setEditValue(_ => newValue)
  }

  // Save the current edit
  let handleSaveEdit = () => {
    switch editingCell {
    | Some({rowId, fieldId}) => {
        // Find the field to get its type
        let fieldOpt = table.fields->Array.find(f => f.id == fieldId)
        switch fieldOpt {
        | Some(field) => {
            let newCellValue = stringToCellValue(editValue, field.fieldType)
            onCellUpdate(rowId, fieldId, newCellValue)
          }
        | None => ()
        }
        setEditingCell(_ => None)
        setEditValue(_ => "")
      }
    | None => ()
    }
  }

  // Cancel edit and revert
  let handleCancelEdit = () => {
    setEditingCell(_ => None)
    setEditValue(_ => "")
  }

  // Find field index by id
  let findFieldIndex = (fieldId: string): int => {
    visibleFields->Array.findIndexOpt(f => f.id == fieldId)->Option.getOr(0)
  }

  // Find row index by id
  let findRowIndex = (rowId: string): int => {
    rows->Array.findIndexOpt(r => r.id == rowId)->Option.getOr(0)
  }

  // Move to adjacent cell
  let moveToCell = (rowDelta: int, colDelta: int) => {
    switch editingCell {
    | Some({rowId, fieldId}) => {
        let currentRowIdx = findRowIndex(rowId)
        let currentColIdx = findFieldIndex(fieldId)
        let newRowIdx = currentRowIdx + rowDelta
        let newColIdx = currentColIdx + colDelta

        // Bounds checking
        if (
          newRowIdx >= 0 &&
          newRowIdx < Array.length(rows) &&
          newColIdx >= 0 &&
          newColIdx < Array.length(visibleFields)
        ) {
          let newRow = rows->Array.getUnsafe(newRowIdx)
          let newField = visibleFields->Array.getUnsafe(newColIdx)
          let cell = newRow.cells->Dict.get(newField.id)
          let value = cell->Option.map(c => c.value)->Option.getOr(NullValue)
          handleStartEdit(newRow.id, newField.id, cellValueToString(value))
        }
      }
    | None => // Start editing first cell if not editing
      if Array.length(rows) > 0 && Array.length(visibleFields) > 0 {
        let firstRow = rows->Array.getUnsafe(0)
        let firstField = visibleFields->Array.getUnsafe(0)
        let cell = firstRow.cells->Dict.get(firstField.id)
        let value = cell->Option.map(c => c.value)->Option.getOr(NullValue)
        handleStartEdit(firstRow.id, firstField.id, cellValueToString(value))
      }
    }
  }

  let handleKeyDown = (e: ReactEvent.Keyboard.t) => {
    let key = ReactEvent.Keyboard.key(e)
    switch key {
    | "Escape" => handleCancelEdit()
    | "Tab" => {
        ReactEvent.Keyboard.preventDefault(e)
        handleSaveEdit()

        // Move to next cell
        if ReactEvent.Keyboard.shiftKey(e) {
          moveToCell(0, -1) // Shift+Tab goes left
        } else {
          moveToCell(0, 1) // Tab goes right
        }
      }
    | "Enter" => if editingCell->Option.isSome {
        handleSaveEdit()
        moveToCell(1, 0) // Move down after enter
      } else {
        // Start editing current selection
        moveToCell(0, 0)
      }
    | "ArrowUp" =>
      if editingCell->Option.isNone {
        ReactEvent.Keyboard.preventDefault(e)
        moveToCell(-1, 0)
      }
    | "ArrowDown" =>
      if editingCell->Option.isNone {
        ReactEvent.Keyboard.preventDefault(e)
        moveToCell(1, 0)
      }
    | "ArrowLeft" =>
      if editingCell->Option.isNone {
        ReactEvent.Keyboard.preventDefault(e)
        moveToCell(0, -1)
      }
    | "ArrowRight" =>
      if editingCell->Option.isNone {
        ReactEvent.Keyboard.preventDefault(e)
        moveToCell(0, 1)
      }
    | _ => ()
    }
  }

  <div className="grid-container" role="grid" onKeyDown={handleKeyDown} tabIndex=0>
    <div className="grid-header" role="rowgroup">
      <div className="grid-row" role="row">
        <div className="grid-row-number-header"> {React.string("#")} </div>
        {visibleFields
        ->Array.map(field => {
          <HeaderCell
            key={field.id}
            field
            width={getColumnWidth(field.id)}
            sortConfig
            onSort
            onResize={handleColumnResize}
          />
        })
        ->React.array}
      </div>
    </div>
    <div className="grid-body" role="rowgroup">
      {rows
      ->Array.mapWithIndex((row, i) => {
        <Row
          key={row.id}
          row
          fields={visibleFields}
          rowIndex={i}
          editingCell
          editValue
          onStartEdit={handleStartEdit}
          onEditChange={handleEditChange}
          onSaveEdit={handleSaveEdit}
          onCancelEdit={handleCancelEdit}
          onDeleteRow
        />
      })
      ->React.array}
      <button className="add-row-button" onClick={_ => onAddRow()} type_="button">
        {React.string("+ Add row")}
      </button>
    </div>
  </div>
}
