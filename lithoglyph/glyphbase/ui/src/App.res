// SPDX-License-Identifier: PMPL-1.0-or-later

open Types

// Type-safe DOM event listener bindings (eliminates Obj.magic)
@val external addKeydownListener: (string, Dom.keyboardEvent => unit) => unit = "document.addEventListener"
@val external removeKeydownListener: (string, Dom.keyboardEvent => unit) => unit = "document.removeEventListener"

// Demo data for development
let demoTable: table = {
  id: "tbl_demo",
  name: "Projects",
  primaryFieldId: "fld_name",
  fields: [
    {
      id: "fld_name",
      name: "Name",
      fieldType: Text,
      required: true,
      defaultValue: None,
      description: None,
    },
    {
      id: "fld_status",
      name: "Status",
      fieldType: Select(["Not Started", "In Progress", "Done"]),
      required: false,
      defaultValue: Some("Not Started"),
      description: None,
    },
    {
      id: "fld_tags",
      name: "Tags",
      fieldType: MultiSelect(["Frontend", "Backend", "Bug", "Feature", "Docs", "Urgent"]),
      required: false,
      defaultValue: None,
      description: None,
    },
    {
      id: "fld_priority",
      name: "Priority",
      fieldType: Number,
      required: false,
      defaultValue: None,
      description: None,
    },
    {
      id: "fld_due",
      name: "Due Date",
      fieldType: Date,
      required: false,
      defaultValue: None,
      description: None,
    },
    {
      id: "fld_done",
      name: "Complete",
      fieldType: Checkbox,
      required: false,
      defaultValue: None,
      description: None,
    },
  ],
}

let demoRows: array<row> = [
  {
    id: "row_1",
    createdAt: "2026-01-12T00:00:00Z",
    updatedAt: "2026-01-12T00:00:00Z",
    cells: Dict.fromArray([
      ("fld_name", {fieldId: "fld_name", value: TextValue("Build grid component"), provenance: []}),
      ("fld_status", {fieldId: "fld_status", value: SelectValue("In Progress"), provenance: []}),
      (
        "fld_tags",
        {fieldId: "fld_tags", value: MultiSelectValue(["Frontend", "Feature"]), provenance: []},
      ),
      ("fld_priority", {fieldId: "fld_priority", value: NumberValue(1.0), provenance: []}),
      (
        "fld_due",
        {fieldId: "fld_due", value: DateValue(Date.fromString("2026-01-15")), provenance: []},
      ),
      ("fld_done", {fieldId: "fld_done", value: CheckboxValue(false), provenance: []}),
    ]),
  },
  {
    id: "row_2",
    createdAt: "2026-01-12T00:00:00Z",
    updatedAt: "2026-01-12T00:00:00Z",
    cells: Dict.fromArray([
      (
        "fld_name",
        {fieldId: "fld_name", value: TextValue("Implement Lith bindings"), provenance: []},
      ),
      ("fld_status", {fieldId: "fld_status", value: SelectValue("Not Started"), provenance: []}),
      (
        "fld_tags",
        {
          fieldId: "fld_tags",
          value: MultiSelectValue(["Backend", "Feature", "Urgent"]),
          provenance: [],
        },
      ),
      ("fld_priority", {fieldId: "fld_priority", value: NumberValue(2.0), provenance: []}),
      (
        "fld_due",
        {fieldId: "fld_due", value: DateValue(Date.fromString("2026-01-20")), provenance: []},
      ),
      ("fld_done", {fieldId: "fld_done", value: CheckboxValue(false), provenance: []}),
    ]),
  },
  {
    id: "row_3",
    createdAt: "2026-01-12T00:00:00Z",
    updatedAt: "2026-01-12T00:00:00Z",
    cells: Dict.fromArray([
      (
        "fld_name",
        {fieldId: "fld_name", value: TextValue("Add real-time collaboration"), provenance: []},
      ),
      ("fld_status", {fieldId: "fld_status", value: SelectValue("Not Started"), provenance: []}),
      (
        "fld_tags",
        {
          fieldId: "fld_tags",
          value: MultiSelectValue(["Frontend", "Backend", "Feature"]),
          provenance: [],
        },
      ),
      ("fld_priority", {fieldId: "fld_priority", value: NumberValue(3.0), provenance: []}),
      (
        "fld_due",
        {fieldId: "fld_due", value: DateValue(Date.fromString("2026-02-01")), provenance: []},
      ),
      ("fld_done", {fieldId: "fld_done", value: CheckboxValue(false), provenance: []}),
    ]),
  },
]

// Demo presence data for collaboration features
let demoPresence: array<CollaborationStore.collaborativeUser> = [
  {clientId: "user_1", name: "Alice", color: "#3b82f6", cursor: None},
  {clientId: "user_2", name: "Bob", color: "#10b981", cursor: None},
  {
    clientId: "user_3",
    name: "Charlie",
    color: "#f59e0b",
    cursor: Some({rowId: "row_1", fieldId: "fld_status"}),
  },
]

module Sidebar = {
  @react.component
  let make = (
    ~bases: array<base>,
    ~currentBase: option<base>,
    ~onSelectBase: string => unit,
    ~onCreateBase: unit => unit,
    ~onDeleteBase: string => unit,
    ~onCreateTable: unit => unit,
    ~onDeleteTable: string => unit,
  ) => {
    <aside className="sidebar">
      <div className="sidebar-section">
        <div style={{display: "flex", justifyContent: "space-between", alignItems: "center"}}>
          <h3> {React.string("Bases")} </h3>
          <button className="sidebar-add-button" onClick={_ => onCreateBase()} title="New Base">
            {React.string("+")}
          </button>
        </div>
        {if Array.length(bases) == 0 {
          <div className="sidebar-empty"> {React.string("No bases yet")} </div>
        } else {
          bases
          ->Array.map(base => {
            let isActive = switch currentBase {
            | Some(cb) => cb.id == base.id
            | None => false
            }
            <div key={base.id} style={{display: "flex", alignItems: "center", gap: "4px"}}>
              <div
                className={"sidebar-item" ++ (isActive ? " active" : "")}
                onClick={_ => onSelectBase(base.id)}
                style={{flex: "1"}}
              >
                {switch base.icon {
                | Some(icon) => <span> {React.string(icon ++ " ")} </span>
                | None => React.null
                }}
                {React.string(base.name)}
              </div>
              <button
                className="sidebar-delete-button"
                onClick={_ => onDeleteBase(base.id)}
                title="Delete base"
              >
                {React.string("×")}
              </button>
            </div>
          })
          ->React.array
        }}
      </div>
      <div className="sidebar-section">
        <div style={{display: "flex", justifyContent: "space-between", alignItems: "center"}}>
          <h3> {React.string("Tables")} </h3>
          <button className="sidebar-add-button" onClick={_ => onCreateTable()} title="New Table">
            {React.string("+")}
          </button>
        </div>
        {switch currentBase {
        | Some(base) =>
          if Array.length(base.tables) == 0 {
            <div className="sidebar-empty"> {React.string("No tables yet")} </div>
          } else {
            base.tables
            ->Array.map(table => {
              <div key={table.id} style={{display: "flex", alignItems: "center", gap: "4px"}}>
                <div className="sidebar-item" style={{flex: "1"}}> {React.string(table.name)} </div>
                <button
                  className="sidebar-delete-button"
                  onClick={_ => onDeleteTable(table.id)}
                  title="Delete table"
                >
                  {React.string("×")}
                </button>
              </div>
            })
            ->React.array
          }
        | None => <div className="sidebar-empty"> {React.string("Select a base first")} </div>
        }}
      </div>
    </aside>
  }
}

module ViewTabs = {
  @react.component
  let make = () => {
    <div className="view-tabs">
      <button className="view-tab active"> {React.string("Grid")} </button>
      <button className="view-tab"> {React.string("Kanban")} </button>
      <button className="view-tab"> {React.string("Calendar")} </button>
      <button className="view-tab"> {React.string("Gallery")} </button>
      <button className="view-tab"> {React.string("+ Add View")} </button>
    </div>
  }
}

module FilterPanel = {
  @react.component
  let make = (
    ~fields: array<fieldConfig>,
    ~filters: array<GridStore.filterCondition>,
    ~onAddFilter: GridStore.filterCondition => unit,
    ~onRemoveFilter: string => unit,
    ~onUpdateFilter: GridStore.filterCondition => unit,
  ) => {
    let operatorOptions = [
      (GridStore.Contains, "contains"),
      (GridStore.DoesNotContain, "does not contain"),
      (GridStore.Is, "is"),
      (GridStore.IsNot, "is not"),
      (GridStore.IsEmpty, "is empty"),
      (GridStore.IsNotEmpty, "is not empty"),
      (GridStore.GreaterThan, ">"),
      (GridStore.LessThan, "<"),
      (GridStore.GreaterOrEqual, ">="),
      (GridStore.LessOrEqual, "<="),
    ]

    let operatorToString = (op: GridStore.filterOperator): string => {
      switch op {
      | Contains => "contains"
      | DoesNotContain => "does not contain"
      | Is => "is"
      | IsNot => "is not"
      | IsEmpty => "is empty"
      | IsNotEmpty => "is not empty"
      | GreaterThan => ">"
      | LessThan => "<"
      | GreaterOrEqual => ">="
      | LessOrEqual => "<="
      }
    }

    let stringToOperator = (s: string): GridStore.filterOperator => {
      switch s {
      | "contains" => Contains
      | "does not contain" => DoesNotContain
      | "is" => Is
      | "is not" => IsNot
      | "is empty" => IsEmpty
      | "is not empty" => IsNotEmpty
      | ">" => GreaterThan
      | "<" => LessThan
      | ">=" => GreaterOrEqual
      | "<=" => LessOrEqual
      | _ => Contains
      }
    }

    let handleAddFilter = () => {
      let firstField = fields->Array.get(0)
      switch firstField {
      | Some(field) =>
        onAddFilter({
          id: "filter_" ++ Float.toString(Date.now()),
          fieldId: field.id,
          operator: Contains,
          value: "",
        })
      | None => ()
      }
    }

    <div className="filter-panel">
      <div className="filter-panel-header">
        <span className="filter-panel-title"> {React.string("Filters")} </span>
        <button className="filter-add-button" onClick={_ => handleAddFilter()} type_="button">
          {React.string("+ Add filter")}
        </button>
      </div>
      <div className="filter-conditions">
        {filters
        ->Array.map(filter => {
          <div key={filter.id} className="filter-row">
            <select
              className="filter-field-select"
              value={filter.fieldId}
              onChange={e => {
                let newFieldId = ReactEvent.Form.target(e)["value"]
                onUpdateFilter({...filter, fieldId: newFieldId})
              }}
            >
              {fields
              ->Array.map(field =>
                <option key={field.id} value={field.id}> {React.string(field.name)} </option>
              )
              ->React.array}
            </select>
            <select
              className="filter-operator-select"
              value={operatorToString(filter.operator)}
              onChange={e => {
                let newOp = stringToOperator(ReactEvent.Form.target(e)["value"])
                onUpdateFilter({...filter, operator: newOp})
              }}
            >
              {operatorOptions
              ->Array.map(((_, label)) =>
                <option key={label} value={label}> {React.string(label)} </option>
              )
              ->React.array}
            </select>
            {switch filter.operator {
            | IsEmpty | IsNotEmpty => React.null
            | _ =>
              <input
                type_="text"
                className="filter-value-input"
                value={filter.value}
                placeholder="Value..."
                onChange={e => {
                  let newValue = ReactEvent.Form.target(e)["value"]
                  onUpdateFilter({...filter, value: newValue})
                }}
              />
            }}
            <button
              className="filter-remove-button"
              onClick={_ => onRemoveFilter(filter.id)}
              type_="button"
              title="Remove filter"
            >
              {React.string("x")}
            </button>
          </div>
        })
        ->React.array}
        {if Array.length(filters) == 0 {
          <div className="filter-empty"> {React.string("No filters applied")} </div>
        } else {
          React.null
        }}
      </div>
    </div>
  }
}

module HideFieldsPanel = {
  @react.component
  let make = (
    ~fields: array<fieldConfig>,
    ~hiddenColumns: array<string>,
    ~onToggleColumn: string => unit,
  ) => {
    <div className="hide-fields-panel">
      <div className="hide-fields-header">
        <span className="hide-fields-title"> {React.string("Fields")} </span>
      </div>
      <div className="hide-fields-list">
        {fields
        ->Array.map(field => {
          let isHidden = hiddenColumns->Array.includes(field.id)
          <label key={field.id} className={"hide-field-item" ++ (isHidden ? " hidden" : "")}>
            <input
              type_="checkbox"
              checked={!isHidden}
              onChange={_ => onToggleColumn(field.id)}
              className="hide-field-checkbox"
            />
            <span className="hide-field-name"> {React.string(field.name)} </span>
          </label>
        })
        ->React.array}
      </div>
      <div className="hide-fields-hint">
        {React.string("Uncheck to hide fields from the grid view")}
      </div>
    </div>
  }
}

module Toolbar = {
  @react.component
  let make = (
    ~filterCount: int,
    ~onToggleFilter: unit => unit,
    ~showFilter: bool,
    ~hiddenCount: int,
    ~onToggleHideFields: unit => unit,
    ~showHideFields: bool,
    ~searchTerm: string,
    ~onSearchChange: string => unit,
  ) => {
    <div className="toolbar">
      <button
        className={"toolbar-button" ++
        (showHideFields ? " active" : "") ++ (hiddenCount > 0 ? " has-filter" : "")}
        onClick={_ => onToggleHideFields()}
      >
        {React.string("Hide fields")}
        {if hiddenCount > 0 {
          <span className="filter-badge"> {React.string(Int.toString(hiddenCount))} </span>
        } else {
          React.null
        }}
      </button>
      <button
        className={"toolbar-button" ++
        (showFilter ? " active" : "") ++ (filterCount > 0 ? " has-filter" : "")}
        onClick={_ => onToggleFilter()}
      >
        {React.string("Filter")}
        {if filterCount > 0 {
          <span className="filter-badge"> {React.string(Int.toString(filterCount))} </span>
        } else {
          React.null
        }}
      </button>
      <button className="toolbar-button"> {React.string("Sort")} </button>
      <button className="toolbar-button"> {React.string("Group")} </button>
      <input
        type_="search"
        className="toolbar-search"
        placeholder="Search..."
        value={searchTerm}
        onChange={evt => {
          let value = %raw(`evt.target.value`)
          onSearchChange(value)
        }}
      />
    </div>
  }
}

@react.component
let make = () => {
  let (rows, setRows) = React.useState(() => demoRows)
  let (filters, setFilters) = Jotai.useAtom(GridStore.filtersAtom)
  let (filterConjunction, _setFilterConjunction) = Jotai.useAtom(GridStore.filterConjunctionAtom)
  let (sortConfig, setSortConfig) = Jotai.useAtom(GridStore.sortConfigAtom)
  let (hiddenColumns, setHiddenColumns) = Jotai.useAtom(GridStore.hiddenColumnsAtom)
  let (searchTerm, setSearchTerm) = Jotai.useAtom(GridStore.searchTermAtom)
  let (history, setHistory) = Jotai.useAtom(GridStore.historyAtom)
  let (showFilterPanel, setShowFilterPanel) = React.useState(() => false)
  let (showHideFieldsPanel, setShowHideFieldsPanel) = React.useState(() => false)

  // Base and table management
  let (bases, setBases) = Jotai.useAtom(BaseStore.basesAtom)
  let (currentBase, setCurrentBase) = Jotai.useAtom(BaseStore.currentBaseAtom)
  let (showCreateBaseModal, setShowCreateBaseModal) = React.useState(() => false)
  let (showCreateTableModal, setShowCreateTableModal) = React.useState(() => false)
  let (showDeleteBaseModal, setShowDeleteBaseModal) = React.useState(() => false)
  let (showDeleteTableModal, setShowDeleteTableModal) = React.useState(() => false)
  let (baseToDelete, setBaseToDelete) = React.useState(() => None)
  let (tableToDelete, setTableToDelete) = React.useState(() => None)
  let (newBaseName, setNewBaseName) = React.useState(() => "")
  let (newTableName, setNewTableName) = React.useState(() => "")

  // Initialize with demo base if no bases exist
  React.useEffect1(() => {
    if Array.length(bases) == 0 {
      let demoBase = BaseStore.createBase("Demo Base", Some("📊"))
      let demoTableWithBase = BaseStore.addTableToBase(demoBase, demoTable)
      setBases(_ => [demoTableWithBase])
      setCurrentBase(_ => Some(demoTableWithBase))
    }
    None
  }, [])

  // Apply search, filters, and sorting to get visible rows
  let searchedRows = GridStore.applySearch(rows, searchTerm)
  let filteredRows = GridStore.applyFilters(searchedRows, filters, filterConjunction)
  let sortedRows = GridStore.applySort(filteredRows, sortConfig)

  // Filter handlers
  let handleAddFilter = (filter: GridStore.filterCondition) => {
    setFilters(prev => Array.concat(prev, [filter]))
  }

  let handleRemoveFilter = (filterId: string) => {
    setFilters(prev => prev->Array.filter(f => f.id != filterId))
  }

  let handleUpdateFilter = (filter: GridStore.filterCondition) => {
    setFilters(prev => prev->Array.map(f => f.id == filter.id ? filter : f))
  }

  let handleToggleFilterPanel = () => {
    setShowFilterPanel(prev => !prev)
    setShowHideFieldsPanel(_ => false)
  }

  let handleToggleHideFieldsPanel = () => {
    setShowHideFieldsPanel(prev => !prev)
    setShowFilterPanel(_ => false)
  }

  // Toggle column visibility
  let handleToggleColumn = (fieldId: string) => {
    setHiddenColumns(prev => {
      if prev->Array.includes(fieldId) {
        prev->Array.filter(id => id != fieldId)
      } else {
        Array.concat(prev, [fieldId])
      }
    })
  }

  // Sort handler - toggle direction or set new field
  let handleSort = (fieldId: string) => {
    setSortConfig(prev => {
      switch prev {
      | Some({fieldId: currentFieldId, direction}) if currentFieldId == fieldId =>
        // Same field - toggle direction or clear
        switch direction {
        | #Asc => Some({GridStore.fieldId, direction: #Desc})
        | #Desc => None // Clear sort on third click
        }
      | _ =>
        // Different field - sort ascending
        Some({GridStore.fieldId, direction: #Asc})
      }
    })
  }

  // Base management handlers
  let handleSelectBase = (baseId: string) => {
    let selected = bases->Array.find(b => b.id == baseId)
    setCurrentBase(_ => selected)
  }

  let handleCreateBase = () => {
    if newBaseName->String.trim != "" {
      let newBase = BaseStore.createBase(newBaseName, None)
      setBases(prev => Array.concat(prev, [newBase]))
      setNewBaseName(_ => "")
      setShowCreateBaseModal(_ => false)
      setCurrentBase(_ => Some(newBase))
    }
  }

  let handleDeleteBase = (baseId: string) => {
    setBaseToDelete(_ => Some(baseId))
    setShowDeleteBaseModal(_ => true)
  }

  let confirmDeleteBase = () => {
    switch baseToDelete {
    | Some(baseId) => {
        setBases(prev => prev->Array.filter(b => b.id != baseId))
        // If deleting current base, clear selection
        switch currentBase {
        | Some(cb) if cb.id == baseId => setCurrentBase(_ => None)
        | _ => ()
        }
        setShowDeleteBaseModal(_ => false)
        setBaseToDelete(_ => None)
      }
    | None => ()
    }
  }

  // Table management handlers
  let handleCreateTable = () => {
    switch currentBase {
    | Some(base) =>
      if newTableName->String.trim != "" {
        let newTable = BaseStore.createTable(base.id, newTableName, "fld_name")
        let updatedBase = BaseStore.addTableToBase(base, newTable)
        setBases(prev => prev->Array.map(b => b.id == base.id ? updatedBase : b))
        setCurrentBase(_ => Some(updatedBase))
        setNewTableName(_ => "")
        setShowCreateTableModal(_ => false)
      }
    | None => Console.log("No base selected")
    }
  }

  let handleDeleteTable = (tableId: string) => {
    setTableToDelete(_ => Some(tableId))
    setShowDeleteTableModal(_ => true)
  }

  let confirmDeleteTable = () => {
    switch (currentBase, tableToDelete) {
    | (Some(base), Some(tableId)) => {
        let updatedBase = BaseStore.removeTableFromBase(base, tableId)
        setBases(prev => prev->Array.map(b => b.id == base.id ? updatedBase : b))
        setCurrentBase(_ => Some(updatedBase))
        setShowDeleteTableModal(_ => false)
        setTableToDelete(_ => None)
      }
    | _ => ()
    }
  }

  // Convert cellValue to JSON for API
  let cellValueToJson = (value: cellValue): JSON.t => {
    switch value {
    | TextValue(s) => JSON.Encode.string(s)
    | NumberValue(n) => JSON.Encode.float(n)
    | CheckboxValue(b) => JSON.Encode.bool(b)
    | SelectValue(s) => JSON.Encode.string(s)
    | MultiSelectValue(arr) => JSON.Encode.array(arr->Array.map(JSON.Encode.string))
    | DateValue(d) => JSON.Encode.string(Date.toISOString(d))
    | LinkValue(ids) => JSON.Encode.array(ids->Array.map(JSON.Encode.string))
    | NullValue => JSON.Encode.null
    | _ => JSON.Encode.null
    }
  }

  // Handle cell updates
  let handleCellUpdate = (rowId: string, fieldId: string, newValue: cellValue) => {
    // Get old value for undo/redo
    let oldValue =
      rows
      ->Array.find(r => r.id == rowId)
      ->Option.flatMap(r => r.cells->Dict.get(fieldId))
      ->Option.map(c => c.value)
      ->Option.getOr(NullValue)

    // Record to history
    setHistory(prev => GridStore.recordEdit(prev, rowId, fieldId, oldValue, newValue))

    // Optimistic update - update local state first
    setRows(prevRows => {
      prevRows->Array.map(row => {
        if row.id == rowId {
          let newCells =
            row.cells
            ->Dict.toArray
            ->Array.map(
              ((key, cell)) => {
                if key == fieldId {
                  (
                    key,
                    {
                      ...cell,
                      value: newValue,
                    },
                  )
                } else {
                  (key, cell)
                }
              },
            )
            ->Dict.fromArray

          // Add the cell if it doesn't exist
          if !(newCells->Dict.keysToArray->Array.includes(fieldId)) {
            newCells->Dict.set(
              fieldId,
              {
                fieldId,
                value: newValue,
                provenance: [],
              },
            )
          }

          {
            ...row,
            cells: newCells,
            updatedAt: Date.toISOString(Date.make()),
          }
        } else {
          row
        }
      })
    })

    // Sync with backend via API
    let _ = Client.updateCell(
      "base_demo",
      demoTable.id,
      rowId,
      fieldId,
      cellValueToJson(newValue),
      (),
    )->Promise.thenResolve(result => {
      switch result {
      | Ok(_) => Console.log("Cell updated successfully")
      | Error(err) => Console.error2("Failed to update cell:", err.message)
      }
    })
  }

  // Handle undo
  let handleUndo = () => {
    if GridStore.canUndo(history) {
      let (newHistory, action) = GridStore.performUndo(history)
      setHistory(_ => newHistory)

      switch action {
      | Some({rowId, fieldId, oldValue, newValue: _}) => {
          // Apply the old value
          setRows(prevRows => {
            prevRows->Array.map(row => {
              if row.id == rowId {
                let newCells =
                  row.cells
                  ->Dict.toArray
                  ->Array.map(
                    ((key, cell)) => {
                      if key == fieldId {
                        (key, {...cell, value: oldValue})
                      } else {
                        (key, cell)
                      }
                    },
                  )
                  ->Dict.fromArray

                {...row, cells: newCells, updatedAt: Date.toISOString(Date.make())}
              } else {
                row
              }
            })
          })

          // Sync with backend
          let _ = Client.updateCell(
            "base_demo",
            demoTable.id,
            rowId,
            fieldId,
            cellValueToJson(oldValue),
            (),
          )
        }
      | None => ()
      }
    }
  }

  // Handle redo
  let handleRedo = () => {
    if GridStore.canRedo(history) {
      let (newHistory, action) = GridStore.performRedo(history)
      setHistory(_ => newHistory)

      switch action {
      | Some({rowId, fieldId, oldValue: _, newValue}) => {
          // Apply the new value
          setRows(prevRows => {
            prevRows->Array.map(row => {
              if row.id == rowId {
                let newCells =
                  row.cells
                  ->Dict.toArray
                  ->Array.map(
                    ((key, cell)) => {
                      if key == fieldId {
                        (key, {...cell, value: newValue})
                      } else {
                        (key, cell)
                      }
                    },
                  )
                  ->Dict.fromArray

                {...row, cells: newCells, updatedAt: Date.toISOString(Date.make())}
              } else {
                row
              }
            })
          })

          // Sync with backend
          let _ = Client.updateCell(
            "base_demo",
            demoTable.id,
            rowId,
            fieldId,
            cellValueToJson(newValue),
            (),
          )
        }
      | None => ()
      }
    }
  }

  // Handle adding a new row
  let handleAddRow = () => {
    let newRowId =
      "row_" ++ Int.toString(Array.length(rows) + 1) ++ "_" ++ Float.toString(Date.now())
    let now = Date.toISOString(Date.make())

    // Create empty cells with default values
    let emptyCells =
      demoTable.fields
      ->Array.map(field => {
        let defaultValue = switch field.defaultValue {
        | Some(v) => TextValue(v)
        | None => NullValue
        }
        (field.id, {fieldId: field.id, value: defaultValue, provenance: []})
      })
      ->Dict.fromArray

    let newRow: row = {
      id: newRowId,
      cells: emptyCells,
      createdAt: now,
      updatedAt: now,
    }

    // Optimistic update - add to local state first
    setRows(prevRows => Array.concat(prevRows, [newRow]))

    // Sync with backend via API
    let cellsJson =
      emptyCells
      ->Dict.toArray
      ->Array.map(((fieldId, cell)) => {
        (fieldId, cellValueToJson(cell.value))
      })
      ->Dict.fromArray

    let _ = Client.createRow(
      "base_demo",
      demoTable.id,
      newRowId,
      cellsJson,
    )->Promise.thenResolve(result => {
      switch result {
      | Ok(_) => Console.log2("Row created successfully:", newRowId)
      | Error(err) => Console.error2("Failed to create row:", err.message)
      }
    })
  }

  // Handle deleting a row
  let handleDeleteRow = (rowId: string) => {
    // Optimistic update - remove from local state first
    setRows(prevRows => prevRows->Array.filter(row => row.id != rowId))

    // Sync with backend via API
    let _ = Client.deleteRow("base_demo", demoTable.id, rowId)->Promise.thenResolve(result => {
      switch result {
      | Ok(_) => Console.log2("Row deleted successfully:", rowId)
      | Error(err) => Console.error2("Failed to delete row:", err.message)
      }
    })
  }

  // Keyboard shortcuts for undo/redo
  React.useEffect0(() => {
    let handleKeyDown = (evt: Dom.keyboardEvent) => {
      let ctrlOrCmd = %raw(`evt.ctrlKey || evt.metaKey`)
      let shift = %raw(`evt.shiftKey`)
      let key = %raw(`evt.key`)

      // Ctrl+Z or Cmd+Z for undo
      if ctrlOrCmd && !shift && key == "z" {
        %raw(`evt.preventDefault()`)
        handleUndo()
      }

      // Ctrl+Y or Ctrl+Shift+Z or Cmd+Shift+Z for redo
      if (ctrlOrCmd && key == "y") || (ctrlOrCmd && shift && key == "z") {
        %raw(`evt.preventDefault()`)
        handleRedo()
      }
    }

    // Type-safe keydown listener via external binding (no Obj.magic)
    addKeydownListener("keydown", handleKeyDown)

    Some(
      () => {
        removeKeydownListener("keydown", handleKeyDown)
      },
    )
  })

  <Jotai.Provider>
    <div className="formbase-app">
      <header className="formbase-header">
        <h1> {React.string("FormBase")} </h1>
        <p> {React.string("Open-source Airtable alternative with provenance tracking")} </p>
      </header>
      <main className="formbase-main">
        <Sidebar
          bases={bases}
          currentBase={currentBase}
          onSelectBase={handleSelectBase}
          onCreateBase={() => setShowCreateBaseModal(_ => true)}
          onDeleteBase={handleDeleteBase}
          onCreateTable={() => setShowCreateTableModal(_ => true)}
          onDeleteTable={handleDeleteTable}
        />
        <div style={{display: "flex", flexDirection: "column", flex: "1"}}>
          <ViewTabs />
          <Toolbar
            filterCount={Array.length(filters)}
            onToggleFilter={handleToggleFilterPanel}
            showFilter={showFilterPanel}
            hiddenCount={Array.length(hiddenColumns)}
            onToggleHideFields={handleToggleHideFieldsPanel}
            showHideFields={showHideFieldsPanel}
            searchTerm={searchTerm}
            onSearchChange={value => setSearchTerm(_ => value)}
          />
          {if showHideFieldsPanel {
            <HideFieldsPanel
              fields={demoTable.fields} hiddenColumns onToggleColumn={handleToggleColumn}
            />
          } else if showFilterPanel {
            <FilterPanel
              fields={demoTable.fields}
              filters
              onAddFilter={handleAddFilter}
              onRemoveFilter={handleRemoveFilter}
              onUpdateFilter={handleUpdateFilter}
            />
          } else {
            React.null
          }}
          <div style={{position: "relative"}}>
            <Grid
              table={demoTable}
              rows={sortedRows}
              onCellUpdate={handleCellUpdate}
              onAddRow={handleAddRow}
              onDeleteRow={handleDeleteRow}
              sortConfig
              onSort={handleSort}
              hiddenColumns
            />
            <LiveCursors users={demoPresence} />
          </div>
          <PresenceIndicators users={demoPresence} />
        </div>
      </main>

      <Modal
        isOpen={showCreateBaseModal}
        onClose={() => setShowCreateBaseModal(_ => false)}
        title="Create New Base"
      >
        <div className="modal-form">
          <div className="modal-form-group">
            <label className="modal-form-label"> {React.string("Base Name")} </label>
            <input
              type_="text"
              className="modal-form-input"
              placeholder="My Base"
              value={newBaseName}
              onChange={evt => {
                let value = %raw(`evt.target.value`)
                setNewBaseName(_ => value)
              }}
              onKeyDown={evt => {
                if evt->ReactEvent.Keyboard.key == "Enter" {
                  handleCreateBase()
                }
              }}
            />
          </div>
          <div className="modal-form-actions">
            <button className="modal-button" onClick={_ => setShowCreateBaseModal(_ => false)}>
              {React.string("Cancel")}
            </button>
            <button className="modal-button modal-button-primary" onClick={_ => handleCreateBase()}>
              {React.string("Create")}
            </button>
          </div>
        </div>
      </Modal>

      <Modal
        isOpen={showCreateTableModal}
        onClose={() => setShowCreateTableModal(_ => false)}
        title="Create New Table"
      >
        <div className="modal-form">
          <div className="modal-form-group">
            <label className="modal-form-label"> {React.string("Table Name")} </label>
            <input
              type_="text"
              className="modal-form-input"
              placeholder="My Table"
              value={newTableName}
              onChange={evt => {
                let value = %raw(`evt.target.value`)
                setNewTableName(_ => value)
              }}
              onKeyDown={evt => {
                if evt->ReactEvent.Keyboard.key == "Enter" {
                  handleCreateTable()
                }
              }}
            />
          </div>
          <div className="modal-form-actions">
            <button className="modal-button" onClick={_ => setShowCreateTableModal(_ => false)}>
              {React.string("Cancel")}
            </button>
            <button
              className="modal-button modal-button-primary" onClick={_ => handleCreateTable()}
            >
              {React.string("Create")}
            </button>
          </div>
        </div>
      </Modal>

      <Modal
        isOpen={showDeleteBaseModal}
        onClose={() => setShowDeleteBaseModal(_ => false)}
        title="Delete Base"
      >
        <div className="modal-form">
          <p> {React.string("Are you sure you want to delete this base and all its tables?")} </p>
          <div className="modal-form-actions">
            <button className="modal-button" onClick={_ => setShowDeleteBaseModal(_ => false)}>
              {React.string("Cancel")}
            </button>
            <button className="modal-button modal-button-danger" onClick={_ => confirmDeleteBase()}>
              {React.string("Delete")}
            </button>
          </div>
        </div>
      </Modal>

      <Modal
        isOpen={showDeleteTableModal}
        onClose={() => setShowDeleteTableModal(_ => false)}
        title="Delete Table"
      >
        <div className="modal-form">
          <p> {React.string("Are you sure you want to delete this table?")} </p>
          <div className="modal-form-actions">
            <button className="modal-button" onClick={_ => setShowDeleteTableModal(_ => false)}>
              {React.string("Cancel")}
            </button>
            <button
              className="modal-button modal-button-danger" onClick={_ => confirmDeleteTable()}
            >
              {React.string("Delete")}
            </button>
          </div>
        </div>
      </Modal>
    </div>
  </Jotai.Provider>
}
