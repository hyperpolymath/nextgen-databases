// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Sharding
 *
 * Consistent hashing and shard management for distributed data
 */

/** Shard status */
type shardStatus =
  | Initializing
  | Active
  | Migrating
  | Inactive

/** Shard info */
type shardInfo = {
  id: int,
  status: shardStatus,
  primaryNode: string,
  replicaNodes: array<string>,
  keyRangeStart: int,
  keyRangeEnd: int,
  documentCount: int,
}

/** Sharding strategy */
type shardingStrategy =
  | Hash
  | Range
  | Directory

/** Sharding configuration */
type shardingConfig = {
  strategy: shardingStrategy,
  numShards: int,
  replicationFactor: int,
  virtualNodes: int, // For consistent hashing
}

/** Default sharding config */
let defaultConfig: shardingConfig = {
  strategy: Hash,
  numShards: 16,
  replicationFactor: 3,
  virtualNodes: 150,
}

/** Hash ring node */
type hashRingNode = {
  hash: int,
  nodeId: string,
  shardId: int,
}

/** Shard manager */
type shardManager = {
  config: shardingConfig,
  mutable shards: array<shardInfo>,
  mutable hashRing: array<hashRingNode>,
  mutable nodeToShards: Js.Dict.t<array<int>>,
}

/** Simple hash function (FNV-1a inspired) */
let hashKey = (key: string): int => {
  let hash = ref(2166136261)
  for i in 0 to String.length(key) - 1 {
    let charCode = String.charCodeAt(key, i)->Option.getOr(0.0)->Float.toInt
    hash := Int.lxor(hash.contents, charCode)
    // Multiply by FNV prime (simplified)
    hash := hash.contents * 16777619
  }
  Int.abs(hash.contents)
}

/** Create shard manager */
let make = (~config: shardingConfig=defaultConfig): shardManager => {
  {
    config,
    shards: [],
    hashRing: [],
    nodeToShards: Js.Dict.empty(),
  }
}

/** Initialize shards */
let initializeShards = (manager: shardManager, nodes: array<string>): unit => {
  let numNodes = Array.length(nodes)
  if numNodes == 0 {
    ()
  } else {
    // Create shards
    let shardsPerRange = 2147483647 / manager.config.numShards

    for i in 0 to manager.config.numShards - 1 {
      let primaryIdx = mod(i, numNodes)
      let primaryNode = nodes->Array.getUnsafe(primaryIdx)

      // Assign replica nodes
      let replicaNodes: array<string> = []
      for j in 1 to min(manager.config.replicationFactor - 1, numNodes - 1) {
        let replicaIdx = mod(primaryIdx + j, numNodes)
        replicaNodes->Array.push(nodes->Array.getUnsafe(replicaIdx))->ignore
      }

      let shard: shardInfo = {
        id: i,
        status: Active,
        primaryNode,
        replicaNodes,
        keyRangeStart: i * shardsPerRange,
        keyRangeEnd: (i + 1) * shardsPerRange - 1,
        documentCount: 0,
      }
      manager.shards->Array.push(shard)->ignore
    }

    // Build hash ring with virtual nodes
    nodes->Array.forEachWithIndex((node, nodeIdx) => {
      for v in 0 to manager.config.virtualNodes - 1 {
        let virtualKey = `${node}:${Int.toString(v)}`
        let hash = hashKey(virtualKey)
        let shardId = mod(nodeIdx, manager.config.numShards)

        manager.hashRing->Array.push({hash, nodeId: node, shardId})->ignore
      }
    })

    // Sort hash ring
    manager.hashRing->Array.sort((a, b) => a.hash - b.hash)

    // Build node to shards mapping
    manager.shards->Array.forEach(shard => {
      // Primary
      switch Js.Dict.get(manager.nodeToShards, shard.primaryNode) {
      | Some(shards) => shards->Array.push(shard.id)->ignore
      | None => Js.Dict.set(manager.nodeToShards, shard.primaryNode, [shard.id])
      }

      // Replicas
      shard.replicaNodes->Array.forEach(node => {
        switch Js.Dict.get(manager.nodeToShards, node) {
        | Some(shards) => shards->Array.push(shard.id)->ignore
        | None => Js.Dict.set(manager.nodeToShards, node, [shard.id])
        }
      })
    })
  }
}

/** Get shard for key (hash strategy) */
let getShardForKey = (manager: shardManager, key: string): option<shardInfo> => {
  switch manager.config.strategy {
  | Hash => {
      let hash = hashKey(key)
      let shardId = mod(hash, manager.config.numShards)
      manager.shards->Array.get(shardId)
    }
  | Range => {
      // Range-based: use first character
      let firstChar = String.charCodeAt(key, 0)->Option.getOr(0.0)->Float.toInt
      let shardId = mod(firstChar, manager.config.numShards)
      manager.shards->Array.get(shardId)
    }
  | Directory => {
      // Directory-based: would look up in directory
      // For now, fall back to hash
      let hash = hashKey(key)
      let shardId = mod(hash, manager.config.numShards)
      manager.shards->Array.get(shardId)
    }
  }
}

/** Get node for key using consistent hashing */
let getNodeForKey = (manager: shardManager, key: string): option<string> => {
  let ringLen = Array.length(manager.hashRing)
  if ringLen == 0 {
    None
  } else {
    let hash = hashKey(key)

    // Binary search for first node with hash >= key hash
    let rec binarySearch = (low: int, high: int): int => {
      if low >= high {
        low
      } else {
        let mid = (low + high) / 2
        switch manager.hashRing->Array.get(mid) {
        | Some(node) =>
          if node.hash < hash {
            binarySearch(mid + 1, high)
          } else {
            binarySearch(low, mid)
          }
        | None => low
        }
      }
    }

    let idx = binarySearch(0, ringLen)
    let finalIdx = if idx >= ringLen {
      0
    } else {
      idx
    }

    manager.hashRing->Array.get(finalIdx)->Option.map(n => n.nodeId)
  }
}

/** Get shards for node */
let getShardsForNode = (manager: shardManager, nodeId: string): array<int> => {
  Js.Dict.get(manager.nodeToShards, nodeId)->Option.getOr([])
}

/** Get shard statistics */
type shardStats = {
  totalShards: int,
  activeShards: int,
  migratingShards: int,
  totalDocuments: int,
}

let getStats = (manager: shardManager): shardStats => {
  let active = manager.shards->Array.filter(s => s.status == Active)->Array.length
  let migrating = manager.shards->Array.filter(s => s.status == Migrating)->Array.length
  let docs = manager.shards->Array.map(s => s.documentCount)->Array.reduce(0, (a, b) => a + b)

  {
    totalShards: Array.length(manager.shards),
    activeShards: active,
    migratingShards: migrating,
    totalDocuments: docs,
  }
}
