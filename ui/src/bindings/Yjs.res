// SPDX-License-Identifier: PMPL-1.0-or-later
// ReScript bindings for Yjs - CRDT library for real-time collaboration

// Y.Doc - The main Yjs document
type doc

@module("yjs") @new
external createDoc: unit => doc = "Doc"

// Y.Map - Collaborative map structure
type map<'a>

@send
external getMap: (doc, string) => map<'a> = "getMap"

@send
external mapSet: (map<'a>, string, 'a) => unit = "set"

@send
external mapGet: (map<'a>, string) => option<'a> = "get"

@send
external mapDelete: (map<'a>, string) => unit = "delete"

@send
external mapHas: (map<'a>, string) => bool = "has"

@send
external mapSize: map<'a> => int = "size"

@send
external mapClear: map<'a> => unit = "clear"

@send
external mapForEach: (map<'a>, ('a, string) => unit) => unit = "forEach"

// Y.Array - Collaborative array structure
type array<'a>

@send
external getArray: (doc, string) => array<'a> = "getArray"

@send
external arrayPush: (array<'a>, array<'a>) => unit = "push"

@send
external arrayDelete: (array<'a>, int, int) => unit = "delete"

@send
external arrayGet: (array<'a>, int) => option<'a> = "get"

@send
external arrayLength: array<'a> => int = "length"

@send
external arrayToArray: array<'a> => array<'a> = "toArray"

// Y.Text - Collaborative text structure
type text

@send
external getText: (doc, string) => text = "getText"

@send
external textInsert: (text, int, string) => unit = "insert"

@send
external textDelete: (text, int, int) => unit = "delete"

@send
external textToString: text => string = "toString"

@send
external textLength: text => int = "length"

// Transactions
type transaction

@send
external transact: (doc, transaction => unit) => unit = "transact"

// Event system
type event<'a>

type observeCallback<'a> = (event<'a>, transaction) => unit

@send
external observe: (map<'a>, observeCallback<'a>) => unit = "observe"

@send
external observeDeep: (doc, (array<event<'a>>, transaction) => unit) => unit = "observeDeep"

@send
external unobserve: (map<'a>, observeCallback<'a>) => unit = "unobserve"

// Awareness protocol (inline implementation for y-websocket compatibility)
type awareness

@module("yjs") @new
external createAwarenessFromDoc: doc => awareness = "Awareness"

@send
external setLocalState: (awareness, 'a) => unit = "setLocalState"

@send
external getLocalState: awareness => option<'a> = "getLocalState"

@send
external getStates: awareness => dict<'a> = "getStates"

@send
external onAwarenessChange: (awareness, {..} => unit) => unit = "on"

// WebSocket Provider (simplified inline version)
type websocketProvider = {
  doc: doc,
  url: string,
  roomname: string,
  awareness: awareness,
  mutable synced: bool,
  mutable connected: bool,
}

// Create provider (note: actual WebSocket connection would need y-websocket package)
let createWebSocketProvider = (url: string, roomname: string, doc: doc): websocketProvider => {
  {
    doc,
    url,
    roomname,
    awareness: createAwarenessFromDoc(doc),
    synced: false,
    connected: false,
  }
}

let providerConnect = (_provider: websocketProvider): unit => {
  Console.log("WebSocket provider connect (stub)")
}

let providerDisconnect = (_provider: websocketProvider): unit => {
  Console.log("WebSocket provider disconnect (stub)")
}

let providerDestroy = (_provider: websocketProvider): unit => {
  Console.log("WebSocket provider destroy (stub)")
}

let providerOn = (_provider: websocketProvider, _event: string, _callback: unit => unit): unit => {
  Console.log("WebSocket provider on (stub)")
}

let providerAwareness = (provider: websocketProvider): awareness => provider.awareness

let providerSynced = (provider: websocketProvider): bool => provider.synced
