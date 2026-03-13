// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Cluster Coordination
 *
 * Node discovery, membership, and cluster state management
 */

/** Node status */
type nodeStatus =
  | Starting
  | Joining
  | Active
  | Leaving
  | Down

/** Node role */
type nodeRole =
  | Leader
  | Follower
  | Candidate

/** Node information */
type nodeInfo = {
  id: string,
  address: string,
  port: int,
  status: nodeStatus,
  role: nodeRole,
  lastHeartbeat: float,
  metadata: Js.Dict.t<string>,
}

/** Cluster state */
type clusterState = {
  clusterId: string,
  mutable nodes: array<nodeInfo>,
  mutable leader: option<string>,
  mutable term: int,
  mutable version: int,
}

/** Cluster configuration */
type clusterConfig = {
  clusterId: string,
  nodeId: string,
  bindAddress: string,
  bindPort: int,
  seedNodes: array<string>,
  heartbeatIntervalMs: float,
  electionTimeoutMs: float,
}

/** Default cluster config */
let defaultConfig: clusterConfig = {
  clusterId: "lith-cluster",
  nodeId: "",
  bindAddress: "0.0.0.0",
  bindPort: 7946,
  seedNodes: [],
  heartbeatIntervalMs: 1000.0,
  electionTimeoutMs: 5000.0,
}

/** Create cluster state */
let makeState = (~clusterId: string): clusterState => {
  {
    clusterId,
    nodes: [],
    leader: None,
    term: 0,
    version: 0,
  }
}

/** Add node to cluster */
let addNode = (state: clusterState, node: nodeInfo): unit => {
  // Check if node already exists
  let exists = state.nodes->Array.some(n => n.id == node.id)
  if !exists {
    state.nodes->Array.push(node)->ignore
    state.version = state.version + 1
  }
}

/** Remove node from cluster */
let removeNode = (state: clusterState, nodeId: string): unit => {
  state.nodes = state.nodes->Array.filter(n => n.id != nodeId)
  state.version = state.version + 1

  // Clear leader if it was the removed node
  switch state.leader {
  | Some(id) if id == nodeId => state.leader = None
  | _ => ()
  }
}

/** Update node status */
let updateNodeStatus = (state: clusterState, nodeId: string, status: nodeStatus): unit => {
  state.nodes->Array.forEach(node => {
    if node.id == nodeId {
      // Would need mutable node for real implementation
      ()
    }
  })
  state.version = state.version + 1
}

/** Get active nodes */
let getActiveNodes = (state: clusterState): array<nodeInfo> => {
  state.nodes->Array.filter(n => n.status == Active)
}

/** Get node by ID */
let getNode = (state: clusterState, nodeId: string): option<nodeInfo> => {
  state.nodes->Array.find(n => n.id == nodeId)
}

/** Check if node is leader */
let isLeader = (state: clusterState, nodeId: string): bool => {
  switch state.leader {
  | Some(id) => id == nodeId
  | None => false
  }
}

/** Set leader */
let setLeader = (state: clusterState, nodeId: string, term: int): unit => {
  state.leader = Some(nodeId)
  state.term = term
  state.version = state.version + 1
}

/** Generate node ID */
let generateNodeId = (): string => {
  let timestamp = Js.Date.now()->Float.toString
  let random = Js.Math.random()->Float.toString
  `node-${timestamp}-${random}`
}

/** Node info to JSON */
let nodeInfoToJson = (node: nodeInfo): Js.Json.t => {
  let statusToString = s =>
    switch s {
    | Starting => "starting"
    | Joining => "joining"
    | Active => "active"
    | Leaving => "leaving"
    | Down => "down"
    }

  let roleToString = r =>
    switch r {
    | Leader => "leader"
    | Follower => "follower"
    | Candidate => "candidate"
    }

  let obj = Js.Dict.empty()
  Js.Dict.set(obj, "id", Js.Json.string(node.id))
  Js.Dict.set(obj, "address", Js.Json.string(node.address))
  Js.Dict.set(obj, "port", Js.Json.number(Int.toFloat(node.port)))
  Js.Dict.set(obj, "status", Js.Json.string(statusToString(node.status)))
  Js.Dict.set(obj, "role", Js.Json.string(roleToString(node.role)))
  Js.Dict.set(obj, "lastHeartbeat", Js.Json.number(node.lastHeartbeat))
  Js.Json.object_(obj)
}

/** Cluster state to JSON */
let stateToJson = (state: clusterState): Js.Json.t => {
  let obj = Js.Dict.empty()
  Js.Dict.set(obj, "clusterId", Js.Json.string(state.clusterId))
  Js.Dict.set(obj, "nodes", Js.Json.array(state.nodes->Array.map(nodeInfoToJson)))
  switch state.leader {
  | Some(id) => Js.Dict.set(obj, "leader", Js.Json.string(id))
  | None => ()
  }
  Js.Dict.set(obj, "term", Js.Json.number(Int.toFloat(state.term)))
  Js.Dict.set(obj, "version", Js.Json.number(Int.toFloat(state.version)))
  Js.Json.object_(obj)
}
