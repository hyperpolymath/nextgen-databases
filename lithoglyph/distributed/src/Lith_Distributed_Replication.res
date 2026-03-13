// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Replication
 *
 * Data replication and synchronization across nodes
 */

/** Replication mode */
type replicationMode =
  | Synchronous    // Wait for all replicas
  | Asynchronous   // Fire and forget
  | SemiSync       // Wait for quorum

/** Consistency level */
type consistencyLevel =
  | One            // One node must respond
  | Quorum         // Majority must respond
  | All            // All nodes must respond
  | LocalQuorum    // Local datacenter quorum

/** Replication event type */
type replicationEventType =
  | Write
  | Update
  | Delete
  | Snapshot

/** Replication event */
type replicationEvent = {
  id: string,
  eventType: replicationEventType,
  collection: string,
  documentId: string,
  data: option<Js.Json.t>,
  timestamp: float,
  sourceNode: string,
  sequenceNumber: int,
}

/** Replication configuration */
type replicationConfig = {
  mode: replicationMode,
  readConsistency: consistencyLevel,
  writeConsistency: consistencyLevel,
  replicationFactor: int,
  syncIntervalMs: float,
  conflictResolution: string, // "last-write-wins", "vector-clock", "custom"
}

/** Default replication config */
let defaultConfig: replicationConfig = {
  mode: SemiSync,
  readConsistency: One,
  writeConsistency: Quorum,
  replicationFactor: 3,
  syncIntervalMs: 100.0,
  conflictResolution: "last-write-wins",
}

/** Replica status */
type replicaStatus = {
  nodeId: string,
  lastSequence: int,
  lag: int,
  isHealthy: bool,
  lastSync: float,
}

/** Replication manager */
type replicationManager = {
  config: replicationConfig,
  nodeId: string,
  mutable sequence: int,
  mutable pendingEvents: array<replicationEvent>,
  mutable replicaStatus: Js.Dict.t<replicaStatus>,
}

/** Create replication manager */
let make = (~config: replicationConfig=defaultConfig, ~nodeId: string): replicationManager => {
  {
    config,
    nodeId,
    sequence: 0,
    pendingEvents: [],
    replicaStatus: Js.Dict.empty(),
  }
}

/** Generate event ID */
let generateEventId = (): string => {
  let timestamp = Js.Date.now()->Float.toString
  let random = Js.Math.random()->Float.toString
  `evt-${timestamp}-${random}`
}

/** Create replication event */
let createEvent = (
  manager: replicationManager,
  eventType: replicationEventType,
  collection: string,
  documentId: string,
  data: option<Js.Json.t>,
): replicationEvent => {
  manager.sequence = manager.sequence + 1

  {
    id: generateEventId(),
    eventType,
    collection,
    documentId,
    data,
    timestamp: Js.Date.now(),
    sourceNode: manager.nodeId,
    sequenceNumber: manager.sequence,
  }
}

/** Queue event for replication */
let queueEvent = (manager: replicationManager, event: replicationEvent): unit => {
  manager.pendingEvents->Array.push(event)->ignore
}

/** Get pending events */
let getPendingEvents = (manager: replicationManager): array<replicationEvent> => {
  manager.pendingEvents
}

/** Clear acknowledged events */
let acknowledgeEvents = (manager: replicationManager, upToSequence: int): unit => {
  manager.pendingEvents = manager.pendingEvents->Array.filter(e =>
    e.sequenceNumber > upToSequence
  )
}

/** Update replica status */
let updateReplicaStatus = (
  manager: replicationManager,
  nodeId: string,
  lastSequence: int,
  isHealthy: bool,
): unit => {
  let lag = manager.sequence - lastSequence
  let status: replicaStatus = {
    nodeId,
    lastSequence,
    lag,
    isHealthy,
    lastSync: Js.Date.now(),
  }
  Js.Dict.set(manager.replicaStatus, nodeId, status)
}

/** Get replica status */
let getReplicaStatus = (manager: replicationManager, nodeId: string): option<replicaStatus> => {
  Js.Dict.get(manager.replicaStatus, nodeId)
}

/** Calculate required responses for consistency level */
let requiredResponses = (manager: replicationManager, level: consistencyLevel): int => {
  let rf = manager.config.replicationFactor
  switch level {
  | One => 1
  | Quorum => rf / 2 + 1
  | All => rf
  | LocalQuorum => rf / 2 + 1 // Simplified
  }
}

/** Check if write is successful */
let isWriteSuccessful = (manager: replicationManager, ackCount: int): bool => {
  let required = requiredResponses(manager, manager.config.writeConsistency)
  ackCount >= required
}

/** Check if read is successful */
let isReadSuccessful = (manager: replicationManager, responseCount: int): bool => {
  let required = requiredResponses(manager, manager.config.readConsistency)
  responseCount >= required
}

/** Get replication lag statistics */
type lagStats = {
  maxLag: int,
  avgLag: float,
  healthyReplicas: int,
  totalReplicas: int,
}

let getLagStats = (manager: replicationManager): lagStats => {
  let statuses = Js.Dict.values(manager.replicaStatus)
  let len = Array.length(statuses)

  if len == 0 {
    {maxLag: 0, avgLag: 0.0, healthyReplicas: 0, totalReplicas: 0}
  } else {
    let maxLag = statuses->Array.map(s => s.lag)->Array.reduce(0, (a, b) => max(a, b))
    let totalLag = statuses->Array.map(s => s.lag)->Array.reduce(0, (a, b) => a + b)
    let avgLag = Int.toFloat(totalLag) /. Int.toFloat(len)
    let healthy = statuses->Array.filter(s => s.isHealthy)->Array.length

    {
      maxLag,
      avgLag,
      healthyReplicas: healthy,
      totalReplicas: len,
    }
  }
}

/** Event to JSON */
let eventToJson = (event: replicationEvent): Js.Json.t => {
  let typeToString = t =>
    switch t {
    | Write => "write"
    | Update => "update"
    | Delete => "delete"
    | Snapshot => "snapshot"
    }

  let obj = Js.Dict.empty()
  Js.Dict.set(obj, "id", Js.Json.string(event.id))
  Js.Dict.set(obj, "type", Js.Json.string(typeToString(event.eventType)))
  Js.Dict.set(obj, "collection", Js.Json.string(event.collection))
  Js.Dict.set(obj, "documentId", Js.Json.string(event.documentId))
  switch event.data {
  | Some(d) => Js.Dict.set(obj, "data", d)
  | None => ()
  }
  Js.Dict.set(obj, "timestamp", Js.Json.number(event.timestamp))
  Js.Dict.set(obj, "sourceNode", Js.Json.string(event.sourceNode))
  Js.Dict.set(obj, "sequenceNumber", Js.Json.number(Int.toFloat(event.sequenceNumber)))
  Js.Json.object_(obj)
}
