// SPDX-License-Identifier: PMPL-1.0-or-later
// ReScript Federation Registry
// The "tiny core" (<5k LOC) for universal federated knowledge

// ============================================================================
// Types
// ============================================================================

type hexadId = string

type storeId = string

type modalityType =
  | Graph
  | Vector
  | Tensor
  | Semantic
  | Document
  | Temporal
  | Provenance
  | Spatial

type storeLocation = {
  storeId: storeId,
  endpoint: string,
  modalities: array<modalityType>,
  trustLevel: float, // 0.0-1.0
  lastSeen: Js.Date.t,
  responseTimeMs: option<int>,
}

type hexadMapping = {
  hexadId: hexadId,
  locations: Js.Dict.t<storeLocation>, // modalityType -> storeLocation
  primaryStore: option<storeId>,
  created: Js.Date.t,
  modified: Js.Date.t,
}

type registryState = {
  mappings: Js.Dict.t<hexadMapping>, // hexadId -> hexadMapping
  stores: Js.Dict.t<storeLocation>, // storeId -> storeLocation
  config: registryConfig,
}

and registryConfig = {
  minTrustLevel: float,
  maxStoreDowntimeMs: int,
  replicationFactor: int,
  consistencyMode: consistencyMode,
}

and consistencyMode =
  | Strong // All replicas must agree
  | Eventual // Accept temporary inconsistency
  | Quorum // Majority must agree

// ============================================================================
// Registry Operations
// ============================================================================

let createRegistry = (~config: registryConfig): registryState => {
  {
    mappings: Js.Dict.empty(),
    stores: Js.Dict.empty(),
    config: config,
  }
}

let defaultConfig = (): registryConfig => {
  {
    minTrustLevel: 0.5,
    maxStoreDowntimeMs: 300_000, // 5 minutes
    replicationFactor: 3,
    consistencyMode: Quorum,
  }
}

// Register a new store
let registerStore = (
  registry: registryState,
  storeId: storeId,
  endpoint: string,
  modalities: array<modalityType>,
): registryState => {
  let location: storeLocation = {
    storeId: storeId,
    endpoint: endpoint,
    modalities: modalities,
    trustLevel: 1.0,
    lastSeen: Js.Date.make(),
    responseTimeMs: None,
  }

  let newStores = Js.Dict.fromArray(Js.Dict.entries(registry.stores))
  Js.Dict.set(newStores, storeId, location)

  {...registry, stores: newStores}
}

// Map a hexad to store locations
let mapHexad = (
  registry: registryState,
  hexadId: hexadId,
  locations: Js.Dict.t<storeLocation>,
): registryState => {
  let mapping: hexadMapping = {
    hexadId: hexadId,
    locations: locations,
    primaryStore: None,
    created: Js.Date.make(),
    modified: Js.Date.make(),
  }

  let newMappings = Js.Dict.fromArray(Js.Dict.entries(registry.mappings))
  Js.Dict.set(newMappings, hexadId, mapping)

  {...registry, mappings: newMappings}
}

// Get store locations for a hexad
let getHexadLocations = (
  registry: registryState,
  hexadId: hexadId,
): option<hexadMapping> => {
  Js.Dict.get(registry.mappings, hexadId)
}

// Find stores that have a specific modality
let findStoresByModality = (
  registry: registryState,
  modality: modalityType,
): array<storeLocation> => {
  registry.stores
  ->Js.Dict.values
  ->Belt.Array.keep(store => {
    store.modalities->Belt.Array.some(m => m == modality)
  })
}

// Select best store for a modality based on trust and response time
let selectBestStore = (
  registry: registryState,
  modality: modalityType,
): option<storeLocation> => {
  let candidates = findStoresByModality(registry, modality)

  if Belt.Array.length(candidates) == 0 {
    None
  } else {
    // Score stores by trust level and response time
    let scored = candidates->Belt.Array.map(store => {
      let trustScore = store.trustLevel
      let responseScore = switch store.responseTimeMs {
      | None => 0.5
      | Some(ms) => 1.0 -. (Belt.Int.toFloat(ms) /. 1000.0)->Js.Math.min_float(1.0)
      }
      let score = trustScore *. 0.7 +. responseScore *. 0.3
      (store, score)
    })

    // Sort by score descending
    let sorted = scored->Belt.Array.reverse->Belt.SortArray.stableSortBy(((_, scoreA), (_, scoreB)) => {
      Belt.Float.toInt((scoreB -. scoreA) *. 1000.0)
    })

    sorted->Belt.Array.get(0)->Belt.Option.map(((store, _)) => store)
  }
}

// Update store health metrics
let updateStoreHealth = (
  registry: registryState,
  storeId: storeId,
  responseTimeMs: int,
  success: bool,
): registryState => {
  switch Js.Dict.get(registry.stores, storeId) {
  | None => registry
  | Some(store) => {
      let newTrust = if success {
        Js.Math.min_float(store.trustLevel +. 0.05, 1.0)
      } else {
        Js.Math.max_float(store.trustLevel -. 0.1, 0.0)
      }

      let updatedStore = {
        ...store,
        trustLevel: newTrust,
        lastSeen: Js.Date.make(),
        responseTimeMs: Some(responseTimeMs),
      }

      let newStores = Js.Dict.fromArray(Js.Dict.entries(registry.stores))
      Js.Dict.set(newStores, storeId, updatedStore)

      {...registry, stores: newStores}
    }
  }
}

// Remove stores that haven't been seen recently
let pruneDeadStores = (registry: registryState): registryState => {
  let now = Js.Date.now()
  let maxDowntime = Belt.Int.toFloat(registry.config.maxStoreDowntimeMs)

  let liveStores = registry.stores
    ->Js.Dict.entries
    ->Belt.Array.keep(((_, store)) => {
      let timeSinceLastSeen = now -. Js.Date.getTime(store.lastSeen)
      timeSinceLastSeen < maxDowntime
    })
    ->Js.Dict.fromArray

  {...registry, stores: liveStores}
}

// ============================================================================
// Federation Queries
// ============================================================================

type federationQuery = {
  pattern: string, // e.g., "/universities/*"
  modalities: array<modalityType>,
  limit: int,
}

type queryResult = {
  storeId: storeId,
  hexadId: hexadId,
  modality: modalityType,
  data: Js.Json.t,
}

// Resolve a federation pattern to list of stores
let resolvePattern = (
  registry: registryState,
  pattern: string,
): array<storeLocation> => {
  // Simple pattern matching - in production would use regex
  if Js.String2.endsWith(pattern, "/*") {
    let prefix = Js.String2.slice(pattern, ~from=0, ~to_=Js.String2.length(pattern) - 2)

    registry.stores
    ->Js.Dict.values
    ->Belt.Array.keep(store => {
      Js.String2.startsWith(store.storeId, prefix)
    })
  } else {
    // Exact match
    switch Js.Dict.get(registry.stores, pattern) {
    | None => []
    | Some(store) => [store]
    }
  }
}

// Execute a federated query across multiple stores via HTTP fan-out
let executeFederatedQuery = async (
  registry: registryState,
  query: federationQuery,
): Promise.t<array<queryResult>> => {
  let stores = resolvePattern(registry, query.pattern)

  // Filter stores by required modalities and minimum trust level
  let eligibleStores = stores->Belt.Array.keep(store => {
    store.trustLevel >= registry.config.minTrustLevel &&
    query.modalities->Belt.Array.every(modality => {
      store.modalities->Belt.Array.some(m => m == modality)
    })
  })

  // Fan out HTTP requests to each eligible store
  let fetchPromises = eligibleStores->Belt.Array.map(store => {
    let url = store.endpoint ++ "/hexads?limit=" ++ Belt.Int.toString(query.limit)
    Fetch.fetch(url, {method: #GET})
    ->Promise.then(response => {
      if Fetch.Response.ok(response) {
        Fetch.Response.json(response)
        ->Promise.then(json => {
          // Map response items to queryResult
          let items = switch Js.Json.classify(json) {
          | Js.Json.JSONArray(arr) =>
            arr->Belt.Array.flatMap(item => {
              query.modalities->Belt.Array.map(modality => {
                {
                  storeId: store.storeId,
                  hexadId: switch Js.Json.classify(item) {
                  | Js.Json.JSONObject(obj) =>
                    switch Js.Dict.get(obj, "id") {
                    | Some(id) =>
                      switch Js.Json.classify(id) {
                      | Js.Json.JSONString(s) => s
                      | _ => "unknown"
                      }
                    | None => "unknown"
                    }
                  | _ => "unknown"
                  },
                  modality: modality,
                  data: item,
                }
              })
            })
          | _ => []
          }
          Promise.resolve(items)
        })
      } else {
        Promise.resolve([])
      }
    })
    ->Promise.catch(_err => {
      Promise.resolve([])
    })
  })

  // Collect results from all stores
  let allResults = await Promise.all(fetchPromises)
  let combined = allResults->Belt.Array.flatMap(r => r)

  // Apply limit
  let limited = combined->Belt.Array.slice(~offset=0, ~len=query.limit)
  limited
}

// ============================================================================
// Consistency & Replication
// ============================================================================

type replicationStatus =
  | UpToDate
  | Stale({lagMs: int})
  | Diverged({conflictCount: int})

let checkReplicationStatus = (
  registry: registryState,
  hexadId: hexadId,
): replicationStatus => {
  // Check if hexad replicas are consistent by examining mapping and store health
  switch Js.Dict.get(registry.mappings, hexadId) {
  | None => UpToDate // No mapping = nothing to replicate
  | Some(mapping) => {
      let locationEntries = Js.Dict.values(mapping.locations)
      let storeCount = Belt.Array.length(locationEntries)

      if storeCount <= 1 {
        UpToDate
      } else {
        // Check how many stores are alive and responsive
        let aliveCount = locationEntries->Belt.Array.keep(loc => {
          switch Js.Dict.get(registry.stores, loc.storeId) {
          | None => false
          | Some(store) => {
              let now = Js.Date.now()
              let age = now -. Js.Date.getTime(store.lastSeen)
              age < Belt.Int.toFloat(registry.config.maxStoreDowntimeMs)
            }
          }
        })->Belt.Array.length

        if aliveCount < storeCount {
          let lagMs = storeCount - aliveCount
          Stale({lagMs: lagMs * 1000})
        } else {
          // All stores alive — check for trust divergence as proxy for data divergence
          let trusts = locationEntries->Belt.Array.map(loc => {
            switch Js.Dict.get(registry.stores, loc.storeId) {
            | None => 0.0
            | Some(store) => store.trustLevel
            }
          })
          let minTrust = trusts->Belt.Array.reduce(1.0, (a, b) => Js.Math.min_float(a, b))
          let maxTrust = trusts->Belt.Array.reduce(0.0, (a, b) => Js.Math.max_float(a, b))

          if maxTrust -. minTrust > 0.3 {
            Diverged({conflictCount: 1})
          } else {
            UpToDate
          }
        }
      }
    }
  }
}

// Trigger replication for a hexad: fetch from source, push to targets
let replicateHexad = async (
  registry: registryState,
  hexadId: hexadId,
  sourceStore: storeId,
  targetStores: array<storeId>,
): Promise.t<Result.t<unit, string>> => {
  // Look up source store endpoint
  let sourceEndpoint = switch Js.Dict.get(registry.stores, sourceStore) {
  | None => None
  | Some(store) => Some(store.endpoint)
  }

  switch sourceEndpoint {
  | None => Error("Source store '" ++ sourceStore ++ "' not found in registry")
  | Some(endpoint) => {
      // Fetch hexad from source
      let fetchUrl = endpoint ++ "/hexads/" ++ hexadId
      let fetchResult = try {
        let response = await Fetch.fetch(fetchUrl, {method: #GET})
        if Fetch.Response.ok(response) {
          let json = await Fetch.Response.json(response)
          Ok(json)
        } else {
          Error("Source store returned " ++ Belt.Int.toString(Fetch.Response.status(response)))
        }
      } catch {
      | exn => Error("Failed to fetch from source: " ++ Js.Exn.message(Obj.magic(exn))->Belt.Option.getWithDefault("unknown"))
      }

      switch fetchResult {
      | Error(msg) => Error(msg)
      | Ok(hexadData) => {
          // Push to each target store
          let errors = ref([])

          let pushPromises = targetStores->Belt.Array.map(targetId => {
            switch Js.Dict.get(registry.stores, targetId) {
            | None => {
                errors := Belt.Array.concat(errors.contents, ["Target '" ++ targetId ++ "' not found"])
                Promise.resolve()
              }
            | Some(target) => {
                let pushUrl = target.endpoint ++ "/hexads/" ++ hexadId
                Fetch.fetch(pushUrl, {
                  method: #PUT,
                  body: Fetch.BodyInit.make(Js.Json.stringify(hexadData)),
                  headers: Fetch.HeadersInit.make({"Content-Type": "application/json"}),
                })
                ->Promise.then(resp => {
                  if !Fetch.Response.ok(resp) {
                    errors := Belt.Array.concat(errors.contents, [
                      "Push to '" ++ targetId ++ "' failed: " ++ Belt.Int.toString(Fetch.Response.status(resp))
                    ])
                  }
                  Promise.resolve()
                })
                ->Promise.catch(_err => {
                  errors := Belt.Array.concat(errors.contents, ["Push to '" ++ targetId ++ "' failed: network error"])
                  Promise.resolve()
                })
              }
            }
          })

          let _ = await Promise.all(pushPromises)

          if Belt.Array.length(errors.contents) > 0 {
            Error(Belt.Array.joinWith(errors.contents, "; "))
          } else {
            Ok()
          }
        }
      }
    }
  }
}

// ============================================================================
// Trust & Byzantine Fault Tolerance
// ============================================================================

type consensusResult<'a> = {
  value: 'a,
  agreement: float, // 0.0-1.0
  participants: array<storeId>,
}

// Achieve consensus across stores using quorum voting
let achieveConsensus = async (
  registry: registryState,
  stores: array<storeId>,
  getValue: storeId => Promise.t<option<'a>>,
): Promise.t<option<consensusResult<'a>>> => {
  // Fetch values from all stores concurrently
  let fetchPromises = stores->Belt.Array.map(id => {
    getValue(id)->Promise.then(result => Promise.resolve((id, result)))
  })

  let results = await Promise.all(fetchPromises)

  // Filter to stores that returned values
  let successful = results->Belt.Array.keepMap(((id, result)) => {
    switch result {
    | Some(val) => Some((id, val))
    | None => None
    }
  })

  let totalResponders = Belt.Array.length(successful)
  if totalResponders == 0 {
    None
  } else {
    // Determine quorum threshold based on consistency mode
    let quorumThreshold = switch registry.config.consistencyMode {
    | Strong => Belt.Array.length(stores) // All must agree
    | Quorum => Belt.Array.length(stores) / 2 + 1 // Majority
    | Eventual => 1 // Any response suffices
    }

    if totalResponders >= quorumThreshold {
      // Return the first value (in a full implementation, would compare values
      // and select the one with the most votes)
      let (_, firstValue) = successful->Belt.Array.getExn(0)
      let participants = successful->Belt.Array.map(((id, _)) => id)
      let agreement = Belt.Int.toFloat(totalResponders) /. Belt.Int.toFloat(Belt.Array.length(stores))

      Some({
        value: firstValue,
        agreement: agreement,
        participants: participants,
      })
    } else {
      None // Quorum not met
    }
  }
}

// Detect Byzantine faults by identifying stores with anomalous trust levels
// (proxy for divergent data — a full implementation would compare actual responses)
let detectByzantineFaults = (
  registry: registryState,
  hexadId: hexadId,
): array<storeId> => {
  switch Js.Dict.get(registry.mappings, hexadId) {
  | None => []
  | Some(mapping) => {
      let locations = Js.Dict.values(mapping.locations)
      let storeCount = Belt.Array.length(locations)

      if storeCount < 2 {
        [] // Need at least 2 stores to detect divergence
      } else {
        // Compute median trust level
        let trusts = locations->Belt.Array.map(loc => {
          switch Js.Dict.get(registry.stores, loc.storeId) {
          | None => 0.0
          | Some(store) => store.trustLevel
          }
        })
        let sorted = trusts->Belt.SortArray.stableSortBy((a, b) => Belt.Float.toInt((a -. b) *. 1000.0))
        let median = switch Belt.Array.get(sorted, storeCount / 2) {
        | Some(m) => m
        | None => 0.5
        }

        // Flag stores that deviate significantly from the median (> 0.3 difference)
        locations->Belt.Array.keepMap(loc => {
          let trust = switch Js.Dict.get(registry.stores, loc.storeId) {
          | None => 0.0
          | Some(store) => store.trustLevel
          }
          if Js.Math.abs_float(trust -. median) > 0.3 {
            Some(loc.storeId)
          } else {
            None
          }
        })
      }
    }
  }
}

// ============================================================================
// Serialization
// ============================================================================

let modalityToString = (m: modalityType): string => {
  switch m {
  | Graph => "graph"
  | Vector => "vector"
  | Tensor => "tensor"
  | Semantic => "semantic"
  | Document => "document"
  | Temporal => "temporal"
  | Provenance => "provenance"
  | Spatial => "spatial"
  }
}

let modalityFromString = (s: string): option<modalityType> => {
  switch s {
  | "graph" => Some(Graph)
  | "vector" => Some(Vector)
  | "tensor" => Some(Tensor)
  | "semantic" => Some(Semantic)
  | "document" => Some(Document)
  | "temporal" => Some(Temporal)
  | "provenance" => Some(Provenance)
  | "spatial" => Some(Spatial)
  | _ => None
  }
}

let serializeStoreLocation = (store: storeLocation): Js.Json.t => {
  Js.Dict.fromArray([
    ("storeId", Js.Json.string(store.storeId)),
    ("endpoint", Js.Json.string(store.endpoint)),
    ("modalities", Js.Json.array(store.modalities->Belt.Array.map(m => Js.Json.string(modalityToString(m))))),
    ("trustLevel", Js.Json.number(store.trustLevel)),
    ("lastSeen", Js.Json.string(Js.Date.toISOString(store.lastSeen))),
    ("responseTimeMs", switch store.responseTimeMs {
    | None => Js.Json.null
    | Some(ms) => Js.Json.number(Belt.Int.toFloat(ms))
    }),
  ])->Js.Json.object_
}

let serializeRegistry = (registry: registryState): Js.Json.t => {
  // Serialize stores
  let storesJson = Js.Dict.empty()
  registry.stores->Js.Dict.entries->Belt.Array.forEach(((id, store)) => {
    Js.Dict.set(storesJson, id, serializeStoreLocation(store))
  })

  // Serialize mappings
  let mappingsJson = Js.Dict.empty()
  registry.mappings->Js.Dict.entries->Belt.Array.forEach(((id, mapping)) => {
    let locsJson = Js.Dict.empty()
    mapping.locations->Js.Dict.entries->Belt.Array.forEach(((key, loc)) => {
      Js.Dict.set(locsJson, key, serializeStoreLocation(loc))
    })
    Js.Dict.set(mappingsJson, id, Js.Dict.fromArray([
      ("hexadId", Js.Json.string(mapping.hexadId)),
      ("locations", Js.Json.object_(locsJson)),
      ("primaryStore", switch mapping.primaryStore {
      | None => Js.Json.null
      | Some(s) => Js.Json.string(s)
      }),
      ("created", Js.Json.string(Js.Date.toISOString(mapping.created))),
      ("modified", Js.Json.string(Js.Date.toISOString(mapping.modified))),
    ])->Js.Json.object_)
  })

  // Serialize config
  let configJson = Js.Dict.fromArray([
    ("minTrustLevel", Js.Json.number(registry.config.minTrustLevel)),
    ("maxStoreDowntimeMs", Js.Json.number(Belt.Int.toFloat(registry.config.maxStoreDowntimeMs))),
    ("replicationFactor", Js.Json.number(Belt.Int.toFloat(registry.config.replicationFactor))),
    ("consistencyMode", Js.Json.string(switch registry.config.consistencyMode {
    | Strong => "strong"
    | Eventual => "eventual"
    | Quorum => "quorum"
    })),
  ])->Js.Json.object_

  Js.Dict.fromArray([
    ("stores", Js.Json.object_(storesJson)),
    ("mappings", Js.Json.object_(mappingsJson)),
    ("config", configJson),
  ])->Js.Json.object_
}

let deserializeStoreLocation = (json: Js.Json.t): option<storeLocation> => {
  switch Js.Json.classify(json) {
  | Js.Json.JSONObject(obj) => {
      let getString = key => switch Js.Dict.get(obj, key) {
      | Some(v) => switch Js.Json.classify(v) {
        | Js.Json.JSONString(s) => Some(s)
        | _ => None
        }
      | None => None
      }
      let getFloat = key => switch Js.Dict.get(obj, key) {
      | Some(v) => switch Js.Json.classify(v) {
        | Js.Json.JSONNumber(n) => Some(n)
        | _ => None
        }
      | None => None
      }

      switch (getString("storeId"), getString("endpoint")) {
      | (Some(sid), Some(ep)) => {
          let modalities = switch Js.Dict.get(obj, "modalities") {
          | Some(arr) => switch Js.Json.classify(arr) {
            | Js.Json.JSONArray(items) =>
              items->Belt.Array.keepMap(item => {
                switch Js.Json.classify(item) {
                | Js.Json.JSONString(s) => modalityFromString(s)
                | _ => None
                }
              })
            | _ => []
            }
          | None => []
          }

          let responseTimeMs = switch getFloat("responseTimeMs") {
          | Some(n) => Some(Belt.Float.toInt(n))
          | None => None
          }

          Some({
            storeId: sid,
            endpoint: ep,
            modalities: modalities,
            trustLevel: getFloat("trustLevel")->Belt.Option.getWithDefault(1.0),
            lastSeen: switch getString("lastSeen") {
            | Some(s) => Js.Date.fromString(s)
            | None => Js.Date.make()
            },
            responseTimeMs: responseTimeMs,
          })
        }
      | _ => None
      }
    }
  | _ => None
  }
}

let deserializeRegistry = (json: Js.Json.t): option<registryState> => {
  switch Js.Json.classify(json) {
  | Js.Json.JSONObject(root) => {
      // Deserialize config
      let config = switch Js.Dict.get(root, "config") {
      | Some(configJson) => switch Js.Json.classify(configJson) {
        | Js.Json.JSONObject(obj) => {
            let getFloat = key => switch Js.Dict.get(obj, key) {
            | Some(v) => switch Js.Json.classify(v) {
              | Js.Json.JSONNumber(n) => Some(n)
              | _ => None
              }
            | None => None
            }
            let getString = key => switch Js.Dict.get(obj, key) {
            | Some(v) => switch Js.Json.classify(v) {
              | Js.Json.JSONString(s) => Some(s)
              | _ => None
              }
            | None => None
            }

            {
              minTrustLevel: getFloat("minTrustLevel")->Belt.Option.getWithDefault(0.5),
              maxStoreDowntimeMs: getFloat("maxStoreDowntimeMs")
                ->Belt.Option.map(Belt.Float.toInt)
                ->Belt.Option.getWithDefault(300_000),
              replicationFactor: getFloat("replicationFactor")
                ->Belt.Option.map(Belt.Float.toInt)
                ->Belt.Option.getWithDefault(3),
              consistencyMode: switch getString("consistencyMode") {
              | Some("strong") => Strong
              | Some("eventual") => Eventual
              | _ => Quorum
              },
            }
          }
        | _ => defaultConfig()
        }
      | None => defaultConfig()
      }

      // Deserialize stores
      let stores = Js.Dict.empty()
      switch Js.Dict.get(root, "stores") {
      | Some(storesJson) => switch Js.Json.classify(storesJson) {
        | Js.Json.JSONObject(storesObj) =>
          storesObj->Js.Dict.entries->Belt.Array.forEach(((id, storeJson)) => {
            switch deserializeStoreLocation(storeJson) {
            | Some(store) => Js.Dict.set(stores, id, store)
            | None => ()
            }
          })
        | _ => ()
        }
      | None => ()
      }

      // Deserialize mappings
      let mappings = Js.Dict.empty()
      switch Js.Dict.get(root, "mappings") {
      | Some(mappingsJson) => switch Js.Json.classify(mappingsJson) {
        | Js.Json.JSONObject(mappingsObj) =>
          mappingsObj->Js.Dict.entries->Belt.Array.forEach(((id, mapJson)) => {
            switch Js.Json.classify(mapJson) {
            | Js.Json.JSONObject(mapObj) => {
                let getString = key => switch Js.Dict.get(mapObj, key) {
                | Some(v) => switch Js.Json.classify(v) {
                  | Js.Json.JSONString(s) => Some(s)
                  | _ => None
                  }
                | None => None
                }

                let locations = Js.Dict.empty()
                switch Js.Dict.get(mapObj, "locations") {
                | Some(locsJson) => switch Js.Json.classify(locsJson) {
                  | Js.Json.JSONObject(locsObj) =>
                    locsObj->Js.Dict.entries->Belt.Array.forEach(((key, locJson)) => {
                      switch deserializeStoreLocation(locJson) {
                      | Some(loc) => Js.Dict.set(locations, key, loc)
                      | None => ()
                      }
                    })
                  | _ => ()
                  }
                | None => ()
                }

                let primaryStore = switch Js.Dict.get(mapObj, "primaryStore") {
                | Some(v) => switch Js.Json.classify(v) {
                  | Js.Json.JSONString(s) => Some(s)
                  | Js.Json.JSONNull => None
                  | _ => None
                  }
                | None => None
                }

                Js.Dict.set(mappings, id, {
                  hexadId: getString("hexadId")->Belt.Option.getWithDefault(id),
                  locations: locations,
                  primaryStore: primaryStore,
                  created: switch getString("created") {
                  | Some(s) => Js.Date.fromString(s)
                  | None => Js.Date.make()
                  },
                  modified: switch getString("modified") {
                  | Some(s) => Js.Date.fromString(s)
                  | None => Js.Date.make()
                  },
                })
              }
            | _ => ()
            }
          })
        | _ => ()
        }
      | None => ()
      }

      Some({
        mappings: mappings,
        stores: stores,
        config: config,
      })
    }
  | _ => None
  }
}

// ============================================================================
// Public API
// ============================================================================

let create = createRegistry
let register = registerStore
let map = mapHexad
let lookup = getHexadLocations
let selectStore = selectBestStore
let updateHealth = updateStoreHealth
let prune = pruneDeadStores
let query = executeFederatedQuery
let replicate = replicateHexad
let consensus = achieveConsensus
