// SPDX-License-Identifier: PMPL-1.0-or-later
// KRaft Serializer — JSON persistence for Raft log and cluster state.
//
// Provides encode/decode functions for all Raft types so the log
// can be persisted to disk (or transmitted over the wire for RPC).

// ============================================================================
// Command Serialization
// ============================================================================

let commandToJson = (cmd: MetadataLog.command): Js.Json.t => {
  open Js.Json

  switch cmd {
  | RegisterStore({storeId, endpoint, modalities}) =>
    Js.Dict.fromArray([
      ("type", string("RegisterStore")),
      ("storeId", string(storeId)),
      ("endpoint", string(endpoint)),
      (
        "modalities",
        array(modalities->Belt.Array.map(m => string(m))),
      ),
    ])->object_

  | UnregisterStore({storeId}) =>
    Js.Dict.fromArray([
      ("type", string("UnregisterStore")),
      ("storeId", string(storeId)),
    ])->object_

  | MapHexad({hexadId, locations}) =>
    Js.Dict.fromArray([
      ("type", string("MapHexad")),
      ("hexadId", string(hexadId)),
      ("locations", locations->object_),
    ])->object_

  | UnmapHexad({hexadId}) =>
    Js.Dict.fromArray([
      ("type", string("UnmapHexad")),
      ("hexadId", string(hexadId)),
    ])->object_

  | UpdateTrust({storeId, newTrust}) =>
    Js.Dict.fromArray([
      ("type", string("UpdateTrust")),
      ("storeId", string(storeId)),
      ("newTrust", number(newTrust)),
    ])->object_

  | NoOp =>
    Js.Dict.fromArray([("type", string("NoOp"))])->object_
  }
}

let commandFromJson = (json: Js.Json.t): option<MetadataLog.command> => {
  open Belt.Option

  let dict = Js.Json.decodeObject(json)

  dict->flatMap(d => {
    let cmdType =
      Js.Dict.get(d, "type")
      ->flatMap(Js.Json.decodeString)

    switch cmdType {
    | Some("RegisterStore") => {
        let storeId = Js.Dict.get(d, "storeId")->flatMap(Js.Json.decodeString)
        let endpoint = Js.Dict.get(d, "endpoint")->flatMap(Js.Json.decodeString)
        let modalities =
          Js.Dict.get(d, "modalities")
          ->flatMap(Js.Json.decodeArray)
          ->map(arr => arr->Belt.Array.keepMap(Js.Json.decodeString))

        switch (storeId, endpoint, modalities) {
        | (Some(s), Some(e), Some(m)) =>
          Some(MetadataLog.RegisterStore({storeId: s, endpoint: e, modalities: m}))
        | _ => None
        }
      }

    | Some("UnregisterStore") => {
        let storeId = Js.Dict.get(d, "storeId")->flatMap(Js.Json.decodeString)
        storeId->map(s => MetadataLog.UnregisterStore({storeId: s}))
      }

    | Some("MapHexad") => {
        let hexadId = Js.Dict.get(d, "hexadId")->flatMap(Js.Json.decodeString)
        let locations =
          Js.Dict.get(d, "locations")
          ->flatMap(Js.Json.decodeObject)

        switch (hexadId, locations) {
        | (Some(h), Some(l)) =>
          Some(MetadataLog.MapHexad({hexadId: h, locations: l}))
        | _ => None
        }
      }

    | Some("UnmapHexad") => {
        let hexadId = Js.Dict.get(d, "hexadId")->flatMap(Js.Json.decodeString)
        hexadId->map(h => MetadataLog.UnmapHexad({hexadId: h}))
      }

    | Some("UpdateTrust") => {
        let storeId = Js.Dict.get(d, "storeId")->flatMap(Js.Json.decodeString)
        let newTrust = Js.Dict.get(d, "newTrust")->flatMap(Js.Json.decodeNumber)

        switch (storeId, newTrust) {
        | (Some(s), Some(t)) =>
          Some(MetadataLog.UpdateTrust({storeId: s, newTrust: t}))
        | _ => None
        }
      }

    | Some("NoOp") => Some(MetadataLog.NoOp)
    | _ => None
    }
  })
}

// ============================================================================
// Log Entry Serialization
// ============================================================================

let logEntryToJson = (entry: MetadataLog.logEntry): Js.Json.t => {
  Js.Dict.fromArray([
    ("term", Js.Json.number(Belt.Int.toFloat(entry.term))),
    ("index", Js.Json.number(Belt.Int.toFloat(entry.index))),
    ("command", commandToJson(entry.command)),
    ("timestamp", Js.Json.number(entry.timestamp)),
  ])->Js.Json.object_
}

let logEntryFromJson = (json: Js.Json.t): option<MetadataLog.logEntry> => {
  open Belt.Option

  Js.Json.decodeObject(json)->flatMap(d => {
    let term =
      Js.Dict.get(d, "term")
      ->flatMap(Js.Json.decodeNumber)
      ->map(Belt.Float.toInt)

    let index =
      Js.Dict.get(d, "index")
      ->flatMap(Js.Json.decodeNumber)
      ->map(Belt.Float.toInt)

    let command =
      Js.Dict.get(d, "command")
      ->flatMap(commandFromJson)

    let timestamp =
      Js.Dict.get(d, "timestamp")
      ->flatMap(Js.Json.decodeNumber)

    switch (term, index, command, timestamp) {
    | (Some(t), Some(i), Some(c), Some(ts)) =>
      Some({
        term: t,
        index: i,
        command: c,
        timestamp: ts,
      }: MetadataLog.logEntry)
    | _ => None
    }
  })
}

// ============================================================================
// Node State Serialization
// ============================================================================

let roleToString = (role: MetadataLog.nodeRole): string => {
  switch role {
  | Leader => "leader"
  | Follower => "follower"
  | Candidate => "candidate"
  }
}

let roleFromString = (s: string): option<MetadataLog.nodeRole> => {
  switch s {
  | "leader" => Some(MetadataLog.Leader)
  | "follower" => Some(MetadataLog.Follower)
  | "candidate" => Some(MetadataLog.Candidate)
  | _ => None
  }
}

let dictToJsonNumbers = (d: Js.Dict.t<MetadataLog.index>): Js.Json.t => {
  let entries = Js.Dict.entries(d)->Belt.Array.map(((k, v)) => {
    (k, Js.Json.number(Belt.Int.toFloat(v)))
  })
  Js.Dict.fromArray(entries)->Js.Json.object_
}

let jsonToDictNumbers = (json: Js.Json.t): Js.Dict.t<MetadataLog.index> => {
  switch Js.Json.decodeObject(json) {
  | None => Js.Dict.empty()
  | Some(d) => {
      let entries = Js.Dict.entries(d)->Belt.Array.keepMap(((k, v)) => {
        Js.Json.decodeNumber(v)->Belt.Option.map(n => (k, Belt.Float.toInt(n)))
      })
      Js.Dict.fromArray(entries)
    }
  }
}

let nodeStateToJson = (state: MetadataLog.nodeState): Js.Json.t => {
  Js.Dict.fromArray([
    ("role", Js.Json.string(roleToString(state.role))),
    ("currentTerm", Js.Json.number(Belt.Int.toFloat(state.currentTerm))),
    (
      "votedFor",
      switch state.votedFor {
      | Some(id) => Js.Json.string(id)
      | None => Js.Json.null
      },
    ),
    ("log", Js.Json.array(state.log->Belt.Array.map(logEntryToJson))),
    ("commitIndex", Js.Json.number(Belt.Int.toFloat(state.commitIndex))),
    ("lastApplied", Js.Json.number(Belt.Int.toFloat(state.lastApplied))),
    ("nextIndex", dictToJsonNumbers(state.nextIndex)),
    ("matchIndex", dictToJsonNumbers(state.matchIndex)),
  ])->Js.Json.object_
}

let nodeStateFromJson = (json: Js.Json.t): option<MetadataLog.nodeState> => {
  open Belt.Option

  Js.Json.decodeObject(json)->flatMap(d => {
    let role =
      Js.Dict.get(d, "role")
      ->flatMap(Js.Json.decodeString)
      ->flatMap(roleFromString)

    let currentTerm =
      Js.Dict.get(d, "currentTerm")
      ->flatMap(Js.Json.decodeNumber)
      ->map(Belt.Float.toInt)

    let votedFor =
      Js.Dict.get(d, "votedFor")
      ->flatMap(v =>
        if v == Js.Json.null {
          Some(None)
        } else {
          Js.Json.decodeString(v)->map(s => Some(s))
        }
      )

    let log =
      Js.Dict.get(d, "log")
      ->flatMap(Js.Json.decodeArray)
      ->map(arr => arr->Belt.Array.keepMap(logEntryFromJson))

    let commitIndex =
      Js.Dict.get(d, "commitIndex")
      ->flatMap(Js.Json.decodeNumber)
      ->map(Belt.Float.toInt)

    let lastApplied =
      Js.Dict.get(d, "lastApplied")
      ->flatMap(Js.Json.decodeNumber)
      ->map(Belt.Float.toInt)

    let nextIndex =
      Js.Dict.get(d, "nextIndex")
      ->map(jsonToDictNumbers)
      ->getWithDefault(Js.Dict.empty())

    let matchIndex =
      Js.Dict.get(d, "matchIndex")
      ->map(jsonToDictNumbers)
      ->getWithDefault(Js.Dict.empty())

    switch (role, currentTerm, votedFor, log, commitIndex, lastApplied) {
    | (Some(r), Some(ct), Some(vf), Some(l), Some(ci), Some(la)) =>
      Some({
        role: r,
        currentTerm: ct,
        votedFor: vf,
        log: l,
        commitIndex: ci,
        lastApplied: la,
        nextIndex: nextIndex,
        matchIndex: matchIndex,
      }: MetadataLog.nodeState)
    | _ => None
    }
  })
}

// ============================================================================
// Vote Request/Response Serialization
// ============================================================================

let voteRequestToJson = (req: MetadataLog.voteRequest): Js.Json.t => {
  Js.Dict.fromArray([
    ("term", Js.Json.number(Belt.Int.toFloat(req.term))),
    ("candidateId", Js.Json.string(req.candidateId)),
    ("lastLogIndex", Js.Json.number(Belt.Int.toFloat(req.lastLogIndex))),
    ("lastLogTerm", Js.Json.number(Belt.Int.toFloat(req.lastLogTerm))),
  ])->Js.Json.object_
}

let voteRequestFromJson = (json: Js.Json.t): option<MetadataLog.voteRequest> => {
  open Belt.Option

  Js.Json.decodeObject(json)->flatMap(d => {
    let term = Js.Dict.get(d, "term")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)
    let candidateId = Js.Dict.get(d, "candidateId")->flatMap(Js.Json.decodeString)
    let lastLogIndex = Js.Dict.get(d, "lastLogIndex")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)
    let lastLogTerm = Js.Dict.get(d, "lastLogTerm")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)

    switch (term, candidateId, lastLogIndex, lastLogTerm) {
    | (Some(t), Some(c), Some(li), Some(lt)) =>
      Some({term: t, candidateId: c, lastLogIndex: li, lastLogTerm: lt}: MetadataLog.voteRequest)
    | _ => None
    }
  })
}

let voteResponseToJson = (res: MetadataLog.voteResponse): Js.Json.t => {
  Js.Dict.fromArray([
    ("term", Js.Json.number(Belt.Int.toFloat(res.term))),
    ("voteGranted", Js.Json.boolean(res.voteGranted)),
  ])->Js.Json.object_
}

let voteResponseFromJson = (json: Js.Json.t): option<MetadataLog.voteResponse> => {
  open Belt.Option

  Js.Json.decodeObject(json)->flatMap(d => {
    let term = Js.Dict.get(d, "term")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)
    let voteGranted = Js.Dict.get(d, "voteGranted")->flatMap(Js.Json.decodeBoolean)

    switch (term, voteGranted) {
    | (Some(t), Some(v)) =>
      Some({term: t, voteGranted: v}: MetadataLog.voteResponse)
    | _ => None
    }
  })
}

// ============================================================================
// AppendEntries Request/Response Serialization
// ============================================================================

let appendEntriesRequestToJson = (req: MetadataLog.appendEntriesRequest): Js.Json.t => {
  Js.Dict.fromArray([
    ("term", Js.Json.number(Belt.Int.toFloat(req.term))),
    ("leaderId", Js.Json.string(req.leaderId)),
    ("prevLogIndex", Js.Json.number(Belt.Int.toFloat(req.prevLogIndex))),
    ("prevLogTerm", Js.Json.number(Belt.Int.toFloat(req.prevLogTerm))),
    ("entries", Js.Json.array(req.entries->Belt.Array.map(logEntryToJson))),
    ("leaderCommit", Js.Json.number(Belt.Int.toFloat(req.leaderCommit))),
  ])->Js.Json.object_
}

let appendEntriesRequestFromJson = (json: Js.Json.t): option<MetadataLog.appendEntriesRequest> => {
  open Belt.Option

  Js.Json.decodeObject(json)->flatMap(d => {
    let term = Js.Dict.get(d, "term")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)
    let leaderId = Js.Dict.get(d, "leaderId")->flatMap(Js.Json.decodeString)
    let prevLogIndex = Js.Dict.get(d, "prevLogIndex")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)
    let prevLogTerm = Js.Dict.get(d, "prevLogTerm")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)
    let entries =
      Js.Dict.get(d, "entries")
      ->flatMap(Js.Json.decodeArray)
      ->map(arr => arr->Belt.Array.keepMap(logEntryFromJson))
    let leaderCommit = Js.Dict.get(d, "leaderCommit")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)

    switch (term, leaderId, prevLogIndex, prevLogTerm, entries, leaderCommit) {
    | (Some(t), Some(l), Some(pi), Some(pt), Some(e), Some(lc)) =>
      Some({
        term: t,
        leaderId: l,
        prevLogIndex: pi,
        prevLogTerm: pt,
        entries: e,
        leaderCommit: lc,
      }: MetadataLog.appendEntriesRequest)
    | _ => None
    }
  })
}

let appendEntriesResponseToJson = (res: MetadataLog.appendEntriesResponse): Js.Json.t => {
  Js.Dict.fromArray([
    ("term", Js.Json.number(Belt.Int.toFloat(res.term))),
    ("success", Js.Json.boolean(res.success)),
    ("matchIndex", Js.Json.number(Belt.Int.toFloat(res.matchIndex))),
  ])->Js.Json.object_
}

let appendEntriesResponseFromJson = (json: Js.Json.t): option<MetadataLog.appendEntriesResponse> => {
  open Belt.Option

  Js.Json.decodeObject(json)->flatMap(d => {
    let term = Js.Dict.get(d, "term")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)
    let success = Js.Dict.get(d, "success")->flatMap(Js.Json.decodeBoolean)
    let matchIndex = Js.Dict.get(d, "matchIndex")->flatMap(Js.Json.decodeNumber)->map(Belt.Float.toInt)

    switch (term, success, matchIndex) {
    | (Some(t), Some(s), Some(mi)) =>
      Some({term: t, success: s, matchIndex: mi}: MetadataLog.appendEntriesResponse)
    | _ => None
    }
  })
}

// ============================================================================
// Full Snapshot Serialization (for persistence)
// ============================================================================

type persistedSnapshot = {
  version: int,
  nodeState: Js.Json.t,
  snapshotTimestamp: float,
}

let snapshotToJson = (state: MetadataLog.nodeState): Js.Json.t => {
  Js.Dict.fromArray([
    ("version", Js.Json.number(1.0)),
    ("nodeState", nodeStateToJson(state)),
    ("snapshotTimestamp", Js.Json.number(Js.Date.now())),
  ])->Js.Json.object_
}

let snapshotFromJson = (json: Js.Json.t): option<MetadataLog.nodeState> => {
  open Belt.Option

  Js.Json.decodeObject(json)->flatMap(d => {
    let version =
      Js.Dict.get(d, "version")
      ->flatMap(Js.Json.decodeNumber)
      ->map(Belt.Float.toInt)

    switch version {
    | Some(1) =>
      Js.Dict.get(d, "nodeState")->flatMap(nodeStateFromJson)
    | _ => None // Unknown version
    }
  })
}

// ============================================================================
// Write-Ahead Log (WAL) Entry Format
// ============================================================================

/// Encode a single log entry as a line for append-only WAL file.
let walEncode = (entry: MetadataLog.logEntry): string => {
  Js.Json.stringify(logEntryToJson(entry))
}

/// Decode a WAL line back to a log entry.
let walDecode = (line: string): option<MetadataLog.logEntry> => {
  try {
    let json = Js.Json.parseExn(line)
    logEntryFromJson(json)
  } catch {
  | _ => None
  }
}

/// Encode multiple WAL entries (newline-delimited JSON).
let walEncodeAll = (entries: array<MetadataLog.logEntry>): string => {
  entries
  ->Belt.Array.map(walEncode)
  ->Belt.Array.joinWith("\n", s => s)
}

/// Decode all entries from a WAL string.
let walDecodeAll = (data: string): array<MetadataLog.logEntry> => {
  Js.String2.split(data, "\n")
  ->Belt.Array.keepMap(line => {
    let trimmed = Js.String2.trim(line)
    if Js.String2.length(trimmed) > 0 {
      walDecode(trimmed)
    } else {
      None
    }
  })
}

// ============================================================================
// Public API
// ============================================================================

// Commands
let encodeCommand = commandToJson
let decodeCommand = commandFromJson

// Log entries
let encodeEntry = logEntryToJson
let decodeEntry = logEntryFromJson

// Node state
let encodeState = nodeStateToJson
let decodeState = nodeStateFromJson

// RPC messages
let encodeVoteReq = voteRequestToJson
let decodeVoteReq = voteRequestFromJson
let encodeVoteRes = voteResponseToJson
let decodeVoteRes = voteResponseFromJson
let encodeAppendReq = appendEntriesRequestToJson
let decodeAppendReq = appendEntriesRequestFromJson
let encodeAppendRes = appendEntriesResponseToJson
let decodeAppendRes = appendEntriesResponseFromJson

// Snapshots
let snapshot = snapshotToJson
let restore = snapshotFromJson

// WAL
let wal = walEncode
let unwal = walDecode
let walAll = walEncodeAll
let unwalAll = walDecodeAll
