// SPDX-License-Identifier: PMPL-1.0-or-later
// State management for bases and tables

open Types

// Current base state
let currentBaseAtom: Jotai.atom<option<base>> = Jotai.atom(None)

// All bases (for sidebar)
let basesAtom: Jotai.atom<array<base>> = Jotai.atom([])

// Current table
let currentTableAtom: Jotai.atom<option<table>> = Jotai.atom(None)

// Current view
let currentViewAtom: Jotai.atom<option<viewConfig>> = Jotai.atom(None)

// Loading states
let isLoadingAtom: Jotai.atom<bool> = Jotai.atom(false)

// Error state
let errorAtom: Jotai.atom<option<string>> = Jotai.atom(None)

// Helper functions for base/table management
let createBase = (name: string, icon: option<string>): base => {
  let id = "base_" ++ Float.toString(Date.now())
  {
    id,
    name,
    description: None,
    icon,
    tables: [],
    views: [],
    createdAt: Date.toISOString(Date.make()),
    updatedAt: Date.toISOString(Date.make()),
  }
}

let createTable = (baseId: string, name: string, primaryFieldId: string): table => {
  let id = "tbl_" ++ Float.toString(Date.now())
  {
    id,
    name,
    primaryFieldId,
    fields: [],
  }
}

let addTableToBase = (base: base, table: table): base => {
  {...base, tables: Array.concat(base.tables, [table])}
}

let removeTableFromBase = (base: base, tableId: string): base => {
  {...base, tables: base.tables->Array.filter(t => t.id != tableId)}
}
