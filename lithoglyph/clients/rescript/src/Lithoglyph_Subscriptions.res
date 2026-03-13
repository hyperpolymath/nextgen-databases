// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>
//
// Lithoglyph ReScript Client - WebSocket Subscriptions
// Real-time journal streaming and migration progress via graphql-ws protocol
//
// Compatible with Deno runtime (not Node/npm)

open Lithoglyph_Types

// =============================================================================
// WebSocket FFI
// =============================================================================

/** Deno/browser WebSocket binding */
type webSocket

@new external createWebSocket: (string, ~protocols: array<string>=?) => webSocket = "WebSocket"

@set external onOpen: (webSocket, unit => unit) => unit = "onopen"
@set external onClose: (webSocket, 'event => unit) => unit = "onclose"
@set external onError: (webSocket, 'event => unit) => unit = "onerror"
@set external onMessage: (webSocket, 'event => unit) => unit = "onmessage"
@send external wsSend: (webSocket, string) => unit = "send"
@send external wsClose: (webSocket, ~code: int=?, ~reason: string=?) => unit = "close"

// =============================================================================
// graphql-ws Protocol Messages
// =============================================================================

/** Create a connection_init message for the graphql-ws protocol */
let connectionInitMsg = () => JSON.stringify(JSON.Encode.object([
  ("type", JSON.Encode.string("connection_init")),
]))

/** Create a subscribe message for the graphql-ws protocol */
let subscribeMsg = (~id, ~query, ~variables=?) => {
  JSON.stringify(JSON.Encode.object([
    ("id", JSON.Encode.string(id)),
    ("type", JSON.Encode.string("subscribe")),
    ("payload", JSON.Encode.object([
      ("query", JSON.Encode.string(query)),
      ...switch variables {
      | Some(v) => [("variables", v)]
      | None => []
      },
    ])),
  ]))
}

/** Create a complete (unsubscribe) message */
let completeMsg = (~id) => {
  JSON.stringify(JSON.Encode.object([
    ("id", JSON.Encode.string(id)),
    ("type", JSON.Encode.string("complete")),
  ]))
}

// =============================================================================
// Subscription Client
// =============================================================================

/** Subscription handle returned by subscribe operations */
type subscriptionHandle = {
  id: string,
  unsubscribe: unit => unit,
}

/** Convert an HTTP base URL to the corresponding WebSocket URL for GraphQL */
let wsUrlFromHttp = baseUrl => {
  let wsUrl = if baseUrl->String.startsWith("https://") {
    "wss://" ++ baseUrl->String.sliceToEnd(~start=8)
  } else if baseUrl->String.startsWith("http://") {
    "ws://" ++ baseUrl->String.sliceToEnd(~start=7)
  } else {
    baseUrl
  }
  `${wsUrl}/graphql`
}

/** Subscribe to journal entries in real time.
 *  Returns a subscription handle; call handle.unsubscribe() to stop.
 *  The onEntry callback fires for each new journal entry received. */
let subscribeJournal = (
  ~baseUrl,
  ~auth=?,
  ~collection=?,
  ~since=?,
  ~onEntry,
  ~onError=?,
  ~onComplete=?,
) => {
  ignore(auth)
  let wsUrl = wsUrlFromHttp(baseUrl)
  let ws = createWebSocket(wsUrl, ~protocols=["graphql-ws"])
  let subId = "journal-stream-1"

  onOpen(ws, () => {
    wsSend(ws, connectionInitMsg())

    let variables = JSON.Encode.object([
      ...switch collection {
      | Some(c) => [("collection", JSON.Encode.string(c))]
      | None => []
      },
      ...switch since {
      | Some(s) => [("since", JSON.Encode.int(s))]
      | None => []
      },
    ])

    let query = `
      subscription JournalStream($collection: String, $since: BigInt) {
        journalStream(collection: $collection, since: $since) {
          seq
          timestamp
          operation
          collection
          documentId
        }
      }
    `
    wsSend(ws, subscribeMsg(~id=subId, ~query, ~variables))
  })

  onMessage(ws, event => {
    let data: string = %raw(`event.data`)
    let parsed = data->JSON.parseExn->JSON.Decode.object
    switch parsed {
    | Some(msg) => {
        let msgType = msg->Dict.get("type")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
        switch msgType {
        | "next" => {
            let payload =
              msg
              ->Dict.get("payload")
              ->Option.flatMap(JSON.Decode.object)
              ->Option.flatMap(p => p->Dict.get("data"))
              ->Option.flatMap(JSON.Decode.object)
              ->Option.flatMap(d => d->Dict.get("journalStream"))
              ->Option.flatMap(JSON.Decode.object)
            switch payload {
            | Some(entry) =>
              onEntry({
                seq: entry
                  ->Dict.get("seq")
                  ->Option.flatMap(JSON.Decode.float)
                  ->Option.map(Float.toInt)
                  ->Option.getOr(0),
                timestamp: entry
                  ->Dict.get("timestamp")
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr(""),
                operation: switch entry
                  ->Dict.get("operation")
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr("INSERT") {
                | "UPDATE" => Update
                | "DELETE" => Delete
                | _ => Insert
                },
                collection: entry->Dict.get("collection")->Option.flatMap(JSON.Decode.string),
                documentId: entry->Dict.get("documentId")->Option.flatMap(JSON.Decode.string),
              })
            | None => ()
            }
          }
        | "error" => {
            let errMsg =
              msg
              ->Dict.get("payload")
              ->Option.map(JSON.stringify)
              ->Option.getOr("Subscription error")
            switch onError {
            | Some(handler) => handler(errMsg)
            | None => ()
            }
          }
        | "complete" =>
          switch onComplete {
          | Some(handler) => handler()
          | None => ()
          }
        | _ => ()
        }
      }
    | None => ()
    }
  })

  onError(ws, _event => {
    switch onError {
    | Some(handler) => handler("WebSocket connection error")
    | None => ()
    }
  })

  {
    id: subId,
    unsubscribe: () => {
      wsSend(ws, completeMsg(~id=subId))
      wsClose(ws)
    },
  }
}

/** Subscribe to migration progress updates in real time.
 *  Returns a subscription handle; call handle.unsubscribe() to stop. */
let subscribeMigrationProgress = (
  ~baseUrl,
  ~auth=?,
  ~migrationId,
  ~onProgress,
  ~onError=?,
  ~onComplete=?,
) => {
  ignore(auth)
  let wsUrl = wsUrlFromHttp(baseUrl)
  let ws = createWebSocket(wsUrl, ~protocols=["graphql-ws"])
  let subId = `migration-progress-${migrationId}`

  onOpen(ws, () => {
    wsSend(ws, connectionInitMsg())

    let variables = JSON.Encode.object([
      ("migrationId", JSON.Encode.string(migrationId)),
    ])

    let query = `
      subscription MigrationProgress($migrationId: ID!) {
        migrationProgress(migrationId: $migrationId) {
          migrationId
          phase
          progress
          message
        }
      }
    `
    wsSend(ws, subscribeMsg(~id=subId, ~query, ~variables))
  })

  onMessage(ws, event => {
    let data: string = %raw(`event.data`)
    let parsed = data->JSON.parseExn->JSON.Decode.object
    switch parsed {
    | Some(msg) => {
        let msgType = msg->Dict.get("type")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
        switch msgType {
        | "next" => {
            let payload =
              msg
              ->Dict.get("payload")
              ->Option.flatMap(JSON.Decode.object)
              ->Option.flatMap(p => p->Dict.get("data"))
              ->Option.flatMap(JSON.Decode.object)
              ->Option.flatMap(d => d->Dict.get("migrationProgress"))
              ->Option.flatMap(JSON.Decode.object)
            switch payload {
            | Some(progress) =>
              onProgress({
                migrationId: progress
                  ->Dict.get("migrationId")
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr(""),
                phase: switch progress
                  ->Dict.get("phase")
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr("ANNOUNCE") {
                | "SHADOW" => Shadow
                | "COMMIT" => Commit
                | "COMPLETE" => Complete
                | "ABORTED" => Aborted
                | _ => Announce
                },
                progress: progress
                  ->Dict.get("progress")
                  ->Option.flatMap(JSON.Decode.float)
                  ->Option.getOr(0.0),
                message: progress
                  ->Dict.get("message")
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr(""),
              })
            | None => ()
            }
          }
        | "error" => {
            let errMsg =
              msg
              ->Dict.get("payload")
              ->Option.map(JSON.stringify)
              ->Option.getOr("Subscription error")
            switch onError {
            | Some(handler) => handler(errMsg)
            | None => ()
            }
          }
        | "complete" =>
          switch onComplete {
          | Some(handler) => handler()
          | None => ()
          }
        | _ => ()
        }
      }
    | None => ()
    }
  })

  onError(ws, _event => {
    switch onError {
    | Some(handler) => handler("WebSocket connection error")
    | None => ()
    }
  })

  {
    id: subId,
    unsubscribe: () => {
      wsSend(ws, completeMsg(~id=subId))
      wsClose(ws)
    },
  }
}
