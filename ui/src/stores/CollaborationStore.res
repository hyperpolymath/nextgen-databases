// SPDX-License-Identifier: PMPL-1.0-or-later
// Real-time collaboration store using Yjs CRDTs

open Types

// Collaboration state types
type rec collaborationState = {
  isConnected: bool,
  isSynced: bool,
  users: array<collaborativeUser>,
}

and collaborativeUser = {
  clientId: string,
  name: string,
  color: string,
  cursor: option<cursorPosition>,
}

and cursorPosition = {
  rowId: string,
  fieldId: string,
}

// Atoms for collaboration state
let collaborationStateAtom: Jotai.atom<collaborationState> = Jotai.atom({
  isConnected: false,
  isSynced: false,
  users: [],
})

// Yjs document and provider (mutable refs)
let yjsDoc: ref<option<Yjs.doc>> = ref(None)
let yjsProvider: ref<option<Yjs.websocketProvider>> = ref(None)

// Initialize Yjs collaboration
let initCollaboration = (
  tableId: string,
  userId: string,
  userName: string,
  ~wsUrl: string="ws://localhost:1234",
  ~onConnected: unit => unit,
  ~onSynced: unit => unit,
  ~onDisconnected: unit => unit,
): unit => {
  // Create Yjs document
  let doc = Yjs.createDoc()
  yjsDoc := Some(doc)

  // Create WebSocket provider
  let provider = Yjs.createWebSocketProvider(wsUrl, `glyphbase-${tableId}`, doc)
  yjsProvider := Some(provider)

  // Set up awareness (for cursors/presence)
  let awareness = Yjs.providerAwareness(provider)
  let randomColor = Int.toFloat(Js.Math.random_int(0, 16777215))
  Yjs.setLocalState(
    awareness,
    {
      "user": {
        "id": userId,
        "name": userName,
        "color": `#${Float.toString(randomColor)}`,
      },
      "cursor": None,
    },
  )

  // Connection events
  Yjs.providerOn(provider, "status", () => {
    Console.log("WebSocket status changed")
  })

  Yjs.providerOn(provider, "sync", () => {
    Console.log("Document synced")
    onSynced()
  })

  onConnected()
}

// Update cell collaboratively
let updateCellCollab = (rowId: string, fieldId: string, value: cellValue): unit => {
  switch yjsDoc.contents {
  | Some(doc) => {
      // Get the shared map for this table
      let cellsMap: Yjs.map<'a> = Yjs.getMap(doc, "cells")

      // Create a key for this cell
      let cellKey = `${rowId}:${fieldId}`

      // Convert cellValue to JS object (use %raw for polymorphic value)
      let jsValue = %raw(`(function(value) {
        switch (value.TAG) {
          case 0: return {type: "text", value: value._0};
          case 1: return {type: "number", value: value._0};
          case 2: return {type: "select", value: value._0};
          case 3: return {type: "multiselect", value: value._0};
          case 4: return {type: "date", value: new Date(value._0).toISOString()};
          case 5: return {type: "checkbox", value: value._0};
          default: return {type: "null", value: null};
        }
      })(value)`)

      // Update in Yjs map (will sync to all clients)
      Yjs.mapSet(cellsMap, cellKey, jsValue)
    }
  | None => Console.error("Yjs doc not initialized")
  }
}

// Observe cell changes from other users
let observeCellChanges = (onCellChange: (string, string, cellValue) => unit): unit => {
  switch yjsDoc.contents {
  | Some(doc) => {
      let cellsMap: Yjs.map<'a> = Yjs.getMap(doc, "cells")

      Yjs.observe(cellsMap, (_event, _transaction) => {
        // When remote changes occur, update local state
        Yjs.mapForEach(cellsMap, (jsValue, cellKey) => {
          // Parse cell key (rowId:fieldId)
          let parts = cellKey->String.split(":")
          switch (parts->Array.get(0), parts->Array.get(1)) {
          | (Some(rowId), Some(fieldId)) => {
              // Convert JS value back to cellValue (basic implementation)
              let value = NullValue // Placeholder - would need proper conversion

              onCellChange(rowId, fieldId, value)
            }
          | _ => ()
          }
        })
      })
    }
  | None => Console.error("Yjs doc not initialized")
  }
}

// Update cursor position for awareness
let updateCursor = (rowId: string, fieldId: string): unit => {
  switch yjsProvider.contents {
  | Some(provider) => {
      let awareness = Yjs.providerAwareness(provider)
      let currentState = Yjs.getLocalState(awareness)

      switch currentState {
      | Some(state) => {
          // Update cursor in awareness state (merge with existing state)
          let updatedState = %raw(`{
            ...state,
            cursor: { rowId: rowId, fieldId: fieldId }
          }`)
          Yjs.setLocalState(awareness, updatedState)
        }
      | None => ()
      }
    }
  | None => ()
  }
}

// Get all active users
let getActiveUsers = (): array<collaborativeUser> => {
  switch yjsProvider.contents {
  | Some(provider) => {
      let awareness = Yjs.providerAwareness(provider)
      let states = Yjs.getStates(awareness)

      states
      ->Dict.toArray
      ->Array.map(((clientId, _state)) => {
        {
          clientId,
          name: "User",
          color: "#000000",
          cursor: None,
        }
      })
    }
  | None => []
  }
}

// Disconnect collaboration
let disconnectCollaboration = (): unit => {
  switch yjsProvider.contents {
  | Some(provider) => {
      Yjs.providerDisconnect(provider)
      Yjs.providerDestroy(provider)
      yjsProvider := None
    }
  | None => ()
  }

  yjsDoc := None
}
